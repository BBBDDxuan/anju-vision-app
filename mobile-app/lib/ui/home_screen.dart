import 'package:flutter/material.dart';
import '../app_controller.dart';
import 'widgets.dart';
import 'devices_screen.dart';
import 'media_hub_screen.dart';
import '../models/household.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.openEvent,
    required this.openHistory,
    required this.openMembers,
    required this.openRisks,
    required this.openObjects,
    this.openDevices,
    this.openSettings,
  });
  final SafetyController controller;
  final void Function(String) openEvent;
  final VoidCallback openHistory;
  final VoidCallback openMembers, openRisks, openObjects;
  final VoidCallback? openDevices, openSettings;
  @override
  Widget build(BuildContext context) {
    final pending = controller.events.where(eventNeedsAction).toList();
    final online = controller.devices.where((d) => d.online).length;
    final unack = pending.where((e) => !e.acknowledged).length;
    final ordered = [
      ...pending,
      ...controller.events.where((e) => !eventNeedsAction(e)),
    ];
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了，牵挂依然在线'
        : hour < 12
        ? '早上好，开启安心的一天'
        : hour < 18
        ? '下午好，把牵挂放在心上'
        : '晚上好，愿家人平安相伴';
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey('home'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          Text(
            greeting,
            style: const TextStyle(fontSize: 12, color: Anju.muted),
          ),
          const SizedBox(height: 7),
          const Text(
            '家的动态，一眼安心',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff173f40), Color(0xff087768)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -7,
                  top: 4,
                  child: HouseIllustration(
                    size: MediaQuery.sizeOf(context).width < 370 ? 88 : 132,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: Color(0xff91dbbf),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'FAMILY CARE',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: Color(0xffa2d2c4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(right: 74),
                        child: Text(
                          unack > 0 ? '每一份牵挂\n都值得及时回应' : '把距离拉近\n让陪伴更安心',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        '最近同步 ${shortTime(controller.lastSync)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xffc3ded4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: .15),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _stat('$online', '在线设备', Icons.wifi_rounded),
                          _stat(
                            '$unack',
                            '待回应',
                            Icons.notifications_active_outlined,
                          ),
                          _stat(
                            '${pending.length - unack}',
                            '处理中',
                            Icons.hourglass_bottom_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionTitle('三项守护', caption: '关心家人、留意风险、找回日常'),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _feature(
                  '成员监护',
                  '档案与人物事件',
                  Icons.groups_outlined,
                  '${controller.members.length} 位成员',
                  openMembers,
                ),
                _feature(
                  '家中风险',
                  '环境线索与告警',
                  Icons.shield_outlined,
                  '${controller.events.where(isRiskEvent).where(eventNeedsAction).length} 条待处理',
                  openRisks,
                ),
                _feature(
                  '物品寻找',
                  '搜索物品与踪迹',
                  Icons.manage_search_rounded,
                  '录像与证据回看',
                  openObjects,
                ),
              ];
              if (constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  children: [
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: card,
                      ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: cards[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    openMediaHub(context, controller, camera: true),
                icon: const Icon(Icons.videocam_outlined, size: 18),
                label: const Text('实时摄像头'),
              ),
              OutlinedButton.icon(
                onPressed: () => openMediaHub(context, controller),
                icon: const Icon(Icons.video_library_outlined, size: 18),
                label: const Text('上传视频'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.videoError != null)
            InfoBanner('录像服务：${controller.videoError}', error: true),
          if (controller.error != null)
            InfoBanner('统一后端同步未完成，当前显示上次记录。${controller.error}', error: true),
          if (controller.storageWarning != null)
            InfoBanner(controller.storageWarning!, error: true),
          if (controller.preferencesError != null)
            InfoBanner(controller.preferencesError!, error: true),
          const SizedBox(height: 12),
          SectionTitle(
            '需要你关注',
            caption: '基于最近 ${controller.events.length} 条已加载记录',
            action: TextButton(
              onPressed: openHistory,
              child: const Text('全部记录 ›'),
            ),
          ),
          if (ordered.isEmpty)
            const Surface(
              child: EmptyState(
                title: '暂无已上报事件',
                message: '新事件会在这里出现，请保持设备和服务在线。',
                icon: Icons.verified_user_outlined,
              ),
            ),
          for (final event in ordered.take(2))
            EventTile(
              event: event,
              onTap: () => openEvent(event.id),
              deviceLabel: controller.nameForDevice(event.deviceId),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _quick(Icons.history_rounded, '事件记录', '每一次回应有迹可循', openHistory),
              const SizedBox(width: 12),
              _quick(
                Icons.notifications_outlined,
                '通知设置',
                '设置你的守护方式',
                openSettings ?? () {},
              ),
            ],
          ),
          SectionTitle(
            '家中设备',
            action: TextButton(
              onPressed: openDevices,
              child: const Text('查看设备 ›'),
            ),
          ),
          for (final device in controller.devices.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DeviceCard(
                device: device,
                compact: true,
                onTap: () =>
                    showDeviceDetails(context, controller, device, openEvent),
              ),
            ),
          if (controller.devices.isEmpty)
            const Surface(
              child: EmptyState(title: '还没有设备', message: '连接服务后，将显示已经注册的家庭设备。'),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                size: 13,
                color: Anju.muted,
              ),
              const SizedBox(width: 6),
              Text('让关心，跨越距离', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feature(
    String title,
    String subtitle,
    IconData icon,
    String detail,
    VoidCallback onTap,
  ) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      key: ValueKey('home-$title'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Anju.light,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: Anju.green, size: 23),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Anju.muted),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: const TextStyle(fontSize: 10, color: Anju.green),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _stat(String value, String label, IconData icon) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, color: const Color(0xff8bc9b8), size: 15),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xffbed8cf)),
        ),
      ],
    ),
  );
  Widget _quick(
    IconData icon,
    String title,
    String caption,
    VoidCallback onTap,
  ) => Expanded(
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Anju.green, size: 24),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: const TextStyle(fontSize: 10, color: Anju.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
