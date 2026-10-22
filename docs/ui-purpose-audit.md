# UI purpose audit (#508)

The audit asks one question of every control: does it help the task the person
came to that screen for? If not, it belongs in Settings, an overflow, a detail
page, or nowhere.

Screens reviewed off-screen on phone (432x960) and desktop (900/1280/1600), in
light and dark: setup, Google sign-in, chat empty/typical/busy/error, notes
list/search/reader, archive, calendar, every Settings section, usage, and the
app lock. No critical breakage was found. The purpose lens is part of
`.claude/agents/ui-reviewer.md`; later reviews apply it.

The findings are tracked as follow-up issues:

- #555: Notes list and reader chrome (two toolbars, duplicated Export/Delete).
- #556: repeated Settings labels, and Advanced/Usage inside the Model card.
- #557: Archive Restore, calendar Today, and the model switcher's affordance.
- #558: product decisions (app-lock recovery, Google-only entry, row Delete,
  advanced-settings gate, Manage usage).

## Top three changes

1. Rebuild the Notes/reader chrome: one list header with Import/Export/Refresh
   in an overflow, one Export and one Delete in the reader, and pull-to-refresh.
2. Fix Settings information architecture: remove repeated section names, split
   Advanced/Usage out of Model, and distinguish language "System" from theme
   "System".
3. Make primary actions discoverable: visible Restore in the archive, a chevron
   on the model chip, and Today beside the month arrows.

## Other findings

- The empty Usage page says "nothing" three times; one empty card is enough.
- The chat busy row uses a small spinner and italic body text; make it a normal
  status row.
- Notes at 840-1000 px leaves the reader too narrow; cap the list at 35% or move
  the split-pane breakpoint.
- Usage desktop title is outside the centred body column; move it in.
- Usage chart has no way to select a day other than touch; add semantics actions
  or a text alternative.
- About holds Log out as its only action; About should hold version, licences,
  privacy and source.
- Setup phone's connect step leaves an empty band between the key field and the
  pinned action; group them in one card.
