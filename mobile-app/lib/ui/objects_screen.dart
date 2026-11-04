import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../app_controller.dart';
import '../models/household.dart';
import '../services/object_api.dart';
import 'widgets.dart';
import 'media_hub_screen.dart';

class ObjectsScreen extends StatefulWidget {
  const ObjectsScreen({super.key, required this.controller});
  final SafetyController controller;
  @override
  State<ObjectsScreen> createState() => _ObjectsScreenState();
}

class _ObjectsScreenState extends State<ObjectsScreen> {
  final _search = TextEditingController();
  ObjectApi? _api;
  ObjectServiceConfig? _config;
  List<Recording> _videos = [];
  String? _selected;
  VideoMemory? _memory;
  Map<String, dynamic>? _answer;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant ObjectsScreen old) {
    super.didUpdateWidget(old);
    if (!identical(_config, widget.controller.household.objects)) _configure();
  }

  void _configure() {
    _generation++;
    _api?.close();
    _api = null;
    _config = widget.controller.household.objects;
    _videos = [];
    _selected = null;
    _memory = null;
    _answer = null;
    _error = null;
    _busy = false;
    {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _api?.close();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final config = widget.controller.household.objects;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
    });
    try {
      final api = _api ??= ObjectApi(config);
      final videos = await api.recordings();
      if (!mounted || generation != _generation) return;
      final selected =
          videos.where((v) => v.id == _selected).firstOrNull ??
          videos.firstOrNull;
      setState(() {
        _videos = videos;
        _selected = selected?.id;
        _memory = null;
      });
      if (selected != null) {
        final memory = await api.memory(selected.id);
        if (!mounted || generation != _generation) return;
        setState(() => _memory = memory);
        await widget.controller.addRecentObjects(
          memory.objectRecords(config.baseUrl),
        );
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _selectVideo(String id) async {
    setState(() => _selected = id);
    await _refresh();
  }

  List<RecentObject> get _records {
    final config = widget.controller.household.objects;
    final saved = widget.controller.household.recentObjects
        .where((e) => e.source == 'video' && e.serviceUrl == config.baseUrl)
        .toList();
    return saved;
  }

  Future<void> _query() async {
    final question = _search.text.trim();
    if (question.isEmpty) return;
    if (question.length > 200) {
      setState(() => _error = '问题请控制在 200 字以内');
      return;
    }
    final config = widget.controller.household.objects;
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
    });
    final generation = _generation;
    try {
      await widget.controller.rememberSearch(question);
      if (!mounted || generation != _generation) return;
      if (_selected == null) throw const FormatException('请先连接并选择一段已分析录像');
      final q = RegExp(r'哪里|在哪|位置|历史|经过|什么时候|最后').hasMatch(question)
          ? question
          : '$question最后在哪里出现？';
      final answer = await (_api ??= ObjectApi(config)).query(_selected!, q);
      if (mounted && generation == _generation)
        setState(() => _answer = answer);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _openRecord(RecentObject item) async {
    final config = widget.controller.household.objects;
    if (item.serviceUrl != config.baseUrl) {
      setState(() => _error = '请先连接这条记录所属的录像服务');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ObjectReplayScreen(config: config, record: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, config = c.household.objects;
    final query = _search.text.trim().toLowerCase();
    final records = _records
        .where(
          (e) =>
              query.isEmpty ||
              e.name.toLowerCase().contains(query) ||
              e.location.toLowerCase().contains(query),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey('objects'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '物品寻找',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '录像与模型接口',
                onPressed: () => configureObjectService(context, c),
                icon: const Icon(
                  Icons.settings_input_component_outlined,
                  color: Anju.green,
                ),
              ),
            ],
          ),
          const Text(
            '从最后看见的位置，找回物品线索',
            style: TextStyle(fontSize: 12, color: Anju.muted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _busy ? null : _query(),
            textInputAction: TextInputAction.search,
            maxLength: 200,
            decoration: InputDecoration(
              counterText: '',
              hintText: '搜索钥匙、背包、杯子…',
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: '查询录像',
                onPressed: _busy ? null : _query,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Anju.green,
                ),
              ),
            ),
          ),
          if (c.household.searches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                for (final text in c.household.searches.take(5))
                  ActionChip(
                    label: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      _search.text = text;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '视频物体追踪',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  '上传录像，分析物品位置变化，回看每条踪迹的时间证据。',
                  style: TextStyle(fontSize: 12, color: Anju.muted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => openMediaHub(context, c, mode: 'objects'),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('导入视频 / 查看录像库'),
                ),
              ],
            ),
          ),
          SectionTitle(
            '原项目录像',
            action: TextButton(
              onPressed: () => configureObjectService(context, c),
              child: Text('配置服务 ›'),
            ),
          ),
          ...[
            Pill(
              config.useCloud ? '云模型增强已开启' : '仅读已有记录 · 云增强关闭',
              color: config.useCloud ? const Color(0xffb87822) : Anju.green,
            ),
            const SizedBox(height: 12),
            if (_videos.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selected,
                key: ValueKey('${config.baseUrl}|$_selected'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '选择已分析录像'),
                items: _videos
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(v.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) {
                        if (id != null) _selectVideo(id);
                      },
              ),
            if (_videos.isEmpty && !_busy)
              const Surface(
                child: EmptyState(
                  title: '暂无可用录像',
                  message: '请先在原项目导入并完成分析，再下拉刷新。',
                  icon: Icons.video_library_outlined,
                ),
              ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null) InfoBanner(_error!, error: true),
          if (_memory?.data['is_mock'] == true)
            const InfoBanner('服务端将此录像标记为模拟分析，请勿作为真实识别结论。'),
          if (_answer != null) ...[
            const SectionTitle('查询结果'),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_answer!['answer'] ?? '未返回可用结论').toString(),
                    style: const TextStyle(fontSize: 14, height: 1.8),
                  ),
                  if (_answer!['coverage_note'] != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _answer!['coverage_note'].toString(),
                      style: const TextStyle(fontSize: 11, color: Anju.muted),
                    ),
                  ],
                  if (_memory != null)
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
                        child: EvidenceFrame(api: _api!, frame: frame),
                      ),
                ],
              ),
            ),
          ],
          SectionTitle('最近物品历史', caption: '当前服务的最近查阅记录'),
          if (records.isEmpty)
            const Surface(
              child: EmptyState(
                title: '暂无匹配的物品线索',
                message: '换一个关键词，或先上传视频或连接录像服务。',
                icon: Icons.manage_search_rounded,
              ),
            ),
          for (final item in records.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Anju.light,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.source == 'local'
                          ? Icons.photo_outlined
                          : Icons.inventory_2_outlined,
                      color: Anju.green,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Pill('录像记录'),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${item.location}\n${item.source == 'video' ? '录像内 ${videoClock(item.videoMs)}' : '导入于 ${shortTime(item.recordedAt)}'}',
                      style: const TextStyle(fontSize: 11, color: Anju.muted),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  onTap: () => _openRecord(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> configureObjectService(BuildContext context, SafetyController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.viewInsetsOf(ctx).bottom +
              MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: _ObjectConfigSheet(controller: c),
      ),
    );

class _ObjectConfigSheet extends StatefulWidget {
  const _ObjectConfigSheet({required this.controller});
  final SafetyController controller;
  @override
  State<_ObjectConfigSheet> createState() => _ObjectConfigSheetState();
}

class _ObjectConfigSheetState extends State<_ObjectConfigSheet> {
  late final TextEditingController _url, _token;
  late bool _cloud;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    final c = widget.controller.household.objects;
    _url = TextEditingController(text: c.baseUrl);
    _token = TextEditingController(text: c.token);
    _cloud = c.useCloud;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final current = widget.controller.household.objects;
      final config = ObjectServiceConfig(
        baseUrl: current.baseUrl,
        token: current.token,
        useCloud: _cloud,
      );
      {
        final api = ObjectApi(config);
        try {
          await api.recordings();
        } finally {
          api.close();
        }
      }
      await widget.controller.saveObjectConfig(config);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '录像与物品服务',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        SelectableText('统一后端：${widget.controller.settings.baseUrl}'),
        const SizedBox(height: 12),
        const InfoBanner('录像、物品与统一告警使用同一地址和令牌。在“我的 → 连接服务”修改统一连接。'),
        TextButton.icon(
          onPressed: () => openMediaSettings(context, widget.controller),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('修改统一连接'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用服务端大模型增强'),
          subtitle: const Text('默认关闭；开启后，提交录像问题可能消耗服务端模型 token'),
          value: _cloud,
          onChanged: _busy ? null : (v) => setState(() => _cloud = v),
        ),
        if (_message != null) InfoBanner(_message!, error: true),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '检查连接中…' : '保存问答设置'),
          ),
        ),
      ],
    ),
  );
}

