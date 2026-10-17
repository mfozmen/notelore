/// The app's words, in English and Turkish. Both languages implement
/// [Strings], so a missing entry does not compile. Texts the core produces
/// (agent steps, a stopped turn) arrive in English and go through [core].
/// OpenAI's required wording for the ChatGPT plan stays English in both.
library;

import 'package:notelore_core/notelore_core.dart';

import 'theme.dart';
import 'transfer.dart' show ExportFormat;

/// The language the app speaks: the device's, or a fixed one.
enum AppLanguage { system, en, tr }

abstract class Strings {
  String get languageCode;

  // Navigation and general.
  String get chat;
  String get notes;
  String get settings;
  String get cancel;
  String get delete;
  String get connect;
  String openFailed(Object error);

  // Setup.
  String get chooseProvider;

  /// Setup's API-key and local providers, under the one-tap plan (#206).
  String get advanced;

  /// A phone has no local models: no word of a computer there (#304).
  String advancedExplained({required bool localModels});
  String get apiKey;
  String get pasteKeyFirst;
  String get checkConnection;
  String get ollamaNoKey;
  String providerName(ProviderSpec spec);
  String groupHeading(ProviderGroup group);
  String groupExplanation(ProviderGroup group);
  String cost(ProviderSpec spec);
  List<String> keySteps(ProviderSpec spec);

  // ChatGPT plan (OpenAI's wording where it asks for it).
  String get continueWithChatGpt => 'Continue with ChatGPT';

  /// A sign-in that failed, in plain words: never a raw code or HTTP body (#302).
  String signInProblem(Object error) =>
      error is NetworkError ? '$cannotReach $checkConnection' : signInUnfinished;
  String get signInUnfinished;
  String get cannotReach;
  String get usingPlan => "You're using your ChatGPT plan";
  String get planWelcome;
  String get gotIt => 'Got it';
  String get usingChatGptPlan => 'Using ChatGPT plan';
  String get manageUsage => 'Manage usage';

  // Chat.
  String get askSomething;
  String get message;
  String get send;
  String get resend;
  String get copy;
  String get copied;

  /// Text files attached in the chat (#222).
  String get attachFile;
  String notText(String name);
  String tooLarge(String name);
  String noPdfText(String name);
  String noImages(String provider);
  String get imagesNotNow;
  String get imagesCannotWait;

  /// A file or an image sent with a message, for screen readers.
  String attachedFile(String name);
  String attachedImage(String name);

  /// The app lock (#224): Settings, its dialogs and the screen at start.
  String get appLock;
  String get appLockOn;
  String get appLockOff;
  String get turnOn;
  String get turnOff;
  String get lockSecret;
  String get lockRepeat;
  String get lockTooShort;
  String get lockMismatch;
  String get lockedTitle;
  String get lockedHint;
  String get unlock;
  String get wrongSecret;
  String lockWaiting(Duration wait);

  /// After an error, when the failed turn had already changed the notes.
  String get notesMayBeSaved;
  String get stop;
  String get changeTheModel;
  String get changeModel;
  String modelGone(String provider, String model);

  /// Shown in rotation while a chat turn runs, instead of a plain "Thinking".
  List<String> get waitingLines;
  String get talk;
  String get stopReading;
  String get waitingToSend;
  String get tryNow;
  String get holdHint;
  String get listening;
  String get speaking;
  String get voiceUnavailable;
  String speechFailed(String code);

  // Notes.
  String get refresh;
  String get noNotes;
  String deleteQuestion(String title);
  String get deleteExplained;
  String alreadyGone(String title);
  String movedToArchive(String title);

  /// Export, share and import (#215).
  String get export;
  String get exportNotes;
  String get importNotes;
  String get exportAs;
  String formatName(ExportFormat format);
  String get chooseNotes;
  String get next;
  String exported(int count);
  String exportFailed(String why);
  String importedAdded(String title);
  String importedRenamed(String title);
  String importedSame(String title);
  String importRefused(String file);
  String get undo;
  String noteSubtitle(String kind, String updated);

  // Settings.
  String get provider;
  String get model;
  String get refreshModels;
  String get modelSaved;
  String get checkForUpdates;
  String get logOut;
  String get logOutExplained;
  String get language;
  String languageName(AppLanguage language);
  String get theme;

  /// The app and its version; a development build has none.
  String versionLine(String version);

  // Usage (#217).
  String get usage;
  String get usageConversation;
  String get usageDevice;
  String get usageNothing;
  String usageTokens(String input, String output);
  String get usageTokensUnavailable;
  String usageUnreported(int calls);
  String usageCost(String dollars);
  String get usageCostUnavailable;
  String usageEstimate(String date);
  String get usagePlan;
  String get usageLocal;
  String get thousands;
  String get decimalPoint;

