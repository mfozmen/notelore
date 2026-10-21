#!/usr/bin/env python3
"""Flag narrative comments in the added lines of a git diff.

Usage:
  check_comments.py [--staged] [RANGE] [--diff-file F] [--file F] [--hook]
                    [--strict] [--allowlist PATH] [--max-block N] [--self-test]

Output is file:line: reason. Exit 0, or 1 with --strict when anything is flagged.
"""
import argparse
import json
import os
import re
import subprocess
import sys

LINE_MARKERS = {
    "#": {"py", "rb", "sh", "bash", "zsh", "yaml", "yml", "toml", "pl", "r", "ps1",
          "cfg", "ini", "dockerfile", "makefile", "tf", "nix", "ex", "exs"},
    "//": {"js", "jsx", "mjs", "cjs", "ts", "tsx", "java", "c", "h", "cpp", "hpp", "cc",
           "cs", "go", "rs", "kt", "kts", "swift", "scala", "php", "dart", "m", "mm",
           "scss", "less", "groovy", "zig", "v", "sv"},
    "--": {"sql", "lua", "hs", "elm", "ada"},
}
BLOCK_MARKERS = {
    ("/*", "*/"): LINE_MARKERS["//"] | {"css"},
    ("<!--", "-->"): {"html", "htm", "xml", "vue", "svelte", "md", "xaml", "csproj", "svg"},
    ('"""', '"""'): {"py"},
    ("'''", "'''"): {"py"},
}
DOC_OPENERS = ("/**", "///", '"""', "'''")

HISTORY = re.compile(
    r"(?<![\w-])(previously|changed (from|to|in|since)|now we|fix(ed|es) (a |the )?(bug|issue|crash|typo)"
    r"|used to|no longer|new:|old:|old (code|version|implementation|way)|renamed from|moved from"
    r"|refactored (from|out)|was (removed|added|replaced))(?![\w-])", re.I)
ISSUE_ONLY = re.compile(
    r"^(see |fixes |closes |refs? |resolves |related:? )?"
    r"(#\d+|[A-Z][A-Z0-9]+-\d+|https?://\S+/(issues|pull|browse|work_items)/\S+)[.,]?$", re.I)
CODE_HEAD = re.compile(
    r"^(if|for|while|return|import|from|def|class|const|let|var|function|public|private|protected"
    r"|static|using|print|console\.|System\.|await|async|try|catch|else|switch|case|select|insert"
    r"|update|delete|drop|alter|create|fmt\.|log\.|raise|throw|new|elif|end|require|include|package)\b")
CODE_SHAPE = re.compile(r"^[A-Za-z_][\w.\[\]]*\s*(=[^=]|\+=|-=|\(.*\)\s*;?$)")
CODE_TAIL = re.compile(r"[;{}]\s*$|\)\s*;$")
CODE_CHARS = re.compile(r"[(){}\[\];=]|\w\.\w|:$")
PROSE = re.compile(r"^[A-Z][a-z].*[.!?]$")
LICENCE = re.compile(r"copyright|licen[cs]e|spdx", re.I)
STRINGS = re.compile(r'"(?:\\.|[^"\\])*"|' + r"'(?:\\.|[^'\\])*'")


def ext_of(path):
    base = path.rsplit("/", 1)[-1].lower()
    return base.rsplit(".", 1)[-1] if "." in base else base


