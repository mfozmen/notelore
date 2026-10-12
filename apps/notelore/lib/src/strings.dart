/// The app's words, in English and Turkish. Both languages implement
/// [Strings], so a missing entry does not compile. Texts the core produces
/// (agent steps, a stopped turn) arrive in English and go through [core].
/// OpenAI's required wording for the ChatGPT plan stays English in both.
library;

import 'package:notelore_core/notelore_core.dart';

import 'theme.dart';

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
  String get usingPlan => "You're using your ChatGPT plan";
  String get planWelcome;
  String get gotIt => 'Got it';
  String get usingChatGptPlan => 'Using ChatGPT plan';
  String get manageUsage => 'Manage usage';

  // Chat.
  String get askSomething;
  String get message;
  String get send;
  String get stop;
  String get changeTheModel;
  String get changeModel;
  String modelGone(String provider, String model);
  String thinking(String step, int seconds);
  String get talk;
  String get backToTyping;
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
  String get undo;
  String noteSubtitle(String kind, String updated);

  // Settings.
  String get provider;
  String get model;
  String modelHelper(String fallback);
  String get refreshModels;
  String get saveModel;
  String get modelSaved;
  String get notesFolder;
  String get checkForUpdates;
  String get logOut;
  String get logOutExplained;
  String get language;
  String languageName(AppLanguage language);
  String get theme;

  /// The app and its version; a development build has none.
  String versionLine(String version);
  String get archive;
  String get pickNote;
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
  String get whisperExplained;
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
  String get apiKey => 'API key';
  @override
  String get pasteKeyFirst => 'Paste the key first.';
  @override
  String get checkConnection => 'Check the connection and try again.';
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
  String get stop => 'Stop';
  @override
  String get changeTheModel => 'Change the model';
  @override
  String get changeModel => 'Change model';
  @override
  String modelGone(String provider, String model) =>
      '$provider no longer offers $model. Pick another model.';
  @override
  String thinking(String step, int seconds) => '$step… $seconds s';
  @override
  String get talk => 'Talk';
  @override
  String get backToTyping => 'Back to typing';
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
  String get undo => 'Undo';
  @override
  String noteSubtitle(String kind, String updated) => '$kind · updated $updated';

  @override
  String get provider => 'Provider';
  @override
  String get model => 'Model';
  @override
  String modelHelper(String fallback) => 'Pick one or type a name; empty means $fallback';
  @override
  String get refreshModels => 'Refresh the model list';
  @override
  String get saveModel => 'Save model';
  @override
  String get modelSaved => 'Model saved.';
  @override
  String get notesFolder => 'Notes folder';
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
  String get archive => 'Archive';
  @override
  String get pickNote => 'Pick a note to read it here.';
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
  String get whisperExplained =>
      'Hears you on this device, offline, in any language. Notelore downloads it once by '
      "itself (about 375 MB); until then voice mode uses the device's recognizer.";
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
  String get syncSection => 'Sync and files';
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
  String get apiKey => 'API anahtarı';
  @override
  String get pasteKeyFirst => 'Önce anahtarı yapıştır.';
  @override
  String get checkConnection => 'Bağlantını kontrol edip yeniden dene.';
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
      'ChatGPT Plus veya Pro planını kullanır: ayrıca ücret yok, planının limitleri '
          'içinde. Şimdilik yalnızca masaüstünde.',
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
      'Create Key’e tıkla, notelore gibi bir ad ver ve anahtarı kopyala.',
      'Anahtarı aşağıya yapıştır (sk-ant- ile başlar).',
    ],
    'openai' => [
      'OpenAI Platform’a giriş yap.',
      'Create new secret key’e tıkla, bir ad ver ve anahtarı kopyala.',
      'Anahtarı aşağıya yapıştır (sk- ile başlar).',
    ],
    'gemini' => [
      'Google AI Studio’ya giriş yap.',
      'Create API key’e tıkla ve anahtarı kopyala.',
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
  String get stop => 'Durdur';
  @override
  String get changeTheModel => 'Modeli değiştir';
  @override
  String get changeModel => 'Model değiştir';
  @override
  String modelGone(String provider, String model) =>
      '$provider artık $model modelini sunmuyor. Başka bir model seç.';
  @override
  String thinking(String step, int seconds) => '$step… $seconds sn';
  @override
  String get talk => 'Sesli konuş';
  @override
  String get backToTyping => 'Yazmaya dön';
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
  String modelHelper(String fallback) => 'Birini seç ya da bir ad yaz; boş bırakırsan $fallback';
  @override
  String get refreshModels => 'Model listesini yenile';
  @override
  String get saveModel => 'Modeli kaydet';
  @override
  String get modelSaved => 'Model kaydedildi.';
  @override
  String get notesFolder => 'Notlar klasörü';
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
  String get archive => 'Arşiv';
  @override
  String get pickNote => 'Okumak için bir not seç.';
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
  String get whisperExplained =>
      'Seni bu cihazda, internetsiz ve her dilde duyar. Notelore onu bir kez kendisi indirir '
      '(yaklaşık 375 MB); o zamana kadar sesli mod cihazın ses tanımasını kullanır.';
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
  String get syncSection => 'Eşitleme ve dosyalar';
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
