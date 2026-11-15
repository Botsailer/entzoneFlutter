import 'dart:io';

import 'package:depressedzone/data/media_proxy.dart';

Future<void> main() async {
  final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests =
      <({String? range, String? referer, String? agent, String? refresh})>[];
  upstream.listen((request) async {
    requests.add((
      range: request.headers.value(HttpHeaders.rangeHeader),
      referer: request.headers.value(HttpHeaders.refererHeader),
      agent: request.headers.value(HttpHeaders.userAgentHeader),
      refresh: request.headers.value('X-Test-Refresh'),
    ));
    if (request.headers.value('X-Test-Refresh') != 'yes') {
      request.response.statusCode = 427;
      request.response.write('427 Forbidden');
    } else {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-3/10',
      );
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.add([0, 1, 2, 3]);
    }
    await request.response.close();
  });

  final proxy = MediaProxy();
  final client = HttpClient();
  try {
    final origin = 'http://127.0.0.1:${upstream.port}/video';
    final url = await proxy.register(
      url: origin,
      headers: {
        'Referer': 'https://player.example/page',
        'User-Agent': 'Mozilla/5.0',
      },
      refresh: () async => (
        url: origin,
        headers: {
          'Referer': 'https://player.example/page',
          'User-Agent': 'Mozilla/5.0',
          'X-Test-Refresh': 'yes',
        },
      ),
    );
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final response = await request.close();
    final bytes = await response.expand((chunk) => chunk).toList();
    if (response.statusCode != 206 ||
        response.headers.value(HttpHeaders.contentRangeHeader) !=
            'bytes 0-3/10' ||
        bytes.join(',') != '0,1,2,3' ||
        requests.length != 2 ||
        requests.any(
          (r) =>
              r.range != 'bytes=0-3' ||
              r.referer != 'https://player.example/page' ||
              r.agent != 'Mozilla/5.0',
        ) ||
        requests.last.refresh != 'yes') {
      stdout.writeln(
        'status=${response.statusCode} range=${response.headers.value(HttpHeaders.contentRangeHeader)} bytes=$bytes requests=$requests',
      );
      throw StateError('Range forwarding or signed URL refresh failed');
    }
    final rejectedUrl = await proxy.register(
      url: origin,
      headers: {
        'Referer': 'https://player.example/page',
        'User-Agent': 'Mozilla/5.0',
      },
    );
    final rejectedRequest = await client.getUrl(Uri.parse(rejectedUrl));
    rejectedRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final rejected = await rejectedRequest.close();
    await rejected.drain<void>();
    if (rejected.statusCode != 427 || proxy.lastUpstreamStatus != 427) {
      throw StateError('CDN rejection status was not preserved');
    }
    stdout.writeln(
      'Media proxy: Range, headers, refresh, and response forwarding passed.',
    );
  } finally {
    client.close(force: true);
    proxy.close();
    await upstream.close(force: true);
  }
}
