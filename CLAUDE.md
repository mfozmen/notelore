# Notelore

An open-source note-taking assistant you talk to, on Windows, macOS and Android (iOS next). You tell it things, an LLM turns them into tidy, human-readable Markdown notes on your disk, and later you ask it questions ("which database did we pick for project X?"). Notes are backed up to Google Drive, and every device syncs through it.

The user only chats. The LLM decides *what* to do; deterministic code decides *how* it is stored and what the facts are.

## Core invariants

These hold end-to-end. Any change that would break one needs explicit maintainer agreement.

1. **Markdown files are the single source of truth.** Everything else (SQLite search index, sync manifest, caches) is derived state that can be deleted and rebuilt from the notes folder at any time.
2. **Notes stay human-readable.** A person must be able to open any note in a plain text editor or Obsidian and understand it without Notelore. The format is specified in `docs/note-format.md`; the parser and writer must round-trip it losslessly.
3. **The LLM never rewrites a file wholesale.** Every write goes through narrow tools over the store (`packages/notelore_core/lib/src/store/`) that append entries, mark decisions superseded, or move notes to the archive. There is no "overwrite file" tool.
4. **Deterministic questions get deterministic answers.** "What is the current decision for X?" is answered by the parser/index, not by the model reading free text. The model only picks the parameters and phrases the result.
5. **Every automated change is reversible.** Nothing is hard-deleted by the agent. Cleanup moves notes to `_archive/`; sync conflicts keep the losing version under `.notelore/history/`; Drive files go to the trash.
6. **Every platform is first-class.** CI runs the full suite on Windows, macOS and Linux and builds the Android, Windows and macOS app. A change that is green on one OS only is not done.

## Commands

```bash
flutter pub get                                   # resolve the Dart workspace (one root pubspec.lock)
dart format .                                     # format (page width 100, analysis_options.yaml)
dart analyze --fatal-infos                        # strict analysis
(cd packages/notelore_core && dart run coverage:test_with_coverage)   # core tests + lcov
(cd apps/notelore && flutter test --coverage)                         # app tests + lcov
(cd packages/notelore_core && dart test -t live)                       # live provider tests (keys in env, opt-in)
dart run tool/coverage_gate.dart packages/notelore_core/coverage/lcov.info apps/notelore/coverage/lcov.info
(cd apps/notelore && flutter run --dart-define-from-file=../../.env)  # run the app, with Drive sign-in
(cd apps/notelore && flutter build apk --debug)   # Android; also `windows`, `macos`
```

Add dependencies with `dart pub add` (or `flutter pub add`) in the package that needs them; commit the root `pubspec.lock`. On Windows, local plugin builds need Developer Mode (symlinks).

## Architecture

A monorepo and a Dart pub workspace. Every device syncs the same notes through the same Drive folder, so the note format, merge rules and manifest behave identically everywhere.

```
packages/notelore_core/   pure Dart, no Flutter: everything that is not UI
apps/notelore/            the Flutter app: Android, iOS, Windows, macOS
spec/fixtures/            the frozen cross-implementation contract (see Testing)
tool/                     the coverage gate
```

Core (`packages/notelore_core/lib/src/`):

- `paths.dart`: every filesystem location comes from here (see Development environment).
- `i18n.dart`: structural strings (section headings) in English and Turkish; English fallback.
- `text.dart`: Python-compatible line splitting, so notes split the same everywhere.
- `store/front_matter.dart`, `store/format.dart`: parse/serialize the note format. Pure functions, no I/O. The YAML front matter is written byte for byte like the original reference (PyYAML).
- `store/notes.dart`: file operations on the notes folder: atomic writes, archive, slugging.
- `store/index.dart`: SQLite index (FTS5, `LIKE` fallback) rebuilt from the files; decision lookups.
- `store/stale.dart`: deterministic cleanup candidates.
- `providers/`: one `LlmProvider` interface over Anthropic, OpenAI, Gemini and Ollama, plain HTTPS through an injectable `Transport`, and key validation by listing models.
- `agent.dart`: the tool-use loop; `tools.dart`: the narrow tools the agent may call (contracts in the library doc).
- `sync/merge.dart`: decision table and three-way merge (a port of difflib); `sync/resolve.dart`: the model as last resort for same-line conflicts; `sync/manifest.dart`: per-device record of the last synced state; `sync/engine.dart`: one sync pass against a `Remote`.
- `sync/drive.dart`: Google Drive as the `Remote` (scope `drive.file` only); `sync/google_auth.dart`: `DriveAuth` and the desktop loopback sign-in.

App (`apps/notelore/lib/`):

- `main.dart`: opens the session on the platform folders.
- `src/session.dart`: what the screens share: provider and key, agent, conversation, notes, Drive sync (one queue for chat turns and syncs).
- `src/drive_auth.dart`: google_sign_in on phones, the loopback flow on the desktop.
- `src/update.dart`: daily update check and checksum-verified self-update of the desktop app.
- `src/app.dart`, `setup.dart`, `chat.dart`, `notes.dart`, `settings.dart`: the screens.

Dependencies point one way: the app imports the core, the core never imports Flutter or the app.

## Development environment

### Never touch real user data

All paths are resolved in `NotelorePaths` (`paths.dart`). Nothing else may build a path to user data.

