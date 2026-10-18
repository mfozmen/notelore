# Notelore privacy policy

Last updated: 2026-10-18

Notelore is an open-source note-taking assistant (https://github.com/mfozmen/notelore). This page says what data it handles, where that data goes and why. The publisher runs no server of its own: Notelore never sends anything to us.

## In short

- Your notes are Markdown files on your device and, if you connect it, in your own Google Drive.
- What you write or say in the chat goes to the AI model you choose. It is sent so that model can answer, and only then.
- There are no analytics, no ads, no tracking and no crash reporting.
- Keys, sign-ins and the app lock stay in your device's keystore. They are never in your notes or on Drive.

## What Notelore stores on your device

- **Notes:** Markdown files in the app's own storage.
- **App state:** a search index rebuilt from the notes, the sync record, the current conversation, messages waiting to be sent, and your settings.
- **Secrets, in the platform keystore** (Android Keystore, Windows Credential Locker, macOS Keychain):
  - the API keys you enter;
  - the Google and ChatGPT sign-in tokens;
  - the app lock's salted hash.
- **Usage:** token counts reported by your provider, to show cost estimates.

Android's own backup and phone-to-phone transfer take nothing from Notelore. Google Drive is the only backup.

## Where data goes, and why

| Destination | What is sent | When |
|---|---|---|
| **Your chosen AI provider:** Anthropic (Claude), OpenAI (GPT, or your ChatGPT plan), or Google (Gemini) | Your message; the text of files you attach; images you attach; the text of web pages you link to; notes the assistant reads to answer; the assistant's instructions | Each time you send a message. Also once when you connect a model, as a short test ("say hello"). |
| **Ollama** (desktop, optional) | The same as above | Only to the Ollama server on your own computer. Nothing leaves the device. |
| **Google Drive** (your account) | Your notes, plus the app settings shared between your devices | On every sync, to a folder Notelore creates. With the `drive.file` permission, Notelore sees only files it created itself. |
| **Google sign-in** | The standard sign-in exchange | When you sign in, and when a token is refreshed |
| **OpenAI sign-in** (ChatGPT plan, optional) | The standard sign-in exchange | When you sign in, and when a token is refreshed |
| **Web pages you link to** | One request for the page | When a message contains a link. Only public http(s) pages are fetched; Notelore never requests addresses on your device or local network. |
| **GitHub** (`api.github.com`) | A request for the latest release | At start, to check for updates. On the desktop it also downloads a new version when you ask for one. |
| **Hugging Face** | A download of the Whisper speech model (about 375 MB) | Once per device, for voice mode |

Each provider handles what it receives under its own terms and privacy policy. These say whether it keeps your data or uses it to improve its products. Notably, **Gemini's free tier may use your requests to improve Google's products**, as the setup screen tells you before you choose it. As of October 2026, Anthropic and OpenAI say they do not train on what is sent with an API key by default, and through your ChatGPT plan your ChatGPT data controls apply. Their own policies are what counts, and they can change.

## The microphone and speech

Voice mode uses the microphone only while you hold the talk button (or, with a screen reader, between two taps).
- **Whisper** turns speech into text on your device, offline. The audio leaves nothing behind and is never sent anywhere.
- Until Whisper is downloaded, voice mode uses your device's own speech recognition. On some devices, Android's recognizer sends the audio to Google, under Google's terms.
- Answers read aloud use your device's text-to-speech.

Only the recognized text goes to your AI provider, like a typed message.

## Images and attachments

Files you attach are read on your device. Only their text, or the image itself for an image, is sent to your provider with that message. Notelore keeps no copy of an attached image. Pictures written into a note are never loaded from the web.

## Your choices

- Choose which provider, if any, gets your messages. You can switch or remove one in *Settings → Model* at any time. With no model connected, nothing is sent.
- Use Ollama on a desktop to keep everything on your computer.
- Disconnect Google Drive by logging out (*Settings → About → Log out*). Your notes stay on the device and in your Drive.
- Delete everything by uninstalling the app and, if you used it, deleting the Notelore folder in your Google Drive.

## Children

Notelore is not directed at children under 13.

## Changes

Changes to this policy are made in this file, and their history is public in the repository.

## Contact

Open an issue at https://github.com/mfozmen/notelore/issues.
