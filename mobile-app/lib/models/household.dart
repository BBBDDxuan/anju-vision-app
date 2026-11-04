import 'models.dart';
import 'camera_connection.dart';

class MemberBinding {
  const MemberBinding({
    required this.deviceId,
    required this.scope,
    this.trackId = '',
  });
  final String deviceId, scope, trackId;
  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'scope': scope,
    'track_id': trackId,
  };
  factory MemberBinding.fromJson(Map<String, dynamic> j) => MemberBinding(
    deviceId: field(j, 'device_id'),
    scope: field(j, 'scope'),
    trackId: field(j, 'track_id'),
  );
}

class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.number,
    this.name = '',
    this.relationship = '',
    this.notes = '',
    this.bindings = const [],
  });
  final String id, name, relationship, notes;
  final int number;
  final List<MemberBinding> bindings;
  String get displayName => name.trim().isEmpty ? '成员$number' : name.trim();
  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'relationship': relationship,
    'notes': notes,
    'bindings': bindings.map((e) => e.toJson()).toList(),
  };
  factory MemberProfile.fromJson(Map<String, dynamic> j) => MemberProfile(
    id: field(j, 'id'),
    number: (j['number'] as num?)?.toInt() ?? 1,
    name: field(j, 'name'),
    relationship: field(j, 'relationship'),
    notes: field(j, 'notes'),
    bindings: (j['bindings'] as List? ?? [])
        .map((e) => MemberBinding.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
  MemberProfile copyWith({
    String? name,
    String? relationship,
    String? notes,
    List<MemberBinding>? bindings,
  }) => MemberProfile(
    id: id,
    number: number,
    name: name ?? this.name,
    relationship: relationship ?? this.relationship,
    notes: notes ?? this.notes,
    bindings: bindings ?? this.bindings,
  );
}

class ObjectServiceConfig {
  const ObjectServiceConfig({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.token = '',
    this.useCloud = false,
  });
  final String baseUrl, token;
  final bool useCloud;
  Map<String, dynamic> toJson() => {
    'base_url': baseUrl,
    'token': token,
    'use_cloud': useCloud,
  };
  factory ObjectServiceConfig.fromJson(Map<String, dynamic> j) =>
      ObjectServiceConfig(
        baseUrl: field(j, 'base_url', 'http://127.0.0.1:8000'),
        token: field(j, 'token'),
        useCloud: j['use_cloud'] == true,
      );
}

class RecentObject {
  const RecentObject({
    required this.id,
    required this.name,
    required this.source,
    required this.recordedAt,
    this.imagePath = '',
    this.videoId = '',
    this.entityId = '',
    this.videoMs = 0,
    this.location = '',
    this.serviceUrl = '',
    this.score,
  });
  final String id,
      name,
      source,
      imagePath,
      videoId,
      entityId,
      location,
      serviceUrl;
  final DateTime recordedAt;
  final int videoMs;
  final double? score;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source,
    'recorded_at': recordedAt.toIso8601String(),
    'image_path': imagePath,
    'video_id': videoId,
    'entity_id': entityId,
    'video_ms': videoMs,
    'location': location,
    'service_url': serviceUrl,
    'score': score,
  };
  factory RecentObject.fromJson(Map<String, dynamic> j) => RecentObject(
    id: field(j, 'id'),
    name: field(j, 'name'),
    source: field(j, 'source'),
    recordedAt:
        dateField(j, 'recorded_at') ?? DateTime.fromMillisecondsSinceEpoch(0),
    imagePath: field(j, 'image_path'),
    videoId: field(j, 'video_id'),
    entityId: field(j, 'entity_id'),
    videoMs: (j['video_ms'] as num?)?.toInt() ?? 0,
    location: field(j, 'location'),
    serviceUrl: field(j, 'service_url'),
    score: (j['score'] as num?)?.toDouble(),
  );
}

class HouseholdData {
  const HouseholdData({
    required this.members,
    this.nextMemberNumber = 4,
    this.eventMembers = const {},
    this.localEvents = const [],
    this.recentObjects = const [],
    this.searches = const [],
    this.objects = const ObjectServiceConfig(),
    this.familyPreferences = FamilyPreferences.defaults,
    this.camera = const CameraConnection(),
  });
  final List<MemberProfile> members;
  final int nextMemberNumber;
  final Map<String, String> eventMembers;
  final List<SafetyEvent> localEvents;
  final List<RecentObject> recentObjects;
  final List<String> searches;
  final ObjectServiceConfig objects;
  final FamilyPreferences familyPreferences;
  final CameraConnection camera;
  factory HouseholdData.initial() =>
      HouseholdData(members: const [], nextMemberNumber: 1);
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'members': members.map((e) => e.toJson()).toList(),
    'next_member_number': nextMemberNumber,
    'event_members': eventMembers,
    'local_events': localEvents.map((e) => e.toJson()).toList(),
    'recent_objects': recentObjects.map((e) => e.toJson()).toList(),
    'searches': searches,
    'objects': objects.toJson(),
    'family_preferences': familyPreferences.toJson(),
    'camera': camera.toJson(),
  };
  factory HouseholdData.fromJson(Map<String, dynamic> j) => HouseholdData(
    members: (j['members'] as List? ?? [])
        .map((e) => MemberProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    nextMemberNumber: (j['next_member_number'] as num?)?.toInt() ?? 4,
    eventMembers: Map<String, String>.from(j['event_members'] as Map? ?? {}),
    localEvents: (j['local_events'] as List? ?? [])
        .map((e) => SafetyEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    recentObjects: (j['recent_objects'] as List? ?? [])
        .map((e) => RecentObject.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.source == 'video')
        .toList(),
    searches: (j['searches'] as List? ?? [])
        .whereType<String>()
        .take(10)
        .toList(),
    familyPreferences: j['family_preferences'] is Map
        ? FamilyPreferences.fromJson(
            Map<String, dynamic>.from(j['family_preferences']),
          )
        : FamilyPreferences.defaults,
    objects: ObjectServiceConfig.fromJson(
      Map<String, dynamic>.from(j['objects'] as Map? ?? {}),
    ),
    camera: CameraConnection.fromJson(
      Map<String, dynamic>.from(j['camera'] as Map? ?? {}),
    ),
  );
  HouseholdData copyWith({
    List<MemberProfile>? members,
    int? nextMemberNumber,
    Map<String, String>? eventMembers,
    List<SafetyEvent>? localEvents,
    List<RecentObject>? recentObjects,
    List<String>? searches,
    ObjectServiceConfig? objects,
    FamilyPreferences? familyPreferences,
    CameraConnection? camera,
  }) => HouseholdData(
    members: members ?? this.members,
    nextMemberNumber: nextMemberNumber ?? this.nextMemberNumber,
    eventMembers: eventMembers ?? this.eventMembers,
    localEvents: localEvents ?? this.localEvents,
    recentObjects: recentObjects ?? this.recentObjects,
    searches: searches ?? this.searches,
    objects: objects ?? this.objects,
    familyPreferences: familyPreferences ?? this.familyPreferences,
    camera: camera ?? this.camera,
  );
}

bool isPersonEvent(SafetyEvent e) => {
  'suspected_fall',
  'help_requested',
  'long_absence',
  'pose_observation',
}.contains(e.eventType);
bool isRiskEvent(SafetyEvent e) =>
    {'fire_detected', 'sparks_detected'}.contains(e.eventType);
