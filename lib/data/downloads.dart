import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/device.dart';
import 'api.dart';
import 'models.dart';
import 'native.dart';
import 'progress.dart';
import 'settings.dart';
import 'store.dart';

enum DownloadStatus { queued, downloading, paused, done, failed }

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.subject,
    required this.se,
    required this.ep,
    required this.quality,
    required this.height,
    required this.url,
    required this.headers,
    required this.fileName,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = 0,
    this.bytesPerSecond = 0,
    this.error,
    this.addedAt = 0,
  });

  final String id;
  final Subject subject;
  final int se;
  final int ep;
  final String quality;
  final int height;

  /// Re-resolved when a resume finds the old URL expired.
  final String url;
  final Map<String, String> headers;
  final String fileName;

  final DownloadStatus status;
  final int received;
  final int total;
  final double bytesPerSecond;
  final String? error;
  final int addedAt;

  bool get isEpisode => se > 0;
  bool get active =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;
  double get ratio => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  EpisodeRef? get episode => isEpisode ? EpisodeRef(se, ep) : null;

  Duration? get eta {
    if (bytesPerSecond <= 0 || total <= 0 || received >= total) return null;
    return Duration(seconds: ((total - received) / bytesPerSecond).round());
  }

  DownloadItem copyWith({
    DownloadStatus? status,
    int? received,
    int? total,
    double? bytesPerSecond,
    Object? error = _keep,
    String? url,
    Map<String, String>? headers,
  }) => DownloadItem(
    id: id,
    subject: subject,
    se: se,
    ep: ep,
    quality: quality,
    height: height,
    url: url ?? this.url,
    headers: headers ?? this.headers,
    fileName: fileName,
    status: status ?? this.status,
    received: received ?? this.received,
    total: total ?? this.total,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    error: error == _keep ? this.error : error as String?,
    addedAt: addedAt,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject.toJson(),
    'se': se,
    'ep': ep,
    'quality': quality,
    'height': height,
    'url': url,
    'headers': headers,
    'fileName': fileName,
    // A download interrupted by a kill resumes as paused, not as a lie.
    'status':
        (status == DownloadStatus.downloading || status == DownloadStatus.queued
                ? DownloadStatus.paused
                : status)
            .name,
    'received': received,
    'total': total,
    'error': error,
    'addedAt': addedAt,
  };

  static DownloadItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = Subject.from(j['subject']);
    if (s == null) return null;
    return DownloadItem(
      id: j['id'].toString(),
      subject: s,
      se: (j['se'] as num?)?.toInt() ?? 0,
      ep: (j['ep'] as num?)?.toInt() ?? 0,
      quality: j['quality']?.toString() ?? '',
      height: (j['height'] as num?)?.toInt() ?? 0,
      url: j['url']?.toString() ?? '',
      headers: ((j['headers'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      fileName: j['fileName']?.toString() ?? '',
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == j['status'],
        orElse: () => DownloadStatus.paused,
      ),
      received: (j['received'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      error: j['error']?.toString(),
      addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

String downloadId(String subjectId, int se, int ep) => '$subjectId:$se:$ep';

/// A finished file on disk.
class OfflineFile {
  const OfflineFile({
    required this.path,
    required this.quality,
    required this.bytes,
  });
  final String path;
  final String quality;
  final int bytes;
}

/// The download queue.
///
/// One transfer runs at a time, by HTTP range request so pause and resume are
/// real: the partial file stays on disk and the next attempt asks the CDN to
/// continue from the byte it reached. The Referer header rides on every request
/// because the CDN refuses without it — the same rule as playback.
///
/// On Android a native foreground service keeps the process alive and owns the
/// progress notification, so a download survives the app being backgrounded.
/// On desktop and iOS the transfer runs in-process; closing the app pauses it,
/// and it resumes from the same byte next launch.
class Downloads {
  Downloads._();
  static final Downloads i = Downloads._();

  static const _key = 'downloads:v2';

  final _dio = Dio();
  final changes = Signal<List<DownloadItem>>(const []);

  List<DownloadItem> _items = const [];
  Directory? _dir;
  CancelToken? _cancel;
  String? _activeId;
  Completer<void>? _readyCompleter;

  List<DownloadItem> get items => _items;

  Future<void> get ready => _readyCompleter?.future ?? Future.value();

  Future<void> init() async {
    _readyCompleter = Completer<void>();
    try {
      final base = await getApplicationSupportDirectory();
      _dir = Directory('${base.path}${Platform.pathSeparator}media');
      if (!await _dir!.exists()) await _dir!.create(recursive: true);

      _items =
          Store.i.getJson(
            _key,
            (j) => (j as List? ?? const [])
                .map(DownloadItem.fromJson)
                .whereType<DownloadItem>()
                .toList(),
          ) ??
          const [];

      // Reconcile with disk: a file the user deleted outside the app should not
      // still read as downloaded.
      final checked = <DownloadItem>[];
      for (final it in _items) {
        if (it.status == DownloadStatus.done) {
          final f = File(_pathFor(it));
          if (!await f.exists()) {
            checked.add(
              it.copyWith(status: DownloadStatus.failed, error: 'file is gone'),
            );
            continue;
          }
        }
        checked.add(it);
      }
      _items = checked;
      _publish(persist: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[downloads] init failed: $e');
    } finally {
      _readyCompleter!.complete();
    }
    unawaited(_pump());
  }

  String _pathFor(DownloadItem it) {
    final dir = _dir;
    if (dir == null) {
      throw const FileSystemException('download storage is unavailable');
    }
    return '${dir.path}${Platform.pathSeparator}${it.fileName}';
  }

  String _partPathFor(DownloadItem it) => '${_pathFor(it)}.part';

  DownloadItem? byId(String id) {
    for (final it in _items) {
      if (it.id == id) return it;
    }
    return null;
  }

  DownloadItem? find(String subjectId, [int se = 0, int ep = 0]) =>
      byId(downloadId(subjectId, se, ep));

  OfflineFile? offlineFile(String subjectId, int se, int ep) {
    final it = find(subjectId, se, ep);
    if (it == null || it.status != DownloadStatus.done || _dir == null) {
      return null;
    }
    final p = _pathFor(it);
    if (!File(p).existsSync()) return null;
    return OfflineFile(path: p, quality: it.quality, bytes: it.total);
  }

  /// A downloaded title stays openable with no connection at all.
  DetailData? offlineDetail(Subject subject) {
    final mine = _items.where(
      (it) =>
          it.subject.subjectId == subject.subjectId &&
          it.status == DownloadStatus.done,
    );
    if (mine.isEmpty) return null;
    final seasons = <int, int>{};
    for (final it in mine) {
      if (it.se > 0) {
        seasons[it.se] = (seasons[it.se] ?? 0) < it.ep
            ? it.ep
            : seasons[it.se]!;
      }
    }
    return DetailData(
      subject: mine.first.subject,
      seasons:
          seasons.entries
              .map((e) => SeasonResource(se: e.key, maxEp: e.value))
              .toList()
            ..sort((a, b) => a.se.compareTo(b.se)),
    );
  }

  int get totalBytesOnDisk => _items
      .where((i) => i.status == DownloadStatus.done)
      .fold(0, (a, b) => a + b.total);

  // ───────────────────────── queue control ─────────────────────────

  Future<void> add({
    required Subject subject,
    required int se,
    required int ep,
    required StreamQualityLike quality,
  }) async {
    await ready;
    final id = downloadId(subject.subjectId, se, ep);
    if (byId(id) != null) return; // already queued or done

    final safe = subject.cleanTitle
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim();
    final stem = se > 0 ? '${safe}_s${se}e$ep' : safe;
    final item = DownloadItem(
      id: id,
      subject: subject,
      se: se,
      ep: ep,
      quality: quality.label,
      height: quality.height,
      url: quality.url,
      headers: quality.headers,
      fileName: '${stem}_${quality.height}p_${subject.subjectId}.mp4',
      total: quality.sizeBytes ?? 0,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _items = [..._items, item];
    _publish();
    unawaited(_pump());
  }

  void pause(String id) {
    final it = byId(id);
    if (it == null || it.status == DownloadStatus.done) return;
    if (_activeId == id) {
      _cancel?.cancel('paused');
      _cancel = null;
      _activeId = null;
    }
    _update(
      id,
      (i) => i.copyWith(status: DownloadStatus.paused, bytesPerSecond: 0),
    );
    unawaited(_pump());
  }

  void resume(String id) {
    final it = byId(id);
    if (it == null || it.status == DownloadStatus.done) return;
    _update(id, (i) => i.copyWith(status: DownloadStatus.queued, error: null));
    unawaited(_pump());
  }

  Future<void> remove(String id) async {
    final it = byId(id);
    if (it == null) return;
    if (_activeId == id) {
      _cancel?.cancel('removed');
      _cancel = null;
      _activeId = null;
    }
    if (_dir != null) {
      for (final p in [_pathFor(it), _partPathFor(it)]) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _items = _items.where((x) => x.id != id).toList();
    _publish();
    unawaited(_pump());
  }

  Future<void> removeAll() async {
    for (final it in [..._items]) {
      await remove(it.id);
    }
  }

  void pauseAll() {
    for (final it in _items.where((i) => i.active)) {
      pause(it.id);
    }
  }

  // ───────────────────────── the pump ─────────────────────────

  Future<void> _pump() async {
    if (_activeId != null || _dir == null) return;
    final next = _items
        .where((i) => i.status == DownloadStatus.queued)
        .firstOrNull;
    if (next == null) {
      await Native.i.stopDownloadService();
      return;
    }

    _activeId = next.id;
    _update(
      next.id,
      (i) => i.copyWith(status: DownloadStatus.downloading, error: null),
    );

    if (Device.i.hasDownloadService) {
      await Native.i.startDownloadService(
        title: next.subject.cleanTitle,
        subtitle: next.isEpisode ? 's${next.se} · e${next.ep}' : 'movie',
      );
    }

    try {
      await _transfer(next.id);
    } catch (e) {
      final cancelled = e is DioException && e.type == DioExceptionType.cancel;
      if (!cancelled) {
        _update(
          next.id,
          (i) => i.copyWith(
            status: DownloadStatus.failed,
            bytesPerSecond: 0,
            error: _friendly(e),
          ),
        );
      }
    } finally {
      if (_activeId == next.id) {
        _activeId = null;
        _cancel = null;
      }
    }
    unawaited(_pump());
  }

  Future<void> _transfer(String id) async {
    var it = byId(id);
    if (it == null) return;

    final part = File(_partPathFor(it));
    var start = await part.exists() ? await part.length() : 0;

    _cancel = CancelToken();
    var lastTick = DateTime.now().millisecondsSinceEpoch;
    var lastBytes = start;

    Future<Response<ResponseBody>> open(String url, int from) =>
        _dio.get<ResponseBody>(
          url,
          cancelToken: _cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            // The Referer is not optional; without it the CDN answers 429.
            headers: {...it!.headers, if (from > 0) 'Range': 'bytes=$from-'},
            validateStatus: (s) => s != null && s < 500,
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

    var res = await open(it.url, start);

    // A stored URL expires. Re-resolve once through the play endpoint rather
    // than failing a download the user already waited for.
    if (res.statusCode == 403 ||
        res.statusCode == 404 ||
        res.statusCode == 410) {
      await _discard(res);
      final fresh = await _reresolve(it);
      if (fresh == null) {
        throw ApiError('This download link expired and could not be renewed.');
      }
      _update(id, (i) => i.copyWith(url: fresh.url, headers: fresh.headers));
      it = byId(id)!;
      res = await open(fresh.url, start);
    }

    // The server ignored our Range: start over rather than corrupt the file.
    if (start > 0 && res.statusCode == 200) {
      start = 0;
      lastBytes = 0;
      if (await part.exists()) await part.delete();
    }

    if (res.statusCode == 429) {
      await _discard(res);
      throw ApiError(
        'The server is rate-limiting downloads. Try again in a minute.',
      );
    }
    if (res.statusCode != 200 && res.statusCode != 206) {
      final code = res.statusCode;
      await _discard(res);
      throw ApiError('The server refused the download ($code).');
    }

    final lenHeader = res.headers.value(Headers.contentLengthHeader);
    final chunkLen = int.tryParse(lenHeader ?? '') ?? 0;
    final total = chunkLen > 0 ? start + chunkLen : it.total;
    _update(id, (i) => i.copyWith(total: total, received: start));

    final sink = part.openWrite(mode: FileMode.append);
    var received = start;

    try {
      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastTick >= 500) {
          final speed = (received - lastBytes) * 1000 / (now - lastTick);
          lastTick = now;
          lastBytes = received;
          _update(
            id,
            (i) => i.copyWith(received: received, bytesPerSecond: speed),
            persist: false,
          );
          if (Device.i.hasDownloadService) {
            final cur = byId(id);
            await Native.i.updateDownloadProgress(
              title: cur?.subject.cleanTitle ?? '',
              percent: total > 0 ? ((received / total) * 100).round() : 0,
            );
          }
        }
        if (byId(id)?.status != DownloadStatus.downloading) {
          // Paused or removed mid-stream.
          await sink.flush();
          await sink.close();
          return;
        }
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.flush();
      await sink.close();
      rethrow;
    }

    await part.rename(_pathFor(it));
    _update(
      id,
      (i) => i.copyWith(
        status: DownloadStatus.done,
        received: received,
        total: received,
        bytesPerSecond: 0,
      ),
    );
    final done = byId(id);
    if (done != null) {
      await Native.i.notifyDownloadComplete(
        title: done.subject.cleanTitle,
        subtitle: done.isEpisode
            ? 's${done.se} · e${done.ep}'
            : 'ready to watch offline',
      );
    }
  }

  /// Drain a response this transfer is not going to read, so its socket is
  /// released instead of being held open until the timeout.
  Future<void> _discard(Response<ResponseBody> res) async {
    try {
      await res.data?.stream.drain<void>();
    } catch (_) {}
  }

  Future<({String url, Map<String, String> headers})?> _reresolve(
    DownloadItem it,
  ) async {
    try {
      final r = await Api.i.play(
        it.subject.subjectId,
        it.subject.detailPath,
        se: it.se,
        ep: it.ep,
      );
      if (r.streams.isEmpty) return null;
      final idx = pickByHeight(
        r.streams.map((s) => s.height).toList(),
        it.height,
      );
      final s = r.streams[idx];
      return (url: s.url, headers: r.mediaHeaders);
    } catch (_) {
      return null;
    }
  }

  String _friendly(Object e) {
    if (e is ApiError) return e.message;
    if (e is FileSystemException) {
      return 'There is not enough space on this device.';
    }
    if (e is DioException) {
      return switch (e.type) {
        DioExceptionType.receiveTimeout || DioExceptionType.connectionTimeout =>
          'The connection stalled. Resume to continue.',
        _ => 'The download was interrupted. Resume to continue.',
      };
    }
    return 'The download was interrupted. Resume to continue.';
  }

  /// [persist] is false for the twice-a-second progress tick: re-encoding the
  /// whole queue to disk that often bought nothing, because the byte count is
  /// recovered from the `.part` file's own length on the next launch.
  void _update(
    String id,
    DownloadItem Function(DownloadItem) change, {
    bool persist = true,
  }) {
    var touched = false;
    _items = _items.map((i) {
      if (i.id != id) return i;
      touched = true;
      return change(i);
    }).toList();
    if (touched) _publish(persist: persist);
  }

  void _publish({bool persist = true}) {
    changes.value = _items;
    if (persist) {
      Store.i.setJson(_key, _items.map((e) => e.toJson()).toList());
    }
  }
}

/// The subset of a rendition a download needs, so this module does not depend
/// on the player's own types.
class StreamQualityLike {
  const StreamQualityLike({
    required this.label,
    required this.url,
    required this.height,
    this.headers = const {},
    this.sizeBytes,
  });

  final String label;
  final String url;
  final int height;
  final Map<String, String> headers;
  final int? sizeBytes;
}

/// Live download list for the widget tree.
final downloadsProvider = StreamProvider<List<DownloadItem>>((ref) async* {
  yield Downloads.i.items;
  yield* Downloads.i.changes.stream;
});

/// Keyed by download id, for a detail screen asking about one episode.
final downloadsByIdProvider = Provider<Map<String, DownloadItem>>((ref) {
  final list = ref.watch(downloadsProvider).asData?.value ?? Downloads.i.items;
  return {for (final d in list) d.id: d};
});

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
