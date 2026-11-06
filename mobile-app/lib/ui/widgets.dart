import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/models.dart';

abstract final class Anju {
  static const ink = Color(0xff172e36);
  static const muted = Color(0xff71818a);
  static const green = Color(0xff087e70);
  static const light = Color(0xffe6f3ee);
  static const background = Color(0xfff4f7f8);
  static const line = Color(0xffe8eef0);
  static ThemeData theme({String? fontFamily}) => ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily ?? 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      primary: green,
      surface: Colors.white,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: green),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: Color(0xffcfdddf)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

String displayTime(DateTime? value, {bool seconds = false}) {
  if (value == null) return '尚未同步';
  final t = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}${seconds ? ':${two(t.second)}' : ''}';
}

String shortTime(DateTime? value) {
  if (value == null) return '时间未知';
  final t = value.toLocal();
  final now = DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
  final prefix = diff == 0
      ? '今天'
      : diff == 1
      ? '昨天'
      : '${t.month}月${t.day}日';
  return '$prefix ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String eventTypeLabel(String type) => switch (type) {
  'suspected_fall' => '疑似跌倒',
  'pose_observation' => '姿态观察',
  'long_absence' => '长时间未出现',
  'sparks_detected' => '火花线索',
  'fire_detected' => '疑似明火',
  'help_requested' => '举手求助',
  'device_offline' => '设备离线',
  _ => '安全事件',
};
IconData eventIcon(String type) => switch (type) {
  'suspected_fall' => Icons.personal_injury_outlined,
  'pose_observation' => Icons.accessibility_new_outlined,
  'fire_detected' => Icons.local_fire_department_outlined,
  'help_requested' => Icons.waving_hand_outlined,
  'device_offline' => Icons.wifi_off_rounded,
  _ => Icons.notifications_none_rounded,
};
String severityLabel(String severity) => switch (severity) {
  'critical' || 'high' => '紧急',
  'warning' || 'medium' => '关注',
  _ => '提示',
};
Color severityColor(String severity) => switch (severity) {
  'critical' || 'high' => const Color(0xffdc6549),
  'warning' || 'medium' => const Color(0xffc58a25),
  _ => Anju.green,
};
String stateLabel(String state) => switch (state) {
  'detected' || 'open' => '待回应',
  'notified' => '待回应',
  'acknowledged' => '处理中',
  'resolved' => '已解决',
  _ => '待核实',
};
String reviewLabel(String state) => switch (state) {
  'observed' => '录像观察记录',
  'inferred' => '录像推断记录',
  'pending' => '复核中',
  'completed' => '复核已完成',
  'failed' => '复核失败',
  'unavailable' => '复核暂不可用',
  _ => '等待复核信息',
};
String notificationLabel(String state) => switch (state) {
  'foreground_polling' => '前台同步提醒',
  'sent' => '推送已提交',
  'failed' => '推送失败',
  'pending' => '等待推送',
  'skipped' => '未发送系统推送',
  _ => '通知状态未知',
};

bool eventNeedsAction(SafetyEvent event) => event.isUnified
    ? event.confirmedDanger && !event.resolved
    : !event.resolved && (!event.fromVideo || !event.acknowledged);

String eventStateLabel(SafetyEvent event) => event.withdrawn
    ? '来源已撤销'
    : event.isUnified
    ? stateLabel(event.state)
    : event.fromVideo
    ? (event.acknowledged ? '已确认' : '待确认')
    : stateLabel(event.state);

String eventSourceLabel(SafetyEvent event, String deviceLabel) {
  if (!event.fromVideo)
    return event.isUnified ? '实摄 · $deviceLabel' : deviceLabel;
  final name = event.details['video_name']?.toString().trim() ?? '';
  final id = event.details['video_id']?.toString().trim() ?? '';
  return '录像 · ${name.isNotEmpty
      ? name
      : id.isNotEmpty
      ? id
      : '未命名录像'}';
}