  /// What [summary] used: tokens, the calls that did not say, the estimated
  /// cost; "not available" where the provider gave nothing to go on.
  List<String> usageLines(UsageSummary summary) {
    if (summary.calls == 0) return [usageNothing];
    String grouped(int n) => '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => thousands);
    return [
      if (summary.tokensKnown)
        usageTokens(grouped(summary.input), grouped(summary.output))
      else
        usageTokensUnavailable,
      if (summary.unreported > 0) usageUnreported(summary.unreported),
      switch (summary.cost) {
        null => usageCostUnavailable,
        final cost => usageCost(
          cost.toStringAsFixed(cost == 0 || cost >= 0.01 ? 2 : 4).replaceFirst('.', decimalPoint),
        ),
      },
    ];
  }

  String get archive;
  String get pickNote;

  /// An archived note's name; archived entries say whose they are.
  String archivedTitle(ArchivedNote archived) =>
      archived.entries ? entriesFrom(archived.title) : archived.title;
  String entriesFrom(String title);
  String get archiveEmpty;
  String archivedOn(String date);
  String get restore;
  String restored(String title);
  String restoreTaken(String title);
  String get webSearch;
  String get webSearchExplained;
  String get webSearchBilled;
  String get webSearchUnavailable;
  String get whisper;
  String get tryAgain;
  String whisperDownloading(int percent);
  String whisperFailed(String why);
  String get microphone;
  String get systemMicrophone;
  String get listMicrophones;
  String paletteName(Palette palette);
  String get appearance;
  String get voiceSection;
  String get syncSection;
  String get aboutSection;
  String appearanceName(Appearance appearance);
  String get drive;
  String get driveNotSetUp;
  String get driveExplained;

  /// Google sign-in, the first step of setup (#208).
  String get signInWithGoogle;
  String get googleExplained;
  String get googleRequired;
  String get syncing;
  String get connected;
  String get syncNow;
  String get disconnectDrive;

  // Updates.
  String get upToDate;
  String updateAvailable(String version);
  String installing(String version);
  String installed(String version);
  String checkFailed(Object error);
  String setupFailed(Object error);
  String get later;
  String get updateAndRestart;
  String get update;
  String get allowInstalls;

  // Sync status.
  String get offline;
  String driveError(String message);
  String signInAgain(String message);
  String noteInUse(String message);
  String synced(int sent, int received, int merged, int waiting);

  /// A text the core produced in English, in this language.
  String core(String english);
}

class EnglishStrings extends Strings {
  @override
  String get languageCode => 'en';
  @override
  String get chat => 'Chat';
  @override
  String get notes => 'Notes';
  @override
  String get settings => 'Settings';
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get connect => 'Connect';
  @override
  String openFailed(Object error) => 'Notelore could not open its folders.\n\n$error';

  @override
  String get chooseProvider => 'Choose a model provider';
  @override
  String get advanced => 'Advanced';
  @override
  String advancedExplained({required bool localModels}) =>
      localModels ? 'Your own API key, or a model on this computer.' : 'Use your own API key.';
  @override
  String get apiKey => 'API key';
  @override
  String get pasteKeyFirst => 'Paste the key first.';
  @override
  String get checkConnection => 'Check the connection and try again.';
  @override
  String get signInUnfinished => 'Sign-in did not finish. Please try again.';
  @override
  String get cannotReach => 'Could not reach the service.';
  @override
  String get ollamaNoKey => 'Ollama runs on this computer; no key is needed.';
  @override
  String providerName(ProviderSpec spec) => spec.displayName;
  @override
  String groupHeading(ProviderGroup group) => group.heading;
  @override
  String groupExplanation(ProviderGroup group) => group.explanation;
  @override
  String cost(ProviderSpec spec) => spec.cost;
  @override
  List<String> keySteps(ProviderSpec spec) => spec.keySteps;

  @override
  String get planWelcome =>
      "Notelore's answers count against your ChatGPT Plus or Pro plan, with no separate "
      'charges. You can see and manage that usage in ChatGPT.';

