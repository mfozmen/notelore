# Notelore

**Your personal lore, kept by an LLM.**

Tell it things. It writes tidy, human-readable Markdown notes on your disk. Ask it later: *"Which database did we pick for Mopsos?"* It answers from your notes, and backs them up to Google Drive.

- Local-first: plain Markdown files you can open in any editor or Obsidian
- Bring your own model: Claude, GPT, Gemini, or a local model via Ollama
- Decisions are tracked with history, so "what did we decide?" has one correct answer
- Windows and macOS

> **Status:** pre-alpha, under active development. See [`docs/PLAN.md`](docs/PLAN.md).

## Install

Download the latest `notelore-<version>-windows-x64.zip` or `notelore-<version>-macos-arm64.zip` from the [releases page](https://github.com/mfozmen/notelore/releases), unzip, and run `notelore`. The macOS binary is not notarized yet: right-click it and choose *Open* the first time.

Notelore checks for a newer release once a day (silently skipped when offline) and tells you when one exists. `notelore update` downloads it, checks it against the SHA-256 published with the release (this catches corrupted or partial downloads; it is not a signature), and only then replaces the executable in place; a Python install gets the matching `uv tool upgrade notelore` hint instead.

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

## Development

Requires [uv](https://docs.astral.sh/uv/).

```bash
uv sync
uv run pre-commit install
uv run pytest
```

Contributor guide for humans and AI agents: [`CLAUDE.md`](CLAUDE.md). Note format spec: [`docs/note-format.md`](docs/note-format.md).

## License

MIT
