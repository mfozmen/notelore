# Notelore

[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=coverage)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Maintainability](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Reliability](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Security](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Release](https://img.shields.io/github/v/release/mfozmen/notelore)](https://github.com/mfozmen/notelore/releases)

> A note-taking assistant you talk to. Your notes stay plain Markdown on your disk.

Tell it things; it writes tidy notes. Ask later, *"Which database did we pick for Mopsos?"*, and it answers from your notes.

- **Plain files:** Markdown you can open in any editor or Obsidian
- **Your choice of model:** your ChatGPT plan, Claude, GPT, Gemini, or a local model with Ollama
- **Talk or type:** voice mode listens and reads answers aloud
- **Every device in sync** through your Google Drive: Windows, macOS and Android
- **English and Turkish**

> [!NOTE]
> Notelore is early and under active development. See the [roadmap](docs/PLAN.md).

## Install

Download the app from the [releases page](https://github.com/mfozmen/notelore/releases):

| Platform | File | Notes |
|---|---|---|
| Windows | `notelore-app-<version>-windows-x64-setup.exe` | Installs for all users by default, or only for you. Windows may warn about an unknown publisher (not code-signed yet). |
| macOS | `notelore-app-<version>-macos.dmg` | Drag `notelore.app` onto *Applications*. The first time, right-click it and choose *Open* (not notarized yet). |
| Android | `notelore-app-<version>-android.apk` | Allow installing from your browser or file manager. |

The app checks for new releases and offers *Update* (on Android you confirm in the system installer).

## Get started

1. Open Notelore and pick a model:
   - **ChatGPT plan** (desktop): *Continue with ChatGPT* and sign in. No extra charges, within your plan's limits.
   - **Claude, GPT or Gemini:** paste an API key; the app shows where to get one. Keys stay in your device's keystore.
   - **Ollama:** start Ollama on this computer; no key needed.
2. Talk to it: *"Mopsos için not al: veritabanı olarak SQLite seçtik."*
3. Ask it later: *"Mopsos'ta hangi veritabanını seçmiştik?"*

Notelore starts on the cheapest model your provider offers; switch any time with the model chip above the message box.

> [!TIP]
> Gemini is free with a key from a Google AI Studio project that has no billing, and Ollama is free too. Claude and GPT through their APIs are billed per use; a Claude Pro or Max subscription cannot be used in other apps.

## Using it

- **Chat:** the chat shows what the assistant is doing; *Stop* ends a turn.
- **Voice mode:** the voice icon next to the message box switches to talking. Notelore listens, answers aloud, and listens again; typing still works. On Windows, add the speech pack for your language (Settings, Time & language, Speech).
- **Notes:** browse your projects and topics. Deleting a note moves it to `_archive/` in the notes folder, with an Undo.
- **Settings:** language (System, English or Türkçe), model, Google Drive, updates, log out.
- **Google Drive:** *Settings → Google Drive → Connect* backs your notes up to a `Notelore` folder and keeps every device in sync. Notelore only sees the files it creates.

Your notes live in `~/Notelore/` on the desktop and in the app's storage on a phone. Nothing is ever deleted for good: archived notes and both sides of a sync conflict are kept.

## Development

See [docs/development.md](docs/development.md).