  @override
  String get askSomething => 'Ask or tell me something.';
  @override
  String get message => 'Message';
  @override
  String get send => 'Send';
  @override
  String get resend => 'Resend';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get attachFile => 'Attach a file';
  @override
  String attachedFile(String name) => 'File: $name';
  @override
  String attachedImage(String name) => 'Image: $name';
  @override
  String notText(String name) =>
      'Notelore reads text files, PDFs (txt, md, csv, pdf and the like) and images (PNG, '
      'JPEG, GIF, WebP) for now; $name is none of them.';
  @override
  String noPdfText(String name) =>
      "$name has no text to read (a scan, or a damaged file); Notelore reads only a PDF's text.";
  @override
  String tooLarge(String name) => '$name is too large to send; split it into smaller files.';
  @override
  String noImages(String provider) => '$provider cannot look at images; text files still work.';
  @override
  String get imagesNotNow => 'Images go when nothing else is on its way; try again in a moment.';
  @override
  String get imagesCannotWait =>
      'Images cannot wait to be sent later: send the message again when you are back online.';
  @override
  String get appLock => 'App lock';
  @override
  String get appLockOn => 'On: Notelore asks for your PIN or password when it opens.';
  @override
  String get appLockOff => 'Off: Notelore opens without asking.';
  @override
  String get turnOn => 'Turn on';
  @override
  String get turnOff => 'Turn off';
  @override
  String get lockSecret => 'PIN or password';
  @override
  String get lockRepeat => 'Repeat it';
  @override
  String get lockTooShort => 'At least 4 characters.';
  @override
  String get lockMismatch => "They don't match.";
  @override
  String get lockedTitle => 'Notelore is locked';
  @override
  String get lockedHint =>
      'Forgot it? Your notes are safe: they stay as files in the notes folder and on Drive.';
  @override
  String get unlock => 'Unlock';
  @override
  String get wrongSecret => "That's not it. Try again.";
  @override
  String lockWaiting(Duration wait) => 'Too many tries. Try again in ${_minutes(wait)}.';
  @override
  String get notesMayBeSaved =>
      'Some notes may already have been saved before this failed. Check them before you '
      'resend, so nothing is saved twice.';
  @override
  String get stop => 'Stop';
  @override
  String get changeTheModel => 'Change the model';
  @override
  String get changeModel => 'Change model';
  @override
  String modelGone(String provider, String model) =>
      '$provider no longer offers $model. Pick another model.';
  @override
  List<String> get waitingLines => const [
    'Went to make coffee, back in a sec.',
    'Waiting for the muse to call back.',
    'Sharpening a pencil…',
    'Rummaging through your notes.',
    'Warming up the brain cells.',
    'Untangling a ball of thoughts.',
    'Asking the rubber duck.',
    'Polishing the commas.',
    'Browsing the shelves, aisle by aisle.',
    'Counting to ten, slowly.',
    'Dusting off the memory palace.',
    'Weighing every word.',
    'Brewing a fresh pot of ideas.',
    'Looking for its reading glasses.',
    'Herding stray thoughts.',
    'Consulting the oracle (it is on a break).',
    'Flipping through the index cards.',
    'Making its thinking face.',
    'Tying its shoelaces first.',
    'Feeding the hamster on the wheel.',
  ];
  @override
  String get talk => 'Hold to talk';
  @override
  String get stopReading => 'Stop reading aloud';
  @override
  String get waitingToSend => 'Waiting to send';
  @override
  String get tryNow => 'Try now';
  @override
  String get holdHint => 'Hold the button while you talk.';
  @override
  String get listening => 'Listening…';
  @override
  String get speaking => 'Speaking…';
  @override
  String speechFailed(String code) => 'Speech recognition failed ($code); back to typing.';
  @override
  String get voiceUnavailable =>
      'Speech recognition is not available. Allow the microphone; on Windows, add the '
      "speech pack for the app's language (Settings, Time & language, Speech).";

  @override
  String get refresh => 'Refresh';
  @override
  String get noNotes => 'No notes yet. Tell the assistant something to remember.';
  @override
  String deleteQuestion(String title) => 'Delete "$title"?';
  @override
  String get deleteExplained =>
      'It moves to the archive; you can bring it back from _archive/ in the notes folder.';
  @override
  String alreadyGone(String title) => '"$title" was already gone.';
  @override
  String movedToArchive(String title) => 'Moved "$title" to the archive.';
  @override
  String get export => 'Export';
  @override
  String get exportNotes => 'Export notes';
  @override
  String get importNotes => 'Import notes';
  @override
  String get exportAs => 'Export as';
  @override
  String formatName(ExportFormat format) => switch (format) {
    ExportFormat.markdown => 'Markdown (can be imported again)',
    ExportFormat.pdf => 'PDF',
    ExportFormat.html => 'Web page (HTML)',
  };
  @override
  String get chooseNotes => 'Which notes?';
  @override
  String get next => 'Next';
  @override
  String exported(int count) => 'Exported $count ${count == 1 ? 'note' : 'notes'}.';
  @override
  String exportFailed(String why) => 'The export failed: $why';
  @override
  String importedAdded(String title) => 'Imported "$title".';
  @override
  String importedRenamed(String title) =>
      'Imported as "$title": a different note already had the name.';
  @override
  String importedSame(String title) => '"$title" is already here, unchanged.';
  @override
  String importRefused(String file) => '"$file" is not a Notelore note.';
  @override
  String get undo => 'Undo';
  @override
  String noteSubtitle(String kind, String updated) => '$kind · updated $updated';

