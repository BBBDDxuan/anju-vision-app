import 'dart:async';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'fixtures/safety_repository.dart';
import 'package:elder_safety_mobile/services/object_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/services/push_service.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';

class MemorySettingsStore implements SettingsStore, HouseholdStore {
  HouseholdData? householdData;
  bool failHouseholdSave = false;
  @override
  Future<HouseholdData?> loadHousehold() async => householdData == null
      ? null
      : HouseholdData.fromJson(householdData!.toJson());
  @override
  Future<void> saveHousehold(HouseholdData data) async {
    if (failHouseholdSave) throw const ApiException('档案保存失败');
    householdData = HouseholdData.fromJson(data.toJson());
  }

  AppSettings settings = const AppSettings();
  Map<String, dynamic>? registration;
  bool failSave = false;
  bool failLoad = false;
  @override
  Future<AppSettings> load() async {
    if (failLoad) throw const ApiException('安全存储不可用');
    return settings;
  }

  @override
  Future<void> save(AppSettings settings) async {
    if (failSave) throw const ApiException('存储失败');
    this.settings = settings;
  }

  @override
  Future<Map<String, dynamic>?> loadPushRegistration() async => registration;
  @override
  Future<void> savePushRegistration(Map<String, dynamic>? value) async {
    registration = value;
  }
}

class RecordingRepository extends FixtureSafetyRepository {
  final calls = <String>[];
  bool failDelete = false;
  bool failPreferences = false;
  bool failEvents = false;
  Completer<List<SafetyEvent>>? blockedEvents;
  int _tokens = 0;
  int eventRequests = 0;
  int closeCalls = 0;
  @override
  void close() {
    closeCalls++;
  }

  @override
  Future<String> registerPush(
    String token,
    String platform,
    String contactId,
  ) async {
    calls.add('register:$token:$platform:$contactId');
    return 'token-${++_tokens}';
  }

  @override
  Future<void> deletePush(String id) async {
    calls.add('delete:$id');
    if (failDelete) throw const ApiException('注销失败');
  }

  @override
  Future<FamilyPreferences> preferences() async {
    if (failPreferences) throw const ApiException('偏好读取失败');
    return super.preferences();
  }

  @override
  Future<List<SafetyEvent>> events() async {
    eventRequests++;
    if (blockedEvents != null) return blockedEvents!.future;
    if (failEvents) throw const ApiException('事件读取失败');
    return super.events();
  }
}

class FakePushGateway implements PushGateway {
  final tokens = StreamController<String>.broadcast();
  final opens = StreamController<String>.broadcast();
  final foreground = StreamController<String>.broadcast();
  String? initialEvent;
  String? token = 'fcm-initial';
  bool denied = false;
  int requests = 0;
  int initializations = 0;
  bool enabled = false;
  @override
  String get platform => 'android';
  @override
  Stream<String> get tokenRefreshes => tokens.stream;
  @override
  Stream<String> get openedEvents => opens.stream;
  @override
  Stream<String> get foregroundEvents => foreground.stream;
  @override
  Future<void> initialize() async {
    initializations++;
    if (initialEvent != null) {
      opens.add(initialEvent!);
      initialEvent = null;
    }
  }

  @override
  Future<String?> requestToken() async {
    requests++;
    if (denied) throw const ApiException('权限拒绝');
    return token;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  Future<void> dispose() async {
    await tokens.close();
    await opens.close();
    await foreground.close();
  }
}

Map<String, dynamic> eventJson({String id = 'event-1'}) => {
  'event_id': id,
  'device_id': 'device-1',
  'event_type': 'suspected_fall',
  'severity': 'critical',
  'confidence': .93,
  'occurred_at': '2026-10-28T01:00:00Z',
  'evidence_id': 'evidence-1',
  'review_status': 'completed',
  'review_summary': '请家属核实',
  'notification_status': 'sent',
  'acknowledgement_status': 'unacknowledged',
  'state': 'detected',
  'created_at': '2026-10-28T01:00:01Z',
};

// Deny unexpected calls so unit/widget tests never depend on a local backend.
http.Client emptyVideoClient() => MockClient((request) async {
  if (request.method == 'GET' && request.url.path == '/api/videos') {
    return http.Response(
      '{"videos":[]}',
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  throw StateError(
    'Unexpected video request: ${request.method} ${request.url.path}',
  );
});

ObjectApi emptyVideoApi(ObjectServiceConfig config) =>
    ObjectApi(config, client: emptyVideoClient());

// ObjectsScreen currently creates its own ObjectApi. Inject its HTTP client too,
// without altering production code or relying on Flutter's default HTTP 400 stub.
Future<void> withEmptyVideoHttp(Future<void> Function() body) =>
    http.runWithClient(body, emptyVideoClient);

Future<void> addFixtureMembers(
  SafetyController controller, [
  int count = 3,
]) async {
  for (var i = 0; i < count; i++) {
    await controller.addMember();
  }
}
