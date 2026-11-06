import 'backend_tls.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../models/unified_alert.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}

abstract interface class UnifiedAlertRepository implements SafetyRepository {
  String get backendUrl;
  Future<Map<String, dynamic>> connection();
  Future<Map<String, dynamic>> alertPage({int offset = 0, int limit = 100});
  Future<Map<String, dynamic>> alertChanges(int after, {int limit = 100});
  Future<SafetyEvent> handleAlert(String id, {required bool resolve});
  Uri mediaUri(String path);
  Future<Uint8List> mediaImage(String path);
}

/// A's single-origin 2026-11-04.v1 contract; legacy device/preferences APIs
/// are compatibility routes at this same origin, never a second phone setting.
class UnifiedHttpSafetyRepository extends HttpSafetyRepository
    implements UnifiedAlertRepository {
  UnifiedHttpSafetyRepository({
    required super.baseUrl,
    required super.bearerToken,
    super.client,
    super.timeout,
  });
  @override
  String get backendUrl => baseUrl;
  Future<Map<String, dynamic>> _getObject(String path) async =>
      _object(_json(await _request('GET', path)));
  @override
  Future<Map<String, dynamic>> connection() async {
    final result = await _getObject('/api/connection');
    if (result['contract_version'] != '2026-11-04.v1' ||
        result['household'] != 'default') {
      throw const ApiException('后端统一接口契约不匹配，请使用 A 的 start-phone 启动入口');
    }
    return result;
  }

  @override
  Future<bool> health() async {
    await connection();
    return true;
  }

  @override
  Future<Map<String, dynamic>> alertPage({int offset = 0, int limit = 100}) =>
      _getObject('/api/alerts?limit=$limit&offset=$offset');
  @override
  Future<Map<String, dynamic>> alertChanges(int after, {int limit = 100}) =>
      _getObject('/api/alerts/changes?after=$after&limit=$limit');
  SafetyEvent _alert(Map<String, dynamic> data) {
    try {
      return unifiedAlertFromJson(data);
    } on FormatException {
      throw const ApiException('统一告警格式无效，未应用本次同步');
    } on TypeError {
      throw const ApiException('统一告警字段类型无效，未应用本次同步');
    }
  }

  @override
  Future<SafetyEvent> event(String id) async =>
      _alert(await _getObject('/api/alerts/${Uri.encodeComponent(id)}'));
  @override
  Future<List<SafetyEvent>> events() async => (await alertPage())['alerts']
      .cast<Map>()
      .map((v) => _alert(Map<String, dynamic>.from(v)))
      .toList()
      .cast<SafetyEvent>();
  @override
  Future<SafetyEvent> handleAlert(
    String id, {
    required bool resolve,
  }) async => _alert(
    _object(
      _json(
        await _request(
          'POST',
          '/api/alerts/${Uri.encodeComponent(id)}/${resolve ? 'resolve' : 'ack'}',
        ),
      ),
    ),
  );
  @override
  Future<void> acknowledge(String id) async {
    await handleAlert(id, resolve: false);
  }

  @override
  Future<void> resolve(String id) async {
    await handleAlert(id, resolve: true);
  }

  @override
  Uri mediaUri(String path) {
    final root = Uri.parse(baseUrl);
    final uri = root.resolve(path);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != root.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const ApiException('证据或播放地址必须属于当前统一后端');
    }
    return uri;
  }

  @override
  Future<Uint8List> mediaImage(String path) async {
    final uri = mediaUri(path);
    final response = await _request(
      'GET',
      '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
      image: true,
    );
    if (!(response.headers['content-type'] ?? '').toLowerCase().startsWith(
          'image/',
        ) ||
        response.bodyBytes.length > 16 * 1024 * 1024) {
      throw const ApiException('证据响应不是有效大小的图片');
    }
    return response.bodyBytes;
  }

  @override
  Future<Uint8List> evidence(String id) => mediaImage(id);
}

class AlertSyncResult {
  const AlertSyncResult(this.events, this.changed, this.cursor, this.initial);
  final List<SafetyEvent> events, changed;
  final int cursor;
  final bool initial;
}

/// Transactional list + cursor synchronization. No UI or notification logic.
class UnifiedAlertSynchronizer {
  UnifiedAlertSynchronizer(this.repository, {this.persist});
  final UnifiedAlertRepository repository;
  final Future<void> Function(Map<String, dynamic>)? persist;
  Map<String, SafetyEvent> _items = {};
  int _cursor = 0;
  bool _initialized = false, _published = false;
  int _acceptedSequence = 0;
  final Map<String, int> _acceptedAt = {};
  List<SafetyEvent> get events => List.unmodifiable(_items.values);
  int get cursor => _cursor;
  String get scope => '${repository.backendUrl}|default';

