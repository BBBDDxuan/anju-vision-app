import 'notifications/alert_gate.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidNotificationStatus {
  const AndroidNotificationStatus({
    required this.permissionRequired,
    required this.permissionGranted,
    required this.appEnabled,
    required this.channelEnabled,
  });
  final bool permissionRequired, permissionGranted, appEnabled, channelEnabled;
  bool get enabled => permissionGranted && appEnabled && channelEnabled;

  factory AndroidNotificationStatus.fromMap(Map<Object?, Object?> data) =>
      AndroidNotificationStatus(
        permissionRequired: data['permission_required'] == true,
        permissionGranted: data['permission_granted'] == true,
        appEnabled: data['app_enabled'] == true,
        channelEnabled: data['channel_enabled'] == true,
      );
}

/// App owns the single native click handler; settings only query this bridge.
/// No credentials, camera frames or external deep links are sent to Android.
class AndroidNotices {
  static const channelId = 'elder_safety_alerts_v1';
  static const _channel = MethodChannel('elder_safety/notifications');
  static AndroidNotices? _owner;
  Future<void>? _initializing;
  bool _disposed = false;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize(
    void Function(String) onOpen, {
    void Function(String scope, String id)? onOpenScoped,
  }) {
    if (!supported || _disposed) return Future.value();
    if (_owner != null && _owner != this) {
      return Future.error(
        StateError('Android notification handler already owned'),
      );
    }
    return _initializing ??= _initialize(onOpen, onOpenScoped);
  }

  Future<void> _initialize(
    void Function(String) onOpen,
    void Function(String, String)? onOpenScoped,
  ) async {
    _owner = this;
    void deliverScoped(Object? value) {
      if (_disposed || value is! Map) return;
      final scope = value['scope'], id = value['event_id'];
      if (scope is String &&
          isNotificationScope(scope) &&
          id is String &&
          isUnifiedAlertId(id))
        onOpenScoped?.call(scope, id);
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openAlert') deliverScoped(call.arguments);
      if (!_disposed &&
          call.method == 'openEvent' &&
          call.arguments is String) {
        onOpen(call.arguments as String);
      }
    });
    try {
      await _channel.invokeMethod<void>('initialize');
      deliverScoped(
        await _channel.invokeMapMethod<Object?, Object?>('initialAlert'),
      );
      final initial = await _channel.invokeMethod<String>('initialEvent');
      if (!_disposed && initial != null) onOpen(initial);
    } catch (_) {
      _initializing = null;
      if (_owner == this) {
        _channel.setMethodCallHandler(null);
        _owner = null;
      }
      rethrow;
    }
  }

  Future<AndroidNotificationStatus?> status() async {
    if (!supported) return null;
    final data = await _channel.invokeMapMethod<Object?, Object?>('status');
    if (data == null) throw StateError('Android 未返回通知状态');
    return AndroidNotificationStatus.fromMap(data);
  }

  Future<AndroidNotificationStatus?> requestPermission({
    bool automatic = false,
  }) async {
    if (!supported) return null;
    final data = await _channel.invokeMapMethod<Object?, Object?>(
      'requestPermission',
      automatic ? {'automatic': true} : null,
    );
    if (data == null) throw StateError('Android 未返回通知权限状态');
    return AndroidNotificationStatus.fromMap(data);
  }

  Future<void> openAppSettings() async {
    if (supported) await _channel.invokeMethod<void>('openAppSettings');
  }

  Future<void> openNotificationSettings() async {
    if (supported)
      await _channel.invokeMethod<void>('openNotificationSettings');
  }

  Future<void> openChannelSettings() async {
    if (supported) await _channel.invokeMethod<void>('openChannelSettings');
  }

  Future<void> show(String eventId, {String? scope}) async {
    if (supported && !_disposed) {
      await _channel.invokeMethod<void>('show', {
        'event_id': eventId,
        if (scope != null) 'scope': scope,
      });
    }
  }

  Future<void> clear() async {
    if (supported) await _channel.invokeMethod<void>('clear');
  }

  Future<void> dispose() async {
    _disposed = true;
    if (_owner == this) {
      _channel.setMethodCallHandler(null);
      _owner = null;
    }
  }
}
