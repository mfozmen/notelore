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
The Windows numbers above are host timings and must not be presented as phone
timings. The emulator run below is separate.

## Android emulator reproduction

The app's `tool/android_latency_probe.dart` runs the same core probe on Android.
It creates and removes notes and an index under the app's system temp directory;
it never opens the normal Notelore session, provider keys, or user notes. It
prints the 10,000-note index result first, then the 1- and 100-note scripted
turn results. The checked-in runner makes the setup reusable by Claude and
Codex sessions without a real provider account.

One profile-mode run on an Android 15 x86_64 Pixel 6 emulator with WHPX,
Flutter 3.47.6 / Dart 3.13.5, and the same Intel i9-13950HX host produced:

| Notes | Turn | Scripted wait per model call | Model calls | Median total | Median provider | Median local tools |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Note-taking | 0 ms | 3 | 4 ms | 0 ms | 4 ms |
| 1 | Note-taking | 200 ms | 3 | 618 ms | 607 ms | 12 ms |
| 1 | Retrieval | 0 ms | 2 | 3 ms | 0 ms | 3 ms |
| 1 | Retrieval | 200 ms | 2 | 431 ms | 418 ms | 11 ms |
| 100 | Note-taking | 0 ms | 3 | 68 ms | 23 ms | 45 ms |
| 100 | Note-taking | 200 ms | 3 | 628 ms | 606 ms | 21 ms |
| 100 | Retrieval | 0 ms | 2 | 18 ms | 1 ms | 17 ms |
| 100 | Retrieval | 200 ms | 2 | 425 ms | 405 ms | 20 ms |

Each row is the median of 20 fresh temp-note samples. The one 10,000-note
corpus took **888 ms** for initial indexing, **89 ms** for the median of five
unchanged refreshes, and **113 ms** for a search tool call including refresh.
The preceding debug-mode run measured 1,400 ms, 113 ms, and 145 ms for those
three operations, respectively. That difference shows why profile mode and
repeated device runs matter. The runner executes on Flutter's main isolate and
its bulk corpus creation caused skipped frames; it is a storage/agent probe,
not a measurement of the normal chat UI's frame timing. None of these timings
come from a physical phone or a live provider/network connection.

On Windows, with Flutter and Android SDK command-line tools already installed:

```powershell
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
& "$sdk\cmdline-tools\latest\bin\android.exe" sdk install emulator
& "$sdk\cmdline-tools\latest\bin\android.exe" sdk install 'system-images/android-35/google_apis/x86_64'
& "$sdk\emulator\emulator.exe" -accel-check
& "$sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n notelore_latency_api35 -k 'system-images;android-35;google_apis;x86_64' -d pixel_6
Start-Process -FilePath "$sdk\emulator\emulator.exe" -ArgumentList @('-avd','notelore_latency_api35','-no-window','-no-audio','-no-boot-anim','-gpu','swiftshader_indirect') -WindowStyle Hidden
& "$sdk\platform-tools\adb.exe" -e wait-for-device
& "$sdk\platform-tools\adb.exe" -e shell getprop sys.boot_completed # wait until 1
$env:NOTELORE_HOME = Join-Path (Get-Location) '.dev-home'
Set-Location apps/notelore
& "$env:USERPROFILE\flutter\bin\flutter.bat" run -d emulator-5554 -t tool/android_latency_probe.dart --profile
```

On macOS or Linux with a configured Android emulator, run from the repository
root: `cd apps/notelore && NOTELORE_HOME="$(cd ../.. && pwd)/.dev-home" flutter run -d <device-id> -t tool/android_latency_probe.dart --profile`.

`NOTELORE_HOME` protects manual host runs. The Android runner itself only uses
explicit temp paths. The JSON lines appear in the Flutter log. Use `q` to stop
`flutter run` after `Latency probe complete.`. The emulator can later be stopped
with `adb -e emu kill`. Keep the host CPU, emulator API/ABI, Flutter mode, and
sample count alongside any result. An emulator is useful for spotting Android
path or SQLite regressions, but its timings do not represent a physical phone.
The scripted provider's 200 ms wait is also not a live network measurement.

The probe does **not** measure a live provider's inference time, internet
round trips, token volume, model choice, a queued Drive sync, Flutter frame
time on a physical Android device. Thus it cannot establish a production end-to-end
baseline or claim an actual speedup. In the app, `Session.send` puts the turn
through `_exclusive`; any sync already in that queue may add waiting time.
`syncNow()` after a turn is launched without waiting for it, so it does not
delay that turn's displayed answer. These are code-path observations, not
timings. A device trace is needed to separate UI and queue delay reliably.

## Timing trace

Development runs time every turn, with names and milliseconds only (never note text, tool arguments or keys):

- `dart run notelore_core:notelore_dev chat "<message>"` prints `⏱ model <ms> ms` and `⏱ tool <name> <ms> ms` for each call.
- The app run with `NOTELORE_HOME` set (`flutter run`) prints the same lines to the debug console, plus `queue <ms> ms`: how long the turn waited behind a sync or an earlier turn. A release build prints nothing.

Rendered frames are measured with Flutter DevTools in profile mode, not by the trace.

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
sync tests. Include a 10,000-note physical-device test before deciding whether to
change index refresh frequency. Until that live baseline exists, changing the
prompt, store, or provider defaults would be guesswork.