  @override
  String get provider => 'Provider';
  @override
  String get model => 'Model';
  @override
  String get refreshModels => 'Refresh the model list';
  @override
  String get modelSaved => 'Model saved.';
  @override
  String get checkForUpdates => 'Check for updates';
  @override
  String get logOut => 'Log out';
  @override
  String get logOutExplained => 'Logging out forgets the API key on this device. Your notes stay.';
  @override
  String get language => 'Language';
  @override
  String languageName(AppLanguage language) => switch (language) {
    AppLanguage.system => 'System',
    AppLanguage.en => 'English',
    AppLanguage.tr => 'Türkçe',
  };
  @override
  String get theme => 'Theme';
  @override
  String versionLine(String version) =>
      version.isEmpty ? 'Notelore · development build' : 'Notelore $version';
  @override
  String get usage => 'Usage';
  @override
  String get usageConversation => 'This conversation';
  @override
  String get usageDevice => 'On this device';
  @override
  String get usageNothing => 'Nothing yet.';
  @override
  String usageTokens(String input, String output) => 'Tokens: $input in, $output out';
  @override
  String get usageTokensUnavailable => 'Tokens: not available';
  @override
  String usageUnreported(int calls) =>
      '$calls model ${calls == 1 ? 'call' : 'calls'} did not report usage';
  @override
  String usageCost(String dollars) => 'Estimated cost: about \$$dollars';
  @override
  String get usageCostUnavailable => 'Estimated cost: not available';
  @override
  String usageEstimate(String date) =>
      "Costs are estimates from list prices taken on $date; your provider's bill is what counts.";
  @override
  String get usagePlan =>
      "The ChatGPT plan has no per-token charge: use counts against your plan's limits.";
  @override
  String get usageLocal => 'A local model has no per-token charge.';
  @override
  String get thousands => ',';
  @override
  String get decimalPoint => '.';
  @override
  String get archive => 'Archive';
  @override
  String get pickNote => 'Pick a note to read it here.';
  @override
  String entriesFrom(String title) => 'Entries from $title';
  @override
  String get archiveEmpty => 'The archive is empty. Deleted notes go here.';
  @override
  String archivedOn(String date) => 'archived $date';
  @override
  String get restore => 'Restore';
  @override
  String restored(String title) => 'Restored "$title".';
  @override
  String restoreTaken(String title) =>
      'A note called "$title" already exists, so this one stays in the archive.';
  @override
  String get webSearch => 'Look things up on the web';
  @override
  String get webSearchExplained =>
      'Only when it helps get a note right, like the author of a book you mention.';
  @override
  String get webSearchBilled =>
      'Only when it helps get a note right. Anthropic bills each search on top of the tokens.';
  @override
  String get webSearchUnavailable => 'Not available with this provider.';
  @override
  String get whisper => 'Whisper speech recognition';
  @override
  String get tryAgain => 'Try again';
  @override
  String whisperDownloading(int percent) => 'Downloading… $percent%';
  @override
  String whisperFailed(String why) => 'The download failed: $why';
  @override
  String get microphone => 'Microphone';
  @override
  String get systemMicrophone => 'System default';
  @override
  String get listMicrophones => 'List the microphones again';
  @override
  String paletteName(Palette palette) => switch (palette) {
    Palette.lagoon => 'Lagoon',
    Palette.forest => 'Pine forest',
    Palette.sea => 'Open sea',
    Palette.sunset => 'Sunset',
    Palette.lavender => 'Lavender field',
    Palette.aurora => 'Northern lights',
  };
  @override
  String get appearance => 'Appearance';
  @override
  String get voiceSection => 'Voice';
  @override
  String get syncSection => 'Sync';
  @override
  String get aboutSection => 'About';
  @override
  String appearanceName(Appearance appearance) => switch (appearance) {
    Appearance.system => 'System',
    Appearance.light => 'Light',
    Appearance.dark => 'Dark',
  };
  @override
  String get drive => 'Google Drive';
  @override
  String get driveNotSetUp => 'Sync is not set up in this build.';
  @override
  String get driveExplained => 'Back up and sync your notes across your devices.';
  @override
  String get signInWithGoogle => 'Sign in with Google';
  @override
  String get googleExplained =>
      'Notelore keeps your notes in your own Google Drive, so all your devices have them. '
      'Sign in with your Google (Gmail) account to start. Notelore can only see the files it '
      'creates there.';
  @override
  String get googleRequired => 'Notelore needs a Google account to continue. Sign in to go on.';
  @override
  String get syncing => 'Syncing...';
  @override
  String get connected => 'Connected.';
  @override
  String get syncNow => 'Sync now';
  @override
  String get disconnectDrive => 'Disconnect Google Drive';

  @override
  String get upToDate => 'Notelore is up to date.';
  @override
  String updateAvailable(String version) => 'Notelore $version is available.';
  @override
  String installing(String version) => 'Installing Notelore $version...';
  @override
  String installed(String version) =>
      'Notelore $version is installed. Close and reopen Notelore to use it.';
  @override
  String checkFailed(Object error) => 'Could not check for updates: $error';
  @override
  String setupFailed(Object error) => 'The setup could not start: $error';
  @override
  String get later => 'Later';
  @override
  String get updateAndRestart => 'Update and restart';
  @override
  String get update => 'Update';
  @override
  String get allowInstalls =>
      'Allow Notelore to install apps in the setting that just opened, then tap Update again.';

  @override
  String get offline => 'Offline; your notes will sync when the connection is back.';
  @override
  String driveError(String message) => 'Google Drive: $message';
  @override
  String signInAgain(String message) => '$message; connect again.';
  @override
  String noteInUse(String message) =>
      'A note is in use by another program ($message); the next sync retries.';
  @override
  String synced(int sent, int received, int merged, int waiting) {
    final parts = [
      if (sent > 0) '$sent sent',
      if (received > 0) '$received received',
      if (merged > 0) '$merged merged',
      if (waiting > 0) '$waiting waiting for a conflict to be settled',
    ];
    return parts.isEmpty ? 'Synced; nothing changed.' : 'Synced: ${parts.join(', ')}.';
  }

