# Kil and Orman: the design spec

One theme with two modes: **Kil** by day (cream and terracotta) and **Orman** by night (green-black and clay orange). Layout, fonts and shapes are the same in both; only the colours change. The maintainer chose it on 2026-11-06 out of seven directions (#781).

Open `index.html` in a browser. It is a hand-drawn HTML mockup, not app code. Fonts load from Google Fonts.

- Headings: Fraunces. Body: Plus Jakarta Sans. Labels: JetBrains Mono, capitals, wide tracking.
- The assistant answers without a bubble (Markdown on the background); the person's message keeps a bordered fill. The mic is a glowing orb.
- The Notes screen opens with the open todos due soon ("Coming up"); long titles clamp to two lines.
- The night background is a static glow, never a continuous animation, and there is no blur behind scrolling lists.

Drawn so far, each in light and dark: phone Chat (with messages, empty, with a banner), the menu drawer, Notes, Note, Calendar, About me (and with Add a fact), Settings › Appearance; desktop Chat, Notes with a note open, Calendar, About me, Settings. The mockup shows the app's real behaviour and texts; the only new items are the agreed ones: excerpt, tags and todo count on note rows (#773), the sync state (#774), Pinned (#775), the Coming up strip, no help lines on the note page (#772), and the shared chat width on desktop (#771). Not drawn yet: dialogs, snackbars, voice recording, busy and no-model states, the archive, setup and lock.

The page picks English or Turkish strings from `<html lang>`; set `lang="tr"` to see the Turkish screens.
