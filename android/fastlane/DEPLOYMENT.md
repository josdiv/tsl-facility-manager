# TSL Facility Manager Android: Google Play runbook

Same approach as SpotLat (android/fastlane there).

- Package: `com.dawnglobalict.tslfacilitymanager`
- Upload key: `android/app/upload-keystore.jks`, alias `upload`, passwords in
  `android/key.properties`. Both are git-ignored. Created 26 Nov 2026,
  SHA-1 `C3:D9:B3:7F:F3:C2:C0:79:8E:AE:8B:CE:90:8C:B2:32:AA:32:BE:2D`.
  Back both files up somewhere safe: every update must be signed with this
  key (Google can reset a lost upload key, but it takes days).
- Play App Signing holds the app signing key. Its SHA-1 (Play Console > Setup
  > App signing) must be on the "TSL Android Maps" API key, next to the
  upload and debug keys, or maps won't load in Play installs.
- Publishing account: service account
  `tsl-play-publisher@tsl-facility-manager.iam.gserviceaccount.com` (Google
  Cloud project tsl-facility-manager, Play Android Developer API on). Its key
  is `android/fastlane/play-service-account.json` (git-ignored). It must be
  invited in Play Console > Users and permissions with access to this app.

## Release

```bash
cd android
export LANG=en_US.UTF-8
# bump version in pubspec.yaml first (the iOS lane `increment_build` does it)
fastlane android deploy            # signed AAB → internal testing
fastlane android promote           # internal → production (rollout:0.2 for 20%)
fastlane android listing           # texts, icon, feature graphic, screenshots
fastlane android status            # version codes per track
```

Release notes for each version code go in
`fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.

## Listing assets

`fastlane/metadata/android/en-US`: title, short and full description, icon
(512×512), feature graphic (1024×500) and 7 phone screenshots (1080×1920,
from the sample data on a 1080×1920 emulator with Android demo mode).

## Notes

- The very first build of a new app has to be uploaded in Play Console by
  hand; after that Fastlane can upload.
- A full disk makes Gradle fail with lint "Unexpected lint invalid
  arguments" errors before the real "No space left on device" one.
