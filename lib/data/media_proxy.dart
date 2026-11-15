import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

typedef RefreshedMedia = ({String url, Map<String, String> headers});

/// A private loopback equivalent of the prototype's /api/media Range endpoint.
/// libmpv only sees localhost; this server attaches the CDN headers and streams
/// each requested byte range without buffering the video in Dart.
class MediaProxy {
  final _client = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);
  final _sources = <String, _MediaSource>{};
  HttpServer? _server;
  Future<HttpServer>? _starting;
  bool _closed = false;

  int? lastUpstreamStatus;

  Future<String> register({
    required String url,
    required Map<String, String> headers,
    Future<RefreshedMedia?> Function()? refresh,
  }) async {
    if (_closed) throw const HttpException('Media proxy is closed');
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && uri.host == '127.0.0.1')) {
      throw const HttpException('Invalid media URL');
    }
    final server = await (_starting ??=
        HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((value) {
          _server = value;
          value.listen(_handle);
          return value;
        }));
    lastUpstreamStatus = null;
    final random = Random.secure();
    final key = base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    if (_sources.length >= 32) _sources.remove(_sources.keys.first);
    _sources[key] = _MediaSource(url, Map.of(headers), refresh);
    return 'http://127.0.0.1:${server.port}/media/$key';
  }

  Future<HttpClientResponse> _open(
    _MediaSource source,
    String method,
    String? range,
    String? ifRange,
  ) async {
    final request = await _client.openUrl(method, Uri.parse(source.url));
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    for (final header in source.headers.entries) {
      request.headers.set(header.key, header.value);
    }
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    if (ifRange != null) {
      request.headers.set(HttpHeaders.ifRangeHeader, ifRange);
    }
    return request.close().timeout(const Duration(seconds: 25));
  }

  Future<void> _handle(HttpRequest request) async {
    final output = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        output.statusCode = HttpStatus.methodNotAllowed;
        await output.close();
        return;
      }
      final parts = request.uri.pathSegments;
      final source = parts.length == 2 && parts.first == 'media'
          ? _sources[parts.last]
          : null;
      if (source == null) {
        output.statusCode = HttpStatus.notFound;
        await output.close();
        return;
      }

      final range = request.headers.value(HttpHeaders.rangeHeader);
      final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
      var upstream = await _open(source, request.method, range, ifRange);
      if (_refreshableStatus(upstream.statusCode) && source.refresh != null) {
        await upstream.drain<void>();
        if (await source.refreshUrl()) {
          upstream = await _open(source, request.method, range, ifRange);
        } else {
          // A refresh can fail independently; report the original CDN status.
          output.statusCode = upstream.statusCode;
          lastUpstreamStatus = upstream.statusCode;
          await output.close();
          return;
        }
      }

      lastUpstreamStatus = upstream.statusCode >= 400
          ? upstream.statusCode
          : null;
      output.statusCode = upstream.statusCode;
      for (final name in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers.value(name);
        if (value != null) output.headers.set(name, value);
      }
      output.headers.set(HttpHeaders.cacheControlHeader, 'private, no-store');
      if (request.method == 'GET') await output.addStream(upstream);
      await output.close();
    } catch (_) {
      lastUpstreamStatus ??= HttpStatus.badGateway;
      try {
        output.statusCode = HttpStatus.badGateway;
        output.headers.contentType = ContentType.text;
        output.write('Media upstream unavailable');
        await output.close();
      } catch (_) {
        // The player closed its Range request while switching or seeking.
      }
    }
  }

  bool _refreshableStatus(int status) =>
      status == 401 ||
      status == 403 ||
      status == 404 ||
      status == 410 ||
      status == 427 ||
      status == 429;

  void close() {
    if (_closed) return;
    _closed = true;
    _sources.clear();
    final server = _server;
    _server = null;
    _starting = null;
    unawaited(server?.close(force: true) ?? Future<void>.value());
    _client.close(force: true);
  }
}

class _MediaSource {
  _MediaSource(this.url, this.headers, this.refresh);

  String url;
  Map<String, String> headers;
  final Future<RefreshedMedia?> Function()? refresh;
  Future<bool>? _refreshing;
  DateTime? _lastRefresh;

  Future<bool> refreshUrl() {
    if (_refreshing != null) return _refreshing!;
    final now = DateTime.now();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!) < const Duration(seconds: 20)) {
      return Future.value(false);
    }
    _lastRefresh = now;
    return _refreshing = _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final updated = await refresh?.call();
      if (updated == null) return false;
      final uri = Uri.tryParse(updated.url);
      if (uri?.scheme != 'https' &&
          !(uri?.scheme == 'http' && uri?.host == '127.0.0.1')) {
        return false;
      }
      if (updated.url == url &&
          updated.headers.length == headers.length &&
          updated.headers.entries.every(
            (entry) => headers[entry.key] == entry.value,
          )) {
        return false;
      }
      url = updated.url;
      headers = Map.of(updated.headers);
      return true;
    } catch (_) {
      return false;
    }
  }
}
