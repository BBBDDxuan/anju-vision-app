import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../services/members_api.dart';
import '../services/object_api.dart' show videoClock;
import 'widgets.dart';

/// Candidate pixels are display-only. Decisions are scoped to a server session.
class ManualTracksPanel extends StatefulWidget {
  const ManualTracksPanel({
    super.key,
    required this.controller,
    this.videoId,
    this.positionMs,
    this.active = true,
    this.onChanged,
    this.apiFactory,
  });
  final SafetyController controller;
  final String? videoId;
  final int Function()? positionMs;
  final bool active;
  final VoidCallback? onChanged;
  final MembersApi Function()? apiFactory;
  @override
  State<ManualTracksPanel> createState() => _ManualTracksPanelState();
}

class _ManualTracksPanelState extends State<ManualTracksPanel>
    with WidgetsBindingObserver {
  Timer? _timer;
  MembersApi? _api;
  String? _session, _error;
  String _scope = '';
  Map<String, dynamic>? _data;
  bool _polling = false, _saving = false, _foreground = true;
  int _epoch = 0;
  bool _videoSession = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_connectionChanged);
    _start();
  }

  String get _currentScope =>
      '${widget.controller.serviceScope}|${widget.controller.settings.bearerToken}';
  void _connectionChanged() {
    if (_scope != _currentScope) _start();
  }

  @override
  void didUpdateWidget(covariant ManualTracksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.active != widget.active)
      _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _start();
  }

  void _release() {
    _saving = false;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    final api = _api, session = _session;
    _api = null;
    _session = null;
    _data = null;
    _polling = false;
    if (api != null) {
      if (_videoSession && session != null) {
        unawaited(
          api
              .request('DELETE', '/api/manual-tracks/$session')
              .catchError((_) => <String, dynamic>{})
              .whenComplete(api.close),
        );
      } else {
        api.close();
      }
    }
  }

  void _start() {
    _release();
    _scope = _currentScope;
    if (!widget.controller.usesSharedMembers || !widget.active || !_foreground)
      return;
    _videoSession = widget.videoId != null;
    try {
      _api =
          widget.apiFactory?.call() ?? MembersApi(widget.controller.settings);
    } catch (_) {
      return;
    }
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    if (_polling || _saving || _api == null) return;
    _polling = true;
    final epoch = _epoch, api = _api!;
    try {
      unawaited(widget.controller.refreshMembers());
      Map<String, dynamic> next;
      if (widget.videoId != null) {
        if (_session == null) {
          final opened = await api.request(
            'POST',
            '/api/manual-tracks/video-sessions',
            json: {'video_id': widget.videoId},
          );
          if (!mounted || epoch != _epoch) {
            unawaited(
              api
                  .request(
                    'DELETE',
                    '/api/manual-tracks/${opened['session_id']}',
                  )
                  .catchError((_) => <String, dynamic>{}),
            );
            return;
          }
          _session = opened['session_id'] as String;
        }
        next = await api.request(
          'POST',
          '/api/manual-tracks/$_session/position',
          json: {'position_ms': widget.positionMs?.call() ?? 0},
        );
      } else {
        next = await api.request('GET', '/api/manual-tracks/live');
      }
      if (mounted && epoch == _epoch)
        setState(() {
          _data = next;
          _error = null;
        });
      if (mounted &&
          epoch == _epoch &&
          (next['segments'] as List? ?? []).isNotEmpty)
        widget.onChanged?.call();
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() {
          _data = null;
          _error = widget.videoId == null
              ? '人物候选暂不可用，请保持电脑监护开启并检查连接'
              : '尚无人物跟踪索引或会话已过期；请重新运行本地安全分析并打开录像';
        });
    } finally {
      if (epoch == _epoch) _polling = false;
    }
  }

  Future<void> _assign(Map<String, dynamic> track, String value) async {
    final session = _data?['session_id'], api = _api;
    if (_saving || session == null || api == null) return;
    final epoch = ++_epoch;
    _polling = false;
    setState(() => _saving = true);
    try {
      final next = await api.request(
        'PUT',
        '/api/manual-tracks/$session/tracks/${Uri.encodeComponent(track['id'] as String)}',
        json: {
          'version': track['version'],
          'status': value.startsWith('member:') ? 'member' : value,
          'member_id': value.startsWith('member:') ? value.substring(7) : null,
        },
      );
      if (mounted && epoch == _epoch)
        setState(() {
          _data = next;
          _error = null;
        });
      if (mounted && epoch == _epoch) widget.onChanged?.call();
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() => _error = '关联未保存，人物可能已丢失；请刷新后重新确认');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_connectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  Widget _crop(String value) {
    if (!value.startsWith('data:image/png;base64,'))
      return const Icon(Icons.person_outline);
    try {
      return Image.memory(
        base64Decode(value.split(',').last),
        width: 56,
        height: 84,
        filterQuality: FilterQuality.none,
        fit: BoxFit.contain,
        semanticLabel: '像素化人物候选',
        errorBuilder: (_, error, stack) => const Icon(Icons.person_outline),
      );
    } catch (_) {
      return const Icon(Icons.person_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = (_data?['tracks'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final segments = (_data?['segments'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '人物候选 · 人工关联',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '刷新人物候选',
                onPressed: _saving ? null : () => unawaited(_poll()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            '来源：${widget.videoId ?? '本机摄像头'}',
            style: const TextStyle(fontSize: 12),
          ),
          const Text(
            '仅对当前 track 生效；丢失、断流或 30 秒未更新后重新确认。截图已整体像素化。',
            style: TextStyle(fontSize: 12, color: Anju.muted),
          ),
          if (_error != null) InfoBanner(_error!, error: true),
          if (tracks.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('当前没有活跃的人物候选'),
            ),
          for (final track in tracks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _crop(track['crop']?.toString() ?? ''),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track['id'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.videoId == null
                              ? '截图：${track['captured_at'] ?? '时间待更新'}'
                              : '截图位置：${videoClock((track['crop_ms'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          (track['association'] as Map?)?['label']
                                  ?.toString() ??
                              '待确认',
                        ),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: 'select',
                          decoration: const InputDecoration(labelText: '人工选择'),
                          items: [
                            const DropdownMenuItem(
                              value: 'select',
                              child: Text('选择成员或标记'),
                            ),
                            for (final member in widget.controller.members)
                              DropdownMenuItem(
                                value: 'member:${member.id}',
                                child: Text(
                                  member.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const DropdownMenuItem(
                              value: 'pending',
                              child: Text('待确认'),
                            ),
                            const DropdownMenuItem(
                              value: 'stranger',
                              child: Text('陌生人（人工标记）'),
                            ),
                            const DropdownMenuItem(
                              value: 'ignored',
                              child: Text('忽略'),
                            ),
                          ],
                          onChanged: _saving || track['active'] != true
                              ? null
                              : (v) {
                                  if (v != null && v != 'select')
                                    unawaited(_assign(track, v));
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (segments.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('本次会话关联分段', style: TextStyle(fontSize: 13)),
              children: [
                for (final segment in segments)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${segment['track_id']} · ${(segment['association'] as Map)['label']}',
                    ),
                    subtitle: Text(
                      widget.videoId == null
                          ? (segment['end_ms'] == null ? '当前有效' : '已失效')
                          : '${videoClock(segment['start_ms'] as num)}–${segment['end_ms'] == null ? '当前' : videoClock(segment['end_ms'] as num)}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
