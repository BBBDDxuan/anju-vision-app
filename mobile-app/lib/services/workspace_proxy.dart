import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/household.dart';
import 'object_api.dart';

/// App-local, capability-protected proxy. Keeps credentials out of page JavaScript,
/// supplies the existing backend's Bearer header to uploads/media/XHR alike, and
/// requires no changes to the user's website or backend.
class WorkspaceProxy {
  WorkspaceProxy(this.config);
  final ObjectServiceConfig config;
  final _http = HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 15);
  HttpServer? _server;
  final String _session = base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  Uri? _upstream;
  Future<Uri> start() async {
    final api = ObjectApi(config);
    _upstream = api.uri('/');
    api.close();
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    server.listen((request) => unawaited(_forward(request)));
    return Uri.parse(
      'http://127.0.0.1:${server.port}/__anju_open?key=${Uri.encodeQueryComponent(_session)}',
    );
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
  Future<void> _forward(HttpRequest incoming) async {
    try {
      if (incoming.uri.path == '/__anju_open') {
        if (incoming.uri.queryParameters['key'] != _session) {
          incoming.response.statusCode = 403;
          await incoming.response.close();
          return;
        }
        incoming.response.cookies.add(
          Cookie('anju_workspace', _session)
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..path = '/',
        );
        incoming.response.statusCode = 302;
        incoming.response.headers.set(HttpHeaders.locationHeader, '/workspace');
        await incoming.response.close();
        return;
      }
      if (!incoming.cookies.any(
        (c) => c.name == 'anju_workspace' && c.value == _session,
      )) {
        incoming.response.statusCode = 403;
        await incoming.response.close();
        return;
      }
      final target = _upstream!.resolve(incoming.uri.toString());
      if (!_sameOrigin(target, _upstream!) ||
          incoming.uri.hasAuthority ||
          incoming.uri.path.startsWith('//')) {
        incoming.response.statusCode = 403;
        await incoming.response.close();
        return;
      }
      final outgoing = await _http.openUrl(incoming.method, target);
      outgoing.followRedirects = false;
      const hop = {
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
        if (!hop.contains(name.toLowerCase()))
          outgoing.headers.set(name, values);
      });
      if (config.token.isNotEmpty)
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${config.token}',
        );
      if (incoming.headers.value('origin') != null)
        outgoing.headers.set('origin', _upstream!.origin);
      if (incoming.headers.value('referer') != null)
        outgoing.headers.set(
          'referer',
          _upstream!.resolve('/workspace').toString(),
        );
      final cookies = incoming.cookies
          .where((c) => c.name != 'anju_workspace')
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (cookies.isNotEmpty)
        outgoing.headers.set(HttpHeaders.cookieHeader, cookies);
      await outgoing.addStream(incoming);
      final response = await outgoing.close();
      incoming.response.statusCode = response.statusCode;
      response.headers.forEach((name, values) {
        if (!{
          'connection',
          'transfer-encoding',
          'set-cookie',
          'location',
        }.contains(name.toLowerCase()))
          incoming.response.headers.set(name, values);
      });
      for (final cookie in response.cookies) {
        cookie.domain = null;
        cookie.path = '/';
        cookie.secure = false;
        incoming.response.cookies.add(cookie);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location != null) {
        final redirect = target.resolve(location);
        if (!_sameOrigin(redirect, _upstream!)) {
          incoming.response.statusCode = 502;
          await incoming.response.close();
          return;
        }
        incoming.response.headers.set(
          HttpHeaders.locationHeader,
          redirect.hasQuery
              ? '${redirect.path}?${redirect.query}'
              : redirect.path,
        );
      }
      await incoming.response.addStream(response);
      await incoming.response.close();
    } catch (_) {
      try {
        incoming.response.statusCode = 502;
        incoming.response.headers.contentType = ContentType.html;
        incoming.response.write(
          '<html lang="zh"><meta charset="utf-8"><body>无法连接工作台服务，请检查 App 中的服务地址、访问令牌和电脑后端状态。</body></html>',
        );
        await incoming.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    _http.close(force: true);
    await _server?.close(force: true);
    _server = null;
  }
}
