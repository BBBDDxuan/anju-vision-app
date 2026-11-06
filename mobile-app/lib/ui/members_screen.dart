import 'dart:async';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import '../models/household.dart';
import 'widgets.dart';
import 'settings_screen.dart' show ContactsEditor;
import 'member_detail_screen.dart';

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
  int _peopleTab = 0;
  bool _adding = false, _importing = false;
  void showPeople() => setState(() => _peopleTab = 0);
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshMembers(force: true));
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.controller.refresh(),
      widget.controller.refreshMembers(force: true),
    ]);
  }

  void _openMember(MemberProfile member) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MemberDetailScreen(
          controller: widget.controller,
          memberId: member.id,
          openEvent: widget.openEvent,
        ),
      ),
    );
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      final before = widget.controller.members.map((m) => m.id).toSet();
      await widget.controller.addMember();
      if (!mounted) return;
      final added = widget.controller.members
          .where((m) => !before.contains(m.id))
          .firstOrNull;
      if (added != null) {
        await editMember(context, widget.controller, added);
        if (mounted && widget.controller.memberById(added.id) != null)
          _openMember(added);
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

  Future<void> _import() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('将旧档案复制到电脑？'),
        content: const Text(
          '复制本机旧成员的姓名、关系、备注和设备范围到当前电脑。原档案会保留；请勿重复复制，已有人脸资料不会随此操作迁移。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('复制档案'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _importing = true);
    try {
      await widget.controller.importLegacyMembers();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _editContacts() => showModalBottomSheet<void>(
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
      child: ContactsEditor(controller: widget.controller),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final personEvents = c.events.where(isPersonEvent).toList();
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey('members'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('被监护人员')),
                ButtonSegment(value: 1, label: Text('家庭联系人')),
              ],
              selected: {_peopleTab},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _peopleTab = value.single),
            ),
            const SizedBox(height: 20),
            if (_peopleTab == 1) ...[
              Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final contact in c.preferences.contacts)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: const Icon(
                          Icons.person_outline,
                          color: Anju.green,
                        ),
                        title: Text(
                          contact.name.trim().isEmpty ||
                                  ['主要联系人', '备用联系人'].contains(contact.name)
                              ? '未设置姓名'
                              : contact.name,
                        ),
                        subtitle: Text(
                          contact.id == 'primary'
                              ? '主要联系人 · 优先接收提醒'
                              : '备用联系人 · 无人确认时接收重要提醒',
                        ),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('备用提醒延迟'),
                      subtitle: Text(_delay(c.preferences.escalationSeconds)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _editContacts,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _editContacts,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑家庭联系人'),
              ),
            ] else ...[
              if (c.memberSyncing) const LinearProgressIndicator(),
              if (c.memberSyncError != null)
                InfoBanner(c.memberSyncError!, error: true),
              if (c.householdWarning != null)
                InfoBanner(c.householdWarning!, error: true),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.usesSharedMembers ? '家庭成员' : '被监护人员',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _adding || !c.canEditMembers ? null : _add,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(_adding ? '添加中' : '添加成员'),
                  ),
                ],
              ),
              if (c.members.isEmpty)
                const Surface(
                  child: EmptyState(
                    title: '还没有成员档案',
                    message: '添加成员，录入人脸后可辅助识别提醒中的人员。',
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                ),
              for (final member in c.members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Surface(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            RegExp(
                              r'^#[0-9a-fA-F]{6}$',
                            ).hasMatch(member.labelColor)
                            ? Color(
                                0xff000000 |
                                    int.parse(
                                      member.labelColor.substring(1),
                                      radix: 16,
                                    ),
                              )
                            : Anju.green,
                        child: Text(
                          member.labelLetter.isNotEmpty
                              ? member.labelLetter
                              : member.displayName.characters.first,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (member.relationship.isNotEmpty)
                            member.relationship,
                          '${c.recordsForMember(member.id).where(eventNeedsAction).length} 条待处理',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openMember(member),
                    ),
                  ),
                ),
              if (c.legacyMembers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _importing || !c.canEditMembers ? null : _import,
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(_importing ? '正在复制旧档案' : '复制本机旧档案到电脑'),
                  ),
                ),
              const SizedBox(height: 18),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('全部人物提醒'),
                subtitle: Text('${personEvents.length} 条记录，点击展开'),
                children: [
                  if (personEvents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无人物提醒，可在设备页开始监护或导入录像。'),
                    ),
                  for (final event in personEvents.take(60))
                    EventTile(
                      event: event,
                      personLabel: c.personLabelFor(event),
                      onTap: () => widget.openEvent(event.id),
                      deviceLabel: c.memberIdFor(event) == null
                          ? '身份未确认'
                          : c.memberById(c.memberIdFor(event)!)!.displayName,
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
  String _delay(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60} 分钟' : '$seconds 秒';
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
  late final String _scope;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scope = widget.controller.serviceScope;
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
      if (widget.controller.serviceScope != _scope)
        throw StateError('后端已切换，请返回成员列表重新编辑');
      final current = widget.controller.memberById(widget.member.id);
      if (current == null) throw StateError('missing');
      await widget.controller.saveMember(
        widget.member.copyWith(
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
        content: Text(
          widget.controller.usesSharedMembers
              ? '删除电脑中的共享档案和全部人脸资料，其他手机同步后也将移除。安全事件会保留。'
              : '删除本机档案、绑定和人工关联，安全事件会保留。',
        ),
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
      if (widget.controller.serviceScope != _scope)
        throw StateError('后端已切换，请返回成员列表');
      if (widget.controller.memberById(widget.member.id)?.revision !=
          widget.member.revision)
        throw StateError('档案已更新，请刷新后重新删除');
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
          '固定编号：成员${widget.member.number} · ${widget.controller.usesSharedMembers ? '档案与电脑共享' : '档案保存在本机'}',
          style: const TextStyle(fontSize: 12, color: Anju.muted),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _name,
          maxLength: widget.controller.usesSharedMembers ? 80 : 40,
          decoration: InputDecoration(
            labelText: '称呼（留空使用默认编号）',
            hintText: '成员${widget.member.number}',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _relation,
          maxLength: widget.controller.usesSharedMembers ? 80 : 30,
          decoration: const InputDecoration(labelText: '与家庭的关系（可选）'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notes,
          maxLength: widget.controller.usesSharedMembers ? 2000 : 500,
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
  late final String _scope;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scope = widget.controller.serviceScope;
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
      if (widget.controller.serviceScope != _scope)
        throw StateError('后端已切换，请返回成员列表重新编辑');
      final current = widget.member;
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
