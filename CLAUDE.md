# TV launcher (FLauncher fork)

Personal fork of FLauncher, an Android TV home launcher written in Flutter. History: upstream
[flauncher/flauncher](https://gitlab.com/flauncher/flauncher) 0.18.0 (last release 2023-03, unmaintained),
then the [zompinc/flauncher](https://github.com/zompinc/flauncher) fork (Firebase removed, pointer support),
which this repo is cloned from. Remotes: `upstream` (GitLab), `zomp` (GitHub). Own remote: `origin` (private GitHub repo `tvlauncher`).

`SETUP.local.md` (git-ignored) describes the target device and home network. Read it before deploying.

## Invariants

- **No `INTERNET` permission.** The APK must stay offline: no analytics, crash reporting or remote config.
  Check the merged manifest after adding a dependency; plugins can inject permissions.
- Permissions: `REQUEST_DELETE_PACKAGES` and `WRITE_SECURE_SETTINGS`. The latter is only for the
  "Remotes & accessories" settings slice and must be granted once over adb after the first install (see Deploy).

## Toolchain

Versions are pinned in three places that must stay in sync: `mise.toml`, `pubspec.yaml` (`environment.flutter`) and
`.github/workflows/release.yml`.

| Tool | Version | Source |
|---|---|---|
| Flutter | 3.47.6 (Dart 3.13) | `mise use flutter@3.47.6` (project-local) |
| JDK | 21 | `mise use java@temurin-21` (Gradle 9.3 / AGP 9.1) |
| Android SDK | platforms;android-36, build-tools;36.0.0, cmdline-tools latest | `~/.local/share/android-sdk` (user-level, no mise backend); `platform-tools` is a symlink to the mise adb. AGP downloads the NDK pinned by Flutter (`flutter.ndkVersion`) on the first build. |
| adb | platform-tools r37.0.1 | already global via mise (`http:platform-tools`) |

`mise.toml` pins Flutter and Java and exports `ANDROID_HOME`/`JAVA_HOME`; run everything as `mise exec -- flutter …`
or with mise activated. Device renders at 1920×1080, density 320 → 960×540 logical px.

`compileSdk`, `targetSdk` (36) and `minSdk` (24) follow the Flutter Gradle plugin defaults (`flutter.*SdkVersion` in
`android/app/build.gradle.kts`); bump them by upgrading Flutter. UI sounds are WAV files in `android/app/src/main/res/raw`, rendered by `uv run tool/sounds.py`; run it again after
changing a tone. SQLite comes from `package:sqlite3` 3.x via Dart build
hooks, so there is no `sqlite3_flutter_libs` any more. Code generation: `dart run build_runner build` (drift, mockito);
after a schema change also `dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/`.

## Build

- `flutter pub get && flutter build apk --release`
- Release signing: see "Package name and signing" below.
- `.github/workflows/release.yml` is inherited from the Zomp fork and builds on `v*` tags.

## Package name and signing

`applicationId`, manifest namespace, Kotlin package and method/event channel names are all `dev.neugebauer.tvlauncher`
(Dart package `tvlauncher`), so the HOME component is `dev.neugebauer.tvlauncher/.MainActivity`. Until 2026-10-12 the
namespace was still `me.efesser.flauncher`; the first install after that rename needs `set-home-activity` again.
The Zomp build (`me.efesser.flauncher`) was uninstalled from the device on 2026-10-08.

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
adb shell cmd package set-home-activity --user 0 dev.neugebauer.tvlauncher/.MainActivity
adb shell pm grant dev.neugebauer.tvlauncher android.permission.WRITE_SECURE_SETTINGS   # once, survives updates
```

If the stock launcher or the setup app's `RecoveryActivity` takes HOME back, see `SETUP.local.md`.

## Band config (readable and writable over adb)

Band size, position, edge, launch/return variants and lengths, focus motion, idle, the frame-time readout and the
motion tuning numbers (`tuning`) live in `/sdcard/Android/data/dev.neugebauer.tvlauncher/files/band_config.json`
(pretty JSON; its `_doc` key lists the allowed values). The launcher writes it on every change from
"Quick settings → Band & motion" and checks it once a second while in front, so a push applies within a second,
with no restart, root or debuggable build:

```
adb shell cat /sdcard/Android/data/dev.neugebauer.tvlauncher/files/band_config.json
adb push band_config.json /sdcard/Android/data/dev.neugebauer.tvlauncher/files/band_config.json
adb logcat -s flutter | grep "band config"     # loads and saves
adb logcat -s flutter | grep "frame times"     # with frameTimes on: fps, build/raster ms, missed vsyncs per batch
```

## Desktop build and bench

The launcher also runs as a Linux desktop app (`linux/`, cmake and ninja pinned in `mise.toml`), with
`lib/desktop/`: a fake `LauncherChannel` (24 made-up apps with generated banners and icons, a hero of five, launches
that hide the launcher and come back), file paths under one directory, and a lifecycle that stays resumed. Nothing in
`lib/main.dart` imports it, so the APK is unchanged.

```
mise exec -- flutter run -d linux --profile -t lib/desktop/main_desktop.dart   # arrows/Enter, Backspace = Back, H = Home, Q = quick settings
tool/bench/run.sh                                                              # BENCH {json}, report in build/bench/latest.json
```

Files (database, `band_config.json`) go to `build/desktop_data`. The bench (`lib/desktop/main_bench.dart` documents
the phases and the report) runs the TV's band config from `tool/bench/band_config.json`. `BENCH_CONFIG=<file>` swaps
it, `BENCH_PROFILE=phases|widgets` adds a self-time profile (`BENCH_PROFILE_PHASE=<phase>` limits it), and
`BENCH_SHOTS=<dir>` saves settled screenshots for `tool/bench/diff.py <dir-a> <dir-b>`.

Caveats: timings still vary by ~5% while the desktop is in use, but the counted work (pictures, scene) repeats exactly.
Linux always enables semantics (about a fifth of UI time), and the TV likely does not. The bench uses the normal
binding because integration_test's live bindings schedule a frame after every frame and would count 60 fps where the
app idles. Desktop numbers rank changes; the TV's frame times still come from the `frameTimes` readout.