  void restore(Map<String, dynamic>? cache) {
    if (cache == null ||
        cache['scope'] != scope ||
        cache['contract_version'] != '2026-11-04.v1')
      return;
    try {
      final cursor = cache['cursor'];
      if (cursor is! int || cursor < 0 || cache['events'] is! List) return;
      final restored = <String, SafetyEvent>{};
      for (final raw in cache['events'] as List) {
        final event = SafetyEvent.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        if (!event.isUnified || event.revision < 1) return;
        restored[event.id] = event;
      }
      _items = restored;
      _cursor = cursor;
      _initialized = true;
    } catch (_) {
      /* Corrupt local cache cannot establish a baseline. */
    }
  }

  Map<String, dynamic> _cache(Map<String, SafetyEvent> items, int cursor) => {
    'contract_version': '2026-11-04.v1',
    'scope': scope,
    'cursor': cursor,
    'events': items.values.map((e) => e.toJson()).toList(),
  };
  void _merge(Map<String, SafetyEvent> target, Iterable<SafetyEvent> events) {
    for (final event in events) {
      if (target[event.id] == null ||
          event.revision > target[event.id]!.revision)
        target[event.id] = event;
    }
  }

  List<SafetyEvent> _events(Map<String, dynamic> data) {
    try {
      return (data['alerts'] as List)
          .map(
            (raw) =>
                unifiedAlertFromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList();
    } catch (_) {
      throw const ApiException('统一告警分页格式无效，游标未前移');
    }
  }

  int _integer(Map<String, dynamic> data, String key) {
    final n = data[key];
    if (n is! int || n < 0) throw const ApiException('统一告警游标无效');
    return n;
  }

  Future<AlertSyncResult> synchronize() async {
    var acceptedBeforeStart = _acceptedSequence;
    await repository.connection();
    var bootstrap = !_initialized;
    var next = bootstrap
        ? <String, SafetyEvent>{}
        : Map<String, SafetyEvent>.from(_items);
    var cursor = _cursor;
    final changes = <SafetyEvent>[];
    for (var reset = 0; reset < 2; reset++) {
      if (bootstrap) {
        next = {};
        changes.clear();
        var offset = 0;
        var first = true;
        while (true) {
          final page = await repository.alertPage(offset: offset);
          final loaded = _events(page);
          if (first) {
            cursor = _integer(page, 'snapshot_cursor');
            first = false;
          }
          if (_integer(page, 'offset') != offset || page['has_more'] is! bool)
            throw const ApiException('告警分页不连续，未应用部分列表');
          _merge(next, loaded);
          if (page['has_more'] == false) break;
          if (loaded.isEmpty || offset > 1000000)
            throw const ApiException('告警分页未取得进展');
          offset += loaded.length;
        }
      }
      var rebuilt = false;
      for (var pageNumber = 0; ; pageNumber++) {
        Map<String, dynamic> page;
        try {
          page = await repository.alertChanges(cursor);
        } on ApiException catch (error) {
          if (!bootstrap && [409, 410, 422].contains(error.statusCode)) {
            rebuilt = true;
            break;
          }
          rethrow;
        }
        final server = _integer(page, 'server_cursor');
        if (server < cursor) {
          rebuilt = true;
          break;
        }
        final loaded = _events(page);
        final after = _integer(page, 'next_cursor');
        if (after < cursor ||
            after > server ||
            page['has_more'] is! bool ||
            (loaded.isNotEmpty && after <= cursor))
          throw const ApiException('告警增量游标不连续');
        _merge(next, loaded);
        changes.addAll(loaded);
        if (page['has_more'] == false) {
          cursor = after;
          break;
        }
        if (after <= cursor || pageNumber > 10000)
          throw const ApiException('告警增量分页未取得进展');
        cursor = after;
      }
      if (!rebuilt) {
        // Preserve ack/resolve responses received while this request was in flight.
        if (!bootstrap) _merge(next, _items.values);
        _merge(
          next,
          _items.values.where(
            (e) => (_acceptedAt[e.id] ?? 0) > acceptedBeforeStart,
          ),
        );
        if (persist != null) await persist!(_cache(next, cursor));
        if (!bootstrap) _merge(next, _items.values);
        _merge(
          next,
          _items.values.where(
            (e) => (_acceptedAt[e.id] ?? 0) > acceptedBeforeStart,
          ),
        );
        _items = next;
        _cursor = cursor;
        _initialized = true;
        final initial = bootstrap || !_published;
        _published = true;
        return AlertSyncResult(
          events,
          List.unmodifiable(changes),
          cursor,
          initial,
        );
      }
      bootstrap = true;
      acceptedBeforeStart = _acceptedSequence;
    }
    throw const ApiException('告警中心在同步期间重建，请稍后刷新');
  }

  Future<SafetyEvent> accept(SafetyEvent event) async {
    _merge(_items, [event]);
    _acceptedAt[event.id] = ++_acceptedSequence;
    if (persist != null && _initialized)
      await persist!(_cache(_items, _cursor));
    return _items[event.id]!;
  }
}

abstract interface class SafetyRepository {
  Future<bool> health();
  Future<List<SafetyDevice>> devices();
  Future<List<SafetyEvent>> events();
  Future<SafetyEvent> event(String id);
  Future<Uint8List> evidence(String id);
  Future<void> acknowledge(String id);
  Future<void> resolve(String id);
  Future<FamilyPreferences> preferences();
  Future<void> savePreferences(FamilyPreferences preferences);
  Future<String> registerPush(String token, String platform, String contactId);
  Future<void> deletePush(String id);
  void close();
}

class HttpSafetyRepository implements SafetyRepository {
  HttpSafetyRepository({
    required String baseUrl,
    required this.bearerToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? backendClient(baseUrl);
  final String baseUrl;
  final String bearerToken;
  final http.Client _client;
  final Duration timeout;

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool image = false,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.followRedirects = false;
    request.headers['Accept'] = image ? 'image/*' : 'application/json';
    if (authenticated) request.headers['Authorization'] = 'Bearer $bearerToken';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = switch (response.statusCode) {
          400 => '后端拒绝了访问地址，请检查主机白名单',
          401 => '认证失败，请在设置中检查用户 token',
          403 => '该用户无权访问此资源',
          404 => '资源不存在或已被删除',
          409 => '事件状态已变化，请刷新后重试',
          410 => '证据已过期，无法读取截图',
          422 => '字段不符合后端要求，请检查输入范围',
          429 => '服务请求额度不足，请稍后重试',
          503 => '后端服务或模型环境未就绪，请查看电脑端配置',
          _ => '后端请求失败（HTTP ${response.statusCode}）',
        };
        // Do not echo a response body which might contain credentials.
        throw ApiException(message, statusCode: response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw const ApiException('连接超时，请检查网络与后端 URL');
    } on http.ClientException {
      throw const ApiException('无法连接后端，请检查网络、URL 和平台网络权限');
    }
  }

  dynamic _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('后端返回了无效 JSON');
    }
  }

