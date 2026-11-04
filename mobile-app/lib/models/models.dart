String field(Map<String, dynamic> json, String key, [String fallback = '']) =>
    json[key]?.toString() ?? fallback;

DateTime? dateField(Map<String, dynamic> json, String key) =>
    DateTime.tryParse(field(json, key));

// Current backend returns Review as an object; older fixtures may contain text.
String reviewText(Object? value) {
  if (value is String) return value;
  if (value is! Map) return '';
  final lines = <String>[];
  if (value['summary'] is String) lines.add(value['summary'] as String);
  for (final entry in {'observations': '观察', 'limitations': '局限'}.entries) {
    final items = value[entry.key];
    if (items is List) {
      lines.addAll(
        items.whereType<String>().map((item) => '${entry.value}：$item'),
      );
    }
  }
  if (value['uncertainty'] is String) lines.add('不确定性：${value['uncertainty']}');
  return lines.join('\n');
}

class SafetyDevice {
  const SafetyDevice({
    required this.id,
    required this.name,
    required this.online,
    this.lastSeenAt,
  });
  final String id;
  final String name;
  final bool online;
  final DateTime? lastSeenAt;

  factory SafetyDevice.fromJson(Map<String, dynamic> json) => SafetyDevice(
    id: field(json, 'device_id', field(json, 'id')),
    name: field(json, 'name'),
    online: json['online'] == true,
    lastSeenAt: dateField(json, 'last_seen_at'),
  );
}

class SafetyEvent {
  const SafetyEvent({
    required this.id,
    required this.deviceId,
    required this.eventType,
    required this.severity,
    required this.confidence,
    required this.occurredAt,
    required this.evidenceId,
    required this.reviewStatus,
    required this.reviewSummary,
    required this.notificationStatus,
    required this.acknowledgementStatus,
    required this.state,
    required this.createdAt,
    this.trackId,
    this.details = const {},
  });
  final String id;
  final String deviceId;
  final String eventType;
  final String severity;
  final double? confidence;
  final DateTime? occurredAt;
  final String? evidenceId;
  final String reviewStatus;
  final String reviewSummary;
  final String notificationStatus;
  final String acknowledgementStatus;
  final String state;
  final DateTime? createdAt;
  final String? trackId;
  final Map<String, dynamic> details;

  bool get fromVideo => details['source'] == 'uploaded_recording';
  bool get isUnified => details['unified_alert'] == true;
  int get revision => (details['revision'] as num?)?.toInt() ?? 0;
  bool get withdrawn => reviewStatus == 'withdrawn';
  bool get confirmedDanger => reviewStatus == 'confirmed' && !withdrawn;
  bool get acknowledged =>
      acknowledgementStatus == 'acknowledged' ||
      acknowledgementStatus == 'acked';
  bool get resolved => state == 'resolved';

  factory SafetyEvent.fromJson(Map<String, dynamic> json) => SafetyEvent(
    id: field(json, 'event_id'),
    deviceId: field(json, 'device_id'),
    eventType: field(json, 'event_type', 'unknown'),
    severity: field(json, 'severity', 'unknown'),
    confidence: (json['confidence'] as num?)?.toDouble(),
    occurredAt: dateField(json, 'occurred_at'),
    evidenceId: json['evidence_id']?.toString(),
    reviewStatus: field(json, 'review_status', 'unknown'),
    reviewSummary: reviewText(json['review_summary']),
    notificationStatus: field(json, 'notification_status', 'unknown'),
    acknowledgementStatus: field(json, 'acknowledgement_status', 'unknown'),
    state: field(json, 'state', 'unknown'),
    createdAt: dateField(json, 'created_at'),
    trackId: json['track_id']?.toString(),
    details: Map<String, dynamic>.from(json['details'] as Map? ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'event_id': id,
    'device_id': deviceId,
    'event_type': eventType,
    'severity': severity,
    'confidence': confidence,
    'occurred_at': occurredAt?.toIso8601String(),
    'evidence_id': evidenceId,
    'review_status': reviewStatus,
    'review_summary': reviewSummary,
    'notification_status': notificationStatus,
    'acknowledgement_status': acknowledgementStatus,
    'state': state,
    'created_at': createdAt?.toIso8601String(),
    'track_id': trackId,
    'details': details,
  };

  SafetyEvent withStatus({String? acknowledgement, String? newState}) =>
      SafetyEvent(
        id: id,
        deviceId: deviceId,
        eventType: eventType,
        severity: severity,
        confidence: confidence,
        occurredAt: occurredAt,
        evidenceId: evidenceId,
        reviewStatus: reviewStatus,
        reviewSummary: reviewSummary,
        notificationStatus: notificationStatus,
        acknowledgementStatus: acknowledgement ?? acknowledgementStatus,
        state: newState ?? state,
        createdAt: createdAt,
        trackId: trackId,
        details: details,
      );
}

class FamilyContact {
  const FamilyContact({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'contact_id': id, 'name': name};
}

class FamilyPreferences {
  const FamilyPreferences({
    required this.escalationSeconds,
    required this.notificationsEnabled,
    required this.contacts,
  });
  final int escalationSeconds;
  final bool notificationsEnabled;
  final List<FamilyContact> contacts;

  static const defaults = FamilyPreferences(
    escalationSeconds: 60,
    notificationsEnabled: true,
    contacts: [
      FamilyContact(id: 'primary', name: '主要联系人'),
      FamilyContact(id: 'backup', name: '备用联系人'),
    ],
  );

  factory FamilyPreferences.fromJson(Map<String, dynamic> json) =>
      FamilyPreferences(
        escalationSeconds: (json['escalation_seconds'] as num?)?.toInt() ?? 60,
        notificationsEnabled: json['notifications_enabled'] == true,
        contacts: (json['contacts'] as List<dynamic>? ?? []).map((value) {
          final item = Map<String, dynamic>.from(value as Map);
          return FamilyContact(
            id: field(item, 'contact_id'),
            name: field(item, 'name'),
          );
        }).toList(),
      );

  String contactName(String id) =>
      contacts
          .where((contact) => contact.id == id)
          .map((contact) => contact.name)
          .firstOrNull ??
      '';

  Map<String, dynamic> toJson() => {
    'escalation_seconds': escalationSeconds,
    'notifications_enabled': notificationsEnabled,
    'contacts': contacts.map((contact) => contact.toJson()).toList(),
  };
}

class EventFilter {
  const EventFilter({
    this.severity,
    this.state,
    this.from,
    this.to,
    this.query = '',
  });
  final String? severity;
  final String? state;
  final DateTime? from;
  final DateTime? to;
  final String query;

  List<SafetyEvent> apply(Iterable<SafetyEvent> events) {
    final needle = query.trim().toLowerCase();
    return events.where((event) {
      final time = event.occurredAt;
      return (severity == null || event.severity == severity) &&
          (state == null || event.state == state) &&
          (from == null || (time != null && !time.isBefore(from!))) &&
          (to == null || (time != null && time.isBefore(to!))) &&
          (needle.isEmpty ||
              '${event.id} ${event.deviceId} ${event.eventType}'
                  .toLowerCase()
                  .contains(needle));
    }).toList()..sort(
      (a, b) => (b.occurredAt ?? DateTime(1970)).compareTo(
        a.occurredAt ?? DateTime(1970),
      ),
    );
  }
}
