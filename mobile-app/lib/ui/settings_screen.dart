import 'dart:async';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/models.dart';
import '../services/android_notices.dart';
import '../services/api.dart';
import '../services/settings_store.dart';
import '../services/push_service.dart';
import 'widgets.dart';
import 'manual_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller, this.openMembers});
  final SafetyController controller;
  final VoidCallback? openMembers;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final name = c.preferences.contactName(c.settings.contactId);
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const Text(
          '我的守护',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text('用更合适的方式，照看重要的人', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        Surface(
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Anju.light,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Anju.green,
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '家庭联系人' : name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.settings.contactId == 'primary'
                          ? '主要联系人 · 第一时间接收提醒'
                          : '备用联系人 · 接收升级提醒',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.favorite_rounded,
                color: Color(0xffe1b7a6),
                size: 22,
              ),
            ],
          ),
        ),
        const SectionTitle('家庭与通知'),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(
                Icons.badge_outlined,
                '被监护人员',
                '${c.household.members.length} 位本机档案 · 成员绑定与记录',
                widget.openMembers,
              ),
              const Divider(indent: 56),
              _row(
                Icons.people_outline_rounded,
                '家庭联系人',
                '主要联系人与备用联系人',
                () => _open(context, ContactsEditor(controller: c)),
              ),
              const Divider(indent: 56),
              _row(
                Icons.notifications_none_rounded,
                '通知管理',
                '系统权限、通知渠道与推送状态',
                () => _open(context, _NotificationsSheet(controller: c)),
              ),
            ],
          ),
        ),
        const SectionTitle('服务与连接'),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(
                Icons.cloud_outlined,
                '连接服务',
                c.videoError != null || c.error != null
                    ? '连接需要检查'
                    : c.lastSync != null
                    ? '已同步 · ${shortTime(c.lastSync)}'
                    : '配置统一后端地址与访问令牌',
                () => _open(context, _ConnectionSheet(controller: c)),
              ),
              const Divider(indent: 56),
              _row(
                Icons.help_outline_rounded,
                '使用帮助',
                '全部功能、连接步骤与常见问题 · 离线可读',
                () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ManualScreen()),
                ),
              ),
            ],
          ),
        ),
        if (c.storageWarning != null)
          InfoBanner(c.storageWarning!, error: true),
        if (c.preferencesError != null)
          InfoBanner(c.preferencesError!, error: true),
        const SizedBox(height: 30),
        Center(
          child: Column(
            children: [
              const BrandMark(size: 32),
              const SizedBox(height: 10),
              const Text(
                '安居视界  1.2.1',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Anju.muted,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '让关心，跨越距离',
                style: TextStyle(fontSize: 11, color: Anju.muted),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => showAboutDialog(
                  context: context,
                  applicationName: '安居视界',
                  applicationVersion: '1.2.1',
                  applicationIcon: const BrandMark(size: 48),
                  children: [
                    const Text('居家安全事件提醒与家庭协作。AI 信息用于辅助核实；请结合实际情况处理。'),
                  ],
                ),
                child: const Text('关于与开源许可'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: Icon(icon, color: Anju.green, size: 23),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: Anju.muted),
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: Anju.muted,
    ),
    onTap: onTap,
  );
}

Future<void> _open(BuildContext context, Widget sheet) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(top: false, child: sheet),
      ),
    );

