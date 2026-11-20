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
- **First write, and cases at once (#598).** `eval --first-write` ends each turn right after its first write (a note made for it does not count) and scores that write: the right tool, into the right note, with the facts. The report then counts, over the failed cases, what each wanted first against what it did (`complete_todo → add_note_entry: 2`), the confusion the training round works on. It saves the rest of the turn and the answer, about a sixth of the time on v3 (105 s against 127 s for the 44 cases). `--parallel=N` runs N cases at once for a server that serves them (`OLLAMA_NUM_PARALLEL`, a cloud model); on an 8 GB laptop GPU two 16k contexts did not fit and ran slower than one.
- **Teachers from OpenCode Go (#604).** `--provider=opencode --model=<id>` runs a model of the maintainer's OpenCode Go plan through its OpenAI-compatible endpoint; the key is `NOTELORE_OPENCODE_API_KEY`, in the environment or in `.dev-home/state/dev-secrets.json`. Only open-weight models whose licenses allow distillation teach (GLM, Kimi, DeepSeek); the plan's GPT, Claude, Gemini and Grok do not. The plan caps each model's spend per five hours, week and month.
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

## Fine-tune v5, 2026-10-25 (#532)

**Setup**
- Student and training as v4: Qwen3-4B-Instruct-2507, QLoRA, one epoch, loss on the assistant's tokens only, on Kaggle's T4.
- Data: v4's 223 turns plus 36 collection turns, all on today's slim prompt (`reprompt --slim`), 259 in all. The new turns came from qwen3:4b on 101 collection scenarios (#591: 20 first-of-their-kind items and a workspace of mixed lists); 36 passed and were clean.
- Eval: the 44 cases of `eval/cases.json` on main at 8ad1e12. v3 was measured again on the same cases, on the same day.

| Model | Slim (as on the device), two runs | Full prompt, one run | Collection (slim, two runs) |
|---|---|---|---|
| notelore-qwen3-4b-v3 | 31/44, 26/44 | 27/44 (61%) | 7/10, 6/10 |
| notelore-qwen3-4b-v5 | 26/44, 25/44 | 26/44 (59%) | 5/10, 5/10 |

Findings:

- **v5 is no better than v3, and worse on collection notes**, the kind it was trained for. With the empty-result steer of #533, v3 already files 6–7 of 10 collection items into the list; v5 files 5.
- **The extra collection data over-taught the list.** v5 writes into a reading list ("okumakta-oldugum-kitaplar") in cases about decisions, todos and reminders: 2–4 times per run, against 0–2 for v3.
- **v3 stays the on-device candidate.** v5 is kept in Ollama as `notelore-qwen3-4b-v5` for comparison and is not published. More distilled turns of one kind shift the model toward that kind instead of teaching the choice; the next gains are on the prompt and tool side.

## Quantization, 2026-10-26 (#606)

**Setup**
- Model: v3, quantized four ways from the same bf16 GGUF with llama.cpp.
- Ollama: run with `OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q8_0`. Without them Q8 did not fit the 8 GB GPU and every case timed out.
- Eval: greedy (`--greedy`), slim. The 44 cases are run twice; the held-out set (`eval/holdout.json`, 292 cases, #599) once.

| Quantization | Size | 44 cases (2 runs, identical) | Held-out |
|---|---|---|---|
| **Q4_K_M** | 2.5 GB | 27/44 | **183/292 (63%)** |
| Q4_K_M + imatrix (150 v6 turns) | 2.5 GB | 30/44 | 163/292 (56%) |
| Q5_K_M | 2.9 GB | 27/44 | — |
| Q8_0 | 4.3 GB | 29/44 | — |

Findings:

- **Plain Q4_K_M stays.**
  - The imatrix lead on 44 cases reverses on the held-out set: 7 points behind.
  - Q5 gains nothing.
  - Q8 gains two cases of 44 for almost twice the size, and is too big for the phone.
- **44 cases cannot rank models a few cases apart.** Decisions between quantizations, and between fine-tunes, are taken on the held-out set.

## Fine-tune v6 and v7, 2026-10-28 (#327)

**Setup**
- Student: Qwen3-4B-Instruct-2507, QLoRA r=16, one epoch, loss on the assistant's tokens only, trained on Kaggle's T4.
  - A tenth of the cases is held out for the validation loss; the best checkpoint is kept.
- v6 data: 756 turns of glm-5.3-flash and glm-5.3 (OpenCode Go), on 302 of the 323 scenarios of `scenarios.py` v6 (#604).
  - Scenario labels were fixed in #627: no other list of the same kind in a list case, and no choice-like fact filed as a plain entry.
- v7 data: v6's turns with the 39 done-like ones replaced by 52 turns re-distilled under the #628 prompt, all of which read the note first.
- Served: Q4_K_M, as #606 decided. Eval greedy and slim; held-out as regenerated by #628 and #630.

| Model | Held-out (292) | 44 cases × 2 | Held-out todo-done |
|---|---|---|---|
| v3 | 183 (63%)\* | 54/88 (61%) | 1/20\* |
| **v6** | 228 (78%)\*, 220 (75%) | 60/88 (68%), 64/88 (73%) | 0/20\*, 2/20 |
| v7 | 220 (75%) | 62/88 (70%) | 1/20 |

\* On the held-out set before #628, which did not yet ask a `done-other` case to read the note. v3's 44-case figure is from before #628 too; v6's second figures, in both columns, are with the #628 prompt.

Findings:

- **v6 is the best model so far, 12–15 points over v3 on the held-out set.**
  - Decisions: 8 → 16/18.
  - Todos: 10 → 18/19.
  - Unclear messages: 1 → 10/15.
  - Plans: 7 → 11/15.
- **No model reliably ticks a todo the user says is done: at most 2/20.**
  - The slim prompt had no rule to read the note first. The rule to tick lives in the `read_note` result (#601), so the read never came. #628 adds the rule.
  - The data taught the same: half of the done-like turns were updates filed with a bare `add_note_entry`.
  - v7 has 52 read-first done turns. They do not outweigh 100+ updates filed straight away, and the two kinds of message look alike ("Home studio: I bought the mic" against "Home studio: the desk goes by the window").
- **Listing the open todos in `add_note_entry`'s result was tried and dropped.**
  - todo-done rose to 18/20.
  - But v7 then ticked a todo on nearly every plain update, and the eval passed those turns. #630 lets a case rule out a tool, and updates now rule out `complete_todo`.
- **New-list collections regress on the 44 cases (v3 14/20 → v6 8/20).** v6 files "Movie to watch: Perfect Days" in the reading list instead of starting a film list.
- **Next: DPO on the student's own failures (#607).** Telling a done message from an update, and starting a list of a new kind, are contrasts. A preference pair shows them directly, where more SFT turns of one kind did not.

## DPO on the student's own failures, 2026-11-03 (#607)

**Setup**
- Pairs: 464 from v7's failed turns on a third scenario set (`dpo_set.py`, 292 cases, disjoint from training and held-out). Each failed turn is paired with a passing turn of its case, v7's own or glm-5.3-flash's.
- Training: TRL's DPO on v7's LoRA, beta 0.1, lr 5e-6, one epoch on Kaggle's T4. The run was cancelled at step 50 of 52; the step-50 checkpoint is the model.
  - Validation reward accuracy rose from 0.77 to 0.79, and the margin from 0.17 to 0.29.
- Served and evaluated like v7: Q4_K_M, greedy, slim.

| Model | Held-out (292) | 44 cases × 2 | Held-out todo-done |
|---|---|---|---|
| v7 | 220 (75%) | 62/88 (70%) | 1/20 |
| v7 + DPO | 215 (74%) | 64/88 (73%) | 3/20 |

Findings:

- **DPO did not move the model.** Both sets are within one run's noise of v7.
  - todo-done: 1 → 3/20; recovery: 12 → 13/15.
  - plan: 12 → 10/15; decision: 15 → 14/18.
- **The pairs taught the preference but not the behaviour.** Validation reward accuracy reached 0.79, yet greedy decoding keeps v7's choices. Likely, at beta 0.1 and this learning rate, one epoch moves the log-probabilities too little to flip the top token.
- **v7 stays.** The DPO model is kept in Ollama as `notelore-qwen3-4b-dpo` for comparison and is not published.

## A tick hint on matching entries, 2026-11-05 (#731)

**Setup**
- Change: `add_note_entry`'s result names each open todo of its note that shares a word stem with the entry (first four letters; the note's title words and a few common words left out), with the `complete_todo` call. Listing every open todo was dropped in #327 because the model then ticked on plain updates; a matching word is rare in an update.
- Model: v7, Q4_K_M, greedy, slim, flash attention and q8_0 KV cache. Before is main at the same commit without the change.

| | Held-out (292) | 44 cases × 2 | Held-out todo-done |
|---|---|---|---|
| before | 221 (75.7%) | 64/88 (73%) | 1/20 |
| after | **233 (79.8%)** | **68/88 (77%)** | **14/20** |

Findings:

- **The biggest single gain since the note list in the prompt:** +12 held-out cases, all of them done messages that were filed as plain entries before (in English and Turkish, and one cross-language). On the 44 cases, todo-done goes 0/4 → 4/4.
- **One false tick:** "İki referans mektubu gerekiyor" shares *mektub* with the todo "Niyet mektubunu yaz", and the model ticks it. Asking for two shared stems would fix it but lose "Balkon bahçesi: toprak alındı" against "Toprak satın al", so the rule stays at one.
- **Still failing:** the `done-other` updates (8/8 fail before and after: they expect the note read first) and cross-language done messages, which share no word with the todo ("statement of purpose" against "Niyet mektubunu yaz").
- Every other kind is unchanged.

## Done updates no longer need a read, 2026-11-05 (#733)

**Setup**
- `done-other` cases ("Home studio: I recorded a test take of the guitar.") expected `read_note` before `add_note_entry` (#628), only so the model would see the open todos. Since #731 the entry's result names a matching todo, so these cases now expect the entry alone and still rule out `complete_todo`. The held-out set is regenerated; only those 8 cases change.
- v7, Q4_K_M, greedy, slim.

| | Held-out (292) | 44 cases × 2 |
|---|---|---|
| #731 | 233 (79.8%) | 68/88 |
| #733 | **241 (82.5%)** | 68/88 |
| #733 without the slim prompt's read-first rule | 236 (80.8%) | 68/88 |

Findings:

- **All 8 `done-other` cases pass:** the entry is filed and nothing is ticked. They had failed on the missing read alone.
- **The read-first rule in the slim prompt stays.** Without it, held-out todo-done drops 14 → 12/20 and unclear 9 → 7/15, so it still steers the model on messages the entry's hint does not reach.
- **v7 with #731 and #733 is past the 80% held-out threshold of #445.**

## LoRA rank 32, 2026-11-05 (#605)

**Setup**
- v7's data and recipe (train-v7, one epoch, the loss on the answer alone, learning rate 2e-4), with rank 32 and alpha 64 instead of 16 and 32.
- Trained on Kaggle's T4 in 7.6 hours. The validation loss fell from 0.541 to 0.497 and was still falling at the last step.
- Q4_K_M, greedy, slim, on main with #731 and #733.

| | Held-out (292) | 44 cases × 2 |
|---|---|---|
| v7, rank 16 | 241 (82.5%) | 68/88 |
| rank 32 | 242 (82.9%) | 68/88 |

Findings:

- **Rank does not matter here:** one held-out case apart, within the noise. The kinds that fail are the same: unclear 5/15, collection 55/73.
- **The data is the limit, not the adapter's size.** The next run, v8, keeps rank 16 and doubles the data (#604).
- A local two-epoch run was dropped: at 240–770 s a step on the laptop GPU, it would have taken over a day. Runs longer than a Kaggle session now stop saved and resume (#740).

## Fine-tune v8, 2026-11-06 (#604)

**Setup**
- v8 data: 1,542 turns from 579 scenarios, twice v7's 769. It is v7's turns plus 773 new ones distilled by glm-5.3-flash, with glm-5.3 for the scenarios flash never passed.
- v7's recipe: rank 16, one epoch, the loss on the answer alone, learning rate 2e-4.
- Trained on Kaggle's T4 across two sessions (#740), 174 steps in about 16 hours, about 2.5 of them in the five validation passes (27–30 minutes each). The validation loss fell from 0.402 at step 40 to 0.334 at the last step.
- Q4_K_M, greedy, slim, on main with #731 and #733.

| | Held-out (292) | 44 cases × 2 |
|---|---|---|
| v7 | 241 (82.5%) | 68/88 (77%) |
| v7, rank 32 | 242 (82.9%) | 68/88 (77%) |
| **v8** | **255 (87.3%)** | **72/88 (82%)** |

Held-out by kind, v7 → v8: unclear 9 → 14/15, todo-done 14 → 16/20, filing 30 → 32/36, question 34 → 36/36, decision 16 → 17/18, new-note 13 → 14/15, collection 53 → 54/73. No kind drops.

Findings:

- **More data is the first training change that moves the model.** +14 held-out cases, where DPO and rank 32 stayed within one case of v7.
- **Unclear messages gain the most**, 60% → 93%: the model now asks back instead of guessing.
- **Collection stays the weakest kind**: 54/73 held-out and 12/20 on the cases.
- On the 44 cases, decision drops 8 → 6/8 and question 18 → 16/20. That is two runs of greedy decoding on few cases, but these are the ones to watch in the next run.
- **v8 replaces v7.** It is in Ollama as `notelore-qwen3-4b-v8`.

## A one-line plan before the first tool call, 2026-11-08 (#608)

**Setup**
- v7's data with a `plan: <note> → <action>` line written into each turn's first tool call, derived from the verified turn (#789). v7's recipe, trained on Kaggle.
- The rule agreed beforehand: keep the plan line only at +5 points of first-call accuracy (`--first-write`).
- Q4_K_M, greedy, slim.

| | Held-out (292) | Held-out, first write | 44 cases | 44 cases, first write |
|---|---|---|---|---|
| v7 | 240 (82%) | 229 (78%) | 34 (77%) | 32 (73%) |
| v7 + plan | 242 (83%) | 229 (78%) | 36 (82%) | 34 (77%) |
| v8 (for scale) | 255 (87.3%) | | | |

Held-out by kind, v7 → v7 + plan: collection 52 → 62/73, todo-done 14 → 16/20, question 34 → 35/36; decision 16 → 11/18, new-note 14 → 12/15, unclear 9 → 8/15, plan 11 → 10/15, chat 15 → 14/15.

Findings:

- **Dropped.** First-call accuracy on the held-out set does not move (229 both), far from the +5 points.
- **The plan line trades decisions for collections.** It picks the right list ten more times, but files five more decisions as plain entries. That trade is not worth a format the app has to strip.
- **More data beats it**: v8 alone is 13 held-out cases ahead of the plan run.

## Fine-tune v9, 2026-11-11 (#604)

**Setup**
- v9 data: 2,064 turns, v8's 1,542 plus 522 new ones (#830).
- v8's recipe: rank 16, one epoch, the loss on the answer alone, learning rate 2e-4.
- Trained on Kaggle's T4 across several sessions, 232 steps. The validation loss fell from 0.453 to 0.349 at the last step, which is the adapter kept.
- Q4_K_M, greedy, slim. v8 was measured again on the same code: the case set has grown to 46 since v8's run, and the code under it changed.

| | Held-out (292) | 46 cases × 2 | About me (14), full prompt |
|---|---|---|---|
| v8 | 259 (88.7%) | 72/92 (78%) | 7 (50%) |
| **v9** | **260 (89.0%)** | **81/92 (88%)** | 7 (50%) |

Held-out by kind, v8 → v9: unclear 14 → 15/15, reminder 12 → 13/15, plan 13 → 14/15, collection 55 → 56/73; filing 32 → 31/36, chat 15 → 13/15. The other kinds are unchanged.

On the 46 cases, v8 → v9 over both runs: decision 4 → 8/8, question 16 → 20/20, collection 12 → 13/20. Every other kind is the same.

Findings:

- **v9 holds v8's level on the held-out set**, one case ahead and within the noise. The 522 new turns did not move what v8 already did well.
- **The gain is on the cases**: +9 over two runs, all of it decision and question, the two kinds v8 lost against v7.
- **Collection is still the weakest kind**: 56/73 held-out, 13/20 on the cases. Most of its misses add to an existing list when the item belongs on a new one (`newlist-*`), or put a film or a recipe on the books list.
- **About me is measured without `--slim`.** The about-me tools are not among the device model's tools (`slim: false`, #447), so a slim run cannot pass it: both models score 1 of 14 that way. The desktop runs the local model with the full prompt and tools.
- **With the full prompt both models remember new facts but never update one**: 7 of 14 each. They call `remember_about_me` where a listed fact changes or gains a detail (5 cases), for a fact already listed, and when asked to move a fact from a note. Neither data set has an about-me turn.
- **v9 can replace v8 on the desktop** (#834). It is in Ollama as `notelore-qwen3-4b-v9`.

## Fine-tune v10, a negative result, 2026-11-14 (#604)

**Setup**
- v10 data: 2,164 turns, v9's plus 100 new ones: 93 about-me turns (update, already known, forget, move to or from a note, facts that are not about the user) and 7 more for new lists (`newlist-*`). The about-me turns use the full prompt and tools, since slim mode has no about-me tools. All the other turns are slim.
- v9's recipe: rank 16, one epoch, the loss on the answer alone, learning rate 2e-4. One session on Kaggle's T4, 244 steps. The validation loss fell from 0.432 to 0.333 at step 240, which is the adapter kept.
- The precision changed too (#907). The about-me turns are about 4.9k tokens, against 3.1k at most before. In the T4's emulated bf16, attention has only the math kernel, whose memory grows with the square of the length, and the first run ran out of memory. v10 trained in fp16 with the LoRA in fp32. v9 trained in emulated bf16.
- Q4_K_M, greedy, the same code for both models (ffc21f8). The cases are measured slim (two runs) and with the full prompt (one run).

| | Held-out (292), slim | Held-out, full | 47 cases × 2, slim | 47 cases, full | About me (14), full |
|---|---|---|---|---|---|
| **v9** | **257 (88.0%)** | **256 (87.7%)** | **81/94 (86%)** | **39/47 (83%)** | 7 (50%) |
| v10 | 255 (87.3%) | 255 (87.3%) | 77/94 (82%) | 38/47 (81%) | **8 (57%)** |

The full-prompt cases first scored 33/47. Nine of the failures were timeouts on the last nine cases in a row. One of them, `rem-tr-1`, loops (below), and the other eight queued behind its runner and timed out. Run alone, five of those eight pass, so the table gives 38.

Held-out by kind, v9 → v10. Slim: collection 54 → 58/73, chat 13 → 15/15; plan 14 → 11/15, and filing, new note, question, todo and unclear one lower each. Full: collection 57 → 61/73, decision, new note and recovery one higher each; plan 13 → 10/15, reminder 14 → 12/15, unclear 12 → 10/15, todo one lower.

Findings:

- **v10 is not better than v9.** It gains on collection (+4 held-out in both modes) and on about me (+1: it now updates `aboutme-en-update` instead of adding a second fact). It loses on plan and on the slim question cases: `q-tr-1` and `q-tr-5` call `get_decision` in both runs. The total is down everywhere but about me.
- **v10 can fall into a repetition loop.** On `rem-tr-1` ("5 dakika sonra bana kitap okumayı hatırlat") with the full prompt, it calls `add_reminder` correctly. After the tool returns, its reply is "5 dakika sonra kitap okumayı hatırlatma hatırlatma hatırlatma…" and never ends: the runner was at 59k tokens when it was killed. This happens every time, greedy. v9 answers the same case in 2.6 s, and the slim prompt does not trigger it. Nothing caps a local model's reply, so a loop hangs the chat (#908).
- **The data causes the loop, not fp16.** v9's data trained with v10's fp16 recipe (v9fp16: 232 steps, validation 0.445 → 0.349, the same curve as v9 in bf16) has no timeout in any run. Replaying v10's looping turn with the reply capped at 400 tokens, v9fp16 answers in 36 tokens and v9 in 34, while v10 hits the cap. The 93 about-me turns are the only full-prompt turns in v10's data, and the loop shows only under the full prompt.

| | Held-out, slim | Held-out, full | Cases × 2, slim | Cases, full | About me |
|---|---|---|---|---|---|
| v9 (bf16) | 257 | 256 | 81/94 | 39/47 | 7 |
| v9fp16 | 253 | 256 | 78/94 | 41/47 | 7 |
| v10 | 255 | 255 | 77/94 | 38/47 | 8 |

- **fp16 costs nothing measurable.** With the full prompt v9fp16 equals v9 (held-out) or beats it (cases +2). It is a little lower slim (−4 held-out, −3 cases), within what two runs of one recipe differ by.
- **v9 stays the desktop model.** v10 is in Ollama as `notelore-qwen3-4b-v10`, for comparison only.

## A bounded note list, 2026-11-14 (#895)

`list_notes` returns at most the 30 newest notes now. With more notes, it adds the total and a line telling the model to use `search_notes` before `create_note` ([scale.md](scale.md)). A case can bring `"filler": N` invented notes, all newer than its own, so its note is not among the newest. The seven `scale` cases in `eval/cases.json` use 80. v9, `--greedy`, before → after:

| set | before | after |
|---|--:|--:|
| held-out, slim | 257/292 | 259/292 |
| cases, slim, 2 runs | 89/108 | 87/108 |
| held-out, full | 256/292 | 260/292 |
| cases, full | 39/54 | 42/54 |
| about me, full | 7/14 | 7/14 |
| scale cases alone, slim | 8/14 (2 runs) | 12/21 (3 runs) |

- **Small folders get the same prompt as before.** A first try changed the prompt's note-list heading for every folder. After that change, three held-out cases that had passed failed when rerun alone (plan-9, unclear-5, unclear-8). The heading now changes only above 30 notes, so a smaller folder's requests are byte for byte what they were. Rerun 3 times alone, before → after: plan-9 2/3 → 3/3, unclear-5 1/3 → 3/3, unclear-8 3/3 → 2/3, coll-en-1 3/3 → 3/3. Greedy decoding on the GPU still varies from run to run.
- **Without the extra line, the bound cost one case.** scale-tr-4 (add a book to a reading list it cannot see) passed 2/2 before the bound, because the old list showed every note; with the bound alone it failed 0/2, making a duplicate list despite `create_note`'s pointer to the right note. With "call it before create_note" it passes 2/3.
- **The other scale misses are v9 filing into a note it can see.** scale-tr-3 and scale-en-3 write into an unrelated invented note from the prompt's list, before and after.
- **With the full prompt, v9 never answers a scale case.** When the note named in the message is not in the prompt's list, it calls `get_decision` on every listed slug until the call times out (180 s). This is the same before and after.
- At 2,000 notes the unbounded list was about 51,000 tokens, more than the device model's 16k context, so the before column is only possible on small folders.
- ChatGPT has not been measured yet.

## Fine-tune v11, 2026-11-15 (#604)

**Setup**
- v11 data: 2,464 turns, re-prompted at e71e53a. 2,071 slim turns (v10's), the 93 about-me turns with the full prompt, and 300 of v9's turns with the full prompt too: every reminder (74) and plan (52) turn, 80 questions and 94 spread over the other kinds. In v10 the about-me turns were the only full-prompt turns, and the loop showed only under the full prompt.
- v9's recipe in fp16 (#907): rank 16, one epoch, the loss on the answer alone, learning rate 2e-4. One session on Kaggle's T4, 278 steps. The validation loss fell from 0.420 to 0.314 at the last step, which is the adapter kept.
- Q4_K_M, greedy, the same code for both models (e71e53a). v9 was measured again there.

| | Held-out (292), slim | Held-out, full | 47 cases × 2, slim | 47 cases, full | About me (14), full |
|---|---|---|---|---|---|
| v9 | 257 (88.0%) | **256 (87.7%)** | 81/94 (86%) | 39/47 (83%) | 7 (50%) |
| **v11** | 257 (88.0%) | 255 (87.3%) | **84/94 (89%)** | **41/47 (87%)** | **9 (64%)** |

Held-out by kind, v9 → v11. Slim: collection 54 → 59/73, chat 13 → 15/15; filing 31 → 29/36, unclear 15 → 13/15, and recovery, todo and todo-done one lower each. Full: collection 57 → 59/73, todo-done 16 → 18/20, new note one higher; unclear 12 → 9/15, and recovery, reminder and todo one lower each.

On the cases, slim over both runs: collection 13 → 20/20; question 20 → 18/20 and todo-done 4 → 2/4. With the full prompt, v11 passes `coll-tr-3`, `coll-en-4`, `coll-en-5` and `q-en-3` and fails `coll-en-3` and `coll-tr-empty`.

Findings:

- **v11 does not loop.** No full-prompt run timed out. Replaying v10's looping turn (`rem-tr-1`, after the tool result) with the reply capped at 400 tokens, v11 answers in 34 tokens, like v9. Run alone, `rem-tr-1`, `rem-en-1`, `rem-tr-title` and `plan-en-1` all end on their own for both models, in 26 to 60 tokens. (`plan-tr-search` needs web search and is not run by the eval.)
- **v11 keeps v10's gains without its losses.** Collection is up in every set, and about me is 9 of 14: it now updates `aboutme-en-update` and `aboutme-en-change-age` instead of adding a second fact. The plan losses of v10 are gone (held-out plan equal to v9 in both modes).
- **Unclear is v11's weak kind.** With the full prompt it asks in 9 of 15 held-out cases against v9's 12, and acts instead. The slim prompt shows it less (13 against 15).
- **v11 is the best model so far on the cases and on about me, and equal on the held-out set.** It is in Ollama as `notelore-qwen3-4b-v11`.

## The prompt's note list chosen by the message, 2026-11-15 (#914)

The system prompt lists the newest notes, so a message about an older note gets no slug for it unless the model calls `search_notes`. `eval --note-list=<order>:<n>` picks the list another way, to compare: `matches` lists the notes the index search finds for the message, best first; `mixed` tops those up with the newest; `newest:<n>` keeps today's order at another size. A folder of at most `n` notes keeps today's list. Six new `scale` cases (filler 80) name an old note only by its words: scale-en-4, scale-en-5, scale-en-6, scale-tr-5, scale-tr-6, scale-tr-7.

Without a model, on the 13 `scale` cases: the newest list holds the target note in none; `matches` and `mixed` at 10, 20 and 30 hold it in 12. The miss is scale-tr-4 ("Tutunamayanlar'ı okuyorum"), whose words share no stem with "Okumakta Olduğum Kitaplar". At 30, the 1,200-character cap keeps 27 to 29 of them.

On v9 (`notelore-qwen3-4b-v9`, Ollama, `--greedy`), `eval/cases.json`, all 61 cases (the other sets have at most 8 notes a case, so their prompt does not change):

| list | cases slim, 2 runs | scale of those | cases full | scale of those |
|---|--:|--:|--:|--:|
| newest (before) | 94/120 | 14/26 | 47/60 | 6/13 |
| matches:20 | 103/120 | 23/26 | 52/60 | 11/13 |
| mixed:10 | 100/120 | 20/26 | 51/60 | 10/13 |
| mixed:20 | 98/120 | 18/26 | 52/60 | 11/13 |
| mixed:30 | 100/120 | 20/26 | 50/60 | 9/13 |

The cases that are not `scale` passed and failed the same in every row. Topping the matches up with the newest notes only dilutes them, so the app now uses `matches:20` (`defaultNotes`); `--note-list=newest` gives the old list. Over 20 notes the list holds only what the search finds, so it can be shorter than 20, down to the heading alone; the model then calls `search_notes` or `list_notes`. Each row is `dart run notelore_core:notelore_dev eval --provider=ollama --model=notelore-qwen3-4b-v9 --greedy --cases=eval/cases.json --note-list=<list>`, with `--slim --runs=2` for the slim column.

One case broke: scale-tr-1 ("Mutfak tezgahı için ne karar vermiştik?") with the full prompt. The model saw the right note in the list and called `get_decision` with a guessed topic ("tezgah"), got a bare miss and gave up; with the newest list it had searched instead. A miss now names the note's current decision topics, and scale-tr-1 passes.

With both changes, on v9, against #913's numbers:

| set | #913 | now |
|---|--:|--:|
| held-out slim | 259/292 | 259/292 |
| held-out full | 260/292 | 256/292 |
| cases slim, 2 runs | 87/108 | 101/120 |
| cases full | 42/54 | 53/60 |
| about me, full | 7/14 | 7/14 |

Four held-out cases failed in this run and passed in #913's. Rerun alone three times each: dec-yuksek-lisans-basvurusu, newlist-2 and unclear-10 fail every time on `main` at 750ca7a too, with and without the `get_decision` change; newlist-first-6 passes every time on all three. So none of the four comes from this change: it is drift between whole-set runs.

## Reminders repeat as asked, once by default, 2026-11-16 (#919, #917)

`add_reminder`'s `repeat` was `enum ["monthly"]`. On ChatGPT, "Yarın kahve siparişi vereceğim." became a monthly reminder (#917). Now `repeat` is `enum ["once", "daily", "weekly", "monthly", "yearly"]`, with `once` the default. The prompt keeps its monthly sentence word for word and adds after it: one that repeats every day, week or year has daily, weekly or yearly, and any other reminder is `repeat: once`.

Two earlier tries failed:
- **`repeat` described as "omit for a one-time reminder".** The coffee plan became `daily` on ChatGPT. That route fills every argument (`kind` too), so with no one-time value it picks some repeat.
- **The monthly line rewritten with examples ("every Monday", "every year on 3 March").** On v9 and v11 it moved plan and reminder dates a day early: "Saturday at 8" became Friday 2026-10-23. Keeping the trained sentence as it was brought rem-5, rem-9 and cross-3 back.

New cases in `eval/cases.json`, written before the change:
- `rem-{tr,en}-{daily,weekly,monthly,yearly}`.
- `rem-tr-once` and `rem-en-once`, the coffee message. They pass with a dated todo or a one-time reminder and fail on any repeat.
- `rem-tr-fix-once`, "Düzelt o zaman." after a wrong monthly reminder. It expects a one-time reminder on the same day.

Before is `main` at d138cb1 with the new cases; after is fd21f13. Each side ran from a binary built once (`dart build cli`), so neither moved while the other was measured.

**ChatGPT** (`--provider=chatgpt --model=gpt-6.1-terra`, full prompt):

| set | before | after |
|---|--:|--:|
| cases (72) | 62 (86%) | **70 (97%)** |
| reminder cases (14) | 5 | 13 |
| held-out (292) | **264 (90%)** | 261 (89%) |

- No case that passed before fails after. The six daily, weekly and yearly cases and both coffee cases now pass.
- `rem-tr-fix-once` fails before and after. The model reads the note, then says it cannot change or remove a reminder. No tool edits a reminder, so this needs a tool of its own, not a repeat value.
- Held-out: the cases that passed before and failed after were rerun alone, three times on each side (before → after).
  - cross-11 3/3 → 3/3, todo-yuksek-lisans-basvurusu 2/3 → 3/3, todo-bike-commute 0/3 → 1/3, coll-hediye-listesi-1-0 2/3 → 3/3, file-ev-tasima-1 1/3 → 3/3, todo-ev-tasima 2/3 → 3/3, cross-14 0/3 → 0/3. All drift.
  - file-saglik-kontrolleri went 3/3 → 2/3 in two separate batches. It files a todo and never calls `add_reminder`.

**v11 and v9** (Ollama, `--greedy`):

| set | v11 before | v11 after | v9 before | v9 after |
|---|--:|--:|--:|--:|
| held-out, slim | 261 | 259 | 260 | 258 |
| held-out, full | 262 | 262 | **256** | 250 |
| cases × 2, slim (142) | 116 | **120** | 105 | **112** |
| cases, full (71) | 55 | 56 | **55** | 52 |
| about me, full (14) | 9 | 9 | 7 | 7 |
| reminder cases, slim (28) | 14 | 18 | 10 | 14 |
| reminder cases, full (14) | 8 | 10 | 5 | 6 |

(`plan-tr-search` needs web search, so the local runs have 71 cases.)

Greedy runs still differ between batches. A case can pass in one subset and fail in another on the same binary, likely because Ollama reuses the prompt prefix of the case before. So each case that passed before and failed after was rerun in a file of its own, in a fresh process, three times on each side (before → after):

- **Same or better alone:** v11 full mixed-tr-1 0/3 → 3/3; v11 slim file-language-exchange 0/3 → 3/3, scale-tr-4 3/3 → 3/3; v9 full q-en-3 3/3 → 3/3; v9 slim newlist-first-6 3/3 → 3/3, scale-tr-3 0/3 → 0/3.
- **Worse every time:**
  - v11 slim mixed-tr-1 3/3 → 0/3 (files Vizontele into a new music note) and newlist-0 2/3 → 0/3. coll-en-3 is 1/3 → 0/3 with the full prompt.
  - v9 full plan-4 and plan-9 3/3 → 0/3: the plan's date is a day early again (the F1 race on Saturday the 24th written as Friday the 23rd).
  - v9 full done-kafe-acilisi-0 3/3 → 0/3: adds a todo for the done task instead of ticking it.
  - v9 full scale-tr-6 3/3 → 0/3.

So on the device models this change does not meet "nothing that passed may fail". The new repeats and the coffee cases gain 4 reminder cases slim on both models. But v9 with the full prompt loses three held-out reminder or plan turns to the day-early slip, and both models lose a few non-reminder turns.

The device prompt and tools are part of what v9 and v11 were trained on. Any change to the reminder text moves their date arithmetic, and keeping the old sentence only reduced that. The next fine-tune, with turns on the new `repeat` values in its data, is where this should settle. Until then, the choice is between shipping the schema to every provider or keeping the old one for the device model.

## Change or remove one reminder, 2026-11-17 (#925)

After a wrong reminder, "Düzelt o zaman." had no tool to call. The model archived entries or said it could not change a reminder. Two tools fix that: `change_reminder(slug, reminder, at?, text?, repeat?)` and `remove_reminder(slug, reminder)`. Each finds the one reminder whose line mentions `reminder` (a few words) and moves the old line under `_archive/`. A change first adds the reminder back with only what changed, and an empty argument keeps what was there, since the ChatGPT route fills every argument. The prompts are unchanged.

Cases in `eval/cases.json`, written before the change:
- `rem-tr-fix-once` now also wants the monthly line in the archive. Before, add_reminder alone passed and left the wrong line in the note.
- `rem-en-fix-once`, its English twin.
- `rem-tr-remove` and `rem-en-remove`: "remove that reminder" right after setting one. The other reminder must stay, and the removed one must be in the archive. `archive` with the reminder's number passes these too.

Before is `main` at 2526ea9 with the new cases; after is 8c78e12. Each side ran from a binary built once (`dart build cli`).

**ChatGPT** (`--provider=chatgpt --model=gpt-6.1-terra`, full prompt):

| set | before | after |
|---|--:|--:|
| cases (75) | 71 | **74** |
| the four new cases | 2 | **4** |
| held-out (292) | **268** | 265 |

- Cases: the two fix cases now pass with one `change_reminder` call, and the removes with one `remove_reminder` call instead of `read_note` and `archive`. No case that passed before fails after. `plan-tr-search` fails on both sides.
- Held-out: the 9 cases that passed before and failed after were rerun alone, three times on each side (before → after). coll-birthday-present-ideas-2-0 1/3 → 1/3, newlist-6 0/3 → 0/3, todo-bike-commute 1/3 → 2/3, todo-ev-tasima-1 2/3 → 2/3, todo-family-reunion 1/3 → 2/3, todo-family-reunion-1 0/3 → 3/3. Then rem-12 6/9 → 6/9 and cross-14 3/9 → 1/9. All drift.
  - todo-book-club went 9/12 → 4/12. Each failing run calls `add_todo` with `"due": ""`, which the tool refuses, and the turn then may or may not recover. The trap exists on both sides; #927 makes an empty `due` mean no date.

**v11** (Ollama, `--greedy`):

| set | before | after |
|---|--:|--:|
| held-out, slim | 259 | 260 |
| held-out, full | **259** | 257 |
| cases × 2, slim (148) | 120 | **130** |
| cases, full (74) | 56 | **59** |
| about me, full (14) | **9** | 8 |
| reminder cases, slim (34) | 18 | 26 |
| reminder cases, full (17) | 10 | 12 |

- New cases, slim (2 runs each): rem-tr-fix-once 0 → 2, both removes 2 → 2 (`archive` before, `remove_reminder` after), rem-en-fix-once 0 → 0. v11 calls `change_reminder` without `repeat`, so the monthly repeat stays.
- Each case that passed before and failed after was rerun alone, three times on each side (before → after):
  - **Drift:** cross-3 3/3 → 3/3, twin-reading-now-0 3/3 → 3/3, aboutme-en-change-age 0/3 → 0/3, rem-11 slim 3/3 → 2/3, q-tr-1 slim 3/3 → 2/3, newlist-2 3/3 → 2/3.
  - **Worse every time, slim:** file-yuksek-lisans-basvurusu-0, newlist-5 and newlist-7, each 3/3 → 0/3.
  - **Worse every time, full:** coll-okuma-listem-1-0, dec-kafe-acilisi, file-side-business, rem-9 and scale-tr-5, each 3/3 → 0/3. newlist-0 went 1/3 → 0/3.

So as with #921, ChatGPT meets "nothing that passed may fail" and v11 does not. Two more tools in its list move a few turns that have nothing to do with reminders, though the totals rise (slim cases +10, full +3). The choice for the device model is between shipping the tools to it now, or leaving them out of its slim list (`slim: false`) until a fine-tune has turns on them. Then its slim prompt and tools stay byte for byte as before, and a correction on the phone still has no tool.

## Fine-tune v12, 2026-11-19 (#604)

v11 was trained before #921 and #925 changed the device prompt and tools. v12 trains on today's prompt and on the new reminder tools.

**Setup**
- v12 data: 2,641 turns, all re-prompted at 822e576.
  - v11's 2,464 turns, less three copies of one turn that filed a weekly lesson as a monthly reminder.
  - 180 new turns from glm-5.3 (OpenCode Go), 100 slim and 80 with the full prompt, on 115 new scenarios (`scenarios.py` v12):
    - 63 reminder scenarios. 33 repeat as asked, every value, and 10 of those are one-time reminders, `once` said or not. 18 correct a reminder just set, through `change_reminder`: 10 turn a repeating one into a one-time one, 4 move its day or time, 4 make it repeat. 12 remove one through `remove_reminder`, with the other reminders kept.
    - 52 contrast scenarios for what v11 lost: 12 plans on a weekday; four projects with five messages each (a done task, a new task, a decision, a filing and a vague message); 10 new lists beside a list of another kind; 10 more vague messages.
  - The teacher passed 58 and 52 of the reminder scenarios (slim, full) and 42 and 28 of the contrast ones. With the full prompt it often made a note twice for a new list, and those turns were dropped as tool errors.
  - Every `add_reminder` call without `repeat` now has `repeat: once` (282 calls), as the prompt says and as glm-5.3 writes it.
- v11's recipe in fp16: rank 16, one epoch, the loss on the answer alone, learning rate 2e-4. One session on Kaggle's T4, 297 steps in 6.9 hours. The validation loss fell from 0.406 at step 40 to 0.285 at the last step, which is the adapter kept.
- Q4_K_M, greedy, both models at 822e576, each eval from one binary built once (`dart build cli`).

| | Held-out (292), slim | Held-out, full | 74 cases × 2, slim | 74 cases, full | About me (14), full |
|---|---|---|---|---|---|
| v11 | 261 (89.4%) | 257 (88.0%) | **130/148 (88%)** | 58 (78%) | 8 (57%) |
| **v12** | **264 (90.4%)** | **266 (91.1%)** | 126/148 (85%) | **60 (81%)** | 8 (57%) |

Held-out by kind, v11 → v12. Slim: collection 58 → 59/73, reminder 14 → 15/15, todo 18 → 19/19, unclear 13 → 14/15; filing 30 → 29/36. Full: collection 57 → 61/73, decision 16 → 18/18, reminder 12 → 15/15, todo-done 17 → 18/20, todo and chat one higher each; unclear 14 → 12/15, filing 30 → 29/36.

Every case that flipped between the models was rerun in a file of its own, three times on each model, each run a fresh process (v11 → v12):

- **The v11 losses of #921 and #925.**
  - Fixed: newlist-5 slim 0/3 → 3/3, newlist-7 slim 1/3 → 3/3; dec-kafe-acilisi, rem-9, coll-en-3 and rem-en-fix-once with the full prompt, each 0/3 → 3/3; scale-tr-5 full 2/3 → 3/3.
  - Still failing on both: mixed-tr-1, newlist-0 and file-yuksek-lisans-basvurusu-0 slim, and scale-tr-6 full, each 0/3 → 0/3.
  - Passing on both: plan-4, plan-9, done-kafe-acilisi-0 and file-side-business full, 3/3 → 3/3. The day-early slip and the missed tick were v9's.
  - Not settled: coll-okuma-listem-1-0 full went 0/3 → 0/3 in one batch of reruns and 0/3 → 3/3 in the next, and v11's rem-en-fix-once slim went 3/3 and 0/3. Even alone, a greedy run depends on what the server ran before.
- **v12 better every time** (0/3 → 3/3): slim rem-8, unclear-12, newlist-1, newlist-first-7, cross-11, rem-en-once and plan-en-1; full dec-ev-tasima-1, chat-11, rem-2, rem-8, newlist-2, newlist-7, cross-3, q-tr-5 and rem-en-daily; scale-tr-7 full 0/3 → 2/3.
- **v12 worse every time** (3/3 → 0/3):
  - A repeating reminder on a day of the month that has passed is written in this month or in the wrong month: rem-en-monthly slim and full ("the 1st of every month" became 2026-10-01 or 2026-01-01) and rem-tr-monthly full ("her ayın 5'inde" became 2026-10-23). rem-en-yearly ("every year on 12 June") fails on both, 1/3 → 0/3, written as 2026-12-12.
  - The answer in the wrong language: coll-en-1 full and cross-5 slim answer an English message in Turkish.
  - Slim unclear-5, newlist-first-0, newlist-first-3, mixed-tr-0, cross-12 and q-tr-1; full unclear-5.
- **Drift:** coll-tr-empty slim 3/3 → 3/3, cross-5 and cross-8 full 3/3 → 3/3, unclear-2 full 1/3 → 3/3; scale-tr-5 slim, newlist-first-7 full and unclear-en-1 full 0/3 on both.

Findings:

- **v12 is better than v11 on four of the five sets.** Held-out +3 slim and +9 full, full-prompt cases +2, about me equal. Alone, 21 case-and-mode pairs pass every time on v12 and never on v11; 12 go the other way.
- **The new reminder tools work.** v12 corrects a reminder with one `change_reminder` call that sets `repeat`, where v11 called it twice and left the repeat, and removes one with a single `remove_reminder` where v11 called it three times. Held-out reminder is 15/15 in both modes.
- **The cost is monthly dates.** v11's data had one monthly scenario (the 1st, so November) in six turns. v12 added four whose day is still to come this month (the 20th to the 30th, eight turns) and two that roll over (four turns), and now keeps the month for a day that has passed. The next round needs more rows that roll over: early days of the month, and yearly dates whose month has passed.
- **Unclear with the full prompt is lower again** (14 → 12/15 held-out), though above v11's 9/15 at e71e53a. The 20 vague contrast turns did not hold it.
- **v12 does not loop.** Replaying v10's looping turn capped at 400 tokens, v12 answers in 36 tokens. Every reminder and plan case of the loop check, and the four fix and remove cases, end on their own in 18 to 55 tokens.
- v12 is in Ollama as `notelore-qwen3-4b-v12`. The app's device model is unchanged.

## Fine-tune v12b, 2026-11-20 (#604)

v12 wrote a monthly reminder whose day had passed in the current month ("the 1st of every month" became 2026-10-01). v12b changes only the data.

**Setup**
- **Why v12 kept the month.** Before v12, the data had one monthly scenario: rem-25, "Ayın 1'inde", which rolls into November. v12 added four monthly rows whose day was still ahead in October and only two that roll over.
- **v12b data:** 2,717 turns, v12's 2,641 plus 76 new ones from glm-5.3 at 822e576 (38 slim, 38 full prompt), on 50 new scenarios:
  - 30 monthly and yearly reminders. Per language, 6 monthly days that have passed (the 1st twice, the 3rd, 7th or 8th, 10th, 15th) against 3 still ahead, and 4 yearly dates that roll into 2027 against 2 still in 2026. Both "on the 1st of every month" and "her ayın 1'inde" are included. The teacher passed 29 slim and 28 full.
  - 8 English messages about Turkish notes; 7 of them passed in each mode.
  - 6 vague "done" messages. Most failed: the teacher ticked a todo in another note.
  - 6 first lists of their kind; 1 passed.
- **`test_scenarios.py` now pins every scenario id to its message** (`tool/train/scenario-ids.json`). A row added mid-table renumbers the rows after it, which happened to v12's plans. The pin starts from main as it is. Nine ids already carry other messages than they had in earlier training files, from older PRs.
- **Training:** v12's recipe, one Kaggle session, 306 steps. The validation loss fell from 0.422 to 0.310 at the last step. The held-out tenth now includes some of the new rows, so 0.310 cannot be compared with v12's 0.285.
- **Eval:** Q4_K_M, greedy, the same 822e576 binary as v12. Main has moved to 0f7f74c with docs and tool changes only, so v12's numbers above stand. Ollama ran nothing else during the evals or the reruns.

| | Held-out (292), slim | Held-out, full | 74 cases × 2, slim | 74 cases, full | About me (14), full |
|---|---|---|---|---|---|
| v11 | 261 | 257 | **130/148** | 58 | 8 |
| **v12** | **264** | **266** | 126/148 | **60** | 8 |
| v12b | 262 | 263 | 125/148 | **60** | **9** |

Held-out by kind, v12 → v12b. Slim: collection 59 → 63/73; plan 14 → 11/15, reminder 15 → 13/15. Full: unclear 12 → 13/15; plan 14 → 12/15, and decision, new note and todo-done one lower each.

Every flipped case was rerun alone, three times on each model (v12 → v12b):

- **v12b better every time** (0/3 → 3/3):
  - Monthly and yearly dates: rem-en-monthly slim and full, rem-tr-yearly slim.
  - The other v12 losses: unclear-5 slim, coll-en-1 full (now answered in English), cross-12 and cross-13 slim, newlist-first-1, newlist-first-2 and newlist-first-3 slim, newlist-first-7 full, mixed-tr-0 slim, unclear-en-1 full.
  - Also file-yuksek-lisans-basvurusu-0, newlist-4, coll-tr-empty and scale-tr-6 slim, and newlist-4, newlist-6 and aboutme-tr-move-from-note full.
- **v12b worse every time** (3/3 → 0/3):
  - Weekday dates: plan-2, plan-9, rem-8 and rem-en-once slim; plan-14, rem-tr-weekly, rem-tr-once and rem-en-once full. "Salı" became Monday 2026-10-19; "Thursday at 20:00" became today, 2026-10-18 20:00.
  - Filing and collections: rem-11 slim (into a new note), done-kafe-acilisi-0, file-side-business (both modes), file-language-exchange, mixed-en-3 and mixed-tr-3 (both modes), new-10, q-tr-5, plan-en-1 (no reminder) and scale-tr-3 slim; coll-okuma-listem-1-0, dec-ev-tasima-1 and cross-3 full.
- **Drift or both failing:** coll-hediye-listesi-0-0 and plan-1 slim, newlist-6 and newlist-first-0 slim 3/3 on both; unclear-13 slim 0/3 on both; scale-tr-4 slim 3/3 → 1/3; plan-1 full 1/3 → 0/3; new-10 full 3/3 → 2/3; cross-5, cross-8 and unclear-2 full 1–2/3 → 3/3.

Findings:

- **v12b fixes what it was trained for**: monthly days that have passed, the answer's language, vague messages, and first lists of their kind.
- **It breaks weekday dates.** The 30 new rows are all monthly or yearly. After them, a plain weekday plan or reminder moves a day early or lands on today. That is 8 case-and-mode pairs that v12 passes every time. Held-out plan falls in both modes.
- **v12b does not replace v12.** It loses 2–3 held-out cases in each mode and one slim case pair, and gains one about-me case. Alone, 20 pairs go 0/3 → 3/3 and 24 go the other way.
- **For the next round:** keep the rollover rows, and add as many weekday and "tomorrow" reminders and plans beside them, so one kind of date does not outweigh the other.
- **No loop.** v10's looping turn ends in 16 tokens. The loop check's reminder, fix and remove cases end on their own in 16 to 39 tokens; plan-en-1 now fails there (no reminder) but also ends.
- v12b is in Ollama as `notelore-qwen3-4b-v12b`. The app's device model is unchanged.