  Future<List<dynamic>> _list(String path) async {
    final value = _json(await _request('GET', '/api/v1$path'));
    if (value is! List) throw const ApiException('后端应返回列表数组');
    return value;
  }

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) throw const ApiException('后端应返回 JSON 对象');
    return Map<String, dynamic>.from(value);
  }

  String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<bool> health() async =>
      (await _request('GET', '/health', authenticated: false)).statusCode < 300;
  @override
  Future<List<SafetyDevice>> devices() async => (await _list(
    '/devices',
  )).map((v) => SafetyDevice.fromJson(_object(v))).toList();
  @override
  Future<List<SafetyEvent>> events() async => (await _list(
    '/events',
  )).map((v) => SafetyEvent.fromJson(_object(v))).toList();
  @override
  Future<SafetyEvent> event(String id) async => SafetyEvent.fromJson(
    _object(_json(await _request('GET', '/api/v1/events/${_id(id)}'))),
  );
  @override
  Future<Uint8List> evidence(String id) async {
    final response = await _request(
      'GET',
      '/api/v1/evidence/${_id(id)}',
      image: true,
    );
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (!type.startsWith('image/')) throw const ApiException('证据响应不是图片');
    return response.bodyBytes;
  }

  @override
  Future<void> acknowledge(String id) async {
    await _request('POST', '/api/v1/events/${_id(id)}/ack');
  }

  @override
  Future<void> resolve(String id) async {
    await _request('POST', '/api/v1/events/${_id(id)}/resolve');
  }

  @override
  Future<FamilyPreferences> preferences() async => FamilyPreferences.fromJson(
    _object(_json(await _request('GET', '/api/v1/preferences'))),
  );
  @override
  Future<void> savePreferences(FamilyPreferences preferences) async {
    await _request('PUT', '/api/v1/preferences', body: preferences.toJson());
  }

  @override
  Future<String> registerPush(
    String token,
    String platform,
    String contactId,
  ) async {
    final json = _object(
      _json(
        await _request(
          'POST',
          '/api/v1/push-tokens',
          body: {'token': token, 'platform': platform, 'contact_id': contactId},
        ),
      ),
    );
    final id = field(json, 'token_id');
    if (id.isEmpty) throw const ApiException('推送注册未返回 token_id');
    return id;
  }

  @override
  Future<void> deletePush(String id) async {
    try {
      await _request('DELETE', '/api/v1/push-tokens/${_id(id)}');
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
  }

  @override
  void close() => _client.close();
}
