# Notelore

An open-source, cross-platform (Windows, macOS; Linux best effort) note-taking assistant you talk to. You tell it things, an LLM turns them into tidy, human-readable Markdown notes on your disk, and later you ask it questions ("which database did we pick for project X?"). Notes are backed up to Google Drive through an in-app integration.

The user only chats. The LLM decides *what* to do; deterministic code decides *how* it is stored and what the facts are.

## Core invariants

These hold end-to-end. Any change that would break one needs explicit maintainer agreement.

1. **Markdown files are the single source of truth.** Everything else (SQLite search index, sync manifest, caches) is derived state that can be deleted and rebuilt from the notes folder at any time.
2. **Notes stay human-readable.** A person must be able to open any note in a plain text editor or Obsidian and understand it without Notelore. The format is specified in `docs/note-format.md`; the parser and writer must round-trip it losslessly.
3. **The LLM never rewrites a file wholesale.** Every write goes through narrow tools in `notelore.store` that append entries, mark decisions superseded, or move notes to the archive. There is no "overwrite file" tool.
4. **Deterministic questions get deterministic answers.** "What is the current decision for X?" is answered by the parser/index, not by the model reading free text. The model only picks the parameters and phrases the result.
5. **Every automated change is reversible.** Nothing is hard-deleted by the agent. Cleanup moves notes to `_archive/`; sync conflicts keep the losing version under `.notelore/history/`.
6. **Windows and macOS are first-class.** CI runs the full suite on Windows, macOS and Linux. A change that is green on one OS only is not done.

## Commands

```bash
uv sync                          # create .venv and install everything (incl. dev group)
uv run notelore                  # run the app
uv run pytest                    # tests (network disabled, live tests skipped)
uv run pytest -m live            # live provider/Drive tests (needs real keys, opt-in)
uv run ruff check . --fix        # lint
uv run ruff format .             # format
uv run mypy                      # type check (strict)
uv run pre-commit run --all-files
```

Use `uv` for everything. Never call `pip` directly. Add dependencies with `uv add <pkg>` (or `uv add --dev <pkg>`) so `uv.lock` stays in sync, and commit `uv.lock`.

### Flutter (the target stack, #60)

```bash
flutter pub get                                   # resolve the Dart workspace (one root pubspec.lock)
dart format .                                     # format (page width 100, analysis_options.yaml)
dart analyze --fatal-infos                        # strict analysis
(cd packages/notelore_core && dart run coverage:test_with_coverage)   # core tests + lcov
(cd apps/notelore && flutter test --coverage)                         # app tests + lcov
dart run tool/coverage_gate.dart packages/notelore_core/coverage/lcov.info apps/notelore/coverage/lcov.info
(cd apps/notelore && flutter build apk --debug)   # Android; also `windows`, `macos`
```

Add Dart dependencies with `dart pub add` (or `flutter pub add`) in the package that needs them; commit the root `pubspec.lock`.

## Architecture (target)

A monorepo. Every device (desktop, Android, later iOS) syncs the same notes through the same Drive folder, so the note format, merge rules and manifest must behave identically everywhere.

