import 'models.dart';

/// Stable navigation identity shared with C; never contains credentials.
class AlertLocation {
  const AlertLocation({
    required this.backend,
    required this.household,
    required this.alertId,
    required this.source,
  });
  final String backend, household, alertId, source;
  String get scope => '${backend.replaceAll(RegExp(r'/+$'), '')}|$household';
  String get key => '$scope|$source|$alertId';
  Map<String, dynamic> toJson() => {
    'backend': backend,
    'household': household,
    'alert_id': alertId,
    'source': source,
  };
  static AlertLocation? tryParse(Map<String, dynamic> value) {
    final backend = value['backend'];
    final family = value['household'];
    final id = value['alert_id'];
    final source = value['source'];
    if ([backend, family, id, source].any(
      (v) =>
          v is! String ||
          v.isEmpty ||
          v.length > 2048 ||
          RegExp(r'[\x00-\x20\x7f]').hasMatch(v),
    ))
      return null;
    final uri = Uri.tryParse(backend as String);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path))
      return null;
    if (!['live_camera', 'uploaded_recording'].contains(source)) return null;
    return AlertLocation(
      backend: backend.replaceAll(RegExp(r'/+$'), ''),
      household: family as String,
      alertId: id as String,
      source: source as String,
    );
  }
}

/// Only emitted after a complete, successful business synchronization.
/// C owns notification deduplication and presentation, not another poller.
class AlertSyncSnapshot {
  const AlertSyncSnapshot({
    required this.backend,
    required this.household,
    required this.cursor,
    required this.initial,
    required this.events,
    required this.changed,
    required this.active,
    required this.notificationsEnabled,
  });
  final String backend, household;
  final int cursor;
  final bool initial, active, notificationsEnabled;
  final List<SafetyEvent> events, changed;
  bool get complete => true;
  String get scope => '$backend|$household';
  AlertLocation locationFor(SafetyEvent event) => AlertLocation(
    backend: backend,
    household: household,
    alertId: event.id,
    source: event.details['source'] as String,
  );
}

SafetyEvent unifiedAlertFromJson(Map<String, dynamic> json) {
  final id = json['id'];
  final source = json['source'];
  final revision = json['revision'];
  if (id is! String ||
      id.isEmpty ||
      !['live_camera', 'uploaded_recording'].contains(source) ||
      revision is! int ||
      revision < 1)
    throw const FormatException('Invalid unified alert identity');
  final evidence = (json['evidence'] as List? ?? [])
      .map((raw) => Map<String, dynamic>.from(raw as Map))
      .toList();
  final handling = field(json, 'handling_status', 'unknown');
  return SafetyEvent(
    id: id,
    deviceId: source == 'live_camera'
        ? field(json, 'camera_id')
        : 'video:${field(json, 'video_id')}',
    eventType: field(json, 'event_type', 'unknown'),
    severity: field(json, 'severity', 'unknown'),
    confidence: (json['confidence'] as num?)?.toDouble(),
    occurredAt: dateField(json, 'occurred_at'),
    createdAt: dateField(json, 'created_at'),
    evidenceId: evidence.isEmpty ? null : evidence.first['url']?.toString(),
    reviewStatus: field(json, 'review_status', 'unknown'),
    reviewSummary: field(json, 'review_reason'),
    notificationStatus: field(json, 'notification_status', 'unknown'),
    acknowledgementStatus: ['acknowledged', 'resolved'].contains(handling)
        ? 'acknowledged'
        : 'unacknowledged',
    state: handling,
    trackId: json['track_id']?.toString(),
    details: {
      ...json,
      'unified_alert': true,
      'evidence': evidence,
      'start_ms': json['video_offset_ms'],
      'end_ms': json['video_end_ms'],
    },
  );
}