def comments_in(lines, ext):
    """Yield (index, text, is_doc, block_id) for the comment text on each line.

    block_id groups consecutive comment lines so the long-block rule can count them.
    """
    line_marks = [m for m, exts in LINE_MARKERS.items() if ext in exts]
    blocks = [m for m, exts in BLOCK_MARKERS.items() if ext in exts]
    if not line_marks and not blocks:
        return
    open_block = None
    is_doc = False
    block_id = 0
    prev_was_comment = False
    for i, raw in enumerate(lines):
        line = raw.strip()
        text = None
        if open_block:
            end = open_block[1]
            text = line.split(end, 1)[0].strip(" *")
            if end in line:
                open_block = None
        else:
            # Strings are blanked at equal length so "http://x" is not a comment and offsets still match.
            code = STRINGS.sub(lambda s: s.group()[0] + " " * (len(s.group()) - 2) + s.group()[-1], line)
            for start, end in blocks:
                pos = code.find(start)
                if pos < 0:
                    continue
                is_doc = line.startswith(DOC_OPENERS)
                rest = line[pos + len(start):]
                if start == end:
                    if code.count(start) >= 2:
                        text = rest.split(end, 1)[0].strip()
                    else:
                        text = rest.strip()
                        open_block = (start, end)
                elif end in rest:
                    text = rest.split(end, 1)[0].strip(" *")
                else:
                    text = rest.strip(" *")
                    open_block = (start, end)
                break
            if text is None:
                for m in line_marks:
                    pos = code.find(m)
                    if pos >= 0 and not (m == "//" and pos > 0 and code[pos - 1] == ":"):
                        text = line[pos + len(m):].strip()
                        is_doc = line[pos:].startswith(DOC_OPENERS)
                        break
        if text is None:
            prev_was_comment = False
            is_doc = False
            continue
        if not prev_was_comment:
            block_id += 1
        prev_was_comment = True
        yield i, text, is_doc, block_id


def classify(text):
    t = text.strip()
    if not t:
        return None
    if ISSUE_ONLY.match(t):
        return "issue-ref: ticket reference as the whole comment; say the why instead"
    if HISTORY.search(t):
        return "history: how the code got here belongs in the commit message"
    if PROSE.match(t):
        return None
    # "return the rows" is narration, not code: a keyword alone needs code punctuation or brevity.
    keyword_code = CODE_HEAD.match(t) and (CODE_CHARS.search(t) or len(t.split()) <= 2)
    if keyword_code or CODE_SHAPE.match(t) or CODE_TAIL.search(t):
        return "dead-code: commented-out code; delete it, git remembers"
    return None


def added_lines(diff_text):
    """Yield (path, new_line_no, text) per added line; (path, None, None) marks a hunk break."""
    path, new_no = None, 0
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:].strip()
            path = None if target == "/dev/null" else re.sub(r"^b/", "", target)
        elif raw.startswith("@@"):
            m = re.match(r"@@ -\S+ \+(\d+)", raw)
            new_no = int(m.group(1)) if m else 0
            if path:
                yield path, None, None
        elif path is None or raw.startswith(("---", "diff ", "index ", "\\")):
            continue
        elif raw.startswith("+"):
            yield path, new_no, raw[1:]
            new_no += 1
        elif raw.startswith(" "):
            new_no += 1
            yield path, None, None


def find_issues(diff_text, max_block=5, allowlist=()):
    allow = [re.compile(a) for a in allowlist if a.strip()]
    per_file = {}
    for path, no, text in added_lines(diff_text):
        per_file.setdefault(path, []).append(None if text is None else (no, text))
    issues = []
    for path, entries in per_file.items():
        ext = ext_of(path)
        runs, run = [], []
        for e in entries:
            if e is None:
                if run:
                    runs.append(run)
                run = []
            else:
                run.append(e)
        if run:
            runs.append(run)
        for run in runs:
            lines = [t for _, t in run]
            blocks = {}
            for i, text, is_doc, bid in comments_in(lines, ext):
                no = run[i][0]
                if any(a.search(text) for a in allow):
                    continue
                blocks.setdefault(bid, []).append((no, text, is_doc))
                reason = classify(text)
                if reason:
                    issues.append((path, no, reason))
            for members in blocks.values():
                if len(members) <= max_block:
                    continue
                if any(d for _, _, d in members) or any(LICENCE.search(t) for _, t, _ in members):
                    continue
                issues.append((path, members[0][0],
                               f"long-block: {len(members)} comment lines; keep it to one or two sentences"))
    issues.sort(key=lambda x: (x[0], x[1]))
    return issues


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout


