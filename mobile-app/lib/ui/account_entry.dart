import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../app_controller.dart';
import '../services/settings_store.dart';
import '../services/backend_tls.dart';
import 'pair_scanner.dart';
import 'widgets.dart';

const _storage = FlutterSecureStorage();
const _sessionKey = 'anju_account_session_v1';
const _addressKey = 'anju_account_address_v1';

class _AuthError implements Exception {
  const _AuthError(this.status, this.message);
  final int status;
  final String message;
}

String? _address(String input) {
  final value = input.trim().replaceAll(RegExp(r'/+$'), '');
  return AppSettings(baseUrl: value).validationError == null &&
          Uri.tryParse(value)?.scheme == 'https'
      ? value
      : null;
}

Future<Map<String, dynamic>> _auth(
  String origin,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  final client = backendClient(origin);
  try {
    final request = http.Request(
      body == null ? 'GET' : 'POST',
      Uri.parse('$origin/api/auth/$path'),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(const Duration(seconds: 12));
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const _AuthError(0, '后端地址发生跳转，请直接填写正确的服务地址。');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    if (response.statusCode != 200) {
      final error = decoded['error'];
      throw _AuthError(
        response.statusCode,
        error is Map && error['message'] is String
            ? error['message'] as String
            : '账号请求失败。',
      );
    }
    return decoded;
  } on _AuthError {
    rethrow;
  } catch (_) {
    throw const _AuthError(0, '无法连接账号服务，请检查后端地址、网络或 HTTPS 证书。');
  } finally {
    client.close();
  }
}

class AccountEntry extends StatefulWidget {
  const AccountEntry({super.key});

  @override
  State<AccountEntry> createState() => _AccountEntryState();
}

class _AccountEntryState extends State<AccountEntry>
    with WidgetsBindingObserver {
  final _origin = TextEditingController();
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = true, _showPassword = false, _checking = false;
  String? _message, _invite, _inviteOrigin, _household, _token;
  Map<String, dynamic>? _user;
  SafetyController? _controller;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    _controller?.dispose();
    for (final field in [_origin, _username, _name, _password, _confirm]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _restore() async {
    try {
      final previous =
          await _storage.read(key: _addressKey) ??
          (await SecureSettingsStore().load()).baseUrl;
      if (!mounted) return;
      if (previous == defaultApiBaseUrl) {
        _origin.text = localBackendOrigin;
      } else {
        final uri = Uri.tryParse(previous);
        if (uri != null && uri.hasAuthority && uri.scheme == 'http') {
          _origin.text = uri
              .replace(scheme: 'https', port: uri.port)
              .toString();
        } else {
          _origin.text = previous;
        }
      }
      final raw = await _storage.read(key: _sessionKey);
      if (!mounted || raw == null) return;
      final saved = jsonDecode(raw) as Map;
      final origin = _address(saved['origin'] as String);
      final token = saved['token'] as String;
      if (origin == null || token.length != 43) {
        await _storage.delete(key: _sessionKey);
        return;
      }
      final result = await _auth(origin, 'me', token: token);
      await _open(origin, token, result);
    } on _AuthError catch (error) {
      if (error.status == 401) await _storage.delete(key: _sessionKey);
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '无法恢复登录，请重新登录。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(
    String origin,
    String token,
    Map<String, dynamic> data,
  ) async {
    final user = Map<String, dynamic>.from(data['user'] as Map);
    final id = user['id'] as String;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) || token.length != 43) {
      throw const FormatException();
    }
    final store = SecureSettingsStore(namespace: '$origin|$id');
    final settings = (await store.load()).copyWith(
      baseUrl: origin,
      bearerToken: token,
    );
    await store.save(settings);
    await _storage.write(key: _addressKey, value: origin);
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'origin': origin, 'token': token}),
    );
    if (!mounted) return;
    _origin.text = origin;
    _password.clear();
    _confirm.clear();
    setState(() {
      _user = user;
      _token = token;
      _controller = SafetyController(store: store, accountMode: true);
    });
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    final token = _token;
    if (token == null || _checking) return;
    _checking = true;
    try {
      await _auth(_origin.text, 'me', token: token);
    } on _AuthError catch (error) {
      if (mounted && _token == token && error.status == 401) {
        await _leave('登录已失效，请重新登录。');
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _leave([String? message]) async {
    final old = _controller;
    _checkTimer?.cancel();
    await _storage.delete(key: _sessionKey);
    if (!mounted) return;
    setState(() {
      _controller = null;
      _user = null;
      _token = null;
      _invite = null;
      _inviteOrigin = null;
      _household = null;
      _message = message;
      _busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null) return;
    String? message;
    try {
      await _auth(_origin.text, 'logout', body: {}, token: token);
    } on _AuthError catch (error) {
      if (error.status != 401) message = '已退出本机；未能通知电脑撤销会话，请联系管理员。';
    }
    if (mounted && _token == token) await _leave(message);
  }

  Future<void> _scanWithContext(
    BuildContext scannerContext,
    bool invite,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final raw = await scanRawQr(scannerContext);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw) as Map;
      final origin = data['origin'] is String
          ? _address(data['origin'] as String)
          : null;
      if (origin == null) {
        throw const _AuthError(0, '此二维码不含 HTTPS 地址，请在电脑生成新版二维码。');
      }
      final kind = data['kind'];
      if (invite) {
        final code = data['code'];
        if (kind != 'anju-invite-v1' ||
            code is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code)) {
          throw const FormatException();
        }
        _origin.text = origin;
        setState(() {
          _invite = code;
          _inviteOrigin = origin;
          _household = null;
        });
        await _inviteInfo(origin);
      } else {
        if (kind != 'anju-server-v1' && kind != 'anju-pair-v1')
          throw const FormatException();
        _origin.text = origin;
        setState(() {
          _invite = null;
          _inviteOrigin = null;
          _household = null;
        });
      }
    } on _AuthError catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '这不是有效的安居视界电脑地址码或邀请二维码。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteInfo(String origin) async {
    final result = await _auth(origin, 'invite-info', body: {'code': _invite});
    if (mounted)
      setState(() => _household = result['household_name'] as String);
  }

  Future<void> _submit() async {
    final origin = _address(_origin.text);
    final register = _invite != null;
    if (origin == null || (register && origin != _inviteOrigin)) {
      setState(() => _message = '请输入以 https:// 开头的电脑后端地址。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (register && _household == null) {
        await _inviteInfo(origin);
        return;
      }
      if (!RegExp(r'^[A-Za-z0-9_.-]{3,32}$').hasMatch(_username.text.trim())) {
        throw const _AuthError(422, '用户名需为 3–32 位英文字母、数字、点、横线或下划线。');
      }
      if (_password.text.isEmpty ||
          (register &&
              (_password.text.length < 12 ||
                  _password.text != _confirm.text ||
                  _name.text.trim().isEmpty))) {
        throw const _AuthError(422, '请填写密码；注册密码至少 12 个字符，两次输入一致，并填写显示名称。');
      }
      final result = await _auth(
        origin,
        register ? 'register' : 'login',
        body: {
          'client': 'app',
          'username': _username.text.trim(),
          'password': _password.text,
          if (register) 'display_name': _name.text.trim(),
          if (register) 'code': _invite,
        },
      );
      await _open(origin, result['token'] as String, result);
    } on _AuthError catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '未能保存账号会话，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final user = _user;
    if (controller != null && user != null) {
      return ElderSafetyApp(
        controller: controller,
        accountLabel:
            '${user['display_name']} · ${user['role'] == 'admin' ? '管理员' : '家庭成员'}',
        accountDisplayName: user['display_name'] as String?,
        accountId: user['id'] as String,
        onAccountLogout: _logout,
      );
    }
    final registering = _invite != null;
    return MaterialApp(
      theme: Anju.theme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    '安居视界',
                    style: TextStyle(
                      color: Anju.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registering ? '注册并加入家庭' : '登录家庭账号',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_household != null) Text('邀请你加入：$_household'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _origin,
                    enabled: !_busy && !registering,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '电脑后端地址',
                      hintText: 'https://电脑地址:8000',
                    ),
                  ),
                  if (!registering)
                    Builder(
                      builder: (context) => Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _scanWithContext(context, false),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('扫码填写地址'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _scanWithContext(context, true),
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('扫码加入家庭'),
                          ),
                        ],
                      ),
                    ),
                  if (!registering || _household != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      enabled: !_busy,
                      maxLength: 32,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    if (registering)
                      TextField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 40,
                        decoration: const InputDecoration(labelText: '显示名称'),
                      ),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: !_showPassword,
                      maxLength: 128,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          tooltip: '显示或隐藏密码',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    if (registering)
                      TextField(
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        maxLength: 128,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(labelText: '确认密码'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? '处理中…'
                          : registering
                          ? (_household == null ? '确认邀请' : '注册并加入')
                          : '登录',
                    ),
                  ),
                  if (registering)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _invite = null;
                              _inviteOrigin = null;
                              _household = null;
                              _message = null;
                              _password.clear();
                              _confirm.clear();
                            }),
                      child: const Text('返回登录'),
                    ),
                  if (_message != null) InfoBanner(_message!, error: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
