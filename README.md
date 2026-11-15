# depressedzone

A Flutter client for browsing and playing titles from an unofficial third-party streaming catalog. The project includes Android phone and TV, iOS, Windows, macOS, Linux, and web targets.

The catalog and media sources are external services. Availability, playback, audio tracks, and subtitles depend on each title and may change. Use the app only with content you are authorized to access.

## Features

- Browse and search films, series, anime, and other catalog sections.
- View title details, seasons, episodes, and watch progress.
- Play media with quality, audio, subtitle, speed, and skip controls.
- Manage a watchlist, history, and offline downloads.
- Use touch, keyboard, remote, or gamepad controls where supported.

## Get started

Install a Flutter SDK compatible with the Dart constraint in [`pubspec.yaml`](pubspec.yaml), then run:

```sh
flutter pub get
flutter run
flutter test
flutter analyze
```

Choose a specific device with `flutter devices` and `flutter run -d <device-id>`.

### Android

Install the Android SDK and JDK 17. The app requires Android 7.0 (API 24) or newer. Android TV launcher resources are included.

```sh
flutter build apk --release
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

For a distributable release, copy [`android/key.properties.example`](android/key.properties.example) to `android/key.properties` and supply your own keystore details. The private properties file and keystore are ignored by Git. Without them, release builds use the debug signing key and must not be distributed.

### Desktop and web

Desktop builds need the platform's Flutter toolchain: Visual Studio with Desktop development with C++ for Windows, Xcode for macOS, or the required Linux development packages. On Windows, enable Developer Mode for plugin symlinks.

```sh
flutter run -d windows
flutter run -d chrome
flutter build web
```

Browser CORS rules can limit catalog requests and media playback on the web target.

### Windows installer

Run this from PowerShell whenever you want a new Windows build:

```powershell
.\build-windows.ps1
```

The script builds the release app and creates one shareable setup EXE in `build/installer/`. It reads the version from `pubspec.yaml`, bundles the Flutter and media playback files, and includes the Microsoft Visual C++ runtime. Inno Setup 6 is required on the build PC; install it with `winget install --id JRSoftware.InnoSetup -e -s winget`. The recipient only needs the setup EXE.

## Project layout

| Path | Purpose |
| --- | --- |
| `lib/core/` | Theme, layout, device, and formatting helpers |
| `lib/data/` | Catalog API, models, playback, downloads, and local storage |
| `lib/ui/` | Screens, widgets, navigation, and player UI |
| `assets/` | Bundled images and fonts |
| `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` | Flutter platform projects |
| `test/` | Dart tests |
| `tool/` | Media proxy check and asset generation scripts |

The source icon and TV banner live in `assets/img/`. The icon and splash scripts in `tool/` use these files to regenerate platform resources. The Android TV banner, launcher icons, and splash assets are already included in their platform directories.

[`PRODUCT.md`](PRODUCT.md) contains the product brief and notes about the external catalog API.
