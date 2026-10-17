# Response latency investigation (#232)

2026-10-17. The question is whether Notelore can answer sooner without losing
note correctness or making every turn more expensive.

## Method and limits

Run `dart run tool/latency_probe.dart` from `packages/notelore_core`. The probe
creates fresh notes and an SQLite index in a system temp directory for each
sample, then removes them. It never opens a provider account or user notes. It
times `Agent.ask`, each `LlmProvider.turn`, and each `Toolbox.call` with a
`Stopwatch`. "Other" is total minus provider and tools. Each cell below is the
range of medians from two independent runs of 20 samples each on Windows x64,
Dart 3.13.5, Intel i9-13950HX. The 200 ms provider
wait is **scripted**; it represents a controlled round-trip delay, not measured
API or internet performance. The zero-wait rows isolate local work.

The note-taking script calls `list_notes`, then `add_note_entry` for an existing
project, then returns an answer: three model calls and two tools. The retrieval
script calls `search_notes`, then returns an answer: two model calls and one
tool. Both exercise the real agent, store, index, and temp Markdown files. The
100-note corpus contains one matching note and 99 unrelated projects.

| Notes | Turn | Scripted wait per model call | Model calls | Total | Provider | Local tools | Other |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | Note-taking | 0 ms | 3 | 17–32 ms | 0 ms | 17–31 ms | 0 ms |
| 1 | Note-taking | 200 ms | 3 | 655–661 ms | 625–627 ms | 30–35 ms | 0–1 ms |
| 1 | Retrieval | 0 ms | 2 | 10–36 ms | 0 ms | 10–35 ms | 0 ms |
| 1 | Retrieval | 200 ms | 2 | 433–437 ms | 417–419 ms | 16–18 ms | 0 ms |
| 100 | Note-taking | 0 ms | 3 | 46–52 ms | 0 ms | 46–52 ms | 0 ms |
| 100 | Note-taking | 200 ms | 3 | 681–685 ms | 623–630 ms | 54–55 ms | 0 ms |
| 100 | Retrieval | 0 ms | 2 | 32–63 ms | 0 ms | 32–62 ms | 0 ms |
| 100 | Retrieval | 200 ms | 2 | 457–490 ms | 417–420 ms | 38–68 ms | 0 ms |

Medians of the components are calculated separately, so they need not add to
the median total. The variation between runs, particularly in the local search
time, is another reason not to treat these numbers as a production baseline.
On this machine, the imposed model wait dominates: about 91–92% of the 100-note
taking turn and 85–92% of retrieval. With no wait, the work is almost entirely
in the local tools. `Toolbox._fresh()` rebuilds the index for
`list_notes` and `search_notes`; `NoteIndex.rebuild()` scans file metadata even
when note content is unchanged. The 100-note corpus raises local tool time to
roughly 30–70 ms.

The issue also asked about a much larger note folder. Run
`dart run tool/latency_probe.dart --large` for one 10,000-note temp corpus. On
the same Windows machine, its initial index build took **2,140 ms**; the median
of five unchanged index refreshes took **275 ms**; a `search_notes` tool call
including that refresh took **304 ms**. This is substantial enough to profile
on a phone before ruling out local search as a bottleneck for large libraries.
Unlike the table above, this large-corpus result is from one run; the initial
build also includes cold file-system cache effects.
No Android device was connected for this investigation, so these numbers must
not be presented as phone timings.

The probe does **not** measure a live provider's inference time, internet
round trips, token volume, model choice, a queued Drive sync, Flutter frame
time, or an Android device. Thus it cannot establish a production end-to-end
baseline or claim an actual speedup. In the app, `Session.send` puts the turn
through `_exclusive`; any sync already in that queue may add waiting time.
`syncNow()` after a turn is launched without waiting for it, so it does not
delay that turn's displayed answer. These are code-path observations, not
timings. A device trace is needed to separate UI and queue delay reliably.

## Options and decision

| Option | Potential gain | Cost or correctness risk |
| --- | --- | --- |
| Faster provider/model | Every model round can get faster. | Provider cost, availability, and answer/tool quality vary. Model selection already exists. |
| Fewer model/tool rounds | Removes an entire provider wait. | Skipping `list_notes` before creating or skipping search before answering can choose the wrong note or invent facts. A model may issue independent tools together, but dependent calls still require another round. |
| Avoid repeated index scans | Could save about 275 ms per query at 10,000 notes on this Windows machine. | A stale index can miss edits from other apps or Drive. The present scan protects the Markdown source of truth. |
| Stream response text | Improves perceived time to first text. | Does not reduce completion time and needs provider-specific streaming plus UI/cancel handling on every platform. |

No behavior change is justified by these measurements alone. The next small,
testable change is an **opt-in, redacted timing trace** for development runs:
record queue wait, each provider call, each tool call, and first/last rendered
frame without recording note contents or credentials. Use only `.dev-home` and
at least 20 note-taking and 20 retrieval turns per chosen provider/model on a
real device. Then compare median and p95 total time and the phase shares. A
candidate optimization should target at least a 20% lower median on the same
tasks while preserving answer correctness and the existing note-format and
sync tests. Include a 10,000-note Android test before deciding whether to
change index refresh frequency. Until that live baseline exists, changing the
prompt, store, or provider defaults would be guesswork.
