import 'backend_tls.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'settings_store.dart';

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.name,
    required this.code,
    required this.packageName,
    required this.abis,
  });
  final String name, packageName;
  final int code;
  final List<String> abis;
  factory InstalledAppVersion.fromJson(Map<dynamic, dynamic> data) {
    final name = data['version_name'],
        code = data['version_code'],
        package = data['package_name'],
        abis = data['abis'];
    if (name is! String ||
        code is! int ||
        code < 1 ||
        package is! String ||
        abis is! List ||
        abis.isEmpty ||
        abis.any((a) => a is! String))
      throw const FormatException('Invalid installed version');
    return InstalledAppVersion(
      name: name,
      code: code,
      packageName: package,
      abis: abis.cast<String>(),
    );
  }
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.name,
    required this.code,
    required this.abi,
    required this.packageName,
    required this.bytes,
    required this.sha256,
    required this.downloadPath,
    required this.notes,
  });
  final String name, abi, packageName, sha256, downloadPath, notes;
  final int code, bytes;
  factory AppUpdateRelease.fromJson(
    Map<String, dynamic> data,
    InstalledAppVersion installed,
  ) {
    final name = data['version_name'],
        code = data['version_code'],
        abi = data['abi'],
        package = data['package_name'],
        bytes = data['size_bytes'],
        sha = data['sha256'],
        path = data['download_path'],
        notes = data['notes'];
    if (name is! String ||
        name.isEmpty ||
        name.length > 100 ||
        code is! int ||
        code <= installed.code ||
        abi is! String ||
        !installed.abis.contains(abi) ||
        package != installed.packageName ||
        bytes is! int ||
        bytes < 1 ||
        bytes > 256 * 1024 * 1024 ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        path != '/api/app/apk/$sha' ||
        notes is! String ||
        notes.length > 10000)
      throw const FormatException('Invalid update manifest');
    return AppUpdateRelease(
      name: name,
      code: code,
      abi: abi,
      packageName: package as String,
      bytes: bytes,
      sha256: sha,
      downloadPath: path as String,
      notes: notes,
    );
  }
  Map<String, Object> toJson() => {
    'version_name': name,
    'version_code': code,
    'abi': abi,
    'package_name': packageName,
    'size_bytes': bytes,
    'sha256': sha256,
    'download_path': downloadPath,
    'notes': notes,
  };
}

abstract interface class AppUpdateGateway {
  Future<InstalledAppVersion> info();
  void onProgress(
    void Function(String digest, int received, int total)? callback,
  );
  Future<void> download(AppUpdateRelease release, String baseUrl, String token);
  Future<String> install();
  Future<void> cancel();
  Future<void> discard();
  void dispose();
}

class AndroidAppUpdateGateway implements AppUpdateGateway {
  AndroidAppUpdateGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('elder_safety/app_updates');
  final MethodChannel _channel;
  @override
  Future<InstalledAppVersion> info() async => InstalledAppVersion.fromJson(
    (await _channel.invokeMapMethod<dynamic, dynamic>('info'))!,
  );
  @override
  void onProgress(void Function(String, int, int)? callback) {
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method != 'downloadProgress' || call.arguments is! Map)
                return;
              final data = call.arguments as Map;
              if (data['sha256'] is String &&
                  data['received'] is int &&
                  data['total'] is int)
                callback(
                  data['sha256'] as String,
                  data['received'] as int,
                  data['total'] as int,
                );
            },
    );
  }

  @override
  Future<void> download(
    AppUpdateRelease release,
    String baseUrl,
    String token,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('download', {
      ...release.toJson(),
      'base_url': baseUrl,
      'bearer_token': token,
    });
    if (result?['ready'] != true)
      throw const FormatException('Download not verified');
  }

  @override
  Future<String> install() async =>
      (await _channel.invokeMapMethod<String, dynamic>('install'))?['status']
          as String? ??
      'failed';
  @override
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }

  @override
  Future<void> discard() async {
    await _channel.invokeMethod<void>('discard');
  }

  @override
  void dispose() => onProgress(null);
}

enum AppUpdatePhase {
  idle,
  checking,
  downloading,
  ready,
  upToDate,
  unavailable,
  failed,
  permissionRequired,
  installerOpened,
  unsupported,
}

/// One updater per App. A changed backend/token invalidates in-flight work.
class AppUpdateManager extends ChangeNotifier {
  AppUpdateManager({
    AppUpdateGateway? gateway,
    http.Client Function()? clientFactory,
    DateTime Function()? clock,
  }) : _gateway = gateway ?? AndroidAppUpdateGateway(),
       _clientFactory = clientFactory,
       _clock = clock ?? DateTime.now {
    _gateway.onProgress((digest, received, total) {
      if (_disposed ||
          phase != AppUpdatePhase.downloading ||
          release?.sha256 != digest ||
          total != release?.bytes)
        return;
      downloadedBytes = received.clamp(0, total);
      _notify();
    });
  }
  final AppUpdateGateway _gateway;
  final http.Client Function()? _clientFactory;
  final DateTime Function() _clock;
  InstalledAppVersion? installed;
  AppUpdateRelease? release;
  AppUpdatePhase phase = AppUpdatePhase.idle;
  String message = '连接电脑后自动检查并下载新版';
  int downloadedBytes = 0;
  int _generation = 0;
  bool _disposed = false;
  bool installing = false;
  String? _baseUrl, _token;
  http.Client? _activeClient;
  DateTime? _lastCheck;
  Future<void>? _initializing;
  Future<void> _connectionReady = Future.value();
  bool get busy =>
      phase == AppUpdatePhase.checking || phase == AppUpdatePhase.downloading;
  bool get ready => [
    AppUpdatePhase.ready,
    AppUpdatePhase.permissionRequired,
    AppUpdatePhase.installerOpened,
  ].contains(phase);
  bool get connected => _baseUrl != null;

