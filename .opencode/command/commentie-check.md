---
description: Check the comments this branch adds (commentie's stdlib pass).
agent: build
---

Run `python tool/check_comments.py origin/main...HEAD` and report each `file:line: reason`. If there are findings, quote the commentie rule in one line (only a non-obvious why, a trap or a hidden coupling, one or two short sentences) and say they are a warning, not a blocker. Do not edit anything.
