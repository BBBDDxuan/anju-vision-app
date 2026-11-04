import 'dart:typed_data';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';

class FixtureSafetyRepository implements SafetyRepository {
  FixtureSafetyRepository() {
    final now = DateTime.now().toUtc();
    _events.addAll([
      _make(
        'fixture-fall',
        'suspected_fall',
        'critical',
        now.subtract(const Duration(minutes: 3)),
      ),
      _make(
        'fixture-inactivity',
        'help_requested',
        'warning',
        now.subtract(const Duration(hours: 2)),
      ),
      _make(
        'fixture-history',
        'device_offline',
        'info',
        now.subtract(const Duration(days: 1)),
      ).withStatus(acknowledgement: 'acknowledged', newState: 'resolved'),
      _make(
        'fixture-fire',
        'fire_detected',
        'critical',
        now.subtract(const Duration(minutes: 15)),
      ),
      _make(
        'fixture-smoke',
        'smoke_detected',
        'warning',
        now.subtract(const Duration(minutes: 45)),
      ),
    ]);
  }
  // Test-only data. Production controllers must explicitly receive this fixture.
  final List<SafetyEvent> _events = [];
  FamilyPreferences _preferences = FamilyPreferences.defaults;
  int _nextEvent = 1;
  Future<void> _commit(List<SafetyEvent> next) async {
    _events
      ..clear()
      ..addAll(next);
  }

  SafetyEvent _make(String id, String type, String severity, DateTime time) =>
      SafetyEvent(
        id: id,
        deviceId: 'living-room',
        eventType: type,
        severity: severity,
        confidence: 0.87,
        occurredAt: time,
        evidenceId: 'fixture-evidence',
        reviewStatus: 'completed',
        reviewSummary: type == 'suspected_fall'
            ? '【模拟说明】人物姿态接近地面且持续未起身，建议家属核实。此为预设演示，不代表真实事故。'
            : type == 'help_requested'
            ? '【模拟说明】检测到持续举手动作，可能在请求帮助。请联系家人核实。此为预设演示。'
            : type == 'fire_detected'
            ? '【模拟说明】画面出现明火候选。此为预设演示，不代表真实火灾。'
            : type == 'smoke_detected'
            ? '【模拟说明】画面出现烟雾候选。此为预设演示，不代表真实烟情。'
            : '【模拟说明】设备心跳曾中断，已完成处理。此为预设演示。',
        notificationStatus: 'skipped',
        acknowledgementStatus: 'unacknowledged',
        state: 'detected',
        createdAt: time,
      );
  Future<SafetyEvent> addEvent() async {
    final event = _make(
      'fixture-generated-${_nextEvent++}',
      'suspected_fall',
      'critical',
      DateTime.now().toUtc(),
    );
    await _commit([event, ..._events].take(200).toList());
    return event;
  }

  @override
  Future<bool> health() async => true;
  @override
  Future<List<SafetyDevice>> devices() async => [
    SafetyDevice(
      id: 'living-room',
      name: '客厅摄像头 · 模拟',
      online: true,
      lastSeenAt: DateTime.now().toUtc(),
    ),
    SafetyDevice(
      id: 'bedroom',
      name: '卧室传感器 · 模拟',
      online: false,
      lastSeenAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    ),
  ];
  @override
  Future<List<SafetyEvent>> events() async {
    return List.of(_events);
  }

  @override
  Future<SafetyEvent> event(String id) async {
    for (final value in _events) {
      if (value.id == id) return value;
    }
    throw const ApiException('模拟事件不存在', statusCode: 404);
  }

  @override
  Future<Uint8List> evidence(String id) async =>
      throw const ApiException('模拟模式展示示意图；真实模式通过认证接口读取截图');
  @override
  Future<void> acknowledge(String id) async {
    final value = await event(id);
    final next = List<SafetyEvent>.of(_events);
    next[next.indexOf(value)] = value.withStatus(
      acknowledgement: 'acknowledged',
      newState: value.resolved ? 'resolved' : 'acknowledged',
    );
    await _commit(next);
  }

  @override
  Future<void> resolve(String id) async {
    final value = await event(id);
    final next = List<SafetyEvent>.of(_events);
    next[next.indexOf(value)] = value.withStatus(
      acknowledgement: 'acknowledged',
      newState: 'resolved',
    );
    await _commit(next);
  }

  @override
  Future<FamilyPreferences> preferences() async => _preferences;
  @override
  Future<void> savePreferences(FamilyPreferences preferences) async {
    _preferences = preferences;
  }

  @override
  Future<String> registerPush(
    String token,
    String platform,
    String contactId,
  ) async => 'fixture-push-$contactId';
  @override
  Future<void> deletePush(String id) async {}
  @override
  void close() {}
}
