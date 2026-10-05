# CHANGELOG

<!-- version list -->

## v0.3.0 (2026-10-05)

### Bug Fixes

- A failed reconnect restores the previous key
  ([`97f6e5d`](https://github.com/mfozmen/notelore/commit/97f6e5d29dcaa9d7874976094f4dce0aee16634a))

- Allow hand-made note file names, reject only path escapes
  ([`b0a6cc3`](https://github.com/mfozmen/notelore/commit/b0a6cc3bc7d1c331328590a29dc5180d4a8c2a07))

- Close a session that finishes opening after the app is gone
  ([`b9609fb`](https://github.com/mfozmen/notelore/commit/b9609fbcb276614d9e028f4a1bc0e264ec5c1e65))

- Close the review follow-ups from merged PRs
  ([`ad54d38`](https://github.com/mfozmen/notelore/commit/ad54d38277b1a1c7d35e50ef4b8d3df8f62fa419))

- Drop half-built tool_use blocks and reject non-object tool input
  ([`1f060d1`](https://github.com/mfozmen/notelore/commit/1f060d1c18c47f58e0a88e64101543cd6fdb6b67))

- Drop unsafe manifest entries on load, treat damaged base copies as missing
  ([`6d5aab6`](https://github.com/mfozmen/notelore/commit/6d5aab646b1303bcd4d376453d6927a1bf5968e9))

- Index review findings
  ([`87eab56`](https://github.com/mfozmen/notelore/commit/87eab56e53608e566e4f90865ef2ed81d65c089b))

- Keep notelore-core out of the mobile app's pip requirements
  ([`975d11b`](https://github.com/mfozmen/notelore/commit/975d11b170b605050a190a68623a63e753d2015f))

- Keep the spike check out of the user's notes, pin Briefcase
  ([`ad42d3d`](https://github.com/mfozmen/notelore/commit/ad42d3ddaf2f5d43ef9638ef859d422dd081d20e))

- Keep user and assistant turns alternating after an empty answer or max_turns
  ([`49f438f`](https://github.com/mfozmen/notelore/commit/49f438f1c23c3aee6455f243a565d82e2fdc3ce2))

- Key coverage gaps by report, map Dart lcov paths for Sonar, pin Flutter once
  ([`83d03aa`](https://github.com/mfozmen/notelore/commit/83d03aa46f40ee15b6d472de65b9ce8f40580fc9))

- Name the Briefcase app notelore-mobile so it does not shadow the core
  ([`7db0885`](https://github.com/mfozmen/notelore/commit/7db0885fca47bd7ea6e11a920f170327afcdec66))

- Never keep a key whose provider settings could not be saved
  ([`32ee2b2`](https://github.com/mfozmen/notelore/commit/32ee2b273db6bb1eb80578ce71efd5a85dc68282))

- NFC and case-safe sync keys, per-file decode errors, upload-first merges
  ([`3567d5c`](https://github.com/mfozmen/notelore/commit/3567d5cdaa9db69eeaf1c00ff9c844f96d11465d))

- NFC-normalize decision topics before matching
  ([`39de52a`](https://github.com/mfozmen/notelore/commit/39de52a9589def381e9126e6504a0a758dd9640a))

- NFC-normalize model merges and surface deletions in the explanation
  ([`d4a140f`](https://github.com/mfozmen/notelore/commit/d4a140fe8917df5db76f5a05876bf7f0bbb620c0))

- Normalize decision input, NFC on write, position-based todo and archive edits
  ([`b37f75b`](https://github.com/mfozmen/notelore/commit/b37f75bc72bbe1438fca495218a2884367364aff))

- Offline token refresh, stray loopback requests, held notes
  ([`fc80e21`](https://github.com/mfozmen/notelore/commit/fc80e21ca0ff010ab0610a5269ed0d2c0720b6b4))

- Reject an empty checksum file, say what the checksum protects against
  ([`1c14b19`](https://github.com/mfozmen/notelore/commit/1c14b1923cb3841d387611c44eab141c5b6caa9b))

- Reject non-canonical slugs so a model-supplied slug cannot leave the notes folder
  ([`2aecf70`](https://github.com/mfozmen/notelore/commit/2aecf708dff0778213b616d742f9498b80fd2c29))

- Report Anthropic early stops, whitelist block fields, compare finish_reason to None
  ([`6075736`](https://github.com/mfozmen/notelore/commit/6075736fd2ea51171b44c859f5204214cd41807b))

- Roll back a failed agent turn; harden tool schemas
  ([`ce58edd`](https://github.com/mfozmen/notelore/commit/ce58eddea0a467def7f2be6ca9d2d857b873059d))

- Roll back a failed index rebuild; forbid CR in slugs
  ([`24a3656`](https://github.com/mfozmen/notelore/commit/24a3656a9fd04cab62c603bc89afd899eeddf574))

- Roll back a failed macOS bundle swap; clearer update failures
  ([`a032fbb`](https://github.com/mfozmen/notelore/commit/a032fbb6e093988d8eb2156e91cedcd3442fac97))

- The app owns and closes its session; review findings
  ([`816cb3b`](https://github.com/mfozmen/notelore/commit/816cb3bbd9d3a50f201a8a95fef60dcd780203e0))

- Treat a non-JSON success page as an HTTPError
  ([`e45f14c`](https://github.com/mfozmen/notelore/commit/e45f14c0a1b08f842837a48afec6b876fa1d0ad4))

- Use the Briefcase template's default Android theme
  ([`9e1a4c4`](https://github.com/mfozmen/notelore/commit/9e1a4c4b9e255ff29099c3b6fc083d1f9a23ad57))

- Validate nested tool arguments, create temp notes without chmod
  ([`f10d642`](https://github.com/mfozmen/notelore/commit/f10d642a4e275fe3e4b58aa425fce99f12bcd3ae))

### Build System

- Flutter workspace with a pure-Dart core and the Flutter app, CI on three OSes
  ([`ab8078f`](https://github.com/mfozmen/notelore/commit/ab8078f5fed131167374d682227fc612e6345e6d))

- Monorepo as a uv workspace with packages/core and apps/cli
  ([`dc05da3`](https://github.com/mfozmen/notelore/commit/dc05da30d4a1ef63419631e30ecef830b7cc2f34))

### Chores

- Retire the Python packages
  ([`a7f08b6`](https://github.com/mfozmen/notelore/commit/a7f08b6698935dbf0f4ec1f3d59660efb016d42e))

### Continuous Integration

- Bump the pinned actions to their latest majors
  ([`16f2b56`](https://github.com/mfozmen/notelore/commit/16f2b56a849bb417a47e1ce2611dbb7455747812))

- Cut releases only on manual dispatch
  ([`0ce10b6`](https://github.com/mfozmen/notelore/commit/0ce10b6dcc8235914afed00d41f1c86b4cfdfa5c))

- Fail loudly when the review range git log fails, test it on a real repo
  ([`ce8af30`](https://github.com/mfozmen/notelore/commit/ce8af3082a5986b3829db7207c2a761cbb461905))

- Incremental Claude review, only commits since the last reviewed head
  ([`7a63e0a`](https://github.com/mfozmen/notelore/commit/7a63e0a863c0674294bb1e676e583be4908458fb))

- Make the release push atomic and re-runnable
  ([`f4b4309`](https://github.com/mfozmen/notelore/commit/f4b43098b09d537da92e75c98d1df5e1c83d6a7d))

- Pin every action to a commit SHA, build Dart coverage outside the Sonar job
  ([`88c5964`](https://github.com/mfozmen/notelore/commit/88c596414b139a7e1246f26cdca8a8065ee3ffa3))

- Print the app's logcat lines in the Android smoke job
  ([`2b23a5e`](https://github.com/mfozmen/notelore/commit/2b23a5ef50fc85b34ab818792572ec13777713fd))

- Push release commits with a deploy key now that main is protected
  ([`980ab38`](https://github.com/mfozmen/notelore/commit/980ab385904cdbea08d096d268d779bc6ab2fe07))

- Put the Sonar comment back above the Sonar job
  ([`266b96d`](https://github.com/mfozmen/notelore/commit/266b96de93324e0587bce2d666e9b6ce6d71a8c0))

- Resolve Dart packages before the SonarCloud scan
  ([`8e59213`](https://github.com/mfozmen/notelore/commit/8e59213c28f93774af2886fafe3039d36224b637))

- Run the Android APK on an emulator and check the core diagnostics
  ([`95ede88`](https://github.com/mfozmen/notelore/commit/95ede8813c47c43781e5e27cef06e6efa2cde137))

### Documentation

- Defer iOS until a Mac and an iOS device are available
  ([`9be599d`](https://github.com/mfozmen/notelore/commit/9be599ddf8ab144c604c427a465cb492d79761a4))

### Features

- Agent tool-use loop with the system prompt rules
  ([`047027b`](https://github.com/mfozmen/notelore/commit/047027b9061fee9dbd6f4727be00ee6888bf5492))

- Agent tools as thin wrappers over the store
  ([`8691691`](https://github.com/mfozmen/notelore/commit/8691691ce5cb2bfbde27d8bb70cdec5b5babce73))

- Android spike, Briefcase app on the shared core with an APK in CI
  ([`dbb2a11`](https://github.com/mfozmen/notelore/commit/dbb2a1111993994729f42ddef2dd45ca6c604ffd))

- Find_stale_notes with the three deterministic staleness signals
  ([`f4cda0d`](https://github.com/mfozmen/notelore/commit/f4cda0d3300d6deebf3bf086b05526c51e11999f))

- Google Drive sign-in and sync in the app
  ([`5f8d5b8`](https://github.com/mfozmen/notelore/commit/5f8d5b83dcab4af202786f25ab10e9cde9f28fb1))

- LLM providers over plain HTTPS, no vendor SDKs
  ([`8cd02cf`](https://github.com/mfozmen/notelore/commit/8cd02cf8504b9b30f8aab72ae7a501599ad4d487))

- LLM providers ported from littlepress-ai with key validation and keyring secrets
  ([`127827d`](https://github.com/mfozmen/notelore/commit/127827d48c948ba83b01ec3558f5cc04afa7afac))

- LLM providers, agent loop and note tools in Dart
  ([`1671f9b`](https://github.com/mfozmen/notelore/commit/1671f9b95b2dfcb2b6f2e33e1e3b7e294fe36747))

- Model resolver for true same-line sync conflicts
  ([`b479a23`](https://github.com/mfozmen/notelore/commit/b479a236f9e00f154b928e2313bd973ba772ae58))

- Note file operations with atomic writes, slugs and archive
  ([`e088e27`](https://github.com/mfozmen/notelore/commit/e088e271a434a8cab8107798be3924dfebe7c0da))

- Note format, front matter, paths and i18n in Dart
  ([`4c2f133`](https://github.com/mfozmen/notelore/commit/4c2f1339a494b4d6d15c6732ff8d85f582e36e66))

- Release the app and update it in place on the desktop
  ([`d11bd51`](https://github.com/mfozmen/notelore/commit/d11bd51b940da95c74783189c7b457193986b75e))

- REPL with provider picker, key entry and slash commands
  ([`625508f`](https://github.com/mfozmen/notelore/commit/625508f579c5aa30fb72cfa2d7c91536c69798f5))

- SQLite index with FTS5 search, LIKE fallback and decision lookups
  ([`38c20d1`](https://github.com/mfozmen/notelore/commit/38c20d1bc480b02245a08c90f1c5a0b0a2fd17b6))

- Store, search index and stale notes in Dart
  ([`694e4e1`](https://github.com/mfozmen/notelore/commit/694e4e1eaebf2b99cc8f0ca918ea819421d72427))

- Sync decision table and three-way line merge
  ([`8f9df5c`](https://github.com/mfozmen/notelore/commit/8f9df5cd3fabc4c54fa4f41d4e626e98485e162b))

- Sync engine against a Remote protocol
  ([`500f849`](https://github.com/mfozmen/notelore/commit/500f849336624212af753dd98763b63de2b69444))

- Sync manifest with merge-base copies in the state dir
  ([`8a67a33`](https://github.com/mfozmen/notelore/commit/8a67a3366f4850a22d1c352998f75678a870b492))

- Sync merge, manifest, engine and model resolver in Dart
  ([`c2dba6e`](https://github.com/mfozmen/notelore/commit/c2dba6e56caa770a11e2aa1c3d47be8446ddcd5c))

- The Flutter app UI: setup, chat, notes and settings
  ([`2914866`](https://github.com/mfozmen/notelore/commit/2914866e9a5a1cbfeee8fcfe65635b7671a6d343))

- Verify self-updates against a published SHA-256
  ([`d9b6d4d`](https://github.com/mfozmen/notelore/commit/d9b6d4d647154182281c3e4c13977ef426568d6f))

### Refactoring

- Split the difflib port into matching blocks and longest match
  ([`fccf717`](https://github.com/mfozmen/notelore/commit/fccf717d62a03ba46cb2b92296964dac01337313))

### Testing

- A stray line in a section does not shift stale entry numbers
  ([`3c65d7e`](https://github.com/mfozmen/notelore/commit/3c65d7e22b7b0209d5751546f51b3a2b7637fdab))

- Dates are ASCII digits in both implementations; check year 0 first
  ([`92d2e71`](https://github.com/mfozmen/notelore/commit/92d2e714487cb4a03c3c8dda52d088353fc5b8c0))

- Use itertools.pairwise for the alternation check
  ([`65f7faa`](https://github.com/mfozmen/notelore/commit/65f7faa7cb2c342eab7d374236e43bd1cf6b805c))

### Breaking Changes

- The command-line app is gone; releases carry only the app for Windows, macOS and Android. The app
  reads the same ~/Notelore.


## v0.2.0 (2026-09-30)

### Bug Fixes

- Keep the update check silent and the executable swap safe
  ([`967bc7c`](https://github.com/mfozmen/notelore/commit/967bc7c8c89cd77e0512573ba9d28b6803f81b9d))

- Tolerate a locked .old executable and drop the download on a failed swap
  ([`53a0bf4`](https://github.com/mfozmen/notelore/commit/53a0bf475b349ac7edaa3c446564896d7b100ae0))

### Features

- Daily update check and notelore update self-update
  ([`93ee126`](https://github.com/mfozmen/notelore/commit/93ee1261d3f92dc212176bdc438a0bc942457f34))

### Testing

- Enforce 100% line and branch coverage
  ([`7891139`](https://github.com/mfozmen/notelore/commit/78911397d8e25f982cc6c18448681b90b023b914))


## v0.1.0 (2026-09-30)

### Bug Fixes

- Reject non-mapping or title-less front matter with ValueError
  ([`0db9c68`](https://github.com/mfozmen/notelore/commit/0db9c68c891bfd834b25a8c6943a282d2b03e178))

### Build System

- Read the version from __init__.py only
  ([`598fdfb`](https://github.com/mfozmen/notelore/commit/598fdfb4891bd42d94ea2f2059a696e23a79da9f))

### Documentation

- Tick M0 CI green in the plan
  ([`e7f36c4`](https://github.com/mfozmen/notelore/commit/e7f36c496567244e3126e668c58e8ad9039fc5ed))

### Features

- Paths and note format parser/serializer
  ([`d382556`](https://github.com/mfozmen/notelore/commit/d382556e77e4d38d4e380dddf98c81fffc328475))


## v0.0.0 (2026-09-30)

- Initial Release
