import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_updates.dart';
import 'widgets.dart';

class AppUpdateScreen extends StatelessWidget {
  const AppUpdateScreen({super.key, required this.updates});
  final AppUpdateManager updates;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('软件更新')),
    body: ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final installed = updates.installed, release = updates.release;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '安居视界',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    installed == null
                        ? '正在读取已安装版本'
                        : '当前版本：' +
                              installed.name +
                              '（' +
                              installed.code.toString() +
                              '）',
                  ),
                  const SizedBox(height: 12),
                  Text(updates.message),
                  if (updates.phase == AppUpdatePhase.checking) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (updates.phase == AppUpdatePhase.downloading &&
                      release != null) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: updates.downloadedBytes / release.bytes,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (updates.downloadedBytes / 1048576).toStringAsFixed(1) +
                          ' / ' +
                          (release.bytes / 1048576).toStringAsFixed(1) +
                          ' MB',
                    ),
                  ],
                ],
              ),
            ),
            if (release != null) ...[
              const SizedBox(height: 16),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '新版本：' + release.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '安装包 ' +
                          (release.bytes / 1048576).toStringAsFixed(1) +
                          ' MB',
                    ),
                    if (release.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(release.notes),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (updates.ready)
              FilledButton.icon(
                onPressed: updates.installing
                    ? null
                    : () => unawaited(updates.install()),
                icon: const Icon(Icons.install_mobile),
                label: Text(updates.installing ? '正在检查安装包' : '安装新版'),
              ),
            if (updates.busy)
              OutlinedButton(
                onPressed: () => unawaited(updates.cancel()),
                child: const Text('取消更新'),
              )
            else
              OutlinedButton.icon(
                onPressed: updates.installing
                    ? null
                    : () => unawaited(updates.check(force: true)),
                icon: const Icon(Icons.refresh),
                label: const Text('检查更新'),
              ),
            const SizedBox(height: 12),
            const Text(
              '连接电脑后会自动检查并下载新版。电脑后端需要保持运行；连接失败不影响继续使用当前版本。安装时请按系统提示确认。',
              style: TextStyle(color: Anju.muted),
            ),
          ],
        );
      },
    ),
  );
}
