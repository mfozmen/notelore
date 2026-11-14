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
  which is capped at 60 notes and 1,200 characters, so it does not grow.

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
