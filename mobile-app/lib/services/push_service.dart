import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'api.dart';
import 'settings_store.dart';
import 'notifications/alert_gate.dart';
import 'notifications/push_payload.dart';
import 'notifications/secure_notice_store.dart';

const useFirebase = bool.fromEnvironment('USE_FIREBASE', defaultValue: false);

String? eventIdFromData(Map<String, dynamic> data) {
  String? clean(Object? value) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))
      return null;
    return value.trim();
  }

  if (data['anju_type'] == 'unified_alert') {
    final id = clean(data['alert_id']);
    return id != null && isUnifiedAlertId(id) ? id : null;
  }
  final direct = clean(data['event_id']);
  if (direct != null) return direct;
  final link = data['deep_link'];
  if (link is! String) return null;
  final uri = Uri.tryParse(link);
  if (uri == null || uri.hasQuery || uri.hasFragment) return null;
  if (uri.scheme == 'elder-safety' &&
      uri.host == 'events' &&
      uri.pathSegments.length == 1)
    return clean(uri.pathSegments.single);
  if (!uri.hasScheme &&
      !uri.hasAuthority &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'events')
    return clean(uri.pathSegments.last);
  return null;
}

/// Android's SDK displays notification+data payloads in the background. This
/// handler only records receipt; it must never post a second local notification.
@pragma('vm:entry-point')
Future<void> unifiedMessagingBackgroundHandler(RemoteMessage message) async {
  final target = scopedPushAlert(message.data);
  if (target == null) return;
  try {
    await initializeConfiguredFirebase();
    await SecureNoticeStateStore().recordBackgroundReceipt(
      target.scope,
      target.id,
    );
  } catch (_) {
    // Actual OEM delivery/storage behavior still requires a real-device test.
  }
}

abstract interface class PushGateway {
  String get platform;
  Stream<String> get tokenRefreshes;
  Stream<String> get openedEvents;
  Stream<String> get foregroundEvents;
  Future<void> initialize();
  Future<String?> requestToken();
  Future<void> setEnabled(bool enabled);
  Future<void> dispose();
}

class FirebasePushGateway implements PushGateway {
  FirebasePushGateway({this.currentScope});
  final String? Function()? currentScope;
  String? _unifiedId(Map<String, dynamic> data) {
    final target = scopedPushAlert(data);
    return target != null && target.scope == currentScope?.call()
        ? target.id
        : null;
  }

  FirebaseMessaging? _messaging;
  final _tokens = StreamController<String>.broadcast();
  final _opened = StreamController<String>.broadcast();
  final _foreground = StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  bool _enabled = false;
  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  @override
  Stream<String> get tokenRefreshes => _tokens.stream;
  @override
  Stream<String> get openedEvents => _opened.stream;
  @override
  Stream<String> get foregroundEvents => _foreground.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      throw const ApiException('FCM 当前仅配置 Android/iOS');
    }
    await initializeConfiguredFirebase();
    FirebaseMessaging.onBackgroundMessage(unifiedMessagingBackgroundHandler);
    _messaging = FirebaseMessaging.instance;
    _subscriptions.add(
      _messaging!.onTokenRefresh.listen(
        _tokens.add,
        onError: (Object error, StackTrace stack) =>
            _tokens.addError(const ApiException('FCM token 刷新失败'), stack),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) async {
        final id = _unifiedId(message.data);
        if (id != null) {
          final target = scopedPushAlert(message.data);
          if (target != null) {
            try {
              await SecureNoticeStateStore().recordBackgroundReceipt(
                target.scope,
                id,
              );
            } catch (_) {}
          }
          _opened.add(id);
        }
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        final id = _unifiedId(message.data);
        if (id != null && _enabled) {
          _foreground.add(id);
          // App renders the system notification from controller.notices.
        }
      }),
    );
    final initial = await _messaging!.getInitialMessage();
    _initialized = true;
    if (initial != null) {
      final id = _unifiedId(initial.data);
      if (id != null) {
        final target = scopedPushAlert(initial.data);
        if (target != null) {
          try {
            await SecureNoticeStateStore().recordBackgroundReceipt(
              target.scope,
              id,
            );
          } catch (_) {}
        }
        _opened.add(id);
      }
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (_messaging != null) {
      await _messaging!.setAutoInitEnabled(enabled);
      if (platform == 'ios') {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: enabled,
          badge: enabled,
          sound: enabled,
        );
      }
    }
  }

  @override
  Future<String?> requestToken() async {
    final messaging = _messaging!;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied ||
        permission.authorizationStatus == AuthorizationStatus.notDetermined) {
      throw const ApiException('系统通知权限未授予；可在系统设置开启后重试');
    }
    if (platform == 'ios' && await messaging.getAPNSToken() == null) {
      throw const ApiException('APNs token 尚未就绪；请在真机配置 APNs 后重试');
    }
    // Keep the registration-token flow to match /push-tokens. Do not mix FID APIs.
    final token = await messaging.getToken();
    if (token == null || token.isEmpty)
      throw const ApiException('FCM 未返回 token，请重试');
    return token;
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _tokens.close();
    await _opened.close();
    await _foreground.close();
  }
}

