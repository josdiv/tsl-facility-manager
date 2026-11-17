import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/di/injection.dart';
import 'core/firebase/firebase_env.dart';
import 'features/notifications/domain/notifications.dart';
import 'firebase_options.dart';

typedef FirebaseInitializer = Future<void> Function();

Future<void> initializeFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await connectEmulatorsIfEnabled();
}

/// Sets up push display and taps. Failing to do so never stops the app.
Future<void> initializePush() async {
  try {
    await sl<PushService>().initialize();
  } on Object catch (e) {
    debugPrint('Push notifications unavailable: $e');
  }
}

/// Prepares everything the app needs before the first frame. Firebase starts
/// first, so dependencies registered afterwards can use it.
Future<void> bootstrap({
  FirebaseInitializer firebase = initializeFirebase,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app is designed for phones held upright.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await firebase();
  configureDependencies(useFirebase: !FirebaseEnv.useSampleData);
  if (!FirebaseEnv.useSampleData) await initializePush();
}