String eventTimeLabel(SafetyEvent event) {
  if (!event.fromVideo) return shortTime(event.occurredAt);
  int? milliseconds(Object? value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite && number >= 0
        ? number.toInt()
        : null;
  }

  String clock(int ms) {
    final seconds = ms ~/ 1000;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  final start = milliseconds(event.details['start_ms']);
  final end = milliseconds(event.details['end_ms']);
  if (start == null) return '录像内时间未提供';
  final range = end != null && end > start ? '—${clock(end)}' : '';
  return '录像内 ${clock(start)}$range';
}

// Small visual primitives shared by all screens.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Anju.green, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.caption});
  final String text;
  final Widget? action;
  final String? caption;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: Theme.of(context).textTheme.titleLarge),
              if (caption != null)
                Text(caption!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: error ? const Color(0xfffff0eb) : Anju.light,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.info_outline : Icons.verified_user_outlined,
          size: 17,
          color: error ? const Color(0xffb45435) : Anju.green,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: error ? const Color(0xff97472e) : Anju.green,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Anju.light,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: Anju.green),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.onTap,
    this.deviceLabel,
    this.personLabel,
  });
  final SafetyEvent event;
  final VoidCallback onTap;
  final String? deviceLabel;
  final String? personLabel;
  @override
  Widget build(BuildContext context) {
    final color = event.resolved ? Anju.green : severityColor(event.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    eventIcon(event.eventType),
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              eventTypeLabel(event.eventType),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Pill(eventStateLabel(event), color: color),
                        ],
                      ),
                      const SizedBox(height: 7),
                      if (personLabel != null) ...[
                        Text(
                          personLabel!,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        eventSourceLabel(event, deviceLabel ?? event.deviceId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Anju.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              eventTimeLabel(event),
                              style: const TextStyle(
                                color: Anju.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: color,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xff12a88b), Color(0xff076c66)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(
      Icons.health_and_safety_rounded,
      color: Colors.white,
      size: size * .69,
    ),
  );
}

class HouseIllustration extends StatelessWidget {
  const HouseIllustration({super.key, this.size = 150});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _HousePainter()),
  );
}

class _HousePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 180, size.height / 180);
    final p = Paint();
    for (var i = 0; i < 3; i++) {
      p
        ..color = Colors.white.withValues(alpha: .05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(const Offset(94, 94), 43 + i * 21, p);
    }
    p
      ..style = PaintingStyle.fill
      ..color = const Color(0xffa4dcc7);
    final roof = Path()
      ..moveTo(33, 80)
      ..lineTo(91, 32)
      ..lineTo(151, 80)
      ..lineTo(140, 92)
      ..lineTo(91, 53)
      ..lineTo(43, 92)
      ..close();
    canvas.drawPath(roof, p);
    p.color = const Color(0xffecf6e9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 80, 85, 67),
        const Radius.circular(7),
      ),
      p,
    );
    p.color = const Color(0xff4c9a85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(64, 94, 21, 21),
        const Radius.circular(4),
      ),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(99, 94, 17, 53),
        const Radius.circular(4),
      ),
      p,
    );
    p.color = Colors.white.withValues(alpha: .65);
    canvas.drawLine(
      const Offset(74, 95),
      const Offset(74, 114),
      p..strokeWidth = 2,
    );
    canvas.drawLine(const Offset(65, 104), const Offset(84, 104), p);
    p
      ..color = const Color(0xff72cfaa)
      ..style = PaintingStyle.fill;
    final shield = Path()
      ..moveTo(131, 106)
      ..lineTo(155, 115)
      ..lineTo(153, 141)
      ..quadraticBezierTo(148, 153, 131, 161)
      ..quadraticBezierTo(113, 152, 109, 140)
      ..lineTo(107, 115)
      ..close();
    canvas.drawPath(shield, p);
    p
      ..color = const Color(0xff075c53)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(120, 132)
        ..lineTo(128, 140)
        ..lineTo(142, 124),
      p,
    );
    for (final point in [
      const Offset(40, 46),
      const Offset(153, 52),
      const Offset(36, 129),
    ]) {
      p
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: .65);
      canvas.drawCircle(point, 2.5, p);
    }
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xff8dcbb7);
    canvas.drawArc(
      const Rect.fromLTWH(123, 43, 21, 21),
      -math.pi * .8,
      math.pi * .65,
      false,
      p,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
