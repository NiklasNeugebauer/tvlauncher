# FLauncher fork

Personal fork of FLauncher, an Android TV home launcher written in Flutter. History: upstream
[flauncher/flauncher](https://gitlab.com/flauncher/flauncher) 0.18.0 (last release 2023-03, unmaintained),
then the [zompinc/flauncher](https://github.com/zompinc/flauncher) fork (Firebase removed, pointer support),
which this repo is cloned from. Remotes: `upstream` (GitLab), `zomp` (GitHub). No own remote yet.

`SETUP.local.md` (git-ignored) describes the target device and home network. Read it before deploying.

## Invariants

- **No `INTERNET` permission.** The APK must stay offline: no analytics, crash reporting or remote config.
  Check the merged manifest after adding a dependency; plugins can inject permissions.
- Permissions: `REQUEST_DELETE_PACKAGES` and `WRITE_SECURE_SETTINGS`. The latter is only for the
  "Remotes & accessories" settings slice and must be granted once over adb after the first install (see Deploy).

## Toolchain

The 2023 code base is pinned to old versions; newer ones do not build it as is.

| Tool | Version | Source |
|---|---|---|
| Flutter | 3.7.5 (Dart 2.19) | `mise use flutter@3.7.5` (project-local) |
| JDK | 11 | `mise use java@temurin-11` (AGP 7.1.1 / Gradle 7.4 do not run on 17+) |
| Android SDK | platforms;android-33, build-tools;33.0.2, cmdline-tools 9477386 | `~/.local/share/android-sdk` (user-level, no mise backend); `platform-tools` is a symlink to the mise adb |
| adb | platform-tools r37.0.1 | already global via mise (`http:platform-tools`) |

`mise.toml` pins Flutter and Java and exports `ANDROID_HOME`/`JAVA_HOME`; run everything as `mise exec -- flutter …`
or with mise activated. Device renders at 1920×1080, density 320 → 960×540 logical px.

Upgrading Flutter/AGP and raising `targetSdkVersion` (currently 33) are candidate improvements: Play Protect
on Android 14 warns "built for an older Android version" on sideload because of the old target SDK.

## Build

- `flutter pub get && flutter build apk --release`
- Release signing: see "Package name and signing" below.
- `.github/workflows/release.yml` is inherited from the Zomp fork and builds on `v*` tags.

## Package name and signing

`applicationId` is `dev.neugebauer.tvlauncher`; the Kotlin package and manifest namespace stay `me.efesser.flauncher`,
so the HOME component is `dev.neugebauer.tvlauncher/me.efesser.flauncher.MainActivity`. The Zomp build
(`me.efesser.flauncher`) was uninstalled from the device on 2026-10-08.

Signing: `android/app/upload-keystore.jks` (alias `tvlauncher`, PKCS12) with its passwords in `android/key.properties`.
Both are git-ignored; the keystore password is in the password manager. Losing the keystore means every future
update is an uninstall/reinstall. CI uses the `SIGNING_*` env vars instead of `key.properties`.

## Deploy to the device

Wireless debugging over adb (pair once, then connect; the connect port changes after every toggle/reboot):

```
adb pair <ip>:<pair-port> <code>
adb mdns services                      # shows the current _adb-tls-connect port
adb connect <ip>:<connect-port>
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell cmd package set-home-activity --user 0 dev.neugebauer.tvlauncher/me.efesser.flauncher.MainActivity
adb shell pm grant dev.neugebauer.tvlauncher android.permission.WRITE_SECURE_SETTINGS   # once, survives updates
```

If the stock launcher or the setup app's `RecoveryActivity` takes HOME back, see `SETUP.local.md`.
