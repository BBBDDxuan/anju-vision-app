import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../app_controller.dart';
import '../models/household.dart';
import '../models/unified_alert.dart';
import '../services/api.dart';
import '../services/media_api.dart';
import '../services/object_api.dart';
import 'objects_screen.dart' show EvidenceFrame, ObjectReplayScreen;
import 'web_workspace_screen.dart';
import 'widgets.dart';

class VideoWorkspaceScreen extends StatefulWidget {
  const VideoWorkspaceScreen({
    super.key,
    required this.controller,
    this.initialMode = 'safety',
    this.initialVideoId,
    this.active = true,
  });
  final SafetyController controller;
  final String initialMode;
  final String? initialVideoId;
  final bool active;
  @override
  State<VideoWorkspaceScreen> createState() => _VideoWorkspaceScreenState();
}

class _VideoWorkspaceScreenState extends State<VideoWorkspaceScreen>
    with WidgetsBindingObserver {
  late MediaApi _api;
  late String _mode;
  String? _selected, _error, _uploadName;
  List<Recording> _videos = [];
  Map<String, dynamic>? _health, _job, _answer, _plan;
  VideoMemory? _memory;
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true,
      _command = false,
      _uploading = false,
      _foreground = true,
      _querying = false,
      _cloud = false;
  int _sequence = 0, _sent = 0, _total = 0, _visibleEvents = 30;
  String _eventFilter = 'all';
  final _question = TextEditingController();
  UploadCancellation? _cancellation;
  Timer? _timer;
  VideoPlayerController? _player;
  bool get _running => {'queued', 'running'}.contains(_job?['status']);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = MediaApi(widget.controller.household.objects);
    _mode = widget.initialMode;
    _cloud = widget.controller.household.objects.useCloud;
    unawaited(_load(preferred: widget.initialVideoId));
  }

  @override
  void didUpdateWidget(covariant VideoWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.initialVideoId != widget.initialVideoId &&
        widget.initialVideoId != null)
      unawaited(_load(preferred: widget.initialVideoId));
    if (old.active != widget.active) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (!_foreground) _player?.pause();
    if (_foreground && widget.active) unawaited(_load(preferred: _selected));
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (widget.active && _foreground && _running)
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_poll()),
      );
    if (!widget.active) _player?.pause();
  }

  Future<void> _load({String? preferred}) async {
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<dynamic>([
        _api.health(),
        _api.recordings(),
      ]);
      if (!mounted || sequence != _sequence) return;
      final videos = result[1] as List<Recording>;
      setState(() {
        _health = result[0] as Map<String, dynamic>;
        _videos = videos;
      });
      final id = preferred ?? _selected ?? videos.firstOrNull?.id;
      if (id != null && videos.any((v) => v.id == id))
        await _select(id);
      else {
        await _player?.dispose();
        _player = null;
        setState(() {
          _selected = null;
          _job = null;
          _memory = null;
          _alerts = [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String id) async {
    final sequence = ++_sequence;
    _timer?.cancel();
    await _player?.dispose();
    _player = null;
    if (!mounted) return;
    setState(() {
      _selected = id;
      _job = null;
      _memory = null;
      _alerts = [];
      _answer = null;
      _plan = null;
      _error = null;
      _visibleEvents = 30;
    });
    try {
      final detail = await _api.video(id);
      if (!mounted || sequence != _sequence) return;
      setState(
        () => _job = detail['latest_job'] is Map
            ? Map<String, dynamic>.from(detail['latest_job'] as Map)
            : null,
      );
      await _readResults(id, sequence);
      _schedule();
    } catch (e) {
      if (mounted && sequence == _sequence) setState(() => _error = '$e');
    }
  }

  Future<void> _readResults(String id, int sequence) async {
    try {
      final memory = await _api.memory(id);
      if (!mounted || sequence != _sequence) return;
      setState(() => _memory = memory);
      await widget.controller.addRecentObjects(
        memory.objectRecords(_api.config.baseUrl),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 409 && e.statusCode != 404) rethrow;
    }
    try {
      final payload = await _api.getJson('${_api.videoPath(id)}/alerts');
      if (mounted && sequence == _sequence)
        setState(
          () => _alerts = (payload['alerts'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
    } on ApiException catch (e) {
      if (e.statusCode != 409 && e.statusCode != 404) rethrow;
    }
  }

  bool _polling = false;
  Future<void> _poll() async {
    final id = _job?['id']?.toString(),
        videoId = _selected,
        sequence = _sequence;
    if (_polling ||
        id == null ||
        videoId == null ||
        !mounted ||
        !widget.active ||
        !_foreground)
      return;
    _polling = true;
    try {
      final next = await _api.job(id);
      if (!mounted || sequence != _sequence) return;
      final ended = !{'queued', 'running'}.contains(next['status']);
      setState(() {
        _job = next;
        _error = null;
      });
      if (ended) {
        await _readResults(videoId, sequence);
        await widget.controller.refresh();
      }
      _schedule();
    } catch (e) {
      if (mounted && sequence == _sequence) setState(() => _error = '$e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mp4'],
      );
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开视频选择器，请先将 MP4 保存到手机文件中。');
      return;
    }
    if (!mounted || file == null) return;
    final selectedFile = file;
    final path = selectedFile.path;
    if (path == null) {
      setState(() => _error = '无法读取这个视频，请先下载到手机本地。');
      return;
    }
    int fileSize;
    try {
      fileSize = await File(path).length();
    } catch (_) {
      if (mounted) setState(() => _error = '视频文件不可读，请重新选择本地 MP4。');
      return;
    }
    if (!mounted) return;
    final limit = (_health?['limits'] as Map?)?['max_upload_mb'] as num?;
    if (limit != null && fileSize > limit * 1024 * 1024) {
      setState(() => _error = '视频超过当前后端的上传大小限制（$limit MiB）。');
      return;
    }
    _cancellation = UploadCancellation();
    setState(() {
      _uploading = true;
      _error = null;
      _sent = 0;
      _total = fileSize;
      _uploadName = selectedFile.name;
    });
    try {
      final id = await _api.uploadVideo(
        File(path),
        selectedFile.name,
        cancellation: _cancellation!,
        onProgress: (sent, total) {
          if (mounted)
            setState(() {
              _sent = sent;
              _total = total;
            });
        },
      );
      if (!mounted) return;
      await _load(preferred: id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _cancellation = null;
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openUnifiedRecordingAlert(
    String videoId,
    Map<String, dynamic> alert,
  ) async {
    await widget.controller.refresh();
    if (!mounted) return;
    final matches = widget.controller.events
        .where(
          (e) =>
              e.isUnified &&
              e.fromVideo &&
              !e.withdrawn &&
              e.details['video_id'] == videoId &&
              e.details['source_event_id'] == alert['id'],
        )
        .toList();
    if (matches.length != 1) {
      setState(() => _error = '该记录尚未对应唯一的确认告警，请等待后端复核或刷新统一告警列表。');
      return;
    }
    final event = matches.single;
    widget.controller.openAlert(
      AlertLocation(
        backend: widget.controller.serviceScope,
        household: 'default',
        alertId: event.id,
        source: 'uploaded_recording',
      ),
    );
  }

  Future<void> _analysis(String action) async {
    final id = _selected;
    if (id == null) return;
    setState(() {
      _command = true;
      _error = null;
    });
    try {
      Map<String, dynamic> result;
      if (action == 'start') {
        final plan = await _api.analysisPlan(id, _mode);
        if (mounted) setState(() => _plan = plan);
        if (_mode == 'safety' && plan['hybrid_safety_enabled'] != true) {
          throw const ApiException('电脑后端尚未启用安全识别模型，请先在原项目配置小模型与复核服务。');
        }
        result = await _api.analyze(id, _mode);
      } else if (action == 'resume') {
        result = await _api.resume(id);
      } else {
        result = await _api.pause(id);
      }
      if (!mounted) return;
      setState(() => _job = result);
      _schedule();
      if (!_running) await _readResults(id, _sequence);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _command = false);
    }
  }

  Future<void> _delete(Recording video) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这段录像？'),
        content: Text('将从后端删除“${video.name}”及其分析记录和独有证据，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除录像'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _command = true);
    try {
      await _api.deleteRecording(video.id);
      if (_selected == video.id) _selected = null;
      await _load();
      await widget.controller.refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _command = false);
    }
  }

  Future<void> _play({int? milliseconds}) async {
    final id = _selected;
    if (id == null) return;
    try {
      var player = _player;
      if (player == null) {
        player = VideoPlayerController.networkUrl(
          _api.videoUri(id),
          httpHeaders: _api.headers,
        );
        _player = player;
        await player.initialize();
        if (!mounted || _selected != id) {
          await player.dispose();
          return;
        }
      }
      if (milliseconds != null)
        await player.seekTo(
          Duration(
            milliseconds: milliseconds.clamp(
              0,
              player.value.duration.inMilliseconds,
            ),
          ),
        );
      if (!mounted) return;
      if (milliseconds == null)
        await player.play();
      else
        await player.pause();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '视频暂时无法播放，请检查网络、服务认证和编码格式。');
    }
  }

  Future<void> _ask() async {
    final id = _selected, question = _question.text.trim();
    if (id == null || question.isEmpty) return;
    setState(() {
      _querying = true;
      _error = null;
    });
    final c = _api.config;
    final api = MediaApi(
      ObjectServiceConfig(baseUrl: c.baseUrl, token: c.token, useCloud: _cloud),
    );
    try {
      final answer = await api.query(id, question);
      if (mounted && id == _selected) setState(() => _answer = answer);
      await widget.controller.rememberSearch(question);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      api.close();
      if (mounted) setState(() => _querying = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sequence++;
    _cancellation?.cancel();
    _timer?.cancel();
    _question.dispose();
    _player?.dispose();
    _api.close();
    super.dispose();
  }

  String _status(String? status) =>
      {
        'queued': '等待分析',
        'running': '分析中',
        'paused': '已保存进度',
        'completed': '分析完成',
        'partial': '部分完成',
        'failed': '分析失败',
        'interrupted': '分析中断',
      }[status] ??
      '尚未分析';
  String _modeTitle(String? mode) => mode == 'objects'
      ? '物体追踪'
      : mode == 'safety'
      ? '安全分析'
      : '联合分析';
  @override
  Widget build(BuildContext context) {
    final selected = _videos.where((v) => v.id == _selected).firstOrNull;
    final player = _player;
    final safety = _job?['safety'] as Map?;
    final events = (_memory?.maps('events') ?? []).where((e) {
      final entity = _memory?.entityFor(e['subject_id']?.toString());
      if (_eventFilter == 'person') return entity?['entity_type'] == 'person';
      if (_eventFilter == 'risk')
        return {'flame', 'smoke', 'sparks'}.contains(e['action']);
      if (_eventFilter == 'object')
        return entity?['entity_type'] == 'object' &&
            !{'flame', 'smoke', 'sparks'}.contains(e['action']);
      return true;
    }).toList();
    final objects = _memory?.objectRecords(_api.config.baseUrl) ?? [];
    return PopScope(
      canPop: !_uploading,
      child: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            30 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const Text(
              '视频工作台',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '导入录像 → 安全分析或物体追踪 → 核对视频证据',
              style: TextStyle(color: Anju.muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _uploading || _command ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: const Text('选择并上传 MP4 视频'),
            ),
            if (_uploading)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_uploadName ?? '视频上传'),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _total == 0 ? null : _sent / _total,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _sent == _total && _total > 0
                          ? '视频已传完，正在检查格式并准备入库；完成后才会出现在录像库…'
                          : '${(_sent / 1024 / 1024).toStringAsFixed(1)} / ${(_total / 1024 / 1024).toStringAsFixed(1)} MiB',
                    ),
                    TextButton(
                      onPressed: () {
                        _cancellation?.cancel();
                        setState(() {});
                      },
                      child: Text(
                        _cancellation?.cancelled == true
                            ? '正在取消，等待当前片段结束…'
                            : '取消上传',
                      ),
                    ),
                  ],
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) InfoBanner(_error!, error: true),
            if (_health != null && _health!['analysis_ready'] != true)
              InfoBanner(
                '后端分析暂未就绪：${(_health!['configuration_error'] as Map?)?['message'] ?? '请在电脑端配置模型服务后重试。'}',
              ),
            const SectionTitle('录像库'),
            if (_videos.isEmpty && !_loading && _error == null)
              const Surface(
                child: EmptyState(
                  title: '还没有录像',
                  message: '上传一段 MP4，或连接已保存录像的电脑后端。',
                  icon: Icons.video_library_outlined,
                ),
              ),
            for (final video in _videos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Surface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    selected: video.id == _selected,
                    leading: Icon(
                      Icons.movie_outlined,
                      color: video.id == _selected ? Anju.green : Anju.muted,
                    ),
                    title: Text(
                      video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('时长 ${videoClock(video.durationMs)}'),
                    onTap: _uploading || _command
                        ? null
                        : () => _select(video.id),
                    trailing: IconButton(
                      tooltip: '删除录像',
                      onPressed: _uploading || _command
                          ? null
                          : () => _delete(video),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
            if (selected != null) ...[
              SectionTitle(selected.name),
              Surface(
                child: Column(
                  children: [
                    if (player?.value.isInitialized == true) ...[
                      AspectRatio(
                        aspectRatio: player!.value.aspectRatio,
                        child: VideoPlayer(player),
                      ),
                      VideoProgressIndicator(player, allowScrubbing: true),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: player,
                        builder: (_, value, child) => IconButton(
                          tooltip: value.isPlaying ? '暂停视频' : '播放视频',
                          onPressed: () =>
                              value.isPlaying ? player.pause() : player.play(),
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            size: 38,
                            color: Anju.green,
                          ),
                        ),
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: () => _play(),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('播放原视频'),
                      ),
                  ],
                ),
              ),
              const SectionTitle('选择分析任务'),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final mode in ['safety', 'objects'])
                    ChoiceChip(
                      label: Text(_modeTitle(mode)),
                      selected: _mode == mode,
                      onSelected: _running || _command
                          ? null
                          : (_) => setState(() {
                              _mode = mode;
                              _plan = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _mode == 'safety'
                    ? '电脑端小模型扫描摔倒、举手求助、可见明火，再使用已配置的大模型复核候选。'
                    : '电脑后端分析物体、位置和变化过程，生成带时间证据的踪迹。',
                style: const TextStyle(
                  fontSize: 12,
                  color: Anju.muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '分析调用和额度沿用后端配置；同一视频一次运行一个任务。',
                style: TextStyle(fontSize: 11, color: Anju.muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed:
                    _running ||
                        _command ||
                        _uploading ||
                        _health?['analysis_ready'] != true
                    ? null
                    : () => _analysis('start'),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(_command ? '正在提交…' : '开始${_modeTitle(_mode)}'),
              ),
              if (_running)
                TextButton(
                  onPressed: _command || _job?['pause_requested'] == true
                      ? null
                      : () => _analysis('pause'),
                  child: Text(
                    _job?['pause_requested'] == true ? '正在保存并暂停…' : '暂停当前任务',
                  ),
                ),
              if (!_running && _job?['resumable'] == true)
                OutlinedButton(
                  onPressed: _command ? null : () => _analysis('resume'),
                  child: Text(
                    '继续上次${_modeTitle(_job?['analysis_mode']?.toString())}',
                  ),
                ),
              if (_job != null) ...[
                const SizedBox(height: 14),
                InfoBanner(
                  '${_modeTitle(_job?['analysis_mode']?.toString())} · ${_status(_job?['status']?.toString())}',
                ),
                if (_running || _job?['resumable'] == true)
                  LinearProgressIndicator(
                    value: _job?['progress'] is num
                        ? ((_job!['progress'] as num).toDouble() / 100).clamp(
                            0.0,
                            1.0,
                          )
                        : null,
                  ),
                if (_job?['stage'] != null)
                  Text(
                    '当前阶段：${_job!['stage']}',
                    style: const TextStyle(fontSize: 11, color: Anju.muted),
                  ),
                if (_job?['error'] != null)
                  InfoBanner('任务说明：${_job!['error']}', error: true),
                if (_job?['retained_analysis'] != null)
                  const InfoBanner('包含保留的历史分析；保留记录未由本次任务重新识别。'),
              ],
              if (safety != null && safety['enabled'] == true)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '安全扫描与复核',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '扫描 ${safety['processed_frames'] ?? '待上报'} / ${safety['total_frames'] ?? '待上报'} 帧',
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          for (final pair in [
                            ['candidate_count', '候选'],
                            ['reviewed', '已复核'],
                            ['confirmed', '已确认'],
                            ['rejected', '已排除'],
                            ['uncertain', '不确定'],
                            ['unavailable', '复核不可用'],
                          ])
                            Text(
                              '${pair[1]} ${safety[pair[0]] ?? '待上报'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_plan != null && _plan!['message'] != null)
                InfoBanner(_plan!['message'].toString()),
              const SectionTitle('危险事件'),
              if (widget.controller.usesUnifiedBackend)
                const InfoBanner('以下为录像分析记录。正式确认与处理请打开统一告警；未复核候选不触发正式危险通知。'),
              if (_alerts.isEmpty)
                const Text(
                  '暂无已生成的危险事件；没有记录不等于现场没有风险。',
                  style: TextStyle(fontSize: 12, color: Anju.muted),
                ),
              for (final alert in _alerts.take(30))
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert['title']?.toString() ?? '危险候选',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '片内 ${videoClock((alert['start_ms'] as num?) ?? 0)} · ${alert['acknowledged'] == true ? '已知悉' : '待核实'}',
                        style: const TextStyle(fontSize: 12, color: Anju.muted),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _play(
                              milliseconds: ((alert['start_ms'] as num?) ?? 0)
                                  .toInt(),
                            ),
                            child: const Text('定位原片'),
                          ),
                          if (widget.controller.usesUnifiedBackend)
                            TextButton(
                              onPressed: () => _openUnifiedRecordingAlert(
                                selected.id,
                                alert,
                              ),
                              child: const Text('查看并处理统一告警'),
                            )
                          else if (alert['acknowledged'] != true)
                            TextButton(
                              onPressed: () async {
                                try {
                                  await _api.postJson(
                                    '${_api.videoPath(selected.id)}/alerts/${Uri.encodeComponent(alert['id'].toString())}/acknowledge',
                                  );
                                  await _readResults(selected.id, _sequence);
                                  await widget.controller.refresh();
                                } catch (e) {
                                  if (mounted) setState(() => _error = '$e');
                                }
                              },
                              child: const Text('我已知悉'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SectionTitle('物品踪迹'),
              if (objects.isEmpty)
                const Text(
                  '完成物体追踪任务后，物品及最后观察位置会显示在这里。',
                  style: TextStyle(fontSize: 12, color: Anju.muted),
                ),
              for (final object in objects.take(40))
                ListTile(
                  leading: const Icon(Icons.route_outlined, color: Anju.green),
                  title: Text(object.name),
                  subtitle: Text(
                    '${object.location} · ${videoClock(object.videoMs)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ObjectReplayScreen(
                        config: _api.config,
                        record: object,
                      ),
                    ),
                  ),
                ),
              const SectionTitle('人物、风险与物体时间线'),
              Wrap(
                spacing: 6,
                children: [
                  for (final item in const {
                    'all': '全部',
                    'person': '人物',
                    'risk': '家庭风险',
                    'object': '物体',
                  }.entries)
                    FilterChip(
                      label: Text(item.value),
                      selected: _eventFilter == item.key,
                      onSelected: (_) => setState(() {
                        _eventFilter = item.key;
                        _visibleEvents = 30;
                      }),
                    ),
                ],
              ),
              for (final event in events.take(_visibleEvents))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(_describe(event)),
                  subtitle: Text(
                    '${videoClock((event['start_ms'] as num?) ?? 0)} · ${event['epistemic_type'] == 'observed'
                        ? '观察记录'
                        : event['epistemic_type'] == 'inferred'
                        ? '推测线索'
                        : '未知'}',
                  ),
                  children: [
                    TextButton(
                      onPressed: () => _play(
                        milliseconds: ((event['start_ms'] as num?) ?? 0)
                            .toInt(),
                      ),
                      child: const Text('定位到这段原片'),
                    ),
                    for (final frame
                        in _memory!
                            .framesForEvidence(
                              (event['evidence_ids'] as List? ?? []).map(
                                (e) => e.toString(),
                              ),
                            )
                            .take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: EvidenceFrame(api: _api, frame: frame),
                      ),
                  ],
                ),
              if (events.length > _visibleEvents)
                TextButton(
                  onPressed: () => setState(() => _visibleEvents += 30),
                  child: const Text('显示更多事件'),
                ),
              const SectionTitle('带证据问答'),
              TextField(
                controller: _question,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '询问物品位置、活动经过或危险线索',
                  hintText: '例如：钥匙最后在哪里出现？',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用服务端模型增强'),
                subtitle: const Text('关闭时查询已有记录；开启后提问可能消耗模型额度。'),
                value: _cloud,
                onChanged: _querying ? null : (v) => setState(() => _cloud = v),
              ),
              OutlinedButton.icon(
                onPressed: _querying || _memory == null ? null : _ask,
                icon: const Icon(Icons.question_answer_outlined),
                label: Text(_querying ? '正在查询…' : '查询已有视频记录'),
              ),
              if (_answer != null)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _answer!['answer']?.toString() ?? '未返回可用结论',
                        style: const TextStyle(height: 1.7),
                      ),
                      if (_answer!['coverage_note'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _answer!['coverage_note'].toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Anju.muted,
                            ),
                          ),
                        ),
                      for (final frame
                          in _memory!
                              .framesForEvidence(
                                (_answer!['evidence'] as List? ?? [])
                                    .whereType<Map>()
                                    .map((e) => e['id'].toString()),
                              )
                              .take(4))
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: EvidenceFrame(api: _api, frame: frame),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WebWorkspaceScreen(config: _api.config),
                  ),
                ),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('打开完整工作台与高级证据工具'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _describe(Map<String, dynamic> event) {
    final subject =
        _memory
            ?.entityFor(event['subject_id']?.toString())?['label']
            ?.toString() ??
        '目标';
    final target =
        _memory
            ?.entityFor(event['target_id']?.toString())?['label']
            ?.toString() ??
        '';
    final action =
        {
          'seen_at': '出现于',
          'place_on': '放到',
          'pick_up': '拿起',
          'put_in': '放入',
          'take_out': '取出',
          'move': '移动至',
          'explicit_exit': '离开画面',
          'walk': '行走',
          'sit_down': '坐下',
          'stand_up': '起身',
          'lie_down': '躺下',
          'lying_on_floor': '躺卧于地面',
          'fall': '疑似跌倒',
          'help_gesture': '疑似求助手势',
          'climb': '攀爬',
          'flame': '出现明火候选',
          'smoke': '出现烟雾候选',
          'sparks': '出现火花候选',
          'unknown': '情况未知',
        }[event['action']] ??
        '有一条记录';
    return '$subject · $action${target.isEmpty ? '' : ' $target'}';
  }
}