def mkdiff(path, lines, start=1):
    body = "\n".join("+" + l for l in lines)
    return (f"diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n"
            f"@@ -{start},0 +{start},{len(lines)} @@\n{body}\n")


def file_as_diff(path, cwd):
    with open(path, encoding="utf-8", errors="replace") as f:
        return mkdiff(os.path.relpath(path, cwd).replace(os.sep, "/"), f.read().splitlines())


def load_allowlist(path):
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]
    return []


def hook_main(args):
    if os.environ.get("CLAUDE_PLUGIN_OPTION_HOOK_ENABLED", "").lower() not in ("true", "1", "yes"):
        return 0
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    path = (payload.get("tool_input") or {}).get("file_path")
    cwd = payload.get("cwd") or os.getcwd()
    if not path or not os.path.isfile(path):
        return 0
    tracked = subprocess.run(["git", "ls-files", "--error-unmatch", path], cwd=cwd,
                             capture_output=True).returncode == 0
    diff = git("diff", "-U0", "HEAD", "--", path, cwd=cwd) if tracked else file_as_diff(path, cwd)
    issues = find_issues(diff, args.max_block, load_allowlist(os.path.join(cwd, args.allowlist)))
    if issues:
        lines = "\n".join(f"{p}:{n}: {r}" for p, n, r in issues)
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "commentie: comments in this edit look narrative (warning only):\n"
                                 + lines + "\nKeep only the why, the trap or the coupling, in one short sentence."}}))
    return 0


