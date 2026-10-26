# TV launcher

Android TV home launcher for a Chromecast with Google TV, forked from
[FLauncher](https://gitlab.com/flauncher/flauncher) via the [Zomp fork](https://github.com/zompinc/flauncher).
Flutter, GPL-3.0 ([LICENSE](LICENSE)).

Built for a household that uses a handful of streaming apps: one row of large "main app" tiles, an alphabetical
grid of everything else, and quick settings for the things you touch from the couch.

## Features

- Main apps row: large tiles, your order, never scrolls. Held select on a grid tile adds, on a main tile moves,
  a longer hold opens the tile's panel.
- Apps grid: six per row, alphabetical, first row peeks in under the main apps. New installs show up by themselves.
- Remote: Down into the grid, Up back out, Back to the first main tile, Home resets focus, long-press Back opens
  quick settings. Pointer/air-mouse supported.
- Quick settings: Bluetooth device list, Wi-Fi, Display & Sound, all settings, launcher settings (wallpaper,
  hidden apps).
- Offline: no `INTERNET` permission, no analytics, no crash reporting.

## Build

Flutter and the JDK are pinned in `mise.toml`; the Android SDK needs platform 36 and build-tools 36.0.0.

```shell
flutter pub get
flutter build apk --release
```

Release builds read `android/key.properties` (git-ignored) or the `SIGNING_*` environment variables.

## Install

```shell
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell cmd package set-home-activity --user 0 dev.neugebauer.tvlauncher/.MainActivity
adb shell pm grant dev.neugebauer.tvlauncher android.permission.WRITE_SECURE_SETTINGS   # once; TV settings requires it for the Bluetooth screen
```

Google TV ignores `set-home-activity` until its own launcher and the setup app are disabled (at your own risk):

```shell
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
# undo: adb shell pm enable <package>
```

## Desktop

The launcher runs on Linux with 24 made-up apps, which is enough to try out changes without a TV:

```shell
mise exec -- flutter run -d linux --profile -t lib/desktop/main_desktop.dart
```

Arrows and Enter act as the remote, Backspace is Back, H is Home, Q opens the quick settings. Data lives in
`build/desktop_data`; its `band_config.json` applies within a second while the app runs. `tool/bench/run.sh` measures
the home screen's frame cost.

## Notes

- The Assistant button and the volume/mute buttons never reach a launcher on this device; the former belongs to
  the voice service, the latter go to the TV or projector directly.
- Picking a wallpaper image needs a file explorer app on the device.
- `docs/` holds the design decisions and the plan for the next version.
