# Releasing the Android app

## 1. Create the upload key (once)

The upload key signs every build sent to Google Play. Create it once, keep
it out of git, and back up both the file and its passwords somewhere safe
(a password manager). With Play App Signing turned on, Google can reset a
lost upload key, but it takes days.

```bash
keytool -genkey -v \
  -keystore ~/keys/tsl-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Then create `android/key.properties` (already ignored by git):

```properties
storeFile=/Users/<you>/keys/tsl-upload.jks
storePassword=<store password>
keyAlias=upload
keyPassword=<key password>
```

Without this file, release builds fall back to the debug key, which Google
Play rejects.

## 2. Check the live project is ready

Release builds talk to the live `tsl-facility-manager` project and its
`tsl-app` database, so these must be in place first: billing (Blaze), the
`tsl-app` database with `firestore.rules` and `firestore.indexes.json`
deployed, Authentication, Cloud Storage with `storage.rules`, and the Cloud
Functions. Test accounts and the sample data are not shown in release
builds.

## 3. Set the version

In `pubspec.yaml`, raise `version: <name>+<build>`. The build number must go
up for every upload.

## 4. Build

```bash
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` to the Play
Console.

## Other build modes

| Build | Command |
| --- | --- |
| Against the local emulators | `tool/emulators.sh`, then `flutter run --dart-define=USE_EMULATORS=true` |
| Sample data, no backend | `flutter run --dart-define=SAMPLE_DATA=true` |