class ObjectReplayScreen extends StatefulWidget {
  const ObjectReplayScreen({
    super.key,
    required this.config,
    required this.record,
  });
  final ObjectServiceConfig config;
  final RecentObject record;
  @override
  State<ObjectReplayScreen> createState() => _ObjectReplayScreenState();
}

class _ObjectReplayScreenState extends State<ObjectReplayScreen> {
  late final ObjectApi _api;
  VideoMemory? _memory;
  Map<String, dynamic>? _replay;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _api = ObjectApi(widget.config);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _api.memory(widget.record.videoId),
        _api.replay(widget.record.videoId, widget.record.entityId),
      ]);
      if (mounted)
        setState(() {
          _memory = values[0] as VideoMemory;
          _replay = values[1] as Map<String, dynamic>;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.record.name}的历史'),
      actions: [
        IconButton(
          tooltip: '刷新历史',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (_error != null) InfoBanner(_error!, error: true),
              const InfoBanner('以下为录像中的历史观察，不保证物品仍在现实中的相同位置。'),
              if (_replay != null) ...[
                if (_replay!['is_mock'] == true)
                  const InfoBanner('服务端标记：模拟分析记录'),
                const SectionTitle('原片回看'),
                EvidenceVideo(
                  api: _api,
                  videoId: widget.record.videoId,
                  startMs: widget.record.videoMs,
                ),
                const SectionTitle('物品时间线'),
                for (final entry
                    in (_replay!['entries'] as List? ?? [])
                        .whereType<Map>()) ...[
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pill(
                          '${videoClock((entry['start_ms'] as num?) ?? 0)} — ${videoClock((entry['end_ms'] as num?) ?? 0)}',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _describeEntry(entry, _memory!),
                          style: const TextStyle(fontSize: 13, height: 1.7),
                        ),
                        for (final frame
                            in _memory!
                                .framesForEvidence(
                                  (entry['evidence_ids'] as List? ?? []).map(
                                    (e) => e.toString(),
                                  ),
                                )
                                .take(3))
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: EvidenceFrame(api: _api, frame: frame),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if ((_replay!['entries'] as List? ?? []).isEmpty)
                  const EmptyState(
                    title: '暂无可回看的物品事件',
                    message: '请确认原项目已完成这件物品的分析。',
                  ),
                for (final note in (_replay!['unknowns'] as List? ?? []))
                  InfoBanner(note.toString()),
              ],
            ],
          ),
  );
  String _describeEntry(Map entry, VideoMemory memory) {
    if (entry['condition'] != null) return entry['condition'].toString();
    final event = entry['event'] as Map? ?? {};
    final target = memory.entityFor(event['target_id']?.toString());
    final action = switch (event['action']) {
      'seen_at' => '出现在',
      'pick_up' => '被拿起',
      'place_on' => '被放到',
      'put_in' => '被放入',
      'take_out' => '被取出',
      'move' => '发生移动',
      'explicit_exit' => '离开画面',
      _ => '被记录',
    };
    return '${entry['epistemic_type'] == 'inferred' ? '推测线索：' : '观察记录：'}${widget.record.name}$action${target == null ? '' : target['label']}。';
  }
}