- `NOTELORE_HOME` overrides the root for **everything** (notes folder, state dir, index). If it is relative, resolve it against the current working directory. A run with it also uses its own keystore entries (`notelore-dev.*`), so it never reads or overwrites the real app's keys.
- `.claude/settings.json` sets `NOTELORE_HOME=.dev-home` for Claude Code sessions, so manual runs during development write into the gitignored `.dev-home/`, never into the maintainer's real notes.
- Without the override: on the desktop the notes go to a visible `~/Notelore/` (the user opens it in other tools); on a phone to the app's documents. State (index, manifest, sync base copies, settings) goes to the app support folder.
- Tests always use temp folders.

### No network in tests

Provider and Drive code is tested against fakes: an injectable `Transport`, `MockClient`, an in-memory Drive, loopback servers on 127.0.0.1. Real API tests are tagged `live`, skip themselves unless their key is in the environment (`NOTELORE_ANTHROPIC_API_KEY`, `NOTELORE_OPENAI_API_KEY`, `NOTELORE_GEMINI_API_KEY`), and run with `dart test -t live`. Use a dedicated Drive test folder for live Drive tests, never the real one.

### Secrets

The Google OAuth client ids are never committed. Locally they live in the gitignored `.env` (`NOTELORE_GOOGLE_CLIENT_ID`, `NOTELORE_GOOGLE_CLIENT_SECRET`, `NOTELORE_GOOGLE_WEB_CLIENT_ID`) and reach the app through `--dart-define-from-file`. For releases they come from GitHub secrets of the same names, like the Android release key (`NOTELORE_ANDROID_*`). API keys and Google refresh tokens live in the platform keystore (`flutter_secure_storage`).

### Cross-platform rules

- `package:path` for every path; no string concatenation of paths.
- Read and write note text as UTF-8 with `\n` line endings, so notes are byte-identical on every OS (this matters for sync hashes).
- Atomic writes: write to a temp file in the same directory, flush, then rename. On Windows the rename can fail while another process (antivirus, Obsidian) holds the file; retry briefly with backoff (`moveWithRetry`).
- Filenames: lowercase ASCII slugs (Turkish characters transliterated, e.g. `ş→s`, `ı→i`), no Windows-reserved names (`con`, `prn`, `aux`, `nul`, `com1`...) or characters `<>:"/\|?*`, max ~100 chars. macOS and Windows filesystems are case-insensitive: two titles that differ only in case map to the same file.
- Normalize all text to Unicode NFC before hashing or comparing (macOS may hand back NFD).
- Dates in notes: local calendar date `YYYY-MM-DD`. Machine timestamps: timezone-aware UTC.
- Open URLs with `url_launcher`. Platform tools (`tar`, `ditto`) only where the platform is known, and injectable for tests.
- SQLite comes bundled with FTS5 (`sqlite3` package); the `LIKE` fallback stays tested.

## Testing (TDD)

All new production code is written test-first: RED (one minimal failing test, watch it fail for the right reason) → GREEN (minimal code) → REFACTOR (tests stay green). Line coverage is 100% for both packages, enforced by `tool/coverage_gate.dart` in CI and tracked in SonarCloud.

- Tests mirror the source tree (`lib/src/store/format.dart` → `test/store/format_test.dart`).
- Prefer real code and real files in temp folders; fake only external services (LLM APIs, Drive, Google sign-in, path_provider).
- Bug fixes start with a regression test.
- `spec/fixtures/` is the frozen contract from the original Python reference: `notes/` (byte-for-byte round trip, including CRLF and Turkish), `front-matter.json` (how PyYAML wrote and read front-matter values), `parsed.json` (the reference parse of every note) and `merge.json` (how the reference three-way merge cut clean parts and conflicts). Change a fixture only together with a deliberate format change.

## Language

All code, comments, docs, commit messages and app text are in English. The maintainer chats in Turkish; that does not leak into the repo. Exceptions: Turkish test fixtures (when testing non-ASCII handling) and the translation table in `i18n.dart`.

At runtime, the agent answers in the language the user writes in, and writes note *content* in that language. Structural headings come from `i18n.dart`; the parser accepts every known variant.

## Workflow

- **Commits:** Conventional Commits (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`). CI config changes are `ci:`.
- **Branches:** one branch per feature/fix, `<type>/<slug>` (e.g. `feat/note-format-parser`), merged via PR with summary, context and test plan. `main` is protected by a repository ruleset: every change goes through a PR (docs too), the Flutter, CI script, SonarCloud and claude-review checks must pass, and force-push and deletion are blocked. The only bypass is the release deploy key (`RELEASE_DEPLOY_KEY`), which the manual release workflow uses to push its version commit and tag.
- **Releases:** manual (`gh workflow run release.yml`). Python Semantic Release (configured in `releaserc.toml`) bumps both pubspec versions from the Conventional Commits; the workflow builds and attaches the app for Windows, macOS and Android with SHA-256 files.
- **README stays current:** any user-visible change updates `README.md` in the same PR.
- **Plan:** `docs/PLAN.md` is the single roadmap. Tick items off as PRs land; keep it short.

## Platform

Maintainer develops on Windows 11 (bash shell) and also runs on macOS.
