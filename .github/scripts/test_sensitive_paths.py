"""Tests for sensitive_paths: which changed files call for the security pass.
No network; one test builds a throwaway git repository. Run by ci.yml:

    python3 .github/scripts/test_sensitive_paths.py
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sensitive_paths import base_ref, changed_files, sensitive

cases = [
    ("a provider", "packages/notelore_core/lib/src/providers/chatgpt.dart", True),
    ("sync", "packages/notelore_core/lib/src/sync/drive.dart", True),
    ("the app lock's secret", "packages/notelore_core/lib/src/secret.dart", True),
    ("the app lock", "apps/notelore/lib/src/lock_state.dart", True),
    ("the updater", "apps/notelore/lib/src/update.dart", True),
    ("any auth file", "apps/notelore/lib/src/drive_auth.dart", True),
    ("core OAuth", "packages/notelore_core/lib/src/chatgpt_auth.dart", True),
    ("the Android manifest", "apps/notelore/android/app/src/main/AndroidManifest.xml", True),
    ("an Apple Info.plist", "apps/notelore/macos/Runner/Info.plist", True),
    ("Apple entitlements", "apps/notelore/macos/Runner/Release.entitlements", True),
    ("a package's dependencies", "apps/notelore/pubspec.yaml", True),
    ("the workspace's lock file", "pubspec.lock", True),
    ("a workflow", ".github/workflows/release.yml", True),
    ("a CI script", ".github/scripts/review_range.py", True),
    ("the security reviewer itself", ".claude/agents/security-reviewer.md", True),
    ("Claude Code's project settings", ".claude/settings.json", True),
    ("an Android build file", "apps/notelore/android/app/build.gradle.kts", True),
    ("Android backup or network rules", "apps/notelore/android/app/src/main/res/xml/backup_rules.xml", True),
    ("the agent's tools", "packages/notelore_core/lib/src/tools.dart", True),
    ("the dev tool, which holds a ChatGPT sign-in", "packages/notelore_core/lib/src/dev.dart", True),
    ("a screen", "apps/notelore/lib/src/chat.dart", False),
    ("a test", "apps/notelore/test/lock_test.dart", False),
    ("docs", "docs/model-eval.md", False),
    ("the README", "README.md", False),
    ("the training tools", "tool/train/finetune.py", False),
]

failures = 0
for name, path, want in cases:
    got = bool(sensitive([path]))
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name} ({path}): got {got}, want {want}")

got = sensitive(["README.md", "apps/notelore/lib/src/update.dart", "docs/x.md"])
ok = got == ["apps/notelore/lib/src/update.dart"]
failures += not ok
print(f"{'ok  ' if ok else 'FAIL'} a mixed change names only its sensitive files: got {got}")

for name, env, want in [
    ("a security range wins over the PR base", {"RANGE_BASE": "abc", "BASE_REF": "def"}, "abc"),
    ("the PR base is the fallback", {"BASE_REF": "def"}, "def"),
    ("the default base is main", {}, "origin/main"),
]:
    got = base_ref(env)
    ok = got == want
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")


# A sensitive file renamed to an ordinary path must still count: git would
# report the rename under its new name only (#385).
with tempfile.TemporaryDirectory() as repo:
    def git(*args):
        subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True)

    git("init", "-q", "-b", "main")
    git("config", "user.email", "t@t")
    git("config", "user.name", "t")
    secret = Path(repo, "packages/notelore_core/lib/src/secret.dart")
    secret.parent.mkdir(parents=True)
    secret.write_text("the hash\n" * 20, encoding="utf-8")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    git("branch", "base")
    Path(repo, "docs").mkdir()
    git("mv", "packages/notelore_core/lib/src/secret.dart", "docs/notes.md")
    git("commit", "-q", "-m", "hide it")
    got = sensitive(changed_files("base", cwd=repo))
    ok = got == ["packages/notelore_core/lib/src/secret.dart"]
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} a renamed sensitive file still counts: got {got}")

sys.exit(1 if failures else 0)
