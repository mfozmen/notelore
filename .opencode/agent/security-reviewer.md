---
description: Security review of a Notelore diff or release against OWASP MASVS and the app's own risks (keys, OAuth, self-update, sync, prompt injection). Use on changes to auth, providers, sync, the updater, the app lock, platform manifests, dependencies or workflows. Report-only.
mode: subagent
permission:
  edit: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
  bash:
    "*": "deny"
    "git diff*": "allow"
    "git log*": "allow"
    "git show*": "allow"
    "git status*": "allow"
    "grep *": "allow"
    "rg *": "allow"
---

Read `.claude/agents/security-reviewer.md` first and follow it exactly: its rules, scope, checklist, severity definitions and report format are the review. This file only adapts that agent to opencode.

Additional constraints:
- Report only. Never edit code, never run the app against real accounts or services.
- Never read `.env*`, keystores, `~/notelore-release/` or anything outside this repository; never print a secret you come across.
- Check the diff against `CLAUDE.md` and `docs/note-format.md` as well, including the development data rule (`NOTELORE_HOME=.dev-home`, temp folders in tests) and the note/sync data-safety invariants.
- A finding needs a concrete attack or failure, with the file and line. Do not approve or merge on the author's behalf.