class EvidenceFrame extends StatefulWidget {
  const EvidenceFrame({super.key, required this.api, required this.frame});
  final ObjectApi api;
  final Map<String, dynamic> frame;
  @override
  State<EvidenceFrame> createState() => _EvidenceFrameState();
}

class _EvidenceFrameState extends State<EvidenceFrame> {
  late Future<Uint8List> _image;
  @override
  void initState() {
    super.initState();
    _image = widget.api.frame(widget.frame['url']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant EvidenceFrame old) {
    super.didUpdateWidget(old);
    if (old.frame['id'] != widget.frame['id'] ||
        old.frame['url'] != widget.frame['url'] ||
        !identical(old.api, widget.api))
      _image = widget.api.frame(widget.frame['url']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const InfoBanner('证据帧暂不可用，请检查录像服务');
      if (!snapshot.hasData)
        return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              snapshot.data!,
              semanticLabel: '原录像证据帧',
              errorBuilder: (_, _, _) => const InfoBanner('证据图片无法解码'),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '原片 ${videoClock((widget.frame['pts_ms'] as num?) ?? 0)}',
            style: const TextStyle(fontSize: 11, color: Anju.muted),
          ),
        ],
      );
    },
  );
}

class EvidenceVideo extends StatefulWidget {
  const EvidenceVideo({
    super.key,
    required this.api,
    required this.videoId,
    this.startMs = 0,
    this.playbackPath,
  });
  final ObjectApi api;
  final String videoId;
  final int startMs;
  final String? playbackPath;
  @override
  State<EvidenceVideo> createState() => _EvidenceVideoState();
}

class _EvidenceVideoState extends State<EvidenceVideo> {
  VideoPlayerController? _player;
  String? _error;
  bool _busy = false;
  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final player = VideoPlayerController.networkUrl(
        widget.playbackPath == null
            ? widget.api.videoUri(widget.videoId)
            : widget.api.uri(widget.playbackPath!),
        httpHeaders: widget.api.headers,
      );
      _player = player;
      await player.initialize();
      if (!mounted) return;
      await player.seekTo(
        Duration(
          milliseconds: widget.startMs.clamp(
            0,
            player.value.duration.inMilliseconds,
          ),
        ),
      );
      if (!mounted) return;
      await player.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '原片暂时无法播放，请检查网络、权限与视频编码。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Surface(
      child: Column(
        children: [
          if (_error != null) InfoBanner(_error!, error: true),
          if (player?.value.isInitialized == true) ...[
            AspectRatio(
              aspectRatio: player!.value.aspectRatio,
              child: VideoPlayer(player),
            ),
            VideoProgressIndicator(player, allowScrubbing: true),
            const SizedBox(height: 10),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: player,
              builder: (context, value, _) => IconButton(
                tooltip: value.isPlaying ? '暂停原片' : '播放原片',
                onPressed: () =>
                    value.isPlaying ? player.pause() : player.play(),
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: Anju.green,
                  size: 36,
                ),
              ),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(
                _busy ? '加载原片中…' : '从 ${videoClock(widget.startMs)} 回看原片',
              ),
            ),
        ],
      ),
    );
  }
}
