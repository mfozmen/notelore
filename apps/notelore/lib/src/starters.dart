/// The first-run starter pool (#577): five reliable kinds of turn, each with
/// twenty subjects and five variations, so there are 500 per language. Every
/// one works on an empty notes folder; none needs a web lookup, an existing
/// note, or the collection path.
library;

const _enPlaces = [
  'the library',
  'the post office',
  'the bank',
  'the pharmacy',
  'the bakery',
  'the gym',
  'the pool',
  'the museum',
  'the town hall',
  'the train station',
  'the market',
  'the park',
  'the clinic',
  'the dentist',
  'the garage',
  'the hardware store',
  'the bookstore',
  'the cafe',
  'the restaurant',
  'the office',
];

const _enDays = ['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays'];

const _enSubjects = [
  'the hallway',
  'the kitchen',
  'the bedroom',
  'the living room',
  'the front door',
  'the bathroom',
  'the study',
  'the dining room',
  'the kitchen cabinets',
  'the stairwell',
  'the garden shed',
  'the balcony wall',
  'the bookshelf',
  'the window frames',
  'the back door',
  'the utility room',
  'the guest room',
  'the ceiling',
  'the garden bench',
  'the fence',
];

const _enChoices = [
  'the pale blue because it is brighter',
  'the warm white because it is calmer',
  'the soft green because it matches the plants',
  'the light grey because it hides marks',
  'the deep teal because it feels warmer',
];

const _enActions = [
  'call the dentist',
  'water the plants',
  'take the cake out',
  'book the ferry',
  'renew the insurance',
  'call Mom',
  'check the tyre pressure',
  'pay the electricity bill',
  'collect the parcel',
  'email the landlord',
  'take the bins out',
  'refill the prescription',
  'clean the filter',
  'charge the drill',
  'buy dog food',
  'return the library book',
  'confirm the booking',
  'ring the plumber',
  'send the invoice',
  'pack the suitcase',
];

const _enWhens = [
  'on Monday at 09:00',
  'on Tuesday at 10:30',
  'on Friday at 18:00',
  'on Saturday at 11:00',
  'tomorrow at 08:00',
];

const _enTasks = [
  'renew the insurance',
  'book the ferry',
  'clean the gutters',
  'fix the fence',
  'order the tiles',
  'call the plumber',
  'pay the deposit',
  'send the forms',
  'buy the paint',
  'book the campsite',
  'replace the filter',
  'sort the receipts',
  'water the plants',
  'cancel the subscription',
  'update the address',
  'check the boiler',
  'return the parcel',
  'submit the meter reading',
  'buy a new lock',
  'plan the route',
];

const _enDues = ['15 November', '1 June', 'the end of the month', 'Friday', 'next Monday'];

const _enProjects = [
  'build a birdhouse',
  'repair the garden gate',
  'paint the hallway',
  'plant a herb box',
  'organise the bookshelf',
  'replace the shed roof',
  'install a bike rack',
  'clean the gutters',
  'frame the old map',
  'sew new curtains',
  'sand the table',
  'tile the bathroom',
  'fix the fence',
  'hang the shelves',
  'clear the garage',
  'prune the hedge',
  'build a window seat',
  'repair the balcony rail',
  'paint the front door',
  'make a compost bin',
];

const _enDetails = [
  'this weekend',
  'before the end of the month',
  'with the kids',
  'without spending much',
  'one step at a time',
];

const _trPlaces = [
  'kütüphane',
  'postane',
  'banka',
  'eczane',
  'fırın',
  'spor salonu',
  'havuz',
  'müze',
  'belediye',
  'tren istasyonu',
  'pazar',
  'park',
  'klinik',
  'dişçi',
  'tamirci',
  'hırdavatçı',
  'kitapçı',
  'kafe',
  'lokanta',
  'ofis',
];

const _trDays = ['pazartesi', 'salı', 'çarşamba', 'perşembe', 'cuma'];

const _trSubjects = [
  'Koridor',
  'Mutfak',
  'Yatak odası',
  'Oturma odası',
  'Ön kapı',
  'Banyo',
  'Çalışma odası',
  'Yemek odası',
  'Mutfak dolapları',
  'Merdiven boşluğu',
  'Bahçe kulübesi',
  'Balkon duvarı',
  'Kitaplık',
  'Pencere çerçeveleri',
  'Arka kapı',
  'Kiler',
  'Misafir odası',
  'Tavan',
  'Bahçe bankı',
  'Çit',
];

