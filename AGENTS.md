# Codex instructions

Read `CLAUDE.md` before changing or reviewing this repository. It is the shared
project guide for Claude and Codex: follow its architecture, data safety, testing,
language, branch, and PR rules.

Claude Code sets `NOTELORE_HOME=.dev-home` through `.claude/settings.json`.
Codex uses `.codex/config.toml` for the same environment value in trusted local
projects. opencode reads `opencode.json` and `.opencode/`: it loads `CLAUDE.md`,
sets `NOTELORE_HOME` and blocks `.env` reads and force-pushes through
`.opencode/plugins/notelore-env.js`, and installs the published commentie
plugin, which injects the comments rule, registers the critic and commands, and
checks edits through its hook. Set it explicitly for any manual app or CLI run
where that project configuration is unavailable. Never read `.env` or real user
data.

For UI design work, read `.claude/skills/ui-ux-pro-max/SKILL.md` if relevant.

## Code Review Rules

Check changed code against `CLAUDE.md` and `docs/note-format.md`:

- Flag any path that can access real user notes or credentials during development;
  manual runs must use `NOTELORE_HOME=.dev-home`, and tests must use temp folders.
- Flag note or sync changes that can lose data, break the Markdown round trip, or
  bypass the narrow store tools. Automated changes must remain reversible.
- Flag cross-platform breakage and untested store or sync behavior. Cite the file
  and line for each finding. Do not approve or merge on the author's behalf.
