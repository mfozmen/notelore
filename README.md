# Notelore

**Your personal lore, kept by an LLM.**

Tell it things. It writes tidy, human-readable Markdown notes on your disk. Ask it later: *"Which database did we pick for Mopsos?"* It answers from your notes, and backs them up to Google Drive.

- Local-first: plain Markdown files you can open in any editor or Obsidian
- Bring your own model: Claude, GPT, Gemini, or a local model via Ollama
- Decisions are tracked with history, so "what did we decide?" has one correct answer
- Windows and macOS

> **Status:** pre-alpha, under active development. See [`docs/PLAN.md`](docs/PLAN.md).

## Install

**The app** (Windows, macOS, Android): download it from the [releases page](https://github.com/mfozmen/notelore/releases).
- **Windows**: `notelore-app-<version>-windows-x64.zip`. Unzip it into a folder of your own, such as `%LOCALAPPDATA%\Notelore`, and run `notelore.exe`.
- **macOS**: `notelore-app-<version>-macos.zip` contains `notelore.app`. It is not notarized yet, so the first time right-click it and choose *Open*.
- **Android**: `notelore-app-<version>-android.apk`. Allow installing from your browser or file manager when Android asks.

The desktop app checks for a newer release once a day (silently skipped when offline). *Update and restart* downloads it and checks it against the SHA-256 published with the release; this catches corrupted or partial downloads, it is not a signature. Only then does it swap the new version in and restart. If the swap fails halfway, the previous version is put back. On Android, install the newer APK over the old one.

**The command line** (until it is retired in [#69](https://github.com/mfozmen/notelore/issues/69)): download `notelore-<version>-windows-x64.zip` or `notelore-<version>-macos-arm64.zip`, unzip it and run `notelore`. It checks for updates the same way. `notelore update` replaces the executable in place; a Python install gets the matching `uv tool upgrade notelore` hint instead.

Releases are cut on demand from the Conventional Commit history on `main`: a `feat` commit bumps the minor version, `fix` or `perf` the patch version; other types (`docs`, `chore`, `ci`...) do not.

## First run

Run `notelore`. It asks which model to use:

1. **Claude**, **GPT** or **Gemini**: it opens the page where you create an API key, you paste the key, and Notelore checks it with one tiny request. The key is stored in your OS credential store (Windows Credential Manager, macOS Keychain), never in a file.
2. **Ollama**: no key. Start the Ollama app first; Notelore checks that it answers on `http://localhost:11434` (or `OLLAMA_HOST`).

Then just talk: *"Mopsos için not al: veritabanı olarak SQLite seçtik, tek kullanıcı."* Notes land in `~/Notelore/`. Commands:

| Command | What it does |
|---|---|
| `/model` | pick another provider or model |
| `/logout` | forget the saved key and pick again |
| `/help` | list the commands |
| `/exit` | quit (Ctrl-D works too) |

In Git Bash on Windows the prompt falls back to plain input: no command completion, and a pasted key stays visible. Windows Terminal or PowerShell give the full prompt.

## The app (preview)

The Flutter app in `apps/notelore` is replacing the command line ([#60](https://github.com/mfozmen/notelore/issues/60)). It does the same on Android, Windows and macOS: pick a provider and paste its key (kept in Android Keystore, macOS Keychain or Windows Credential Manager), then chat; the Notes tab lists every project and topic and opens them read-only, and Settings changes the model or logs out (which forgets every saved key on that device; the notes stay). Notes go to `~/Notelore/` on the desktop and to the app's own storage on a phone. The macOS app is not sandboxed, so that folder is the real, visible one; it ships outside the Mac App Store. In Settings, **Google Drive → Connect** backs the notes up to a `Notelore` folder in your Drive and keeps every device in sync: on start, after every chat turn and on *Sync now*. The app only asks for access to files it creates itself (`drive.file`), never the rest of your Drive. Offline is fine; the next sync catches up. When two devices changed the same line, the model merges them and both originals are kept under `.notelore/history/`.

Until the first release, run it with `flutter run` from `apps/notelore` or install the debug APK that CI attaches to every build. Drive sign-in needs the project's OAuth client ids, which are never committed: put them in the repo's gitignored `.env` (`NOTELORE_GOOGLE_CLIENT_ID` and `NOTELORE_GOOGLE_CLIENT_SECRET` for the desktop client, `NOTELORE_GOOGLE_WEB_CLIENT_ID` for Android) and run `flutter run --dart-define-from-file=../../.env`. A build without them works, just without sync.

## Development

Requires [uv](https://docs.astral.sh/uv/) for the Python packages and [Flutter](https://docs.flutter.dev/get-started/install) for the Dart ones. Notelore is moving to Flutter ([#60](https://github.com/mfozmen/notelore/issues/60)); until then both live side by side:

| Path | Package | What it is |
|---|---|---|
| `packages/core` | `notelore-core` | shared core: note format, store, sync, providers, agent |
| `apps/cli` | `notelore` | the desktop command and chat |
| `apps/mobile` | | Briefcase spike, superseded by the Flutter app |
| `packages/notelore_core` | | Dart port of the core ([#60](https://github.com/mfozmen/notelore/issues/60)) |
| `apps/notelore` | | the Flutter app: Android, iOS, Windows, macOS ([#60](https://github.com/mfozmen/notelore/issues/60)) |

```bash
uv sync
uv run pre-commit install
uv run pytest
```

Contributor guide for humans and AI agents: [`CLAUDE.md`](CLAUDE.md). Note format spec: [`docs/note-format.md`](docs/note-format.md).

## License

MIT
