import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore/src/transfer.dart';
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
      // The Choose step's card (#358): five lines, told in each language.
      for (final line in <String Function(Strings)>[
        (s) => s.optionCost(spec),
        (s) => s.optionPrivacy(spec),
        (s) => s.optionQuality(spec),
        (s) => s.optionEffort(spec),
        (s) => s.optionFit(spec),
      ]) {
        expect(line(en), isNotEmpty, reason: spec.name);
        expect(line(tr), isNot(line(en)), reason: spec.name);
      }
    }
    expect(tr.providerName(findProvider('ollama')), 'Ollama (yerel)');
    for (final group in ProviderGroup.values) {
      expect(tr.groupHeading(group), isNot(group.heading));
      expect(en.groupHeading(group), group.heading);
    }
  });

  test('a failed turn is said kindly, never as raw HTTP (#306)', () {
    for (final s in [EnglishStrings(), TurkishStrings()]) {
      final said = {
        for (final error in <Exception>[
          const NetworkError('socket closed'),
          const HttpError(401, 'invalid x-api-key'),
          const HttpError(403, 'forbidden'),
          const HttpError(429, 'rate_limit_error'),
          const HttpError(503, 'overloaded'),
        ])
          s.chatError(error),
      };
      expect(said, hasLength(4), reason: s.languageCode); // 401 and 403 share one: the key
      for (final text in said) {
        expect(text, isNot(matches(RegExp('HTTP|socket|x-api-key|rate_limit|overloaded'))));
      }
      // Other refusals keep their detail, kindly framed; the core's own messages
      // (a Stop, the plan's limit) stay as they are.
      expect(s.chatError(const HttpError(400, 'image too large')), contains('image too large'));
      expect(s.chatError(const TurnStopped()), s.core('Stopped.'));
    }
  });

  test('plenty of waiting lines in both languages, each its own', () {
    for (final s in [en, tr]) {
      expect(s.waitingLines.length, greaterThanOrEqualTo(15));
      expect(s.waitingLines.toSet(), hasLength(s.waitingLines.length));
    }
    expect(tr.waitingLines.first, isNot(en.waitingLines.first));
  });

  test('the sync summary and the note kinds', () {
    expect(en.synced(0, 0, 0, 0), 'Synced; nothing changed.');
    expect(en.synced(1, 2, 3, 4), contains('1 sent, 2 received, 3 merged, 4 waiting'));
    expect(en.lockWaiting(const Duration(minutes: 5)), 'Too many tries. Try again in 5:00.');
    expect(
      tr.lockWaiting(const Duration(seconds: 30)),
      'Çok fazla deneme. 0:30 sonra tekrar dene.',
    );
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
      'stepOf': s.stepOf(1, 3),
      'connectedTo': s.connectedTo('x'),
      'connectedExplained': s.connectedExplained,
      'start': s.start,
      'connectedModels': s.connectedModels,
      'connectAnother': s.connectAnother,
      'remove': s.remove,
      'removeModel': s.removeModel('x'),
      'removeModelWhy': s.removeModelWhy,
      'nowUsing': s.nowUsing('x'),
      'chooseProviderWhy': s.chooseProviderWhy,
      'openKeyPage': s.openKeyPage('example.com'),
      'connectedBadge': s.connectedBadge,
      'apiKey': s.apiKey,
      'pasteKeyFirst': s.pasteKeyFirst,
      'checkConnection': s.checkConnection,
      'ollamaNoKey': s.ollamaNoKey,
      'planWelcome': s.planWelcome,
      'askSomething': s.askSomething,
      'message': s.message,
      'send': s.send,
      'resend': s.resend,
      'copy': s.copy,
      'copied': s.copied,
      'attachFile': s.attachFile,
      'notText': s.notText('x'),
      'tooLarge': s.tooLarge('x'),
      'noPdfText': s.noPdfText('x'),
      'noImages': s.noImages('x'),
      'imagesNotNow': s.imagesNotNow,
      'imagesCannotWait': s.imagesCannotWait,
      'attachedFile': s.attachedFile('x'),
      'attachedImage': s.attachedImage('x'),
      'appLock': s.appLock,
      'appLockOn': s.appLockOn,
      'appLockOff': s.appLockOff,
      'turnOn': s.turnOn,
      'turnOff': s.turnOff,
      'lockSecret': s.lockSecret,
      'lockRepeat': s.lockRepeat,
      'lockTooShort': s.lockTooShort,
      'lockMismatch': s.lockMismatch,
      'lockedTitle': s.lockedTitle,
      'lockedHint': s.lockedHint,
      'unlock': s.unlock,
      'wrongSecret': s.wrongSecret,
      'export': s.export,
      'exportNotes': s.exportNotes,
      'importNotes': s.importNotes,
      'exportAs': s.exportAs,
      for (final f in ExportFormat.values)
        if (f != ExportFormat.pdf) 'format-${f.name}': s.formatName(f),
      'chooseNotes': s.chooseNotes,
      'next': s.next,
      'exported': s.exported(2),
      'exportFailed': s.exportFailed('x'),
      'importedAdded': s.importedAdded('T'),
      'importedRenamed': s.importedRenamed('T'),
      'importedSame': s.importedSame('T'),
      'importRefused': s.importRefused('f'),
      'lockWaiting': s.lockWaiting(const Duration(minutes: 1, seconds: 5)),
      'notesMayBeSaved': s.notesMayBeSaved,
      'stop': s.stop,
      'changeTheModel': s.changeTheModel,
      'changeModel': s.changeModel,
      'modelGone': s.modelGone('P', 'm'),
      'talk': s.talk,
      'stopReading': s.stopReading,
      'waitingToSend': s.waitingToSend,
      'tryNow': s.tryNow,
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
      'refreshModels': s.refreshModels,
      'modelSaved': s.modelSaved,
      'checkForUpdates': s.checkForUpdates,
      'logOut': s.logOut,
      'logOutExplained': s.logOutExplained,
      'language': s.language,
      'system': s.languageName(AppLanguage.system),
      'driveNotSetUp': s.driveNotSetUp,
      'driveExplained': s.driveExplained,
      'signInWithGoogle': s.signInWithGoogle,
      'welcomeTitle': s.welcomeTitle,
      'welcomePromise': s.welcomePromise,
      'welcomeDrive': s.welcomeDrive,
      'welcomePrivate': s.welcomePrivate,
      'welcomeAccount': s.welcomeAccount,
      'signingIn': s.signingIn,
      'googleRequired': s.googleRequired,
      'signInUnfinished': s.signInUnfinished,
      'working': s.working,
      'noChatGptPlan': s.noChatGptPlan,
      'noChatGptPlanWhy': s.noChatGptPlanWhy,
      'freeGemini': s.freeGemini,
      'freeGeminiPrivacy': s.freeGeminiPrivacy,
      'getFreeGeminiKey': s.getFreeGeminiKey,
      'keyFromClipboard': s.keyFromClipboard,
      'cannotReach': s.cannotReach,
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

  test('usage: tokens grouped, the cost an estimate, missing data said so (#217)', () {
    const none = UsageSummary(UsageCount(), cost: 0, plan: false);
    expect(en.usageLines(none), ['Nothing yet.']);
    const known = UsageSummary(
      UsageCount(calls: 3, input: 1234567, output: 8900),
      cost: 2.5,
      plan: false,
    );
    expect(en.usageLines(known), [
      'Tokens: 1,234,567 in, 8,900 out',
      'Estimated cost: about \$2.50',
    ]);
    expect(tr.usageLines(known), [
      'Token: 1.234.567 giriş, 8.900 çıkış',
      'Tahmini maliyet: yaklaşık \$2,50',
    ]);
    const small = UsageSummary(
      UsageCount(calls: 1, input: 10, output: 1),
      cost: 0.00042,
      plan: false,
    );
    expect(en.usageLines(small).last, 'Estimated cost: about \$0.0004');
    const gaps = UsageSummary(
      UsageCount(calls: 3, unreported: 1, input: 5, output: 1),
      cost: null,
      plan: false,
    );
    expect(en.usageLines(gaps), [
      'Tokens: 5 in, 1 out',
      '1 model call did not report usage',
      'Estimated cost: not available',
    ]);
    const blank = UsageSummary(UsageCount(calls: 2, unreported: 2), cost: null, plan: false);
    expect(en.usageLines(blank), [
      'Tokens: not available',
      '2 model calls did not report usage',
      'Estimated cost: not available',
    ]);
    expect(tr.usageLines(blank), [
      'Token: bilgi yok',
      '2 model çağrısı kullanım bildirmedi',
      'Tahmini maliyet: bilgi yok',
    ]);
    expect(tr.usageLines(none), ['Henüz yok.']);
    for (final s in [en, tr]) {
      expect([
        s.usage,
        s.usageConversation,
        s.usageDevice,
        s.usagePlan,
        s.usageLocal,
      ], everyElement(isNotEmpty));
      expect(s.usageEstimate('2026-10-17'), contains('2026-10-17'));
    }
  });
}
