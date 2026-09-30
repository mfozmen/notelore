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

Notelore checks for a newer release once a day (silently skipped when offline) and tells you when one exists. `notelore update` downloads it and replaces the executable in place; a Python install gets the matching `uv tool upgrade notelore` hint instead.

Releases are cut automatically from the Conventional Commit history on `main`: a `feat` commit bumps the minor version, `fix` or `perf` the patch version; other types (`docs`, `chore`, `ci`...) do not release.

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
