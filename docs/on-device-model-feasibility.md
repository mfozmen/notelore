# On-device model: feasibility and decision (#227)

Status: the feasibility study is complete. The on-device path is already shipped
as an optional provider (#446, #450); making it the default is deferred until
the gates below are met. The evidence lives in `docs/model-eval.md` and
`docs/latency-investigation.md`.

## Decision

Keep the on-device model as an optional, offline provider. Do not make it the
default yet. Cloud providers and Ollama remain the quality path; the device
model is the no-account, no-network, no-per-token-cost fallback.

This is not a rejection. The path is real and works on Windows, macOS and
Android, but the measured quality and phone latency are below what a default
needs.

## What was evaluated

- Model: Qwen3-4B-Instruct-2507, Q4_K_M, about 2.5 GB, Apache-2.0. The app pins
  one revision and checks its SHA-256 (`device_model.dart`).
- Runtime: llama.cpp through llamadart 0.14.0, CPU only, behind the core
  `LocalProvider` and a small `LocalEngine` interface. The Dart side is tested
  against a fake engine; the native glue is validated on-device.
- Training: QLoRA on synthetic turns from two teachers, filtered by the eval
  scorer. v1 and v3/v4 are documented in `docs/model-eval.md`.
- Platforms: Android 64-bit with at least 6 GB of memory, Windows and macOS 14
  or newer. The model downloads once and resumes after a dropped connection.

## Evidence

### Quality

The 38-case baseline used the full prompt; the later 44-case runs used the slim
on-device prompt unless noted. The case counts differ, so compare within each
group, not across.

| Model | Cases | Score | Time per turn |
| --- | ---: | ---: | ---: |
| Stock Qwen3-4B-Instruct-2507 (non-thinking) | 38 | 26% | 1.3 s |
| Fine-tune v1 | 38 | 61% | 2.1 s |
| Qwen3-4B thinking (teacher) | 38 | 68% | 52 s |
| Fine-tune v3, slim run 1 | 44 | 52% (23/44) | - |
| Fine-tune v3, slim run 2 | 44 | 50% (22/44) | - |
| Fine-tune v3, full | 44 | 64% (28/44) | - |
| Fine-tune v4, slim run 1 | 44 | 48% (21/44) | - |
| Fine-tune v4, slim run 2 | 44 | 55% (24/44) | - |

The app currently ships the stock model; the slim fine-tune numbers are the
best evidence for the slim prompt, not a measurement of the stock model. The
best fine-tune is still around half the slim eval, and collection notes remain
the main failure: the model calls `related_notes`, sees the list note, then
creates a note named after the item anyway (#532). More distilled data of the
same kind did not fix it (v4). The 70% target in #327 is not met.

### Speed and memory

| Device / runtime | Prompt | Load | Cold turn | Warm turn | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Galaxy S23 Ultra, CPU, 8 threads | 2,707 tokens | 8.6 s | 130 s (20.8 tok/s prefill) | 17 s to first token | not published |
| x86_64 Android 15 emulator, CPU | 3,237 tokens | 11.2 s | 552 s | 6.2 s | 4.5 GB |

The S23's warm decode fell to 0.3 tok/s as the phone heated. The slim prompt is
1,828 tokens: about 43% fewer than the emulator's 3,237-token prompt and about 32%
fewer than the S23's 2,707. That should put a cold turn near 90 s on the S23 at
the same prefill rate; that run has not been done. The emulator is a rough
guide only, but its 4.5 GB peak matches the 6 GB phone floor. Desktop speed has
more headroom, but no published measurement yet.

### Size and availability

- Download: 2,497,281,120 bytes (about 2.5 GB), resumable, SHA-256 checked.
- App: the arm64 APK grows by about 24 MB for the llama.cpp runtime; the macOS
  floor moves to 14.
- Offered only where it can run: Windows, macOS, and 64-bit Android with at
  least 6 GB of memory. A smaller phone is not offered it and the chat says so.
- No images and no web search on the device model. Links are still read from
  the web, and Drive still backs up the notes.

## Privacy, cost and the OAuth decision

The model runs inside Notelore: no AI provider sees the notes, no account or
key is needed, and there is no per-token charge. The costs are the one-time
download, memory, battery and heat.

The OAuth-only decision in #206 applied to provider connections. An on-device
model makes no connection, so it does not conflict with that decision. It is
the only path that works with no account, key or network; cloud providers and
Ollama stay alternatives.

## Platform AI

Gemini Nano, Apple Foundation Models and Phi Silica are optional accelerators,
not the main path (#329): partial device coverage, a context window near 4k
tokens against a 1.8k-3.2k prompt plus notes and history, and tool calling only
on Apple. Use them only where the eval shows they are good enough.

## Risks

- Quality: the best slim fine-tune is around half the eval, and collection
  notes are weak. A default that misfiles notes is worse than a cloud default.
- Latency: a 90 s cold turn is not daily use on a phone; warm turns depend on
  prompt-cache reuse and thermals.
- Memory: 4.5 GB peak rules out many 6 GB phones once the OS and app are
  counted; low-memory behavior must stay tested.
- Distribution: 2.5 GB is too large for a GitHub release asset; the fine-tune
  needs a model host (#445). Until then the app ships the stock model.
- Maintenance: llama.cpp/llamadart, the pinned model revision and the slim
  prompt/tool set are a second runtime to keep working on every platform.
- Coverage: no images, no web search, and Turkish quality is measured only as
  part of the mixed eval, not as its own gate.

## Gates for making it the default

1. A real-phone run with the slim prompt: cold turn at or below 60 s and warm
   first token at or below 5 s on a cool S23-class phone, then on a mid-range
   phone.
2. At least 70% on the 44-case eval, with collection notes at least 8/10 and
   Turkish no more than 10 points behind English.
3. Peak RSS at or below 5 GB, with no severe thermal throttle across three
   consecutive turns.
4. The v3 fine-tune published with an Apache-2.0 model card, a pinned revision
   and SHA-256, and a resumable download (#445).
5. A tested fallback on a 6 GB phone and on a device that cannot run the model,
   including low storage and an interrupted download.

If the first three gates fail, keep the model as an offline fallback and do not
spend more on a 4B default. Lean on the platform AI (#329) only where it
scores, and on desktop Ollama or cloud providers for daily quality.

## Next work

- #328: one probe run of the slim prompt on the S23 Ultra (4 and 8 CPU
  threads, stock and v3 if side-loadable).
- #445: choose the Hugging Face model repo and publish v3.
- #532: steer `create_note` to the collection note that `related_notes` found.

## Sources

- `docs/model-eval.md`: baselines, fine-tunes v1-v4, slim prompt.
- `docs/latency-investigation.md`: emulator probe.
- #227 comments: S23 spike, prompt token breakdown, runtime decision.
- `packages/notelore_core/lib/src/providers/local.dart`,
  `apps/notelore/lib/src/device_model.dart`,
  `apps/notelore/lib/src/device_native.dart`.
