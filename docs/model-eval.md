# On-device model eval (#227)

Notelore should run on a free model on the user's device, with no server of our own. Paid plans and keys stay options. This page records how small open models do on the eval set (`eval/cases.json`, run with `notelore_dev eval`), so the default model is chosen by measurement.

Decision and risks: [on-device-model-feasibility.md](on-device-model-feasibility.md).

## Baseline, 2026-10-18 (#326)

Setup: 38 cases (EN and TR) through the Ollama provider, with `num_ctx` 16384 and `think: false` (#336). Hardware: an RTX 4070 laptop (8 GB), Ollama 0.40.5, Q4 models as Ollama ships them. A case passes only if the right tools were called, only the expected notes changed, they hold the expected facts, and the answer has the expected facts.

| Model | All | Questions | Collection notes | Filing | Decisions | Todos (add / done) | Median time per case |
|---|---|---|---|---|---|---|---|
| qwen3:4b | **26/38 (68%)** | 10/10 | 4/9 | 2/4 | 2/4 | 1/2 · 0/2 | 52 s |
| qwen3-coder:30b (MoE, 3B active; teacher candidate) | 24/38 (63%) | 7/10 | 1/9 | 3/4 | 3/4 | 2/2 · 1/2 | 7.1 s |
| qwen3-vl:8b | 10/38 (26%) | 1/10 | 2/9 | 1/4 | 1/4 | 1/2 · 1/2 | 178 s |
| qwen3:4b-instruct-2507 (non-thinking) | 10/38 (26%) | 4/10 | 1/9 | 0/4 | 0/4 | 0/2 · 0/2 | 1.3 s |
| llama3.1:8b | 11/38 (29%) | 6/10 | 1/9 | 0/4 | 0/4 | 0/2 · 0/2 | 2.6 s |
| qwen3:1.7b | 10/38 (26%) | 5/10 | 0/9 | 2/4 | 0/4 | 0/2 · 0/2 | 0.7 s |
| phi4-mini | 4/38 (11%) | 1/10 | 0/9 | 0/4 | 0/4 | 0/2 · 0/2 | — |
| llama3.2:3b | 2/38 (5%) | 0/10 | 0/9 | 0/4 | 0/4 | 0/2 · 0/2 | — |
| gemma3:4b | not run | | | | | | Ollama's gemma3 has no tool calling |

Findings:

- **Qwen3 4B is the only usable baseline.**
  - It answers every question from the notes and handles new notes, archive, small talk and unclear requests.
  - It fails the cases a fine-tune targets:
    - it opens a note named after a book or film instead of adding to the collection note (the #293 mistake);
    - it does not complete todos;
    - it writes notes in the wrong language.
  - It is slow (52 s median). Ollama's `qwen3:4b` is the thinking variant, and with `think: false` it still writes long reasoning into the answer. A non-thinking instruct build is the next run.
- **Thinking buys the quality.** The non-thinking instruct build of the same 4B is 40 times faster (1.3 s) but drops to 26%. It skips writes, puts facts into new notes and answers questions without reading. This is the gap a fine-tune closes: teach the fast non-thinking model the right tool calls from a stronger teacher's correct turns (distillation, #327).
- **No local model is a clean teacher.** Qwen3 4B thinking (68%) and Qwen3-Coder 30B (63%) are the best, and every model fails collection notes, which points at the prompt as much as the model (#293). So the training data is filtered: the teacher plays generated turns, the eval's scorer keeps only the turns that pass, and only those train the student. A wrong teacher answer never reaches training.
- **Distill filters teacher detours (#381).** In addition to the eval pass, `notelore_dev distill` drops turns with a tool result starting `Error` or a repeated call with the same name and arguments. It reports the count for each reason; a turn with both reasons appears in both counts. A read repeated with the same arguments and the same result (a second identical `list_notes`, say) is not a reason: it taught nothing, so it is dropped from the example, with its step when it was the step's only call, and the turn is kept (#447's analysis: this filter had dropped most of the passing reminder and todo-done turns). Earlier training files are unchanged.
- **Distill resumes (#327).** Each kept turn is appended to the output as its case ends, and the finished case ids go to `<out>.done`. A run that was stopped (out of memory, hours in) loses nothing; rerun the same command and it skips the ids in `.done`. A turn written just before the stop, whose case was not yet marked, is dropped and run again, so no example is kept twice. Failed and left-out cases count as finished too, so a rerun does not retry them, and its pass rate and `kept N of M` cover only the cases it ran. Delete `.done` to start over; without it a run empties the output first.
- **A tool that fails, and words the answer must not have (#474).** A case with `"fail_first_call": true` gets an error for its first tool call; the model must fix the call and go on. `answer_not` lists words the answer must not hold (a tool's name, an apology), so a turn that hands the error to the user fails. `distill` keeps such a turn: the injected error is no tool error, and its retry no repeated call, since recovering is what the student should learn. v3 in daily use had turned a failed `related_notes` into an English question to the user; the prompt now says to fix the call and never name a tool, and a missing or unknown argument's error shows the whole call (`Call it as related_notes({"title": string, "about"?: string})`).
- **A case's own web (#478).** A case with `search` results gets a `web_search` tool that answers with them, the same every run and on the eval's own day (a real search would find this week's derby, not the eval's). It runs only for a provider that can search in the app (`ProviderSpec.webSearch`); elsewhere `eval` leaves it out and says how many.
- **A held-out set (#599).** `eval/holdout.json`, written by `tool/train/holdout.py`: 292 cases built like the training scenarios from notes, items and sentences of their own (a test checks that no title, message or listed item appears in the training scenarios or in `eval/cases.json`), at least 15 of every kind, and 16 cross-language cases (an English message about a Turkish note and the reverse). Run it with `eval --cases=eval/holdout.json`. v3 on the slim prompt, one sampled run: 157/292 (54%); unclear 1/15, todo-done 2/20, reminder 4/15 (it guesses a slug and creates a new note), new notes 15/15. The publish threshold of #445 (80%) is measured on this set.
- **Greedy, repeated runs and the answer's language (#597).** `eval --greedy` asks Ollama for temperature 0, so a run gives the same result every time; `--runs=N` repeats the set and prints each run's total before the kinds over all runs. A case fails when the answer is in another language than the user's, told by each language's small words with quoted text left out. v3 on the slim prompt, greedy, two runs: 20/44 and 20/44, against 31 and 26 sampled the same day. Greedy shows the model's most likely choice, and for v3 that choice is often wrong where sampling sometimes finds the right one: decisions 0/8 greedy against 2–4 of 4 sampled, todo 0/4. Two of the failures are an English question answered in Turkish. Model comparisons from here on are greedy; a sampled `--runs=3` shows what a user meets.
- **One prompt per training file.** Examples distilled at different times carry the system prompt and tools of their day. `notelore_dev reprompt --in=<file> --out=<file> [--slim]` gives every example today's prompt and tools and keeps its turns as they were, so a model never learns two versions of the rules (v3.1).
- **A slim prompt for the model on the device (#447).** A phone reads the whole prompt before the first word, so the model on the device gets the same rules in fewer words, without web search or pictures, and without `merge_notes`, `find_stale_notes` and `decision_history`; desktop and cloud models keep the full prompt. Measured through Ollama's Qwen3-4B-2507 template with one user message, the prompt is 1,828 tokens instead of 3,128 (system 555 instead of 1,335), 42% fewer. `eval --slim` and `distill --slim` ask and train that way. With v2, which was trained on the full prompt, the 40 cases of `eval/cases.json` scored 21/40 (53%) full and 19/40 (48%) slim, at 2.2 s and 1.7 s per turn on average: slim did better on collections (5/9 against 1/9) and worse on questions (5/10 against 9/10) and reminders (0/2 against 1/2). That gap is the case for v4: distilled and trained on the slim prompt.
- **Below 4B, tool use falls apart:** the models skip the write, loop on `create_note`, or answer without tools.
- **Next:**
  - run `qwen3:4b-instruct-2507` (non-thinking), FunctionGemma 270M and Gemma 3n through a runtime that supports their tool format;
  - add a hosted model as the ceiling;
  - fine-tune the best one (#327) on the failing kinds: collection notes, todo completion and note language.

## Fine-tune v1, 2026-10-18 (#327)

**Setup**
- Student: Qwen3-4B-Instruct-2507, trained with QLoRA (r=16, 3 epochs) by `tool/train/finetune.py`.
- Data: 120 turns that two teachers played on the generated scenarios (`tool/train/scenarios.py`, none from the eval set), kept only when the eval's scorer passed them. 66 came from qwen3:4b and 54 from qwen3-coder:30b.
- Served: merged, then converted to a Q4_K_M GGUF (2.5 GB) and run by Ollama.
- Eval: the same 38 cases, with the prompt that has the todo rule (#349). All three models were rerun on that prompt.

| Model | All | Questions | Collection notes | Filing | Decisions | Todos (add / done) | Median time per case |
|---|---|---|---|---|---|---|---|
| **notelore-qwen3-4b-v1** (fine-tuned) | **23/38 (61%)** | 8/10 | 3/9 | 3/4 | 3/4 | 1/2 · 0/2 | **2.1 s** |
| qwen3:4b-instruct-2507 (the untuned student) | 12/38 (32%) | 5/10 | 1/9 | 1/4 | 0/4 | 1/2 · 0/2 | 1.8 s |
| qwen3:4b, thinking (the teacher) | 26/38 (68%) | 9/10 | 5/9 | 2/4 | 1/4 | 2/2 · 1/2 | 68 s |

Findings:

- **Fine-tuning nearly doubles the student at the same speed.** v1 is 7 points behind the thinking teacher at about 32 times its speed. The goal is ≥70% at instruct speed.
- **v1 overfits.**
  - Training loss fell from 2.0 to 0.06.
  - It files most collection items into "Okumakta olduğum kitaplar", a note from its training data, whatever the item is.
  - The next run needs many more, more varied scenarios, fewer epochs and a held-out split.
- **No todo-done yet:** the training data had almost no completed-todo turns. With the #349 rule the teacher now ticks one of the two cases, so v2's data can have them.
- **Slug case:** two of v1's failures were the slug `Mopsos` for `mopsos.md`. On Windows that renamed the note; on Android it failed. The tools now find a note whatever the case (#367).
- **The run is slow because of memory, not length.**
  - Each training turn is 2.7–3.1k tokens, mostly the system prompt and the tool schemas.
  - 45 steps took about 5 h 20 min (about 7 min a step) at 7.9 of 8 GB. That points to spilling into shared memory.
- **Ollama on Windows** cannot import or quantize safetensors: that path needs its MLX runtime. The working route is llama.cpp's `convert_hf_to_gguf.py`, then `llama-quantize` to Q4_K_M, then `ollama create` with the template the base model ships with. `finetune.py`'s docstring has the steps.

## Fine-tune v4, 2026-10-20 (#447)

**Setup**
- Student: Qwen3-4B-Instruct-2507, QLoRA, one epoch, loss on the assistant's tokens only (as v3), trained on Kaggle's T4.
- Data: 223 turns on the slim prompt and tools (`distill --slim`, then `reprompt --slim`). 122 came from qwen3:4b and 101 from qwen3-coder:30b; 209 scenarios, none overlapping the eval. The teachers rarely passed `plan` (3 of 12), `recovery` (3 of 8) or `todo-done` (10 of 32), so those kinds are thin.
- Eval: the 44 cases of `eval/cases.json` on main after #500 (one web-search case is left out on Ollama). v3 was measured again on the same cases.

| Model | Slim (as on the device), two runs | Full prompt, one run |
|---|---|---|
| notelore-qwen3-4b-v3 | 23/44, 22/44 | 28/44 (64%) |
| notelore-qwen3-4b-v4 | 21/44, 24/44 | 18/44 (41%) |

Findings:

- **On the slim prompt v4 is no better than v3.** Both average 22.5/44 over two runs. Between v3 and v4, 18 cases flip one way or the other, so one run carries a noise of about ±2 cases. One run of 44 cannot tell models apart that are a few cases apart.
- **On the full prompt v4 falls from 28 to 18.** It was trained only on the slim prompt and tools. v3 stays the better model for a desktop that sends the full prompt.
- **Collection notes stay the main failure for both** (2–4 of 10). The model calls `related_notes`, sees the list note, and still runs `create_note` with the item's own title ("Perfect Days", "Kürk Mantolu Madonna"). More distilled turns of the same kind did not teach it. The next step is on the tool side, not v5: steer `create_note` toward the collection that `related_notes` found.
- **v3 stays the on-device candidate.** v4 is kept in Ollama as `notelore-qwen3-4b-v4` for comparison and is not published.
