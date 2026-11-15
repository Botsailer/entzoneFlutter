import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'store.dart';

/// MovieBox H5 web API client.
///
/// Ported from the React Native app's `lib/api.ts`, which was debugged against
/// the live service. The awkward parts are load-bearing — do not "simplify" them:
///
///  • The anonymous token arrives in the `x-user` *response header* of `/home`,
///    but only when the request carries no `token` cookie. Native HTTP stacks
///    keep the `set-cookie` from the first visit and replay it, after which the
///    server stops sending `x-user` — and it only accepts the token as a Bearer
///    header, never as a cookie. So: ask with cookies off; if no token comes
///    back, clear the jar and ask once more.
///  • Any 4xx means a stale token (the API answers with 400, 401 *or* 403).
///    Drop it, re-issue, retry once.
///  • Playback is a two-step dance through a rotating player domain, and the
///    constructed page `Referer` is what the play endpoint actually checks.
///  • The `referer` that comes back must ride on every media request or the CDN
///    answers 429. That is why PlayResult carries it.
class Api {
  Api._();
  static final Api i = Api._();

  static const _base = 'https://h5-api.aoneroom.com/wefeed-h5api-bff';
  static const _host = 'movie-box.co';
  static const _tokenKey = 'api:token';
  static const _timeout = Duration(seconds: 15);
  static const _tokenTtl = Duration(minutes: 10);

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _base,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
      responseType: ResponseType.plain,
      validateStatus: (_) => true, // we read the body on every status
      headers: {'Accept': 'application/json'},
    ),
  );

  /// A bare client for the player domain and media probes — different origin,
  /// and it must never carry the catalog's Authorization header.
  late final Dio _plain = Dio(
    BaseOptions(
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );

  String? _token;
  int _tokenAt = 0;
  bool _tokenLoaded = false;
  Future<void>? _tokenInflight;

  /// Headers the MovieBox web client sends with every call.
  Map<String, String> get _clientHeaders => {
    'X-Request-Lang': 'en',
    'X-Client-Info': jsonEncode({'timezone': _timezone}),
  };

  String get _timezone {
    try {
      final offset = DateTime.now().timeZoneOffset;
      // The server only reads this loosely; the real zone name is unavailable
      // in Dart without a plugin, and the catalog's own client sends a guess.
      return offset.inMinutes == 330 ? 'Asia/Calcutta' : 'Etc/GMT';
    } catch (_) {
      return 'Asia/Calcutta';
    }
  }

  // ───────────────────────── token ─────────────────────────

  Future<void> _loadToken() async {
    if (_tokenLoaded) return;
    _tokenLoaded = true;
    final raw = await Store.i.getString(_tokenKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['token'] is String) {
        _token = j['token'] as String;
        _tokenAt = (j['at'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  void _captureToken(Response res) {
    final xUser = res.headers.value('x-user');
    if (xUser == null) return;
    try {
      final parsed = jsonDecode(xUser);
      if (parsed is Map && parsed['token'] is String) {
        _token = parsed['token'] as String;
        _tokenAt = DateTime.now().millisecondsSinceEpoch;
        Store.i.setString(
          _tokenKey,
          jsonEncode({'token': _token, 'at': _tokenAt}),
        );
      }
    } catch (_) {}
  }

  /// Drop whatever cookies the stack is holding for the API origin. Without
  /// this the server stops issuing `x-user` after the first ever request.
  Future<void> _clearCookies() async {
    try {
      _dio.options.headers.remove('Cookie');
      // Dio on native keeps no jar unless one is installed, and we install
      // none — so there is nothing to purge beyond an explicit header. On web
      // the browser owns the jar and `withCredentials: false` keeps it out.
    } catch (_) {}
  }

  Future<void> _fetchToken() async {
    try {
      await _raw<Map<String, Object?>>('/home?host=$_host', auth: false);
    } catch (_) {}
    if (_token != null) return;
    await _clearCookies();
    await _raw<Map<String, Object?>>('/home?host=$_host', auth: false);
    if (_token == null) {
      throw ApiError('Could not reach the catalog. Check your connection.');
    }
  }

  Future<void> _ensureToken() async {
    await _loadToken();
    final fresh =
        _token != null &&
        DateTime.now().millisecondsSinceEpoch - _tokenAt <
            _tokenTtl.inMilliseconds;
    if (fresh) return;
    _token = null;
    _tokenInflight ??= _fetchToken().whenComplete(() => _tokenInflight = null);
    await _tokenInflight;
  }

  // ───────────────────────── http ─────────────────────────

  Future<T> _raw<T>(String path, {Object? body, bool auth = true}) async {
    late Response res;
    try {
      res = await _dio.request(
        path,
        data: body == null ? null : jsonEncode(body),
        options: Options(
          method: body == null ? 'GET' : 'POST',
          headers: {
            ..._clientHeaders,
            if (body != null) 'Content-Type': 'application/json',
            if (auth && _token != null) 'Authorization': 'Bearer $_token',
          },
          extra: {'withCredentials': false},
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw ApiError('The catalog took too long to answer.');
      }
      throw ApiError('Could not reach the catalog. Check your connection.');
    }

    _captureToken(res);

    final text = res.data is String ? res.data as String : '';
    Map<String, Object?>? json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) json = decoded;
    } catch (_) {}

    final ok =
        res.statusCode != null &&
        res.statusCode! >= 200 &&
        res.statusCode! < 300;
    final code = json?['code'];

    if (!ok || json == null || code != 0) {
      final reason = (json?['message'] ?? json?['msg'] ?? '').toString();
      final detail = reason.isNotEmpty
          ? reason
          : (text.isEmpty
                ? 'empty response'
                : text.substring(0, text.length.clamp(0, 120)));
      if (kDebugMode) {
        debugPrint(
          '[api] ${body == null ? 'GET' : 'POST'} $path -> '
          'HTTP ${res.statusCode} code=$code  $detail',
        );
      }
      throw ApiError(
        ok ? detail : 'The catalog returned an error (${res.statusCode}).',
        ok ? (code is int ? code : null) : res.statusCode,
      );
    }
    return json['data'] as T;
  }

  Future<T> _request<T>(String path, {Object? body}) async {
    await _ensureToken();
    try {
      return await _raw<T>(path, body: body);
    } on ApiError catch (e) {
      final s = e.status;
      // Any 4xx: the token is stale. Re-issue and retry exactly once.
      if (s != null && s >= 400 && s < 500) {
        _token = null;
        await Store.i.remove(_tokenKey);
        await _ensureToken();
      }
      return _raw<T>(path, body: body);
    }
  }

  // ───────────────────────── cache ─────────────────────────

  final _memory = <String, ({int at, Object? data})>{};

  Future<({int at, Object? data})?> _readCache(String key) async {
    final hit = _memory[key];
    if (hit != null) return hit;
    final raw = await Store.i.getString('api:cache:$key');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final entry = (at: (j['at'] as num).toInt(), data: j['data']);
      _memory[key] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }

  void _writeCache(String key, Object? data, bool persist) {
    final entry = (at: DateTime.now().millisecondsSinceEpoch, data: data);
    _memory[key] = entry;
    if (_memory.length > 220) {
      // Bounded: drop the oldest third rather than growing without limit.
      final keys = _memory.keys.take(70).toList();
      for (final k in keys) {
        _memory.remove(k);
      }
    }
    if (persist) {
      Store.i.setString(
        'api:cache:$key',
        jsonEncode({'at': entry.at, 'data': data}),
      );
    }
  }

  /// Fetch with cache. Returns the cached value when it is younger than
  /// [maxAge]; falls back to a stale value when the network fails, so the app
  /// opens and keeps working offline.
  Future<T> _cached<T>(
    String key,
    Future<Object?> Function() fetch,
    T Function(Object?) parse,
    Duration maxAge, {
    bool persist = false,
  }) async {
    final hit = await _readCache(key);
    final age = hit == null
        ? null
        : DateTime.now().millisecondsSinceEpoch - hit.at;
    if (hit != null && age! < maxAge.inMilliseconds) return parse(hit.data);
    try {
      final data = await fetch();
      _writeCache(key, data, persist);
      return parse(data);
    } catch (e) {
      if (hit != null) return parse(hit.data); // offline → serve stale
      rethrow;
    }
  }

  // ───────────────────────── catalog ─────────────────────────

  Future<Feed> home({bool force = false}) => _cached(
    'home',
    () => _request<Object?>('/home?host=$_host'),
    Feed.from,
    force ? Duration.zero : const Duration(minutes: 10),
    persist: true,
  );

  /// Operating feed for a tab (tabId 2 = Movie).
  Future<Feed> tab(int tabId, {bool force = false}) => _cached(
    'tab:$tabId',
    () => _request<Object?>('/tab-operating?tabId=$tabId&host=$_host'),
    Feed.from,
    force ? Duration.zero : const Duration(minutes: 10),
    persist: true,
  );

  Future<List<Subject>> trending({int page = 1, int perPage = 24}) => _cached(
    'trending:$page:$perPage',
    () => _request<Object?>('/subject/trending?page=$page&perPage=$perPage'),
    (d) => safeSubjects(
      ((d as Map?)?['subjectList'] as List? ?? const []).map(Subject.from),
    ),
    const Duration(minutes: 10),
    persist: page == 1,
  );

  Future<PagedSubjects> filter(FilterQuery q) => _cached(
    'filter:${q.cacheKey}',
    () => _request<Object?>('/subject/filter', body: q.toBody()),
    PagedSubjects.from,
    const Duration(minutes: 10),
    persist: q.page == 1,
  );

  Future<PagedSubjects> search(
    String keyword, {
    int page = 1,
    int perPage = 24,
    int subjectType = 0,
  }) async {
    final data = await _request<Object?>(
      '/subject/search',
      body: {
        'keyword': keyword,
        'page': page,
        'perPage': perPage,
        'subjectType': subjectType,
      },
    );
    return PagedSubjects.from(data);
  }

  Future<SearchHome> searchHome() => _cached(
    'everyone-search',
    () => _request<Object?>('/subject/everyone-search'),
    SearchHome.from,
    const Duration(minutes: 30),
    persist: true,
  );

  Future<List<String>> suggest(String keyword, {int perPage = 8}) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      final data = await _request<Object?>(
        '/subject/search-suggest',
        body: {'keyword': keyword, 'perPage': perPage},
      );
      return ((data as Map?)?['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => (e['word'] ?? '').toString())
          .where((w) => w.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<DetailData> detail(String detailPath) => _cached(
    'detail:$detailPath',
    () => _request<Object?>(
      '/detail?detailPath=${Uri.encodeComponent(detailPath)}',
    ),
    (d) {
      final parsed = DetailData.from(d);
      if (parsed == null) {
        throw ApiError('This title is no longer in the catalog.');
      }
      return parsed;
    },
    const Duration(minutes: 30),
    persist: true,
  );

  Future<List<Subject>> related(
    String subjectId, {
    int page = 1,
    int perPage = 12,
  }) => _cached(
    'rec:$subjectId:$page',
    () => _request<Object?>(
      '/subject/detail-rec?subjectId=$subjectId&page=$page&perPage=$perPage',
    ),
    (d) => safeSubjects(
      ((d as Map?)?['items'] as List? ?? const []).map(Subject.from),
    ),
    const Duration(minutes: 30),
  );

  // ───────────────────────── playback ─────────────────────────

  /// The current player origin. MovieBox rotates this; it is cached for a few
  /// minutes and the call itself needs the bearer token.
  Future<String> playerBase() => _cached(
    'playerBase',
    () => _request<Object?>('/media-player/get-domain'),
    (d) {
      final raw = d?.toString() ?? '';
      final u = Uri.tryParse(raw);
      if (u == null ||
          u.scheme != 'https' ||
          !RegExp(r'^[a-z0-9.-]+$', caseSensitive: false).hasMatch(u.host)) {
        throw ApiError('The player domain looks wrong; try again shortly.');
      }
      return u.origin;
    },
    const Duration(minutes: 10),
  );

  final _playCache = <String, ({int at, PlayResult value})>{};
  static const _playTtl = Duration(seconds: 90);

  /// Resolve playable MP4 renditions for a movie (se = ep = 0) or an episode.
  ///
  /// Mirrors the web player exactly: get-domain (authenticated) → the play call
  /// on that domain with a constructed page Referer (unauthenticated; the
  /// Referer is what the endpoint checks). vip-locked and non-MP4 renditions
  /// are dropped because they will not play.
  Future<PlayResult> play(
    String subjectId,
    String detailPath, {
    int se = 0,
    int ep = 0,
    bool forceRefresh = false,
  }) async {
    final key = '$subjectId:$se:$ep';
    final hit = _playCache[key];
    if (!forceRefresh &&
        hit != null &&
        DateTime.now().millisecondsSinceEpoch - hit.at <
            _playTtl.inMilliseconds) {
      return hit.value;
    }

    await _ensureToken();
    final base = await playerBase();

    final referer =
        '$base/spa/videoPlayPage/movies/${Uri.encodeComponent(detailPath)}?'
        '${Uri(queryParameters: {'id': subjectId, 'type': '/movie/detail', 'detailSe': '$se', 'detailEp': '$ep', 'lang': 'en'}).query}';

    final url =
        '$base/wefeed-h5api-bff/subject/play?'
        '${Uri(queryParameters: {'subjectId': subjectId, 'se': '$se', 'ep': '$ep', 'detailPath': detailPath}).query}';

    Response res;
    try {
      res = await _plain.get(
        url,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Referer': referer,
            ..._clientHeaders,
          },
          extra: {'withCredentials': false},
        ),
      );
    } on DioException {
      throw ApiError('Could not reach the player service.');
    }

    Map<String, Object?>? j;
    try {
      final decoded = jsonDecode(
        res.data is String ? res.data as String : '{}',
      );
      if (decoded is Map<String, Object?>) j = decoded;
    } catch (_) {}

    if (j == null || j['code'] != 0) {
      throw ApiError(
        (j?['message'] ?? 'Playback is unavailable for this title right now.')
            .toString(),
      );
    }

    final d = (j['data'] as Map?) ?? const {};
    final streams =
        ((d['streams'] as List?) ?? const [])
            .whereType<Map>()
            .where(
              (s) =>
                  (s['url']?.toString().isNotEmpty ?? false) &&
                  s['vipLocked'] != true &&
                  s['format'] == 'MP4',
            )
            .map(
              (s) => PlayStream(
                url: s['url'].toString(),
                resolution: s['resolutions']?.toString() ?? '',
                height: int.tryParse(s['resolutions']?.toString() ?? '') ?? 0,
                duration:
                    num.tryParse(s['duration']?.toString() ?? '')?.toInt() ?? 0,
                codec: s['codecName']?.toString() ?? '',
                size: num.tryParse(s['size']?.toString() ?? '')?.toInt(),
              ),
            )
            .toList()
          ..sort((a, b) => b.height.compareTo(a.height));

    final value = PlayResult(
      streams: streams,
      referer: referer,
      hasResource: d['hasResource'] == true,
      limited: d['limited'] == true,
      vipLocked: d['vipLocked'] == true,
    );

    if (_playCache.length > 64) _playCache.clear();
    _playCache[key] = (at: DateTime.now().millisecondsSinceEpoch, value: value);
    return value;
  }

  /// Drop every cached response. The session token survives.
  Future<void> clearCache() async {
    _memory.clear();
    _playCache.clear();
    await Store.i.removeWhere((k) => k.startsWith('api:cache:'));
  }

  /// Approximate size of the on-disk response cache, for the settings screen.
  Future<int> cacheBytes() =>
      Store.i.bytesWhere((k) => k.startsWith('api:cache:'));
}
