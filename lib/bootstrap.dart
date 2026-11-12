import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'core/di/injection.dart';
import 'firebase_options.dart';

typedef FirebaseInitializer = Future<void> Function();

Future<void> initializeFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Prepares everything the app needs before the first frame. Firebase starts
/// first, so dependencies registered afterwards can use it.
Future<void> bootstrap({
  FirebaseInitializer firebase = initializeFirebase,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await firebase();
  configureDependencies();
}
