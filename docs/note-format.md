# Note format

This is the contract between the LLM, the code and the human reader. The goal is that a person who has never heard of Notelore can open any file and understand it. The parser and writer in `notelore.store.format` must round-trip every valid file byte-for-byte.

## Folder layout

```
Notelore/                         # notes root (default ~/Notelore, or $NOTELORE_HOME/notes)
├── projects/<slug>.md            # one file per project
├── topics/<slug>.md              # everything that is not a project (people, ideas, how-tos...)
├── _archive/<YYYY-MM-DD>/<relative path>   # notes removed by cleanup, never deleted
└── .notelore/
    └── history/<YYYY-MM-DD>T<hhmmss>Z/<relative path>   # losing side of sync conflicts
```

`_archive/` and `.notelore/history/` are synced to Drive too, so nothing is lost if a device dies. The search index and sync manifest are **not** in this folder; they are device-local derived state.

## File structure

UTF-8, LF line endings, Unicode NFC. YAML front matter, then a title, then sections.

```markdown
---
title: Mopsos
kind: project
created: 2026-09-12
updated: 2026-09-30
tags: [investing, side-project]
---
# Mopsos

## Decisions
- ~~2026-09-12 — **database**: PostgreSQL.~~ _(superseded 2026-09-28)_
- 2026-09-28 — **database**: SQLite. Single user, zero setup.
- 2026-09-20 — **frontend**: React + Vite.

## Notes
- 2026-09-15: Prediction hit rate is calculated weekly, on Sundays.
- 2026-09-22: Considered adding crypto, postponed until the stock flow is stable.

## Todo
- [ ] 2026-10-15: Add Drive backup
- [x] 2026-09-25: Set up CI
```

### Front matter

| Key | Required | Meaning |
|---|---|---|
| `title` | yes | Human title, any language |
| `kind` | yes | `project` or `topic` |
| `created` | yes | Local date the file was created |
| `updated` | yes | Local date of the last change (maintained by code, not the LLM) |
| `tags` | no | Lowercase list |

### Sections

Known sections have a canonical key and localized headings from `i18n.py`. The parser recognizes every known heading variant; the writer uses the language the file was created in.

| Key | English | Turkish |
|---|---|---|
| `decisions` | `## Decisions` | `## Kararlar` |
| `notes` | `## Notes` | `## Notlar` |
| `todo` | `## Todo` | `## Yapılacaklar` |

Unknown sections (a human added `## Links` by hand) are preserved verbatim and never touched by code.

### Decision entries

```
- <date> — **<topic>**: <value>. <optional reason>
- ~~<date> — **<topic>**: <value>. <optional reason>~~ _(superseded <date>)_
```

- `topic` is a short, lowercase key (`database`, `hosting`, `auth`). It is what makes lookups deterministic: "current decision for `database` in `mopsos`" = the newest non-superseded entry with that topic.
- Recording a new decision for an existing topic marks the previous active one as superseded in the same write. At most one active entry per topic.
- Strikethrough is chosen on purpose: it renders as "crossed out" in Obsidian, GitHub and most Markdown viewers, so a human sees the history at a glance.

### Note entries

```
- <date>: <text>
```

Text can wrap to indented continuation lines. The LLM writes a clean, self-contained sentence (no "as discussed above"), in the language the user spoke.

### Todo entries

```
- [ ] <date>: <text>          # date = due date if given, otherwise creation date
- [x] <date>: <text>
```

## Staleness signals

`find_stale_notes` collects candidates deterministically; the LLM only explains and ranks them:

- superseded decisions older than N days (default 90),
- files whose `updated` is older than N days (default 180),
- open todos whose date is in the past,
- note entries the user explicitly marked outdated.

Cleanup always requires user confirmation and moves content to `_archive/`, keeping the original relative path.
