import 'dart:async';
import 'package:flutter/material.dart';
import 'native_camera_view.dart';
import '../app_controller.dart';
import '../models/camera_connection.dart';
import '../services/media_api.dart';
import 'widgets.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.controller, this.active = true});
  final SafetyController controller;
  final bool active;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late TextEditingController _host, _port, _user, _password, _path;
  Uri? _stream;
  Timer? _connectionTimer;
  bool _busy = false, _showPassword = false, _connecting = false;
  String? _message;
  int _generation = 0;
  Map<String, dynamic>? _server;
  CameraConnection get _connection => CameraConnection(
    host: _host.text.trim(),
    port: int.tryParse(_port.text) ?? 0,
    username: _user.text.trim(),
    password: _password.text,
    path: _path.text.trim(),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final c = widget.controller.household.camera;
    _host = TextEditingController(text: c.host);
    _port = TextEditingController(text: '${c.port}');
    _user = TextEditingController(text: c.username);
    _password = TextEditingController(text: c.password);
    _path = TextEditingController(text: c.path);
  }

  @override
  void didUpdateWidget(covariant CameraScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) unawaited(_stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached)
      unawaited(_stop());
  }

  Future<void> _connect() async {
    final c = _connection;
    if (c.validationError != null) {
      setState(() => _message = c.validationError);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _stream = null;
      _connecting = true;
      _message = null;
    });
    try {
      await widget.controller.saveCamera(c);
      if (!mounted || generation != _generation) return;
      setState(() => _stream = c.streamUri);
      _connectionTimer?.cancel();
      _connectionTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && generation == _generation && _connecting) {
          setState(() {
            _connecting = false;
            _message = '尚未收到实时画面，请检查摄像头地址、设备账号和网络后重连。';
          });
        }
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _connecting = false;
          _message = '连接失败，请确认摄像头已接入同一局域网，且本地账号和 RTSP 路径正确。';
        });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    _generation++;
    _connecting = false;
    _connectionTimer?.cancel();
    _stream = null;
    if (mounted) setState(() {});
  }

  Future<void> _serverStatus() async {
    final api = MediaApi(widget.controller.household.objects);
    try {
      final value = await api.cameraStatus();
      if (mounted) setState(() => _server = value);
    } catch (_) {
      if (mounted)
        setState(
          () => _message =
              '现有网页后端可能只允许电脑本机控制实时识别。可在电脑网页开启识别；App 可直连摄像头预览，并可分析已上传的视频、查看已接入的告警。',
        );
    } finally {
      api.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _connectionTimer?.cancel();
    for (final field in [_host, _port, _user, _password, _path]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        30 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const Text(
          '局域网摄像头',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '手机与摄像头连接可互通的 Wi-Fi，通过设备本地账号拉取实时视频。',
          style: TextStyle(fontSize: 12, color: Anju.muted),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: const Color(0xff132b30),
              child: _stream == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            color: Colors.white70,
                            size: 46,
                          ),
                          SizedBox(height: 12),
                          Text(
                            '填写摄像头信息后连接',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    )
                  : NativeCameraView(
                      key: ValueKey(_generation),
                      uri: _stream!,
                      onStatus: (status) {
                        if (!mounted) return;
                        setState(() {
                          if (status == 'playing') {
                            _connecting = false;
                            _connectionTimer?.cancel();
                            _message = null;
                          }
                          if (status == 'error' || status == 'ended') {
                            _connecting = false;
                            _message = '实时视频已中断，请核对设备状态后重新连接。';
                          }
                        });
                      },
                    ),
            ),
          ),
        ),
        if (_connecting)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null) InfoBanner(_message!, error: true),
        const SizedBox(height: 14),
        if (_stream != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('断开画面'),
              ),
            ],
          ),
        const SizedBox(height: 10),
        const Text(
          '此处连接实时画面。已有录像可在“导入视频”中上传分析；连续实时识别由电脑端现有服务执行。',
          style: TextStyle(fontSize: 12, color: Anju.muted, height: 1.6),
        ),
        const SectionTitle('摄像头连接'),
        TextField(
          controller: _host,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '摄像头局域网 IP',
            hintText: '例如 192.168.137.39',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _port,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'RTSP 端口',
            helperText: 'TP-LINK 默认 554，以设备设置为准',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _user,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '摄像头本地用户名'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '摄像头设备密码',
            suffixIcon: IconButton(
              tooltip: '显示或隐藏密码',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _path,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'RTSP 视频路径',
            helperText: '单摄：stream1 / stream2；双摄需带 channel 参数',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: [
            for (final path in [
              'stream1',
              'stream2',
              'stream1&channel=1',
              'stream1&channel=2',
            ])
              ActionChip(
                label: Text(path),
                onPressed: _busy
                    ? null
                    : () => setState(() => _path.text = path),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(_busy ? '处理中…' : '保存并连接实时画面'),
        ),
        const SizedBox(height: 8),
        const Text(
          '设备密码保存在本机安全存储中。请使用设备账号，不填写云平台登录密码。',
          style: TextStyle(fontSize: 11, color: Anju.muted),
        ),
        const SectionTitle('电脑端实时识别'),
        OutlinedButton.icon(
          onPressed: _serverStatus,
          icon: const Icon(Icons.sensors_outlined),
          label: const Text('查看已连接后端的识别状态'),
        ),
        if (_server != null) ...[
          InfoBanner(
            '后端状态：${_server!['state']} · 画面人数 ${_server!['persons'] ?? '待上报'} · ${_server!['fps'] ?? '待上报'} FPS',
          ),
          for (final event
              in (_server!['events'] as List? ?? []).whereType<Map>().take(20))
            ListTile(
              title: Text(
                eventTypeLabel(event['event_type']?.toString() ?? ''),
              ),
              subtitle: Text(
                '复核：${event['review_status'] ?? '未复核'}\n${event['review_reason'] ?? ''}',
              ),
            ),
        ],
      ],
    ),
  );
}
