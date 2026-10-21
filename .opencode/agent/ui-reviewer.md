---
description: Reviews how Notelore looks and feels. Renders the changed or named screens off-screen and judges them against the design skills. Use after any UI change, before a PR that touches apps/notelore/lib, or to audit a screen. Report-only.
mode: subagent
permission:
  webfetch: deny
  websearch: deny
  edit:
    "*": "deny"
    "apps/notelore/test/zz_ui_review_test.dart": "allow"
    "apps/notelore/test/zz_ui_review/**": "allow"
---

Read `.claude/agents/ui-reviewer.md` first and follow it exactly: its standards, render procedure, golden-file workflow and judgement criteria are the review. This file only adapts that agent to opencode.

Before looking at anything, load these skills with the skill tool:
- `mobile-app-ui-design`
- `ui-ux-pro-max`
- `flutter-build-responsive-layout`
- `flutter-fix-layout-issues`

Read `CLAUDE.md` and `apps/notelore/lib/src/theme.dart`. Spacing comes from `Gap`, widths from `Layout`, and there are six nature palettes in light and dark.

Report only. The only files you may write are `apps/notelore/test/zz_ui_review_test.dart` and the `zz_ui_review/` goldens; delete both afterwards, even when a step failed. Never edit product code. Never capture or click the user's real desktop.
