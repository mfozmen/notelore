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

The app checks for a newer release when it starts (at most once a day), every 6 hours while it stays open, and on *Settings → Check for updates*. An update is installed only when its SHA-256 matches the one published with the release and that checksum carries the release's Ed25519 signature (`<file>.sha256.sig`): the checksum catches corrupted or partial downloads, the signature proves Notelore's release workflow made the file, so whoever can only replace files in a GitHub release cannot ship an update.

The signing key is set up once, by the maintainer:

```bash
openssl genpkey -algorithm ed25519 -out update-key.pem
openssl pkey -in update-key.pem -pubout -outform DER | tail -c 32 | base64   # the public half
```

- The PEM goes into the repository secret `NOTELORE_UPDATE_SIGNING_KEY`; keep an offline copy and delete the file.
- The public half goes into the repository variable `NOTELORE_UPDATE_PUBLIC_KEY`; release builds pin it (`--dart-define=NOTELORE_UPDATE_PUBLIC_KEY`).
- The release workflow stops before tagging when either is missing, and before uploading when they are not a pair. Changing the key strands the apps that pin the old one: they no longer update themselves, and need the new version installed by hand. On Windows the setup runs silently and restarts Notelore; on macOS the new app replaces the old one, which is put back if that fails halfway; on Android the system installer opens and the user taps Install.

The old command line (`notelore-<version>-*.zip`, v0.2.0 and earlier) is retired; the app reads the same `~/Notelore` folder.

## App icon

Notelore's mark (a note you talk to: a white card with a folded corner and a speech tail, on lagoon teal) is drawn in code, in `apps/notelore/lib/src/mark.dart`. The app shows it on the sign-in screen and in Settings' About card. Every platform's icon is rendered from that same painter: the Android legacy and adaptive icons (foreground inside the 66 dp safe zone, plus a monochrome layer for themed icons), the Windows `.ico`, and the macOS and iOS app icon sets. After changing the mark, regenerate them and commit the result:

```bash
cd apps/notelore && flutter test tool/make_icons_test.dart
```

It lives outside `test/`, so the test suite never writes these files.

## More

- Contributor guide for humans and AI agents: [`CLAUDE.md`](../CLAUDE.md)
- Note format: [`note-format.md`](note-format.md)
- Roadmap: [`PLAN.md`](PLAN.md)
