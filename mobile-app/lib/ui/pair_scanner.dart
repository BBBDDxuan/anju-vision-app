import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

Uri? pairingOrigin(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final parts = uri.host.split('.');
  if (parts.length != 4) return null;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((n) => n == null || n < 0 || n > 255)) return null;
  final a = octets[0], b = octets[1]!;
  if (a != 10 && !(a == 172 && b >= 16 && b <= 31) && !(a == 192 && b == 168)) {
    return null;
  }
  if (uri.port < 1 || uri.port > 65535) return null;
  return uri;
}

Future<String?> scanRawQr(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const _PairScanner()));

Future<({String origin, String token})?> scanPairing(
  BuildContext context,
) async {
  final raw = await scanRawQr(context);
  if (raw == null) return null;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw const FormatException('不是安居视界配对二维码。');
  }
  final origin = pairingOrigin(data['origin']);
  final code = data['code'];
  if (data['kind'] != 'anju-pair-v1' ||
      origin == null ||
      code is! String ||
      !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code)) {
    throw const FormatException('不是有效的安居视界配对二维码。');
  }
  final client = http.Client();
  try {
    final request =
        http.Request('POST', origin.replace(path: '/api/lan/pair/exchange'))
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'code': code});
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(const Duration(seconds: 8));
    if (response.statusCode == 403) {
      throw const FormatException('配对码无效或已过期，请在电脑上重新生成。');
    }
    if (response.statusCode != 200) throw const FormatException('电脑未接受配对。');
    final decoded = jsonDecode(response.body);
    final token = decoded is Map ? decoded['token'] : null;
    if (token is! String || token.isEmpty)
      throw const FormatException('电脑未返回配对凭据。');
    return (origin: origin.toString(), token: token);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('无法连接电脑，请检查手机和电脑网络是否互通。');
  } finally {
    client.close();
  }
}

class _PairScanner extends StatefulWidget {
  const _PairScanner();

  @override
  State<_PairScanner> createState() => _PairScannerState();
}

class _PairScannerState extends State<_PairScanner> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描电脑配对二维码')),
    body: MobileScanner(
      errorBuilder: (context, error) =>
          const Center(child: Text('无法打开相机，请检查相机权限，或返回手动连接。')),
      onDetect: (capture) {
        if (_done) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value == null || value.isEmpty || value.length > 512) continue;
          _done = true;
          Navigator.of(context).pop(value);
          break;
        }
      },
    ),
  );
}
