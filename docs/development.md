# Developing Notelore

Requires [Flutter](https://docs.flutter.dev/get-started/install) (the version pinned in the root `pubspec.yaml`). The repo is a Dart pub workspace:

| Path | What it is |
|---|---|
| `packages/notelore_core` | pure Dart: note format, store, search index, sync, Drive, providers, agent |
| `apps/notelore` | the Flutter app: Android, iOS, Windows, macOS |
| `spec/fixtures` | the frozen format and merge contract from the original Python implementation |

```bash
flutter pub get
(cd packages/notelore_core && dart test)
(cd apps/notelore && flutter test)
(cd apps/notelore && flutter run --dart-define-from-file=../../.env)
```

Drive sign-in needs the project's OAuth client ids, which are never committed. Put them in the repo's gitignored `.env`:

- `NOTELORE_GOOGLE_CLIENT_ID` and `NOTELORE_GOOGLE_CLIENT_SECRET` for the desktop client.
- `NOTELORE_GOOGLE_WEB_CLIENT_ID` for Android.

A build without them works, just without sync. On Windows, Flutter needs Developer Mode for plugin builds.

## Releases and updates

Releases are cut on demand from the Conventional Commit history on `main`: a `feat` commit bumps the minor version, `fix` or `perf` the patch version; other types (`docs`, `chore`, `ci`...) do not.

The app checks for a newer release when it starts (at most once a day), every 6 hours while it stays open, and on *Settings → Check for updates*. An update is installed only when its SHA-256 matches the one published with the release; this catches corrupted or partial downloads, it is not a signature. On Windows the setup runs silently and restarts Notelore; on macOS the new app replaces the old one, which is put back if that fails halfway; on Android the system installer opens and the user taps Install.

The old command line (`notelore-<version>-*.zip`, v0.2.0 and earlier) is retired; the app reads the same `~/Notelore` folder.

## More

- Contributor guide for humans and AI agents: [`CLAUDE.md`](../CLAUDE.md)
- Note format: [`note-format.md`](note-format.md)
- Roadmap: [`PLAN.md`](PLAN.md)
