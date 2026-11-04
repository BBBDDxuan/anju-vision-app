import 'package:firebase_core/firebase_core.dart';

// Default builds never call this bridge and never import firebase_options.dart.
// Opt-in builds use native Android/iOS Firebase configuration, prepared locally
// with FlutterFire CLI. Missing native configuration becomes a recoverable push
// initialization error; the app continues to use foreground polling.
Future<FirebaseApp> initializeConfiguredFirebase() => Firebase.initializeApp();
