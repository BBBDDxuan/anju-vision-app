import 'package:flutter/material.dart';
import '../app_controller.dart';
import 'camera_screen.dart';
import 'video_workspace_screen.dart';
import 'web_workspace_screen.dart';
import 'settings_screen.dart';

Future<void> openMediaHub(
  BuildContext context,
  SafetyController c, {
  bool camera = false,
  String mode = 'safety',
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        MediaHubScreen(controller: c, camera: camera, initialMode: mode),
  ),
);

Future<void> openMediaSettings(BuildContext context, SafetyController c) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('服务连接与设置')),
          body: SettingsScreen(controller: c),
        ),
      ),
    );

class MediaHubScreen extends StatefulWidget {
  const MediaHubScreen({
    super.key,
    required this.controller,
    this.camera = false,
    this.initialMode = 'safety',
  });
  final SafetyController controller;
  final bool camera;
  final String initialMode;
  @override
  State<MediaHubScreen> createState() => _MediaHubScreenState();
}

class _MediaHubScreenState extends State<MediaHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.camera ? 0 : 1,
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_changed);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final config = widget.controller.household.objects;
      return Scaffold(
        appBar: AppBar(
          title: const Text('视频与实时监护'),
          actions: [
            IconButton(
              tooltip: '完整工作台',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WebWorkspaceScreen(config: config),
                ),
              ),
            ),
            IconButton(
              tooltip: '连接服务',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => openMediaSettings(context, widget.controller),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.videocam_outlined), text: '实时摄像头'),
              Tab(icon: Icon(Icons.video_library_outlined), text: '导入视频'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            CameraScreen(
              key: ValueKey('camera-${identityHashCode(config)}'),
              controller: widget.controller,
              active: _tabs.index == 0,
            ),
            VideoWorkspaceScreen(
              key: ValueKey('video-${identityHashCode(config)}'),
              controller: widget.controller,
              initialMode: widget.initialMode,
              active: _tabs.index == 1,
            ),
          ],
        ),
      );
    },
  );
}
