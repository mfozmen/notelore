# Contributing to Notelore

The rules are in [`CLAUDE.md`](CLAUDE.md). It is the guide for people and AI agents alike. This page is the workflow in short.

## Before you start

- **Set up:** follow [`docs/development.md`](docs/development.md): Flutter, `flutter pub get`, and the optional `.env` for Drive sign-in.
- **Keep real notes safe:** set `NOTELORE_HOME=.dev-home` for any manual run, so it never touches your real notes.

## One change, start to finish

1. **Issue:**
   - Open one, or pick one from the earliest open milestone ([roadmap](https://github.com/mfozmen/notelore/milestones?direction=asc&sort=due_date)).
   - It needs exactly one `priority/*` label and a milestone.
   - Add `WIP` when you start.
2. **Branch:** one per change, `<type>/<slug>` (`feat/about-me`, `fix/mac-keychain-once`).
3. **Test first:** write a failing test, make it pass with the least code, then clean up. Coverage stays at 100% in both packages.
4. **Design:**
   - Follow [`docs/design-patterns.md`](docs/design-patterns.md): branch on a platform or kind in one place, and inject what crosses a boundary.
   - UI changes go through the design skills, with before and after renders in the PR.
5. **Check locally:**
   ```bash
   dart format .
   dart analyze --fatal-infos
   (cd packages/notelore_core && dart run coverage:test_with_coverage)
   (cd apps/notelore && flutter test --coverage)
   dart run tool/coverage_gate.dart packages/notelore_core/coverage/lcov.info apps/notelore/coverage/lcov.info
   python tool/check_comments.py origin/main...HEAD
   ```
6. **Commit:** use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:` …), with the issue number in the subject. Commit types decide the next version.
7. **Pull request:**
   - Write a summary, the context (the issue) and a test plan.
   - If the change is user-visible, update `README.md` in the same PR.
8. **Merge gate:**
   - CI is green on Windows, macOS and Linux.
   - SonarCloud shows 0 new issues.
   - The AI review and security review show no Critical.
   - Review findings are settled in the PR: fixed, or argued until the reviewer and author agree.
9. **After the merge:** remove `WIP`. Releases are cut by hand (`gh workflow run release.yml`).

## Never

- **History:** force-push, `reset --hard` or rewrite history on shared branches. Catch up with `git merge`.
- **Secrets:** commit them (`.env`, OAuth client ids, keys) or read someone's real notes.
- **Writes:** add a tool that rewrites a note wholesale, or that deletes without a way back.