class _ConnectionSheet extends StatefulWidget {
  const _ConnectionSheet({required this.controller});
  final SafetyController controller;
  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  late final TextEditingController _url, _token, _poll;
  late String _contact;
  bool _show = false, _busy = false;
  String? _message;
  bool _error = false;
  final _pollKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _url = TextEditingController(text: s.baseUrl);
    _token = TextEditingController(text: s.bearerToken);
    _poll = TextEditingController(text: '${s.pollSeconds}');
    _contact = s.contactId;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _poll.dispose();
    super.dispose();
  }

  AppSettings _candidate() => AppSettings(
    baseUrl: _url.text.trim().replaceAll(RegExp(r'/+$'), ''),
    bearerToken: _token.text.trim(),
    contactId: _contact,
    pollSeconds: int.tryParse(_poll.text.trim()) ?? 0,
  );

  Future<void> _run(bool probe) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });
    UnifiedHttpSafetyRepository? repo;
    try {
      final candidate = _candidate();
      if (candidate.validationError != null)
        throw ApiException(candidate.validationError!);
      if (candidate.bearerToken.isEmpty)
        throw const ApiException('请填写 A 提供的统一访问令牌（APP_LAN_TOKEN）');
      if (probe) {
        repo = UnifiedHttpSafetyRepository(
          baseUrl: candidate.baseUrl,
          bearerToken: candidate.bearerToken,
        );
        final connection = await repo.connection();
        await repo.alertPage(limit: 1);
        final ready = (connection['analysis'] as Map?)?['ready'] == true;
        if (mounted)
          setState(
            () => _message =
                '统一后端连接成功，身份验证通过。' +
                (ready ? '分析服务已就绪。' : '模型尚未就绪，请由 A 检查模型环境；连接本身已成功。'),
          );
      } else {
        await widget.controller.applyConnection(candidate);
        if (mounted)
          setState(() {
            _error = widget.controller.error != null;
            _message = _error
                ? '连接配置已保存；同步需要检查：${widget.controller.error}'
                : '统一连接已保存，录像与两类告警共用此地址。';
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _message = '$e';
          _error = true;
        });
    } finally {
      repo?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tokenField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required bool visible,
    required VoidCallback toggle,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    obscureText: !visible,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 4,
      suffixIcon: IconButton(
        tooltip: visible ? '隐藏令牌' : '显示令牌',
        onPressed: _busy ? null : toggle,
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '连接服务',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '一个后端地址连接录像、实摄告警、联系人和证据。',
          style: TextStyle(color: Anju.muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _url,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '统一后端地址',
            hintText: 'http://电脑局域网IP:8000',
            helperText: '填写根地址，不加 /api。模拟器访问本机可用 http://10.0.2.2:8000。',
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 16),
        _tokenField(
          controller: _token,
          label: '统一访问令牌',
          helper: '填写 A 配置的 APP_LAN_TOKEN 原文，不加 Bearer 前缀；不是模型 API Key。',
          visible: _show,
          toggle: () => setState(() => _show = !_show),
        ),
        const SizedBox(height: 16),
        const InfoBanner('令牌保存在设备安全存储中。局域网可用私有 IP 的 HTTP 地址，外网连接请使用 HTTPS。'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _contact,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '此手机的联系人角色'),
          items: const [
            DropdownMenuItem(value: 'primary', child: Text('主要联系人')),
            DropdownMenuItem(value: 'backup', child: Text('备用联系人')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _contact = v!),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          maintainState: true,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: const Text('高级设置', style: TextStyle(fontSize: 14)),
          onExpansionChanged: (expanded) {
            if (!expanded) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final target = _pollKey.currentContext;
              if (mounted && target != null) {
                unawaited(
                  Scrollable.ensureVisible(
                    target,
                    alignment: 1,
                    duration: const Duration(milliseconds: 200),
                  ),
                );
              }
            });
          },
          children: [
            const SizedBox(height: 12),
            // A wrapping caption stays readable on narrow screens and large text.
            const Text('前台刷新间隔', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              key: _pollKey,
              controller: _poll,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              scrollPadding: const EdgeInsets.all(32),
              decoration: const InputDecoration(
                labelText: '间隔（秒）',
                helperText: '有效范围：5–300 秒；仅在 App 前台自动刷新。',
                helperMaxLines: 4,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
        if (_message != null) InfoBanner(_message!, error: _error),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : () => _run(true),
            child: const Text('检查连接'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : () => _run(false),
            child: const Text('保存连接'),
          ),
        ),
      ],
    ),
  );
}

class ContactsEditor extends StatefulWidget {
  const ContactsEditor({required this.controller});
  final SafetyController controller;
  @override
  State<ContactsEditor> createState() => ContactsEditorState();
}

