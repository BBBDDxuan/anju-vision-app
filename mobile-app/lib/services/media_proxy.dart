import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/household.dart';
import 'backend_tls.dart';

/// video_player 在 Android 上使用 ExoPlayer，只信任系统证书；扫码配对得到的
/// 家庭 CA 只装进了 Dart 的 SecurityContext。这里用本机回环 HTTP 中转播放请求，
/// 由带配对信任的 HttpClient 访问上游，并原样转发 Range/206。
class MediaProxy {
  MediaProxy(this.config);

  final ObjectServiceConfig config;
  late final HttpClient _upstream = backendHttpClient(config.baseUrl)
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);
  final String _key = base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  HttpServer? _server;
  Uri? _origin;

  Future<Uri> uri(String path) async {
    if (!path.startsWith('/media/videos/') ||
        RegExp(r'\s').hasMatch(path) ||
        path.split('/').any((part) => part == '.' || part == '..')) {
      throw ArgumentError('MediaProxy 只转发录像播放路径');
    }
    _origin ??= Uri.parse(config.baseUrl.replaceAll(RegExp(r'/+$'), ''));
    final server = _server ?? await _start();
    return Uri.parse('http://127.0.0.1:${server.port}/$_key$path');
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    server.listen((request) => unawaited(_forward(request)));
    return server;
  }

  Future<void> _forward(HttpRequest incoming) async {
    try {
      final prefix = '/$_key/media/videos/';
      final path = incoming.uri.path;
      if (!path.startsWith(prefix)) {
        await _status(incoming, 403);
        return;
      }
      if (incoming.method != 'GET' && incoming.method != 'HEAD') {
        await _status(incoming, 405);
        return;
      }
      final relative = path.substring('/$_key'.length);
      if (relative.split('/').any((part) => part == '.' || part == '..')) {
        await _status(incoming, 403);
        return;
      }
      final target = _origin!.resolve(
        incoming.uri.hasQuery ? '$relative?${incoming.uri.query}' : relative,
      );
      if (target.scheme != _origin!.scheme ||
          target.host != _origin!.host ||
          target.port != _origin!.port) {
        await _status(incoming, 403);
        return;
      }
      final outgoing = await _upstream.openUrl(incoming.method, target);
      outgoing.followRedirects = false;
      const dropped = {
        'host',
        'connection',
        'keep-alive',
        'proxy-authenticate',
        'proxy-authorization',
        'te',
        'trailer',
        'transfer-encoding',
        'upgrade',
        'authorization',
        'cookie',
        'accept-encoding',
      };
      incoming.headers.forEach((name, values) {
        if (!dropped.contains(name.toLowerCase())) {
          outgoing.headers.set(name, values);
        }
      });
      if (config.token.isNotEmpty) {
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${config.token}',
        );
      }
      final response = await outgoing.close();
      incoming.response.statusCode = response.statusCode;
      for (final name in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final value = response.headers.value(name);
        if (value != null) incoming.response.headers.set(name, value);
      }
      await incoming.response.addStream(response);
      await incoming.response.close();
    } catch (_) {
      await _status(incoming, 502);
    }
  }

  Future<void> _status(HttpRequest request, int code) async {
    try {
      request.response.statusCode = code;
      await request.response.close();
    } catch (_) {}
  }

  Future<void> close() async {
    _upstream.close(force: true);
    await _server?.close(force: true);
    _server = null;
  }
}
