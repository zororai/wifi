# RSSI Mapper

Indoor Wi-Fi RSSI mapping and strongest-signal region detection (Flutter, Android only).

The app records device-reported Wi-Fi RSSI (dBm) at known positions in a rectangular
room and builds maps **only** from those measured points plus IDW interpolation. It is
not a spectrum analyser, cannot see Wi-Fi through the camera, and cannot locate the
router. Fully offline.

## Requirements

- Flutter stable (developed with 3.47.4 / Dart 3.13.3)
- Android SDK with platform 36, Android 8.0+ (API 26) device

## Commands

```
flutter pub get
dart run build_runner build      # drift code generation (after changing tables)
flutter analyze
flutter test
flutter run                       # on a connected Android device
```

## Layout

```
lib/
  core/       result and error types, theme, routing
  domain/     pure Dart engine (no Flutter imports)        – Phase 2
  data/       drift database, repositories
  platform/   Wi-Fi and AR interfaces + native bridges     – Phases 3, 4B
  features/   screens (dashboard, survey, heatmap, …)
spikes/       Phase 0 throwaway validation apps (not part of the app)
```
