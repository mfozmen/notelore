# CHANGELOG

<!-- version list -->

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

### Chores

- Share project guidance with Codex ([#230](https://github.com/mfozmen/notelore/pull/230),
  [`0731a6f`](https://github.com/mfozmen/notelore/commit/0731a6f32cc74f6559f5b940eee2477fcd02846f))

### Continuous Integration

- A PR with new SonarCloud issues fails the SonarCloud check
  ([`4e8199c`](https://github.com/mfozmen/notelore/commit/4e8199c0123cad36dc5161e33a93a440c53b2afa))

- Every issue carries a priority label
  ([`e7074ce`](https://github.com/mfozmen/notelore/commit/e7074ce8b7b8ab0a1c7092fd78914b96d2ffbbfb))

### Documentation

- Clarify emulator probe setup ([#267](https://github.com/mfozmen/notelore/pull/267),
  [`890bb8e`](https://github.com/mfozmen/notelore/commit/890bb8eb055deddc67eae1779aa84bf6015de970))

- Clarify large-corpus timing limits ([#259](https://github.com/mfozmen/notelore/pull/259),
  [`b907713`](https://github.com/mfozmen/notelore/commit/b90771343a2c8b128e0c5a8c161f878ef774decb))

- Measure assistant response latency ([#259](https://github.com/mfozmen/notelore/pull/259),
  [`b907713`](https://github.com/mfozmen/notelore/commit/b90771343a2c8b128e0c5a8c161f878ef774decb))

- Measure synthetic assistant response latency
  ([#259](https://github.com/mfozmen/notelore/pull/259),
  [`b907713`](https://github.com/mfozmen/notelore/commit/b90771343a2c8b128e0c5a8c161f878ef774decb))

- Name the Sync settings section
  ([`4644253`](https://github.com/mfozmen/notelore/commit/46442535d36337ac6884772854d68772dfd44c21))

- Say where a named note's ending may go
  ([`59a3854`](https://github.com/mfozmen/notelore/commit/59a38540f2b009ea92c88e28cc4e7ea8eff3f6bf))

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

### Refactoring

- Const text styles in the PDF layout
  ([`f71d5dd`](https://github.com/mfozmen/notelore/commit/f71d5dd6a7c154c50609888bf16c87b7fdb94c34))

- No nested ternaries, one Content-Type constant
  ([`af917b0`](https://github.com/mfozmen/notelore/commit/af917b0b4d0e763c43f8d39d199cc5b52c0231e0))

- One chat turn and its failure in their own methods
  ([`c656317`](https://github.com/mfozmen/notelore/commit/c6563176be76586faf04997bf66aa92e827ac803))

- One chat turn and its failure in their own methods
  ([`f766850`](https://github.com/mfozmen/notelore/commit/f7668507090aed1e379172a520e6bc6501ecad26))

- Reading both sides of a note in its own method
  ([`4852268`](https://github.com/mfozmen/notelore/commit/48522680203098edca452f6c90c38cf0770f53de))

- Reading both sides of a note in its own method
  ([`bd6e56c`](https://github.com/mfozmen/notelore/commit/bd6e56cd9854de2b4c24ba7b9775ff29acc47d90))

- Split core functions over Sonar's complexity limit by job
  ([`253c2d0`](https://github.com/mfozmen/notelore/commit/253c2d0a32202975f85f35f0bc9b824277fb85a4))

- Split Home.build and the Whisper download by job
  ([`51e63b1`](https://github.com/mfozmen/notelore/commit/51e63b1326dd0ae2c8cb0c62e73c678d02610053))

- Split mergeNotes by job, under Sonar's complexity limit
  ([`978dd31`](https://github.com/mfozmen/notelore/commit/978dd3192224e5bc1ef9678e7d79c8b5b3538996))

- Split the chat and Settings screens into widgets by what they show
  ([`4d8f95a`](https://github.com/mfozmen/notelore/commit/4d8f95ab6fdbdf6aa8610981ed8b8446cf716aba))

- The app lock's state in its own class
  ([`e146d30`](https://github.com/mfozmen/notelore/commit/e146d304ebf653240be7ff4f376bcf5ff2cece5e))

- The composer's row is a widget of its own
  ([`f489b80`](https://github.com/mfozmen/notelore/commit/f489b807abe07a22c9b530d3eda806ee59ffb4e5))

- The remote side's hash in its own function
  ([`85e0d80`](https://github.com/mfozmen/notelore/commit/85e0d80544e8ccb06e94000286b56c6c3cd79e76))

- The voice status line is a widget of its own
  ([`7184a80`](https://github.com/mfozmen/notelore/commit/7184a80a2604b33b586fb9fd0349e28b539bf248))

### Testing

- A hold begun while an answer is read aloud still sends
  ([`90f72f8`](https://github.com/mfozmen/notelore/commit/90f72f8f2356a25a878a7855467571db9e42db05))

- Tap the rendered note links, including a bare URL
  ([#223](https://github.com/mfozmen/notelore/pull/223),
  [`4718f81`](https://github.com/mfozmen/notelore/commit/4718f815de193c965fcb05b842dd4ccc919d3b3d))


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

### Testing

- The archive tool reports the new archive paths
  ([`a258801`](https://github.com/mfozmen/notelore/commit/a258801b09338e0256522a9c409d056a5a9fe6ae))


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

### Documentation

- The README describes the Settings layout; a precise test title
  ([`a4e5ab3`](https://github.com/mfozmen/notelore/commit/a4e5ab378e0cdeb7d927bd3b18f0d2c48d859704))

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

### Chores

- Install the ui-ux-pro-max skill for the redesign
  ([`4a08b43`](https://github.com/mfozmen/notelore/commit/4a08b43d18bac35c7f3b9380fb5f102d6994219d))

### Continuous Integration

- Bump the actions group across 1 directory with 3 updates
  ([`0d4e936`](https://github.com/mfozmen/notelore/commit/0d4e93657d2d2ff373d1f6b6f7845480b59f5095))

- Skip the AI review on Dependabot's pull requests
  ([`81ccf3c`](https://github.com/mfozmen/notelore/commit/81ccf3cbf74872a07138e94e859a976eb824037c))

### Documentation

- A simpler README, with the SonarCloud badges
  ([`f233004`](https://github.com/mfozmen/notelore/commit/f233004132c434c82388b8a8132fb6e30c0985b2))

- Full file names, the Claude subscription note, precise Android update wording
  ([`a604af0`](https://github.com/mfozmen/notelore/commit/a604af0a7480fb623dff4ad154a262793231c8c5))

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

### Testing

- Pin the theme's contract; one radius constant per shape
  ([`dca5725`](https://github.com/mfozmen/notelore/commit/dca5725aca21cc240aa07deca122e649ae4eb416))


## v0.5.0 (2026-10-11)

### Bug Fixes

- Keep API-key headers out of the dev trace; option values may hold '='
  ([`4968242`](https://github.com/mfozmen/notelore/commit/4968242a1aaaf1b6715b719ff851b54a74241c5f))

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

- Give iscc the absolute build folder
  ([`3b42968`](https://github.com/mfozmen/notelore/commit/3b42968bb539490a1ee10f42f1bd5d68a7aaec89))

- Never swap in a half-copied app; clean leftover setups
  ([`21b1786`](https://github.com/mfozmen/notelore/commit/21b17863c8ca0ec09cae76434283d1995b6d4c4c))

- One ChatGPT token refresh at a time; tolerate stream markers
  ([`8c27fb8`](https://github.com/mfozmen/notelore/commit/8c27fb830c14cd2b67bf01b1544b6a57d3eb5079))

- One idle check for timer and resume syncs; count queued syncs
  ([`3e0322a`](https://github.com/mfozmen/notelore/commit/3e0322ad02b867f3b4ac50f70acd26561e8db134))

- Sync other devices' changes while the app is open
  ([`9db6f8d`](https://github.com/mfozmen/notelore/commit/9db6f8dd0630fdcbfeaa9c65428b073b122e5b21))

### Continuous Integration

- Upload the Windows release assets with bash; rebuild an existing tag
  ([`1a077e0`](https://github.com/mfozmen/notelore/commit/1a077e09849674e94416bcef56153b8c72a11acd))

- Write release checksums with LF on every OS
  ([`612acd4`](https://github.com/mfozmen/notelore/commit/612acd4b16f041ce5f3f10f8816b1b5490fa7dff))

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

- Close the review follow-ups from merged PRs
  ([`ad54d38`](https://github.com/mfozmen/notelore/commit/ad54d38277b1a1c7d35e50ef4b8d3df8f62fa419))

- Drop half-built tool_use blocks and reject non-object tool input
  ([`1f060d1`](https://github.com/mfozmen/notelore/commit/1f060d1c18c47f58e0a88e64101543cd6fdb6b67))

- Drop unsafe manifest entries on load, treat damaged base copies as missing
  ([`6d5aab6`](https://github.com/mfozmen/notelore/commit/6d5aab646b1303bcd4d376453d6927a1bf5968e9))

- Index review findings
  ([`87eab56`](https://github.com/mfozmen/notelore/commit/87eab56e53608e566e4f90865ef2ed81d65c089b))

- Keep notelore-core out of the mobile app's pip requirements
  ([`975d11b`](https://github.com/mfozmen/notelore/commit/975d11b170b605050a190a68623a63e753d2015f))

- Keep the spike check out of the user's notes, pin Briefcase
  ([`ad42d3d`](https://github.com/mfozmen/notelore/commit/ad42d3ddaf2f5d43ef9638ef859d422dd081d20e))

- Keep user and assistant turns alternating after an empty answer or max_turns
  ([`49f438f`](https://github.com/mfozmen/notelore/commit/49f438f1c23c3aee6455f243a565d82e2fdc3ce2))

- Key coverage gaps by report, map Dart lcov paths for Sonar, pin Flutter once
  ([`83d03aa`](https://github.com/mfozmen/notelore/commit/83d03aa46f40ee15b6d472de65b9ce8f40580fc9))

- Name the Briefcase app notelore-mobile so it does not shadow the core
  ([`7db0885`](https://github.com/mfozmen/notelore/commit/7db0885fca47bd7ea6e11a920f170327afcdec66))

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

- The app owns and closes its session; review findings
  ([`816cb3b`](https://github.com/mfozmen/notelore/commit/816cb3bbd9d3a50f201a8a95fef60dcd780203e0))

- Treat a non-JSON success page as an HTTPError
  ([`e45f14c`](https://github.com/mfozmen/notelore/commit/e45f14c0a1b08f842837a48afec6b876fa1d0ad4))

- Use the Briefcase template's default Android theme
  ([`9e1a4c4`](https://github.com/mfozmen/notelore/commit/9e1a4c4b9e255ff29099c3b6fc083d1f9a23ad57))

- Validate nested tool arguments, create temp notes without chmod
  ([`f10d642`](https://github.com/mfozmen/notelore/commit/f10d642a4e275fe3e4b58aa425fce99f12bcd3ae))

### Build System

- Flutter workspace with a pure-Dart core and the Flutter app, CI on three OSes
  ([`ab8078f`](https://github.com/mfozmen/notelore/commit/ab8078f5fed131167374d682227fc612e6345e6d))

- Monorepo as a uv workspace with packages/core and apps/cli
  ([`dc05da3`](https://github.com/mfozmen/notelore/commit/dc05da30d4a1ef63419631e30ecef830b7cc2f34))

### Chores

- Retire the Python packages
  ([`a7f08b6`](https://github.com/mfozmen/notelore/commit/a7f08b6698935dbf0f4ec1f3d59660efb016d42e))

### Continuous Integration

- Bump the pinned actions to their latest majors
  ([`16f2b56`](https://github.com/mfozmen/notelore/commit/16f2b56a849bb417a47e1ce2611dbb7455747812))

- Cut releases only on manual dispatch
  ([`0ce10b6`](https://github.com/mfozmen/notelore/commit/0ce10b6dcc8235914afed00d41f1c86b4cfdfa5c))

- Fail loudly when the review range git log fails, test it on a real repo
  ([`ce8af30`](https://github.com/mfozmen/notelore/commit/ce8af3082a5986b3829db7207c2a761cbb461905))

- Incremental Claude review, only commits since the last reviewed head
  ([`7a63e0a`](https://github.com/mfozmen/notelore/commit/7a63e0a863c0674294bb1e676e583be4908458fb))

- Make the release push atomic and re-runnable
  ([`f4b4309`](https://github.com/mfozmen/notelore/commit/f4b43098b09d537da92e75c98d1df5e1c83d6a7d))

- Pin every action to a commit SHA, build Dart coverage outside the Sonar job
  ([`88c5964`](https://github.com/mfozmen/notelore/commit/88c596414b139a7e1246f26cdca8a8065ee3ffa3))

- Print the app's logcat lines in the Android smoke job
  ([`2b23a5e`](https://github.com/mfozmen/notelore/commit/2b23a5ef50fc85b34ab818792572ec13777713fd))

- Push release commits with a deploy key now that main is protected
  ([`980ab38`](https://github.com/mfozmen/notelore/commit/980ab385904cdbea08d096d268d779bc6ab2fe07))

- Put the Sonar comment back above the Sonar job
  ([`266b96d`](https://github.com/mfozmen/notelore/commit/266b96de93324e0587bce2d666e9b6ce6d71a8c0))

- Resolve Dart packages before the SonarCloud scan
  ([`8e59213`](https://github.com/mfozmen/notelore/commit/8e59213c28f93774af2886fafe3039d36224b637))

- Run the Android APK on an emulator and check the core diagnostics
  ([`95ede88`](https://github.com/mfozmen/notelore/commit/95ede8813c47c43781e5e27cef06e6efa2cde137))

### Documentation

- Defer iOS until a Mac and an iOS device are available
  ([`9be599d`](https://github.com/mfozmen/notelore/commit/9be599ddf8ab144c604c427a465cb492d79761a4))

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

### Refactoring

- Split the difflib port into matching blocks and longest match
  ([`fccf717`](https://github.com/mfozmen/notelore/commit/fccf717d62a03ba46cb2b92296964dac01337313))

### Testing

- A stray line in a section does not shift stale entry numbers
  ([`3c65d7e`](https://github.com/mfozmen/notelore/commit/3c65d7e22b7b0209d5751546f51b3a2b7637fdab))

- Dates are ASCII digits in both implementations; check year 0 first
  ([`92d2e71`](https://github.com/mfozmen/notelore/commit/92d2e714487cb4a03c3c8dda52d088353fc5b8c0))

- Use itertools.pairwise for the alternation check
  ([`65f7faa`](https://github.com/mfozmen/notelore/commit/65f7faa7cb2c342eab7d374236e43bd1cf6b805c))

### Breaking Changes

- The command-line app is gone; releases carry only the app for Windows, macOS and Android. The app
  reads the same ~/Notelore.


## v0.2.0 (2026-09-30)

### Bug Fixes

- Keep the update check silent and the executable swap safe
  ([`967bc7c`](https://github.com/mfozmen/notelore/commit/967bc7c8c89cd77e0512573ba9d28b6803f81b9d))

- Tolerate a locked .old executable and drop the download on a failed swap
  ([`53a0bf4`](https://github.com/mfozmen/notelore/commit/53a0bf475b349ac7edaa3c446564896d7b100ae0))

### Features

- Daily update check and notelore update self-update
  ([`93ee126`](https://github.com/mfozmen/notelore/commit/93ee1261d3f92dc212176bdc438a0bc942457f34))

### Testing

- Enforce 100% line and branch coverage
  ([`7891139`](https://github.com/mfozmen/notelore/commit/78911397d8e25f982cc6c18448681b90b023b914))


## v0.1.0 (2026-09-30)

### Bug Fixes

- Reject non-mapping or title-less front matter with ValueError
  ([`0db9c68`](https://github.com/mfozmen/notelore/commit/0db9c68c891bfd834b25a8c6943a282d2b03e178))

### Build System

- Read the version from __init__.py only
  ([`598fdfb`](https://github.com/mfozmen/notelore/commit/598fdfb4891bd42d94ea2f2059a696e23a79da9f))

### Documentation

- Tick M0 CI green in the plan
  ([`e7f36c4`](https://github.com/mfozmen/notelore/commit/e7f36c496567244e3126e668c58e8ad9039fc5ed))

### Features

- Paths and note format parser/serializer
  ([`d382556`](https://github.com/mfozmen/notelore/commit/d382556e77e4d38d4e380dddf98c81fffc328475))


## v0.0.0 (2026-09-30)

- Initial Release
