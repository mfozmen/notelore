import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart';

void main() {
  final en = EnglishStrings();
  final tr = TurkishStrings();

  test('the language: fixed, or the device one with English as the fallback', () {
    expect(stringsFor(AppLanguage.tr, 'en').languageCode, 'tr');
    expect(stringsFor(AppLanguage.en, 'tr').languageCode, 'en');
    expect(stringsFor(AppLanguage.system, 'tr').languageCode, 'tr');
    expect(stringsFor(AppLanguage.system, 'de').languageCode, 'en');
  });

  test('every text the core produces has Turkish', () {
    final produced = [
      'Thinking',
      for (final tool in ['search_notes', 'read_note', 'add_todo', 'something_new'])
        describeTool(tool),
      '${const TurnStopped()}',
      'No answer in time, so I stopped. Please try again.',
      'The model sent no answer. Try again.',
      'I stopped after too many tool calls in a row. Please rephrase the request.',
    ];
    for (final text in produced) {
      expect(tr.core(text), isNot(text), reason: text);
      expect(en.core(text), text);
    }
    expect(tr.core('an answer from the model'), 'an answer from the model');
  });

  test('every provider and group reads in Turkish', () {
    for (final spec in providerSpecs) {
      expect(tr.cost(spec), isNot(spec.cost), reason: spec.name);
      expect(tr.keySteps(spec), hasLength(spec.keySteps.length), reason: spec.name);
      expect(tr.providerName(spec), isNotEmpty);
      expect(en.providerName(spec), spec.displayName);
      expect(en.cost(spec), spec.cost);
      expect(en.keySteps(spec), spec.keySteps);
    }
    expect(tr.providerName(findProvider('ollama')), 'Ollama (yerel)');
    for (final group in ProviderGroup.values) {
      expect(tr.groupHeading(group), isNot(group.heading));
      expect(tr.groupExplanation(group), isNot(group.explanation));
      expect(en.groupHeading(group), group.heading);
      expect(en.groupExplanation(group), group.explanation);
    }
  });

  test('the sync summary and the note kinds', () {
    expect(en.synced(0, 0, 0, 0), 'Synced; nothing changed.');
    expect(en.synced(1, 2, 3, 4), contains('1 sent, 2 received, 3 merged, 4 waiting'));
    expect(tr.synced(0, 0, 0, 0), 'Eşitlendi; değişiklik yok.');
    expect(tr.synced(1, 2, 3, 4), contains('1 gönderildi, 2 alındı, 3 birleştirildi, 4 '));
    expect(tr.noteSubtitle('project', '2026-10-11'), 'proje · güncelleme 2026-10-11');
    expect(tr.noteSubtitle('topic', 'x'), startsWith('konu'));
    expect(tr.noteSubtitle('other', 'x'), startsWith('other'));
  });

  test("OpenAI's plan wording stays as OpenAI asks in both languages", () {
    for (final s in [en, tr]) {
      expect(s.continueWithChatGpt, 'Continue with ChatGPT');
      expect(s.usingPlan, "You're using your ChatGPT plan");
      expect(s.usingChatGptPlan, 'Using ChatGPT plan');
      expect(s.manageUsage, 'Manage usage');
      expect(s.gotIt, 'Got it');
    }
  });

  test('every entry exists in both languages, and the Turkish is Turkish', () {
    Map<String, String> all(Strings s) => {
      'chat': s.chat,
      'notes': s.notes,
      'settings': s.settings,
      'cancel': s.cancel,
      'delete': s.delete,
      'connect': s.connect,
      'openFailed': s.openFailed('x'),
      'chooseProvider': s.chooseProvider,
      'apiKey': s.apiKey,
      'pasteKeyFirst': s.pasteKeyFirst,
      'checkConnection': s.checkConnection,
      'ollamaNoKey': s.ollamaNoKey,
      'planWelcome': s.planWelcome,
      'askSomething': s.askSomething,
      'message': s.message,
      'send': s.send,
      'stop': s.stop,
      'changeTheModel': s.changeTheModel,
      'changeModel': s.changeModel,
      'modelGone': s.modelGone('P', 'm'),
      'thinking': s.thinking('x', 3),
      'talk': s.talk,
      'stopReading': s.stopReading,
      'holdHint': s.holdHint,
      'listening': s.listening,
      'speaking': s.speaking,
      'voiceUnavailable': s.voiceUnavailable,
      'speechFailed': s.speechFailed('error_network'),
      'refresh': s.refresh,
      'noNotes': s.noNotes,
      'deleteQuestion': s.deleteQuestion('t'),
      'deleteExplained': s.deleteExplained,
      'alreadyGone': s.alreadyGone('t'),
      'movedToArchive': s.movedToArchive('t'),
      'undo': s.undo,
      'provider': s.provider,
      'refreshModels': s.refreshModels,
      'modelSaved': s.modelSaved,
      'notesFolder': s.notesFolder,
      'checkForUpdates': s.checkForUpdates,
      'logOut': s.logOut,
      'logOutExplained': s.logOutExplained,
      'language': s.language,
      'system': s.languageName(AppLanguage.system),
      'driveNotSetUp': s.driveNotSetUp,
      'driveExplained': s.driveExplained,
      'syncing': s.syncing,
      'connected': s.connected,
      'syncNow': s.syncNow,
      'disconnectDrive': s.disconnectDrive,
      'upToDate': s.upToDate,
      'updateAvailable': s.updateAvailable('1'),
      'installing': s.installing('1'),
      'installed': s.installed('1'),
      'checkFailed': s.checkFailed('x'),
      'setupFailed': s.setupFailed('x'),
      'later': s.later,
      'updateAndRestart': s.updateAndRestart,
      'update': s.update,
      'allowInstalls': s.allowInstalls,
      'offline': s.offline,
      'signInAgain': s.signInAgain('x'),
      'noteInUse': s.noteInUse('x'),
      'theme': s.theme,
      'devBuild': s.versionLine(''),
      'archive': s.archive,
      'pickNote': s.pickNote,
      'entriesFrom': s.entriesFrom('t'),
      'archiveEmpty': s.archiveEmpty,
      'archivedOn': s.archivedOn('2026-10-12'),
      'restore': s.restore,
      'restored': s.restored('t'),
      'restoreTaken': s.restoreTaken('t'),
      'webSearch': s.webSearch,
      'webSearchExplained': s.webSearchExplained,
      'webSearchBilled': s.webSearchBilled,
      'webSearchUnavailable': s.webSearchUnavailable,
      'appearance': s.appearance,
      'voiceSection': s.voiceSection,
      'syncSection': s.syncSection,
      'aboutSection': s.aboutSection,
      'whisper': s.whisper,
      'whisperExplained': s.whisperExplained,
      'tryAgain': s.tryAgain,
      'whisperDownloading': s.whisperDownloading(42),
      'whisperFailed': s.whisperFailed('x'),
      'microphone': s.microphone,
      'systemMicrophone': s.systemMicrophone,
      'listMicrophones': s.listMicrophones,
      for (final palette in Palette.values) palette.name: s.paletteName(palette),
      for (final a in Appearance.values) 'appearance-${a.name}': s.appearanceName(a),
    };
    final english = all(en);
    final turkish = all(tr);
    for (final key in english.keys) {
      expect(english[key], isNotEmpty, reason: key);
      expect(turkish[key], isNot(english[key]), reason: key);
    }
    // Names stay names.
    for (final s in [en, tr]) {
      expect(s.model, 'Model');
      expect(s.drive, 'Google Drive');
      expect(s.driveError('x'), 'Google Drive: x');
      expect(s.languageName(AppLanguage.en), 'English');
      expect(s.languageName(AppLanguage.tr), 'Türkçe');
    }
  });
}
