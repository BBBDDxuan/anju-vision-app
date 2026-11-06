import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/household.dart';
import '../models/models.dart';
import 'api.dart';
import 'settings_store.dart';

class Recording {
  const Recording({required this.id, required this.name, this.durationMs = 0});
  final String id, name;
  final int durationMs;
  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
    id: j['id'].toString(),
    name: (j['name'] ?? '未命名录像').toString(),
    durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
  );
}

class VideoMemory {
  const VideoMemory(this.videoId, this.data);
  final String videoId;
  final Map<String, dynamic> data;
  List<Map<String, dynamic>> maps(String key) => (data[key] as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  List<Map<String, dynamic>> get frames => maps('frames');
  List<Map<String, dynamic>> get evidence => maps('evidence');
  List<Map<String, dynamic>> get entities => maps('entities');
  Map<String, dynamic>? entity(String id) =>
      entities.where((e) => e['id'] == id).firstOrNull;
  List<RecentObject> objectRecords(String service) {
    final result = <RecentObject>[];
    for (final entity in entities.where((e) => e['entity_type'] == 'object')) {
      final id = entity['id'].toString();
      final events =
          maps('events')
              .where(
                (e) =>
                    e['subject_id'] == id && e['epistemic_type'] == 'observed',
              )
              .toList()
            ..sort(
              (a, b) => ((b['end_ms'] as num?) ?? 0).compareTo(
                (a['end_ms'] as num?) ?? 0,
              ),
            );
      if (events.isEmpty) continue;
      final event = events.first;
      final target = entityFor(event['target_id']?.toString());
      final action = event['action']?.toString() ?? '';
      final location = target == null
          ? '位置未明确'
          : action == 'put_in'
          ? '放入${target['label']}（后续不可见）'
          : target['label'].toString();
      result.add(
        RecentObject(
          id: '$service|$videoId|$id',
          name: entity['label']?.toString() ?? '未命名物品',
          source: 'video',
          recordedAt: DateTime.now(),
          videoId: videoId,
          entityId: id,
          videoMs: (event['end_ms'] as num?)?.toInt() ?? 0,
          location: location,
          serviceUrl: service,
        ),
      );
    }
    result.sort((a, b) => b.videoMs.compareTo(a.videoMs));
    return result;
  }

  Map<String, dynamic>? entityFor(String? id) =>
      id == null ? null : entities.where((e) => e['id'] == id).firstOrNull;
  List<Map<String, dynamic>> framesForEvidence(Iterable<String> ids) {
    final frameIds = evidence
        .where((e) => ids.contains(e['id']))
        .expand((e) => (e['frame_ids'] as List? ?? []).map((v) => v.toString()))
        .toSet();
    return frames.where((f) => frameIds.contains(f['id'])).toList();
  }
}

class ObjectApi {
  ObjectApi(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client() {
    final candidate = AppSettings(
      baseUrl: config.baseUrl,
      bearerToken: 'url-validation-only',
    );
    if (candidate.validationError != null)
      throw ApiException(candidate.validationError!);
    if (RegExp(r'\s').hasMatch(config.token))
      throw const ApiException('录像服务令牌不能含空白');
  }
  final Map<String, List<SafetyEvent>> _safetyCache = {};
  final List<String> safetyWarnings = [];
  final ObjectServiceConfig config;
  final http.Client _client;
  final Duration timeout;
  Uri uri(String path) {
    final root = Uri.parse(config.baseUrl.replaceAll(RegExp(r'/+$'), ''));
    final result = root.resolve(path);
    if (result.scheme != root.scheme ||
        result.host != root.host ||
        result.port != root.port ||
        result.userInfo.isNotEmpty)
      throw const ApiException('证据地址必须属于同一录像服务');
    return result;
  }

  Map<String, String> get headers => {
    if (config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
  };
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? requestTimeout,
  }) async {
    final request = http.Request(method, uri(path))..followRedirects = false;
    request.headers.addAll({...headers, 'Accept': 'application/json'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(requestTimeout ?? timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          final value = body is Map && body['error'] is Map
              ? body['error']['code']
              : null;
          if (value is String && RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(value))
            code = value;
        } catch (_) {
          /* Never display arbitrary server bodies or credentials. */
        }
        final known = switch (code) {
          'CAMERA_AUTH_FAILED' => '摄像头本地账号或密码未通过认证，请核对设备密码与 RTSP 权限；这不是后端访问令牌错误',
          'CAMERA_STREAM_NOT_FOUND' => '摄像头视频路径不存在，请核对 stream1、stream2 或通道参数',
          'CAMERA_STREAM_TIMEOUT' => '摄像头取流超时，请检查设备是否在线及取流连接数',
          'CAMERA_STREAM_UNAVAILABLE' => '摄像头端口可达但无法取流，请检查 RTSP 服务、视频路径及连接数',
          'CAMERA_PROBE_MISSING' => '后端取流检查工具不可用，请检查电脑上的 FFprobe 配置',
          'CAMERA_UNREACHABLE' => '电脑后端无法连接摄像头，请检查电脑到摄像头的网络和 RTSP 端口',
          'CAMERA_ALERT_RELAY_MISSING' => '摄像头告警身份未配置，请由后端负责人重新运行手机服务配置',
          'CAMERA_RUNTIME_MISSING' => '电脑上的摄像头模型运行环境未就绪',
          'TRANSCODE_FAILED' => '视频转码失败，请由后端检查 FFmpeg 与编码兼容性',
          'MODEL_NOT_CONFIGURED' ||
          'NETWORK_DISABLED' ||
          'COST_NOT_CONFIRMED' ||
          'SAFETY_REVIEW_DISABLED' => '模型环境未就绪，请由后端负责人检查配置',
          'INVALID_MP4' || 'VIDEO_INVALID' => '文件内容不是有效的 MP4，请重新导出为 MP4 后上传',
          'VIDEO_ROTATION' => '此视频带有旋转信息，当前后端暂不支持；请在相册中编辑并重新导出后上传',
          'VIDEO_DURATION' => '视频时长无效或超过后端上限，请缩短视频或检查后端时长配置',
          'VIDEO_RESOLUTION' => '视频分辨率超出后端范围，请导出为 1080p 或更低分辨率后上传',
          'VIDEO_STREAM' || 'NO_VIDEO_STREAM' => '视频轨道不符合要求，请导出为单视频轨道的 MP4 后上传',
          'MEDIA_PROBE_FAILED' ||
          'PROBE_FAILED' => '后端无法读取视频信息，请检查视频是否损坏及 FFprobe 配置',
          'INVALID_METADATA' => '视频缺少有效的时长或尺寸信息，请重新导出 MP4 后上传',
          'EMPTY_CHUNK' => '收到的视频片段为空，请重新选择手机本地视频后上传',
          _ => null,
        };
        throw ApiException(
          (known ??
                  switch (response.statusCode) {
                    400 =>
                      utf8
                                  .decode(
                                    response.bodyBytes,
                                    allowMalformed: true,
                                  )
                                  .trim() ==
                              'Invalid host header'
                          ? '录像服务拒绝了访问地址，请检查主机白名单与网关配置'
                          : '录像服务未接受此请求，请检查视频要求与后端错误记录',
                    401 || 403 => '录像服务认证失败，请检查访问令牌',
                    404 => '录像或证据不存在',
                    409 => '该录像暂无可用结果，请在视频工作台完成分析',
                    429 => '服务请求额度不足，请稍后重试',
                    413 => '视频超过后端限制或存储空间不足',
                    _ => '录像服务请求失败（HTTP ${response.statusCode}）',
                  }) +
              (code == null ? '' : '（错误码：$code）'),
          statusCode: response.statusCode,
          code: code,
        );
      }
      return response;
    } on TimeoutException {
      throw const ApiException('录像服务响应超时，请检查地址与网络');
    } on http.ClientException {
      throw const ApiException('无法连接录像服务，请检查网络与服务地址');
    }
  }

