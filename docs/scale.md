# Notes at scale

How the index and the tools behave with many notes (#895). Measured with
`packages/notelore_core/tool/load_test.dart`, which writes invented notes
(`lib/src/sample_notes.dart`: Turkish and English, projects and topics, 1 to 34
entries each, with tags, todos and decisions; never real notes) into a temp
folder and times each step, the median of 7 runs:

```bash
(cd packages/notelore_core && dart run tool/load_test.dart)        # 200, 1,000, 2,000
(cd packages/notelore_core && dart run tool/load_test.dart 5000)   # any counts
```

Tokens are estimated as four characters each; no tokenizer runs.

## Results

On a Windows 11 desktop, after this change:

| notes | folder MB | first build ms | full rescan ms | one file changed ms | search_notes ms | listNotes ms | relatedTo ms | related_notes ms | list_notes tokens | search_notes tokens | system prompt tokens |
| --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |
| 200 | 0.3 | 486 | 15 | 40 | 17 | 0.9 | 7.2 | 24 | 685 | 1505 | 1125 |
| 1000 | 1.4 | 1404 | 57 | 74 | 38 | 3.2 | 29 | 90 | 686 | 1662 | 1125 |
| 2000 | 2.9 | 2430 | 110 | 128 | 72 | 6.4 | 55 | 268 | 686 | 1772 | 1125 |

Before it, the first build took 713 / 3,523 / 11,211 ms and `list_notes` was
4,948 / 25,273 / 51,081 tokens.

- **first build**: a new or deleted index, every note parsed and stored once.
- **full rescan**: the scan `rebuild()` does at most every 5 s, nothing changed.
- **one file changed**: the same scan with one note rewritten.
- **search_notes**, **related_notes**: the tool calls, JSON included.
- **listNotes**, **relatedTo**: the index queries behind the Notes list and a
  note page's related notes.
- **system prompt tokens**: the slim prompt plus the note list at its end,
  which is capped at 1,200 characters, so it does not grow. Over 20 notes it
  lists the notes the index search finds for the message, at most 20
  ([model-eval.md](model-eval.md), `--note-list` to compare).

## What the numbers changed

- **list_notes was the one cost that grew without bound**: every note's title,
  slug and date, about 25 tokens a note, 51,000 tokens at 2,000 notes, in a
  4B model's context on every turn that lists notes. It now gives the 30 newest
  (filterable by `kind`), the total, and a line saying to find the rest with
  `search_notes`: under 700 tokens at any size.
- **The first build was quadratic**: each new file first deleted its old rows,
  and a `DELETE` on the FTS5 table scans the whole table, so 2,000 notes took
  11.2 s. A file the index has never seen has no rows to delete; the build now
  skips that and takes 2.4 s.
- Everything else grows about linearly and stays well under the time a model
  turn takes. `related_notes` is the slowest tool call at about 0.27 s for
  2,000 notes; left as it is.

## Finding notes by meaning, measured (#929)

The prompt's note list and `search_notes` both come from the index's word
search, so a message that shares no word stem with its note never finds it
("Tutunamayanlar'ı okuyorum" vs "Okumakta Olduğum Kitaplar", scale-tr-4).
Sixteen `scale-meaning-*` cases in `eval/cases.json` (filler 80, 8 Turkish,
8 English) pair a message with a note it shares no stem with: a dish and a
cooking note, a relative and a family note, a symptom and a health log, a brand
and an appliance list, a film and a film diary, a pet's jab and vet visits, a
licence and official documents, blood type and a medical card, a book and a
reading list. Whether the target reaches the prompt, without a model:

```bash
NOTELORE_HOME=.dev-home dart run notelore_core:notelore_dev reach --cases=eval/cases.json   # --note-list=… to compare
```

Two candidates were tried offline on the same notes, CPU only. Neither is in
the app:

- **A, embeddings**: each note's text (without front matter) and the message
  become vectors from a small multilingual model on onnxruntime (2 threads),
  ranked by cosine similarity. Then fused with today's matches by reciprocal
  rank (RRF, k 60), or appended after them.
- **B, a one-line description**: a separate model wrote one line per note,
  filler included, as the app's model would on `create_note`. It saw only the
  notes, never the messages. The index then searched the description with the
  title.

Hit rate at 20 (the target note among the 20 the prompt lists), with each
case's 80 filler notes:

| list | 13 old `scale` | 16 new | all 29 |
|---|--:|--:|--:|
| today, `matches:20` | 12 | 0 | 12 |
| B, description searched with the title | 12 | 4 | 16 |
| A, multilingual-e5-small int8: vectors only | 13 | 15 | 28 |
| A, e5-small int8: RRF(matches, vectors) | 13 | 15 | 28 |
| A, e5-small int8: matches, then vectors | 13 | 15 | 28 |
| A, e5-small fp32: any of the three | 13 | 15 | 28 |
| A, paraphrase-multilingual-MiniLM-L12-v2 int8: vectors only | 13 | 16 | 29 |
| A, MiniLM-L12 int8: RRF or matches, then vectors | 13 | 15 | 28 |

The same cases with 2,000 filler notes instead of 80:

| list | 13 old | 16 new | all 29 |
|---|--:|--:|--:|
| today, `matches:20` | 12 | 0 | 12 |
| B | 12 | 4 | 16 |
| A, e5-small int8: vectors only | 12 | 10 | 22 |
| A, e5-small int8: RRF or matches, then vectors | 13 | 9 | 22 |
| A, MiniLM-L12 int8: vectors only | 9 | 10 | 19 |
| A, MiniLM-L12 int8: RRF or matches, then vectors | 13 | 8 | 21 |

The filler is made from 30 subjects per language, so 2,000 notes hold about 33
near-copies of each, "Sourdough" and "Kitchen Herbs" among them. That is harder
than a real folder: e5 ranks "Ev Yemekleri" 815th among Turkish sourdough and
herb notes. With 2,000 notes the word matches alone fill the 20 slots, so
appending the nearest notes adds nothing. RRF fared no better. Keeping some
slots for the vectors (say 12 matches and 8 nearest notes) was not tried.

Cost on a Windows 11 desktop CPU, 2 threads, one note at a time:

| model | file | per note, 80 filler (median, max) | per note, 2,000 filler | per query | dims |
|---|--:|--:|--:|--:|--:|
| multilingual-e5-small int8 | 118 MB | 52 ms, 478 ms | 148 ms, 1.7 s | 12 to 15 ms | 384 |
| multilingual-e5-small fp32 | 470 MB | 118 ms, 851 ms | not run | 26 ms | 384 |
| paraphrase-multilingual-MiniLM-L12-v2 int8 | 118 MB | 44 ms, 491 ms | 139 ms, 677 ms | 9 to 10 ms | 384 |

Each model also needs its 17 MB `tokenizer.json`, a SentencePiece unigram
vocabulary of 250k words. The median note is 85 tokens in the 80-filler set and
250 in the 2,000 set, which has more long notes. The first embedding pass over
2,000 notes takes about 5 minutes on this desktop; after that, only changed
notes are embedded. The phone was not measured. Expect it to be a few times
slower.

- **B helps only where the description happens to use the message's word.**
  It found the two film diaries ("film", "izlediğim" next to "izledim") and
  the two medical cards ("blood type", "kan grubu"), and nothing else. The
  description says "recipes" where the person says "tikka masala", and
  "akrabalarım" where the person says "halam". Turkish endings make it worse:
  "okuduğum" in a description and "okuyorum" in a message share only three
  letters, fewer than the index's four-letter prefix. Old notes have no
  description until rewritten, and B is a format change.
- **A finds almost every case at 80 notes, and the old ones stay found.** The
  one miss depends on the model: e5 ranks "Ev Yemekleri" 31st for "Hünkâr
  beğendi … kaymakla", and MiniLM ranks "Appliance Wishlist" 15th for the Dyson
  message, which the fused list then loses to word matches. At 2,000 near-copy
  notes, A still finds 9 or 10 of the 16 that today finds none of.
- **What A takes in the app.** The app already ships onnxruntime through
  sherpa-onnx: `libonnxruntime.so` on Android, `onnxruntime.dll` on Windows,
  and linked into `libsherpa-onnx-c-api.dylib` on macOS. But sherpa-onnx has no
  text-embedding API, so the core would need its own FFI to the onnxruntime C
  API (or a package that bundles it), and a SentencePiece unigram tokenizer in
  Dart. The model would be a download, like the Whisper model
  (`whisper_model.dart`), not part of the installer. Vectors are derived state
  in the SQLite index, rebuilt from the files (invariant 1), and a device
  without the model keeps today's search. The FFI is native glue the coverage
  gate cannot load, so it would sit behind an interface with a fake in the
  tests, like Whisper.

**Recommendation: A**, with multilingual-e5-small int8: 118 MB plus its
tokenizer, about 50 to 150 ms per note once, and about 15 ms per message. It
took the new cases from 0 to 15 of 16 at 80 notes and to 9 or 10 at 2,000,
without losing an old one when fused. B is cheaper but found 4 of 16 and needs
a format change. e5 held up better than MiniLM at 2,000 notes. The fusion
should keep slots for the vectors, because word matches alone fill the list in
a big folder; that split is the first thing to measure when A is built, with
`reach` and then the eval and held-out set before and after, as the issue's
plan says. These numbers came from a throwaway Python script (onnxruntime 1.32,
not committed) run on the notes `reach` writes.
