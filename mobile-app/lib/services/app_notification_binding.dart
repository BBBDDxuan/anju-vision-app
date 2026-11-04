import '../models/unified_alert.dart';
import 'android_notices.dart';
import 'notifications/alert_gate.dart';
import 'notifications/notification_service.dart';
import 'notifications/secure_notice_store.dart';

/// Connects B's sole alert stream to C's persistent gate and native presenter.
/// Operations are serialized across scope changes, including slow secure writes.
class AppNotificationBinding {
  AppNotificationBinding({
    required AndroidNotices android,
    required this.currentScope,
    required this.canPresent,
    NoticeStateStore? store,
  }) : _store = store ?? SecureNoticeStateStore() {
    _android = _ScopedPresenter(
      android,
      (scope) => !_disposed && scope == currentScope() && canPresent(scope),
    );
  }

  final String? Function() currentScope;
  final bool Function(String) canPresent;
  final NoticeStateStore _store;
  late final AndroidNotices _android;
  UnifiedNotificationService? _service;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  Future<List<UnifiedAlertNotice>> accept(AlertSyncSnapshot snapshot) {
    final next = _queue.then((_) async {
      if (_disposed || !snapshot.complete || snapshot.scope != currentScope())
        return <UnifiedAlertNotice>[];
      if (_service?.gate.scope != snapshot.scope) {
        _service = UnifiedNotificationService(
          gate: AlertNotificationGate(store: _store, scope: snapshot.scope),
          android: _android,
        );
      }
      final notices = await _service!.synchronize(
        snapshot.events.map((event) => event.details),
        historical: snapshot.initial,
        notificationsEnabled:
            snapshot.notificationsEnabled &&
            snapshot.active &&
            canPresent(snapshot.scope),
      );
      if (_disposed ||
          snapshot.scope != currentScope() ||
          !canPresent(snapshot.scope))
        return <UnifiedAlertNotice>[];
      return notices;
    });
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void dispose() => _disposed = true;
}

/// Delegates only display to the App's one initialized native bridge. Recheck
/// scope/permission preference after C's asynchronous durable deduplication.
class _ScopedPresenter extends AndroidNotices {
  _ScopedPresenter(this.delegate, this.allowed);
  final AndroidNotices delegate;
  final bool Function(String) allowed;
  @override
  Future<void> show(String eventId, {String? scope}) async {
    if (scope != null && allowed(scope))
      await delegate.show(eventId, scope: scope);
  }
}
