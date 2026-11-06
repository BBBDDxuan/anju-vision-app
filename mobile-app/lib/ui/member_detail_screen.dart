import 'package:flutter/material.dart';
import '../app_controller.dart';
import 'members_screen.dart' show editMember, bindMemberDevices;
import 'widgets.dart';
import 'member_avatar.dart';

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
  @override
  void initState() {
    super.initState();
    _scope = widget.controller.serviceScope;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('成员详情')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller,
            member = widget.controller.memberById(widget.memberId);
        if (c.serviceScope != _scope)
          return const Center(child: Text('后端已切换，请返回成员列表'));
        if (member == null) return const Center(child: Text('成员档案已移除，请返回列表刷新'));
        final records = c.recordsForMember(member.id);
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
                    MemberAvatarEditor(controller: c, memberId: member.id),
                    const SizedBox(height: 16),
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
                    OutlinedButton.icon(
                      onPressed: c.canEditMembers
                          ? () => editMember(context, c, member)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑档案'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '标签来自用户对当前人物 track 的人工关联；丢失、断流或超时后需重新确认。',
                      style: TextStyle(fontSize: 12, color: Anju.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('监护设备'),
                subtitle: const Text('设备范围仅作备注，不自动确定成员'),
                children: [
                  for (final binding in member.bindings.where(
                    (b) =>
                        b.scope == c.serviceScope || b.scope == 'phone-local',
                  ))
                    ListTile(
                      leading: const Icon(Icons.videocam_outlined),
                      title: Text(c.nameForDevice(binding.deviceId)),
                    ),
                  TextButton(
                    onPressed: c.canEditMembers
                        ? () => bindMemberDevices(context, c, member)
                        : null,
                    child: const Text('编辑设备备注'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionTitle('${member.displayName}的记录'),
              if (records.isEmpty) const Surface(child: Text('暂无人工关联记录。')),
              for (final event in records.take(60))
                EventTile(
                  event: event,
                  onTap: () => widget.openEvent(event.id),
                  deviceLabel: c.associationLabel(event),
                ),
            ],
          ),
        );
      },
    ),
  );
}