const _trChoices = [
  'soluk maviyi seçtik, daha aydınlık duruyor',
  'sıcak beyazı seçtik, daha sakin duruyor',
  'yumuşak yeşili seçtik, bitkilerle uyumlu',
  'açık griyi seçtik, lekeleri gizliyor',
  'koyu turkuazı seçtik, daha sıcak hissettiriyor',
];

const _trActions = [
  'annemi aramamı',
  'çiçekleri sulamayı',
  'keki fırından almayı',
  'vapuru ayırtmayı',
  'sigortayı yenilemeyi',
  'dişçiyi aramamı',
  'lastik basıncını kontrol etmeyi',
  'elektrik faturasını ödemeyi',
  'kargoyu almayı',
  'ev sahibine yazmayı',
  'çöpü çıkarmayı',
  'reçeteyi yeniletmeyi',
  'filtreyi temizlemeyi',
  'matkabı şarj etmeyi',
  'köpek maması almayı',
  'kütüphane kitabını iade etmeyi',
  'rezervasyonu onaylamayı',
  'tesisatçıyı aramayı',
  'faturayı göndermeyi',
  'bavulu hazırlamayı',
];

const _trWhens = [
  "Pazartesi 09.00'da",
  "Salı 10.30'da",
  "Cuma 18.00'de",
  "Cumartesi 11.00'de",
  "Yarın 08.00'de",
];

const _trTasks = [
  'sigortayı yenile',
  'vapuru ayırt',
  'olukları temizle',
  'çiti onar',
  'fayansları sipariş et',
  'tesisatçıyı ara',
  'depozitoyu öde',
  'formları gönder',
  'boyayı al',
  'kamp yerini ayırt',
  'filtreyi değiştir',
  'fişleri ayır',
  'çiçekleri sula',
  'aboneliği iptal et',
  'adresi güncelle',
  'kazanı kontrol ettir',
  'kargoyu iade et',
  'sayaç okumasını bildir',
  'yeni kilit al',
  'rotayı planla',
];

const _trDues = [
  "15 Kasım'a kadar",
  "1 Haziran'a kadar",
  'ay sonuna kadar',
  "Cuma'ya kadar",
  "gelecek Pazartesi'ye kadar",
];

const _trProjects = [
  'kuş evi yap',
  'bahçe kapısını onar',
  'koridoru boya',
  'saksıda ot yetiştir',
  'kitaplığı düzenle',
  'kulübe çatısını değiştir',
  'bisiklet askısı tak',
  'olukları temizle',
  'eski haritayı çerçevele',
  'yeni perdeler dik',
  'masayı zımparala',
  'banyoyu fayansla',
  'çiti tamir et',
  'rafları as',
  'garajı boşalt',
  'çitleri buda',
  'pencere minderi yap',
  'balkon korkuluğunu onar',
  'ön kapıyı boya',
  'kompost kutusu yap',
];

const _trDetails = [
  'bu hafta sonu',
  'ay sonundan önce',
  'çocuklarla',
  'fazla harcamadan',
  'adım adım',
];

/// 500 English starters: 20 subjects × 5 variations for each of five kinds.
final List<String> starterExamplesEn = List.unmodifiable([
  for (final place in _enPlaces)
    for (final day in _enDays) 'Save this: $place is closed on $day.',
  for (final subject in _enSubjects)
    for (final choice in _enChoices) 'For $subject, we chose $choice.',
  for (final action in _enActions)
    for (final when in _enWhens) 'Remind me to $action $when.',
  for (final task in _enTasks)
    for (final due in _enDues) 'Add a todo: $task by $due.',
  for (final project in _enProjects)
    for (final detail in _enDetails) 'New project: $project $detail.',
]);

/// 500 Turkish starters, the same five kinds as [starterExamplesEn].
final List<String> starterExamplesTr = List.unmodifiable([
  for (final place in _trPlaces)
    for (final day in _trDays) 'Bunu not al: $place $day günleri kapalı.',
  for (final subject in _trSubjects)
    for (final choice in _trChoices) '$subject için $choice.',
  for (final action in _trActions)
    for (final when in _trWhens) '$when $action hatırlat.',
  for (final task in _trTasks)
    for (final due in _trDues) 'Yapılacak: $due $task.',
  for (final project in _trProjects)
    for (final detail in _trDetails) 'Yeni proje: $project $detail.',
]);
