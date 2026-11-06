import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'services/members_api.dart';
import 'package:flutter/foundation.dart';
import 'models/models.dart';
import 'models/unified_alert.dart';
import 'models/household.dart';
import 'models/camera_connection.dart';
import 'services/api.dart';
import 'services/object_api.dart';
import 'services/push_service.dart';
import 'services/notifications/alert_gate.dart' as native_notices;
import 'services/settings_store.dart';
import 'ui/widgets.dart' show eventTypeLabel;

class EventNotice {
  const EventNotice(this.eventId, this.message);
  final String eventId;
  final String message;
}

typedef RepositoryFactory = SafetyRepository Function(AppSettings settings);
typedef ObjectApiFactory = ObjectApi Function(ObjectServiceConfig config);

class SafetyController extends ChangeNotifier {
  SafetyController({
    required this.store,
    PushGateway? gateway,
    RepositoryFactory? repositoryFactory,
    ObjectApiFactory? videoApiFactory,
    MembersApi Function(AppSettings)? membersApiFactory,
  }) : _membersFactory = membersApiFactory,
       _videoFactory =
           videoApiFactory ??
           ((config) => ObjectApi(config, timeout: const Duration(seconds: 8))),
       _explicitRepository = repositoryFactory != null,
       _factory =
           repositoryFactory ??
           ((settings) => UnifiedHttpSafetyRepository(
             baseUrl: settings.baseUrl,
             bearerToken: settings.bearerToken,
           )) {
    push = PushCoordinator(
      store: store,
      gateway: gateway,
      onOpen: (id) {
        if (_disposed) return;
        if (usesUnifiedBackend) {
          final scope = notificationScope;
          if (scope != null) unawaited(openScopedAlert(scope, id));
        } else {
          openEvents.add(id);
        }
      },
      onForeground: (id) {
        if (usesUnifiedBackend) {
          if (!_disposed) unawaited(refresh());
          return;
        }
        if (!_disposed &&
            _active &&
            preferences.notificationsEnabled &&
            _announced.add('$serviceScope|$id')) {
          notices.add(EventNotice(id, '收到新的安全事件，请及时查看'));
          unawaited(refresh());
        }
      },
      onStatus: (value) {
        pushStatus = value;
        _notify();
      },
    );
  }
  final SettingsStore store;
  final RepositoryFactory _factory;
  final ObjectApiFactory _videoFactory;
  final MembersApi Function(AppSettings)? _membersFactory;
  final bool _explicitRepository;
  late final PushCoordinator push;
  final notices = StreamController<EventNotice>.broadcast();
  final openEvents = StreamController<String>.broadcast();
  final alertSnapshots = StreamController<AlertSyncSnapshot>.broadcast();
  final alertOpens = StreamController<AlertLocation>.broadcast();
  final List<AlertLocation> _pendingAlertOpens = [];
  UnifiedAlertSynchronizer? _alertSync;
  final _pendingScopedOpen = native_notices.PendingAlertOpen();
  int _openRequest = 0;
  String? get notificationScope {
    if (_disposed || _repository == null || settings.bearerToken.isEmpty)
      return null;
    try {
      return native_notices.notificationScope(settings.baseUrl);
    } catch (_) {
      return null;
    }
  }

  bool canPresentNotifications(String scope) =>
      !_disposed &&
      !configuring &&
      _active &&
      notificationScope == scope &&
      _preferencesLoaded &&
      preferences.notificationsEnabled;

  /// Native/FCM clicks provide a scoped ID; fetch its real source before routing.
  Future<void> openScopedAlert(String scope, String id) async {
    if (_disposed ||
        !native_notices.isNotificationScope(scope) ||
        !native_notices.isUnifiedAlertId(id))
      return;
    _pendingScopedOpen.add(scope: scope, id: id);
    await _consumeScopedOpen();
  }