  Future<void> initialize() => _initializing ??= _loadInstalled();
  Future<void> _loadInstalled() async {
    try {
      installed = await _gateway.info();
    } catch (_) {
      if (!_disposed) {
        phase = AppUpdatePhase.unsupported;
        message = '当前平台不支持 APK 更新';
      }
    }
    _notify();
  }

  void configure(AppSettings? settings) {
    final valid =
        settings != null &&
        settings.validationError == null &&
        settings.bearerToken.trim().isNotEmpty;
    final base = valid
        ? settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')
        : null;
    final token = valid ? settings.bearerToken.trim() : null;
    if (_baseUrl == base && _token == token) return;
    _baseUrl = base;
    _token = token;
    final generation = ++_generation;
    _activeClient?.close();
    _activeClient = null;
    installing = false;
    _lastCheck = null;
    release = null;
    downloadedBytes = 0;
    phase = AppUpdatePhase.idle;
    message = valid ? '连接电脑后自动检查并下载新版' : '请先配置电脑后端地址与访问令牌';
    _notify();
    _connectionReady = _connectionReady.then((_) async {
      try {
        await _gateway.cancel();
        await _gateway.discard();
      } catch (_) {}
    });
    unawaited(
      _connectionReady.then((_) async {
        if (!_disposed && generation == _generation && valid) await check();
      }),
    );
  }

  Future<Map<String, dynamic>> _manifest(
    http.Client client,
    Uri uri,
    String token,
  ) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw const FormatException('Update server unavailable');
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 128 * 1024)
        throw const FormatException('Manifest too large');
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (result is! Map<String, dynamic> || result['available'] is! bool)
      throw const FormatException('Invalid version response');
    return result;
  }

  Future<void> check({bool force = false}) async {
    await _connectionReady;
    await initialize();
    if (_disposed || installed == null || busy || installing) return;
    final base = _baseUrl, token = _token;
    if (base == null || token == null) {
      message = '请先配置电脑后端地址与访问令牌';
      _notify();
      return;
    }
    if (!force &&
        _lastCheck != null &&
        _clock().difference(_lastCheck!) < const Duration(minutes: 30))
      return;
    final generation = ++_generation;
    _lastCheck = _clock();
    final previous = ready ? release : null;
    var previousValid = previous != null;
    phase = AppUpdatePhase.checking;
    message = '正在向电脑检查新版本';
    _notify();
    final client = _clientFactory?.call() ?? backendClient(base);
    _activeClient = client;
    try {
      final uri = Uri.parse('$base/api/app/version').replace(
        queryParameters: {
          'version_code': installed!.code.toString(),
          'abi': installed!.abis.first,
        },
      );
      final data = await _manifest(client, uri, token);
      if (_disposed || generation != _generation) return;
      if (data['available'] == false) {
        release = null;
        phase = AppUpdatePhase.upToDate;
        message = '电脑上当前没有可用的新版本';
        return;
      }
      if (data['update'] is! Map<String, dynamic>)
        throw const FormatException('Missing release');
      final candidate = AppUpdateRelease.fromJson(
        data['update'] as Map<String, dynamic>,
        installed!,
      );
      release = candidate;
      final cachedMatches =
          previous?.sha256 == candidate.sha256 &&
          previous?.code == candidate.code &&
          previous?.bytes == candidate.bytes &&
          previous?.abi == candidate.abi &&
          previous?.name == candidate.name;
      if (!cachedMatches) {
        previousValid = false;
        phase = AppUpdatePhase.downloading;
        downloadedBytes = 0;
        message = '发现 ' + candidate.name + '，正在自动下载';
        _notify();
        await _gateway.download(candidate, base, token);
        if (_disposed || generation != _generation) return;
      }
      downloadedBytes = candidate.bytes;
      phase = AppUpdatePhase.ready;
      message = '新版已下载并校验，点击安装';
    } catch (_) {
      if (!_disposed && generation == _generation) {
        release = previousValid ? previous : null;
        phase = previousValid
            ? AppUpdatePhase.ready
            : AppUpdatePhase.unavailable;
        message = previousValid ? '已保留下载好的新版，可继续安装' : '更新检查或下载暂不可用，请连接电脑后重试';
      }
    } finally {
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
      if (!_disposed && generation == _generation) _notify();
    }
  }

  Future<void> cancel() async {
    final generation = ++_generation;
    _activeClient?.close();
    _activeClient = null;
    try {
      await _gateway.cancel();
    } catch (_) {}
    if (_disposed || generation != _generation) return;
    release = null;
    downloadedBytes = 0;
    phase = AppUpdatePhase.idle;
    message = '已取消更新，可手动重新检查';
    _notify();
  }

  Future<void> install() async {
    if (!ready || release == null || _disposed || installing) return;
    final generation = _generation;
    installing = true;
    _notify();
    try {
      final status = await _gateway.install();
      if (_disposed || generation != _generation) return;
      if (status == 'permission_required') {
        phase = AppUpdatePhase.permissionRequired;
        message = '请允许此应用安装更新，返回后再次点击安装';
      } else if (status == 'installer_opened') {
        phase = AppUpdatePhase.installerOpened;
        message = '请在系统安装界面确认；取消后可再次点击安装';
      } else {
        throw const FormatException('Install unavailable');
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      phase = AppUpdatePhase.failed;
      message = '安装包未通过检查或无法打开安装界面，请重新检查更新';
      release = null;
    } finally {
      if (!_disposed && generation == _generation) {
        installing = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _activeClient?.close();
    unawaited(_gateway.cancel().catchError((_) {}));
    _gateway.dispose();
    super.dispose();
  }
}
