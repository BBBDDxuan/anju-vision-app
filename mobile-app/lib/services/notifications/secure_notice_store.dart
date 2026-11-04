import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'alert_gate.dart';

/// Separate from B's connection/settings schema; no bearer tokens stored here.
class SecureNoticeStateStore
    implements NoticeStateStore, BackgroundNoticeReceipts {
  SecureNoticeStateStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String scope) =>
      'anju_notice_v1_${base64Url.encode(utf8.encode(scope))}';
  @override
  Future<String?> read(String scope) => _storage.read(key: _key(scope));
  @override
  Future<void> write(String scope, String value) =>
      _storage.write(key: _key(scope), value: value);
  @override
  Future<bool> wasReceived(String scope, String id) async =>
      await _storage.read(key: _key(scope) + '_' + id) == 'received';
  Future<void> recordBackgroundReceipt(String scope, String id) async {
    if (!isUnifiedAlertId(id)) return;
    await _storage.write(key: _key(scope) + '_' + id, value: 'received');
  }
}
