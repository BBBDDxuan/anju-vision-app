import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import 'widgets.dart';
import '../models/household.dart';
import 'member_widgets.dart';
import '../models/unified_alert.dart';
import '../services/object_api.dart';
import 'objects_screen.dart' show EvidenceVideo;

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.controller,
    required this.eventId,
    this.location,
  });
  final SafetyController controller;
  final String eventId;
  final AlertLocation? location;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  SafetyEvent? _event;
  Uint8List? _image;
  String? _error;
  String? _imageError;
  bool _loading = true;
  bool _acting = false;
  int _loadVersion = 0;
  late final String _scope;
  ObjectApi? _playbackApi;

  @override
  void initState() {
    super.initState();
    _scope = widget.location?.scope ?? widget.controller.alertScope;
    widget.controller.addListener(_syncEvent);
    _load();
  }

  void _syncEvent() {
    if (!mounted) return;
    if (widget.controller.usesUnifiedBackend &&
        widget.controller.alertScope != _scope) {
      _loadVersion++;
      setState(() {
        _event = null;
        _image = null;
        _loading = false;
        _error = '连接已切换，请返回当前服务重新打开告警';
      });
      return;
    }
    if (_loading || _acting) return;
    for (final e in widget.controller.events) {
      if (e.id != widget.eventId ||
          (e.isUnified && _event != null && e.revision < _event!.revision))
        continue;
      if (e.evidenceId != _event?.evidenceId) {
        _load();
        return;
      }
      setState(() => _event = e);
      break;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncEvent);
    _playbackApi?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
      _image = null;
      _imageError = null;
    });
    try {
      if (widget.controller.usesUnifiedBackend &&
          _scope != widget.controller.alertScope)
        throw StateError('通知所属后端与当前连接不同');
      final event = await widget.controller.loadEvent(widget.eventId);
      if (widget.location != null &&
          event.details['source'] != widget.location!.source)
        throw StateError('通知来源与告警详情不匹配');
      if (event.fromVideo && _playbackApi == null)
        _playbackApi = ObjectApi(widget.controller.household.objects);
      Uint8List? image;
      String? imageError;
      if (widget.controller.isLocalEvent(event.id) ||
          (event.evidenceId != null && event.evidenceId!.isNotEmpty)) {
        try {
          image = await widget.controller.evidenceFor(event);
        } catch (error) {
          imageError = '$error';
        }
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _event = event;
        _image = image;
        _imageError = imageError;
      });
    } catch (error) {
      if (mounted && version == _loadVersion) setState(() => _error = '$error');
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _act(bool resolve) async {
    if (_acting || _loading || _event == null) return;
    if (_event!.withdrawn ||
        (resolve && _event!.fromVideo && !_event!.isUnified))
      return;
    setState(() => _acting = true);
    if (resolve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('标记事件已解决？'),
          content: const Text('请在已核实家中情况并完成处理后标记。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('已核实，解决'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _acting = false);
        return;
      }
    }
    setState(() {
      _acting = true;
      _error = null;
    });
    var mutationCompleted = false;
    try {
      if (resolve) {
        await widget.controller.resolveEvent(widget.eventId);
      } else {
        await widget.controller.acknowledgeEvent(widget.eventId);
      }
      mutationCompleted = true;
      final event = await widget.controller.loadEvent(widget.eventId);
      if (mounted) setState(() => _event = event);
      await widget.controller.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              event.fromVideo
                  ? '已确认录像记录并刷新详情'
                  : resolve
                  ? '已提交解决并刷新状态'
                  : '已提交确认并刷新状态',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted)
        setState(
          () => _error = mutationCompleted
              ? '操作已提交，但状态刷新失败，请刷新核实后再操作。$error'
              : '$error',
        );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final color = event == null
        ? Anju.green
        : event.resolved
        ? Anju.green
        : severityColor(event.severity);
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件详情'),
        actions: [
          IconButton(
            tooltip: '刷新详情',
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: event == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Anju.line)),
                ),
                child: event.resolved || event.withdrawn
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Anju.green),
                          SizedBox(width: 9),
                          Text(
                            event.withdrawn ? '来源已撤销，不再提醒' : '这条事件已解决',
                            style: TextStyle(
                              color: Anju.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _acting || event.acknowledged
                                  ? null
                                  : () => _act(false),
                              child: Text(
                                event.acknowledged
                                    ? '已确认收到'
                                    : event.fromVideo
                                    ? '确认录像记录'
                                    : '我已收到',
                              ),
                            ),
                          ),
                          if (!event.fromVideo || event.isUnified) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _acting ? null : () => _act(true),
                                child: Text(_acting ? '正在处理…' : '标记已解决'),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (_error != null) InfoBanner(_error!, error: true),
                  if (widget.controller.videoError != null)
                    InfoBanner(
                      '录像服务：${widget.controller.videoError}',
                      error: true,
                    ),
                  if (widget.controller.error != null)
                    InfoBanner('统一后端：${widget.controller.error}', error: true),
                  if (event == null)
                    const EmptyState(
                      title: '事件暂时无法读取',
                      message: '请检查网络，点击右上角刷新重试。',
                    ),
                  if (event != null) ...[
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  eventIcon(event.eventType),
                                  size: 29,
                                  color: color,
                                ),
                              ),
                              const Spacer(),
                              Pill(eventStateLabel(event), color: color),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            eventTypeLabel(event.eventType),
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${eventSourceLabel(event, widget.controller.nameForDevice(event.deviceId))} · ${eventTimeLabel(event)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Anju.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: color,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    event.fromVideo
                                        ? '这是上传录像中的历史线索。请结合证据核实，再确认收到或标记处理完毕。'
                                        : event.resolved
                                        ? '已记录处理结果，感谢你的及时回应。'
                                        : event.acknowledged
                                        ? '你已确认收到，请核实现场情况后完成处理。'
                                        : '请先核对现场信息，确认家人和设备的实际情况。',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPersonEvent(event)) ...[
                      const SizedBox(height: 16),
                      MemberAssociationCard(
                        controller: widget.controller,
                        event: event,
                      ),
                    ],
                    if (event.fromVideo) ...[
                      const SizedBox(height: 16),
                      Surface(
                        child: SelectableText(
                          '录像编号：${event.details['video_id'] ?? '未提供'}\n来源服务：${event.isUnified ? widget.controller.settings.baseUrl : event.details['source_url'] ?? '未提供'}\n片内位置：${eventTimeLabel(event)}',
                          style: const TextStyle(fontSize: 12, height: 1.8),
                        ),
                      ),
                    ],
                    if (event.fromVideo &&
                        event.details['playback_url'] is String &&
                        _playbackApi != null) ...[
                      const SizedBox(height: 16),
                      EvidenceVideo(
                        key: ValueKey('$_scope|${event.id}'),
                        api: _playbackApi!,
                        videoId: event.details['video_id']?.toString() ?? '',
                        playbackPath: event.details['playback_url'] as String,
                        startMs:
                            (event.details['start_ms'] as num?)?.toInt() ?? 0,
                      ),
                    ],
                    SectionTitle(
                      event.fromVideo
                          ? '录像证据'
                          : widget.controller.isLocalEvent(event.id)
                          ? '历史证据'
                          : '现场证据',
                      caption: event.fromVideo ? '原录像截图，不代表实时画面' : '从可核对的信息开始',
                    ),
                    if (_image != null)
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => Dialog.fullscreen(
                            backgroundColor: Colors.black,
                            child: Stack(
                              children: [
                                Center(
                                  child: InteractiveViewer(
                                    minScale: .5,
                                    maxScale: 5,
                                    child: Image.memory(_image!),
                                  ),
                                ),
                                SafeArea(
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: IconButton(
                                      tooltip: '关闭图片',
                                      color: Colors.white,
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.memory(
                            _image!,
                            fit: BoxFit.contain,
                            semanticLabel: event.fromVideo
                                ? '原录像证据，点击放大'
                                : '现场证据，点击放大',
                            errorBuilder: (_, _, _) =>
                                const InfoBanner('图片解码失败，请刷新重试', error: true),
                          ),
                        ),
                      ),
                    if (_image == null)
                      Surface(
                        child: EmptyState(
                          title: _imageError == null
                              ? (event.fromVideo ? '暂未提供录像截图' : '暂未提供截图')
                              : '证据截图暂不可用',
                          message: _imageError ?? '该事件来源未上传图片，稍后可下拉刷新。',
                          icon: Icons.image_not_supported_outlined,
                        ),
                      ),
                    SectionTitle(
                      event.fromVideo
                          ? '录像证据说明'
                          : widget.controller.isLocalEvent(event.id)
                          ? '本机模型说明'
                          : 'AI 复核说明',
                    ),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_outlined,
                                color: Anju.green,
                                size: 20,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  reviewLabel(event.reviewStatus),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            event.reviewSummary.isEmpty
                                ? (event.fromVideo
                                      ? '该录像记录暂未提供详细说明。'
                                      : '复核说明尚未生成，请稍后刷新。')
                                : event.reviewSummary,
                            style: const TextStyle(fontSize: 13, height: 1.85),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            event.fromVideo
                                ? '录像观察与推断表示证据类型，不代表已完成大模型复核；历史线索需结合原片核实。'
                                : '复核状态表示任务进度，实际情况仍需人工核实。',
                            style: TextStyle(fontSize: 11, color: Anju.muted),
                          ),
                        ],
                      ),
                    ),
                    const SectionTitle('处理进度'),
                    Surface(
                      child: Column(
                        children: [
                          _step(
                            event.fromVideo ? '录像线索已记录' : '事件已记录',
                            event.fromVideo
                                ? eventTimeLabel(event)
                                : displayTime(event.occurredAt),
                            true,
                            false,
                          ),
                          _step(
                            notificationLabel(event.notificationStatus),
                            event.fromVideo
                                ? '仅在 App 前台同步，不等同后台系统推送'
                                : '供应商受理不等于手机实际收到',
                            event.notificationStatus == 'sent' ||
                                event.notificationStatus ==
                                    'foreground_polling',
                            false,
                          ),
                          _step(
                            event.acknowledged ? '已确认收到' : '等待家属回应',
                            event.acknowledged
                                ? '已记录确认状态'
                                : event.fromVideo
                                ? '点击底部“确认录像记录”'
                                : '点击底部“我已收到”',
                            event.acknowledged,
                            event.fromVideo,
                          ),
                          if (!event.fromVideo)
                            _step(
                              event.resolved ? '事件已解决' : '等待核实与处理',
                              event.resolved ? '处理状态已更新' : '核实现场后，再标记已解决',
                              event.resolved,
                              true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Surface(
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        title: const Text(
                          '查看记录信息',
                          style: TextStyle(fontSize: 13),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          18,
                          0,
                          18,
                          18,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              '事件编号：${event.id}\n设备编号：${event.deviceId}\n创建时间：${displayTime(event.createdAt)}\n'
                              '${event.eventType == 'device_offline' ? '心跳超时事件，无模型评分' : '模型评分：${event.confidence == null ? '未知' : '${(event.confidence! * 100).toStringAsFixed(1)}%'}（非事故概率）'}',
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.8,
                                color: Anju.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _step(String title, String subtitle, bool done, bool last) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  Icon(
                    done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: done ? Anju.green : const Color(0xffcfdbdd),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        color: Anju.line,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: done ? Anju.ink : Anju.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Anju.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
