import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _storage = FlutterSecureStorage();
const _trustKey = 'anju_backend_trust_v1';
const _limit = 16 * 1024;
const _timeout = Duration(seconds: 8);
final _sha256Text = RegExp(r'^[a-f0-9]{64}$');
String? _trustedOrigin;
SecurityContext? _pairedContext;

class BackendPairingException implements Exception {
  const BackendPairingException(this.message);
  final String message;
}

Future<void> loadLocalBackendTrust() async {
  final raw = await _storage.read(key: _trustKey);
  if (raw == null) return;
  try {
    final saved = jsonDecode(raw) as Map<String, dynamic>;
    final origin = saved['origin'] as String;
    final uri = Uri.parse(origin);
    final pem = base64Decode(saved['ca'] as String);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != origin ||
        pem.isEmpty ||
        pem.length > _limit) {
      throw const FormatException();
    }
    final context = SecurityContext()..setTrustedCertificatesBytes(pem);
    _trustedOrigin = origin;
    _pairedContext = context;
  } on FormatException {
    await _storage.delete(key: _trustKey);
  } on TlsException {
    await _storage.delete(key: _trustKey);
  } on TypeError {
    await _storage.delete(key: _trustKey);
  }
}

Future<Uint8List> _getPairingData(HttpClient client, Uri uri) async {
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200 || response.contentLength > _limit) {
        throw const BackendPairingException(
          '电脑网关未返回有效的证书或账号服务，请检查 HTTPS 网关后重新扫码。',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > _limit) {
          throw const BackendPairingException('电脑返回的配对数据超出大小限制。');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    })().timeout(_timeout);
  } finally {
    client.close(force: true);
  }
}

Future<void> pairBackendTrust(
  String origin, {
  required String caSha256,
  required String tlsSha256,
}) async {
  final uri = Uri.parse(origin);
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.origin != origin ||
      !_sha256Text.hasMatch(caSha256) ||
      !_sha256Text.hasMatch(tlsSha256)) {
    throw const BackendPairingException('二维码中的地址或证书指纹格式无效。');
  }
  try {
    // This dedicated client sends only a certificate GET, with no cookies,
    // password or login code. Its exception is pinned to the scanned TLS leaf.
    final bootstrap = HttpClient();
    bootstrap.findProxy = (_) => 'DIRECT';
    bootstrap.badCertificateCallback = (cert, host, port) =>
        host == uri.host &&
        port == uri.port &&
        sha256.convert(cert.der).toString() == tlsSha256;
    final pem = await _getPairingData(
      bootstrap,
      uri.replace(path: '/api/auth/pair-ca'),
    );
    if (pem.isEmpty || sha256.convert(pem).toString() != caSha256) {
      throw const BackendPairingException('下载的证书与二维码指纹不一致，请在电脑重新生成二维码。');
    }

    final context = SecurityContext()..setTrustedCertificatesBytes(pem);
    final statusBytes = await _getPairingData(
      HttpClient(context: context)..findProxy = (_) => 'DIRECT',
      uri.replace(path: '/api/auth/status'),
    );
    final status = jsonDecode(utf8.decode(statusBytes));
    if (status is! Map || status['enabled'] != true) {
      throw const BackendPairingException('已连接电脑，但账号服务未启用。');
    }
    await _storage.write(
      key: _trustKey,
      value: jsonEncode({'origin': origin, 'ca': base64Encode(pem)}),
    );
    _trustedOrigin = origin;
    _pairedContext = context;
  } on TlsException {
    throw const BackendPairingException('电脑证书校验失败。请确认网关证书覆盖当前地址，并在电脑重新生成二维码。');
  } on TimeoutException {
    throw const BackendPairingException('下载或校验证书超时，请确认手机和电脑在互通的 Wi-Fi 下。');
  } on SocketException {
    throw const BackendPairingException('无法连接电脑下载证书，请检查网关地址和 Wi-Fi。');
  } on HttpException {
    throw const BackendPairingException('证书下载连接中断，请检查电脑网关后重新扫码。');
  } on FormatException {
    throw const BackendPairingException('电脑返回的配对数据无效，请检查 HTTPS 网关。');
  }
}

HttpClient backendHttpClient(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (_pairedContext != null &&
      uri?.scheme == 'https' &&
      uri!.hasAuthority &&
      uri.origin == _trustedOrigin) {
    return HttpClient(context: _pairedContext)..findProxy = (_) => 'DIRECT';
  }
  return HttpClient();
}

http.Client backendClient(String baseUrl) =>
    IOClient(backendHttpClient(baseUrl));
