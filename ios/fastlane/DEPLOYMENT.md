# TSL Facility Manager iOS: TestFlight / App Store runbook

Same setup as SpotLat (same Apple team).

- Bundle ID: `com.dawnglobalict.tslfacilitymanager`
- Apple team: `932B2QQQ55` · App Store Connect team: `118531340`
- Auth: App Store Connect API key `AuthKey_B825553C28.p8` (Admin, created
  25 Nov 2026). It lives beside this file and is git-ignored. Keep the
  original somewhere safe: Apple only lets you download it once.
- Issuer ID: `69a6de90-5b4d-47e3-e053-5b8c7c11a4d1` (pass as `ASC_ISSUER_ID`).

## On a new machine

1. Copy `AuthKey_B825553C28.p8` into `ios/fastlane/`.
2. Create `ios/Flutter/Secrets.xcconfig` (git-ignored) with the iOS Maps
   key ("TSL iOS Maps" in Google Cloud, restricted to the bundle ID):
   `GMS_API_KEY = …`. Without it the map crashes on iOS.
3. Fastlane and Homebrew CocoaPods installed (`gem install fastlane`,
   `brew install cocoapods`).

## Release

```bash
cd ios
export LANG=en_US.UTF-8 ASC_ISSUER_ID=69a6de90-5b4d-47e3-e053-5b8c7c11a4d1
fastlane ios increment_build      # bumps +build in pubspec.yaml
fastlane ios deploy               # Flutter build → signed IPA → TestFlight
fastlane ios submit build:<N>     # once processed: send it for review
```

Versions live only in `pubspec.yaml` (`version: <name>+<build>`). Every
upload needs a higher build number.

| Lane | What it does |
|------|--------------|
| `register_app_id` | Registers the App ID (done once, 25 Nov 2026) |
| `deploy` | Flutter build, pods, signed IPA, upload via altool |
| `build` | Signed IPA only |
| `export_upload archive:<path>` | Re-export an existing .xcarchive and upload (after an export failure) |
| `upload ipa:<path>` | Upload an existing IPA |
| `increment_build` | Bump the build number |
| `certificates` | Create/fetch distribution cert + App Store profile (manual signing only) |
| `submit build:<N>` | Submit a processed build for review |

## Signing

Automatic signing through the API key: Xcode creates the distribution
certificate and profile, and turns on Push from `Runner.entitlements`
(the API key can't change capabilities directly). Every build overrides the
project's personal team with `DEPLOYMENT_TEAM=932B2QQQ55`.

The distribution certificate's private key exists only on the Mac that
created it. To release from another Mac, export it from Keychain Access as
`.p12` and import it there, or let automatic signing create a new one.

## Known traps on this network

- Git over HTTP/2 to GitHub breaks mid-clone (pods). Run with
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1`.
- Swift Package Manager couldn't fetch firebase-ios-sdk, so the project uses
  CocoaPods (`enable-swift-package-manager: false` in pubspec.yaml).
  Firebase stops publishing new CocoaPods versions after October 2026; the
  current ones keep working.
- Upload with altool, not `upload_to_testflight` (spurious 409 on the
  sibling apps).
- From April 2027 uploads need Xcode 27 (iOS 27 SDK).

## App Review access

Reviewers can't receive email codes and aren't on site, so:

- Client: `appreview@thickservices.com` signs in with a fixed code
  (`settings/appReview`, set with `tool/set_review_code.cjs`; nothing is
  emailed).
- Staff: App Review Supervisor / App Review Technician (dashboard staff,
  `appreview.supervisor@` / `appreview.staff@thickservices.com`).
- Facility: "App Review Demo – do not use", radius 20,100 km, so a reviewer
  anywhere counts as on site. Listed in `settings/public.reviewFacilityIds`
  and shown only to `settings/public.reviewAccountIds`. Keep it: every
  update goes through review.
- Passwords and the client code: the git-ignored `.test-accounts.json`.
- `settings/public.clientSignupOnIos = false` hides client sign-up on iOS
  without a new build, if App Review objects to it (guideline 3.1.1, as
  happened to SpotLat).
