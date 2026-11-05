import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'app_controller.dart';
import 'services/push_service.dart';
import 'services/settings_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'VideoLAN LibVLC / FFmpeg native video',
    ], await rootBundle.loadString('assets/licenses/native-video.txt'));
  });
  late final SafetyController controller;
  controller = SafetyController(
    store: SecureSettingsStore(),
    gateway: useFirebase
        ? FirebasePushGateway(currentScope: () => controller.notificationScope)
        : null,
  );
  runApp(ElderSafetyApp(controller: controller));
}
