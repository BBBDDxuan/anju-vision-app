import 'package:flutter/material.dart';

import '../services/members_api.dart';
import '../services/settings_store.dart';
import 'widgets.dart';

class RegisteredFamilyPanel extends StatefulWidget {
  const RegisteredFamilyPanel({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<RegisteredFamilyPanel> createState() => _RegisteredFamilyPanelState();
}

class _RegisteredFamilyPanelState extends State<RegisteredFamilyPanel> {
  late Future<List<Map<String, dynamic>>> _members;

  @override
  void initState() {
    super.initState();
    _members = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = MembersApi(widget.settings);
    try {
      final data = await api.request('GET', '/api/auth/family-members');
      return (data['members'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } finally {
      api.close();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _members,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('这里显示已注册的家庭账号，与被监护人员档案分开。'),
        const SizedBox(height: 12),
        if (snapshot.connectionState == ConnectionState.waiting)
          const LinearProgressIndicator()
        else if (snapshot.hasError)
          const InfoBanner('未能读取注册家庭成员，请检查后端后重试。', error: true)
        else
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final item in snapshot.data ?? <Map<String, dynamic>>[])
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Anju.light,
                      child: Text(
                        (item['display_name'] as String)
                            .trim()
                            .characters
                            .take(2)
                            .toString(),
                      ),
                    ),
                    title: Text(item['display_name'] as String),
                    subtitle: Text(item['role'] == 'admin' ? '管理员' : '家庭成员'),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: snapshot.connectionState == ConnectionState.waiting
              ? null
              : () => setState(() => _members = _load()),
          icon: const Icon(Icons.refresh),
          label: const Text('刷新家庭成员'),
        ),
      ],
    ),
  );
}
