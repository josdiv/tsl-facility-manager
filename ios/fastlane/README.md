fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios register_app_id

```sh
[bundle exec] fastlane ios register_app_id
```

Register the App ID (with Push Notifications) on the developer portal

### ios deploy

```sh
[bundle exec] fastlane ios deploy
```

Build the Flutter release + signed IPA and upload to TestFlight

### ios export_upload

```sh
[bundle exec] fastlane ios export_upload
```

Export an existing .xcarchive to an IPA and upload it

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the signed IPA only (no upload)

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload an existing IPA to TestFlight (via altool)

### ios increment_build

```sh
[bundle exec] fastlane ios increment_build
```

Increment the build number in pubspec.yaml

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

Fetch/create the distribution certificate and App Store profile

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit a processed build for App Store review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
