import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/household.dart';
import 'widgets.dart';
import 'media_hub_screen.dart';

class RisksScreen extends StatefulWidget {
  const RisksScreen({
    super.key,
    required this.controller,
    required this.openEvent,
    required this.openDevices,
  });
  final SafetyController controller;
  final void Function(String) openEvent;
  final VoidCallback openDevices;
  @override
  State<RisksScreen> createState() => _RisksScreenState();
}

class _RisksScreenState extends State<RisksScreen> {
  String? _filter;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final risks = c.events.where(isRiskEvent).toList();
    final filtered = risks
        .where((e) => _filter == null || e.eventType == _filter)
        .toList();
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const PageStorageKey('risks'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Text(
            '家中风险',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '关注环境线索，与人物事件分开处理',
            style: TextStyle(fontSize: 12, color: Anju.muted),
          ),
          const SizedBox(height: 20),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Anju.green),
                    SizedBox(width: 8),
                    Text(
                      '家庭风险概览',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _stat(
                      '明火记录',
                      risks.where((e) => e.eventType == 'fire_detected').length,
                    ),
                    _stat(
                      '火花记录',
                      risks
                          .where((e) => e.eventType == 'sparks_detected')
                          .length,
                    ),
                    _stat('待处理', risks.where(eventNeedsAction).length),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '基于当前 ${risks.length} 条已加载环境记录',
                  style: const TextStyle(fontSize: 11, color: Anju.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MediaHubScreen(controller: c, initialMode: 'safety'),
              ),
            ),
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('上传视频开展安全分析'),
          ),
          if (c.videoError != null)
            InfoBanner('录像服务：${c.videoError}', error: true),
          if (c.error != null) InfoBanner('统一后端：${c.error}', error: true),
          SectionTitle(
            '环境事件',
            action: TextButton(
              onPressed: () => openMediaHub(context, c, camera: true),
              child: const Text('实时摄像头 ›'),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final value in <String?>[
                null,
                'fire_detected',
                'sparks_detected',
              ])
                ChoiceChip(
                  label: Text(
                    value == null
                        ? '全部'
                        : value == 'fire_detected'
                        ? '明火'
                        : '火花',
                  ),
                  selected: _filter == value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = value),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const Surface(
              child: EmptyState(
                title: '暂无匹配的风险记录',
                message: '可连接事件服务，或上传视频开展安全分析。没有记录不代表现场已被确认安全。',
                icon: Icons.shield_outlined,
              ),
            ),
          for (final e in filtered)
            EventTile(
              event: e,
              deviceLabel: c.nameForDevice(e.deviceId),
              onTap: () => widget.openEvent(e.id),
            ),
          SectionTitle(
            '设备状态',
            action: TextButton(
              onPressed: widget.openDevices,
              child: const Text('管理设备 ›'),
            ),
          ),
          for (final e
              in c.events.where((e) => e.eventType == 'device_offline').take(5))
            EventTile(
              event: e,
              deviceLabel: c.nameForDevice(e.deviceId),
              onTap: () => widget.openEvent(e.id),
            ),
          if (!c.events.any((e) => e.eventType == 'device_offline'))
            const Text(
              '当前没有已加载的设备离线事件。',
              style: TextStyle(fontSize: 12, color: Anju.muted),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, int count) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Anju.muted)),
      ],
    ),
  );
}