**Moving to Flutter (#60).** The target is one Dart codebase for Android, iOS, Windows and macOS: `packages/notelore_core` (pure Dart, no Flutter) and `apps/notelore` (the Flutter app), in a Dart pub workspace. The port goes one milestone at a time (#61–#70), test-first against the same fixtures in `spec/fixtures/notes`. Until it reaches parity, the Python packages below are the reference implementation; they are retired in #69. Do not add features to the Python side; port them.

```
packages/core/src/notelore/       notelore-core: shared by every app (import: notelore)
apps/cli/src/notelore_cli/        notelore: the desktop command (import: notelore_cli)
apps/mobile/                      Briefcase (BeeWare) app: Android now, iOS later (#50)
tests/                            mirrors both trees (tests/cli/ for the desktop app)
```

Core (`packages/core/src/notelore/`):

- `agent.py` — tool-use loop driving the active LLM.
- `tools.py` — the narrow tools exposed to the agent (see `docs/PLAN.md`). Tool contracts live in the module docstring.
- `providers/` — `LLMProvider` protocol + Anthropic, OpenAI, Gemini, Ollama implementations and key validation. The message translations were **ported from littlepress-ai** (`src/providers/llm.py`, `src/providers/validator.py`, same author, MIT). They talk plain HTTPS through `providers/http.py` (stdlib + certifi), never the vendor SDKs: those need pydantic-core/jiter, which have no Android/iOS wheels (#51).
- `store/format.py` — parse/serialize the note format. Pure functions, no I/O.
- `store/notes.py` — file operations on the notes folder: atomic writes, archive, slugging.
- `store/index.py` — SQLite (FTS5) index rebuilt from the files; decision lookups.
- `sync/engine.py` — one sync pass against a `Remote`; `sync/drive.py` — Google Drive client (scope `drive.file` only).
- `sync/manifest.py` — per-device record of last-synced state.
- `sync/merge.py` — three-way merge; `sync/resolve.py` — LLM fallback only for true same-line conflicts.
- `paths.py` — every filesystem location comes from here (see Development environment).
- `secrets.py` — API keys and OAuth tokens via `keyring`; environment variables override for dev/CI.
- `i18n.py` — structural strings (section headings, prompts) in English + Turkish; English fallback.

Desktop app (`apps/cli/src/notelore_cli/`):

- `cli.py` — `notelore` console entry point.
- `repl.py` — read loop, slash commands (`/model`, `/sync`, `/logout`, `/help`, `/exit`), provider picker.
- `update.py` — daily update check and checksum-verified self-update of the packaged executables.

Dependencies point one way: apps import the core, the core never imports an app.

## Development environment

### Never touch real user data

All paths are resolved in `notelore.paths`. Nothing else may build a path to user data.

- `NOTELORE_HOME` overrides the root for **everything** (notes folder, state dir, index). If it is relative, resolve it against the current working directory.
- `.claude/settings.json` sets `NOTELORE_HOME=.dev-home` for Claude Code sessions, so manual runs during development write into the gitignored `.dev-home/`, never into the maintainer's real notes.
- Without the override: notes go to `~/Notelore/` (visible on purpose, the user opens it in other tools); state (index, manifest, sync base copies) goes to `platformdirs.user_data_dir("notelore")`.
- Tests always use `tmp_path` and set `NOTELORE_HOME` through a fixture in `tests/conftest.py`.

### No network in tests

`pytest-socket` disables sockets for the whole suite. Provider and Drive code is tested against fakes. Real API tests are marked `@pytest.mark.live` plus `@pytest.mark.enable_socket`, are skipped by default, and read keys from env vars (`NOTELORE_ANTHROPIC_API_KEY`, `NOTELORE_OPENAI_API_KEY`, `NOTELORE_GEMINI_API_KEY`). Use a dedicated Drive test folder for live Drive tests, never the real one.

### Cross-platform rules

- `pathlib` only; no string path concatenation (ruff `PTH` rules enforce this).
- Always read/write text with `encoding="utf-8"`; write with `newline="\n"` so notes are byte-identical on every OS (this matters for sync hashes).
- Atomic writes: write to a temp file in the same directory, `fsync`, then `os.replace`. On Windows `os.replace` can fail with `PermissionError` if another process (antivirus, Obsidian) holds the file; retry briefly with backoff.
- Filenames: lowercase ASCII slugs (Turkish characters transliterated, e.g. `ş→s`, `ı→i`), no Windows-reserved names (`con`, `prn`, `aux`, `nul`, `com1`...) or characters `<>:"/\|?*`, max ~100 chars. macOS and Windows filesystems are case-insensitive: two titles that differ only in case map to the same file.
- Normalize all text to Unicode NFC before hashing or comparing (macOS may hand back NFD).
- Dates in notes: local calendar date `YYYY-MM-DD`. Machine timestamps: timezone-aware UTC.
- No shell-specific subprocess calls. Open URLs with `webbrowser`, not `open`/`start`.
- Verify SQLite FTS5 availability at startup; fall back to `LIKE` search if missing (there is a test for both paths).

## Testing (TDD)

All new production code is written test-first: RED (one minimal failing test, watch it fail for the right reason) → GREEN (minimal code) → REFACTOR (tests stay green).

- Tests mirror the source tree (`packages/core/src/notelore/store/format.py` → `tests/store/test_format.py`, `apps/cli/src/notelore_cli/repl.py` → `tests/cli/test_repl.py`).
- Prefer real code and real files in `tmp_path`; mock only external services (LLM APIs, Drive).
- Bug fixes start with a regression test.
- The note format has round-trip tests: parse → serialize must return identical bytes for every fixture in `spec/fixtures/notes/`. `spec/` is the cross-implementation contract: `spec/fixtures/front-matter.json` (how PyYAML writes and reads front-matter values) `spec/fixtures/parsed.json` (the reference parse of every fixture) and `spec/fixtures/merge.json` (how the reference three-way merge cuts clean parts and conflicts) are generated by `spec/tools/` from the Python reference; the Dart port is tested against them.

## Language

All code, comments, docs, commit messages and CLI output are in English. The maintainer chats in Turkish; that does not leak into the repo. Exceptions: Turkish test fixtures (when testing non-ASCII handling) and the structured translation table in `i18n.py`.

At runtime, the agent answers in the language the user writes in, and writes note *content* in that language. Structural headings come from `i18n.py`; the parser accepts every known variant.

## Workflow

- **Commits:** Conventional Commits (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`). CI config changes are `ci:`.
- **Branches:** one branch per feature/fix, `<type>/<slug>` (e.g. `feat/note-format-parser`), merged via PR with summary, context and test plan. `main` is protected by a repository ruleset: every change goes through a PR (docs too), the lint, test matrix, SonarCloud and claude-review checks must pass, and force-push and deletion are blocked. The only bypass is the release deploy key (`RELEASE_DEPLOY_KEY`), which the manual release workflow uses to push its version commit and tag.
- **README stays current:** any user-visible change updates `README.md` in the same PR.
- **Plan:** `docs/PLAN.md` is the single roadmap. Tick items off as PRs land; keep it short.

## Platform

Maintainer develops on Windows 11 (bash shell) and also runs on macOS.
