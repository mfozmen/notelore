# Notelore app

The Flutter app. Shared Dart code lives in
[`packages/notelore_core`](../../packages/notelore_core): the note format, store,
search index, Drive sync, providers and the agent.

Android, Windows and macOS are built today. The iOS runner is in place but waits
for a Mac and a test device.

## Run

From the repository root:

```bash
flutter pub get
cd apps/notelore
flutter run -d windows   # or -d macos, -d <android-device>
```

## Test

```bash
cd apps/notelore
flutter test
```

## More

- [Development](../../docs/development.md)
- [Contributor guide](../../CLAUDE.md)
