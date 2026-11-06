import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/household.dart';
import 'members_screen.dart' show editMember, bindMemberDevices;
import 'widgets.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({
    super.key,
    required this.controller,
    required this.memberId,
    required this.openEvent,
  });
  final SafetyController controller;
  final String memberId;
  final void Function(String) openEvent;
  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  late final String _scope;
  bool _busy = false, _consent = false;
  String? _message;
  Uint8List? _trialPhoto;
  Map<String, dynamic>? _trial;
  void _discardTrial() {
    if (_trialPhoto != null) MemoryImage(_trialPhoto!).evict();
    _trial = null;
    _trialPhoto = null;
  }

  @override
  void dispose() {
    _discardTrial();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.controller.serviceScope;
  }

  Future<void> _enroll(MemberProfile member, {bool trial = false}) async {
    if ((!trial && !_consent) || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _discardTrial();
    });
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (picked == null || !mounted) return;
      // Android photo providers may return content:// URIs without a file path.
      // Read through the picker and bound the stream before sending raw bytes.
      final size = await picked.length();
      if (size != null && size > 5 * 1024 * 1024)
        throw StateError('照片超过 5 MiB，请先缩小');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in picked.readAsByteStream()) {
        if (bytes.length + chunk.length > 5 * 1024 * 1024)
          throw StateError('照片超过 5 MiB，请先缩小');
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      if (!mounted || widget.controller.serviceScope != _scope) return;
      if (trial) {
        final result = await widget.controller.recognizeMemberFaces(data);
        if (mounted && widget.controller.serviceScope == _scope) {
          setState(() {
            _trialPhoto = data;
            _trial = result;
          });
        }
      } else {
        await widget.controller.enrollMemberFace(
          member.id,
          data,
          consent: _consent,
        );
        if (mounted && widget.controller.serviceScope == _scope)
          setState(() => _message = '人脸资料已录入，可继续选择不同角度的照片');
      }
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(MemberProfile member) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除人脸资料？'),
        content: const Text('删除电脑中该成员的全部人脸特征，成员档案和安全事件会保留。此操作不可撤回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || widget.controller.serviceScope != _scope)
      return;
    setState(() {
      _busy = true;
      _message = null;
      _discardTrial();
    });
    try {
      await widget.controller.clearMemberFaces(member.id);
      if (mounted) setState(() => _message = '人脸资料已清除');
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('成员详情')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final member = c.memberById(widget.memberId);
        if (c.serviceScope != _scope)
          return const Center(child: Text('后端已切换，请返回成员列表'));
        if (member == null) return const Center(child: Text('成员档案已移除，请返回列表刷新'));
        final records = c.recordsForMember(member.id);
        final ready =
            c.faceStatus['enabled'] == true && c.faceStatus['ready'] == true;
        return RefreshIndicator(
          onRefresh: () => c.refreshMembers(force: true),
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (member.relationship.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(member.relationship),
                      ),
                    if (member.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(member.notes),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || !c.canEditMembers
                              ? null
                              : () => editMember(context, c, member),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑档案'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || !c.canEditMembers
                              ? null
                              : () => bindMemberDevices(context, c, member),
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('关联设备'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '人脸识别',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      member.faceSampleCount == 0
                          ? '尚未录入人脸'
                          : '已录入 ${member.faceSampleCount} 张照片的特征',
                    ),
                    if (!ready)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '电脑尚未启用识别或模型未就绪，配置后下拉刷新。',
                          style: TextStyle(color: Anju.muted),
                        ),
                      ),
                    if (c.usesSharedMembers) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '请先拍好清晰正脸、稍向左和向右的照片，每张只包含该成员。建议录入 3–5 张，最多 10 张，每张不超过 5 MiB。电脑保存识别特征，不保留录入原照。识别结果需要结合画面核对。',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _consent,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _consent = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('已取得该成员同意，将人脸资料用于本家庭监护'),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                _busy ||
                                    !_consent ||
                                    !ready ||
                                    !c.canEditMembers ||
                                    member.faceSampleCount >= 10
                                ? null
                                : () => _enroll(member),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(_busy ? '正在处理' : '选择照片录入'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy || !ready || !c.canEditMembers
                                ? null
                                : () => _enroll(member, trial: true),
                            icon: const Icon(Icons.person_search_outlined),
                            label: const Text('选择照片试识别'),
                          ),
                          if (member.faceSampleCount > 0)
                            OutlinedButton(
                              onPressed: _busy || !c.canEditMembers
                                  ? null
                                  : () => _clear(member),
                              child: const Text('清除人脸资料'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '试识别会与全部已录入成员比对，不会新增样本。仅支持 JPEG/PNG；HEIC 照片请先转换。',
                      ),
                    ],
                    if (_trial != null) ...[
                      const SizedBox(height: 12),
                      if (_trialPhoto != null)
                        _FaceTrialPreview(photo: _trialPhoto!, result: _trial!),
                      FaceTrialResult(result: _trial!),
                      TextButton(
                        onPressed: () => setState(_discardTrial),
                        child: const Text('收起试识别'),
                      ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_message!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('监护设备'),
                subtitle: Text(
                  '${member.bindings.where((b) => b.scope == c.serviceScope || b.scope == 'phone-local').length} 个关联范围',
                ),
                children: [
                  const ListTile(
                    title: Text('设备范围只表示监护区域。多人共用摄像头时，身份由识别结果或人工确认决定。'),
                  ),
                  for (final binding in member.bindings.where(
                    (b) =>
                        b.scope == c.serviceScope || b.scope == 'phone-local',
                  ))
                    ListTile(
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(c.nameForDevice(binding.deviceId)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SectionTitle('${member.displayName}的记录'),
              if (records.isEmpty)
                const Surface(child: Text('暂无关联记录。识别到该成员或人工关联后，会在这里展示。')),
              for (final event in records.take(60))
                EventTile(
                  event: event,
                  onTap: () => widget.openEvent(event.id),
                  deviceLabel: c.associationLabel(event),
                  personLabel: c.personLabelFor(event),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class FaceTrialResult extends StatelessWidget {
  const FaceTrialResult({super.key, required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final faces = (result['faces'] as List? ?? []).whereType<Map>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(faces.isEmpty ? '未检测到可用人脸，请换一张清晰照片。' : '检测到 ${faces.length} 张人脸'),
        for (final (index, face) in faces.indexed)
          Text(
            face['status'] == 'matched' &&
                    face['member_id'] != null &&
                    (face['name']?.toString().trim().isNotEmpty ?? false)
                ? '${index + 1} · ${face['name']}（人脸识别候选，请核对）'
                : '${index + 1} · 身份未确认',
          ),
      ],
    );
  }
}

class _FaceTrialPreview extends StatelessWidget {
  const _FaceTrialPreview({required this.photo, required this.result});
  final Uint8List photo;
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final faces = (result['faces'] as List? ?? []).whereType<Map>().toList();
    return Stack(
      children: [
        Image.memory(
          photo,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, _, _) => const Text('照片预览无法显示，请查看识别结果。'),
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (_, size) => Stack(
              children: [
                for (final (index, face) in faces.indexed)
                  if (face['bbox'] case [num x1, num y1, num x2, num y2]
                      when x1 >= 0 &&
                          y1 >= 0 &&
                          x2 <= 1 &&
                          y2 <= 1 &&
                          x2 > x1 &&
                          y2 > y1)
                    Positioned(
                      left: x1 * size.maxWidth,
                      top: y1 * size.maxHeight,
                      width: (x2 - x1) * size.maxWidth,
                      height: (y2 - y1) * size.maxHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: face['status'] == 'matched'
                                ? Anju.green
                                : Colors.orange,
                            width: 2,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ColoredBox(
                            color: Colors.black87,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
