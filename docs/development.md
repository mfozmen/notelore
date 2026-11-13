# Developing Notelore

Requires [Flutter](https://docs.flutter.dev/get-started/install) (the version pinned in the root `pubspec.yaml`). The repo is a Dart pub workspace:

| Path | What it is |
|---|---|
| `packages/notelore_core` | pure Dart: note format, store, search index, sync, Drive, providers, agent |
| `apps/notelore` | the Flutter app: Android, iOS, Windows, macOS |
| `apps/catalog` | the design catalog (Widgetbook) on fake data: [Design catalog](#design-catalog) |
| `apps/notelore/android/wear` | the Wear OS watch app, native Kotlin: [`wear-os.md`](wear-os.md) |
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
- The public half is pinned in `.github/workflows/release.yml` (the same literal the app builds with). It is public; changing it takes a protected PR.
- The release workflow stops before tagging when either is missing or they are not a pair, and checks the pair again before it signs. Changing the key strands the apps that pin the old one: they no longer update themselves, and need the new version installed by hand. On Windows the setup runs silently and restarts Notelore; on macOS the new app replaces the old one, which is put back if that fails halfway; on Android the system installer opens and the user taps Install.

The old command line (`notelore-<version>-*.zip`, v0.2.0 and earlier) is retired; the app reads the same `~/Notelore` folder.

## Design catalog

`apps/catalog` is a [Widgetbook](https://docs.widgetbook.io) app that shows the design language in one place: the rules page (Kil and Orman colours, the three faces, spacing, the orb, the soft card, Phosphor weights), the components, and the main screens. Its knobs switch Kil and Orman, text at 1x, 1.5x and 2x, and the Galaxy S23 Ultra (412x915), a small phone (360x640) and a 1280-wide desktop.

The screens run on a made-up session (`apps/catalog/lib/fake.dart`): temp folders, invented notes, an in-memory keystore and a scripted model, never the real notes, keys or network. It stays in the repo, with no public hosting.

```bash
cd apps/catalog && flutter run -d windows
```

Its tests also hold the goldens: every main screen at 412x915, 360x640 and 1280 wide, light and dark, text at 1x and 2x, with the bundled fonts. They compare on Linux only (other systems rasterise fonts a little differently) and skip elsewhere; a failure uploads the diff images as the `golden-diffs` artifact. Render them anew only on purpose, with the reason in the PR: `flutter test --update-goldens` on Linux, or run the Flutter workflow by hand with `update_goldens` and commit its `goldens-linux` artifact into `apps/catalog/test/goldens/`.

```bash
gh workflow run flutter.yml --ref <branch> -f update_goldens=true
gh run download <run id> -n goldens-linux -D apps/catalog/test/goldens
```

Only Windows has its runner committed; for macOS or a phone, add one locally first with `flutter create --platforms=macos .` (or `android`) and leave it uncommitted. CI analyses and tests the catalog, but it is outside the 100% coverage gate: it is a viewer for code that is already covered in `apps/notelore`, and its own tests check that every screen builds.

## App icon

Notelore's mark (a folded ribbon N, its end cut like a bookmark, on the Kil theme's terracotta) is drawn in code, in `apps/notelore/lib/src/mark.dart`. The app shows it on the sign-in screen and in Settings' About card. Every platform's icon is rendered from that same painter: the Android legacy and adaptive icons (foreground inside the 66 dp safe zone, plus a monochrome layer for themed icons), the Windows `.ico`, and the macOS and iOS app icon sets. After changing the mark, regenerate them and commit the result:

```bash
cd apps/notelore && flutter test tool/make_icons_test.dart
```

It lives outside `test/`, so the test suite never writes these files.

## More

- Contributor guide for humans and AI agents: [`CLAUDE.md`](../CLAUDE.md)
- Workflow in one page: [`CONTRIBUTING.md`](../CONTRIBUTING.md)
- Design patterns: [`design-patterns.md`](design-patterns.md)
- Note format: [`note-format.md`](note-format.md)
- The Wear OS app, its emulator and a real watch: [`wear-os.md`](wear-os.md)
- Roadmap: [`PLAN.md`](PLAN.md)

On Windows a release also publishes a signed changed-files delta from each of
the last two releases, when that older app already has `notelore-updater.exe`.
The app uses the delta only when the manifest signature and every changed file
hash match; otherwise it downloads the full setup. macOS keeps the full signed
dmg, because changing files inside the signed bundle breaks its signature.
