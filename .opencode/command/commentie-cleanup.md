---
description: Clean narrative comments in a diff range or path (commentie).
agent: build
---

Run commentie's cleanup. Load the `cleanup` skill (the commentie bridge registers it); if it is unavailable, read the newest installed `~/.claude/plugins/cache/devkit/commentie/*/skills/cleanup/SKILL.md`, or the canonical file at https://github.com/mfozmen/commentie. Follow it exactly.

The mechanical pass is `python tool/check_comments.py --diff-file -` with the scope's diff on stdin (`tool/check_comments.py` is byte-identical to the plugin's script). Never change code, only comment text, and verify with `git diff -U0` that every touched line is a comment.

Scope: $ARGUMENTS
