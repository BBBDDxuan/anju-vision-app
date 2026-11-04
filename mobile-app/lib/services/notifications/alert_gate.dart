import 'dart:async';
import 'dart:convert';

/// Opaque, backend-wide ID. Never deduplicate by title, timestamp or source ID.
bool isUnifiedAlertId(String value) =>
    value.length == 42 && RegExp(r'^a_[0-9a-f]{40}$').hasMatch(value);

/// Must match server APP_FCM_ORIGIN + '|default'. Contains no bearer token.
String notificationScope(String baseUrl, {String household = 'default'}) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      household != 'default') {
    throw const FormatException('Invalid notification backend scope');
  }
  final origin = uri
      .replace(path: '')
      .toString()
      .replaceFirst(RegExp(r'/$'), '');
  if (origin.length > 200)
    throw const FormatException('Notification backend scope too long');
  return origin + '|default';
}

/// Canonical, credential-free routing metadata, never an arbitrary URL.
bool isNotificationScope(String value) {
  if (!value.endsWith('|default')) return false;
  try {
    return notificationScope(
          value.substring(0, value.length - '|default'.length),
        ) ==
        value;
  } catch (_) {
    return false;
  }
}

class UnifiedAlertNotice {
  const UnifiedAlertNotice({
    required this.id,
    required this.source,
    required this.revision,
    required this.review,
    required this.handling,
    required this.notification,
  });
  final String id, source, review, handling, notification;
  final int revision;
  bool get eligible =>
      review == 'confirmed' &&
      handling == 'unacknowledged' &&
      !['skipped_history', 'cancelled'].contains(notification);

  static UnifiedAlertNotice? fromJson(Map<String, dynamic> json) {
    final id = json['id'], revision = json['revision'], source = json['source'];
    if (id is! String ||
        !isUnifiedAlertId(id) ||
        revision is! int ||
        revision < 1 ||
        !['live_camera', 'uploaded_recording'].contains(source))
      return null;
    return UnifiedAlertNotice(
      id: id,
      source: source as String,
      revision: revision,
      review: json['review_status'] as String? ?? '',
      handling: json['handling_status'] as String? ?? '',
      notification: json['notification_status'] as String? ?? '',
    );
  }
}

abstract interface class NoticeStateStore {
  Future<String?> read(String scope);
  Future<void> write(String scope, String value);
}

/// Background receipts use per-ID keys so a background isolate never rewrites
/// the foreground revision map (which could otherwise lose concurrent updates).
abstract interface class BackgroundNoticeReceipts {
  Future<bool> wasReceived(String scope, String id);
}

/// B owns list/changes requests and cursor transactions. C never starts polling.
/// Use one gate per backend+household. Persist before returning notices; a failed
/// write produces no notice and leaves the previous in-memory state untouched.
class AlertNotificationGate {
  AlertNotificationGate({required this.store, required this.scope});
  final NoticeStateStore store;
  final String scope;
  Map<String, dynamic>? _state;
  Future<void> _queue = Future<void>.value();

  Future<List<UnifiedAlertNotice>> accept(
    Iterable<Map<String, dynamic>> snapshots, {
    required bool historical,
    bool notificationsEnabled = true,
  }) {
    final copied = snapshots
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final next = _queue.then(
      (_) => _accept(copied, historical, notificationsEnabled),
    );
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<UnifiedAlertNotice>> _accept(
    List<Map<String, dynamic>> snapshots,
    bool historical,
    bool enabled,
  ) async {
    if (scope.isEmpty) throw StateError('Notification scope is required');
    if (_state == null) {
      final raw = await store.read(scope);
      if (raw == null) {
        _state = {'version': 1, 'seen': <String, dynamic>{}};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded['version'] != 1 ||
            decoded['seen'] is! Map)
          throw StateError(
            'Notification state is invalid; do not silently replay history',
          );
        _state = Map<String, dynamic>.from(decoded);
      }
    }
    final seen = Map<String, dynamic>.from(_state!['seen'] as Map);
    final ready = <UnifiedAlertNotice>[];
    for (final json in snapshots) {
      final notice = UnifiedAlertNotice.fromJson(json);
      if (notice == null)
        throw const FormatException('Invalid unified alert snapshot');
      final old = seen[notice.id];
      if (old is Map && (old['revision'] as int) >= notice.revision) continue;
      final remembered = old is Map ? old['consumed'] != false : false;
      final consumed =
          remembered ||
          (store is BackgroundNoticeReceipts &&
              await (store as BackgroundNoticeReceipts).wasReceived(
                scope,
                notice.id,
              ));
      if (!consumed && !historical && enabled && notice.eligible) {
        ready.add(notice);
      }
      // Pending candidates stay silent but may become confirmed later. History,
      // disabled notifications, handling and withdrawal permanently consume ID.
      final terminal =
          historical ||
          !enabled ||
          notice.eligible ||
          notice.handling == 'acknowledged' ||
          notice.handling == 'resolved' ||
          notice.review == 'withdrawn' ||
          ['skipped_history', 'cancelled'].contains(notice.notification);
      seen[notice.id] = {
        'revision': notice.revision,
        'consumed': consumed || terminal,
      };
    }
    final next = {'version': 1, 'seen': seen};
    await store.write(scope, jsonEncode(next));
    _state = next;
    return ready;
  }
}

/// Queue one click until B has authenticated and prepared its navigator.
/// A different backend/household must never consume an old notification.
class PendingAlertOpen {
  String? _scope, _id;
  void add({required String scope, required String id}) {
    if (!isUnifiedAlertId(id) || scope.isEmpty) return;
    _scope = scope;
    _id = id;
  }

  String? take(String scope) {
    if (_scope != scope) return null;
    final id = _id;
    _scope = null;
    _id = null;
    return id;
  }

  void clear() {
    _scope = null;
    _id = null;
  }
}
