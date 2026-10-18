# Play Console: data safety answers

Prepared for the first Play release (#308). The source for every answer is [privacy.md](privacy.md). Review this again whenever a change adds a network destination or a permission.

## Data collection and security

- **Does the app collect or share any of the required user data types?** Yes. Play counts data sent off the device as "collected", even when it goes to services the user picks. Notelore runs no server.
- **Is all user data encrypted in transit?** Yes. Every destination is HTTPS, apart from a local Ollama on the user's own computer, which never leaves the device. On the phone, Ollama is not offered.
- **Can users request that their data be deleted?** Yes. The data lives on the device and in the user's own Google Drive. Uninstalling, or deleting the Notelore folder in Drive, removes it. The publisher holds no copy.

## Data types

| Play data type | Collected | Shared | Optional | Purpose | Note |
|---|---|---|---|---|---|
| Personal info → Email address | Yes | No | No | Account management | Google sign-in for Drive. Stays between the device and Google. |
| Messages → Other in-app messages | Yes | Yes | No | App functionality | Chat messages go to the AI provider the user chose. That's sharing with a third party, at the user's direction. |
| Files and docs | Yes | Yes | Yes | App functionality | Notes go to the user's Drive. Attached files' text goes to the chosen provider. |
| Photos and videos → Photos | Yes | Yes | Yes | App functionality | An image the user attaches goes to the chosen provider and is not kept. |
| Audio → Voice or sound recordings | No | No | Yes | App functionality | Whisper runs on the device. With the device recognizer instead, Android may send audio to Google: declare it as optional, processed by the system. |
| Web browsing | No | No | — | — | Only links the user sends are fetched, one request each, and only the page text is used. |
| App activity, App info and performance, Device or other IDs, Location, Financial, Health, Contacts, Calendar | No | No | — | — | No analytics, crash reporting or ads SDK. |

## Permissions to explain in the listing

- `RECORD_AUDIO`: voice mode, only while the talk button is held.
- `INTERNET`: the chosen AI provider, Google Drive, sign-in, reading linked pages, and the update check.
- Play builds have no `REQUEST_INSTALL_PACKAGES`: a Play build updates through Play (#307).

## Privacy policy URL

https://github.com/mfozmen/notelore/blob/main/docs/privacy.md

It is linked from *Settings → About → Privacy policy* in the app.
