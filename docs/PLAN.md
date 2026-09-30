# Plan

Single roadmap. Tick items as PRs land; delete finished milestones once they are stable.

## M0 — Scaffold (done when CI is green on all three OS)

- [x] `uv sync`, `uv run pytest`, `uv run ruff check .`, `uv run mypy` all pass locally
- [x] CI green on ubuntu, windows, macos
- [x] `tests/conftest.py`: fixture that points `NOTELORE_HOME` at `tmp_path`

## M1 — Store (no LLM yet)

Everything here is pure, deterministic and fully unit-tested.

- [x] `paths.py`: `NOTELORE_HOME` override, `~/Notelore` + platformdirs defaults
- [x] `store/format.py`: parse and serialize the format in `docs/note-format.md`; byte-for-byte round-trip tests over `tests/fixtures/notes/` (include Turkish content, CRLF input normalization, unknown sections, empty sections)
- [x] `store/notes.py`: create note, append note entry, add/complete todo, record decision (supersedes previous), archive entry/file, slugging rules, atomic writes with Windows retry
- [ ] `store/index.py`: SQLite FTS5 index rebuilt from files (incremental by mtime + hash), `LIKE` fallback, `get_decision`, `decision_history`, `search`
- [x] `find_stale_notes` per the staleness signals (three signals; "entries marked outdated" needs a format marker first, see docs/note-format.md)

## M2 — Agent

- [ ] Port `providers/` from littlepress-ai (Anthropic, OpenAI, Gemini, Ollama; key validation; keyring storage; env override)
- [ ] `repl.py` with `prompt_toolkit`, slash commands: `/model`, `/logout`, `/help`, `/exit`
- [ ] `agent.py` tool-use loop, system prompt: ask when the project/topic is ambiguous, never invent facts, answer decisions from `get_decision`
- [ ] `tools.py` (below), each a thin wrapper over `store/`

### Agent tools

| Tool | Purpose |
|---|---|
| `list_notes(kind?)` | Projects/topics with title, slug, updated |
| `read_note(slug)` | Full parsed note |
| `create_note(kind, title, tags?)` | New project/topic file |
| `add_note_entry(slug, text)` | Append a dated note |
| `add_todo(slug, text, due?)` / `complete_todo(slug, id)` | Todos |
| `record_decision(slug, topic, value, reason?)` | New decision; supersedes the active one for that topic |
| `get_decision(slug, topic)` | Current decision (deterministic) |
| `decision_history(slug, topic?)` | All decisions incl. superseded |
| `search_notes(query, kind?)` | Full-text search |
| `find_stale_notes()` | Candidates for cleanup |
| `archive(slug, entry_ids?)` | Move entries or a whole file to `_archive/` (only after user confirmation in the conversation) |

No tool overwrites a file or deletes anything.

## M3 — Google Drive sync

- [ ] OAuth desktop flow (`google-auth-oauthlib`), scope `https://www.googleapis.com/auth/drive.file` only; token in keyring
- [ ] App creates a `Notelore` folder in Drive and mirrors the notes tree by relative path (`appProperties.relpath`)
- [ ] `sync/manifest.py`: per device, per file: last synced local hash, Drive file id, Drive `md5Checksum` and `modifiedTime`; plus a copy of the last synced content (merge base) in the state dir
- [ ] Sync on startup, after each write (debounced) and on `/sync`
- [ ] `sync/merge.py` decision table:
  - only local changed → push
  - only remote changed → pull
  - both changed, non-overlapping → automatic line-level three-way merge
  - both changed, same lines → LLM merges using base + both sides + dates, explains the result in one sentence; losing sides saved under `.notelore/history/`
  - file deleted on one side, changed on the other → keep the changed one
- [ ] Offline tolerant: failed sync never blocks note taking; retried on next trigger

Open question: ship a shared OAuth client ID with the app (needs Google brand verification for > 100 users; `drive.file` is a non-sensitive scope, so no security assessment) and also let users supply their own client ID via config.

## M4 — Release

- [ ] Python Semantic Release (reuse littlepress-ai's `release.yml` and `[tool.semantic_release]` config)
- [ ] Publish to PyPI; `uvx notelore` works on Windows and macOS
- [ ] README: install, first run, provider setup, Drive setup
- [x] Update check once a day + `notelore update` self-update for the packaged executables

## Later (not planned yet)

- Reminders (OS notifications from due todos)
- Embedding-based semantic search
- Desktop UI on top of the same core