  @override
  String core(String english) => english;
}

class TurkishStrings extends Strings {
  @override
  String get languageCode => 'tr';
  @override
  String get chat => 'Sohbet';
  @override
  String get notes => 'Notlar';
  @override
  String get settings => 'Ayarlar';
  @override
  String get cancel => 'Vazgeç';
  @override
  String get delete => 'Sil';
  @override
  String get connect => 'Bağlan';
  @override
  String openFailed(Object error) => 'Notelore klasörlerini açamadı.\n\n$error';

  @override
  String get chooseProvider => 'Bir model sağlayıcı seç';
  @override
  String get advanced => 'Gelişmiş';
  @override
  String advancedExplained({required bool localModels}) => localModels
      ? 'Kendi API anahtarın ya da bu bilgisayardaki bir model.'
      : 'Kendi API anahtarını kullan.';
  @override
  String get apiKey => 'API anahtarı';
  @override
  String get pasteKeyFirst => 'Önce anahtarı yapıştır.';
  @override
  String get checkConnection => 'Bağlantını kontrol edip yeniden dene.';
  @override
  String get signInUnfinished => 'Giriş tamamlanmadı. Lütfen yeniden dene.';
  @override
  String get cannotReach => 'Hizmete ulaşılamadı.';
  @override
  String get ollamaNoKey => 'Ollama bu bilgisayarda çalışır; anahtar gerekmez.';
  @override
  String providerName(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'ChatGPT planı (OpenAI)',
    'ollama' => 'Ollama (yerel)',
    _ => spec.displayName,
  };
  @override
  String groupHeading(ProviderGroup group) => switch (group) {
    ProviderGroup.plan => 'Planınla kullan',
    ProviderGroup.apiKey => 'API anahtarı',
    ProviderGroup.local => 'Bu bilgisayarda',
  };
  @override
  String groupExplanation(ProviderGroup group) => switch (group) {
    ProviderGroup.plan => 'Ek ücret yok, planının limitleri içinde.',
    ProviderGroup.apiKey =>
      'Sağlayıcı kullandıkça ücretlendirir; Gemini’nin ücretsiz bir kotası var.',
    ProviderGroup.local => 'Ücretsiz: model bu bilgisayarda çalışır.',
  };
  @override
  String cost(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' =>
      'ChatGPT Plus veya Pro planını kullanır: ayrıca ücret yok, planının limitleri içinde.',
    'anthropic' =>
      'Anthropic API üzerinden kullandıkça ücretlendirilir. Claude Pro veya Max aboneliği '
          'başka uygulamalarda kullanılamaz.',
    'openai' =>
      'OpenAI API üzerinden kullandıkça ücretlendirilir. ChatGPT Plus veya Pro planını '
          'kullanmak için "ChatGPT planı"nı seç.',
    'gemini' =>
      'Faturalandırması olmayan bir Google AI Studio projesinin anahtarıyla ücretsiz: hız '
          'sınırlıdır ve Google ücretsiz istekleri ürünlerini geliştirmek için kullanabilir. '
          'Aksi halde kullandıkça ücretlendirilir.',
    _ => 'Ücretsiz: model bu bilgisayarda çalışır.',
  };
  @override
  List<String> keySteps(ProviderSpec spec) => switch (spec.name) {
    'anthropic' => [
      'Anthropic Console’a giriş yap (ücretsiz bir hesap yeterli).',
      'Create Key’i seç, notelore gibi bir ad ver ve anahtarı kopyala.',
      'Anahtarı aşağıya yapıştır (sk-ant- ile başlar).',
    ],
    'openai' => [
      'OpenAI Platform’a giriş yap.',
      'Create new secret key’i seç, bir ad ver ve anahtarı kopyala.',
      'Anahtarı aşağıya yapıştır (sk- ile başlar).',
    ],
    'gemini' => [
      'Google AI Studio’ya giriş yap.',
      'Create API key’i seç ve anahtarı kopyala.',
      'Anahtarı aşağıya yapıştır.',
    ],
    _ => const [],
  };

  @override
  String get planWelcome =>
      'Notelore’un cevapları ChatGPT Plus veya Pro planından düşer, ayrıca ücret '
      'alınmaz. Bu kullanımı ChatGPT’de görebilir ve yönetebilirsin.';

