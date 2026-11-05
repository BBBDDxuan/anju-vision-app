import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/household.dart';
import 'api.dart';
import 'settings_store.dart';

/// Household IDs belong to the connected computer. No face photos are cached here.
class MembersApi {
  MembersApi(this.settings, {http.Client? client})
    : _client = client ?? http.Client() {
    if (settings.validationError != null || settings.bearerToken.isEmpty) {
      throw const ApiException('请先配置电脑后端地址与访问令牌');
    }
  }
  final AppSettings settings;
  final http.Client _client;
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? json,
    Uint8List? image,
    String? imageType,
  }) async {
    final origin = Uri.parse(settings.baseUrl.trim());
    final uri = origin.resolve(path);
    if (uri.origin != origin.origin || !path.startsWith('/api/'))
      throw const ApiException('成员接口地址无效');
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer ${settings.bearerToken}',
      'Accept': 'application/json',
    });
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    if (image != null) {
      if (image.isEmpty || image.length > 5 * 1024 * 1024)
        throw const ApiException('请选择不超过 5 MiB 的 JPEG 或 PNG 照片');
      request.headers['Content-Type'] = imageType!;
      request.bodyBytes = image;
    }
    try {
      return await (() async {
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 1024 * 1024)
            throw const ApiException('成员服务返回内容过大');
          bytes.addAll(chunk);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          String? code;
          try {
            final body = jsonDecode(utf8.decode(bytes));
            code = (body['error'] is Map ? body['error']['code'] : body['code'])
                ?.toString();
          } catch (_) {}
          if (response.statusCode == 401 || response.statusCode == 403)
            throw const ApiException('没有成员服务访问权限，请检查连接令牌');
          if (response.statusCode == 404)
            throw const ApiException('成员不存在或后端尚未更新，请刷新并确认两端版本');
          const errors = {
            'FACE_SINGLE_REQUIRED': '照片需包含一张清晰人脸，请换一张照片',
            'FACE_ENROLLMENT_QUALITY': '照片需包含一张足够清晰的人脸，请换一张照片',
            'FACE_IMAGE_INVALID': '照片无法读取，请使用方向正常的 JPEG 或 PNG',
            'FACE_IMAGE_DIMENSIONS': '照片像素过大，请缩小后重试',
            'HOUSEHOLD_REVISION_CONFLICT': '档案已被其他设备修改，请刷新后重新编辑',
            'HOUSEHOLD_MEMBER_LIMIT': '家庭成员已达 32 人上限，请先整理已有档案',
            'FACE_MODEL_INTEGRITY': '电脑人脸模型校验失败，请按后端说明重新准备模型',
            'FACE_MODEL_RUNTIME': '电脑人脸识别环境不可用，请检查后端配置',
            'FACE_SAMPLE_LIMIT': '该成员照片数量已达上限，请先清除旧人脸资料',
            'FACE_RECOGNITION_DISABLED': '电脑尚未启用人脸识别，请在后端配置后重试',
            'FACE_MODEL_MISSING': '电脑尚未准备人脸模型，请按后端说明配置',
          };
          throw ApiException(errors[code] ?? '成员操作未成功，请检查照片、后端配置或稍后重试');
        }
        if (bytes.isEmpty) return <String, dynamic>{};
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) throw const FormatException();
        return result;
      })().timeout(const Duration(seconds: 30));
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('成员服务响应超时，请保持电脑后端运行后重试');
    } catch (_) {
      throw const ApiException('暂时无法连接成员服务，请检查电脑后端与网络');
    }
  }

  Future<List<MemberProfile>> members() async {
    final result = await request('GET', '/api/household/members');
    if (result['members'] is! List) throw const ApiException('成员服务版本不兼容');
    return (result['members'] as List)
        .map((m) => MemberProfile.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  String path(String id) => '/api/household/members/${Uri.encodeComponent(id)}';
  Future<MemberProfile> save(MemberProfile member) async {
    final result = await request('PUT', path(member.id), json: member.toJson());
    return MemberProfile.fromJson(Map<String, dynamic>.from(result['member']));
  }

  Future<void> delete(MemberProfile member) async {
    await request('DELETE', '${path(member.id)}?revision=${member.revision}');
  }

  Future<Map<String, dynamic>> status() => request('GET', '/api/faces/status');
  Future<void> enroll(
    MemberProfile member,
    Uint8List image, {
    required bool consent,
  }) async {
    if (!consent) throw const ApiException('请先取得成员同意再录入人脸');
    final png =
        image.length >= 8 &&
        image[0] == 137 &&
        image[1] == 80 &&
        image[2] == 78 &&
        image[3] == 71;
    final jpeg =
        image.length >= 3 &&
        image[0] == 255 &&
        image[1] == 216 &&
        image[2] == 255;
    if (!png && !jpeg) throw const ApiException('请选择 JPEG 或 PNG 照片');
    final query = Uri(
      queryParameters: {'name': member.displayName, 'consent': 'true'},
    ).query;
    await request(
      'POST',
      '/api/faces/members/${Uri.encodeComponent(member.id)}/samples?$query',
      image: image,
      imageType: png ? 'image/png' : 'image/jpeg',
    );
  }

  Future<void> clearFaces(String id) async {
    await request(
      'DELETE',
      '/api/faces/members/${Uri.encodeComponent(id)}/samples',
    );
  }

  void close() => _client.close();
}
