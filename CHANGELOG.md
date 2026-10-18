# CHANGELOG


## v0.13.1 (2026-10-18)

### Bug Fixes

- An asterisk note must hug its letters; a spoken "2 * 3" stays ([#402](https://github.com/mfozmen/notelore/pull/402), [`f5fa81d`](https://github.com/mfozmen/notelore/commit/f5fa81dd608db65e569c064aefcc1f5886953d97))

- Android keeps the app out of the freezer while a ChatGPT sign-in waits, so the sign-in completes ([`2bbb7e7`](https://github.com/mfozmen/notelore/commit/2bbb7e733de0bd78e1853f757e5fdc14086313ba))

- Every waiting line ends with an ellipsis, so it reads as thinking ([`6bfd123`](https://github.com/mfozmen/notelore/commit/6bfd1235beef6c6037a178f165863c3e38e3e583))

- Fifty waiting lines in each language, so a long wait seldom repeats one ([`6665396`](https://github.com/mfozmen/notelore/commit/6665396a3f4c392d8fa4937eea51cfab6cee9c05))

- Gemini starts on gemini-2.5-flash, and a 429 with no quota says to choose another model ([`7d139de`](https://github.com/mfozmen/notelore/commit/7d139de5b08eea50f8001de831ebfdbdf01d8d93))

- Require Send for shared text ([#383](https://github.com/mfozmen/notelore/pull/383), [`4598f5f`](https://github.com/mfozmen/notelore/commit/4598f5f77ab38b4572916fcfc5b3b7d70be265be))

- The empty chat invites a note, not a chat ([`3848eeb`](https://github.com/mfozmen/notelore/commit/3848eebcee301612a23e043a9b298ead17a95f99))

- Voice mode on Android: Whisper's notes on sounds are not sent as words ([#402](https://github.com/mfozmen/notelore/pull/402), [`f5fa81d`](https://github.com/mfozmen/notelore/commit/f5fa81dd608db65e569c064aefcc1f5886953d97))


## v0.13.0 (2026-10-18)

### Bug Fixes

- A book or film in passing goes under a collection note
  ([`13adba6`](https://github.com/mfozmen/notelore/commit/13adba6ed99c2f0f585c1f7043a560d6ce550198))

- A failed turn is a centred status row with Try again, not an answer
  ([`c28c18a`](https://github.com/mfozmen/notelore/commit/c28c18aaa0d6476eae5706291625ff0924975fa3))

- A free ChatGPT account is told why, and offered a free Gemini key
  ([`3ebb6ff`](https://github.com/mfozmen/notelore/commit/3ebb6ffeb56b76a0d1d6fdcf986b154063a6b5e0))

- A note slug in another case finds its note on every OS
  ([`2553e0e`](https://github.com/mfozmen/notelore/commit/2553e0e621f266c2d51bbd3f3ae356b27efd6960))

- A phone's setup speaks of no computer, and of choosing, not clicking
  ([`0770ede`](https://github.com/mfozmen/notelore/commit/0770edea43c81c8a1fb57e34ea955f32abbf8cc8))

- A roomier chat: full-size line buttons, a gutter beside bubbles, examples in an empty chat
  ([`885e8bb`](https://github.com/mfozmen/notelore/commit/885e8bbac2299e0d4e80c58cd6021635ea0e1326))

- An Ollama set up before connections counts as connected; a waiting message outlives a removed
  model
  ([`8fce743`](https://github.com/mfozmen/notelore/commit/8fce743157da1bfd1295846b902b293c13b4e741))

- Any error in the test turn returns to Connect; the hello is not metered, pinned by a test
  ([`a60fbe8`](https://github.com/mfozmen/notelore/commit/a60fbe80c84c33544d66a137afb4b4f46296c31e))

- Attachments: a hung PDF stops at 30 s and reads 200 pages at most; nothing is sent after a lock; a
  garbled redirect fails only its link
  ([`dfc3938`](https://github.com/mfozmen/notelore/commit/dfc39385bc4e6ccd23db9ebda9c352e1ab12ba53))

- Drop the reasoning Ollama thinking models leak into the answer
  ([`3440a52`](https://github.com/mfozmen/notelore/commit/3440a52e3401a7703b5655812ed1c5a8ffb32b97))

- Examples wrap as full-width rows near the composer; a line's buttons sit close under it
  ([`0be7e11`](https://github.com/mfozmen/notelore/commit/0be7e117961a3e70b2a36d0ee86b358f3a9b26e0))

- Finish the ChatGPT sign-in on Android: back to the app, then one exchange
  ([`5c4b779`](https://github.com/mfozmen/notelore/commit/5c4b7794e26b7ca237868b7358377c98fed6c630))

- Honor marked writes during index audits ([#332](https://github.com/mfozmen/notelore/pull/332),
  [`7677d0e`](https://github.com/mfozmen/notelore/commit/7677d0eefb0a17e8b41aaf96f0f80f6fc32644eb))

- Images and files told apart in the bubble; resend checks the provider; _read under Sonar's limit
  ([`da65c4d`](https://github.com/mfozmen/notelore/commit/da65c4db6876422f1b59e902e057fdb5012ecc60))

- Images and PDFs share one attachment path after the rebase
  ([`1a73f13`](https://github.com/mfozmen/notelore/commit/1a73f13efbd5e73ef5594727a6ce79eaee4c697e))

- Images in an answer are never fetched; links and code look the part
  ([`f741481`](https://github.com/mfozmen/notelore/commit/f741481415702a6eec0388ec7be2701623df8acc))

- Images leave the history after their turn; 5 MB over a message's images; Gemini parts split
  ([`b53e93e`](https://github.com/mfozmen/notelore/commit/b53e93ec7e5d36a56be26e75c2b3dae7c7d36501))

- Keep Ollama models on the GPU and skip hidden thinking
  ([`60a8715`](https://github.com/mfozmen/notelore/commit/60a871541ae7104ebdcda9dddc5455024c89b8e0))

- Locking also clears a notice from before, which could name a note
  ([`73500cf`](https://github.com/mfozmen/notelore/commit/73500cfeba01aa3a7a046dac5636d0125d283ffd))

- No back while a key is checked, a refused key stays with its provider, no nested ternary
  ([`75781be`](https://github.com/mfozmen/notelore/commit/75781be9628de9b68136aecd7a7319707518e094))

- No image in a note is ever loaded, and Android backs nothing up
  ([`f71bdb1`](https://github.com/mfozmen/notelore/commit/f71bdb14aace3b1dc6497aae1f748ed9adb59d0f))

- Settings says when removing a model fails, and nothing is removed while switching
  ([`eca4090`](https://github.com/mfozmen/notelore/commit/eca4090defe6ff4800ecad2277958c34d033456d))

- Setup polish: the free key leads without a plan, an edge over the pinned action, numbers grow with
  text
  ([`6a4f58a`](https://github.com/mfozmen/notelore/commit/6a4f58a287fb58f971b83f775b2310f6303bc5ad))

- The chat shows an answer's Markdown formatted, not raw
  ([`924decf`](https://github.com/mfozmen/notelore/commit/924decf382fdf4f4da83e1940f40a3b2458b196b))

- The desk card never asks a negative height; README without Advanced; simpler build and card; pin
  the revoked-key way back
  ([`3043664`](https://github.com/mfozmen/notelore/commit/3043664a393a289eb9bf8cdc4a754ac58c18737e))

- The link reader checks every address a host resolves to, so no form of a private address gets
  through
  ([`dac92fb`](https://github.com/mfozmen/notelore/commit/dac92fb30c46af8aff48e4e71a472c0def4ead7a))

- The link reader stays off private hosts, sync follows no links, and a file cannot end its marker
  in another case
  ([`1e26441`](https://github.com/mfozmen/notelore/commit/1e26441f015c356d820867fb26680a8caacf764b))

- The lock's wait survives a clock moved ahead and covers turning it off; oversize attachments are
  refused unread
  ([`77571cd`](https://github.com/mfozmen/notelore/commit/77571cd8c07b30e765568dd421d9ff71ba51960e))

- The no-plan card goes with another provider; the clipboard is read once, safely
  ([`3060a4a`](https://github.com/mfozmen/notelore/commit/3060a4ab0066e7909b4728b3558bb820689c5a21))

- The sign-in scrolls as a whole on a short window; the busy button says it is signing in
  ([`6bd5d62`](https://github.com/mfozmen/notelore/commit/6bd5d62d68e9bedd05d770b489151b3848682ad2))

- The updater downloads into, and cleans up, a temp folder it is given
  ([`3d66c8f`](https://github.com/mfozmen/notelore/commit/3d66c8fc42db7d38cf3314ef95a5f7d6ef95d57c))

- The wizard's test turn stops at 20 s and a late answer is ignored
  ([`733322c`](https://github.com/mfozmen/notelore/commit/733322c789d8ce71648fb84b779f6fef833bd962))

- The working line is a passing status, not an answer bubble
  ([`9b30fe0`](https://github.com/mfozmen/notelore/commit/9b30fe0085fa37efa7dc507c5b86c2e273f286f3))

- Tick the open todo when the user says a task is done
  ([`4f9aed4`](https://github.com/mfozmen/notelore/commit/4f9aed47a5032f27668370705cbe028e26963466))

- When the app locks, a note or dialog left open closes, so only the lock shows
  ([`a0baa7e`](https://github.com/mfozmen/notelore/commit/a0baa7e96422d5a1530759a14e455402e6b8555f))

- With no model, nothing sends: no resend or quick answers, and send does nothing
  ([`0b7e580`](https://github.com/mfozmen/notelore/commit/0b7e5801c58a6c29abc23448e0b38d5f3229745d))

### Features

- A welcoming Google sign-in screen with Google's own button
  ([`a55df95`](https://github.com/mfozmen/notelore/commit/a55df951f3e7b37944cc2951048e81c371c78a8e))

- Attach images in the chat; the model sees them
  ([`e19e25f`](https://github.com/mfozmen/notelore/commit/e19e25f68bd0d8981b315b592210911b8eb559c4))

- Attach PDFs in the chat; their text goes to the assistant
  ([`1e92c05`](https://github.com/mfozmen/notelore/commit/1e92c05a1c110ea22b42209b700b132d6401640e))

- Back from any key page, a copied key of that provider goes into the box
  ([`3a0e0d3`](https://github.com/mfozmen/notelore/commit/3a0e0d3335bdcb7488d7f510818bd8b32f097479))

- List connected models, switch back with one tap, remove one
  ([`9e229ab`](https://github.com/mfozmen/notelore/commit/9e229ab9e114ccfa3a4b4835b7af063eb4ff734b))

- Notelore's own mark and app icons, instead of Flutter's
  ([`c528c34`](https://github.com/mfozmen/notelore/commit/c528c3419bc517d0a446aed82a9a2290f3f7ad13))

- Ollama's Connect step says how to install it and pull a model, and needs one
  ([`91e663b`](https://github.com/mfozmen/notelore/commit/91e663bf1c5f285abeab1395044c69470a9c7f55))

- Redesign the setup screen in the welcome's visual language
  ([`7145d40`](https://github.com/mfozmen/notelore/commit/7145d4091fc82397a7b47bf9a8072835550353a6))

- Settings lists connected models: switch with one tap, remove one, connect another
  ([`7bc507e`](https://github.com/mfozmen/notelore/commit/7bc507efd700dbce99835a658fe119facc6ea3e1))

- The assistant takes notes instead of making conversation
  ([`8757129`](https://github.com/mfozmen/notelore/commit/87571294307c4b94c11c578b9394551cd7a2882d))

- The provider wizard: Choose, Connect, Done, with back and a step indicator
  ([`8f12199`](https://github.com/mfozmen/notelore/commit/8f1219983d950f8251bea3f7049dd9ab2e60b1bc))

- The wizard's Choose step compares every option on a card
  ([`d43fe2a`](https://github.com/mfozmen/notelore/commit/d43fe2a9cd7ed9d20c0c33d9bb6aaf304464ec31))

- The wizard's Done step says hello through the new model, so you see it works
  ([`e5c0902`](https://github.com/mfozmen/notelore/commit/e5c0902facd647b870037d88bc3342f087d72674))

- With no model in use, the app stays open and the chat asks for one
  ([`2dbca93`](https://github.com/mfozmen/notelore/commit/2dbca937e35d1a7e665a3f830fb0aa7f871a97ad))

### Performance Improvements

- Refresh only changed note index files ([#332](https://github.com/mfozmen/notelore/pull/332),
  [`7677d0e`](https://github.com/mfozmen/notelore/commit/7677d0eefb0a17e8b41aaf96f0f80f6fc32644eb))


## v0.12.0 (2026-10-17)

### Bug Fixes

- A device synced before the update opens offline; only a refusal means no account
  ([`2b41d69`](https://github.com/mfozmen/notelore/commit/2b41d69b338d22c24c7cbd21bbed4b5eb084b49c))

- A file cannot break out of its marker; the size limit counts every file
  ([`3a1416f`](https://github.com/mfozmen/notelore/commit/3a1416f64fa7d0291b3ec43b05d3cba36615833b))

- A folder the old notes move cannot remove does not stop the start
  ([`d2cd3fc`](https://github.com/mfozmen/notelore/commit/d2cd3fcfbe2527ca35b2e135372bc51972930330))

- A Gemini answer without answer tokens still counts its prompt
  ([`b9b53c7`](https://github.com/mfozmen/notelore/commit/b9b53c7fb12caba50f00af81e7257c64e9b7738a))

- A message written during a retry waits too, and logout mid-retry leaves nothing stuck
  ([`ac0a300`](https://github.com/mfozmen/notelore/commit/ac0a3006b032153e12151d01e679eac366a48954))

- A note file that cannot be read stays put instead of stopping the start
  ([`2cf4b0a`](https://github.com/mfozmen/notelore/commit/2cf4b0a8625fba99ee0196f08ee9858bdb21bd3d))

- A question that names a note searches only that note
  ([`3d6f36c`](https://github.com/mfozmen/notelore/commit/3d6f36c806163832278aa2084114f16a3e875ef3))

- A reply lost while the phone had Notelore in the background arrives on return
  ([`6012107`](https://github.com/mfozmen/notelore/commit/6012107ea3def5f047f66379f7e07ef540de6fd0))

- A turn that never got an answer keeps the archive notice for the next
  ([`eec31d1`](https://github.com/mfozmen/notelore/commit/eec31d17a7af898e94bedee568feb1edd06f7b64))

- Back before the failure surfaced, the reply is fetched at once; logout drops a held message
  ([`d37d1ba`](https://github.com/mfozmen/notelore/commit/d37d1ba7f2b375d3de2302c2b5f160a9d3bfc59a))

- Cut pages keep no script, stalled downloads stop, Recents shares once
  ([`7637ff4`](https://github.com/mfozmen/notelore/commit/7637ff41b7c7f9f433c66a35d04a68807d10cf27))

- Keep an unsent chat draft across tabs and layouts
  ([#234](https://github.com/mfozmen/notelore/pull/234),
  [`dd0a3de`](https://github.com/mfozmen/notelore/commit/dd0a3deb1e430e3f061c32ddb7dda7c511cfe3d0))

- Messages that joined a turn which has to wait are kept in the queue too
  ([`2bcbf8c`](https://github.com/mfozmen/notelore/commit/2bcbf8c6c7603b0b29b9e8981d7678a4a26b4888))

- Name a note with whole words only, so "Plan" does not capture "planning"
  ([`c544d29`](https://github.com/mfozmen/notelore/commit/c544d291b5f3aa38247552fd518e31c7b70d88cf))

- Suggested answers only after a question
  ([`f9eaf80`](https://github.com/mfozmen/notelore/commit/f9eaf80950d2376cc9fcf2fc2b96fe97850f53bd))

- Sync never writes over an edit saved while it downloads
  ([`c04fd32`](https://github.com/mfozmen/notelore/commit/c04fd32c32ffe6149db847f82b8e0ac177cf30c2))

- The assistant never answers from archived notes
  ([`79bb872`](https://github.com/mfozmen/notelore/commit/79bb872cfefb0208e82e11468d06fca0b0c67310))

- The ChatGPT sign-in on a phone keeps trying until OpenAI is reachable
  ([`ab89164`](https://github.com/mfozmen/notelore/commit/ab8916440bfa7e537a204802961816e0e67fc819))

- The talk button reads as disabled to a screen reader while it works
  ([`9a2cbda`](https://github.com/mfozmen/notelore/commit/9a2cbda56363ce706aaffd4546e4460bd4b5cbe1))

- Write English terms the way they are spelled, not how they sounded
  ([`ed65f88`](https://github.com/mfozmen/notelore/commit/ed65f88caf9af1831a1654036cc0d2dc1b7c2762))

### Features

- Attach text files in the chat; the assistant files them into notes
  ([`ae72f90`](https://github.com/mfozmen/notelore/commit/ae72f90ec818c7f96569b8b18edf50f63226cf77))

- Copy a message or an answer with one tap
  ([`c9129a4`](https://github.com/mfozmen/notelore/commit/c9129a4385537de3ca692e4080b98b38f6e574a4))

- Export, share and import notes ([#247](https://github.com/mfozmen/notelore/pull/247),
  [`be9a66c`](https://github.com/mfozmen/notelore/commit/be9a66c7ce8f8c1a768e0351a785554b1bcfae46))

- Find related notes across categories and merge them on request
  ([`61dc37a`](https://github.com/mfozmen/notelore/commit/61dc37a1e26717b73ab73cfd6511918c61928d38))

- Messages wait offline or over the usage limit, and go out later
  ([`8e0d030`](https://github.com/mfozmen/notelore/commit/8e0d030dbf1d95e8d967f0ce9952ae27dfaa66de))

- Notes live in the app's own folder, one copy, no path to manage
  ([`99d90df`](https://github.com/mfozmen/notelore/commit/99d90dff9e998db84b8fe777375bc985baf9b84b))

- One composer button: Send with text, push to talk without
  ([`749b386`](https://github.com/mfozmen/notelore/commit/749b38647ba805d5400591d79488544d820d039c))

- Open saved note links in browser ([#223](https://github.com/mfozmen/notelore/pull/223),
  [`4718f81`](https://github.com/mfozmen/notelore/commit/4718f815de193c965fcb05b842dd4ccc919d3b3d))

- Optional PIN or password to open Notelore ([#241](https://github.com/mfozmen/notelore/pull/241),
  [`b72ce5b`](https://github.com/mfozmen/notelore/commit/b72ce5bd0120f24f8761f270c25cda7e60be7099))

- Playful waiting lines instead of a plain "Thinking"
  ([`be4357c`](https://github.com/mfozmen/notelore/commit/be4357c2970c3b56e7b3dcc69308a37bc6ff0df5))

- Push to talk by keyboard and screen reader
  ([`12b4c14`](https://github.com/mfozmen/notelore/commit/12b4c147adf5c55d54056fb8ea5f912701a961cb))

- Read shared links and file them by what the page says
  ([`db8226c`](https://github.com/mfozmen/notelore/commit/db8226cdf61995912cb5cff0a9fe2ae05f9e0702))

- Resend the last message with one tap ([#220](https://github.com/mfozmen/notelore/pull/220),
  [`218441f`](https://github.com/mfozmen/notelore/commit/218441fc2cf0b09df205a38030e8d7ce5182c1d9))

- Setup leads with Continue with ChatGPT; keys and local models under Advanced
  ([`b99334c`](https://github.com/mfozmen/notelore/commit/b99334c09b569c9124acea4b5489cdbe414de4dd))

- Show token usage and an estimated cost in Settings
  ([`7bf8ad1`](https://github.com/mfozmen/notelore/commit/7bf8ad1b39f9ebe78dafaf32e3d575814e1224c1))

- Sign in with Google first; Notelore needs a Google account
  ([`c10552a`](https://github.com/mfozmen/notelore/commit/c10552a1d01152f04fe8400394c4b7bdc20efdad))

- Suggested answers as buttons under the assistant's question
  ([`7ca8d0e`](https://github.com/mfozmen/notelore/commit/7ca8d0ea92ef9f003d8f566c3e8124560a1e98ee))

- Time each model call, tool call and queue wait in development runs
  ([`6bfe564`](https://github.com/mfozmen/notelore/commit/6bfe564ca66fa318f06784603393a97399ae65e7))

### Performance Improvements

- Document Android latency probe ([#267](https://github.com/mfozmen/notelore/pull/267),
  [`890bb8e`](https://github.com/mfozmen/notelore/commit/890bb8eb055deddc67eae1779aa84bf6015de970))


## v0.11.0 (2026-10-12)

### Bug Fixes

- A plain click on the talk button says to hold; an overtaken turn keeps its failure
  ([`8a23b6a`](https://github.com/mfozmen/notelore/commit/8a23b6a8f931af6fc40a6a87c43c2edf83d047c5))

- A resume the server refuses starts the Whisper file over
  ([`420cd39`](https://github.com/mfozmen/notelore/commit/420cd392bd5b4a049f722ca780d3e3f90e57e678))

- A resumed Whisper download appends only the rest it asked for
  ([`a2d76e5`](https://github.com/mfozmen/notelore/commit/a2d76e5b2756532a7a0a81a456bdf76dcdc5e68d))

- An archived note comes back under its own name; archived entries go back into their note
  ([`ce0426f`](https://github.com/mfozmen/notelore/commit/ce0426f718eba63e20d537761f14203fc6e1a522))

- Just "Listening…" while the button is held
  ([`a0e5d82`](https://github.com/mfozmen/notelore/commit/a0e5d82a2a1d789ab4417c10527814dce3b6da29))

- List the microphones again from Settings; log why none were listed
  ([`7ca397a`](https://github.com/mfozmen/notelore/commit/7ca397a22b34f44774ff624c31b4c96e63142a2a))

- Phones offer the ChatGPT plan and no longer a model "on this computer"
  ([`0d32315`](https://github.com/mfozmen/notelore/commit/0d323158f182aec768694437b2c42251e627b7aa))

- The side rail and side-by-side panes switch at one window width
  ([`320f992`](https://github.com/mfozmen/notelore/commit/320f9925008f989da1c70270e0190c993c01ad20))

- Whisper's download resumes after a lost connection; review follow-ups
  ([`feb6619`](https://github.com/mfozmen/notelore/commit/feb6619492a9069b68f42cd1ed37a3d53f6de840))

### Features

- Push to talk: hold the microphone button, let go to send
  ([`19aa72d`](https://github.com/mfozmen/notelore/commit/19aa72dc6e23d2498be74cbc5acf754f9b8298f8))

- Settings pickers with one designed look; the model is picked, never typed
  ([`cee79a4`](https://github.com/mfozmen/notelore/commit/cee79a45af4d51d028cca351740bbd52d1144cd4))


## v0.10.0 (2026-10-12)

### Bug Fixes

- A microphone not plugged in now records from the default; doc comments in place
  ([`0417a57`](https://github.com/mfozmen/notelore/commit/0417a57cae7d6ec8d3a0a3f7841cfd62251754f4))

- The open note follows a sync or the assistant; comment on its line
  ([`02d617c`](https://github.com/mfozmen/notelore/commit/02d617cdc69bd1d58684ad1d918316aa0441cc49))

- The open note shows same-day changes too
  ([`43448ea`](https://github.com/mfozmen/notelore/commit/43448ea809637c9f4e4b969d567913aaf32d0ff0))

- Whisper hears a quiet Windows microphone
  ([`d72680a`](https://github.com/mfozmen/notelore/commit/d72680ab70a6fc3918f8d614abd5d1baed502aec))

### Features

- A desktop layout: side rail, a readable chat column, notes beside the reader
  ([`bc4dbf0`](https://github.com/mfozmen/notelore/commit/bc4dbf02f4766dc27b0df73e99a2417b5efadd04))

- Check for updates every time the app opens
  ([`9b5282f`](https://github.com/mfozmen/notelore/commit/9b5282f7276e66eed80b34de7af61be1ba2b61b3))

- Pick the microphone Whisper records from
  ([`709960a`](https://github.com/mfozmen/notelore/commit/709960a0dc601dbb3886153e130a8fa61563a8d1))

- Settings on a wide window: sections on the left, one at a time
  ([`074306a`](https://github.com/mfozmen/notelore/commit/074306afbecf818fc399b96eca26b2b5dc6831f1))

- Whisper downloads by itself on first start; no button, no switch
  ([`210f1ff`](https://github.com/mfozmen/notelore/commit/210f1ff8e7aae92c1694543939d6aef10063b055))


## v0.9.0 (2026-10-12)

### Bug Fixes

- A long phrase is not cut off by Whisper's silence timeout; pinned model
  ([`80a090a`](https://github.com/mfozmen/notelore/commit/80a090aa7dc2768f0418601835a3742b2101deca))

- Android voice mode asks only for the microphone, and says why it cannot start
  ([`560d130`](https://github.com/mfozmen/notelore/commit/560d1300130d70f10cf9d52f16595f961a9126a8))

- Voice mode uses the words it heard even when the recognizer never marks them final
  ([`1206ad1`](https://github.com/mfozmen/notelore/commit/1206ad1e46cfdd71c63f6f5a125a5fec1d51f066))

### Features

- On-device Whisper for voice mode, downloaded from Settings
  ([`9b69e75`](https://github.com/mfozmen/notelore/commit/9b69e75b88120b00d341bb412cb89de7759d7d31))

- Settings in two columns on wide windows, with an About card
  ([`87ab3eb`](https://github.com/mfozmen/notelore/commit/87ab3eb516a46a8c57385d74a7e730ae46ba6c49))


## v0.8.0 (2026-10-12)

### Bug Fixes

- The "moved to the archive" notice goes away by itself, with a close button
  ([`3b88be9`](https://github.com/mfozmen/notelore/commit/3b88be9a2dfdd90b81ee3dfc0ba4943846606caf))

### Features

- An Archive in the Notes screen, to browse and restore deleted notes
  ([`ad68dd5`](https://github.com/mfozmen/notelore/commit/ad68dd50b55a2011e196394ddc937728a270be31))

- Show the app version in Settings
  ([`ec0afae`](https://github.com/mfozmen/notelore/commit/ec0afae7f3cc10997d2e85a18e2629bc6518d6be))


## v0.7.0 (2026-10-12)

### Bug Fixes

- A message taken by a turn that then fails still goes out; busy stays on across follow-ups
  ([`0ca1336`](https://github.com/mfozmen/notelore/commit/0ca13363ce08fe7ec380c08fe99138e7756d2fd4))

- A route that refuses the search tool still answers, without search
  ([`99d61bb`](https://github.com/mfozmen/notelore/commit/99d61bbb6554f7a13349344b20a9a0be3cc942ed))

- Keep Anthropic's search blocks out of the provider's answer
  ([`01c5277`](https://github.com/mfozmen/notelore/commit/01c5277adfe08340cdbffa2d0539e22321b4eaa1))

### Features

- Keep writing while the assistant works, one answer for all
  ([`de42d9e`](https://github.com/mfozmen/notelore/commit/de42d9e0f62eac86195ea010209746f78c1ee84d))

- Look things up on the web when it helps a note, with a setting
  ([`aea5c9a`](https://github.com/mfozmen/notelore/commit/aea5c9a305acb4d8eae070938a0ce4c41f811cb5))

- Nature themes, each in light and dark
  ([`b886856`](https://github.com/mfozmen/notelore/commit/b886856207aa057e0c6b8eaabd21a65269b796fa))


## v0.6.0 (2026-10-11)

### Bug Fixes

- A new top model never hides the cheaper ones before it
  ([`81df1b3`](https://github.com/mfozmen/notelore/commit/81df1b37dccd96c1e0a7e6cf89a2271c4e962c14))

- A recognizer failure reads in the app language
  ([`a68a2a7`](https://github.com/mfozmen/notelore/commit/a68a2a774cc21e7cde24360864667183ccb4a85d))

- A timer check never touches an installing update or a put-off version
  ([`27bab7a`](https://github.com/mfozmen/notelore/commit/27bab7a812b96fc8d525da64928b4614cc80e726))

- A visible delete button on every note in the list
  ([`21a0c79`](https://github.com/mfozmen/notelore/commit/21a0c7931521be9057a82e8a127cd1bd71fbe9d2))

- An installer failure shows in the banner; one APK copy at most, made off the main thread
  ([`0f7baf9`](https://github.com/mfozmen/notelore/commit/0f7baf94bf65c357f420efa1096f0b9f530efc6e))

- Keep the string tables out of duplicate detection; forgiving language save
  ([`e9f96fd`](https://github.com/mfozmen/notelore/commit/e9f96fd89c8bf6c27da59c65d10856ba85f19a6c))

- List the Windows app as plain "Notelore" in Installed apps
  ([`aaaa6ec`](https://github.com/mfozmen/notelore/commit/aaaa6eca196a9415d80a8be7c6cb3ceb6ce81f5b))

- Say OpenAI, not ChatGPT, in errors a key user can see
  ([`ab74f49`](https://github.com/mfozmen/notelore/commit/ab74f49e5ed20619e34553d3b1e367eff04c0331))

- Use the Responses API for GPT with an API key
  ([`32ffaaf`](https://github.com/mfozmen/notelore/commit/32ffaafbf372bd219ece28b113256a5fdaad58a2))

- Voice mode survives a closed chat, stops on real recognizer errors, speaks answers only
  ([`27ff4e8`](https://github.com/mfozmen/notelore/commit/27ff4e8eddd7cd4225f754d113846906e753747b))

### Features

- A calmer, more polished look
  ([`2fb1840`](https://github.com/mfozmen/notelore/commit/2fb1840d70fd2cd34a6b84d5cab4ff3c067d567a))

- Check for updates by hand, and while the app stays open
  ([`5cb2fb5`](https://github.com/mfozmen/notelore/commit/5cb2fb51f72a4d06dd5d22e1754a9cf4a9b27667))

- List only the current model versions, cheapest by default
  ([`87f0867`](https://github.com/mfozmen/notelore/commit/87f0867a5bb6ee27ca74358d9ec93f8e42fa1bed))

- Sync the app settings through Google Drive
  ([`9453f3a`](https://github.com/mfozmen/notelore/commit/9453f3ab2bc57c0771f1f2b22a7379e02c03f2ec))

- Turkish app language, picked in Settings
  ([`6527488`](https://github.com/mfozmen/notelore/commit/652748850fbdc0106216ef7c1c8507c2640c39fc))

- Update the Android app from inside the app
  ([`c229c0c`](https://github.com/mfozmen/notelore/commit/c229c0c1ca155b21281f8eadd4d31957769d58f6))

- Voice mode, talk to the assistant and hear its answers
  ([`d50e991`](https://github.com/mfozmen/notelore/commit/d50e9914a738f6450f8eae9691f0a5214fb63062))


## v0.5.0 (2026-10-11)

### Bug Fixes

- Read the ChatGPT plan's answer from its streamed items
  ([`7f1e0df`](https://github.com/mfozmen/notelore/commit/7f1e0df452b452a711dfebf9112200c91a074030))

- Say so when a note to delete is already gone
  ([`854a48d`](https://github.com/mfozmen/notelore/commit/854a48d3c212c87671f60ba7d6ee84f812e5082a))

- Stop a turn still queued behind a sync; label unknown tools neutrally
  ([`a8560b4`](https://github.com/mfozmen/notelore/commit/a8560b45e961c7a1e0cc16eb91a258628ff1a89e))

### Features

- A dev command line that runs and traces real agent turns
  ([`1f7b348`](https://github.com/mfozmen/notelore/commit/1f7b34830e8fbc2e3e74e685d1bfbd22d3f06ad7))

- Ask for another model when the chosen one is no longer offered
  ([`0de8b66`](https://github.com/mfozmen/notelore/commit/0de8b665f33df6c40e2128fa2315773d103b394e))

- Delete a note from the Notes screen, with undo
  ([`40e13a6`](https://github.com/mfozmen/notelore/commit/40e13a61f06539317bdc49b93af20d2eaafa39b2))

- Group model providers by how they are paid for
  ([`84d5572`](https://github.com/mfozmen/notelore/commit/84d557275e3efeb90880ddabd98bb58d7334f100))

- Refresh the model list on every start
  ([`6243022`](https://github.com/mfozmen/notelore/commit/6243022b04e7656fd44d42205e5d2e5be420c3cb))

- Show what the assistant is doing, and let a turn be stopped
  ([`7ba166d`](https://github.com/mfozmen/notelore/commit/7ba166df8774884de4c87d88b33138380efa5bfe))

- Start an API key on the cheapest model it lists
  ([`99ecabf`](https://github.com/mfozmen/notelore/commit/99ecabf0722214a871d1ecedf754bc9a64bb5256))

- Switch the model from the chat screen
  ([`a9c7a8e`](https://github.com/mfozmen/notelore/commit/a9c7a8ee0fde41c4bfd4827a831fe67a8c7b811c))


## v0.4.1 (2026-10-11)

### Bug Fixes

- Install for all users into Program Files by default
  ([`ddc7d02`](https://github.com/mfozmen/notelore/commit/ddc7d02942086b51ccf660e75c80aafa27856926))

- Let the Windows setup install for all users into Program Files
  ([`b7bbed0`](https://github.com/mfozmen/notelore/commit/b7bbed0df6bf52e7725004ac74720a9e65763989))


## v0.4.0 (2026-10-10)

### Bug Fixes

- A long Turkish inflection finds the bare root
  ([`e34397b`](https://github.com/mfozmen/notelore/commit/e34397bb9e6bfa278504ef839d12de621fa2719d))

- A model list that arrives after logout is dropped
  ([`e3d3572`](https://github.com/mfozmen/notelore/commit/e3d3572f53ca451cc80f499ad45dfd06a7592abf))

- A Turkish question finds its note; the agent keeps details
  ([`8b7a52f`](https://github.com/mfozmen/notelore/commit/8b7a52fadc8d880dbd09ee6cc9076fb31f735059))

- Never swap in a half-copied app; clean leftover setups
  ([`21b1786`](https://github.com/mfozmen/notelore/commit/21b17863c8ca0ec09cae76434283d1995b6d4c4c))

- One ChatGPT token refresh at a time; tolerate stream markers
  ([`8c27fb8`](https://github.com/mfozmen/notelore/commit/8c27fb830c14cd2b67bf01b1544b6a57d3eb5079))

- One idle check for timer and resume syncs; count queued syncs
  ([`3e0322a`](https://github.com/mfozmen/notelore/commit/3e0322ad02b867f3b4ac50f70acd26561e8db134))

- Sync other devices' changes while the app is open
  ([`9db6f8d`](https://github.com/mfozmen/notelore/commit/9db6f8dd0630fdcbfeaa9c65428b073b122e5b21))

### Features

- Installers instead of zips; updates run the installer
  ([`4925298`](https://github.com/mfozmen/notelore/commit/4925298b49bba2b5b5a8a376c2529f0bd7b7395a))

- Pick the model from the list the provider gives
  ([`9b684f3`](https://github.com/mfozmen/notelore/commit/9b684f3e8198aadf5080a36ae069611b67f25f50))

- Say what each model provider costs before asking for a key
  ([`6fc5bf9`](https://github.com/mfozmen/notelore/commit/6fc5bf97fd8b5d1f91ded28a27a465eb872853db))

- Use a ChatGPT Plus or Pro plan ("Sign in with ChatGPT")
  ([`c8004ed`](https://github.com/mfozmen/notelore/commit/c8004edd810ce23ed577ec6b04c27e81a15003d7))


## v0.3.0 (2026-10-05)

### Bug Fixes

- A failed reconnect restores the previous key
  ([`97f6e5d`](https://github.com/mfozmen/notelore/commit/97f6e5d29dcaa9d7874976094f4dce0aee16634a))

- Allow hand-made note file names, reject only path escapes
  ([`b0a6cc3`](https://github.com/mfozmen/notelore/commit/b0a6cc3bc7d1c331328590a29dc5180d4a8c2a07))

- Close a session that finishes opening after the app is gone
  ([`b9609fb`](https://github.com/mfozmen/notelore/commit/b9609fbcb276614d9e028f4a1bc0e264ec5c1e65))

- Drop half-built tool_use blocks and reject non-object tool input
  ([`1f060d1`](https://github.com/mfozmen/notelore/commit/1f060d1c18c47f58e0a88e64101543cd6fdb6b67))

- Drop unsafe manifest entries on load, treat damaged base copies as missing
  ([`6d5aab6`](https://github.com/mfozmen/notelore/commit/6d5aab646b1303bcd4d376453d6927a1bf5968e9))

- Keep user and assistant turns alternating after an empty answer or max_turns
  ([`49f438f`](https://github.com/mfozmen/notelore/commit/49f438f1c23c3aee6455f243a565d82e2fdc3ce2))

- Never keep a key whose provider settings could not be saved
  ([`32ee2b2`](https://github.com/mfozmen/notelore/commit/32ee2b273db6bb1eb80578ce71efd5a85dc68282))

- NFC and case-safe sync keys, per-file decode errors, upload-first merges
  ([`3567d5c`](https://github.com/mfozmen/notelore/commit/3567d5cdaa9db69eeaf1c00ff9c844f96d11465d))

- NFC-normalize decision topics before matching
  ([`39de52a`](https://github.com/mfozmen/notelore/commit/39de52a9589def381e9126e6504a0a758dd9640a))

- NFC-normalize model merges and surface deletions in the explanation
  ([`d4a140f`](https://github.com/mfozmen/notelore/commit/d4a140fe8917df5db76f5a05876bf7f0bbb620c0))

- Normalize decision input, NFC on write, position-based todo and archive edits
  ([`b37f75b`](https://github.com/mfozmen/notelore/commit/b37f75bc72bbe1438fca495218a2884367364aff))

- Offline token refresh, stray loopback requests, held notes
  ([`fc80e21`](https://github.com/mfozmen/notelore/commit/fc80e21ca0ff010ab0610a5269ed0d2c0720b6b4))

- Reject an empty checksum file, say what the checksum protects against
  ([`1c14b19`](https://github.com/mfozmen/notelore/commit/1c14b1923cb3841d387611c44eab141c5b6caa9b))

- Reject non-canonical slugs so a model-supplied slug cannot leave the notes folder
  ([`2aecf70`](https://github.com/mfozmen/notelore/commit/2aecf708dff0778213b616d742f9498b80fd2c29))

- Report Anthropic early stops, whitelist block fields, compare finish_reason to None
  ([`6075736`](https://github.com/mfozmen/notelore/commit/6075736fd2ea51171b44c859f5204214cd41807b))

- Roll back a failed agent turn; harden tool schemas
  ([`ce58edd`](https://github.com/mfozmen/notelore/commit/ce58eddea0a467def7f2be6ca9d2d857b873059d))

- Roll back a failed index rebuild; forbid CR in slugs
  ([`24a3656`](https://github.com/mfozmen/notelore/commit/24a3656a9fd04cab62c603bc89afd899eeddf574))

- Roll back a failed macOS bundle swap; clearer update failures
  ([`a032fbb`](https://github.com/mfozmen/notelore/commit/a032fbb6e093988d8eb2156e91cedcd3442fac97))

- Treat a non-JSON success page as an HTTPError
  ([`e45f14c`](https://github.com/mfozmen/notelore/commit/e45f14c0a1b08f842837a48afec6b876fa1d0ad4))

- Use the Briefcase template's default Android theme
  ([`9e1a4c4`](https://github.com/mfozmen/notelore/commit/9e1a4c4b9e255ff29099c3b6fc083d1f9a23ad57))

- Validate nested tool arguments, create temp notes without chmod
  ([`f10d642`](https://github.com/mfozmen/notelore/commit/f10d642a4e275fe3e4b58aa425fce99f12bcd3ae))

### Features

- Agent tool-use loop with the system prompt rules
  ([`047027b`](https://github.com/mfozmen/notelore/commit/047027b9061fee9dbd6f4727be00ee6888bf5492))

- Agent tools as thin wrappers over the store
  ([`8691691`](https://github.com/mfozmen/notelore/commit/8691691ce5cb2bfbde27d8bb70cdec5b5babce73))

- Android spike, Briefcase app on the shared core with an APK in CI
  ([`dbb2a11`](https://github.com/mfozmen/notelore/commit/dbb2a1111993994729f42ddef2dd45ca6c604ffd))

- Find_stale_notes with the three deterministic staleness signals
  ([`f4cda0d`](https://github.com/mfozmen/notelore/commit/f4cda0d3300d6deebf3bf086b05526c51e11999f))

- Google Drive sign-in and sync in the app
  ([`5f8d5b8`](https://github.com/mfozmen/notelore/commit/5f8d5b83dcab4af202786f25ab10e9cde9f28fb1))

- LLM providers over plain HTTPS, no vendor SDKs
  ([`8cd02cf`](https://github.com/mfozmen/notelore/commit/8cd02cf8504b9b30f8aab72ae7a501599ad4d487))

- LLM providers ported from littlepress-ai with key validation and keyring secrets
  ([`127827d`](https://github.com/mfozmen/notelore/commit/127827d48c948ba83b01ec3558f5cc04afa7afac))

- LLM providers, agent loop and note tools in Dart
  ([`1671f9b`](https://github.com/mfozmen/notelore/commit/1671f9b95b2dfcb2b6f2e33e1e3b7e294fe36747))

- Model resolver for true same-line sync conflicts
  ([`b479a23`](https://github.com/mfozmen/notelore/commit/b479a236f9e00f154b928e2313bd973ba772ae58))

- Note file operations with atomic writes, slugs and archive
  ([`e088e27`](https://github.com/mfozmen/notelore/commit/e088e271a434a8cab8107798be3924dfebe7c0da))

- Note format, front matter, paths and i18n in Dart
  ([`4c2f133`](https://github.com/mfozmen/notelore/commit/4c2f1339a494b4d6d15c6732ff8d85f582e36e66))

- Release the app and update it in place on the desktop
  ([`d11bd51`](https://github.com/mfozmen/notelore/commit/d11bd51b940da95c74783189c7b457193986b75e))

- REPL with provider picker, key entry and slash commands
  ([`625508f`](https://github.com/mfozmen/notelore/commit/625508f579c5aa30fb72cfa2d7c91536c69798f5))

- SQLite index with FTS5 search, LIKE fallback and decision lookups
  ([`38c20d1`](https://github.com/mfozmen/notelore/commit/38c20d1bc480b02245a08c90f1c5a0b0a2fd17b6))

- Store, search index and stale notes in Dart
  ([`694e4e1`](https://github.com/mfozmen/notelore/commit/694e4e1eaebf2b99cc8f0ca918ea819421d72427))

- Sync decision table and three-way line merge
  ([`8f9df5c`](https://github.com/mfozmen/notelore/commit/8f9df5cd3fabc4c54fa4f41d4e626e98485e162b))

- Sync engine against a Remote protocol
  ([`500f849`](https://github.com/mfozmen/notelore/commit/500f849336624212af753dd98763b63de2b69444))

- Sync manifest with merge-base copies in the state dir
  ([`8a67a33`](https://github.com/mfozmen/notelore/commit/8a67a3366f4850a22d1c352998f75678a870b492))

- Sync merge, manifest, engine and model resolver in Dart
  ([`c2dba6e`](https://github.com/mfozmen/notelore/commit/c2dba6e56caa770a11e2aa1c3d47be8446ddcd5c))

- The Flutter app UI: setup, chat, notes and settings
  ([`2914866`](https://github.com/mfozmen/notelore/commit/2914866e9a5a1cbfeee8fcfe65635b7671a6d343))

- Verify self-updates against a published SHA-256
  ([`d9b6d4d`](https://github.com/mfozmen/notelore/commit/d9b6d4d647154182281c3e4c13977ef426568d6f))


## v0.2.0 (2026-09-30)

### Bug Fixes

- Keep the update check silent and the executable swap safe
  ([`967bc7c`](https://github.com/mfozmen/notelore/commit/967bc7c8c89cd77e0512573ba9d28b6803f81b9d))

- Tolerate a locked .old executable and drop the download on a failed swap
  ([`53a0bf4`](https://github.com/mfozmen/notelore/commit/53a0bf475b349ac7edaa3c446564896d7b100ae0))

### Features

- Daily update check and notelore update self-update
  ([`93ee126`](https://github.com/mfozmen/notelore/commit/93ee1261d3f92dc212176bdc438a0bc942457f34))


## v0.1.0 (2026-09-30)

### Bug Fixes

- Reject non-mapping or title-less front matter with ValueError
  ([`0db9c68`](https://github.com/mfozmen/notelore/commit/0db9c68c891bfd834b25a8c6943a282d2b03e178))

### Features

- Paths and note format parser/serializer
  ([`d382556`](https://github.com/mfozmen/notelore/commit/d382556e77e4d38d4e380dddf98c81fffc328475))


## v0.0.0 (2026-09-30)

- Initial Release
