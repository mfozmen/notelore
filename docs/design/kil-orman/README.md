# Kil and Orman: the design spec

One theme with two modes: **Kil** by day (cream and terracotta) and **Orman** by night (green-black and clay orange). Layout, fonts and shapes are the same in both; only the colours change. The maintainer chose it on 2026-11-06 out of seven directions (#781).

Open `index.html` in a browser. It is a hand-drawn HTML mockup, not app code. Fonts load from Google Fonts.

- Headings: Fraunces. Body: Plus Jakarta Sans. Labels: JetBrains Mono, capitals, wide tracking.
- The assistant answers without a bubble; a decision it finds is a coloured card. The mic is a glowing orb.
- The Notes screen opens with the open todos due soon ("Coming up"); long titles clamp to two lines.
- The night background is a static glow, never a continuous animation, and there is no blur behind scrolling lists.

Chat, Notes and Note are drawn so far. The full spec (tokens, every screen on phone and desktop, redlines) grows here before the Flutter build (#782).
