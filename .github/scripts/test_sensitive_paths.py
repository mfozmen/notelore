"""Tests for sensitive_paths: which changed files call for the security pass.
No network, no git. Run by ci.yml:

    python3 .github/scripts/test_sensitive_paths.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sensitive_paths import sensitive

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

sys.exit(1 if failures else 0)
