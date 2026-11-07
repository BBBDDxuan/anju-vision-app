import 'dart:async';
import 'dart:convert';
import 'models/unified_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_controller.dart';
import 'services/android_notices.dart';
import 'services/app_notification_binding.dart';
import 'services/app_updates.dart';
import 'ui/app_update_screen.dart';
import 'ui/event_detail_screen.dart';

import 'ui/home_screen.dart';
import 'ui/history_screen.dart';
import 'ui/members_screen.dart';
import 'ui/risks_screen.dart';
import 'ui/objects_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/devices_screen.dart';
import 'ui/widgets.dart';
import 'package:flutter/services.dart';

class ElderSafetyApp extends StatefulWidget {
  const ElderSafetyApp({
    super.key,
    required this.controller,
    this.accountLabel,
    this.accountDisplayName,
    this.accountId,
    this.onAccountLogout,
  });
  final String? accountLabel, accountId, accountDisplayName;
  final VoidCallback? onAccountLogout;
  final SafetyController controller;
  @override
  State<ElderSafetyApp> createState() => _ElderSafetyAppState();
}

class _ElderSafetyAppState extends State<ElderSafetyApp>
    with WidgetsBindingObserver {
  final _updates = AppUpdateManager();
  String? _promptedUpdate;
  Timer? _updateTimer;
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<EventNotice>? _notices;
  StreamSubscription<String>? _opens;
  StreamSubscription<AlertLocation>? _alertOpens;
  StreamSubscription<AlertSyncSnapshot>? _snapshots;
  late final AppNotificationBinding _notificationBinding;
  int _tab = 0;
  String? _openId;
  final List<String> _pendingOpens = [];
  bool _ready = false;
  bool _active = true;
  final _android = AndroidNotices();
  late final Future<void> _nativeReady;
  bool _askedForNotificationPermission = false;
  final Set<String> _systemNotices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.addListener(_updateChanged);
    widget.controller.addListener(_syncUpdateConnection);
    unawaited(_updates.initialize());
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (_active) unawaited(_updates.check());
    });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _nativeReady = _initializeNativeNotices();
    _notificationBinding = AppNotificationBinding(
      android: _android,
      currentScope: () => widget.controller.notificationScope,
      accountId: widget.accountId,
      canPresent: (scope) =>
          mounted &&
          _active &&
          widget.controller.canPresentNotifications(scope),
    );
    _snapshots = widget.controller.alertSnapshots.stream.listen((snapshot) {
      unawaited(_forwardSnapshot(snapshot));
    });
    _notices = widget.controller.notices.stream.listen((notice) {
      if (!mounted ||
          !_active ||
          !widget.controller.preferences.notificationsEnabled)
        return;
      unawaited(_showSystemNotice(notice.eventId));
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(notice.message),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => _openEvent(notice.eventId),
          ),
        ),
      );
    });
    _opens = widget.controller.openEvents.stream.listen(_openEvent);
    _alertOpens = widget.controller.alertOpens.stream.listen(
      (_) => _consumeAlertOpens(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.initialize();
      if (!mounted) return;
      _ready = true;
      unawaited(_requestNotificationPermission());
      _consumeAlertOpens();
      if (_pendingOpens.isNotEmpty) {
        final id = _pendingOpens.last;
        _pendingOpens.clear();
        _openEvent(id);
      }
    });
  }

  void _syncUpdateConnection() {
    final c = widget.controller;
    if (!c.initialized) return;
    _updates.configure(c.configuring ? null : c.settings);
  }

  void _updateChanged() {
    if (!mounted || !_active || !_updates.ready || _updates.release == null)
      return;
    final digest = _updates.release!.sha256;
    if (_promptedUpdate == digest) return;
    _promptedUpdate = digest;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: const Text('新版已下载，可安装更新'),
        duration: const Duration(seconds: 20),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            unawaited(
              _navigator.currentState?.push<void>(
                MaterialPageRoute(
                  builder: (_) => AppUpdateScreen(updates: _updates),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _initializeNativeNotices() async {
    try {
      await _android.initialize(
        _openNativeNotice,
        onOpenScoped: (scope, id) {
          unawaited(widget.controller.openScopedAlert(scope, id));
        },
      );
    } catch (_) {
      // Native integration failure must not suppress the in-app warning.
      debugPrint('Android notification initialization failed');
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (!_ready ||
        !_active ||
        !mounted ||
        widget.accountId == null ||
        !AndroidNotices.supported ||
        _askedForNotificationPermission) {
      return;
    }
    _askedForNotificationPermission = true;
    try {
      await _android.requestPermission(automatic: true);
    } catch (_) {
      // The notification settings screen can retry and show the platform status.
      debugPrint('Automatic Android notification permission request failed');
    }
  }

  Future<void> _forwardSnapshot(AlertSyncSnapshot snapshot) async {
    await _nativeReady;
    if (!mounted) return;
    try {
      final notices = await _notificationBinding.accept(snapshot);
      if (!mounted || notices.isEmpty || !_active) return;
      final notice = notices.last;
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            notices.length == 1
                ? '收到新的安全告警，请及时查看'
                : '收到 ${notices.length} 条新的安全告警，请及时查看',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              unawaited(
                widget.controller.openScopedAlert(snapshot.scope, notice.id),
              );
            },
          ),
        ),
      );
    } catch (_) {
      debugPrint('Unified notification synchronization unavailable');
    }
  }

  Future<void> _showSystemNotice(String id) async {
    await _nativeReady;
    if (!mounted ||
        !_active ||
        !widget.controller.preferences.notificationsEnabled)
      return;
    final c = widget.controller;
    final key = '${c.settings.baseUrl}|${c.household.objects.baseUrl}|$id';
    if (!_systemNotices.add(key)) return;
    try {
      await _android.show(id);
    } catch (_) {
      _systemNotices.remove(key);
      // Permissions and channel switches are explained in Notification settings.
      debugPrint('Android system notification unavailable');
    }
  }

  void _openFeature(String title, Widget Function() screen) {
    _navigator.currentState?.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/features/$title'),
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (_, _) => screen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMembers() => _openFeature(
    '成员监护',
    () => MembersScreen(
      controller: widget.controller,
      openEvent: _openEvent,
      openDevices: _openDevices,
      accountMode: widget.accountId != null,
    ),
  );

  void _openRisks() => _openFeature(
    '家中风险',
    () => RisksScreen(
      controller: widget.controller,
      openEvent: _openEvent,
      openDevices: _openDevices,
    ),
  );

  void _openObjects() =>
      _openFeature('物品寻找', () => ObjectsScreen(controller: widget.controller));

  void _openDevices() {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    _selectTab(1);
  }

  void _selectTab(int value) {
    _messenger.currentState?.clearSnackBars();
    setState(() => _tab = value);
  }

  void _openNativeNotice(String payload) {
    try {
      final value = jsonDecode(payload);
      if (value is Map) {
        final location = AlertLocation.tryParse(
          Map<String, dynamic>.from(value),
        );
        if (location != null) {
          widget.controller.openAlert(location);
          return;
        }
      }
    } catch (_) {
      /* Legacy payloads only belong to the legacy connection. */
    }
    if (!widget.controller.usesUnifiedBackend) _openEvent(payload);
  }

  void _consumeAlertOpens() {
    if (!mounted || !_ready || _navigator.currentState == null) return;
    final pending = widget.controller.takePendingAlertOpens();
    if (pending.isEmpty) return;
    final location = pending.last;
    if (!widget.controller.locationMatches(location)) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('这条通知属于其他后端或家庭，请切换到原连接后查看')),
      );
      return;
    }
    _openUnifiedAlert(location);
  }

  void _openUnifiedAlert(AlertLocation location) {
    if (!mounted || _openId == location.key) return;
    if (_openId != null)
      _navigator.currentState!.popUntil((route) => route.isFirst);
    _openId = location.key;
    unawaited(
      _navigator.currentState!
          .push<void>(
            MaterialPageRoute(
              settings: RouteSettings(
                name: '/alerts/${Uri.encodeComponent(location.alertId)}',
                arguments: location.toJson(),
              ),
              builder: (_) => EventDetailScreen(
                controller: widget.controller,
                eventId: location.alertId,
                location: location,
              ),
            ),
          )
          .whenComplete(() {
            if (_openId == location.key) _openId = null;
          }),
    );
  }

  void _openEvent(String id) {
    if (widget.controller.usesUnifiedBackend) {
      final event = widget.controller.events
          .where((e) => e.id == id && e.isUnified)
          .firstOrNull;
      if (event != null)
        widget.controller.openAlert(
          AlertLocation(
            backend: widget.controller.serviceScope,
            household: 'default',
            alertId: id,
            source: event.details['source'] as String,
          ),
        );
      return;
    }
    if (!mounted || _openId == id) return;
    if (!_ready || _navigator.currentState == null) {
      _pendingOpens.add(id);
      return;
    }
    // Replace a previously opened event rather than stacking several alerts.
    if (_openId != null)
      _navigator.currentState!.popUntil((route) => route.isFirst);
    _openId = id;
    unawaited(
      _navigator.currentState!
          .push<void>(
            MaterialPageRoute(
              settings: RouteSettings(
                name: '/events/${Uri.encodeComponent(id)}',
              ),
              builder: (_) =>
                  EventDetailScreen(controller: widget.controller, eventId: id),
            ),
          )
          .whenComplete(() {
            if (_openId == id) _openId = null;
          }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    widget.controller.setActive(_active);
    if (_active) {
      unawaited(_requestNotificationPermission());
      unawaited(_updates.check());
      _updateChanged();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '安居视界',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
    theme: Anju.theme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final pending = controller.events.where(eventNeedsAction).length;
        final screens = [
          HomeScreen(
            controller: controller,
            openEvent: _openEvent,
            openHistory: () => _selectTab(2),
            openDevices: _openDevices,
            openSettings: () => _selectTab(3),
            openMembers: _openMembers,
            openRisks: _openRisks,
            openObjects: _openObjects,
          ),
          DevicesScreen(controller: controller, openEvent: _openEvent),
          HistoryScreen(controller: controller, openEvent: _openEvent),
          ListenableBuilder(
            listenable: _updates,
            builder: (context, child) => SettingsScreen(
              controller: controller,
              openMembers: _openMembers,
              updates: _updates,
              accountLabel: widget.accountLabel,
              accountDisplayName: widget.accountDisplayName,
              accountId: widget.accountId,
              onAccountLogout: widget.onAccountLogout,
            ),
          ),
        ];
        return PopScope(
          canPop: _tab == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _tab != 0) setState(() => _tab = 0);
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 64,
              titleSpacing: 20,
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 32),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '安居视界',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Center(
                    child: _tab == 3
                        ? ListenableBuilder(
                            listenable: _updates,
                            builder: (context, child) {
                              final version = _updates.installed?.name;
                              return Pill(
                                version == null || version.isEmpty
                                    ? '版本未知'
                                    : 'v$version',
                                icon: Icons.shield_outlined,
                              );
                            },
                          )
                        : const Pill('家庭守护', icon: Icons.shield_outlined),
                  ),
                ),
              ],
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            body: !controller.initialized
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (controller.loading)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Row(
                            children: [
                              if (constraints.maxWidth >= 720)
                                NavigationRail(
                                  selectedIndex: _tab,
                                  onDestinationSelected: (value) =>
                                      setState(() => _tab = value),
                                  labelType: NavigationRailLabelType.all,
                                  destinations: const [
                                    NavigationRailDestination(
                                      icon: Icon(Icons.home_outlined),
                                      selectedIcon: Icon(Icons.home_rounded),
                                      label: Text('首页'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.videocam_outlined),
                                      label: Text('设备'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(
                                        Icons.notifications_none_rounded,
                                      ),
                                      label: Text('消息'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.person_outline_rounded),
                                      label: Text('我的'),
                                    ),
                                  ],
                                ),
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 640,
                                    ),
                                    child: IndexedStack(
                                      index: _tab,
                                      children: screens,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
            bottomNavigationBar: MediaQuery.sizeOf(context).width >= 720
                ? null
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Anju.line)),
                    ),
                    child: NavigationBar(
                      height: 72,
                      elevation: 0,
                      backgroundColor: Colors.white,
                      indicatorColor: Anju.light,
                      selectedIndex: _tab,
                      onDestinationSelected: (value) {
                        HapticFeedback.selectionClick();
                        _selectTab(value);
                      },
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: '首页',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.videocam_outlined),
                          selectedIcon: Icon(Icons.videocam_rounded),
                          label: '设备',
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible: pending > 0,
                            label: Text('$pending'),
                            child: const Icon(Icons.notifications_none_rounded),
                          ),
                          selectedIcon: const Icon(Icons.notifications_rounded),
                          label: '消息',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: '我的',
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_syncUpdateConnection);
    _updates.removeListener(_updateChanged);
    _updateTimer?.cancel();
    _updates.dispose();
    unawaited(_notices?.cancel());
    unawaited(_opens?.cancel());
    unawaited(_alertOpens?.cancel());
    _notificationBinding.dispose();
    unawaited(_snapshots?.cancel());
    unawaited(_android.dispose());
    widget.controller.dispose();
    super.dispose();
  }
}
