import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:elder_safety_mobile/ui/app_update_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/services/app_updates.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';

const digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const installed = InstalledAppVersion(
  name: '1.2.3',
  code: 8008,
  packageName: 'com.eldersafety.elder_safety_mobile',
  abis: ['x86_64'],
);
const settings = AppSettings(
  baseUrl: 'http://192.168.1.10:8000',
  bearerToken: 'test-local-access-token',
);
Map<String, dynamic> manifest({Map<String, dynamic> change = const {}}) => {
  'available': true,
  'update': {
    'version_name': '1.2.4',
    'version_code': 8009,
    'abi': 'x86_64',
    'package_name': installed.packageName,
    'size_bytes': 12345,
    'sha256': digest,
    'download_path': '/api/app/apk/$digest',
    'notes': '修复和更新',
    ...change,
  },
};

http.Response jsonResponse(Map<String, dynamic> data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Gateway implements AppUpdateGateway {
  void Function(String, int, int)? progress;
  int downloads = 0, installs = 0;
  String installStatus = 'installer_opened';
  String? downloadOrigin, downloadToken;
  Completer<void>? blockedDownload;
  @override
  Future<InstalledAppVersion> info() async => installed;
  @override
  void onProgress(void Function(String, int, int)? callback) =>
      progress = callback;
  @override
  Future<void> download(
    AppUpdateRelease release,
    String baseUrl,
    String token,
  ) async {
    downloads++;
    downloadOrigin = baseUrl;
    downloadToken = token;
    progress?.call(release.sha256, 100, release.bytes);
    await blockedDownload?.future;
  }

  @override
  Future<String> install() async {
    installs++;
    return installStatus;
  }

  @override
  Future<void> cancel() async {
    if (downloads > 0 &&
        blockedDownload != null &&
        !blockedDownload!.isCompleted)
      blockedDownload!.complete();
  }

  @override
  Future<void> discard() async {}
  @override
  void dispose() {}
}

Future<void> waitFor(bool Function() done) async {
  for (var n = 0; n < 100; n++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Updater did not reach expected state');
}

void main() {
  test(
    'automatic check uses real ABI version and token, downloads but does not install',
    () async {
      final gateway = Gateway();
      final requests = <http.Request>[];
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return jsonResponse(manifest());
        }),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.ready);
      expect(requests.single.url.queryParameters, {
        'version_code': '8008',
        'abi': 'x86_64',
      });
      expect(
        requests.single.headers['Authorization'],
        'Bearer test-local-access-token',
      );
      expect(requests.single.followRedirects, isFalse);
      expect(gateway.downloads, 1);
      expect(gateway.installs, 0);
      expect(gateway.downloadOrigin, settings.baseUrl);
      expect(gateway.downloadToken, settings.bearerToken);
      expect(manager.release!.code, 8009);
      expect(manager.downloadedBytes, 12345);
      await manager.check();
      await manager.check(force: true);
      expect(
        gateway.downloads,
        1,
        reason: 'Already verified identical APK is reused',
      );
      await manager.install();
      expect(gateway.installs, 1);
      expect(manager.phase, AppUpdatePhase.installerOpened);
    },
  );

  test(
    'no published/new version does not download and cannot be called latest',
    () async {
      final gateway = Gateway();
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient(
          (_) async => http.Response('{"available":false,"update":null}', 200),
        ),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.phase == AppUpdatePhase.upToDate);
      expect(manager.message, '电脑上当前没有可用的新版本');
      expect(gateway.downloads, 0);
    },
  );

  for (final bad in <Map<String, dynamic>>[
    {'version_code': 8008},
    {'version_code': 5009},
    {'package_name': 'attacker.package'},
    {'abi': 'arm64-v8a'},
    {'download_path': 'https://other.invalid/package.apk'},
    {'download_path': '/api/app/apk/../../private'},
    {'sha256': 'invalid'},
    {'size_bytes': 300 * 1024 * 1024},
    {'size_bytes': 0},
  ]) {
    test(
      'invalid manifest is rejected before native download: ' +
          bad.keys.first +
          '=' +
          bad.values.first.toString(),
      () async {
        final gateway = Gateway();
        final manager = AppUpdateManager(
          gateway: gateway,
          clientFactory: () =>
              MockClient((_) async => jsonResponse(manifest(change: bad))),
        );
        addTearDown(manager.dispose);
        manager.configure(settings);
        await waitFor(() => manager.phase == AppUpdatePhase.unavailable);
        expect(gateway.downloads, 0);
        expect(manager.release, isNull);
      },
    );
  }

  test(
    'backend failure is non-blocking, throttled automatically, manual retry succeeds',
    () async {
      final gateway = Gateway();
      var count = 0;
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient(
          (_) async => ++count == 1
              ? http.Response('private server details', 401)
              : jsonResponse(manifest()),
        ),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.phase == AppUpdatePhase.unavailable);
      expect(manager.message, isNot(contains('private server details')));
      await manager.check();
      expect(count, 1);
      await manager.check(force: true);
      expect(manager.ready, isTrue);
      expect(count, 2);
    },
  );

  test(
    'switching backend discards a slow previous response and uses new token only',
    () async {
      final gateway = Gateway(), slow = Completer<http.Response>();
      final requests = <http.Request>[];
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return request.url.host == '192.168.1.10'
              ? slow.future
              : http.Response('{"available":false,"update":null}', 200);
        }),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => requests.isNotEmpty);
      manager.configure(
        const AppSettings(
          baseUrl: 'http://192.168.1.11:8000',
          bearerToken: 'other-token',
        ),
      );
      await waitFor(() => manager.phase == AppUpdatePhase.upToDate);
      slow.complete(jsonResponse(manifest()));
      await Future<void>.delayed(Duration.zero);
      expect(gateway.downloads, 0);
      expect(manager.release, isNull);
      expect(requests.last.headers['Authorization'], 'Bearer other-token');
    },
  );

  test(
    'cancelling or switching during download cannot publish stale ready state',
    () async {
      final gateway = Gateway()..blockedDownload = Completer<void>();
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((_) async => jsonResponse(manifest())),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.phase == AppUpdatePhase.downloading);
      await manager.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(manager.phase, AppUpdatePhase.idle);
      expect(manager.release, isNull);
      expect(gateway.installs, 0);
    },
  );

  test(
    'install permission returns to ready flow; no silent installation',
    () async {
      final gateway = Gateway()..installStatus = 'permission_required';
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((_) async => jsonResponse(manifest())),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.ready);
      await manager.install();
      expect(manager.phase, AppUpdatePhase.permissionRequired);
      expect(manager.ready, isTrue);
      gateway.installStatus = 'installer_opened';
      await manager.install();
      expect(manager.phase, AppUpdatePhase.installerOpened);
    },
  );

  test(
    'native signature or hash failure cannot expose an install action',
    () async {
      final gateway = BadGateway();
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((_) async => jsonResponse(manifest())),
      );
      addTearDown(manager.dispose);
      manager.configure(settings);
      await waitFor(() => manager.phase == AppUpdatePhase.unavailable);
      expect(manager.ready, isFalse);
      await manager.install();
      expect(gateway.installs, 0);
    },
  );
  testWidgets(
    'update page displays downloaded release and asks system permission on user tap',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = Gateway()..installStatus = 'permission_required';
      final manager = AppUpdateManager(
        gateway: gateway,
        clientFactory: () => MockClient((_) async => jsonResponse(manifest())),
      );
      addTearDown(manager.dispose);
      await tester.runAsync(() async {
        manager.configure(settings);
        await waitFor(() => manager.ready);
      });
      await tester.pumpWidget(
        MaterialApp(home: AppUpdateScreen(updates: manager)),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前版本：1.2.3（8008）'), findsOneWidget);
      expect(find.text('新版本：1.2.4'), findsOneWidget);
      expect(gateway.installs, 0);
      await tester.ensureVisible(find.text('安装新版'));
      await tester.tap(find.text('安装新版'));
      await tester.pumpAndSettle();
      expect(gateway.installs, 1);
      expect(find.text('请允许此应用安装更新，返回后再次点击安装'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class BadGateway extends Gateway {
  @override
  Future<void> download(
    AppUpdateRelease release,
    String baseUrl,
    String token,
  ) async => throw PlatformException(code: 'SIGNATURE_MISMATCH');
}
