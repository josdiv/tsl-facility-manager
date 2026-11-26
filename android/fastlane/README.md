fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android build

```sh
[bundle exec] fastlane android build
```

Build the signed release App Bundle

### android validate

```sh
[bundle exec] fastlane android validate
```

Dry-run an upload to the internal track (nothing is published)

### android deploy

```sh
[bundle exec] fastlane android deploy
```

Build and upload to the internal testing track

### android promote

```sh
[bundle exec] fastlane android promote
```

Promote the current internal release to production

### android listing

```sh
[bundle exec] fastlane android listing
```

Upload the store listing: texts, icon, feature graphic, screenshots

### android status

```sh
[bundle exec] fastlane android status
```

Show the version codes on each track

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
