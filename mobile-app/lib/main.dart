import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ui/account_entry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'VideoLAN LibVLC / FFmpeg native video',
    ], await rootBundle.loadString('assets/licenses/native-video.txt'));
  });
  runApp(const AccountEntry());
}
