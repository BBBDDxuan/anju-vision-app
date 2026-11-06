import 'dart:async';
import 'package:flutter/material.dart';
import 'native_camera_view.dart';
import '../app_controller.dart';
import '../models/camera_connection.dart';
import '../services/media_api.dart';
import '../services/api.dart';
import 'widgets.dart';
import 'manual_tracks_panel.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.controller,
    this.active = true,
    this.mediaApiFactory,
  });
  final SafetyController controller;
  final bool active;
  final MediaApi Function()? mediaApiFactory;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late TextEditingController _host, _port, _user, _password, _path;
  Uri? _stream;
  Timer? _connectionTimer, _statusTimer;
  bool _foreground = true, _statusBusy = false;
  bool _busy = false, _showPassword = false, _connecting = false;
  int _generation = 0, _statusEpoch = 0;
  late String _backendScope;
  String? _message, _statusError;
  Map<String, dynamic>? _server;
  String get _scope =>
      '${widget.controller.household.objects.baseUrl}|${widget.controller.household.objects.token}';
  MediaApi _api() =>
      widget.mediaApiFactory?.call() ??
      MediaApi(widget.controller.household.objects);
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
    _backendScope = _scope;
    widget.controller.addListener(_controllerChanged);
    _startStatusPolling();
  }

  @override
  void didUpdateWidget(covariant CameraScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) unawaited(_stop());
    if (!old.active && widget.active) _startStatusPolling();
  }

  void _controllerChanged() {
    if (_backendScope == _scope) return;
    _backendScope = _scope;
    unawaited(_stop());
    _server = null;
    _message = null;
    _statusError = null;
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    if (!widget.active || !_foreground) return;
    unawaited(_serverStatus());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_serverStatus()),
    );
  }

  void _invalidateStatus() {
    _statusEpoch++;
    _statusBusy = false;
    _statusTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _startStatusPolling();
    }
  }

  Future<void> _connect() async {
    final c = _connection;
    if (c.validationError != null) {
      setState(() => _message = c.validationError);
      return;
    }
    final generation = ++_generation;
    _invalidateStatus();
    setState(() {
      _busy = true;
      _stream = null;
      _connecting = true;
      _message = null;
    });
    MediaApi? api;
    try {
      api = _api();
      final status = await api.connectCamera(c);
      if (!mounted || generation != _generation) return;
      setState(() => _server = status);
      try {
        await widget.controller.saveCamera(c);
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _message = '后端监护已启动，但手机保存配置失败，请稍后重试。');
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() => _stream = c.streamUri);
      _connectionTimer?.cancel();
      _connectionTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && generation == _generation && _connecting) {
          setState(() {
            _connecting = false;
            _message = '手机预览尚未连接，请检查手机到摄像头的网络；后端监护状态请见下方。';
          });
        }
      });
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _connecting = false;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _connecting = false;
          _message = '连接失败，请确认后端服务、访问令牌及电脑到摄像头的网络。';
        });
      }
    } finally {
      api?.close();
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _startStatusPolling();
      }
    }
  }

  // Disconnect only the phone preview. Backend monitoring has an explicit stop.
  Future<void> _stop() async {
    _generation++;
    _invalidateStatus();
    _busy = false;
    _connecting = false;
    _connectionTimer?.cancel();
    _stream = null;
    if (mounted) {
      setState(() {});
      _startStatusPolling();
    }
  }

  Future<void> _serverStatus() async {
    if (_statusBusy || _busy || !widget.active || !_foreground) return;
    _statusBusy = true;
    final epoch = _statusEpoch, scope = _scope;
    MediaApi? api;
    try {
      api = _api();
      final value = await api.cameraStatus();
      if (mounted && epoch == _statusEpoch && scope == _scope) {
        setState(() {
          _server = value;
          _statusError = null;
        });
      }
    } catch (_) {
      if (mounted && epoch == _statusEpoch && scope == _scope) {
        setState(() {
          _server = null;
          _statusError = '无法读取后端监护状态，请确认已更新并启动手机后端服务，且服务地址与令牌正确。';
        });
      }
    } finally {
      api?.close();
      if (epoch == _statusEpoch) _statusBusy = false;
    }
  }

  Future<void> _backendCommand(String action) async {
    if (_busy) return;
    final generation = _generation, scope = _scope;
    if (action == 'stop') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('停止后端监护？'),
          content: const Text('所有连接此后端的手机都将停止接收该摄像头的新告警。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止监护'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted || generation != _generation || scope != _scope) return;
    _invalidateStatus();
    MediaApi? api;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      api = _api();
      final status = await api.cameraCommand(action);
      if (mounted && generation == _generation && scope == _scope) {
        setState(() => _server = status);
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation && scope == _scope) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation && scope == _scope) {
        setState(() => _message = '后端监护操作失败，请检查服务连接。');
      }
    } finally {
      api?.close();
      if (mounted && generation == _generation && scope == _scope) {
        setState(() => _busy = false);
        _startStatusPolling();
      }
    }
  }

  String get _backendState => switch (_server?['state']) {
    'running' => '正在识别',
    'starting' => '正在启动模型',
    'reconnecting' => '正在重连摄像头',
    'stale' => '画面更新延迟',
    'error' => '识别进程异常，请检查后端',
    'stopped' => '已停止',
    _ => '等待状态',
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_controllerChanged);
    _generation++;
    _invalidateStatus();
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
          '电脑后端须能访问摄像头；手机连接后端后即可开启监护，并可独立预览。',
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
                            _message = '手机预览已中断，后端监护状态请见下方。';
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
        if (_statusError != null) InfoBanner(_statusError!, error: true),
        ManualTracksPanel(
          controller: widget.controller,
          active: widget.active && _foreground,
        ),
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
          '连接后由电脑后端持续拉流，使用小模型检测与大模型复核。退出此页或断开画面后监护继续；后端服务须保持运行。',
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
          label: Text(_busy ? '处理中…' : '连接摄像头并开启后端监护'),
        ),
        const SizedBox(height: 8),
        const Text(
          '设备密码保存在手机安全存储与电脑后端本地配置中。请使用设备账号，不填写云平台登录密码。',
          style: TextStyle(fontSize: 11, color: Anju.muted),
        ),
        const SectionTitle('后端实时监护'),
        OutlinedButton.icon(
          onPressed: _busy ? null : _serverStatus,
          icon: const Icon(Icons.sensors_outlined),
          label: const Text('查看已连接后端的识别状态'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _backendCommand('start'),
              child: const Text('启动已保存的后端监护'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _backendCommand('stop'),
              child: const Text('停止后端监护'),
            ),
          ],
        ),
        if (_server != null) ...[
          InfoBanner(
            '后端状态：$_backendState · 画面人数 ${_server!['persons'] ?? '待上报'} · ${_server!['fps'] ?? '待上报'} FPS',
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
