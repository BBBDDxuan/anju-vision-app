class CameraConnection {
  const CameraConnection({
    this.host = '',
    this.port = 554,
    this.username = 'admin',
    this.password = '',
    this.path = 'stream1',
  });
  final String host, username, password, path;
  final int port;
  String? get validationError {
    final parts = host.trim().split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255))
      return '请填写摄像头的局域网 IPv4 地址';
    final a = parts.cast<int>();
    if (!(a[0] == 10 ||
        (a[0] == 192 && a[1] == 168) ||
        (a[0] == 172 && a[1] >= 16 && a[1] <= 31)))
      return '摄像头须使用同一局域网的私有 IP 地址';
    if (port < 1 || port > 65535) return '端口应为 1–65535';
    if (username.trim().isEmpty ||
        username.length > 64 ||
        password.trim().isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(username + password) ||
        password.length > 256)
      return '请填写摄像头本地用户名和密码';
    if (path.replaceFirst(RegExp(r'^/+'), '').isEmpty ||
        path.length > 256 ||
        path.contains('://') ||
        RegExp(r'[\s#\\\x00-\x1f\x7f]').hasMatch(path) ||
        path.contains('..'))
      return '视频路径不正确';
    return null;
  }

  Uri get streamUri => Uri.parse(
    'rtsp://${Uri.encodeComponent(username.trim())}:${Uri.encodeComponent(password)}@${host.trim()}:$port/${path.replaceFirst(RegExp(r"^/+"), "")}',
  );
  Map<String, dynamic> toJson() => {
    'host': host.trim(),
    'port': port,
    'username': username.trim(),
    'password': password,
    'path': path,
  };
  factory CameraConnection.fromJson(Map<String, dynamic> j) => CameraConnection(
    host: j['host']?.toString() ?? '',
    port: (j['port'] as num?)?.toInt() ?? 554,
    username: j['username']?.toString() ?? 'admin',
    password: j['password']?.toString() ?? '',
    path: j['path']?.toString() ?? 'stream1',
  );
}
