# Notelore

**Your personal lore, kept by an LLM.**

Tell it things. It writes tidy, human-readable Markdown notes on your disk. Ask it later: *"Which database did we pick for Mopsos?"* It answers from your notes, and backs them up to Google Drive.

- Local-first: plain Markdown files you can open in any editor or Obsidian
- Bring your own model: Claude, GPT, Gemini, or a local model via Ollama
- Decisions are tracked with history, so "what did we decide?" has one correct answer
- Windows, macOS and Android (iOS next), all in sync through your Google Drive

> **Status:** pre-alpha, under active development. See [`docs/PLAN.md`](docs/PLAN.md).

## Install

**The app** (Windows, macOS, Android): download it from the [releases page](https://github.com/mfozmen/notelore/releases).
- **Windows**: `notelore-app-<version>-windows-x64-setup.exe`. Run it; by default it installs for all users into Program Files (asks for admin rights), or choose to install only for you (no admin rights). It adds a Start menu entry and an uninstaller. Windows may warn that the publisher is unknown, because the setup is not code-signed yet.
- **macOS**: `notelore-app-<version>-macos.dmg`. Open it and drag `notelore.app` onto *Applications*. It is not notarized yet, so the first time right-click it and choose *Open*.
- **Android**: `notelore-app-<version>-android.apk`. Allow installing from your browser or file manager when Android asks.

The desktop app checks for a newer release when it starts (at most once a day) and every 6 hours while it stays open, silently skipped when offline; *Settings → Check for updates* asks right away. *Update and restart* downloads it and checks it against the SHA-256 published with the release; this catches corrupted or partial downloads, it is not a signature. Only then does it install it: on Windows the setup runs silently and restarts Notelore; on macOS the new app replaces the old one, which is put back if that fails halfway. On Android, install the newer APK over the old one.

The old command line (`notelore-<version>-*.zip`, v0.2.0 and earlier) is retired. Newer releases carry no executable for it, so its `notelore update` reports one missing. Switch to the app instead: it reads the same `~/Notelore` folder.

Releases are cut on demand from the Conventional Commit history on `main`: a `feat` commit bumps the minor version, `fix` or `perf` the patch version; other types (`docs`, `chore`, `ci`...) do not.

## First run

Open Notelore and pick a model. The list is grouped by how you pay: *Use your plan*, *API key* and *On this computer*; Settings shows which one is in use.

0. **ChatGPT plan** (Windows and macOS): *Continue with ChatGPT* signs in in your browser and lets Notelore use your ChatGPT Plus or Pro plan ("Sign in with ChatGPT"). There are no separate charges, within your plan's limits; *Manage usage* under the chat opens ChatGPT's usage settings. You can disconnect Notelore in ChatGPT's settings.
1. **Claude**, **GPT** or **Gemini**: the app shows where to create an API key. Paste the key and Notelore checks it with a free request (it lists the models) and starts on the cheapest model listed; switch any time with the model chip in the chat. The key is kept in the platform keystore (Android Keystore, macOS Keychain, Windows Credential Manager), never in a file.
2. **Ollama**: no key. Start Ollama first; Notelore checks that it answers on `http://localhost:11434` (or `OLLAMA_HOST`).

What it costs (the setup screen says it too):
- **Free**: Gemini with a key from a Google AI Studio project that has no billing. It is rate limited, and Google may use free-tier requests to improve its products. Ollama is also free.
- **Your ChatGPT plan**: no separate charges, within the plan's limits (desktop).
- **Billed per use**: Claude and GPT through their APIs. A Claude Pro or Max subscription cannot be used in other apps (Anthropic's terms).

Then just talk: *"Mopsos için not al: veritabanı olarak SQLite seçtik, tek kullanıcı."* The model chip above the message box switches between the models your provider offers at any time; the conversation carries on. While the assistant works, the chat shows what it is doing ("Searching the notes… 4 s"); *Stop* ends the turn, and a turn that takes more than 3 minutes stops by itself.
- **Notes**: lists every project and topic and opens each one read-only. A long press (or the delete button of an open note) moves a note to the archive, `_archive/<date>/` in the notes folder, with an Undo; nothing is deleted for good.
- **Settings**: pick the model from the ones your key can use (the list comes from the provider and is refreshed on every start, or with the refresh button; you can also type any model name; the last chosen model is kept, and if the provider stops offering it the chat asks you to pick another), or log out. Logging out forgets every saved key on that device; the notes stay.

Notes go to `~/Notelore/` on the desktop and to the app's own storage on a phone. The macOS app is not sandboxed, so that folder is the real, visible one; it ships outside the Mac App Store.

### Google Drive

In Settings, **Google Drive → Connect** backs the notes up to a `Notelore` folder in your Drive and keeps every device in sync: on start, after every chat turn, every few minutes while the app is open, whenever you come back to it, and on *Sync now*.
- The app only asks for access to files it creates itself (`drive.file`), never the rest of your Drive.
- Offline is fine; the next sync catches up.
- When two devices changed the same line, the model merges them, and both originals are kept under `.notelore/history/`.

## Development

Requires [Flutter](https://docs.flutter.dev/get-started/install) (the version pinned in the root `pubspec.yaml`). It is a Dart pub workspace:

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

Contributor guide for humans and AI agents: [`CLAUDE.md`](CLAUDE.md). Note format spec: [`docs/note-format.md`](docs/note-format.md).

## License

MIT
