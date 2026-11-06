import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Local trust is deliberately limited to this deployment's HTTPS origin.
// The certificate chain and server IP are still checked by dart:io.
const _configuredOrigins = String.fromEnvironment('ANJU_LAN_ORIGINS');
const _encodedCa = String.fromEnvironment('ANJU_LAN_CA_BASE64');
final _localOrigins = _configuredOrigins
    .split(',')
    .where((value) => value.isNotEmpty)
    .toSet();
String get localBackendOrigin => _localOrigins.firstOrNull ?? '';
SecurityContext? _localContext;

Future<void> loadLocalBackendTrust() async {
  if (_encodedCa.isEmpty || _localOrigins.isEmpty) return;
  _localContext = SecurityContext()
    ..setTrustedCertificatesBytes(base64Decode(_encodedCa));
}

HttpClient backendHttpClient(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  final isLocal =
      uri != null &&
      uri.hasAuthority &&
      uri.scheme == 'https' &&
      _localOrigins.contains(uri.origin);
  return HttpClient(context: isLocal ? _localContext : null);
}

http.Client backendClient(String baseUrl) =>
    IOClient(backendHttpClient(baseUrl));