  Future<void> _consumeScopedOpen() async {
    final scope = notificationScope;
    if (!initialized || configuring || scope == null || !usesUnifiedBackend)
      return;
    final id = _pendingScopedOpen.take(scope);
    if (id == null) return;
    final request = ++_openRequest, generation = _generation;
    try {
      final event = await loadEvent(id);
      if (_disposed ||
          request != _openRequest ||
          generation != _generation ||
          scope != notificationScope)
        return;
      final source = event.details['source'];
      if (!['live_camera', 'uploaded_recording'].contains(source)) return;
      openAlert(
        AlertLocation(
          backend: serviceScope,
          household: 'default',
          alertId: event.id,
          source: source as String,
        ),
      );
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = '通知对应的告警暂时无法读取，请检查连接后在消息中重试';
        _notify();
      }
    }
  }

  bool get usesUnifiedBackend =>
      !_explicitRepository || _repository is UnifiedAlertRepository;
  String get alertScope => '$serviceScope|default';
  bool locationMatches(AlertLocation location) => location.scope == alertScope;
  void openAlert(AlertLocation location) {
    if (_disposed) return;
    _pendingAlertOpens.add(location);
    if (_pendingAlertOpens.length > 20) _pendingAlertOpens.removeAt(0);
    alertOpens.add(location);
  }

  List<AlertLocation> takePendingAlertOpens() {
    final result = List<AlertLocation>.of(_pendingAlertOpens);
    _pendingAlertOpens.clear();
    return result;
  }

  AppSettings settings = const AppSettings();
  FamilyPreferences preferences = FamilyPreferences.defaults;
  HouseholdData household = HouseholdData.initial();
  String? householdWarning;
  bool _householdWritable = true;
  Future<void> _householdQueue = Future.value();
  SafetyRepository? _repository;
  SafetyRepository get repository {
    if (_repository == null) throw const ApiException('请先完成连接设置');
    return _repository!;
  }

  ObjectApi? _videoApi;
  String? videoError;
  List<SafetyEvent> _liveEvents = [], _videoEvents = [];
  final Set<String> _baselines = {};
  List<SafetyDevice> devices = [];
  List<SafetyEvent> events = [];
  String? error;
  String? preferencesError;
  String? storageWarning;
  String pushStatus = '尚未初始化';
  DateTime? lastSync;
  bool loading = false;
  bool initialized = false;
  bool configuring = false;
  bool _refreshing = false;
  bool _preferencesLoaded = false;
  bool _disposed = false;
  bool _active = true;
  int _generation = 0;
  final Set<String> _seen = {};
  final Set<String> _announced = {};
  Timer? _timer;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      try {
        settings = await store.load();
      } catch (_) {
        storageWarning = '安全存储不可用；本次连接设置可能无法保存。';
        settings = const AppSettings();
      }
      if (_disposed) return;
      await _loadHousehold();
      if (!_explicitRepository) await _migrateUnifiedConnection();
      _resetVideoApi();
      preferences = household.familyPreferences;
      if (settings.validationError == null &&
          (settings.bearerToken.isNotEmpty || _explicitRepository)) {
        _repository = _factory(settings);
      } else {
        error = settings.validationError;
      }
      await _prepareAlertSync();
      await Future.wait([
        if (_repository != null) _loadPreferences(),
        refresh(),
      ]);
      await _configurePush();
      await refreshMembers();
      _startPolling();
    } catch (_) {
      error = '初始化失败，请检查安全存储或连接设置后重试';
    } finally {
      initialized = true;
      _notify();
      unawaited(_consumeScopedOpen());
    }
  }

  Future<void> _loadPreferences() async {
    final generation = _generation;
    final current = repository;
    try {
      final updated = await current.preferences();
      if (_disposed || generation != _generation) return;
      preferences = updated;
      _preferencesLoaded = true;
      preferencesError = null;
    } catch (value) {
      if (_disposed || generation != _generation) return;
      _preferencesLoaded = false;
      preferencesError = '家庭偏好未同步：$value';
    }
  }

  Future<void> _configurePush() async {
    if (_disposed) return;
    if (_repository == null) {
      pushStatus = '安全后端未启用；录像事件在 App 前台刷新提醒';
      _notify();
      return;
    }
    try {
      await push.configure(
        repository,
        settings,
        _preferencesLoaded && preferences.notificationsEnabled,
      );
    } catch (_) {
      // Push failure does not hide usable devices/events or block polling.
    }
  }

  void _resetVideoApi() {
    _videoApi?.close();
    try {
      _videoApi = _videoFactory(household.objects);
      videoError = null;
    } catch (e) {
      _videoApi = null;
      videoError = '$e';
    }
  }

  void _acceptEvents(String source, List<SafetyEvent> updated) {
    if (_baselines.contains(source) &&
        _active &&
        preferences.notificationsEnabled &&
        (source != 'live' || _preferencesLoaded)) {
      for (final event in updated) {
        if (!_seen.contains('${eventScope(event)}|${event.id}') &&
            !event.acknowledged &&
            !event.resolved &&
            _announced.add('${eventScope(event)}|${event.id}')) {
          notices.add(
            EventNotice(
              event.id,
              '${event.fromVideo ? '录像分析' : '实时监护'} · ${eventTypeLabel(event.eventType)}',
            ),
          );
        }
      }
    }
    _seen.addAll(updated.map((e) => '${eventScope(e)}|${e.id}'));
    _baselines.add(source);
  }

  void _mergeEvents() {
    events = const EventFilter().apply(
      [
        ..._liveEvents,
        ..._videoEvents,
        ...household.localEvents.where((e) => e.details['image_path'] == null),
      ].where((e) => e.eventType != 'smoke_detected'),
    );
  }

  Future<void> refresh() async {
    unawaited(refreshMembers());
    if (usesUnifiedBackend) return _refreshUnified();
    if (_refreshing || configuring || _disposed) return;
    _refreshing = true;
    loading = true;
    _notify();
    final generation = _generation;
    final current = _repository, videos = _videoApi;
    bool valid() => !_disposed && generation == _generation;
    try {
      // Each source publishes independently, so an unavailable camera service
      // does not delay or discard already available uploaded-video alerts.
      await Future.wait([
        if (current != null)
          (() async {
            try {
              final result = await Future.wait<dynamic>([
                current.devices(),
                current.events(),
              ]);
              if (!valid()) return;
              devices = result[0] as List<SafetyDevice>;
              _liveEvents = result[1] as List<SafetyEvent>;
              _acceptEvents('live', _liveEvents);
              error = null;
              lastSync = DateTime.now();
            } catch (e) {
              if (valid()) error = '$e';
            }
            if (valid()) {
              _mergeEvents();
              _notify();
            }
          })(),
        if (videos != null)
          (() async {
            try {
              final updated = await videos.safetyEvents();
              if (!valid()) return;
              _videoEvents = updated;
              _acceptEvents('video', updated);
              videoError = videos.safetyWarnings.isEmpty
                  ? null
                  : videos.safetyWarnings.join('；');
              lastSync = DateTime.now();
            } catch (e) {
              if (valid()) videoError = '$e';
            }
            if (valid()) {
              _mergeEvents();
              _notify();
            }
          })(),
      ]);
    } finally {
      if (valid()) {
        _refreshing = false;
        loading = false;
        _notify();
      }
    }
  }

  Future<void> _migrateUnifiedConnection() async {
    if (settings.connectionVersion < 2) {
      final oldVideo = household.objects;
      var url = oldVideo.baseUrl;
      var token = oldVideo.token;
      final videoUri = Uri.tryParse(url),
          oldUri = Uri.tryParse(settings.baseUrl);
      if (token.isEmpty &&
          videoUri?.host == '127.0.0.1' &&
          oldUri != null &&
          oldUri.host != '127.0.0.1') {
        url = oldUri
            .replace(port: oldUri.port == 8010 ? 8000 : oldUri.port)
            .toString();
      }
      settings = settings.copyWith(
        baseUrl: url.replaceAll(RegExp(r'/+$'), ''),
        bearerToken: token,
        connectionVersion: 2,
      );
      storageWarning = '已迁移为单一后端地址，请在连接服务核对并填写统一访问令牌；旧 8010 用户令牌未自动复用。';
      try {
        await store.save(settings);
      } catch (_) {
        storageWarning = '统一连接迁移未保存，请重新保存连接设置。';
      }
    }
    household = household.copyWith(
      objects: ObjectServiceConfig(
        baseUrl: settings.baseUrl,
        token: settings.bearerToken,
        useCloud: household.objects.useCloud,
      ),
    );
  }

  Future<void> _prepareAlertSync() async {
    _alertSync = null;
    final current = _repository;
    if (current is! UnifiedAlertRepository) return;
    if (household.objects.baseUrl != settings.baseUrl ||
        household.objects.token != settings.bearerToken) {
      household = household.copyWith(
        objects: ObjectServiceConfig(
          baseUrl: settings.baseUrl,
          token: settings.bearerToken,
          useCloud: household.objects.useCloud,
        ),
      );
      _resetVideoApi();
    }
    final syncStore = store is AlertSyncStore ? store as AlertSyncStore : null;
    final scope = '${current.backendUrl}|default';
    final sync = UnifiedAlertSynchronizer(
      current,
      persist: syncStore == null
          ? null
          : (value) => syncStore.saveAlertSync(scope, value),
    );
    _alertSync = sync;
    if (syncStore != null) {
      try {
        sync.restore(await syncStore.loadAlertSync(scope));
      } catch (_) {
        storageWarning = '告警缓存读取失败，将重新进行完整同步。';
      }
    }
    if (sync != _alertSync || _disposed) return;
    _setUnifiedEvents(sync.events);
  }

  void _setUnifiedEvents(List<SafetyEvent> updated) {
    _liveEvents = updated.where((e) => !e.fromVideo).toList();
    _videoEvents = updated.where((e) => e.fromVideo).toList();
    _mergeEvents();
  }

  Future<void> _refreshUnified() async {
    if (_refreshing || configuring || _disposed) return;
    final current = _repository, sync = _alertSync;
    if (current is! UnifiedAlertRepository || sync == null) {
      error = '请在“我的 → 连接服务”填写统一后端地址和访问令牌';
      _notify();
      return;
    }
    _refreshing = true;
    loading = true;
    _notify();
    final generation = _generation;
    bool valid() =>
        !_disposed && generation == _generation && sync == _alertSync;
    try {
      await Future.wait([
        (() async {
          try {
            final result = await sync.synchronize();
            if (!valid()) return;
            _setUnifiedEvents(sync.events);
            error = null;
            lastSync = DateTime.now();
            alertSnapshots.add(
              AlertSyncSnapshot(
                backend: serviceScope,
                household: 'default',
                cursor: result.cursor,
                initial: result.initial,
                events: List.unmodifiable(events.where((e) => e.isUnified)),
                changed: result.changed,
                active: _active,
                notificationsEnabled:
                    _preferencesLoaded && preferences.notificationsEnabled,
              ),
            );
          } catch (e) {
            if (valid()) error = '$e';
          }
        })(),
        (() async {
          try {
            final updated = await current.devices();
            if (valid()) devices = updated;
          } catch (_) {
            /* Device heartbeat failures cannot erase authoritative alerts. */
          }
        })(),
      ]);
    } finally {
      if (valid()) {
        _refreshing = false;
        loading = false;
        _notify();
      }
    }
  }

  void _startPolling() {
    _timer?.cancel();
    if (_active && !_disposed) {
      _timer = Timer.periodic(Duration(seconds: settings.pollSeconds), (_) {
        unawaited(refresh());
      });
    }
  }

  void setActive(bool active) {
    _active = active;
    if (!active) {
      _timer?.cancel();
      return;
    }
    _startPolling();
    unawaited(refresh());
  }

  Future<void> applyConnection(AppSettings next) async {
    final invalid = next.validationError;
    if (invalid != null) throw ApiException(invalid);
    if (configuring) throw const ApiException('正在保存设置，请稍候');
    configuring = true;
    _generation++;
    _resetMemberConnection();
    _refreshing = false;
    loading = false;
    _timer?.cancel();
    _notify();
    SafetyRepository? candidate;
    var committed = false;
    try {
      candidate = (next.bearerToken.isNotEmpty || _explicitRepository)
          ? _factory(next)
          : null;
      // A failed delete preserves the old configuration, preventing an orphan token.
      if (_repository != null) await push.detach();
      await store.save(next);
      _repository?.close();
      settings = next;
      if (!_explicitRepository || candidate is UnifiedAlertRepository) {
        household = household.copyWith(
          objects: ObjectServiceConfig(
            baseUrl: next.baseUrl,
            token: next.bearerToken,
            useCloud: household.objects.useCloud,
          ),
        );
        _resetVideoApi();
      }
      _repository = candidate;
      committed = true;
      storageWarning = null;
      devices = [];
      _liveEvents = [];
      if (usesUnifiedBackend) _videoEvents = [];
      await _prepareAlertSync();
      _baselines.remove('live');
      _mergeEvents();
      lastSync = null;
      preferences = household.familyPreferences;
      _preferencesLoaded = false;
      if (_repository != null) await _loadPreferences();
    } catch (_) {
      if (!committed) candidate?.close();
      // Reattach the old connection when saving the new settings fails.
      if (!committed) await _configurePush();
      rethrow;
    } finally {
      configuring = false;
      _notify();
      _startPolling();
    }
    await refresh();
    await refreshMembers();
    await _configurePush();
    await _consumeScopedOpen();
  }

  Future<void> saveFamilyPreferences(FamilyPreferences next) async {
    if (next.escalationSeconds < 5 || next.escalationSeconds > 86400) {
      throw const ApiException('备用联系人提醒延迟需为 5–86400 整数秒');
    }
    final generation = _generation;
    final current = _repository;
    if (current == null) {
      await _updateHousehold((data) => data.copyWith(familyPreferences: next));
      preferences = next;
      preferencesError = null;
      _notify();
      return;
    }
    await current.savePreferences(next);
    // Read back from the server; don't claim saved preferences based on a button click.
    final updated = await current.preferences();
    if (_disposed || generation != _generation) return;
    preferences = updated;
    _preferencesLoaded = true;
    preferencesError = null;
    _notify();
    await _configurePush();
  }

  Future<void> retryPush() async {
    if (usesUnifiedBackend) {
      await _loadPreferences();
      await _configurePush();
      return;
    }
    await _loadPreferences();
    if (!_preferencesLoaded) throw ApiException(preferencesError!);
    await push.configure(
      repository,
      settings,
      preferences.notificationsEnabled,
    );
    _notify();
  }

  bool get usesSharedMembers => !_explicitRepository || _membersFactory != null;
  List<MemberProfile>? _remoteMembers;
  MembersApi? _membersApi;
  String? memberSyncError;
  Map<String, dynamic> faceStatus = const {};
  bool memberSyncing = false, memberBackendAvailable = false;
  DateTime? _memberChecked;
  int _memberMutation = 0;
  List<MemberProfile> get members => usesSharedMembers
      ? (_remoteMembers ?? household.sharedMembers[serviceScope] ?? const [])
      : household.members;
  List<MemberProfile> get legacyMembers => usesSharedMembers
      ? household.members
            .where(
              (m) => !members.any(
                (shared) =>
                    shared.id == household.memberImports[serviceScope]?[m.id],
              ),
            )
            .toList()
      : const [];
  bool get canEditMembers =>
      !configuring && (!usesSharedMembers || memberBackendAvailable);
  void _resetMemberConnection() {
    _membersApi?.close();
    _membersApi = null;
    _remoteMembers = null;
    memberBackendAvailable = false;
    memberSyncing = false;
    memberSyncError = null;
    faceStatus = const {};
    _memberChecked = null;
    ++_memberMutation;
  }

  MembersApi _requireMembersApi() {
    if (!usesSharedMembers ||
        configuring ||
        settings.bearerToken.isEmpty ||
        _disposed)
      throw const ApiException('请先连接电脑后端');
    return _membersApi ??= (_membersFactory ?? MembersApi.new)(settings);
  }

  Future<void> _acceptRemoteMembers(
    List<MemberProfile> value,
    int generation, {
    int? mutation,
  }) async {
    if (_disposed ||
        generation != _generation ||
        (mutation != null && mutation != _memberMutation))
      return;
    _remoteMembers = value;
    memberBackendAvailable = true;
    memberSyncError = null;
    final scope = serviceScope;
    try {
      await _updateHousehold((data) {
        if (_disposed ||
            generation != _generation ||
            (mutation != null && mutation != _memberMutation))
          throw const ApiException('档案已更新，请重新刷新');
        return data.copyWith(
          sharedMembers: {...data.sharedMembers, scope: value},
        );
      });
    } catch (_) {
      if (!_disposed && generation == _generation) {
        memberSyncError = '电脑档案已更新，本机离线缓存未保存';
        _notify();
      }
    }
  }

  Future<void> refreshMembers({bool force = false}) async {
    if (!usesSharedMembers ||
        configuring ||
        _disposed ||
        settings.bearerToken.isEmpty ||
        memberSyncing)
      return;
    if (!force &&
        _memberChecked != null &&
        DateTime.now().difference(_memberChecked!) <
            const Duration(seconds: 30))
      return;
    final generation = _generation, mutation = _memberMutation;
    memberSyncing = true;
    _memberChecked = DateTime.now();
    _notify();
    try {
      final api = _requireMembersApi();
      final value = await api.members();
      if (_disposed || generation != _generation || mutation != _memberMutation)
        return;
      await _acceptRemoteMembers(value, generation, mutation: mutation);
      try {
        final status = await api.status();
        if (!_disposed &&
            generation == _generation &&
            mutation == _memberMutation)
          faceStatus = status;
      } catch (_) {
        if (!_disposed && generation == _generation)
          faceStatus = const {'ready': false};
      }
    } catch (e) {
      if (!_disposed &&
          generation == _generation &&
          mutation == _memberMutation) {
        memberBackendAvailable = false;
        memberSyncError = '$e';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        memberSyncing = false;
        _notify();
      }
    }
  }

  String _newMemberId() {
    final random = Random.secure();
    return 'm-' +
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
  }

  Future<void> _saveRemoteMember(MemberProfile value) async {
    final api = _requireMembersApi(), generation = _generation;
    ++_memberMutation;
    final saved = await api.save(value);
    if (_disposed || generation != _generation) return;
    ++_memberMutation;
    final updated = [...members.where((m) => m.id != saved.id), saved]
      ..sort((a, b) => a.number.compareTo(b.number));
    await _acceptRemoteMembers(updated, generation);
  }

  Future<void> importLegacyMembers() async {
    final generation = _generation, scope = serviceScope;
    for (final old in List<MemberProfile>.of(legacyMembers)) {
      if (_disposed || generation != _generation)
        throw const ApiException('后端连接已改变，请重新选择');
      final id = household.memberImports[scope]?[old.id] ?? _newMemberId();
      // Persist the import identity BEFORE sending: retries cannot create another person.
      await _updateHousehold(
        (data) => data.copyWith(
          memberImports: {
            ...data.memberImports,
            scope: {...?data.memberImports[scope], old.id: id},
          },
        ),
      );
      if (_disposed || generation != _generation)
        throw const ApiException('后端连接已改变，请重新选择');
      if (members.any((m) => m.id == id)) continue;
      await _saveRemoteMember(
        MemberProfile(
          id: id,
          number: members.length + 1,
          name: old.name,
          relationship: old.relationship,
          notes: old.notes,
          bindings: old.bindings,
        ),
      );
    }
  }

  Future<void> enrollMemberFace(
    String id,
    Uint8List image, {
    required bool consent,
  }) async {
    final member = memberById(id);
    if (member == null) throw const ApiException('成员档案已不存在');
    final api = _requireMembersApi(), generation = _generation;
    ++_memberMutation;
    await api.enroll(member, image, consent: consent);
    if (_disposed || generation != _generation) return;
    final mutation = ++_memberMutation;
    final updated = await api.members();
    if (!_disposed && generation == _generation && mutation == _memberMutation)
      await _acceptRemoteMembers(updated, generation, mutation: mutation);
  }

  Future<Map<String, dynamic>> recognizeMemberFaces(Uint8List image) async {
    final api = _requireMembersApi(), generation = _generation;
    final result = await api.recognize(image);
    if (_disposed || generation != _generation)
      throw const ApiException('后端连接已改变，请重新试识别');
    return result;
  }

  Future<void> clearMemberFaces(String id) async {
    final api = _requireMembersApi(), generation = _generation;
    ++_memberMutation;
    await api.clearFaces(id);
    if (_disposed || generation != _generation) return;
    final mutation = ++_memberMutation;
    // A successful DELETE revokes cached identities even if the next GET fails.
    await _acceptRemoteMembers(
      members
          .map(
            (member) => member.id == id
                ? member.copyWith(
                    faceSampleCount: 0,
                    revision: member.revision + 1,
                  )
                : member,
          )
          .toList(),
      generation,
      mutation: mutation,
    );
    final updated = await api.members();
    if (!_disposed && generation == _generation && mutation == _memberMutation)
      await _acceptRemoteMembers(updated, generation, mutation: mutation);
  }

  String get serviceScope => settings.baseUrl.replaceAll(RegExp(r'/+$'), '');
  bool isLocalEvent(String id) => household.localEvents.any((e) => e.id == id);
  String eventScope(SafetyEvent event) => event.isUnified
      ? serviceScope
      : isLocalEvent(event.id)
      ? 'phone-local'
      : event.fromVideo
      ? event.details['source_url'].toString()
      : serviceScope;
  String eventAssociationKey(SafetyEvent event) =>
      '${eventScope(event)}|${event.id}';
  MemberProfile? memberById(String id) =>
      members.where((e) => e.id == id).firstOrNull;
  Future<void> _loadHousehold() async {
    final current = store;
    try {
      if (current is HouseholdStore)
        household =
            await (current as HouseholdStore).loadHousehold() ??
            HouseholdData.initial();
      _mergeEvents();
      _householdWritable = true;
    } catch (_) {
      householdWarning = '本机成员档案暂时无法读取，已显示临时档案；为保护原数据，暂不可保存修改。';
      _householdWritable = false;
    }
  }

  Future<void> _updateHousehold(
    HouseholdData Function(HouseholdData) transform,
  ) {
    final operation = _householdQueue.then((_) async {
      if (!_householdWritable) throw const ApiException('成员档案存储不可用，请重新启动后重试');
      final next = transform(household);
      final current = store;
      if (current is HouseholdStore)
        await (current as HouseholdStore).saveHousehold(next);
      if (_disposed) return;
      household = next;
      _mergeEvents();
      _notify();
    });
    _householdQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> addMember() async {
    if (usesSharedMembers) {
      await _saveRemoteMember(
        MemberProfile(
          id: _newMemberId(),
          number:
              members.fold<int>(0, (v, m) => v > m.number ? v : m.number) + 1,
        ),
      );
      return;
    }
    await _updateHousehold((data) {
      final number = data.nextMemberNumber;
      return data.copyWith(
        members: [
          ...data.members,
          MemberProfile(id: 'member-$number', number: number),
        ],
        nextMemberNumber: number + 1,
      );
    });
  }

  Future<void> saveMember(MemberProfile member) async {
    if (usesSharedMembers) {
      await _saveRemoteMember(member);
      return;
    }
    await _updateHousehold((data) {
      if (member.displayName.length > 40 ||
          member.relationship.length > 30 ||
          member.notes.length > 500)
        throw const ApiException('姓名最多 40 字，关系最多 30 字，备注最多 500 字');
      if (!data.members.any((m) => m.id == member.id))
        throw const ApiException('成员档案已不存在，请刷新');
      for (final b in member.bindings) {
        if (b.trackId.isNotEmpty &&
            data.members.any(
              (m) =>
                  m.id != member.id &&
                  m.bindings.any(
                    (x) =>
                        x.scope == b.scope &&
                        x.deviceId == b.deviceId &&
                        x.trackId == b.trackId,
                  ),
            )) {
          throw const ApiException('同一设备的该跟踪编号已绑定其他成员');
        }
      }
      return data.copyWith(
        members: data.members
            .map((m) => m.id == member.id ? member : m)
            .toList(),
      );
    });
  }

  Future<void> deleteMember(String id) async {
    if (usesSharedMembers) {
      final member = memberById(id);
      if (member == null) throw const ApiException('成员档案已不存在');
      final api = _requireMembersApi(), generation = _generation;
      ++_memberMutation;
      await api.delete(member);
      if (_disposed || generation != _generation) return;
      ++_memberMutation;
      await _acceptRemoteMembers(
        members.where((m) => m.id != id).toList(),
        generation,
      );
      return;
    }
    await _updateHousehold(
      (data) => data.copyWith(
        members: data.members.where((m) => m.id != id).toList(),
        eventMembers: Map.fromEntries(
          data.eventMembers.entries.where((e) => e.value != id),
        ),
      ),
    );
  }

  String? memberIdFor(SafetyEvent event) {
    final key = eventAssociationKey(event);
    if (household.eventMembers.containsKey(key)) {
      final id = household.eventMembers[key];
      return id == 'unassigned' || memberById(id!) == null ? null : id;
    }
    final marked = event.details['member_id']?.toString();
    if (usesSharedMembers && eventScope(event) != serviceScope) return null;
    if (marked != null && memberById(marked) != null) {
      final identity = event.details['face_identity'];
      if (identity is Map) {
        final member = memberById(marked)!;
        // Cached alerts must not keep a revoked identity after profile sync.
        if (!{'suspected_fall', 'help_requested'}.contains(event.eventType) ||
            identity['status'] != 'matched' ||
            identity['member_id'] != marked ||
            member.faceSampleCount == 0 ||
            (identity['revision'] != null &&
                identity['revision'] != member.revision))
          return null;
      }
      return marked;
    }
    // Shared-camera ranges cannot establish a person identity.
    if (usesSharedMembers) return null;
    final scope = eventScope(event);
    final exact = members
        .where(
          (m) => m.bindings.any(
            (b) =>
                b.scope == scope &&
                b.deviceId == event.deviceId &&
                b.trackId.isNotEmpty &&
                b.trackId == event.trackId,
          ),
        )
        .toList();
    if (exact.length == 1) return exact.single.id;
    if (exact.length > 1) return null;
    final ranged = members
        .where(
          (m) => m.bindings.any(
            (b) =>
                b.scope == scope &&
                b.deviceId == event.deviceId &&
                b.trackId.isEmpty,
          ),
        )
        .toList();
    return ranged.length == 1 ? ranged.single.id : null;
  }

  String associationLabel(SafetyEvent event) {
    if (household.eventMembers.containsKey(eventAssociationKey(event)))
      return memberIdFor(event) == null ? '待归属' : '人工关联';
    final id = memberIdFor(event);
    if (id == null) return '待归属';
    if (event.details['member_id']?.toString() == id)
      return event.details['face_identity'] is Map ? '人脸识别候选 · 请核对' : '服务端成员标记';
    final m = memberById(id)!;
    return m.bindings.any(
          (b) =>
              b.scope == eventScope(event) &&
              b.deviceId == event.deviceId &&
              b.trackId.isNotEmpty &&
              b.trackId == event.trackId,
        )
        ? '设备与跟踪编号绑定'
        : '设备范围关联';
  }

  String? personLabelFor(SafetyEvent event) {
    if (!{'suspected_fall', 'help_requested'}.contains(event.eventType))
      return null;
    final id = memberIdFor(event);
    return id == null
        ? '身份未确认'
        : '${memberById(id)!.displayName} · ${associationLabel(event)}';
  }

  Future<void> associateMember(SafetyEvent event, String? memberId) =>
      _updateHousehold((data) {
        if (memberId != null && !members.any((m) => m.id == memberId))
          throw const ApiException('请选择现有成员');
        return data.copyWith(
          eventMembers: {
            ...data.eventMembers,
            eventAssociationKey(event): memberId ?? 'unassigned',
          },
        );
      });
  List<SafetyEvent> recordsForMember(String id) =>
      events.where((e) => isPersonEvent(e) && memberIdFor(e) == id).toList();
  Future<SafetyEvent> loadEvent(String id) async {
    if (usesUnifiedBackend) {
      final generation = _generation, sync = _alertSync;
      final current = repository;
      if (current is! UnifiedAlertRepository || sync == null)
        throw const ApiException('统一告警服务尚未连接');
      final loaded = await current.event(id);
      if (_disposed || generation != _generation || sync != _alertSync)
        throw const ApiException('连接已切换，请重新打开告警');
      final event = await sync.accept(loaded);
      if (_disposed || generation != _generation || sync != _alertSync)
        throw const ApiException('连接已切换，请重新打开告警');
      _setUnifiedEvents(sync.events);
      return event;
    }
    final local = household.localEvents.where((e) => e.id == id).firstOrNull;
    if (local != null) return local;
    if (id.startsWith('video:')) {
      final generation = _generation;
      final api = _videoApi;
      final cached = _videoEvents.where((e) => e.id == id).firstOrNull;
      if (cached == null || api == null)
        throw const ApiException('录像事件未同步，请先刷新列表');
      final updated = await api.safetyEventsFor(
        Recording(
          id: cached.details['video_id'].toString(),
          name: cached.details['video_name'].toString(),
        ),
      );
      if (_disposed || generation != _generation || api != _videoApi)
        throw const ApiException('连接已变化，请重新打开录像事件');
      final found = updated.where((e) => e.id == id).firstOrNull;
      if (found == null) throw const ApiException('录像告警已更新或移除，请刷新列表');
      _videoEvents = _videoEvents.map((e) => e.id == id ? found : e).toList();
      _mergeEvents();
      return found;
    }
    return repository.event(id);
  }

  Future<Uint8List> evidenceFor(SafetyEvent event) async {
    if (event.isUnified) {
      final current = repository;
      if (current is! UnifiedAlertRepository || event.evidenceId == null)
        throw const ApiException('截图暂未关联，可稍后刷新');
      return current.mediaImage(event.evidenceId!);
    }
    if (isLocalEvent(event.id)) {
      final path = event.details['image_path']?.toString() ?? '';
      if (path.isEmpty) throw const ApiException('本机观察记录没有图片');
      try {
        return await File(path).readAsBytes();
      } catch (_) {
        throw const ApiException('本机图片已不存在');
      }
    }
    if (event.evidenceId == null) throw const ApiException('该来源尚未提供图片');
    if (event.fromVideo) {
      if (_videoApi == null ||
          event.details['source_url'] != household.objects.baseUrl)
        throw const ApiException('请连接事件所属的录像服务');
      return _videoApi!.frame(event.evidenceId!);
    }
    return repository.evidence(event.evidenceId!);
  }

  Future<void> acknowledgeEvent(String id) async {
    if (usesUnifiedBackend) {
      await _handleUnified(id, false);
      return;
    }
    if (id.startsWith('video:')) {
      final api = _videoApi;
      final generation = _generation;
      final event = await loadEvent(id);
      if (api == null || api != _videoApi || generation != _generation)
        throw const ApiException('连接已变化，请重试');
      await api.acknowledgeSafety(event);
      if (api != _videoApi || generation != _generation)
        throw const ApiException('连接已变化，请回到原服务核实确认状态');
      final verified = await loadEvent(id);
      if (!verified.acknowledged) throw const ApiException('录像告警确认状态尚未同步');
      _notify();
      return;
    }
    if (!isLocalEvent(id)) {
      await repository.acknowledge(id);
      return;
    }
    await _updateHousehold(
      (data) => data.copyWith(
        localEvents: data.localEvents
            .map(
              (e) => e.id == id
                  ? e.withStatus(
                      acknowledgement: 'acknowledged',
                      newState: e.resolved ? 'resolved' : 'acknowledged',
                    )
                  : e,
            )
            .toList(),
      ),
    );
  }

  Future<void> resolveEvent(String id) async {
    if (usesUnifiedBackend) {
      await _handleUnified(id, true);
      return;
    }
    if (id.startsWith('video:'))
      throw const ApiException('录像告警支持确认，请在网页管理分析结果');
    if (!isLocalEvent(id)) {
      await repository.resolve(id);
      return;
    }
    await _updateHousehold(
      (data) => data.copyWith(
        localEvents: data.localEvents
            .map(
              (e) => e.id == id
                  ? e.withStatus(
                      acknowledgement: 'acknowledged',
                      newState: 'resolved',
                    )
                  : e,
            )
            .toList(),
      ),
    );
  }

  Future<void> _handleUnified(String id, bool resolve) async {
    final generation = _generation, sync = _alertSync;
    final current = repository;
    if (current is! UnifiedAlertRepository || sync == null)
      throw const ApiException('统一后端未连接');
    final event = await current.handleAlert(id, resolve: resolve);
    if (_disposed || generation != _generation || sync != _alertSync)
      throw const ApiException('连接已切换，请回原服务核对处理状态');
    await sync.accept(event);
    if (_disposed || generation != _generation || sync != _alertSync) return;
    _setUnifiedEvents(sync.events);
    _notify();
  }

  Future<void> addLocalEvent(SafetyEvent event, {String? memberId}) =>
      _updateHousehold(
        (data) => data.copyWith(
          localEvents: [event, ...data.localEvents].take(200).toList(),
          eventMembers: memberId == null
              ? data.eventMembers
              : {...data.eventMembers, 'phone-local|${event.id}': memberId},
        ),
      );
  Future<void> saveObjectConfig(
    ObjectServiceConfig config, {
    bool refreshNow = true,
  }) async {
    if (usesUnifiedBackend) {
      final next = settings.copyWith(
        baseUrl: config.baseUrl,
        bearerToken: config.token,
        connectionVersion: 2,
      );
      if (next.baseUrl != settings.baseUrl ||
          next.bearerToken != settings.bearerToken)
        await applyConnection(next);
      await _updateHousehold(
        (data) => data.copyWith(
          objects: ObjectServiceConfig(
            baseUrl: settings.baseUrl,
            token: settings.bearerToken,
            useCloud: config.useCloud,
          ),
        ),
      );
      if (refreshNow) await refresh();
      return;
    }
    final check = AppSettings(
      baseUrl: config.baseUrl,
      bearerToken: config.token,
    ).validationError;
    if (check != null) throw ApiException(check);
    await _updateHousehold((data) => data.copyWith(objects: config));
    _generation++;
    _refreshing = false;
    _videoEvents = [];
    _baselines.remove('video');
    _resetVideoApi();
    _mergeEvents();
    if (refreshNow) await refresh();
    _startPolling();
  }

  Future<void> saveCamera(CameraConnection camera) => _updateHousehold((data) {
    if (camera.validationError != null)
      throw ApiException(camera.validationError!);
    return data.copyWith(camera: camera);
  });
  Future<void> rememberSearch(String query) => _updateHousehold(
    (data) => data.copyWith(
      searches: [
        query,
        ...data.searches.where((e) => e != query),
      ].take(10).toList(),
    ),
  );
  Future<void> addRecentObjects(List<RecentObject> records) => _updateHousehold(
    (data) => data.copyWith(
      recentObjects: [
        ...records,
        ...data.recentObjects.where((e) => !records.any((n) => n.id == e.id)),
      ].take(100).toList(),
    ),
  );

  String nameForDevice(String id) {
    if (id.startsWith('video:'))
      return _videoEvents
              .where((e) => e.deviceId == id)
              .firstOrNull
              ?.details['video_name']
              ?.toString() ??
          '上传录像';
    if (id == 'phone-local') return '本机离线分析';
    for (final d in devices) {
      if (d.id == id) return d.name;
    }
    return id;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _resetMemberConnection();
    _videoApi?.close();
    _timer?.cancel();
    unawaited(
      push
          .dispose()
          .catchError((Object _) {})
          .whenComplete(() => _repository?.close()),
    );
    unawaited(notices.close());
    unawaited(openEvents.close());
    unawaited(alertSnapshots.close());
    unawaited(alertOpens.close());
    super.dispose();
  }
}
