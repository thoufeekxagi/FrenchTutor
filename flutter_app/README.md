# french_tutor

A new Flutter project.

## Local run and release commands

From this directory, use the single entry point:

```bash
./run_app.sh                 # debug run on the configured iPhone
./run_app.sh release         # release run on the configured iPhone
./run_app.sh ipa             # build a release IPA for distribution
```

The script automatically reads the local `secrets.local.properties` file when
present. Supabase production public configuration has a built-in fallback, so
the app can start without running a separate key-preparation script. Use
`--device DEVICE_ID` or `FLUTTER_DEVICE_ID` when testing on another device.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