  @override
  String get askSomething => 'Bana bir şey sor ya da anlat.';
  @override
  String get message => 'Mesaj';
  @override
  String get send => 'Gönder';
  @override
  String get resend => 'Yeniden gönder';
  @override
  String get copy => 'Kopyala';
  @override
  String get copied => 'Kopyalandı';
  @override
  String get attachFile => 'Dosya ekle';
  @override
  String attachedFile(String name) => 'Dosya: $name';
  @override
  String attachedImage(String name) => 'Görsel: $name';
  @override
  String notText(String name) =>
      "Notelore şimdilik metin dosyalarını, PDF'leri (txt, md, csv, pdf gibi) ve görselleri "
      '(PNG, JPEG, GIF, WebP) okuyor; $name bunlardan değil.';
  @override
  String noPdfText(String name) =>
      '$name içinde okunacak yazı yok (taranmış ya da bozuk bir dosya); '
      "Notelore bir PDF'nin yalnızca yazısını okur.";
  @override
  String tooLarge(String name) => '$name gönderilemeyecek kadar büyük; daha küçük dosyalara böl.';
  @override
  String noImages(String provider) => '$provider görsellere bakamıyor; metin dosyaları yine olur.';
  @override
  String get imagesNotNow => 'Görseller, yolda başka bir şey yokken gider; birazdan yeniden dene.';
  @override
  String get imagesCannotWait =>
      'Görseller sonra gönderilmek üzere bekleyemez: tekrar çevrimiçi olunca mesajı yeniden gönder.';
  @override
  String get appLock => 'Uygulama kilidi';
  @override
  String get appLockOn => 'Açık: Notelore açılırken PIN veya parolanı sorar.';
  @override
  String get appLockOff => 'Kapalı: Notelore sormadan açılır.';
  @override
  String get turnOn => 'Aç';
  @override
  String get turnOff => 'Kapat';
  @override
  String get lockSecret => 'PIN veya parola';
  @override
  String get lockRepeat => 'Tekrar yaz';
  @override
  String get lockTooShort => 'En az 4 karakter.';
  @override
  String get lockMismatch => 'Aynı değil.';
  @override
  String get lockedTitle => 'Notelore kilitli';
  @override
  String get lockedHint =>
      'Unuttun mu? Notların güvende: not klasöründe ve Drive’da dosya olarak duruyorlar.';
  @override
  String get unlock => 'Kilidi aç';
  @override
  String get wrongSecret => 'Bu değil. Tekrar dene.';
  @override
  String lockWaiting(Duration wait) => 'Çok fazla deneme. ${_minutes(wait)} sonra tekrar dene.';
  @override
  String get notesMayBeSaved =>
      'Bu hatadan önce bazı notlar kaydedilmiş olabilir. Bir şey iki kez kaydedilmesin diye '
      'yeniden göndermeden önce onlara bak.';
  @override
  String get stop => 'Durdur';
  @override
  String get changeTheModel => 'Modeli değiştir';
  @override
  String get changeModel => 'Model değiştir';
  @override
  String modelGone(String provider, String model) =>
      '$provider artık $model modelini sunmuyor. Başka bir model seç.';
  @override
  List<String> get waitingLines => const [
    'Kahve koymaya gitti, birazdan döner.',
    'Keyfinin kâhyasını bekliyor.',
    'İlham perisine mesaj attı, cevap bekliyor.',
    'Kalemini açıyor…',
    'Notlarının arasında dolaşıyor.',
    'Beyin hücrelerini ısıtıyor.',
    'Düşünce yumağını çözüyor.',
    'Çay demlendi, bardaklara koyuyor.',
    'Virgülleri parlatıyor.',
    'Rafları tek tek geziyor.',
    'İçinden ona kadar sayıyor.',
    'Hafızasının tozunu alıyor.',
    'Kelimeleri tartıyor, bir gram fazla gelmesin.',
    'Gözlüğünü arıyor.',
    'Simitçiden dönüyor.',
    'Kâhine danıştı, kâhin molada.',
    'Fişleri karıştırıyor.',
    'Düşünür pozunu verdi.',
    'Önce ayakkabılarını bağlıyor.',
    'Çarktaki hamsteri besliyor.',
  ];
  @override
  String get talk => 'Basılı tut, konuş';
  @override
  String get stopReading => 'Sesli okumayı durdur';
  @override
  String get waitingToSend => 'Gönderilmeyi bekliyor';
  @override
  String get tryNow => 'Şimdi dene';
  @override
  String get holdHint => 'Konuşurken düğmeyi basılı tut.';
  @override
  String get listening => 'Dinliyorum…';
  @override
  String get speaking => 'Okuyorum…';
  @override
  String speechFailed(String code) => 'Ses tanıma başarısız oldu ($code); yazmaya dönüldü.';
  @override
  String get voiceUnavailable =>
      'Ses tanıma kullanılamıyor. Mikrofona izin ver; Windows’ta uygulama dilinin konuşma '
      'paketini ekle (Ayarlar, Saat ve dil, Konuşma).';

