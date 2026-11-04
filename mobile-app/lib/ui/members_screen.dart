import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import '../models/household.dart';
import 'widgets.dart';
import 'settings_screen.dart' show ContactsEditor;
import 'media_hub_screen.dart';
import 'member_widgets.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({
    super.key,
    required this.controller,
    required this.openEvent,
    required this.openDevices,
  });
  final SafetyController controller;
  final void Function(String) openEvent;
  final VoidCallback openDevices;
  @override
  State<MembersScreen> createState() => MembersScreenState();
}

class MembersScreenState extends State<MembersScreen> {
  void showPeople() => setState(() => _peopleTab = 0);
  String? _selected;
  int _peopleTab = 0;
  bool _adding = false;
  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await widget.controller.addMember();
      if (mounted) {
        final member = widget.controller.household.members.last;
        setState(() => _selected = member.id);
        await editMember(context, widget.controller, member);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final member = _selected == null ? null : c.memberById(_selected!);
    final records = member == null
        ? c.events.where(isPersonEvent).toList()
        : c.recordsForMember(member.id);
    final pending = records.where(eventNeedsAction).length;
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const PageStorageKey('members'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '成员监护',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '实时摄像头与视频',
                onPressed: () => openMediaHub(context, c, camera: true),
                icon: const Icon(
                  Icons.offline_bolt_outlined,
                  color: Anju.green,
                ),
              ),
            ],
          ),
          const Text(
            '人员档案、设备范围与每一次观察',
            style: TextStyle(fontSize: 12, color: Anju.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('被监护人员'),
                  selected: _peopleTab == 0,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _peopleTab = 0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceChip(
                  label: const Text('家庭联系人'),
                  selected: _peopleTab == 1,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _peopleTab = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (c.householdWarning != null)
            InfoBanner(c.householdWarning!, error: true),
          if (_peopleTab == 1) ...[
            const Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '接收提醒的人',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '家庭联系人负责接收和处理提醒，与被监护人员档案分别管理。',
                    style: TextStyle(fontSize: 12, color: Anju.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final contact in c.preferences.contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Surface(
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, color: Anju.green),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              contact.id == 'primary'
                                  ? '主要联系人 · 优先提醒'
                                  : '备用联系人 · 超时升级提醒',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Anju.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
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
                  child: ContactsEditor(controller: c),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑家庭联系人'),
            ),
          ] else ...[
            Surface(
              child: Row(
                children: [
                  const BrandMark(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.household.members.length} 位被监护人员',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$pending 条记录待处理 · 档案保存在本机',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Anju.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SectionTitle(
              '被监护人员',
              action: TextButton.icon(
                onPressed: _adding ? null : _add,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('添加成员'),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _memberCard(null, c),
                  for (final m in c.household.members) _memberCard(m, c),
                ],
              ),
            ),
            if (member != null) ...[
              const SizedBox(height: 14),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.displayName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Pill('编号 成员${member.number}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      member.relationship.isEmpty
                          ? '关系尚未填写'
                          : member.relationship,
                      style: const TextStyle(fontSize: 12, color: Anju.muted),
                    ),
                    if (member.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          member.notes,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => editMember(context, c, member),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('编辑档案'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              bindMemberDevices(context, c, member),
                          icon: const Icon(Icons.link_rounded, size: 17),
                          label: const Text('绑定设备'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已绑定 ${member.bindings.where((b) => b.scope == c.serviceScope || b.scope == 'phone-local').length} 个设备范围',
                      style: const TextStyle(fontSize: 11, color: Anju.muted),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MediaHubScreen(controller: c, initialMode: 'safety'),
                ),
              ),
              icon: const Icon(Icons.accessibility_new_outlined),
              label: const Text('导入视频 / 实时监护'),
            ),
            if (c.videoError != null)
              InfoBanner('录像服务：${c.videoError}', error: true),
            if (c.error != null) InfoBanner('统一后端：${c.error}', error: true),
            SectionTitle(
              member == null ? '人物事件' : '${member.displayName}的记录',
              caption: '人物事件与家中风险分别展示',
              action: TextButton(
                onPressed: widget.openDevices,
                child: const Text('设备管理 ›'),
              ),
            ),
            if (records.isEmpty)
              const Surface(
                child: EmptyState(
                  title: '暂无关联人物记录',
                  message: '绑定设备范围，或在事件详情中人工关联成员。也可导入录像开展安全分析。',
                  icon: Icons.person_search_outlined,
                ),
              ),
            for (final e in records.take(60))
              Column(
                children: [
                  EventTile(
                    event: e,
                    onTap: () => widget.openEvent(e.id),
                    deviceLabel:
                        '${c.nameForDevice(e.deviceId)} · ${c.memberIdFor(e) == null ? '待归属' : c.memberById(c.memberIdFor(e)!)!.displayName}',
                  ),
                  if (c.memberIdFor(e) == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => assignEventMember(context, c, e),
                        child: const Text('关联成员'),
                      ),
                    ),
                ],
              ),
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text(
                '设备范围绑定用于组织记录，不代表人脸识别。多人共用设备时请人工确认归属。',
                style: TextStyle(fontSize: 11, color: Anju.muted, height: 1.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberCard(MemberProfile? m, SafetyController c) {
    final active = m == null ? _selected == null : _selected == m.id;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _selected = m?.id),
        child: Container(
          width: 112,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? Anju.green : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: active
                    ? Colors.white.withValues(alpha: .15)
                    : Anju.light,
                child: Icon(
                  m == null ? Icons.groups_outlined : Icons.person_outline,
                  color: active ? Colors.white : Anju.green,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                m?.displayName ?? '全部成员',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: active ? Colors.white : Anju.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                m == null
                    ? '人物记录总览'
                    : '${c.recordsForMember(m.id).length} 条关联记录',
                style: TextStyle(
                  fontSize: 10,
                  color: active ? const Color(0xffc2e7dd) : Anju.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> editMember(
  BuildContext context,
  SafetyController c,
  MemberProfile member,
) => showModalBottomSheet<void>(
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
    child: _MemberEditor(controller: c, member: member),
  ),
);

class _MemberEditor extends StatefulWidget {
  const _MemberEditor({required this.controller, required this.member});
  final SafetyController controller;
  final MemberProfile member;
  @override
  State<_MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<_MemberEditor> {
  late final TextEditingController _name, _relation, _notes;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.member.name);
    _relation = TextEditingController(text: widget.member.relationship);
    _notes = TextEditingController(text: widget.member.notes);
  }

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final current = widget.controller.memberById(widget.member.id);
      if (current == null) throw StateError('missing');
      await widget.controller.saveMember(
        current.copyWith(
          name: _name.text.trim(),
          relationship: _relation.text.trim(),
          notes: _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个成员档案？'),
        content: const Text('仅删除本机档案、绑定和人工关联，不删除安全事件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除档案'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.deleteMember(widget.member.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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
          '编辑被监护人员',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '固定编号：成员${widget.member.number} · 档案保存在本机',
          style: const TextStyle(fontSize: 12, color: Anju.muted),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _name,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: '称呼（留空使用默认编号）',
            hintText: '成员${widget.member.number}',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _relation,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '与家庭的关系（可选）'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notes,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '监护备注（可选）'),
        ),
        if (_error != null) InfoBanner(_error!, error: true),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '正在保存…' : '保存档案'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('删除成员档案'),
        ),
      ],
    ),
  );
}

Future<void> bindMemberDevices(
  BuildContext context,
  SafetyController c,
  MemberProfile member,
) => showModalBottomSheet<void>(
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
    child: _BindingEditor(controller: c, member: member),
  ),
);

class _BindingEditor extends StatefulWidget {
  const _BindingEditor({required this.controller, required this.member});
  final SafetyController controller;
  final MemberProfile member;
  @override
  State<_BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<_BindingEditor> {
  final _selected = <String>{};
  final _tracks = <String, TextEditingController>{};
  late final List<SafetyDevice> _devices;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _devices = [...widget.controller.devices];
    for (final b in widget.member.bindings.where(
      (b) =>
          b.scope == widget.controller.serviceScope || b.scope == 'phone-local',
    )) {
      _selected.add(b.deviceId);
      _tracks[b.deviceId] = TextEditingController(text: b.trackId);
      if (!_devices.any((d) => d.id == b.deviceId))
        _devices.add(
          SafetyDevice(id: b.deviceId, name: b.deviceId, online: false),
        );
    }
    for (final d in _devices) {
      _tracks.putIfAbsent(d.id, () => TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _tracks.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final current = widget.controller.memberById(widget.member.id)!;
      final preserved = current.bindings.where(
        (b) =>
            b.scope != widget.controller.serviceScope &&
            b.scope != 'phone-local',
      );
      await widget.controller.saveMember(
        current.copyWith(
          bindings: [
            ...preserved,
            ..._selected.map(
              (id) => MemberBinding(
                deviceId: id,
                scope: id == 'phone-local'
                    ? 'phone-local'
                    : widget.controller.serviceScope,
                trackId: _tracks[id]!.text.trim(),
              ),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .83,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '绑定设备 · ${widget.member.displayName}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          const InfoBanner('仅绑定设备时，记录按设备范围组织；多人绑定同一设备会保持待归属。跟踪编号可能重置，不等同真实身份。'),
          for (final d in _devices)
            Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.name),
                  subtitle: Text(d.id, style: const TextStyle(fontSize: 11)),
                  value: _selected.contains(d.id),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _selected.add(d.id);
                          } else {
                            _selected.remove(d.id);
                          }
                        }),
                ),
                if (_selected.contains(d.id) && d.id != 'phone-local')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _tracks[d.id],
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: '跟踪编号（可选）',
                        helperText: '只有明确知道该设备的候选编号时才填写',
                      ),
                    ),
                  ),
              ],
            ),
          if (_error != null) InfoBanner(_error!, error: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '正在保存…' : '保存设备绑定'),
            ),
          ),
        ],
      ),
    ),
  );
}
