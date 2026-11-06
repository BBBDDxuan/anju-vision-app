import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/household.dart';

const defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class AppSettings {
  const AppSettings({
    this.baseUrl = defaultApiBaseUrl,
    this.bearerToken = '',
    this.contactId = 'primary',
    this.pollSeconds = 15,
    this.connectionVersion = 2,
  });
  final String baseUrl;
  final String bearerToken;
  final String contactId;
  final int pollSeconds;
  final int connectionVersion;
  AppSettings copyWith({
    String? baseUrl,
    String? bearerToken,
    String? contactId,
    int? pollSeconds,
    int? connectionVersion,
  }) => AppSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    bearerToken: bearerToken ?? this.bearerToken,
    contactId: contactId ?? this.contactId,
    pollSeconds: pollSeconds ?? this.pollSeconds,
    connectionVersion: connectionVersion ?? this.connectionVersion,
  );

  Map<String, dynamic> toJson() => {
    'base_url': baseUrl,
    'bearer_token': bearerToken,
    'contact_id': contactId,
    'poll_seconds': pollSeconds,
    'connection_version': connectionVersion,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    baseUrl: json['base_url'] as String? ?? defaultApiBaseUrl,
    bearerToken: json['bearer_token'] as String? ?? '',
    contactId: json['contact_id'] == 'backup' ? 'backup' : 'primary',
    connectionVersion: (json['connection_version'] as num?)?.toInt() ?? 1,
    pollSeconds: ((json['poll_seconds'] as num?)?.toInt() ?? 15)
        .clamp(5, 300)
        .toInt(),
  );

  String? get validationError {
    if (contactId != 'primary' && contactId != 'backup') return '联系人无效';
    if (pollSeconds < 5 || pollSeconds > 300) return '轮询间隔需为 5–300 秒';
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path != '' && uri.path != '/')) {
      return '后端 URL 需为 http(s)://主机[:端口]，不要添加 /api/v1 或凭据';
    }
    if (uri.scheme == 'http') {
      final parts = uri.host.split('.').map(int.tryParse).toList();
      final ipv4 =
          parts.length == 4 &&
          parts.every((p) => p != null && p >= 0 && p <= 255);
      final privateAddress =
          ipv4 &&
          (parts[0] == 10 ||
              parts[0] == 127 ||
              (parts[0] == 192 && parts[1] == 168) ||
              (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31));
      if (!privateAddress && uri.host != 'localhost' && uri.host != '::1')
        return '外网服务请使用 HTTPS，HTTP 仅用于局域网 IP 调试';
    }
    if (RegExp(r'\s').hasMatch(bearerToken.trim())) {
      return '请输入用户 token 原文，不含 Bearer 前缀或空白';
    }
    return null;
  }
}

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<Map<String, dynamic>?> loadPushRegistration();
  Future<void> savePushRegistration(Map<String, dynamic>? registration);
}

abstract interface class HouseholdStore {
  Future<HouseholdData?> loadHousehold();
  Future<void> saveHousehold(HouseholdData data);
}

abstract interface class AlertSyncStore {
  Future<Map<String, dynamic>?> loadAlertSync(String scope);
  Future<void> saveAlertSync(String scope, Map<String, dynamic> snapshot);
}

class SecureSettingsStore
    implements SettingsStore, HouseholdStore, AlertSyncStore {
  SecureSettingsStore({FlutterSecureStorage? storage, this.namespace = ""})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  final String namespace;
  String _key(String name) => namespace.isEmpty ? name : '$name|$namespace';
  static const _settingsKey = 'elder_safety_settings_v1';
  static const _pushKey = 'elder_safety_push_v1';
  Future<void> _alertWrites = Future.value();
  @override
  Future<Map<String, dynamic>?> loadAlertSync(String scope) async {
    final raw = await _storage.read(key: _key('anju_alert_sync_v1|$scope'));
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> saveAlertSync(String scope, Map<String, dynamic> snapshot) {
    // Cursor and matching mirror are one atomic secure-storage value.
    final encoded = jsonEncode(snapshot);
    final operation = _alertWrites.then(
      (_) => _storage.write(
        key: _key('anju_alert_sync_v1|$scope'),
        value: encoded,
      ),
    );
    _alertWrites = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<HouseholdData?> loadHousehold() async {
    final raw = await _storage.read(key: _key('anju_household_v11'));
    return raw == null
        ? null
        : HouseholdData.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  @override
  Future<void> saveHousehold(HouseholdData data) => _storage.write(
    key: _key('anju_household_v11'),
    value: jsonEncode(data.toJson()),
  );

  @override
  Future<AppSettings> load() async {
    await _storage.delete(key: 'elder_safety_demo_preferences_v1');
    await _storage.delete(key: 'anju_demo_events_v1');
    final raw = await _storage.read(key: _key(_settingsKey));
    if (raw == null) return const AppSettings();
    return AppSettings.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  @override
  Future<void> save(AppSettings settings) => _storage.write(
    key: _key(_settingsKey),
    value: jsonEncode(settings.toJson()),
  );
  @override
  Future<Map<String, dynamic>?> loadPushRegistration() async {
    final raw = await _storage.read(key: _key(_pushKey));
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> savePushRegistration(Map<String, dynamic>? registration) =>
      registration == null
      ? _storage.delete(key: _key(_pushKey))
      : _storage.write(key: _key(_pushKey), value: jsonEncode(registration));
}
