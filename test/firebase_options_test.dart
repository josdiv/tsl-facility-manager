import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsl_facility_manager/firebase_options.dart';

void main() {
  const project = 'tsl-facility-manager';
  const bundleId = 'com.dawnglobalict.tslfacilitymanager';

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android uses the TSL Facility Manager project and Android app', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final options = DefaultFirebaseOptions.currentPlatform;
    expect(options.projectId, project);
    expect(options.appId, contains(':android:'));
  });

  test('iOS uses the same project and the app bundle id', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final options = DefaultFirebaseOptions.currentPlatform;
    expect(options.projectId, project);
    expect(options.appId, contains(':ios:'));
    expect(options.iosBundleId, bundleId);
  });

  test('both platforms share one storage bucket', () {
    expect(DefaultFirebaseOptions.android.storageBucket, isNotEmpty);
    expect(
      DefaultFirebaseOptions.android.storageBucket,
      DefaultFirebaseOptions.ios.storageBucket,
    );
  });

  test('platforms the app does not target are refused', () {
    // The admin portal is another team's web app, so web stays unconfigured.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      () => DefaultFirebaseOptions.currentPlatform,
      throwsUnsupportedError,
    );
  });
}
