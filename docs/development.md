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

The app checks for a newer release when it starts (at most once a day), every 6 hours while it stays open, and on *Settings → Check for updates*. An update is installed only when its SHA-256 matches the one published with the release (corrupted or partial downloads) and its `.sig` is an ed25519 signature by the release key built into the app (#312): someone who can only upload release assets cannot make the app install their file. On Windows the setup runs silently and restarts Notelore; on macOS the new app replaces the old one, which is put back if that fails halfway; on Android the system installer opens and the user taps Install.

**The release key (once).** The release workflow signs every app file with an ed25519 key, and the apps check those signatures against its public half:

```bash
openssl genpkey -algorithm ed25519 -out notelore-update.pem          # keep it safe, outside the repo
openssl pkey -in notelore-update.pem -pubout -outform DER | tail -c 32 | base64   # its public half
```

Store the whole PEM file as the repository **secret** `NOTELORE_UPDATE_SIGNING_KEY`, and the base64 line as the repository **variable** `NOTELORE_UPDATE_PUBLIC_KEY` (it is public). A release fails without them, and it fails if they do not belong together, so an app that could never update again is never shipped. Losing the private key means the next app has to be installed by hand once.

**Google Play.** Play forbids self-updates, so its build has no updater on Android and no `REQUEST_INSTALL_PACKAGES` permission or FileProvider (#307): `flutter build appbundle --release --dart-define=NOTELORE_STORE=play`. The one define switches both the Dart updater and the manifest (`android/app/src/play/AndroidManifest.xml`, merged by `build.gradle.kts`). The release workflow builds this bundle as the `play-bundle` artifact, for upload to Play by hand; the GitHub APK keeps updating itself.

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