  dynamic _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ApiException('录像服务返回了无效 JSON');
    }
  }

  Future<List<Recording>> recordings() async {
    final data = _json(await _request('GET', '/api/videos'));
    if (data is! Map || data['videos'] is! List)
      throw const ApiException('录像列表格式不正确');
    return (data['videos'] as List)
        .map((e) => Recording.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<SafetyEvent>> safetyEvents() async {
    final videos = await recordings();
    safetyWarnings.clear();
    final ids = videos.map((v) => v.id).toSet();
    _safetyCache.removeWhere((id, _) => !ids.contains(id));
    var successes = 0;
    // Bound concurrent requests while retaining results for temporarily unavailable videos.
    for (var offset = 0; offset < videos.length; offset += 3) {
      await Future.wait(
        videos.skip(offset).take(3).map((video) async {
          try {
            _safetyCache[video.id] = await safetyEventsFor(video);
            successes++;
          } catch (e) {
            safetyWarnings.add('${video.name}：$e');
          }
        }),
      );
    }
    if (videos.isNotEmpty && successes == 0 && _safetyCache.isEmpty) {
      throw ApiException(safetyWarnings.join('；'));
    }
    return _safetyCache.values.expand((e) => e).toList();
  }

  Future<List<SafetyEvent>> safetyEventsFor(Recording video) async {
    final data = _json(
      await _request(
        'GET',
        '/api/videos/${Uri.encodeComponent(video.id)}/alerts',
      ),
    );
    if (data is! Map ||
        data['alerts'] is! List ||
        data['evidence'] is! List ||
        data['frames'] is! List) {
      throw const ApiException('录像告警格式不正确');
    }
    final events = <SafetyEvent>[];
    for (final alert in (data['alerts'] as List).whereType<Map>()) {
      if (alert['is_mock'] == true) continue;
      final type = switch (alert['action']) {
        'fall' || 'lying_on_floor' => 'suspected_fall',
        'help_gesture' => 'help_requested',
        'flame' => 'fire_detected',
        _ => null,
      };
      if (type == null || alert['id'] == null) continue;
      final refs = (alert['evidence_ids'] as List? ?? []).toSet();
      final frameIds = (data['evidence'] as List)
          .whereType<Map>()
          .where((e) => refs.contains(e['id']))
          .expand((e) => (e['frame_ids'] as List? ?? []))
          .toSet();
      final frame = (data['frames'] as List)
          .whereType<Map>()
          .where((f) => frameIds.contains(f['id']))
          .firstOrNull;
      final evidenceUrl = frame?['url']?.toString();
      if (evidenceUrl != null) uri(evidenceUrl);
      final ack = alert['acknowledged'] == true || alert['acknowledged'] == 1;
      events.add(
        SafetyEvent(
          id: 'video:${video.id}:${alert['id']}',
          deviceId: 'video:${video.id}',
          eventType: type,
          severity: alert['severity'] == 'urgent' ? 'critical' : 'warning',
          confidence: (alert['model_score'] as num?)?.toDouble(),
          // The backend provides a video offset, not a wall-clock capture time.
          occurredAt: dateField(
            Map<String, dynamic>.from(alert),
            'occurred_at',
          ),
          createdAt: dateField(Map<String, dynamic>.from(alert), 'created_at'),
          evidenceId: evidenceUrl,
          reviewStatus: alert['epistemic_type']?.toString() ?? 'observed',
          reviewSummary:
              '${alert['title'] ?? ''} · 录像 ${videoClock((alert['start_ms'] as num?) ?? 0)}',
          notificationStatus: 'foreground_polling',
          acknowledgementStatus: ack ? 'acknowledged' : 'pending',
          state: ack ? 'acknowledged' : 'open',
          trackId: alert['subject_id']?.toString(),
          details: {
            'source': 'uploaded_recording',
            'source_url': config.baseUrl,
            'video_id': video.id,
            'video_name': video.name,
            'alert_id': alert['id'],
            'start_ms': alert['start_ms'],
            'end_ms': alert['end_ms'],
          },
        ),
      );
    }
    _safetyCache[video.id] = events;
    return events;
  }

  Future<void> acknowledgeSafety(SafetyEvent event) async {
    final video = Uri.encodeComponent(event.details['video_id'].toString());
    final alert = Uri.encodeComponent(event.details['alert_id'].toString());
    final data = _json(
      await _request('POST', '/api/videos/$video/alerts/$alert/acknowledge'),
    );
    if (data is! Map || data['acknowledged'] != true) {
      throw const ApiException('录像服务未确认接收操作');
    }
  }

  Future<VideoMemory> memory(String id) async {
    final data = _json(
      await _request('GET', '/api/videos/${Uri.encodeComponent(id)}/events'),
    );
    if (data is! Map) throw const ApiException('录像分析记录格式不正确');
    return VideoMemory(id, Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> query(
    String id,
    String question, {
    String? entityId,
  }) async {
    final data = _json(
      await _request(
        'POST',
        '/api/videos/${Uri.encodeComponent(id)}/query',
        body: {
          'question': question,
          'entity_id': entityId,
          'use_model': config.useCloud,
        },
      ),
    );
    if (data is! Map) throw const ApiException('物品查询返回格式不正确');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> replay(String videoId, String entityId) async {
    final query = Uri(queryParameters: {'entity_id': entityId}).query;
    final data = _json(
      await _request(
        'GET',
        '/api/videos/${Uri.encodeComponent(videoId)}/replay?$query',
      ),
    );
    if (data is! Map) throw const ApiException('物品回看格式不正确');
    return Map<String, dynamic>.from(data);
  }

  Future<Uint8List> frame(String path) async {
    final response = await _request('GET', path);
    if (!(response.headers['content-type'] ?? '').startsWith('image/') ||
        response.bodyBytes.length > 5000000)
      throw const ApiException('证据图片格式或大小不符合要求');
    return response.bodyBytes;
  }

  Uri videoUri(String id) => uri('/media/videos/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> getJson(String path) async {
    final data = _json(await _request('GET', path));
    if (data is! Map) throw const ApiException('服务返回格式不正确');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> postJson(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final data = _json(
      await _request(
        'POST',
        path,
        body: body,
        requestTimeout: path.endsWith('/complete')
            ? const Duration(minutes: 5)
            : null,
      ),
    );
    if (data is! Map) throw const ApiException('服务返回格式不正确');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> postBytes(String path, Uint8List bytes) async {
    final request = http.Request('POST', uri(path))..followRedirects = false;
    request.headers.addAll({
      ...headers,
      'Content-Type': 'video/mp4',
      'Accept': 'application/json',
    });
    request.bodyBytes = bytes;
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw ApiException(
          '视频片段上传失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      final data = _json(response);
      if (data is! Map) throw const ApiException('上传响应格式不正确');
      return Map<String, dynamic>.from(data);
    } on TimeoutException {
      throw const ApiException('上传响应超时，请刷新录像库确认后重试');
    } on http.ClientException {
      throw const ApiException('上传连接中断，请检查网络后重试');
    }
  }

  void close() => _client.close();
}

String videoClock(num milliseconds) {
  final seconds = (milliseconds / 1000).floor();
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
