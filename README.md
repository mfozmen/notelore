# Notelore

**Your personal lore, kept by an LLM.**

Tell it things. It writes tidy, human-readable Markdown notes on your disk. Ask it later: *"Which database did we pick for Mopsos?"* It answers from your notes, and backs them up to Google Drive.

- Local-first: plain Markdown files you can open in any editor or Obsidian
- Bring your own model: Claude, GPT, Gemini, or a local model via Ollama
- Decisions are tracked with history, so "what did we decide?" has one correct answer
- Windows and macOS

> **Status:** pre-alpha, under active development. See [`docs/PLAN.md`](docs/PLAN.md).

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