class ContactsEditorState extends State<ContactsEditor> {
  late final TextEditingController _primary, _backup, _seconds;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    final p = widget.controller.preferences;
    _primary = TextEditingController(text: p.contactName('primary'));
    _backup = TextEditingController(text: p.contactName('backup'));
    _seconds = TextEditingController(text: '${p.escalationSeconds}');
  }

  @override
  void dispose() {
    _primary.dispose();
    _backup.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final seconds = int.tryParse(_seconds.text);
    final a = _primary.text.trim(), b = _backup.text.trim();
    if (a.isEmpty ||
        b.isEmpty ||
        a.length > 80 ||
        b.length > 80 ||
        seconds == null ||
        seconds < 5 ||
        seconds > 86400) {
      setState(() => _message = '请填写 1–80 字姓名，升级等待为 5–86400 整数秒');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.saveFamilyPreferences(
        FamilyPreferences(
          escalationSeconds: seconds,
          notificationsEnabled:
              widget.controller.preferences.notificationsEnabled,
          contacts: [
            FamilyContact(id: 'primary', name: a),
            FamilyContact(id: 'backup', name: b),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
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
          '家庭联系人',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '让提醒找到合适的人',
          style: TextStyle(fontSize: 12, color: Anju.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _primary,
          decoration: const InputDecoration(
            labelText: '主要联系人姓名',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _backup,
          decoration: const InputDecoration(
            labelText: '备用联系人姓名',
            prefixIcon: Icon(Icons.people_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _seconds,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '未回应升级等待（秒）'),
        ),
        const SizedBox(height: 12),
        const InfoBanner('主要联系人未确认时，由服务端按设定时间向备用联系人发送升级提醒。真实送达依赖已注册的推送服务。'),
        if (_message != null) InfoBanner(_message!, error: true),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '正在保存…' : '保存联系人'),
          ),
        ),
      ],
    ),
  );
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet({required this.controller});
  final SafetyController controller;
  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet>
    with WidgetsBindingObserver {
  final _android = AndroidNotices();
  AndroidNotificationStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _android.status();
      if (mounted)
        setState(() {
          _status = status;
          _error = null;
        });
    } catch (_) {
      if (mounted) setState(() => _error = '系统通知状态读取失败，请重试。');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission() async {
    final status = await _android.requestPermission();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _refresh() async {
    await _refreshStatus();
    final c = widget.controller;
    if (c.settings.bearerToken.isNotEmpty && useFirebase) await c.retryPush();
  }

  Widget _statusRow(String label, bool enabled) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          enabled ? Icons.check_circle_outline : Icons.info_outline,
          color: enabled ? Anju.green : Anju.muted,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('$label：${enabled ? '已开启' : '未开启'}')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final status = _status;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '通知管理',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('家庭事件提醒'),
              subtitle: const Text('关闭后停止新告警提醒；后台和锁屏送达情况以实际验证为准。'),
              value: c.preferences.notificationsEnabled,
              onChanged: _busy
                  ? null
                  : (v) => _run(() async {
                      await c.saveFamilyPreferences(
                        FamilyPreferences(
                          escalationSeconds: c.preferences.escalationSeconds,
                          notificationsEnabled: v,
                          contacts: c.preferences.contacts,
                        ),
                      );
                      if (!v) await _android.clear();
                    }),
            ),
            if (AndroidNotices.supported) ...[
              const SizedBox(height: 20),
              const Text(
                'Android 系统通知',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (status == null)
                const InfoBanner('通知状态尚未读取，请刷新重试。')
              else ...[
                if (status.permissionRequired)
                  _statusRow('Android 13+ 通知权限', status.permissionGranted)
                else
                  const Text(
                    '此 Android 版本无需单独申请运行时通知权限。',
                    style: TextStyle(fontSize: 13, color: Anju.muted),
                  ),
                _statusRow('应用通知总开关', status.appEnabled),
                _statusRow('居家危险提醒渠道', status.channelEnabled),
                if (!status.enabled)
                  const InfoBanner('系统通知尚未全部开启。应用内提示仍可显示；可在下方申请权限或打开系统设置。'),
                if (status.permissionRequired && !status.permissionGranted)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _run(_requestPermission),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('申请通知权限'),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(_android.openNotificationSettings),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('系统通知设置'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(_android.openChannelSettings),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('居家危险提醒渠道设置'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(_android.openAppSettings),
                  icon: const Icon(Icons.settings_applications_outlined),
                  label: const Text('系统应用设置'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text('安全推送状态', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            InfoBanner(
              c.settings.bearerToken.isEmpty
                  ? '尚未填写统一访问令牌，请先连接后端。'
                  : c.pushStatus,
            ),
            const SizedBox(height: 12),
            Text(
              'App 在前台刷新统一告警。通知服务尚未就绪，后台和锁屏提醒尚未验证。',
              style: const TextStyle(
                fontSize: 13,
                color: Anju.muted,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) InfoBanner(_error!, error: true),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_refresh),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_busy ? '正在检查…' : '刷新通知状态'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
