import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/household.dart';
import '../models/camera_connection.dart';
import 'object_api.dart';
import 'api.dart';

class UploadCancellation {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class MediaApi extends ObjectApi {
  MediaApi(ObjectServiceConfig config, {http.Client? client})
    : super(config, client: client);
  String videoPath(String id) => '/api/videos/${Uri.encodeComponent(id)}';
  Future<Map<String, dynamic>> health() => getJson('/api/health');
  Future<Map<String, dynamic>> video(String id) => getJson(videoPath(id));
  Future<Map<String, dynamic>> analysisPlan(String id, String mode) =>
      getJson('${videoPath(id)}/analysis-plan?mode=$mode');
  Future<Map<String, dynamic>> analyze(String id, String mode) {
    if (!{'safety', 'objects', 'all'}.contains(mode))
      throw const ApiException('分析模式无效');
    return postJson('${videoPath(id)}/analyze?mode=$mode');
  }

  Future<Map<String, dynamic>> resume(String id) =>
      postJson('${videoPath(id)}/resume');
  Future<Map<String, dynamic>> pause(String id) =>
      postJson('${videoPath(id)}/pause');
  Future<Map<String, dynamic>> job(String id) =>
      getJson('/api/jobs/${Uri.encodeComponent(id)}');
  Future<void> deleteRecording(String id) async {
    await postJson('${videoPath(id)}/delete');
  }

  Future<Map<String, dynamic>> cameraStatus() =>
      getJson('/api/monitoring/camera');
  Future<Map<String, dynamic>> connectCamera(CameraConnection camera) {
    if (camera.validationError != null) {
      throw ApiException(camera.validationError!);
    }
    return postJson('/api/monitoring/camera', camera.toJson());
  }

  Future<Map<String, dynamic>> cameraCommand(String action) {
    if (!{'start', 'stop'}.contains(action))
      throw const ApiException('摄像头操作无效');
    return postJson('/api/monitoring/camera/$action');
  }

  /// Bounded chunks match the original web backend; no whole-video RAM buffering.
  Future<String> uploadVideo(
    File file,
    String filename, {
    required UploadCancellation cancellation,
    required void Function(int sent, int total) onProgress,
  }) async {
    final total = await file.length();
    if (total <= 0 || !filename.toLowerCase().endsWith('.mp4'))
      throw const ApiException('请选择有效的 MP4 视频');
    String? uploadId;
    RandomAccessFile? input;
    bool completed = false;
    try {
      if (cancellation.cancelled) throw const ApiException('上传已取消');
      final session = await postJson('/api/uploads', {
        'filename': filename.length > 150
            ? '${filename.substring(0, 146)}.mp4'
            : filename,
        'size': total,
      });
      uploadId = session['upload_id']?.toString();
      final chunkSize = (session['chunk_bytes'] as num?)?.toInt() ?? 0;
      if (uploadId == null ||
          uploadId.isEmpty ||
          chunkSize < 1 ||
          chunkSize > 16 * 1024 * 1024)
        throw const ApiException('服务返回的上传参数无效');
      input = await file.open();
      var offset = 0;
      onProgress(0, total);
      while (offset < total) {
        if (cancellation.cancelled) throw const ApiException('上传已取消');
        final bytes = await input.read(chunkSize);
        if (bytes.isEmpty) throw const ApiException('读取视频失败，文件可能已被移动');
        final result = await postBytes(
          '/api/uploads/${Uri.encodeComponent(uploadId)}/chunks?offset=$offset',
          bytes,
        );
        final received = (result['received'] as num?)?.toInt();
        if (received != offset + bytes.length)
          throw const ApiException('服务端接收进度不一致，请重新上传');
        offset = received!;
        onProgress(offset, total);
      }
      if (cancellation.cancelled) throw const ApiException('上传已取消');
      final result = await postJson(
        '/api/uploads/${Uri.encodeComponent(uploadId)}/complete',
      );
      final videoId = result['video_id']?.toString();
      if (videoId == null || videoId.isEmpty)
        throw const ApiException('视频已上传，但服务未返回录像编号，请刷新录像库');
      completed = true;
      return videoId;
    } finally {
      await input?.close();
      if (uploadId != null && !completed) {
        try {
          await postJson(
            '/api/uploads/${Uri.encodeComponent(uploadId)}/cancel',
          );
        } catch (_) {}
      }
    }
  }
}
