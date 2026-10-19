/// The app's words, in English and Turkish. Both languages implement
/// [Strings], so a missing entry does not compile. Texts the core produces
/// (agent steps, a stopped turn) arrive in English and go through [core].
/// OpenAI's required wording for the ChatGPT plan stays English in both.
library;

import 'package:notelore_core/notelore_core.dart';

import 'lock_state.dart' show LockKind;
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
  String stepOf(int step, int of);
  String connectedTo(String name);
  String optionCost(ProviderSpec spec);
  String optionPrivacy(ProviderSpec spec);
  String optionQuality(ProviderSpec spec);
  String optionEffort(ProviderSpec spec);
  String optionFit(ProviderSpec spec);
  String get connectedBadge;
  List<String> optionTags(ProviderSpec spec);
  String get useThisModel;
  String get tryPrompt;
  String get trying;
  String get tryCost;

  /// The test turn got no answer in time (#376).
  String tryTimedOut(int seconds);
  String get noModel;
  String get noModelWhy;
  String get connectModel;
  String get connectedExplained;
  String get start;

  /// Under the setup screen's headline: what the provider is for.
  String get chooseProviderWhy;

  /// The button that opens a provider's key page at [host].
  String openKeyPage(String host);

  /// Setup's API-key and local providers, under the one-tap plan (#206).

  /// A phone has no local models: no word of a computer there (#304).
  String get apiKey;
  String get pasteKeyFirst;
  String get checkConnection;
  String get ollamaNoKey;

  // The model on the device (#328).
  String get downloadAndConnect;
  String get resumeDownload;
  String get deviceDownloadNote;
  String get deviceModelHere;
  String get downloadingModel;
  String downloadedPercent(int percent);
  String get deviceDownloadFailed;
  String providerName(ProviderSpec spec);
  String groupHeading(ProviderGroup group);
  String cost(ProviderSpec spec);
  List<String> keySteps(ProviderSpec spec);

  // ChatGPT plan.
  String get continueWithChatGpt;

  /// A sign-in that failed, in plain words: never a raw code or HTTP body (#302).
  String signInProblem(Object error) =>
      error is NetworkError ? '$cannotReach $checkConnection' : signInUnfinished;
  String get signInUnfinished;

  /// A ChatGPT account with no Plus or Pro plan, and the free way on (#321).
  String get noChatGptPlan;
  String get noChatGptPlanWhy;
  String get freeGemini;
  String get freeGeminiPrivacy;
  String get getFreeGeminiKey;
  String get keyFromClipboard;
  String get cannotReach;
  String get usingPlan;
  String get planWelcome;
  String get gotIt;
  String get usingChatGptPlan;
  String get manageUsage;

  // Chat.
  String get askSomething;

  /// Tappable starters under an empty chat: what talking to Notelore looks like.
  List<String> get examples;
  String get message;
  String get send;
  String get resend;
  String get copy;
  String get copied;

  /// Text files attached in the chat (#222).
  String get attachFile;
  String fileTooBig(String name);
  String transcribing(String name);
  String audioNeedsWhisper(String name);
  String audioFormat(String name);
  String audioNoWords(String name);
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

  /// What opens Notelore now (#295); an older password lock invites a switch.
  String appLockOn(LockKind kind);
  String get appLockOff;

  /// The lock chooser (#295).
  String get lockChoose;
  String get lockWithDevice;
  String get lockWithDeviceExplained;
  String get lockNoDevice;
  String get lockWithPattern;
  String get lockWithPin;
  String get recommended;
  String get lockPin;
  String get drawPattern;
  String get drawPatternAgain;
  String get patternMismatch;
  String patternDot(int number);
  String get clearPattern;
  String get patternDone;

  /// What the device's own lock prompt says it is for.
  String get unlockReason;
  String get lockOnReason;
  String get lockOffReason;
  String get drawYourPattern;
  String get deviceNotUnlocked;
  String get deviceLockGone;
  String get pinTooEasy;
  String get patternTooEasy;
  String patternDotsChosen(int count);
  String get lockNotTurnedOn;
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

  /// What a screen reader hears while the assistant works (#290).
  String get working;
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
  String get connectedModels;
  String get connectAnother;
  String get remove;
  String removeModel(String name);
  String get removeModelWhy;
  String get removeFailed;
  String nowUsing(String name);
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
  String get showAdvanced;
  String get showAdvancedWhy;
  String get usageWhat;
  String get lastDays;
  String get byModel;

  /// What the last days chart says to a screen reader.
  String lastDaysSummary(String total);
  String get lastDaysNothing;
  String busiestDay(String amount, int day);
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
  String get usageInPlan;
  String get usageNoCharge;
  String get usagePlanPart;
  String get usageLocal;
  String get thousands;
  String get decimalPoint;

  /// What [summary] used: tokens, the calls that did not say, the estimated
  /// cost; "not available" where the provider gave nothing to go on.
  /// [n] with this language's thousands separator.
  String number(int n) => '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => thousands);

  List<String> usageLines(UsageSummary summary) {
    if (summary.calls == 0) return [usageNothing];
    return [
      if (summary.tokensKnown)
        usageTokens(number(summary.input), number(summary.output))
      else
        usageTokensUnavailable,
      if (summary.unreported > 0) usageUnreported(summary.unreported),
      _costLine(summary),
      if (summary.billed && summary.plan) usagePlanPart,
    ];
  }

  /// Nothing charged per token: where it went, never "$0.00" (#436).
  String _costLine(UsageSummary summary) {
    if (!summary.billed) return summary.plan ? usageInPlan : usageNoCharge;
    return switch (summary.cost) {
      null => usageCostUnavailable,
      final cost => usageCost(
        cost.toStringAsFixed(cost == 0 || cost >= 0.01 ? 2 : 4).replaceFirst('.', decimalPoint),
      ),
    };
  }

  String get archive;
  String get pickNote;

  /// Under a remote image in a note, before it is fetched (#339).
  String get tapToShow;

  /// Under an image in a note that could not be shown.
  String get imageFailed;

  // The note reader (#426).
  String noteKind(String kind);
  String updatedOn(String date);
  String earlierDecisions(int count);
  String supersededOn(String date);
  String overdue(String date);
  String reminderPassed(String date);

  // Reminders as this device's notifications (#431).
  String get reminders;
  String get remindersOn;
  String get remindersOff;
  String get allowNotifications;
  String get notificationsBlocked;
  String get reminderHidden;

  // Reminders through Google Calendar (#432).
  String get addToCalendar;
  String get addToCalendarHint;
  String get remindersInCalendar;
  String get calendarSignInFailed;
  String get calendarUpdateFailed;
  String get calendarElsewhere;
  String get signInCalendar;

  /// The months, short, January first.
  List<String> get months;

  /// "18 Oct", with the year when it is not [today]'s.
  String shortDate(DateTime date, DateTime today) =>
      '${date.day} ${months[date.month - 1]}${date.year == today.year ? '' : ' ${date.year}'}';

  /// An archived note's name; archived entries say whose they are.
  String archivedTitle(ArchivedNote archived) =>
      archived.entries ? entriesFrom(archived.title) : archived.title;
  String entriesFrom(String title);
  String get archiveEmpty;
  String archivedOn(String date);
  String get restore;
  String restored(String title);

  // Deleting from the archive for good (#438).
  String get deleteForever;
  String deleteForeverTitle(String title);
  String get deleteForeverBody;
  String deletedForever(String title);
  String get emptyArchive;
  String emptyArchiveBody(int count);
  String archiveEmptied(int count);
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

  /// The welcome before Google sign-in (#296).
  String get welcomeTitle;
  String get welcomePromise;
  String get welcomeDrive;
  String get welcomePrivate;
  String get welcomeAccount;
  String get signingIn;
  String get googleRequired;
  String get syncing;
  String get connected;
  String get syncNow;
  String get disconnectDrive;

  // Updates.
  String get upToDate;
  String updateAvailable(String version);
  String get whatsNew;
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

  // Many notes gone from Drive at once (#454).
  String heldNotes(int count);
  String get restoreToDrive;
  String get deleteHereToo;
  String deleteHeldQuestion(int count);
  String get deleteHeldExplained;
  String andMore(int count);

  /// A text the core produced in English, in this language.
  String core(String english);

  /// A failed chat turn, said kindly (#306): never the provider's raw reply.
  /// The core's own messages (a Stop, the plan's limit, a sign-in) stay as
  /// they are; any other refusal keeps its detail, framed.
  String chatError(Exception error) => switch (error) {
    NetworkError() => errorOffline,
    HttpError(status: 401 || 403) => errorKey,
    // Gemini's free tier answers a model it gives no quota with 429 "limit: 0" (#400).
    HttpError(status: 429, :final message) when message.contains('limit: 0') => errorNoQuota,
    HttpError(status: 429) => errorBusy,
    HttpError(:final status) when status >= 500 => errorProvider,
    HttpError(:final message) => errorOther(message),
    LocalModelFailed() => errorDevice,
    _ => core('$error'),
  };
  String get errorOffline;
  String get errorKey;
  String get errorBusy;
  String get errorNoQuota;
  String get errorProvider;
  String errorOther(String detail);
  String get errorDevice;
}

