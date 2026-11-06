import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/household.dart';
import 'widgets.dart';

/// Pure color and letter display. No photo is decoded or uploaded.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 24});
  final MemberProfile member;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final value = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(member.labelColor)
        ? int.parse(member.labelColor.substring(1), radix: 16)
        : 0x237e7b;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(0xff000000 | value),
      child: Text(
        member.labelLetter.isEmpty
            ? member.displayName.characters.first
            : member.labelLetter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class MemberAvatarEditor extends StatelessWidget {
  const MemberAvatarEditor({
    super.key,
    required this.controller,
    required this.memberId,
    this.disabled = false,
  });
  final SafetyController controller;
  final String memberId;
  final bool disabled;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final member = controller.memberById(memberId);
      if (member == null) return const SizedBox.shrink();
      return Row(
        children: [
          MemberAvatar(member: member, radius: 32),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              '颜色与字母仅作人工标签，在编辑档案中设置。',
              style: TextStyle(fontSize: 12, color: Anju.muted),
            ),
          ),
        ],
      );
    },
  );
}
