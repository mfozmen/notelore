/// The catalog's made-up world: a session on temp folders with invented notes,
/// a short conversation and a model that answers from a script. It never
/// reads or writes the real notes, keys or settings, and never goes online.
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

/// The day every fake note and screen is dated from, so renders never drift.
final fakeToday = DateTime.utc(2026, 9, 30);

/// Answers in order, then says it is ready.
class ScriptedModel implements LlmProvider {
  ScriptedModel(this.answers);

  final List<String> answers;

  @override
  String get model => 'claude-sonnet-5-5';

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async =>
      AgentResponse([
        {'type': 'text', 'text': answers.isEmpty ? 'Ready.' : answers.removeAt(0)},
      ], 'end_turn');
}

const _notes = {
  'projects/garden-shed.md': '''
---
title: Garden Shed
kind: project
created: 2026-09-02
updated: 2026-09-28
tags: [home, diy]
---
# Garden Shed

## Decisions
- ~~2026-09-05 — **roof**: Cedar shingles.~~ _(superseded 2026-09-26)_
- 2026-09-26 — **roof**: Corrugated metal. Cheaper, and it outlasts shingles.
- 2026-09-10 — **floor**: Treated pine on concrete blocks.

## Notes
- 2026-09-02: The shed goes behind the apple tree, 2.4 by 1.8 metres.
- 2026-09-18: The neighbour lends his circular saw on weekends.

## Todo
- [ ] 2026-10-02: Order the stainless screws
- [ ] 2026-10-10: Paint the door sage green
- [x] 2026-09-20: Level the ground

## Reminders
- 2026-10-03 10:00: Timber delivery, keep the gate open
''',
  'projects/lisbon-trip.md': '''
---
title: Lisbon Trip
kind: project
created: 2026-09-14
updated: 2026-09-29
tags: [travel]
---
# Lisbon Trip

## Decisions
- 2026-09-14 — **dates**: 12 to 18 October.
- 2026-09-21 — **stay**: A flat in Alfama with a terrace.

## Notes
- 2026-09-29: Tram 28 is crowded before ten; walk up to the castle instead.

## Todo
- [ ] 2026-10-08: Print the boarding passes
''',
  'topics/reading-list.md': '''
---
title: Reading List
kind: topic
created: 2026-08-20
updated: 2026-09-25
tags: [books]
---
# Reading List

## Notes
- 2026-08-20: Start with a short novel, then the history of maps.
- 2026-09-25: Finished the novel; the ending was quiet and right.
''',
  'topics/passport-renewal.md': '''
---
title: Passport Renewal
kind: topic
created: 2026-09-01
updated: 2026-09-19
tags: []
---
# Passport Renewal

## Notes
- 2026-09-01: The old passport expires in December.

## Reminders
- 2026-10-07 09:30: Passport office, bring two photos
''',
  'about-me.md': '''
# About me

## Work
- Works as a landscape architect, mostly on school yards.

## Home
- Lives in a terraced house with a narrow garden.

## Family
- Has a sister who lives in Porto.

## Other
- Prefers short answers.
''',
};

/// The conversation the chat shows: each question with its scripted answer.
const fakeChat = [
  (
    'Which roof did we pick for the shed?',
    '**Corrugated metal**, since 26 September: cheaper than cedar shingles, and it lasts longer.',
  ),
  (
    'Remind me to order the screws on Friday',
    'Done. You will hear about it on **Friday 2 October**: order the stainless screws.',
  ),
];

/// The catalog's one folder, emptied at start so runs leave no pile behind.
/// While another catalog holds it open, Windows refuses the delete, so this
/// one gets a folder of its own.
Directory _catalogFolder() {
  final dir = Directory(p.join(Directory.systemTemp.path, 'notelore_catalog'));
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    return dir;
  } on FileSystemException {
    return Directory.systemTemp.createTempSync('notelore_catalog_');
  }
}

/// A ready session on [root] (the catalog's temp folder when null): connected
/// to the scripted model, with the fake notes on disk and, when [chat], the
/// fake conversation already in the chat.
Future<Session> fakeSession({Directory? root, bool chat = true}) async {
  final dir = root ?? _catalogFolder();
  for (final MapEntry(:key, :value) in _notes.entries) {
    File(p.join(dir.path, 'notes', key))
      ..createSync(recursive: true)
      ..writeAsStringSync(value.trimLeft());
  }
  // An in-memory keystore: the catalog's fake key never reaches the real one.
  // ignore: invalid_use_of_visible_for_testing_member
  FlutterSecureStorage.setMockInitialValues({});
  final scripted = ScriptedModel([for (final (_, answer) in fakeChat) answer]);
  final session = Session(
    NotelorePaths(
      notes: Directory(p.join(dir.path, 'notes')),
      state: Directory(p.join(dir.path, 'state')),
    ),
    today: fakeToday,
    clock: () => fakeToday.add(const Duration(hours: 9)),
    keySpace: 'notelore-catalog',
    validate: (spec, key) async => [scripted.model],
    makeProvider: (spec, key, {model, planToken, webSearch = false}) => scripted,
    httpClient: () => MockClient((_) async => http.Response('', 404)),
    resolve: (_) async => [InternetAddress.loopbackIPv4],
    listMicrophones: () async => const [],
    localModels: false,
    offThread: <R>(work) async => work(),
  );
  await session.load();
  await session.connect(providerSpecs.firstWhere((s) => s.id == ProviderId.anthropic), 'fake');
  if (chat) {
    for (final (question, _) in fakeChat) {
      await session.send(question);
    }
  }
  return session;
}