class PushCoordinator {
  PushCoordinator({
    required this.store,
    required this.onOpen,
    required this.onForeground,
    required this.onStatus,
    this.gateway,
  });
  final SettingsStore store;
  final PushGateway? gateway;
  final void Function(String) onOpen;
  final void Function(String) onForeground;
  final void Function(String) onStatus;
  final List<StreamSubscription<String>> _subscriptions = [];
  SafetyRepository? _repository;
  AppSettings? _settings;
  bool _enabled = false;
  bool _attached = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> configure(
    SafetyRepository repository,
    AppSettings settings,
    bool notificationsEnabled,
  ) => _serialize(() async {
    if (_disposed) return;
    _repository = repository;
    _settings = settings;
    _enabled = notificationsEnabled;
    if (settings.bearerToken.isEmpty || gateway == null) {
      // No safety credentials: video polling remains independent of FCM.
      await gateway?.setEnabled(false);
      if (!notificationsEnabled && settings.bearerToken.isNotEmpty) {
        await _removeRegistration();
      }
      onStatus(
        !notificationsEnabled
            ? '家庭事件提醒已关闭'
            : settings.bearerToken.isEmpty
            ? '安全后端未启用；录像事件仅在 App 前台刷新提醒，后台视频推送尚未实现'
            : 'Firebase 未启用；安全事件仅在 App 前台刷新提醒',
      );
      return;
    }
    if (!_attached) {
      _attached = true;
      _subscriptions.add(
        gateway!.tokenRefreshes.listen((token) {
          unawaited(
            _serialize(() async {
              if (_enabled &&
                  !_disposed &&
                  _settings?.bearerToken.isNotEmpty == true)
                await _register(token, gateway!.platform);
            }).catchError((Object _) => onStatus('FCM token 刷新注册失败，请重试')),
          );
        }, onError: (Object _) => onStatus('FCM token 刷新失败，请重试')),
      );
      _subscriptions.add(
        gateway!.openedEvents.listen((id) {
          if (!_disposed && _settings?.bearerToken.isNotEmpty == true)
            onOpen(id);
        }),
      );
      _subscriptions.add(
        gateway!.foregroundEvents.listen((id) {
          if (_enabled &&
              !_disposed &&
              _settings?.bearerToken.isNotEmpty == true)
            onForeground(id);
        }),
      );
    }
    try {
      if (!notificationsEnabled) {
        await gateway!.setEnabled(false);
        await _removeRegistration();
        onStatus('通知已关闭，后端 token 已注销');
        return;
      }
      await gateway!.initialize();
      await gateway!.setEnabled(true);
      final token = await gateway!.requestToken();
      if (token == null) {
        _enabled = false;
        await gateway!.setEnabled(false);
        await _removeRegistration();
        onStatus('通知权限未授权或 token 不可用；未登记后台推送');
        return;
      }
      await _register(token, gateway!.platform);
      onStatus('FCM 已注册（${settings.contactId}）；送达需真机验证');
    } catch (_) {
      onStatus('FCM 初始化/权限/注册失败，请检查 Firebase、系统权限和 APNs 后重试');
      rethrow;
    }
  });

  Future<void> _register(String token, String platform) async {
    final settings = _settings!;
    final previous = await store.loadPushRegistration();
    // Re-register idempotently: a server restart/reset may lose its token table.
    // Preserve the old installation registration until replacement is durable.
    if (previous != null && previous['base_url'] != settings.baseUrl) {
      throw const ApiException('仍有其他后端的推送记录，请连接原后端注销后再切换');
    }
    final id = await _repository!.registerPush(
      token,
      platform,
      settings.contactId,
    );
    // Persist a cleanup tombstone so interrupted rotation can be retried.
    final stale = <String>{
      ...?((previous?['stale_token_ids'] as List?)?.cast<String>()),
      if (previous != null && previous['token_id'] != id)
        previous['token_id'] as String,
    };
    final registration = <String, dynamic>{
      'token_id': id,
      'token': token,
      'platform': platform,
      'contact_id': settings.contactId,
      'base_url': settings.baseUrl,
      'stale_token_ids': stale.where((old) => old != id).toList(),
    };
    try {
      await store.savePushRegistration(registration);
    } catch (_) {
      if (id != previous?['token_id']) await _repository!.deletePush(id);
      rethrow;
    }
    await _cleanupStale(registration);
  }

  Future<void> _cleanupStale(Map<String, dynamic> registration) async {
    final stale = List<String>.from(
      registration['stale_token_ids'] as List? ?? const [],
    );
    for (final id in List<String>.from(stale)) {
      try {
        await _repository!.deletePush(id);
      } on ApiException catch (e) {
        // A's DELETE returns 404 if a previous retry already removed it.
        if (e.statusCode != 404) rethrow;
      }
      stale.remove(id);
      registration['stale_token_ids'] = List<String>.from(stale);
      await store.savePushRegistration(registration);
    }
  }

  Future<void> _removeRegistration() async {
    final previous = await store.loadPushRegistration();
    if (previous != null) {
      if (previous['base_url'] != _settings?.baseUrl) {
        throw const ApiException('仍有其他后端的推送记录，请连接原后端注销后再切换');
      }
      await _cleanupStale(previous);
      try {
        await _repository!.deletePush(previous['token_id'] as String);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
      await store.savePushRegistration(null);
    }
  }

  Future<void> unregister() => _serialize(() async {
    _enabled = false;
    await _removeRegistration();
    await gateway?.setEnabled(false);
    onStatus('设备 token 已注销');
  });

  Future<void> detach() => _serialize(() async {
    _enabled = false;
    await _removeRegistration();
    await gateway?.setEnabled(false);
    _repository = null;
    _settings = null;
  });

  Future<void> dispose() async {
    _disposed = true;
    _enabled = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _queue;
    await gateway?.dispose();
  }
}
