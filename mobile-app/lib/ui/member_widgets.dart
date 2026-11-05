import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import 'widgets.dart';

Future<void> assignEventMember(
  BuildContext context,
  SafetyController c,
  SafetyEvent event,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheet) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      24 + MediaQuery.viewPaddingOf(sheet).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '关联被监护人员',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '由你核对并指定，不代表自动身份识别。',
          style: TextStyle(fontSize: 12, color: Anju.muted),
        ),
        const SizedBox(height: 16),
        for (final id in <String?>[null, ...c.members.map((m) => m.id)])
          ListTile(
            leading: Icon(
              id == null ? Icons.person_search_outlined : Icons.person_outline,
              color: Anju.green,
            ),
            title: Text(id == null ? '待归属' : c.memberById(id)!.displayName),
            trailing: c.memberIdFor(event) == id
                ? const Icon(Icons.check_rounded, color: Anju.green)
                : null,
            onTap: () async {
              try {
                await c.associateMember(event, id);
                if (sheet.mounted) Navigator.pop(sheet);
              } catch (_) {
                if (sheet.mounted)
                  ScaffoldMessenger.of(
                    sheet,
                  ).showSnackBar(const SnackBar(content: Text('成员关联未保存，请重试')));
              }
            },
          ),
      ],
    ),
  ),
);

class MemberAssociationCard extends StatelessWidget {
  const MemberAssociationCard({
    super.key,
    required this.controller,
    required this.event,
  });
  final SafetyController controller;
  final SafetyEvent event;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final id = controller.memberIdFor(event);
      return Surface(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.person_pin_outlined, color: Anju.green),
          title: Text(
            id == null ? '身份未确认' : controller.memberById(id)!.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            '${controller.associationLabel(event)} · 点击调整',
            style: const TextStyle(fontSize: 11, color: Anju.muted),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => assignEventMember(context, controller, event),
        ),
      );
    },
  );
}