  @override
  String get refresh => 'Yenile';
  @override
  String get noNotes => 'Henüz not yok. Asistana hatırlaması gereken bir şey anlat.';
  @override
  String deleteQuestion(String title) => '"$title" silinsin mi?';
  @override
  String get deleteExplained =>
      'Arşive taşınır; notlar klasöründeki _archive/ içinden geri getirebilirsin.';
  @override
  String alreadyGone(String title) => '"$title" zaten silinmiş.';
  @override
  String movedToArchive(String title) => '"$title" arşive taşındı.';
  @override
  String get export => 'Dışa aktar';
  @override
  String get exportNotes => 'Notları dışa aktar';
  @override
  String get importNotes => 'Not içe aktar';
  @override
  String get exportAs => 'Şu biçimde dışa aktar';
  @override
  String formatName(ExportFormat format) => switch (format) {
    ExportFormat.markdown => 'Markdown (yeniden içe aktarılabilir)',
    ExportFormat.pdf => 'PDF',
    ExportFormat.html => 'Web sayfası (HTML)',
  };
  @override
  String get chooseNotes => 'Hangi notlar?';
  @override
  String get next => 'İleri';
  @override
  String exported(int count) => '$count not dışa aktarıldı.';
  @override
  String exportFailed(String why) => 'Dışa aktarma başarısız oldu: $why';
  @override
  String importedAdded(String title) => '"$title" içe aktarıldı.';
  @override
  String importedRenamed(String title) =>
      '"$title" olarak içe aktarıldı: bu adda başka bir not zaten vardı.';
  @override
  String importedSame(String title) => '"$title" zaten var, değişmedi.';
  @override
  String importRefused(String file) => '"$file" bir Notelore notu değil.';
  @override
  String get undo => 'Geri al';
  @override
  String noteSubtitle(String kind, String updated) =>
      '${switch (kind) {
        'project' => 'proje',
        'topic' => 'konu',
        _ => kind,
      }} · güncelleme $updated';

  @override
  String get provider => 'Sağlayıcı';
  @override
  String get model => 'Model';
  @override
  String get refreshModels => 'Model listesini yenile';
  @override
  String get modelSaved => 'Model kaydedildi.';
  @override
  String get checkForUpdates => 'Güncellemeleri denetle';
  @override
  String get logOut => 'Çıkış yap';
  @override
  String get logOutExplained => 'Çıkış yapınca bu cihazdaki API anahtarı silinir. Notların kalır.';
  @override
  String get language => 'Dil';
  @override
  String languageName(AppLanguage language) => switch (language) {
    AppLanguage.system => 'Sistem',
    AppLanguage.en => 'English',
    AppLanguage.tr => 'Türkçe',
  };
  @override
  String get theme => 'Tema';
  @override
  String versionLine(String version) =>
      version.isEmpty ? 'Notelore · geliştirme sürümü' : 'Notelore $version';
  @override
  String get usage => 'Kullanım';
  @override
  String get usageConversation => 'Bu konuşma';
  @override
  String get usageDevice => 'Bu cihazda';
  @override
  String get usageNothing => 'Henüz yok.';
  @override
  String usageTokens(String input, String output) => 'Token: $input giriş, $output çıkış';
  @override
  String get usageTokensUnavailable => 'Token: bilgi yok';
  @override
  String usageUnreported(int calls) => '$calls model çağrısı kullanım bildirmedi';
  @override
  String usageCost(String dollars) => 'Tahmini maliyet: yaklaşık \$$dollars';
  @override
  String get usageCostUnavailable => 'Tahmini maliyet: bilgi yok';
  @override
  String usageEstimate(String date) =>
      'Maliyetler $date tarihli liste fiyatlarından tahmindir; geçerli olan sağlayıcınızın faturasıdır.';
  @override
  String get usagePlan =>
      'ChatGPT planında token başına ücret yok: kullanım planınızın sınırlarından düşer.';
  @override
  String get usageLocal => 'Yerel modelde token başına ücret yok.';
  @override
  String get thousands => '.';
  @override
  String get decimalPoint => ',';
  @override
  String get archive => 'Arşiv';
  @override
  String get pickNote => 'Okumak için bir not seç.';
  @override
  String entriesFrom(String title) => '$title notundan girdiler';
  @override
  String get archiveEmpty => 'Arşiv boş. Silinen notlar buraya gelir.';
  @override
  String archivedOn(String date) => '$date tarihinde arşivlendi';
  @override
  String get restore => 'Geri getir';
  @override
  String restored(String title) => '"$title" geri getirildi.';
  @override
  String restoreTaken(String title) =>
      '"$title" adında bir not zaten var, bu yüzden bu not arşivde kalıyor.';
  @override
  String get webSearch => 'Gerekirse internette araştır';
  @override
  String get webSearchExplained =>
      'Yalnızca notu doğru tutmaya yardım edecekse; örneğin andığın bir kitabın yazarı.';
  @override
  String get webSearchBilled =>
      'Yalnızca notu doğru tutmaya yardım edecekse. Anthropic her aramayı ayrıca ücretlendirir.';
  @override
  String get webSearchUnavailable => 'Bu sağlayıcıda kullanılamıyor.';
  @override
  String get whisper => 'Whisper ses tanıma';
  @override
  String get tryAgain => 'Tekrar dene';
  @override
  String whisperDownloading(int percent) => 'İndiriliyor… %$percent';
  @override
  String whisperFailed(String why) => 'İndirme başarısız oldu: $why';
  @override
  String get microphone => 'Mikrofon';
  @override
  String get systemMicrophone => 'Sistem varsayılanı';
  @override
  String get listMicrophones => 'Mikrofonları yeniden listele';
  @override
  String paletteName(Palette palette) => switch (palette) {
    Palette.lagoon => 'Lagün',
    Palette.forest => 'Çam ormanı',
    Palette.sea => 'Açık deniz',
    Palette.sunset => 'Gün batımı',
    Palette.lavender => 'Lavanta tarlası',
    Palette.aurora => 'Kuzey ışıkları',
  };
  @override
  String get appearance => 'Görünüm';
  @override
  String get voiceSection => 'Ses';
  @override
  String get syncSection => 'Eşitleme';
  @override
  String get aboutSection => 'Hakkında';
  @override
  String appearanceName(Appearance appearance) => switch (appearance) {
    Appearance.system => 'Sistem',
    Appearance.light => 'Açık',
    Appearance.dark => 'Koyu',
  };
  @override
  String get drive => 'Google Drive';
  @override
  String get driveNotSetUp => 'Bu sürümde eşitleme ayarlı değil.';
  @override
  String get driveExplained => 'Notlarını yedekle ve cihazların arasında eşitle.';
  @override
  String get signInWithGoogle => 'Google ile giriş yap';
  @override
  String get googleExplained =>
      'Notelore notlarını kendi Google Drive’ında tutar, böylece tüm cihazlarında olurlar. '
      'Başlamak için Google (Gmail) hesabınla giriş yap. Notelore orada yalnızca kendi '
      'oluşturduğu dosyaları görebilir.';
  @override
  String get googleRequired =>
      'Notelore’u kullanmak için bir Google hesabı gerekir. Devam etmek için giriş yap.';
  @override
  String get syncing => 'Eşitleniyor...';
  @override
  String get connected => 'Bağlı.';
  @override
  String get syncNow => 'Şimdi eşitle';
  @override
  String get disconnectDrive => 'Google Drive bağlantısını kes';

  @override
  String get upToDate => 'Notelore güncel.';
  @override
  String updateAvailable(String version) => 'Notelore $version çıktı.';
  @override
  String installing(String version) => 'Notelore $version kuruluyor...';
  @override
  String installed(String version) =>
      'Notelore $version kuruldu. Kullanmak için Notelore’u kapatıp yeniden aç.';
  @override
  String checkFailed(Object error) => 'Güncellemeler denetlenemedi: $error';
  @override
  String setupFailed(Object error) => 'Kurulum başlatılamadı: $error';
  @override
  String get later => 'Sonra';
  @override
  String get updateAndRestart => 'Güncelle ve yeniden başlat';
  @override
  String get update => 'Güncelle';
  @override
  String get allowInstalls =>
      'Az önce açılan ayarda Notelore’un uygulama yüklemesine izin ver, sonra yeniden Güncelle’ye bas.';

  @override
  String get offline => 'Çevrimdışı; bağlantı gelince notların eşitlenecek.';
  @override
  String driveError(String message) => 'Google Drive: $message';
  @override
  String signInAgain(String message) => '$message; yeniden bağlan.';
  @override
  String noteInUse(String message) =>
      'Bir not başka bir program tarafından kullanılıyor ($message); sonraki eşitleme yeniden dener.';
  @override
  String synced(int sent, int received, int merged, int waiting) {
    final parts = [
      if (sent > 0) '$sent gönderildi',
      if (received > 0) '$received alındı',
      if (merged > 0) '$merged birleştirildi',
      if (waiting > 0) '$waiting çakışmanın çözülmesini bekliyor',
    ];
    return parts.isEmpty ? 'Eşitlendi; değişiklik yok.' : 'Eşitlendi: ${parts.join(', ')}.';
  }

  static const _core = {
    'Thinking': 'Düşünüyor',
    'Searching the notes': 'Notlar aranıyor',
    'Reading the notes': 'Notlar okunuyor',
    'Writing the notes': 'Notlar yazılıyor',
    'Working': 'Çalışıyor',
    'Stopped.': 'Durduruldu.',
    'No answer in time, so I stopped. Please try again.':
        'Zamanında cevap gelmedi, durdurdum. Lütfen yeniden dene.',
    'The model sent no answer. Try again.': 'Model cevap vermedi. Yeniden dene.',
    'I stopped after too many tool calls in a row. Please rephrase the request.':
        'Arka arkaya çok fazla araç çağrısı oldu, durdum. İsteği başka türlü söyler misin?',
  };

  @override
  String core(String english) => _core[english] ?? english;
}

/// The strings for [language], [system] being the device's language code.
Strings stringsFor(AppLanguage language, String system) => switch (language) {
  AppLanguage.tr => TurkishStrings(),
  AppLanguage.en => EnglishStrings(),
  AppLanguage.system => system == 'tr' ? TurkishStrings() : EnglishStrings(),
};

/// A wait as minutes and seconds, like a timer: 0:30, 5:00.
String _minutes(Duration wait) =>
    '${wait.inMinutes}:${(wait.inSeconds % 60).toString().padLeft(2, '0')}';