def self_test():
    def reasons(path, lines, **kw):
        return [(ln, r.split(":")[0]) for _, ln, r in find_issues(mkdiff(path, lines), **kw)]

    # history words
    assert reasons("a.py", ["# previously this used a dict"]) == [(1, "history")]
    assert reasons("a.ts", ["// changed from Map to Set"]) == [(1, "history")]
    assert reasons("a.go", ["// now we retry twice"]) == [(1, "history")]
    assert reasons("a.cs", ["// fixed bug where id was null"]) == [(1, "history")]
    assert reasons("a.sql", ["-- new: index on user_id"]) == [(1, "history")]
    assert reasons("a.rb", ["# used to be async"]) == [(1, "history")]
    assert reasons("a.js", ["// no longer needed after v2"]) == [(1, "history")]
    # bare issue refs
    assert reasons("a.py", ["# #1234"]) == [(1, "issue-ref")]
    assert reasons("a.java", ["// JIRA-99"]) == [(1, "issue-ref")]
    assert reasons("a.ts", ["// see https://github.com/x/y/issues/12"]) == [(1, "issue-ref")]
    assert reasons("a.ts", ["// Retry here: PROJ-12 tracks the upstream fix."]) == []
    # commented-out code
    assert reasons("a.py", ["# result = compute(x)"]) == [(1, "dead-code")]
    assert reasons("a.ts", ["// console.log(user);"]) == [(1, "dead-code")]
    assert reasons("a.cs", ["// if (x > 1) {"]) == [(1, "dead-code")]
    assert reasons("a.go", ["// return err"]) == [(1, "dead-code")]
    assert reasons("a.py", ["# import os"]) == [(1, "dead-code")]
    assert reasons("a.sql", ["-- SELECT * FROM users;"]) == [(1, "dead-code")]
    assert reasons("a.py", ["# Return early: the cache is stale after midnight."]) == []
    assert reasons("a.py", ["# return early when the cache is warm"]) == []
    assert reasons("a.py", ["# create a dict reader"]) == []           # narration is the critic's job
    assert reasons("a.py", ['# old: return sum(float(r["a"]) for r in rows)']) == [(1, "history")]
    assert reasons("a.py", ["# if cached:"]) == [(1, "dead-code")]
    # long blocks
    six = ["// line %d of a long explanation" % i for i in range(6)]
    assert reasons("a.ts", six) == [(1, "long-block")]
    assert reasons("a.ts", six, max_block=6) == []
    assert reasons("a.ts", ["/**"] + six + ["*/"]) == []           # doc block exempt
    assert reasons("a.py", ['"""'] + ["doc"] * 8 + ['"""']) == []  # docstring exempt
    lic = ["# Copyright (c) 2026 X", "# Licensed under MIT"] + ["# blah"] * 6
    assert reasons("a.py", lic) == []                             # licence header exempt
    # block comments
    assert reasons("a.c", ["/* previously a macro */"]) == [(1, "history")]
    assert reasons("a.html", ["<!-- fixed bug in layout -->"]) == [(1, "history")]
    assert reasons("a.c", ["/*", " * changed from int", " */"]) == [(2, "history")]
    # not comments
    assert reasons("a.ts", ['const url = "http://x.io"; // used to fail']) == [(1, "history")]
    assert reasons("a.ts", ['const s = "// previously";']) == []
    assert reasons("a.py", ["x = 1  # no longer"]) == [(1, "history")]
    assert reasons("a.py", ["s = '# changed from'"]) == []
    assert reasons("a.py", ['f("# import os")  # no longer']) == [(1, "history")]
    assert reasons("a.py", ['f("# import os")  # Keep: the API wants it.']) == []
    assert reasons("a.txt", ["previously nothing"]) == []
    # real why / trap / coupling comments pass
    good = [
        ("a.py", "# Sleep before retry: the API rate-limits bursts under 200ms."),
        ("a.ts", "// Order matters: the index must exist before the trigger."),
        ("a.go", "// Keep in sync with the enum in proto/status.proto."),
        ("a.cs", "// Windows locks the file until the stream is disposed."),
        ("a.sql", "-- Partial index: nulls are 90% of rows and never queried."),
        ("a.py", "# TODO: drop this shim when Python 3.9 support ends."),
        ("a.ts", "// eslint-disable-next-line no-console -- CLI entry point"),
    ]
    for path, line in good:
        assert reasons(path, [line]) == [], (path, line)
    # allowlist and line numbers
    assert reasons("a.py", ["# previously"], allowlist=[r"previously"]) == []
    out = find_issues(mkdiff("a.py", ["x = 1", "# previously"], start=10))
    assert out == [("a.py", 11, out[0][2])]
    # several files, deletions ignored
    d = mkdiff("a.py", ["# previously"]) + (
        "diff --git a/b.py b/b.py\n--- a/b.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-# previously\n")
    assert [p for p, _, _ in find_issues(d)] == ["a.py"]
    print("self-test ok")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("range", nargs="?", help="git range such as main..HEAD (default: staged changes)")
    ap.add_argument("--staged", action="store_true", help="check staged changes (default)")
    ap.add_argument("--diff-file", help="read a unified diff from this file, or - for stdin")
    ap.add_argument("--file", help="check one file's changes against HEAD (whole file if untracked)")
    ap.add_argument("--hook", action="store_true", help="PostToolUse mode: read hook JSON on stdin")
    ap.add_argument("--strict", action="store_true", help="exit 1 when anything is flagged")
    ap.add_argument("--allowlist", default=".commentie-allow",
                    help="file of regexes to skip, one per line (default .commentie-allow)")
    ap.add_argument("--max-block", type=int, default=5,
                    help="flag comment blocks longer than N lines (default 5)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.hook:
        return hook_main(args)
    if args.diff_file:
        if args.diff_file == "-":
            diff = sys.stdin.read()
        else:
            with open(args.diff_file, encoding="utf-8") as f:
                diff = f.read()
    elif args.file:
        cwd = os.getcwd()
        tracked = subprocess.run(["git", "ls-files", "--error-unmatch", args.file],
                                 cwd=cwd, capture_output=True).returncode == 0
        diff = git("diff", "-U0", "HEAD", "--", args.file, cwd=cwd) if tracked \
            else file_as_diff(args.file, cwd)
    elif args.range:
        diff = git("diff", "-U0", args.range)
    else:
        diff = git("diff", "-U0", "--cached")
    issues = find_issues(diff, args.max_block, load_allowlist(args.allowlist))
    for p, n, r in issues:
        print(f"{p}:{n}: {r}")
    return 1 if issues and args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