class EnglishStrings extends Strings {
  @override
  String get continueWithChatGpt => 'Continue with ChatGPT';
  @override
  String get usingPlan => "You're using your ChatGPT plan";
  @override
  String get gotIt => 'Got it';
  @override
  String get usingChatGptPlan => 'Using ChatGPT plan';
  @override
  String get manageUsage => 'Manage usage';
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
  String stepOf(int step, int of) => 'Step $step of $of';
  @override
  String connectedTo(String name) => 'Connected to $name';
  @override
  String optionCost(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'Your ChatGPT Plus or Pro plan, no extra charge',
    'anthropic' => 'Pay per use, billed by Anthropic',
    'openai' => 'Pay per use, billed by OpenAI',
    'gemini' => 'Free tier, or pay per use',
    'device' => 'Free, and works offline',
    _ => 'Free',
  };
  @override
  String optionPrivacy(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'Your notes go to OpenAI.',
    'anthropic' => 'Your notes go to Anthropic.',
    'openai' => 'Your notes go to OpenAI.',
    'gemini' =>
      'Your notes go to Google; on the free tier it may use them to improve its products.',
    'device' => 'The model runs on this device: your notes go to no AI provider.',
    _ => 'Your notes stay on this computer.',
  };
  @override
  String optionQuality(ProviderSpec spec) => switch (spec.name) {
    'anthropic' => 'Very strong answers',
    'openai' => 'Very strong answers',
    'chatgpt' => 'Strong answers',
    'gemini' => 'Strong answers',
    'device' => 'Simpler answers, and slow on a phone',
    _ => 'Depends on the model; usually weaker',
  };
  @override
  String optionEffort(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'One tap: sign in with ChatGPT',
    'anthropic' => 'A key from the Anthropic Console, with billing set up',
    'openai' => 'A key from the OpenAI platform, with billing set up',
    'gemini' => 'A free key from Google AI Studio, about a minute',
    'device' => 'A 2.5 GB download, once',
    _ => 'Install Ollama and a model first',
  };
  @override
  String optionFit(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'You have ChatGPT Plus or Pro',
    'anthropic' => 'You want the best answers and pay as you go',
    'openai' => 'You already use the OpenAI API',
    'gemini' => 'You want to start for free',
    'device' => 'No AI provider should see your notes',
    _ => 'Nothing should leave this computer',
  };
  @override
  String get connectedBadge => 'Connected';
  @override
  List<String> optionTags(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => ['Your plan', 'One tap'],
    'anthropic' || 'openai' => ['Pay per use', apiKey],
    'gemini' => ['Free tier', apiKey],
    'device' => ['Free', 'Offline'],
    _ => ['Free', 'Stays on this computer'],
  };
  @override
  String get useThisModel => 'Use this model';
  @override
  String get tryPrompt => 'Say hello in one short sentence.';
  @override
  String get trying => 'Saying hello to the model…';
  @override
  String tryTimedOut(int seconds) =>
      'The model did not answer within $seconds seconds. Check the connection, then connect again.';
  @override
  String get tryCost =>
      'This one message went to the provider and counts against your plan or key, a few '
      'tokens.';
  @override
  String get noModel => 'Connect a model to start';
  @override
  String get noModelWhy =>
      'Notelore needs a model to write and answer. Your notes are all here meanwhile.';
  @override
  String get connectModel => 'Connect a model';
  @override
  String get connectedExplained =>
      'Notelore will use it to write your notes and answer from them. You can change it in '
      'Settings.';
  @override
  String get start => 'Start';
  @override
  String get chooseProviderWhy =>
      'Notelore uses an AI model to write your notes and answer from them. Pick one; you can '
      'change it later in Settings.';
  @override
  String openKeyPage(String host) => 'Open $host';
  @override
  String get apiKey => 'API key';
  @override
  String get pasteKeyFirst => 'Paste the key first.';
  @override
  String get checkConnection => 'Check the connection and try again.';
  @override
  String get signInUnfinished => 'Sign-in did not finish. Please try again.';
  @override
  String get noChatGptPlan => 'Your ChatGPT account has no Plus or Pro plan';
  @override
  String get noChatGptPlanWhy =>
      'Only Plus and Pro plans can be used in other apps, so Notelore cannot use this account.';
  @override
  String get freeGemini =>
      'You can start for free with Gemini: get a key from Google AI Studio with the Google '
      'account you just signed in with, copy it, and come back here.';
  @override
  String get freeGeminiPrivacy =>
      'On the free tier, Google may use your requests to improve its products.';
  @override
  String get getFreeGeminiKey => 'Get a free Gemini key';
  @override
  String get keyFromClipboard => 'Key pasted from the clipboard. Tap Connect.';
  @override
  String get cannotReach => 'Could not reach the service.';
  @override
  String get ollamaNoKey => 'No key is needed.';
  @override
  String get downloadAndConnect => 'Download and connect';
  @override
  String get resumeDownload => 'Resume download';
  @override
  String get deviceDownloadNote => 'Use Wi-Fi and keep the app open while it downloads.';
  @override
  String get deviceModelHere => 'The model is on this device. No key is needed.';
  @override
  String get downloadingModel => 'Downloading the model';
  @override
  String downloadedPercent(int percent) => 'Downloading… $percent%';
  @override
  String get deviceDownloadFailed =>
      'The model could not be downloaded. Check the connection and try again: '
      'it continues where it stopped.';
  @override
  String providerName(ProviderSpec spec) => spec.displayName;
  @override
  String groupHeading(ProviderGroup group) => group.heading;
  @override
  String cost(ProviderSpec spec) => spec.cost;
  @override
  List<String> keySteps(ProviderSpec spec) => spec.keySteps;

