# Notelore

[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=coverage)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Maintainability](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Reliability](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Security](https://sonarcloud.io/api/project_badges/measure?project=mfozmen_notelore&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=mfozmen_notelore)
[![Release](https://img.shields.io/github/v/release/mfozmen/notelore)](https://github.com/mfozmen/notelore/releases)

> A note-taking assistant you talk to. Your notes stay plain Markdown on your disk.

Tell it things; it writes tidy notes. Ask later, *"Which database did we pick for Mopsos?"*, and it answers from your notes.

- **Plain files:** your notes are Markdown, readable in any editor or Obsidian; export them from the Notes screen (or find them in your Google Drive's Notelore folder)
- **Your choice of model:** your ChatGPT plan, Claude, GPT, Gemini, or a local model with Ollama
- **Talk or type:** voice mode listens and reads answers aloud
- **Every device in sync** through your Google Drive: Windows, macOS and Android
- **English and Turkish**

> [!NOTE]
> Notelore is early and under active development. See the [roadmap](https://github.com/mfozmen/notelore/milestones?direction=asc&sort=due_date).

## Install

Download the app from the [releases page](https://github.com/mfozmen/notelore/releases):

| Platform | File | Notes |
|---|---|---|
| Windows | `notelore-app-<version>-windows-x64-setup.exe` | Installs for all users by default, or only for you. Windows may warn about an unknown publisher (not code-signed yet). |
| macOS | `notelore-app-<version>-macos.dmg` | Drag `notelore.app` onto *Applications*. The first time, right-click it and choose *Open* (not notarized yet). |
| Android | `notelore-app-<version>-android.apk` | Allow installing from your browser or file manager. |

The app checks for a new release every time it opens (and every few hours while it stays open) and offers *Update* (on Android you confirm in the system installer).

## Get started

1. Open Notelore and *Sign in with Google* with your Google (Gmail) account: this also connects Google Drive, where your notes are backed up and synced.
2. Pick a model, step by step: *Choose* the provider (each option is a card saying who it suits; the chosen one shows what it costs, where your notes go, how good it is and the effort to set it up; one you connected before is used again at once), *Connect* it (its cost and, for a key, numbered steps to get one), and *Done* says what is connected and shows the model's own one-line hello, proof that it works (that one message goes to the provider, a few tokens; if it fails, you are back on *Connect* with the reason). A bar on top shows the step; back goes one step back and keeps your choice. The ChatGPT plan stays one tap, straight from *Choose*:
   - **ChatGPT plan** (desktop and phone), the default: *Continue with ChatGPT* and sign in, one tap; on a phone the browser hands you back to Notelore by itself. No extra charges, within your plan's limits. It needs a **Plus or Pro** plan: only those can be shared with other apps. A free ChatGPT account is told so plainly, and offered the free way in right there: *Get a free Gemini key* opens Google AI Studio with your Google account; copy the key, come back, and Notelore puts it in the box for you (you still tap *Connect*). On the free tier Google may use your requests to improve its products.
   - Beside it, for your own API key or a local model:
     - **Claude, GPT or Gemini:** paste an API key; numbered steps show where to get one, and a button opens the provider's key page in the browser. Keys stay in your device's keystore.
     - **Ollama** (desktop): start Ollama on this computer; no key needed.

   A key you set up before keeps working.
3. Talk to it: *"Mopsos için not al: veritabanı olarak SQLite seçtik."*
4. Ask it later: *"Mopsos'ta hangi veritabanını seçmiştik?"*

Notelore starts on the cheapest model your provider offers; switch any time with the model chip above the message box.

> [!TIP]
> Gemini is free with a key from a Google AI Studio project that has no billing, and Ollama is free too. Claude and GPT through their APIs are billed per use; a Claude Pro or Max subscription cannot be used in other apps.

## Using it

- **Its mark:** a note you talk to, a white card with a speech tail on lagoon teal; on Android it follows the system's themed icons.
- **On the desktop:** a side rail (with labels when the window is wide enough) replaces the phone's bottom bar, and the chat is a readable column.
- **Chat:** Notelore takes notes rather than making conversation: after you tell it something, it says in a sentence what it saved and in which note, and leaves it there (it still asks when it cannot tell where something belongs, and answers questions about your notes in full). While the assistant works, a playful line keeps you company ("went to make coffee"); *Stop* ends a turn. Offline, or over your provider's usage limit, a message waits ("Waiting to send") instead of failing: it is kept across restarts and goes out by itself when Notelore can reach the model again (on return to the app, every minute, or with *Try now*), in the order you wrote them. A question that names a project or topic ("what do my Notelore notes say about sync?") is answered from that note only. You can keep writing while it works: what you add joins its answer. A message you have not sent yet stays in the box when you visit another tab. When the assistant asks something with a few likely answers, they show as buttons under its question: one tap answers, and typing still works. The paperclip beside the message box attaches text files (txt, md, csv, logs and the like) and PDFs (their text, read on the device): type what they are about first if you like, and the assistant files their content into the right notes, asking when it is unclear where it belongs. Images (PNG, JPEG, GIF, WebP, up to 5 MB in one message) go to the model as pictures with ChatGPT, Claude, GPT and Gemini; Ollama says it cannot look at them. An image is sent only when nothing else is on its way, and never waits offline: if the network is gone, the message says to send it again, and no picture is kept on the device. A scanned PDF with no text in it and audio are refused with a note for now, and nothing is sent. A copy button under each message and answer puts its text on the clipboard. A button under your last message sends it again with one tap. When an answer fails, a short note says why in plain words (offline, a refused key, a busy or troubled service) with *Try again* right beside it; if that answer had already saved notes, the note says so, so nothing is saved twice. With ChatGPT, GPT or Claude it can look things up on the web when that helps get a note right (the author of a book you mention, say); turn it off in Settings. Anthropic bills each search.
- **Links:** send a link (paste it, or on Android use *Share → Notelore* from the browser or any app) and Notelore reads the page and files the link into the note it fits, with what you wrote about it taking precedence. It asks only when the page cannot be read or no note clearly fits, and never guesses what an unreadable page says. Only the page's text is read (a few links per message, with a size and time limit). The desktop has no share target: paste the link into the chat.
- **Voice:** one button next to the message box, like a messenger's: with text it sends, empty it records. Hold it and talk; let go and what you said is sent, and the answer is read aloud (by keyboard, hold Space on the focused button; a screen reader taps once to start and again to send). Typing still works. On first start Notelore downloads Whisper by itself in the background (about 375 MB, once per device; not bundled, so updates stay small; an interrupted download continues where it stopped). Whisper hears you on the device, offline, in any language; Settings shows the download and lets you pick the microphone (and list them again after plugging one in). Until it is there, voice mode uses the device's speech recognition (on Windows that needs the speech pack for your language, and Windows has no Turkish one). English product and technical terms in Turkish speech are written in their usual spelling ("deyta beys" becomes "database").
- **Related notes:** Things mentioned in passing, such as a book you are reading or a film to watch, go as entries into a collection note ("Books I'm reading"), not a note each, unless you ask for one. Before starting a new note, the assistant checks your projects and topics (both kinds) for one it belongs with, by shared title words and matching lines, and adds to that note instead. When two notes belong together, it suggests merging them and does so only after you agree: everything of the one note that the other lacks is added (duplicates once), and the merged note moves to `_archive/`, from where the *Archive* button restores it.
- **Notes:** browse your projects and topics; on a wide window the open note sits beside the list. Links in notes open in your browser. Deleting a note moves it to `_archive/` in the notes folder, with an Undo; the *Archive* button lists what was deleted and restores it (entries the assistant archived go back into their note).
- **Export, share and import:** an open note's share button exports it as Markdown (the note file itself, which Notelore can import again), PDF (set in Noto Sans, so every Turkish letter shows) or a web page (HTML). *Export notes* above the list does the same for several notes at once: one PDF or page for all, or one Markdown file each. On a phone the files go to the share sheet (WhatsApp, mail, Drive...); on the desktop to a file or folder you pick, never over a file already there. *Import notes* brings Markdown notes in, for example ones someone shared with you: a note whose name is taken comes in beside it as "<title> (2)", the same note again changes nothing, and anything that is not a Notelore note is refused. Import never overwrites a note.
- **Settings:** language (System, English or Türkçe), a theme from six nature palettes (lagoon, pine forest, open sea, sunset, lavender field, northern lights) in light or dark, model and usage, Google Drive, an optional app lock, and an About card with the version, updates and log out. On a wide window the sections (model, voice, sync, appearance, app lock, about) are listed on the left, one shown at a time. *Settings → Model* lists every model you connected on this device, the one in use marked: tap another to switch to it (its key is checked again), remove one you no longer want (asked first; your notes and the conversation stay), or *Connect another model* to run the setup wizard again. Removing the one in use leaves none until you pick one in the wizard.
- **Usage:** *Settings → Usage* shows the tokens the model used in this conversation and in total on this device, as the provider reported them, and an estimated cost from a small table of list prices (with the date they were taken). It is an estimate: your provider's bill is what counts. Where a provider or model gives nothing to go on, it says "not available" instead of guessing. The ChatGPT plan and a local Ollama model have no per-token charge.
- **App lock:** *Settings → App lock → Turn on* sets a PIN or password (at least 4 characters, typed twice) that Notelore asks for every time it opens, before any note or chat shows, and again when it comes back after a minute or more in the background (a quick switch to another app does not lock). After five wrong tries it makes you wait before the next one: 30 seconds, then a minute, then five minutes; the count survives a restart and resets on the right entry. Only a salted hash of it is kept, in the device's keystore; it is never stored as plain text and never synced. Turning it off asks for it first. The lock never touches your notes: if you forget it, they are still Markdown files in the app's storage and on Drive.
- **Google Drive:** setup starts with *Sign in with Google*: Notelore needs a Google (Gmail) account, any account Google lets you sign in with, Workspace included, and without one it goes no further. Signing in connects Drive, which backs your notes up to a `Notelore` folder and keeps every device in sync, settings too (language, theme, provider and model; never your keys). Notelore only sees the files it creates. After that the device opens without asking again, even offline; if access expires, the notes stay and *Settings → Google Drive → Connect* signs in again. Disconnecting signs out, and the next start asks for Google again. A build without Google sign-in (a development run without the client ids) skips this step and has no sync.

Your notes live in the app's own storage on every device (one copy, nothing for you to manage), and on Google Drive when you connect it. Updating from a version that kept them in a visible `~/Notelore/` folder moves them there once. Nothing is ever deleted for good: archived notes and both sides of a sync conflict are kept.

## Development

See [docs/development.md](docs/development.md).
