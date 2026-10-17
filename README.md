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

The app checks for a new release every time it opens (and every few hours while it stays open) and offers *Update* (on Android you confirm in the system installer).

## Get started

1. Open Notelore and pick a model:
   - **ChatGPT plan** (desktop and phone): *Continue with ChatGPT* and sign in. No extra charges, within your plan's limits.
   - **Claude, GPT or Gemini:** paste an API key; the app shows where to get one. Keys stay in your device's keystore.
   - **Ollama** (desktop): start Ollama on this computer; no key needed.
2. Talk to it: *"Mopsos için not al: veritabanı olarak SQLite seçtik."*
3. Ask it later: *"Mopsos'ta hangi veritabanını seçmiştik?"*

Notelore starts on the cheapest model your provider offers; switch any time with the model chip above the message box.

> [!TIP]
> Gemini is free with a key from a Google AI Studio project that has no billing, and Ollama is free too. Claude and GPT through their APIs are billed per use; a Claude Pro or Max subscription cannot be used in other apps.

## Using it

- **On the desktop:** a side rail (with labels when the window is wide enough) replaces the phone's bottom bar, and the chat is a readable column.
- **Chat:** while the assistant works, a playful line keeps you company ("went to make coffee"); *Stop* ends a turn. You can keep writing while it works: what you add joins its answer. A message you have not sent yet stays in the box when you visit another tab. A button under your last message sends it again with one tap, handy after a failed answer; if that answer had already saved notes, its error says so, so nothing is saved twice. With ChatGPT, GPT or Claude it can look things up on the web when that helps get a note right (the author of a book you mention, say); turn it off in Settings. Anthropic bills each search.
- **Voice:** one button next to the message box, like a messenger's: with text it sends, empty it records. Hold it and talk; let go and what you said is sent, and the answer is read aloud (by keyboard, hold Space on the focused button; a screen reader taps once to start and again to send). Typing still works. On first start Notelore downloads Whisper by itself in the background (about 375 MB, once per device; not bundled, so updates stay small; an interrupted download continues where it stopped). Whisper hears you on the device, offline, in any language; Settings shows the download and lets you pick the microphone (and list them again after plugging one in). Until it is there, voice mode uses the device's speech recognition (on Windows that needs the speech pack for your language, and Windows has no Turkish one). English product and technical terms in Turkish speech are written in their usual spelling ("deyta beys" becomes "database").
- **Notes:** browse your projects and topics; on a wide window the open note sits beside the list. Links in notes open in your browser. Deleting a note moves it to `_archive/` in the notes folder, with an Undo; the *Archive* button lists what was deleted and restores it (entries the assistant archived go back into their note).
- **Settings:** language (System, English or Türkçe), a theme from six nature palettes (lagoon, pine forest, open sea, sunset, lavender field, northern lights) in light or dark, model, Google Drive, an optional app lock, and an About card with the version, updates and log out. On a wide window the sections (model, voice, sync and files, appearance, app lock, about) are listed on the left, one shown at a time.
- **App lock:** *Settings → App lock → Turn on* sets a PIN or password (at least 4 characters, typed twice) that Notelore asks for every time it opens, before any note or chat shows, and again when it comes back after a minute or more in the background (a quick switch to another app does not lock). After five wrong tries it makes you wait before the next one: 30 seconds, then a minute, then five minutes; the count survives a restart and resets on the right entry. Only a salted hash of it is kept, in the device's keystore; it is never stored as plain text and never synced. Turning it off asks for it first. The lock never touches your notes: if you forget it, they are still files in the notes folder and on Drive.
- **Google Drive:** *Settings → Google Drive → Connect* backs your notes up to a `Notelore` folder and keeps every device in sync, settings too (language, theme, provider and model; never your keys). Notelore only sees the files it creates.

Your notes live in `~/Notelore/` on the desktop and in the app's storage on a phone. Nothing is ever deleted for good: archived notes and both sides of a sync conflict are kept.

## Development

See [docs/development.md](docs/development.md).
