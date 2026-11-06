import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import 'widgets.dart';
import 'media_hub_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    required this.controller,
    required this.openEvent,
  });
  final SafetyController controller;
  final void Function(String) openEvent;
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  int _filter = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final devices = c.devices
        .where((d) => _filter == 0 || (_filter == 1 ? d.online : !d.online))
        .toList();
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        key: const PageStorageKey('devices'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Text(
            '我的设备',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '摄像头与录像',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '连接同一局域网摄像头，或上传已有视频进行分析。',
                  style: TextStyle(fontSize: 12, color: Anju.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => openMediaHub(context, c, camera: true),
                      icon: const Icon(Icons.videocam_outlined, size: 18),
                      label: const Text('实时摄像头'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => openMediaHub(context, c),
                      icon: const Icon(Icons.video_library_outlined, size: 18),
                      label: const Text('上传视频 / 录像库'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
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
                        '家庭设备',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${c.devices.where((d) => d.online).length} 台在线 · ${c.devices.length} 台设备',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.home_outlined, color: Anju.green),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(['全部设备', '在线', '离线'][i]),
                  selected: _filter == i,
                  onSelected: (_) => setState(() => _filter = i),
                  showCheckmark: false,
                ),
            ],
          ),
          if (c.error != null) InfoBanner('统一后端：${c.error}', error: true),
          const SizedBox(height: 18),
          for (final device in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DeviceCard(
                device: device,
                onTap: () =>
                    showDeviceDetails(context, c, device, widget.openEvent),
              ),
            ),
          if (devices.isEmpty)
            const Surface(
              child: EmptyState(
                title: '暂无匹配设备',
                message: '尝试切换筛选，或在连接服务后下拉刷新。',
                icon: Icons.devices_other_outlined,
              ),
            ),
          const SizedBox(height: 12),
          const InfoBanner('设备状态由服务端心跳更新。离线时请检查设备电源、网络与采集服务。'),
        ],
      ),
    );
  }
}

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
    this.compact = false,
  });
  final SafetyDevice device;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: device.online ? Anju.light : Anju.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.videocam_outlined,
                    color: device.online ? Anju.green : Anju.muted,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        device.online ? '设备心跳正常' : '暂未收到设备心跳',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Pill(
                  device.online ? '在线' : '离线',
                  color: device.online ? Anju.green : Anju.muted,
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: Anju.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '最近在线 ${shortTime(device.lastSeenAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Anju.green,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> showDeviceDetails(
  BuildContext context,
  SafetyController c,
  SafetyDevice device,
  void Function(String) openEvent,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .65,
    maxChildSize: .9,
    minChildSize: .4,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      children: [
        Text(device.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Pill(
            device.online ? '在线 · 心跳正常' : '离线 · 请检查设备',
            icon: device.online ? Icons.wifi : Icons.wifi_off,
            color: device.online ? Anju.green : const Color(0xffc58a25),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '最近在线：${displayTime(device.lastSeenAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('设备编号：${device.id}', style: Theme.of(context).textTheme.bodySmall),
        const InfoBanner('此页展示设备状态与关联事件。实时视频暂未接入手机端。'),
        const SectionTitle('关联事件'),
        if (!c.events.any((e) => e.deviceId == device.id))
          const EmptyState(title: '暂无关联事件', message: '该设备上报的事件将在这里显示。'),
        for (final e in c.events.where((e) => e.deviceId == device.id).take(10))
          EventTile(
            event: e,
            deviceLabel: c.nameForDevice(e.deviceId),
            personLabel: c.personLabelFor(e),
            onTap: () {
              Navigator.pop(sheet);
              openEvent(e.id);
            },
          ),
      ],
    ),
  ),
);