  @override
  String get planWelcome =>
      "Notelore's answers count against your ChatGPT Plus or Pro plan, with no separate "
      'charges. You can see and manage that usage in ChatGPT.';

  @override
  String get askSomething => 'Write something to note, or ask about your notes.';
  @override
  List<String> get examples => const [
    "I'm reading Tanpınar's The Time Regulation Institute",
    'Remind me to renew my passport next month',
    'What did we decide about the database?',
  ];
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
  String transcribing(String name) => 'Listening to $name…';
  @override
  String audioNeedsWhisper(String name) =>
      '$name needs on-device speech recognition: Whisper is still on its way (Settings → Voice).';
  @override
  String audioFormat(String name) => '$name cannot be opened on this device. Try it as a WAV file.';
  @override
  String audioNoWords(String name) => 'No words were heard in $name, so nothing was sent.';
  @override
  String fileTooBig(String name) => '$name is too big to attach (20 MB at most).';
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
  String appLockOn(LockKind kind) => switch (kind) {
    LockKind.device => "On: your device's lock opens Notelore.",
    LockKind.pattern => 'On: a pattern opens Notelore.',
    LockKind.pin => 'On: a PIN opens Notelore.',
    _ =>
      "On: your password opens Notelore. You can switch to your device's lock, a pattern or a PIN.",
  };
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
  String get lockTooShort => 'At least 4 digits.';
  @override
  String get lockChoose => 'How should Notelore lock?';
  @override
  String get lockWithDevice => "Your device's lock";
  @override
  String get lockWithDeviceExplained =>
      'Fingerprint, face, pattern or PIN: whatever unlocks this device.';
  @override
  String get lockNoDevice =>
      'This device has no screen lock set up: set one up, or use a pattern or PIN.';
  @override
  String get lockWithPattern => 'A pattern for Notelore';
  @override
  String get lockWithPin => 'A PIN for Notelore';
  @override
  String get recommended => 'Recommended';
  @override
  String get lockPin => 'PIN';
  @override
  String get drawPattern => 'Draw a pattern through at least 4 dots.';
  @override
  String get drawPatternAgain => 'Draw the same pattern again.';
  @override
  String get patternMismatch => 'That was a different pattern. Start again.';
  @override
  String patternDot(int number) => 'Dot $number';
  @override
  String get clearPattern => 'Clear';
  @override
  String get patternDone => 'Done';
  @override
  String get unlockReason => 'Unlock Notelore';
  @override
  String get lockOnReason => 'Turn on the app lock';
  @override
  String get lockOffReason => 'Turn off the app lock';
  @override
  String get drawYourPattern => 'Draw your pattern.';
  @override
  String get deviceNotUnlocked => 'Not unlocked. Tap Unlock to try again.';
  @override
  String get deviceLockGone =>
      "This device has no screen lock any more. Set one up in the device's settings to open Notelore.";
  @override
  String get pinTooEasy => 'Too easy to guess: not one digit repeated, nor a run like 1234.';
  @override
  String get patternTooEasy => 'That pattern is one of the first people try. Draw another.';
  @override
  String patternDotsChosen(int count) => count == 1 ? '1 dot chosen' : '$count dots chosen';
  @override
  String get lockNotTurnedOn => 'The app lock is still off.';
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
  String get working => 'Working on it…';
  @override
  List<String> get waitingLines => const [
    'Went to make coffee, back in a sec…',
    'Waiting for the muse to call back…',
    'Sharpening a pencil…',
    'Rummaging through your notes…',
    'Warming up the brain cells…',
    'Untangling a ball of thoughts…',
    'Asking the rubber duck…',
    'Polishing the commas…',
    'Browsing the shelves, aisle by aisle…',
    'Counting to ten, slowly…',
    'Dusting off the memory palace…',
    'Weighing every word…',
    'Brewing a fresh pot of ideas…',
    'Looking for its reading glasses…',
    'Herding stray thoughts…',
    'Consulting the oracle (it is on a break)…',
    'Flipping through the index cards…',
    'Making its thinking face…',
    'Tying its shoelaces first…',
    'Feeding the hamster on the wheel…',
    'Checking under the sofa cushions…',
    'Asking the notes politely…',
    'Lining up the thoughts in a row…',
    'Finding the right drawer…',
    'Licking the pencil tip…',
    'Turning the page, carefully…',
    'Reading between the lines…',
    'Sorting the sticky notes by colour…',
    'Waiting for the kettle to whistle…',
    'Putting on its thinking cap…',
    'Stacking the index cards neatly…',
    'Following a hunch…',
    'Taking a deep breath…',
    'Opening the right notebook…',
    'Checking the margins…',
    'Unfolding a crumpled idea…',
    'Cleaning its glasses again…',
    'Choosing between two good words…',
    'Putting two and two together…',
    'Flipping back a few pages…',
    'Looking up the cross-references…',
    'Stretching its fingers…',
    'Clearing a corner of the desk…',
    'Sharpening the next thought…',
    'Asking the bookmark where it was…',
    'Underlining the important bit…',
    'Tidying the paper clips…',
    'Checking it twice…',
    'Letting the idea settle…',
    'Writing it neatly this time…',
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
  String noteSubtitle(String kind, String updated) => '${noteKind(kind)} · updated $updated';

  @override
  String get connectedModels => 'Connected models';
  @override
  String get connectAnother => 'Connect another model';
  @override
  String get remove => 'Remove';
  @override
  String removeModel(String name) => 'Remove $name?';
  @override
  String get removeFailed => 'Could not remove it. Please try again.';
  @override
  String get removeModelWhy =>
      'Its key or sign-in is removed from this device. Your notes and this conversation stay.';
  @override
  String nowUsing(String name) => 'Now using $name';
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
  String get showAdvanced => 'Show advanced settings';
  @override
  String get showAdvancedWhy => 'Extra pages for checking how the app works.';
  @override
  String busiestDay(String amount, int day) => 'Busiest day: the ${day}th, $amount';
  @override
  String get usageWhat => 'What the model read and wrote, and what it cost';
  @override
  String get lastDays => 'Last 14 days';
  @override
  String get byModel => 'By model';
  @override
  String lastDaysSummary(String total) => 'Last 14 days: $total in all';
  @override
  String get lastDaysNothing => 'Last 14 days: nothing used';
  @override
  String get usageConversation => 'This conversation';
  @override
  String get usageDevice => 'On this device';
  @override
  String get usageNothing => 'Nothing yet.';
  @override
  String usageTokens(String input, String output) => '$input read · $output written';
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
  String get usageInPlan => 'Included in your ChatGPT plan';
  @override
  String get usageNoCharge => 'No per-token charge: a local model';
  @override
  String get usagePlanPart => 'What ran on the ChatGPT plan is included in it';
  @override
  String usageEstimate(String date) =>
      'Read and written are counted in tokens, pieces of words. Costs are estimates from list '
      "prices taken on $date; your provider's bill is what counts.";
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
  String get tapToShow => 'Tap to show';
  @override
  String get imageFailed => "Couldn't load";
  @override
  String noteKind(String kind) => switch (kind) {
    'project' => 'Project',
    'topic' => 'Topic',
    _ => kind,
  };
  @override
  String updatedOn(String date) => 'Updated $date';
  @override
  String earlierDecisions(int count) => 'Earlier decisions ($count)';
  @override
  String supersededOn(String date) => 'superseded $date';
  @override
  String overdue(String date) => 'Overdue, $date';
  @override
  String reminderPassed(String date) => 'Passed, $date';
  @override
  String get reminders => 'Reminders';
  @override
  String get remindersOn => "Notelore notifies you on this device at a reminder's time.";
  @override
  String get remindersOff =>
      "Notifications are off for Notelore: reminders stay in your notes, but you won't be notified.";
  @override
  String get allowNotifications => 'Allow notifications';
  @override
  String get notificationsBlocked => 'Turn on notifications for Notelore in the system settings.';
  @override
  String get reminderHidden => 'You have a reminder.';
  @override
  String get addToCalendar => 'Add to Google Calendar';
  @override
  String get addToCalendarHint =>
      'Only a calendar of its own: your other calendars stay as they are.';
  @override
  String get remindersInCalendar =>
      'Google Calendar reminds you on every device. Notelore sends no notifications of its own.';
  @override
  String get calendarSignInFailed => "Couldn't sign in to Google Calendar. Try again.";
  @override
  String get calendarUpdateFailed => "Couldn't update Google Calendar. Notelore tries again later.";
  @override
  String get calendarElsewhere =>
      'Google Calendar reminds you, set up on another device. '
      'Sign in here too, so the reminders you add on this device go there as well.';
  @override
  String get signInCalendar => 'Sign in to Google Calendar';
  @override
  List<String> get months => const [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
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
  String get deleteForever => 'Delete for good';
  @override
  String deleteForeverTitle(String title) => 'Delete "$title" for good?';
  @override
  String get deleteForeverBody =>
      'This cannot be undone on this device. With Google Drive on, its copy stays in '
      "Drive's trash for 30 days.";
  @override
  String deletedForever(String title) => 'Deleted "$title" for good.';
  @override
  String get emptyArchive => 'Empty the archive';
  @override
  String archiveEmptied(int count) =>
      'Deleted $count ${count == 1 ? 'note' : 'notes'} from the archive for good.';
  @override
  String emptyArchiveBody(int count) =>
      'All $count ${count == 1 ? 'note' : 'notes'} in the archive will be deleted for good. '
      "This cannot be undone on this device; with Google Drive on, the copies stay in Drive's "
      'trash for 30 days.';
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
  String get welcomeTitle => 'Welcome to Notelore';
  @override
  String get welcomePromise =>
      'Tell it things and it keeps tidy notes. Ask later, and it answers from them.';
  @override
  String get welcomeDrive =>
      'Your notes are backed up and synced through your own Google Drive, on all your devices.';
  @override
  String get welcomePrivate => 'Notelore can only see the files it creates there.';
  @override
  String get welcomeAccount => 'Sign in with your Google (Gmail) account to start.';
  @override
  String get signingIn => 'Signing in…';
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
  String updateAvailable(String version) => 'A fresh Notelore is ready: $version.';
  @override
  String get whatsNew => "What's new";
  @override
  String installing(String version) => 'Putting the new Notelore in place ($version)…';
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
  String heldNotes(int count) => count == 1
      ? '1 note was removed from Google Drive. Notelore kept it here.'
      : '$count notes were removed from Google Drive at once. Notelore kept them here.';
  @override
  String get restoreToDrive => 'Restore to Drive';
  @override
  String get deleteHereToo => 'Delete here too';
  @override
  String deleteHeldQuestion(int count) =>
      count == 1 ? 'Delete 1 note here too?' : 'Delete $count notes here too?';
  @override
  String get deleteHeldExplained =>
      "They leave this device as they left Drive. A copy stays in Notelore's history.";
  @override
  String andMore(int count) => '+$count more';

  @override
  String core(String english) => english;
  @override
  String get errorOffline => "Couldn't reach the model. Check your connection.";
  @override
  String get errorKey => 'The provider turned the key or sign-in down. Check it in Settings.';
  @override
  String get errorBusy => 'The provider is getting too many requests just now. Wait a moment.';
  @override
  String get errorNoQuota =>
      'Your key has no quota for this model, so waiting will not help. Choose another model in Settings.';
  @override
  String get errorProvider => "The model's service is having trouble right now. Try again soon.";
  @override
  String errorOther(String detail) => 'The provider could not answer: $detail';
  @override
  String get errorDevice =>
      'This device could not run the model: it may not have enough memory. '
      'Choose another model in Settings.';
}

class TurkishStrings extends Strings {
  static const _free = 'Ücretsiz';

  @override
  String get continueWithChatGpt => 'ChatGPT ile devam et';
  @override
  String get usingPlan => 'ChatGPT planını kullanıyorsun';
  @override
  String get gotIt => 'Anladım';
  @override
  String get usingChatGptPlan => 'ChatGPT planı kullanılıyor';
  @override
  String get manageUsage => 'Kullanımı yönet';
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
  String stepOf(int step, int of) => 'Adım $step/$of';
  @override
  String connectedTo(String name) => '$name bağlandı';
  @override
  String optionCost(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'ChatGPT Plus ya da Pro planın, ek ücret yok',
    'anthropic' => 'Kullandıkça öde, Anthropic faturalar',
    'openai' => 'Kullandıkça öde, OpenAI faturalar',
    'gemini' => 'Ücretsiz katman ya da kullandıkça öde',
    'device' => 'Ücretsiz, çevrimdışı da çalışır',
    _ => _free,
  };
  @override
  String optionPrivacy(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => "Notların OpenAI'ye gider.",
    'anthropic' => "Notların Anthropic'e gider.",
    'openai' => "Notların OpenAI'ye gider.",
    'gemini' => "Notların Google'a gider; ücretsiz katmanda Google bunları ürünlerini geliştirmek için kullanabilir.",
    'device' => 'Model bu cihazda çalışır: notların hiçbir yapay zekâ sağlayıcısına gitmez.',
    _ => 'Notların bu bilgisayarda kalır.',
  };
  @override
  String optionQuality(ProviderSpec spec) => switch (spec.name) {
    'anthropic' => 'Çok güçlü cevaplar',
    'openai' => 'Çok güçlü cevaplar',
    'chatgpt' => 'Güçlü cevaplar',
    'gemini' => 'Güçlü cevaplar',
    'device' => 'Daha basit cevaplar; telefonda yavaş',
    _ => 'Modele bağlı; genelde daha zayıf',
  };
  @override
  String optionEffort(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'Tek dokunuş: ChatGPT ile giriş yap',
    'anthropic' => "Anthropic Console'dan, faturalandırması açık bir anahtar",
    'openai' => 'OpenAI platformundan, faturalandırması açık bir anahtar',
    'gemini' => "Google AI Studio'dan ücretsiz bir anahtar, yaklaşık bir dakika",
    'device' => 'Bir kez 2,5 GB indirme',
    _ => "Önce Ollama'yı ve bir modeli kur",
  };
  @override
  String optionFit(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => "ChatGPT Plus ya da Pro'n varsa",
    'anthropic' => 'En iyi cevapları istiyor, kullandıkça ödemeye razıysan',
    'openai' => 'Zaten OpenAI API kullanıyorsan',
    'gemini' => 'Ücretsiz başlamak istiyorsan',
    'device' => 'Notlarını hiçbir yapay zekâ sağlayıcısı görmesin istiyorsan',
    _ => 'Hiçbir şey bu bilgisayardan çıkmasın istiyorsan',
  };
  @override
  String get connectedBadge => 'Bağlı';
  @override
  List<String> optionTags(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => ['Planın', 'Tek dokunuş'],
    'anthropic' || 'openai' => ['Kullandıkça öde', apiKey],
    'gemini' => ['Ücretsiz katman', apiKey],
    'device' => [_free, 'Çevrimdışı'],
    _ => [_free, 'Bu bilgisayarda kalır'],
  };
  @override
  String get useThisModel => 'Bu modeli kullan';
  @override
  String get tryPrompt => 'Tek kısa cümleyle merhaba de.';
  @override
  String get trying => 'Modele merhaba deniyor…';
  @override
  String tryTimedOut(int seconds) =>
      'Model $seconds saniye içinde cevap vermedi. Bağlantıyı kontrol edip yeniden bağlan.';
  @override
  String get tryCost =>
      'Bu tek mesaj sağlayıcıya gitti ve planından ya da anahtarından birkaç token düştü.';
  @override
  String get noModel => 'Başlamak için bir model bağla';
  @override
  String get noModelWhy =>
      'Notelore yazmak ve cevaplamak için bir modele ihtiyaç duyar. Notların bu arada burada.';
  @override
  String get connectModel => 'Model bağla';
  @override
  String get connectedExplained =>
      'Notelore notlarını yazmak ve onlardan cevap vermek için bunu kullanacak. Ayarlar\'dan '
      'değiştirebilirsin.';
  @override
  String get start => 'Başla';
  @override
  String get chooseProviderWhy =>
      'Notelore notlarını yazmak ve onlardan cevap vermek için bir yapay zekâ modeli kullanır. '
      'Birini seç; sonra Ayarlar\'dan değiştirebilirsin.';
  @override
  String openKeyPage(String host) => '$host adresini aç';
  @override
  String get apiKey => 'API anahtarı';
  @override
  String get pasteKeyFirst => 'Önce anahtarı yapıştır.';
  @override
  String get checkConnection => 'Bağlantını kontrol edip yeniden dene.';
  @override
  String get signInUnfinished => 'Giriş tamamlanmadı. Lütfen yeniden dene.';
  @override
  String get noChatGptPlan => 'ChatGPT hesabında Plus ya da Pro planı yok';
  @override
  String get noChatGptPlanWhy =>
      'Başka uygulamalarda yalnızca Plus ve Pro planları kullanılabilir; Notelore bu hesabı '
      'kullanamaz.';
  @override
  String get freeGemini =>
      'Gemini ile ücretsiz başlayabilirsin: az önce giriş yaptığın Google hesabıyla Google AI '
      'Studio’dan bir anahtar al, kopyala ve buraya dön.';
  @override
  String get freeGeminiPrivacy =>
      'Ücretsiz katmanda Google, isteklerini ürünlerini geliştirmek için kullanabilir.';
  @override
  String get getFreeGeminiKey => 'Ücretsiz Gemini anahtarı al';
  @override
  String get keyFromClipboard => 'Anahtar panodan yapıştırıldı. Bağlan’a dokun.';
  @override
  String get cannotReach => 'Hizmete ulaşılamadı.';
  @override
  String get ollamaNoKey => 'Anahtar gerekmez.';
  @override
  String get downloadAndConnect => 'İndir ve bağlan';
  @override
  String get resumeDownload => 'İndirmeye devam et';
  @override
  String get deviceDownloadNote => 'İnerken Wi-Fi kullan ve uygulamayı açık tut.';
  @override
  String get deviceModelHere => 'Model bu cihazda. Anahtar gerekmez.';
  @override
  String get downloadingModel => 'Model indiriliyor';
  @override
  String downloadedPercent(int percent) => 'İndiriliyor… %$percent';
  @override
  String get deviceDownloadFailed =>
      'Model indirilemedi. Bağlantını kontrol edip yeniden dene: '
      'kaldığı yerden devam eder.';
  @override
  String providerName(ProviderSpec spec) => switch (spec.name) {
    'chatgpt' => 'ChatGPT planı (OpenAI)',
    'ollama' => 'Ollama (yerel)',
    _ => spec.displayName,
  };
  @override
  String groupHeading(ProviderGroup group) => switch (group) {
    ProviderGroup.plan => 'Planınla kullan',
    ProviderGroup.apiKey => apiKey,
    ProviderGroup.local => 'Bu bilgisayarda',
    ProviderGroup.device => 'Bu cihazda',
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
    'ollama' => [
      'Ollama’yı ollama.com’dan kur ve başlat.',
      'Bir model indir: terminalde şunu çalıştır: ollama pull qwen3:4b',
      'Geri dön ve bağlan.',
    ],
    _ => const [],
  };

  @override
  String get planWelcome =>
      'Notelore’un cevapları ChatGPT Plus veya Pro planından düşer, ayrıca ücret '
      'alınmaz. Bu kullanımı ChatGPT’de görebilir ve yönetebilirsin.';

  @override
  String get askSomething => 'Not almamı istediğin bir şey yaz ya da notlarına sor.';
  @override
  List<String> get examples => const [
    "Tanpınar'ın Saatleri Ayarlama Enstitüsü'nü okuyorum",
    'Gelecek ay pasaportumu yenilemeyi hatırlat',
    'Veritabanı için ne karar vermiştik?',
  ];
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
  String transcribing(String name) => '$name dinleniyor…';
  @override
  String audioNeedsWhisper(String name) =>
      '$name için cihazda konuşma tanıma gerekiyor: Whisper henüz yolda (Ayarlar → Ses).';
  @override
  String audioFormat(String name) => '$name bu cihazda açılamıyor. WAV dosyası olarak dene.';
  @override
  String audioNoWords(String name) => '$name içinde kelime duyulmadı, bir şey gönderilmedi.';
  @override
  String fileTooBig(String name) => '$name eklemek için çok büyük (en fazla 20 MB).';
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
  String appLockOn(LockKind kind) => switch (kind) {
    LockKind.device => 'Açık: Notelore cihazının kilidiyle açılır.',
    LockKind.pattern => 'Açık: Notelore bir desenle açılır.',
    LockKind.pin => 'Açık: Notelore bir PIN ile açılır.',
    _ =>
      'Açık: Notelore parolanla açılır. Cihazının kilidine, bir desene ya da PIN’e geçebilirsin.',
  };
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
  String get lockTooShort => 'En az 4 rakam.';
  @override
  String get lockChoose => 'Notelore nasıl kilitlensin?';
  @override
  String get lockWithDevice => 'Cihazının kilidi';
  @override
  String get lockWithDeviceExplained => 'Parmak izi, yüz, desen ya da PIN: bu cihazı ne açıyorsa.';
  @override
  String get lockNoDevice =>
      'Bu cihazda ekran kilidi kurulu değil: bir tane kur ya da desen veya PIN kullan.';
  @override
  String get lockWithPattern => 'Notelore için bir desen';
  @override
  String get lockWithPin => 'Notelore için bir PIN';
  @override
  String get recommended => 'Önerilen';
  @override
  String get lockPin => 'PIN';
  @override
  String get drawPattern => 'En az 4 noktadan geçen bir desen çiz.';
  @override
  String get drawPatternAgain => 'Aynı deseni bir kez daha çiz.';
  @override
  String get patternMismatch => 'Farklı bir desen çizdin. Baştan başla.';
  @override
  String patternDot(int number) => 'Nokta $number';
  @override
  String get clearPattern => 'Temizle';
  @override
  String get patternDone => 'Tamam';
  @override
  String get unlockReason => 'Notelore kilidini aç';
  @override
  String get lockOnReason => 'Uygulama kilidini etkinleştir';
  @override
  String get lockOffReason => 'Uygulama kilidini kapat';
  @override
  String get drawYourPattern => 'Desenini çiz.';
  @override
  String get deviceNotUnlocked => 'Kilit açılmadı. Tekrar denemek için Kilidi aç’a dokun.';
  @override
  String get deviceLockGone =>
      'Bu cihazda artık ekran kilidi yok. Notelore’u açmak için cihaz ayarlarından bir tane kur.';
  @override
  String get pinTooEasy =>
      'Tahmini çok kolay: tek bir rakamın tekrarı ya da 1234 gibi bir sıra olmasın.';
  @override
  String get patternTooEasy => 'Bu desen ilk denenenlerden biri. Başka bir desen çiz.';
  @override
  String patternDotsChosen(int count) => '$count nokta seçildi';
  @override
  String get lockNotTurnedOn => 'Uygulama kilidi hâlâ kapalı.';
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
  String get working => 'Üzerinde çalışıyor…';
  @override
  List<String> get waitingLines => const [
    'Kahve koymaya gitti, birazdan döner…',
    'Keyfinin kâhyasını bekliyor…',
    'İlham perisine mesaj attı, cevap bekliyor…',
    'Kalemini açıyor…',
    'Notlarının arasında dolaşıyor…',
    'Beyin hücrelerini ısıtıyor…',
    'Düşünce yumağını çözüyor…',
    'Çay demlendi, bardaklara koyuyor…',
    'Virgülleri parlatıyor…',
    'Rafları tek tek geziyor…',
    'İçinden ona kadar sayıyor…',
    'Hafızasının tozunu alıyor…',
    'Kelimeleri tartıyor, bir gram fazla gelmesin…',
    'Gözlüğünü arıyor…',
    'Simitçiden dönüyor…',
    'Kâhine danıştı, kâhin molada…',
    'Fişleri karıştırıyor…',
    'Düşünür pozunu verdi…',
    'Önce ayakkabılarını bağlıyor…',
    'Çarktaki hamsteri besliyor…',
    'Kanepe minderlerinin altına bakıyor…',
    'Notlara kibarca soruyor…',
    'Düşünceleri sıraya diziyor…',
    'Doğru çekmeceyi arıyor…',
    'Kalemin ucunu ıslatıyor…',
    'Sayfayı dikkatle çeviriyor…',
    'Satır aralarını okuyor…',
    'Yapışkan notları renge göre ayırıyor…',
    'Çaydanlığın ötmesini bekliyor…',
    'Düşünme şapkasını takıyor…',
    'Kartları düzgünce üst üste koyuyor…',
    'Bir sezginin peşine düşmüş…',
    'Derin bir nefes alıyor…',
    'Doğru defteri açıyor…',
    'Kenar notlarına bakıyor…',
    'Buruşmuş bir fikri düzeltiyor…',
    'Gözlüğünü yine siliyor…',
    'İki güzel kelime arasında kalmış…',
    'İkiyle ikiyi topluyor…',
    'Birkaç sayfa geri gidiyor…',
    'Çapraz bağlantılara bakıyor…',
    'Parmaklarını esnetiyor…',
    'Masada biraz yer açıyor…',
    'Bir sonraki düşünceyi açıyor…',
    'Kitap ayracına nerede kaldığını soruyor…',
    'Önemli yerin altını çiziyor…',
    'Ataçları topluyor…',
    'Bir kez daha kontrol ediyor…',
    'Fikrin oturmasını bekliyor…',
    'Bu sefer temiz yazıyor…',
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
  String noteSubtitle(String kind, String updated) => '${noteKind(kind)} · güncelleme $updated';

  @override
  String get connectedModels => 'Bağlı modeller';
  @override
  String get connectAnother => 'Başka bir model bağla';
  @override
  String get remove => 'Kaldır';
  @override
  String removeModel(String name) => '$name kaldırılsın mı?';
  @override
  String get removeFailed => 'Kaldırılamadı. Lütfen yeniden dene.';
  @override
  String get removeModelWhy =>
      'Anahtarı ya da girişi bu cihazdan silinir. Notların ve bu sohbet yerinde kalır.';
  @override
  String nowUsing(String name) => 'Artık $name kullanılıyor';
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
  String get showAdvanced => 'Gelişmiş ayarları göster';
  @override
  String get showAdvancedWhy => 'Uygulamanın nasıl çalıştığını gösteren ek sayfalar.';
  @override
  String busiestDay(String amount, int day) => 'En yoğun gün: $day, $amount';
  @override
  String get usageWhat => 'Modelin okuduğu, yazdığı ve maliyeti';
  @override
  String get lastDays => 'Son 14 gün';
  @override
  String get byModel => 'Modele göre';
  @override
  String lastDaysSummary(String total) => 'Son 14 gün: toplam $total';
  @override
  String get lastDaysNothing => 'Son 14 gün: kullanım yok';
  @override
  String get usageConversation => 'Bu konuşma';
  @override
  String get usageDevice => 'Bu cihazda';
  @override
  String get usageNothing => 'Henüz yok.';
  @override
  String usageTokens(String input, String output) => '$input okundu · $output yazıldı';
  @override
  String get usageTokensUnavailable => 'Token: bilgi yok';
  @override
  String usageUnreported(int calls) => '$calls model çağrısı kullanım bildirmedi';
  @override
  String usageCost(String dollars) => 'Tahmini maliyet: yaklaşık \$$dollars';
  @override
  String get usageCostUnavailable => 'Tahmini maliyet: bilgi yok';
  @override
  String get usageInPlan => 'ChatGPT planına dahil';
  @override
  String get usageNoCharge => 'Token başına ücret yok: yerel model';
  @override
  String get usagePlanPart => 'ChatGPT planında çalışan kısım plana dahil';
  @override
  String usageEstimate(String date) =>
      'Okunan ve yazılan token ile, yani kelime parçalarıyla sayılır. Maliyetler $date tarihli '
      'liste fiyatlarından tahmindir; geçerli olan sağlayıcının faturasıdır.';
  @override
  String get usagePlan =>
      'ChatGPT planında token başına ücret yok: kullanım planının sınırlarından düşer.';
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
  String get tapToShow => 'Göstermek için dokun';
  @override
  String get imageFailed => 'Yüklenemedi';
  @override
  String noteKind(String kind) => switch (kind) {
    'project' => 'Proje',
    'topic' => 'Konu',
    _ => kind,
  };
  @override
  String updatedOn(String date) => 'Güncellendi $date';
  @override
  String earlierDecisions(int count) => 'Önceki kararlar ($count)';
  @override
  String supersededOn(String date) => '$date tarihinde değişti';
  @override
  String overdue(String date) => 'Gecikti, $date';
  @override
  String reminderPassed(String date) => 'Geçti, $date';
  @override
  String get reminders => 'Hatırlatıcılar';
  @override
  String get remindersOn => 'Notelore, hatırlatıcının saatinde bu cihazda bildirim gönderir.';
  @override
  String get remindersOff =>
      'Notelore için bildirimler kapalı: hatırlatıcılar notlarında kalır ama bildirim gelmez.';
  @override
  String get allowNotifications => 'Bildirimlere izin ver';
  @override
  String get notificationsBlocked => 'Notelore için bildirimleri sistem ayarlarından aç.';
  @override
  String get reminderHidden => 'Bir hatırlatıcın var.';
  @override
  String get addToCalendar => "Google Takvim'e ekle";
  @override
  String get addToCalendarHint => 'Yalnızca kendi takvimi: diğer takvimlerine dokunulmaz.';
  @override
  String get remindersInCalendar =>
      'Google Takvim her cihazda hatırlatır. Notelore ayrıca bildirim göndermez.';
  @override
  String get calendarSignInFailed => "Google Takvim'e giriş yapılamadı. Tekrar dene.";
  @override
  String get calendarUpdateFailed =>
      'Google Takvim güncellenemedi. Notelore daha sonra yeniden dener.';
  @override
  String get calendarElsewhere =>
      'Google Takvim hatırlatıyor, başka bir cihazda kuruldu. '
      'Bu cihazda eklediğin hatırlatıcılar da oraya gitsin diye burada da giriş yap.';
  @override
  String get signInCalendar => "Google Takvim'e giriş yap";
  @override
  List<String> get months => const [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara', //
  ];
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
  String get deleteForever => 'Kalıcı olarak sil';
  @override
  String deleteForeverTitle(String title) => '"$title" kalıcı olarak silinsin mi?';
  @override
  String get deleteForeverBody =>
      'Bu cihazda geri alınamaz. Google Drive açıksa kopyası 30 gün Drive çöp kutusunda kalır.';
  @override
  String deletedForever(String title) => '"$title" kalıcı olarak silindi.';
  @override
  String get emptyArchive => 'Arşivi boşalt';
  @override
  String archiveEmptied(int count) => 'Arşivden $count not kalıcı olarak silindi.';
  @override
  String emptyArchiveBody(int count) =>
      'Arşivdeki $count not kalıcı olarak silinecek. Bu cihazda geri alınamaz; Google Drive '
      'açıksa kopyaları 30 gün Drive çöp kutusunda kalır.';
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
  String get welcomeTitle => 'Notelore’a hoş geldin';
  @override
  String get welcomePromise =>
      'Ona anlat, düzenli notlar tutsun. Sonra sor, notlarından yanıtlasın.';
  @override
  String get welcomeDrive =>
      'Notların kendi Google Drive’ın üzerinden yedeklenir ve tüm cihazlarında eşitlenir.';
  @override
  String get welcomePrivate => 'Notelore orada yalnızca kendi oluşturduğu dosyaları görebilir.';
  @override
  String get welcomeAccount => 'Başlamak için Google (Gmail) hesabınla giriş yap.';
  @override
  String get signingIn => 'Giriş yapılıyor…';
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
  String updateAvailable(String version) => 'Notelore’un taze bir sürümü hazır: $version.';
  @override
  String get whatsNew => 'Neler yeni';
  @override
  String installing(String version) => 'Yeni Notelore yerine yerleşiyor ($version)…';
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

  @override
  String heldNotes(int count) => count == 1
      ? "1 not Google Drive'dan kaldırıldı. Notelore onu burada tuttu."
      : "$count not Google Drive'dan bir anda kaldırıldı. Notelore onları burada tuttu.";
  @override
  String get restoreToDrive => "Drive'a geri yükle";
  @override
  String get deleteHereToo => 'Burada da sil';
  @override
  String deleteHeldQuestion(int count) => '$count not burada da silinsin mi?';
  @override
  String get deleteHeldExplained =>
      "Drive'dan gittikleri gibi bu cihazdan da giderler. Bir kopyası Notelore'un geçmişinde kalır.";
  @override
  String andMore(int count) => '+$count tane daha';

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
  @override
  String get errorOffline => 'Modele ulaşılamadı. Bağlantını kontrol et.';
  @override
  String get errorKey => 'Sağlayıcı anahtarı ya da girişi kabul etmedi. Ayarlar’dan kontrol et.';
  @override
  String get errorBusy => 'Sağlayıcı şu an çok fazla istek alıyor. Biraz bekle.';
  @override
  String get errorNoQuota =>
      'Anahtarının bu model için kotası yok, beklemek işe yaramaz. Ayarlar’dan başka bir model seç.';
  @override
  String get errorProvider => 'Modelin hizmetinde şu an bir sorun var; birazdan yeniden dene.';
  @override
  String errorOther(String detail) => 'Sağlayıcı yanıt veremedi: $detail';
  @override
  String get errorDevice =>
      'Bu cihaz modeli çalıştıramadı: belleği yetmiyor olabilir. '
      "Ayarlar'dan başka bir model seç.";
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
