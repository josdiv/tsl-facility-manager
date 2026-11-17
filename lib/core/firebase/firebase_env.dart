import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Build-time Firebase settings, passed with --dart-define.
///
///   flutter run --dart-define=USE_EMULATORS=true
///
/// The app's data lives in its own Firestore database, separate from the
/// `(default)` database the admin dashboard has been prototyping in.
abstract final class FirebaseEnv {
  /// Talk to the Firebase emulators on the development machine instead of the
  /// live project. On a USB-connected Android phone, run
  /// `adb reverse tcp:<port> tcp:<port>` for each emulator port first.
  static const useEmulators = bool.fromEnvironment('USE_EMULATORS');

  static const emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  static const databaseId = String.fromEnvironment(
    'FIRESTORE_DATABASE',
    defaultValue: 'tsl-app',
  );

  /// Cloud Functions region. Same as the Firestore location's main region.
  static const functionsRegion = 'europe-west1';

  static const authPort = 9099;
  static const firestorePort = 8080;
  static const storagePort = 9199;
  static const functionsPort = 5001;
}

/// The app's Firestore database.
FirebaseFirestore appFirestore() => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: FirebaseEnv.databaseId,
);

FirebaseFunctions appFunctions() =>
    FirebaseFunctions.instanceFor(region: FirebaseEnv.functionsRegion);

/// Points every Firebase service at the local emulators when
/// [FirebaseEnv.useEmulators] is set. Call once, right after
/// `Firebase.initializeApp`.
Future<void> connectEmulatorsIfEnabled() async {
  if (!FirebaseEnv.useEmulators) return;
  const host = FirebaseEnv.emulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(host, FirebaseEnv.authPort);
  appFirestore().useFirestoreEmulator(host, FirebaseEnv.firestorePort);
  await FirebaseStorage.instance.useStorageEmulator(
    host,
    FirebaseEnv.storagePort,
  );
  appFunctions().useFunctionsEmulator(host, FirebaseEnv.functionsPort);
}
