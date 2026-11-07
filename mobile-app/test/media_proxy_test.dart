import 'dart:io';

import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/media_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('本机中转转发 Range 并注入家庭令牌', () async {
    String? authorization;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      final found = request.uri.path == '/media/videos/v1';
      request.response.statusCode = found
          ? HttpStatus.partialContent
          : HttpStatus.notFound;
      if (found) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-3/8',
        );
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add([1, 2, 3, 4]);
      }
      await request.response.close();
    });
    final proxy = MediaProxy(
      ObjectServiceConfig(
        baseUrl: 'http://127.0.0.1:${upstream.port}',
        token: 'household-token',
      ),
    );
    final client = HttpClient();
    try {
      final uri = await proxy.uri('/media/videos/v1');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-3/8',
      );
      expect(authorization, 'Bearer household-token');
      await response.drain<void>();
      await expectLater(
        proxy.uri('/api/videos/v1'),
        throwsA(isA<ArgumentError>()),
      );
    } finally {
      client.close(force: true);
      await proxy.close();
      await upstream.close(force: true);
    }
  });
}
