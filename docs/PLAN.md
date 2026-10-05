# Plan

Single roadmap. Tick items as PRs land; delete finished milestones once they are stable.

The first version was a Python command line (store, agent, Drive sync design). It was ported to one Flutter codebase for every device ([#60](https://github.com/mfozmen/notelore/issues/60)) and retired in [#69](https://github.com/mfozmen/notelore/issues/69); its behaviour lives on in the Dart tests and the `spec/fixtures` contract.

## M6 — Flutter (epic #60)

One Dart codebase for Android, iOS, Windows and macOS. Step by step; each step is one issue and lands before the next starts.

- [x] F1 Toolchain and CI: Dart workspace, analysis, tests with the 100% coverage gate on three OSes, APK and desktop builds, Sonar (#61)
- [x] F2 Note format, paths, i18n against `spec/fixtures/notes` (#62)
- [x] F3 Store, search index, stale notes (#63)
- [x] F4 Sync merge, manifest, engine, model resolver (#64)
- [x] F5 LLM providers over HTTPS, agent, tools (#65)
- [x] F6 App UI: setup, chat, notes, settings (#66)
- [x] F7 Google Drive sign-in, remote, sync triggers (#67)
- [x] F8 Release pipeline and desktop self-update (#68)
- [x] F9 Retire the Python packages (#69)
- [ ] F10 iOS (#70): deferred until a Mac and an iOS device are available

Waiting on the maintainer (consoles, keys, live checks): [#84](https://github.com/mfozmen/notelore/issues/84).

## Later (not planned yet)

- Reminders (OS notifications from due todos)
- Embedding-based semantic search
- Run file and index I/O off the UI thread (an isolate) if large note folders make the app stutter
