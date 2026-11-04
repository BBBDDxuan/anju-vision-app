import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../models/household.dart';
import '../services/workspace_proxy.dart';
import 'widgets.dart';

/// The original workspace supplies advanced timeline/review/region tools too.
/// Authentication becomes an HttpOnly same-origin session in the LAN adapter.
class WebWorkspaceScreen extends StatefulWidget {
  const WebWorkspaceScreen({super.key, required this.config});
  final ObjectServiceConfig config;
  @override
  State<WebWorkspaceScreen> createState() => _WebWorkspaceScreenState();
}

class _WebWorkspaceScreenState extends State<WebWorkspaceScreen> {
  WebViewController? _web;
  String? _error;
  int _progress = 0;
  WorkspaceProxy? _proxy;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final proxy = WorkspaceProxy(widget.config);
      _proxy = proxy;
      final entry = await proxy.start();
      final root = entry;
      final web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xfff5f8f7))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (value) {
              if (mounted) setState(() => _progress = value);
            },
            onPageStarted: (_) {
              if (mounted) setState(() => _error = null);
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame == true)
                setState(() => _error = '工作台暂不可用，请检查服务地址、访问令牌和网络。');
            },
            onNavigationRequest: (request) {
              final target = Uri.tryParse(request.url);
              return target != null &&
                      target.scheme == root.scheme &&
                      target.host == root.host &&
                      target.port == root.port
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
          ),
        );
      if (web.platform is AndroidWebViewController) {
        final android = web.platform as AndroidWebViewController;
        await android.setMediaPlaybackRequiresUserGesture(false);
        await android.setOnShowFileSelector((params) async {
          final file = await FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: ['mp4'],
          );
          final path = file?.path;
          return path == null ? <String>[] : [File(path).uri.toString()];
        });
      }
      if (!mounted) return;
      setState(() => _web = web);
      await web.loadRequest(entry);
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开完整工作台，请检查服务连接。');
    }
  }

  @override
  void dispose() {
    _proxy?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('完整工作台'),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: () => _web?.reload(),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '工作台内返回',
          onPressed: () async {
            if (await _web?.canGoBack() == true) await _web?.goBack();
          },
          icon: const Icon(Icons.undo),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: InfoBanner(_error!, error: true),
            ),
          Expanded(
            child: _web == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _web!),
          ),
        ],
      ),
    ),
  );
}
