"""The scenarios preference training samples on (#607): built like the training
and held-out ones (`scenarios.py`, `holdout.py`), from notes, items and
sentences of their own, so a model is sampled on what it never trained on and
the held-out eval stays unseen. `main` checks that no note title, message or
listed item appears in the training or the held-out scenarios, nor a message
or note title of `eval/cases.json` (`scenarios.check`), and that every kind
has at least 15 cases.

    python tool/train/dpo_set.py [out.json]      (default .dev-home/train/scenarios-dpo.json)

Standard library only; the same seed always writes the same file.
"""

import collections
import json
import random
import sys
from pathlib import Path

import holdout
import scenarios

SEED = 607

COLLECTIONS = [
    ("en", "Graphic Novels to Read", "Maus — Art Spiegelman",
     ["Persepolis", "Blankets", "Fun Home", "Ghost World", "Habibi"],
     ["Graphic novel to read: {x}.", "Add {x} to my graphic novels."]),
    ("tr", "Okunacak Şiir Kitapları", "Cemal Süreya — Üvercinka",
     ["Turgut Uyar — Dünyanın En Güzel Arabistanı", "Edip Cansever — Yerçekimli Karanfil",
      "Attilâ İlhan — Ben Sana Mecburum", "Sezai Karakoç — Monna Rosa", "Orhan Veli — Garip"],
     ["Okunacak şiir kitabı: {x}.", "Şiir listeme ekle: {x}."]),
    ("en", "Anime Series to Watch", "Cowboy Bebop",
     ["Mushishi", "Frieren", "Vinland Saga", "Haikyu", "Ping Pong the Animation"],
     ["Anime to watch: {x}.", "Put {x} on my anime list."]),
    ("tr", "Gidilecek Konserler", "Mor ve Ötesi",
     ["Duman", "Teoman", "Kalben", "Can Bonomo", "Adamlar"],
     ["Gitmek istediğim konser: {x}.", "Konser listesine {x} ekle."]),
    ("en", "Hot Sauces to Try", "Cholula",
     ["Valentina", "El Yucateco", "Sriracha", "Frank's RedHot", "Tapatío"],
     ["Hot sauce to try: {x}.", "Add {x} to the hot sauces."]),
    ("tr", "Denenecek Kahvaltı Tarifleri", "Menemen",
     ["Çılbır", "Kaygana", "Pişi", "Gözleme", "Muhlama"],
     ["Kahvaltıda denemek istediğim: {x}.", "Kahvaltı tariflerine ekle: {x}."]),
    ("en", "National Parks to Visit", "Yosemite",
     ["Banff", "Torres del Paine", "Plitvice Lakes", "Zion", "Kruger"],
     ["National park to visit: {x}.", "Add {x} to the national parks."]),
    ("tr", "Oynanacak Kutu Oyunları", "Monopoly",
     ["Codenames", "Dixit", "Splendor", "Pandemic", "7 Wonders"],
     ["Oynamak istediğim kutu oyunu: {x}.", "Kutu oyunları listesine {x} ekle."]),
    ("en", "Housewarming Gift Ideas", "A cast-iron pan for Nora",
     ["a doormat for Felix", "a candle set for Priya", "a cheese board for Omar", "a bonsai for Ines"],
     ["Housewarming gift idea: {x}.", "Gift for a housewarming: {x}."]),
    ("tr", "Doğum Günü Hediyeleri", "Ablama bir parfüm",
     ["dedeme bir radyo", "kuzenime bir kaykay", "teyzeme bir örgü seti", "patronuma bir dolma kalem"],
     ["Doğum günü hediyesi fikri: {x}.", "Hediyelere ekle: {x}."]),
    ("en", "Jazz Albums to Hear", "Kind of Blue — Miles Davis",
     ["A Love Supreme", "Time Out", "Mingus Ah Um", "Moanin'", "Waltz for Debby"],
     ["Jazz album to hear: {x}.", "Add {x} to the jazz albums."]),
    ("tr", "Gezilecek Müzeler", "İstanbul Modern",
     ["Pera Müzesi", "Rahmi M. Koç Müzesi", "Zeugma Mozaik Müzesi", "Anıtkabir", "Sakıp Sabancı Müzesi"],
     ["Gezmek istediğim müze: {x}.", "Müzeler listesine ekle: {x}."]),
    ("en", "Online Courses to Take", "CS50",
     ["Machine Learning by Andrew Ng", "Learning How to Learn", "The Science of Well-Being",
      "Introduction to Psychology", "Financial Markets"],
     ["Course I want to take: {x}.", "Add {x} to my online courses."]),
    ("tr", "Denenecek Restoranlar", "Kantin",
     ["Lokanta Maya", "Asmalı Cavit", "Yeni Lokanta", "Datlı Maya", "Meze by Lemon Tree"],
     ["Denenecek restoran: {x}.", "Restoranlar listesine {x} ekle."]),
    ("en", "Trails to Hike", "Tour du Mont Blanc",
     ["the West Highland Way", "the Camino Portugués", "the Kungsleden", "the Inca Trail", "the Cinque Terre path"],
     ["Trail I want to hike: {x}.", "Add {x} to my trails."]),
]

PROJECTS = [
    ("en", "Garage Workshop", ["The workbench is along the back wall."], [("saw", "Bosch table saw")],
     ["Install the pegboard"], ["Ventilation needs a second fan.", "Pavel checked the electrics."],
     [("dust extractor", "Festool CT", "it is quiet"), ("lighting", "LED strips", "they use little power")],
     ["Buy a fire extinguisher", "Seal the concrete floor"],
     ["I installed the pegboard in the garage workshop.", "Garage workshop: the pegboard is up."],
     "Garage workshop: I swept out the sawdust today.", "sawdust"),
    ("en", "Charity Bake Sale", ["The sale is at the primary school."], [("venue", "School gym")],
     ["Ask parents for cakes"], ["Proceeds go to the animal shelter.", "Twenty volunteers signed up."],
     [("cash box", "Metal tin", "it locks"), ("payment", "Card reader", "fewer coins")],
     ["Make price signs", "Borrow folding tables"],
     ["I asked the parents for cakes for the bake sale.", "Charity bake sale: the parents are asked for cakes."],
     "Charity bake sale: I designed a poster for the school board.", "poster"),
    ("en", "Japan Trip", ["We fly to Osaka in April."], [("rail pass", "7-day JR Pass")],
     ["Apply for travel insurance"], ["Hotels are booked in Kyoto and Tokyo.", "Ryo will show us around Nara."],
     [("luggage", "Carry-on only", "trains are crowded"), ("phone plan", "eSIM", "it is cheaper")],
     ["Learn basic Japanese phrases", "Exchange some yen"],
     ["I got the travel insurance for the Japan trip.", "Japan trip: travel insurance is sorted."],
     "Japan trip: I made a list of ramen shops in Osaka.", "ramen"),
    ("en", "Wedding Speech", ["The wedding is on 20 March 2027."], [("length", "Five minutes")],
     ["Collect stories from Ben's friends"], ["Ben hates long toasts.", "The groom's sister speaks first."],
     [("opening", "Camping story", "everyone laughs"), ("closing", "Short toast", "it ends on a high")],
     ["Rehearse in front of Mia", "Print cue cards"],
     ["I collected the stories from Ben's friends.", "Wedding speech: stories from Ben's friends are collected."],
     "Wedding speech: I had my suit tailored for the day.", "suit"),
    ("tr", "Tekne Restorasyonu", ["Tekne Bodrum'da karaya çekili."], [("vernik", "Marin vernik")],
     ["Eski boyayı kazı"], ["Omurga sağlam çıktı.", "Yelkenler İzmir'de dikilecek."],
     [("motor", "Yanmar dizel", "parçası kolay bulunuyor"), ("güverte", "Tik ağacı", "suya dayanıklı")],
     ["Halatları yenile", "Sigorta poliçesini çıkar"],
     ["Eski boyayı kazıdım, tekne için o iş tamam.", "Tekne restorasyonu: eski boya kazındı."],
     "Tekne restorasyonu: pervaneyi parlattım.", "pervane"),
    ("tr", "Mahalle Kütüphanesi", ["Kütüphane muhtarlığın alt katında."], [("raf", "Metal raf")],
     ["Gönüllülere çizelge hazırla"], ["Şimdiden 400 kitap toplandı.", "Açılış cumartesi öğleden sonra."],
     [("kayıt sistemi", "Excel tablosu", "herkes kullanabiliyor"), ("açılış saati", "Hafta sonları", "gönüllüler müsait")],
     ["Tabela astır", "Okuma köşesine minder al"],
     ["Gönüllülerin çizelgesini hazırladım.", "Mahalle kütüphanesi: gönüllü çizelgesi hazır, o iş tamam."],
     "Mahalle kütüphanesi: ilk bağış kolisi geldi.", "bağış"),
    ("tr", "Seramik Atölyesi", ["Atölye Kadıköy'de bir bodrum katında."], [("fırın", "Elektrikli fırın")],
     ["Çark siparişi ver"], ["İlk dönem sekiz öğrenci kaydoldu.", "Kil Çanakkale'den geliyor."],
     [("sır", "Kurşunsuz sır", "daha güvenli"), ("ders günü", "Çarşamba akşamı", "çalışanlara uyuyor")],
     ["Raf sistemini kur", "Sosyal medya hesabı aç"],
     ["Çarkın siparişini verdim, atölye için o iş tamam.", "Seramik atölyesi: çark sipariş edildi."],
     "Seramik atölyesi: ilk vazolar fırından sağlam çıktı.", "vazo"),
    ("tr", "Yayla Evi Tadilatı", ["Ev Rize'de, 1800 metrede."], [("çatı", "Bakır kaplama")],
     ["Ustaya keşif yaptır"], ["Yol Mayıs'a kadar kapalı.", "Komşu Hasan amca anahtarı tutuyor."],
     [("ısınma", "Odun sobası", "elektrik sık kesiliyor"), ("pencere", "Çift cam", "kış çok sert")],
     ["Su deposunu temizlet", "Jeneratör al"],
     ["Ustaya keşfi yaptırdım, yayla evi için o iş tamam.", "Yayla evi tadilatı: ustanın keşfi yapıldı."],
     "Yayla evi tadilatı: bahçedeki çitleri boyadım.", "çit"),
]

TOPICS = [
    ("en", "Home Insurance", ["The policy renews on 1 March."], "The claim for the roof leak was approved.", "When does the policy renew?", "1 March"),
    ("tr", "Bütçe Takibi", ["Kira aylık bütçenin yarısı."], "Elektrik faturası bu ay 900 lira.", "Kira bütçenin ne kadarı?", "yarısı"),
    ("en", "Sleep Tracking", ["I sleep about seven hours a night."], "No coffee after 2 pm improved my sleep.", "How many hours do I sleep?", "seven"),
    ("tr", "Papağanımız Limon", ["Limon'un kanat kesimi Şubat'ta."], "Limon artık birkaç kelime söylüyor.", "Limon'un kanat kesimi ne zaman?", "Şubat"),
    ("en", "Volunteer Shifts", ["I help at the food bank on Wednesdays."], "The food bank moved to a bigger warehouse.", "When do I help at the food bank?", "Wednesday"),
]

NEW_PROJECTS = [
    ("en", "New project: convert the loft into a guest room.", r"^projects/[^/]*(loft|guest)[^/]*\.md$", None),
    ("en", "Starting a project to build a backyard pizza oven from bricks.", r"^projects/[^/]*(pizza|oven)[^/]*\.md$", "brick"),
    ("en", "New project: a YouTube channel about vintage watches.", r"^projects/[^/]*(youtube|channel|watch)[^/]*\.md$", "vintage"),
    ("en", "I'm starting a project to sew a quilt for my niece.", r"^projects/[^/]*quilt[^/]*\.md$", "niece"),
    ("en", "New project: a mobile game for learning the periodic table.", r"^projects/[^/]*(game|periodic)[^/]*\.md$", "periodic"),
    ("en", "Kicking off a project to restore my grandfather's motorcycle.", r"^projects/[^/]*(motor|grandfather)[^/]*\.md$", None),
    ("en", "New project: organise a neighbourhood street party in June.", r"^projects/[^/]*(street|party)[^/]*\.md$", "June"),
    ("en", "I want to start a project to run a half marathon in spring.", r"^projects/[^/]*(half|marathon)[^/]*\.md$", None),
    ("tr", "Yeni proje: bahçeye bir sera kuracağım.", r"^projects/[^/]*sera[^/]*\.md$", None),
    ("tr", "Bir proje başlatıyorum: dedemin anılarını ses kayıtlarıyla saklayacağım.", r"^projects/[^/]*(ani|dede)[^/]*\.md$", "ses"),
    ("tr", "Yeni proje: köpeğim için bir kulübe yapacağım.", r"^projects/[^/]*(kopek|kulube)[^/]*\.md$", None),
    ("tr", "Yeni bir proje: üniversite arkadaşlarımla bir mezuniyet buluşması düzenleyeceğim.", r"^projects/[^/]*(mezun|bulusma)[^/]*\.md$", None),
    ("tr", "Proje başlatıyorum: eski bir minibüsü karavana çevireceğim.", r"^projects/[^/]*(karavan|minibus)[^/]*\.md$", None),
    ("tr", "Yeni proje: mahalle parkına oyun alanı için imza toplayacağım.", r"^projects/[^/]*(park|oyun|imza)[^/]*\.md$", "imza"),
    ("tr", "Yeni bir proje: illüstrasyonlarımı kendi sitemde satacağım.", r"^projects/[^/]*(illustrasyon|site|satis)[^/]*\.md$", None),
]

NEW_LISTS = [
    ("en", "Cheese to try: a Comté aged 24 months.", r"^topics/[^/]*chees[^/]*\.md$", "Comté"),
    ("en", "Podcast to listen to: Reply All.", r"^topics/[^/]*podcast[^/]*\.md$", "Reply All"),
    ("en", "Tea to try: a Taiwanese oolong.", r"^topics/[^/]*tea[^/]*\.md$", "oolong"),
    ("en", "Houseplant to get: a string of pearls.", r"^topics/[^/]*plant[^/]*\.md$", "pearls"),
    ("tr", "Dinlenecek albüm: Sezen Aksu'nun Firuze'si.", r"^topics/[^/]*(album|muzik)[^/]*\.md$", "Firuze"),
    ("tr", "İzlenecek dizi: Leyla ile Mecnun.", r"^topics/[^/]*dizi[^/]*\.md$", "Leyla ile Mecnun"),
    ("tr", "Denenecek peynir: Kars gravyeri.", r"^topics/[^/]*peynir[^/]*\.md$", "gravyer"),
    ("tr", "Katılmak istediğim atölye: ebru sanatı.", r"^topics/[^/]*(atolye|kurs)[^/]*\.md$", "ebru"),
]

FIRST_OF_KIND = [
    ("en", "I'm reading Lonesome Dove these days.", r"^topics/[^/]*book[^/]*\.md$", "Lonesome Dove"),
    ("en", "Watching The Third Man tonight.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Third Man"),
    ("en", "Recipe idea: lamb tagine with apricots.", r"^topics/[^/]*recipe[^/]*\.md$", "tagine"),
    ("en", "I'd love to see the Atacama Desert one day.", r"^topics/[^/]*(place|visit|travel)[^/]*\.md$", "Atacama"),
    ("tr", "Şu sıralar Huzursuzluk'u okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Huzursuzluk"),
    ("tr", "Bu akşam Kelebekler filmini izleyeceğim.", r"^topics/[^/]*film[^/]*\.md$", "Kelebekler"),
    ("tr", "Tarif fikri: fırında levrek.", r"^topics/[^/]*tarif[^/]*\.md$", "levrek"),
    ("tr", "Bir gün Hasankeyf'e gitmek istiyorum.", r"^topics/[^/]*(gez|yer)[^/]*\.md$", "Hasankeyf"),
]

MIXED_LISTS = [
    ("en", {"books": "Shelf of Unread Books", "films": "Films for Rainy Days", "recipes": "Weeknight Cooking", "places": "Places on My Map"}, [
        ("Started reading Babel by R. F. Kuang.", "books", "Babel"),
        ("Film for a rainy evening: Amélie.", "films", "Amélie"),
        ("Weeknight dinner idea: sesame noodles.", "recipes", "sesame noodles"),
        ("I want to go to Zanzibar one day.", "places", "Zanzibar"),
    ]),
    ("tr", {"books": "Kitap Rafım", "films": "Film Arşivim", "recipes": "Pratik Yemekler", "places": "Görülecek Yerler"}, [
        ("Dün Saatleri Ayarlama Enstitüsü'ne başladım.", "books", "Saatleri Ayarlama"),
        ("Hafta sonu izlenecek: Selvi Boylum Al Yazmalım.", "films", "Selvi Boylum"),
        ("Pratik yemek fikri: patlıcanlı makarna.", "recipes", "patlıcanlı makarna"),
        ("Görmek istediğim yer: İshak Paşa Sarayı.", "places", "İshak Paşa"),
    ]),
]

TWIN_LISTS = [
    ("en", "Currently Reading", "To Read Next Year", [
        ("Just opened The Left Hand of Darkness.", True, "Left Hand of Darkness"),
        ("Next year I want to read War and Peace.", False, "War and Peace"),
    ]),
    ("tr", "Elimdeki Kitaplar", "Bir Gün Okunacaklar", [
        ("Şu sıralar Serenad'ı okuyorum.", True, "Serenad"),
        ("Bir gün Anayurt Oteli'ni okumak istiyorum.", False, "Anayurt Oteli"),
    ]),
]

UNCLEAR = [
    ("en", "Put that one in."), ("en", "File it where it goes."), ("en", "Do what I said before."),
    ("en", "Fix the other entry."), ("en", "Add those to it."), ("en", "Cross that out."),
    ("en", "Keep this somewhere."), ("en", "Use the second option."),
    ("tr", "Bunu da oraya yaz."), ("tr", "Öbürüne ekle."), ("tr", "Dediğim gibi yap."),
    ("tr", "Şunu düzelt."), ("tr", "Onu da hallet."), ("tr", "Bunu tamamlandı yap."),
    ("tr", "Şunu bir kenara yaz."),
]

# From 2026-10-18 14:00, a Sunday.
PLANS = [
    ("en", "Tomorrow at 15:00 I'm meeting my accountant.", "2026-10-19 15:00"),
    ("en", "On Wednesday I'm going to a wine tasting.", "2026-10-21"),
    ("en", "Friday at 21:00 I'm going to a stand-up show.", "2026-10-23 21:00"),
    ("en", "On 12 November I have a flight to Madrid.", "2026-11-12"),
    ("en", "Saturday morning I'm helping Lea move house.", "2026-10-24"),
    ("en", "Thursday at 12:30 I'm having lunch with my sister.", "2026-10-22 12:30"),
    ("en", "On 4 December I'm going to a Christmas market.", "2026-12-04"),
    ("en", "Monday at 7 I'm going for a swim.", "2026-10-19 07:00"),
    ("tr", "Yarın saat 16'da veli toplantısına gideceğim.", "2026-10-19 16:00"),
    ("tr", "Perşembe akşamı halı saha maçım var.", "2026-10-22"),
    ("tr", "Cumartesi saat 11'de semt pazarına gideceğim.", "2026-10-24 11:00"),
    ("tr", "20 Kasım'da Antalya'ya gideceğim.", "2026-11-20"),
    ("tr", "Çarşamba günü kuzenimin nişanı var.", "2026-10-21"),
    ("tr", "Salı saat 13'te bankaya gideceğim.", "2026-10-20 13:00"),
    ("tr", "Cuma günü annemi ziyaret edeceğim.", "2026-10-23"),
]

REMINDERS = [
    ("en", "Garage Workshop", "project", "Remind me tomorrow at 10 to pick up the plywood for the garage workshop.", "2026-10-19 10:00", "plywood"),
    ("en", "Charity Bake Sale", "project", "Bake sale: remind me in 2 hours to email the head teacher.", "2026-10-18 16:00", "teacher"),
    ("en", "Japan Trip", "project", "Remind me on Thursday at 20:00 to check the flights for the Japan trip.", "2026-10-22 20:00", "flight"),
    ("en", "Wedding Speech", "project", "Wedding speech: remind me on 15 March 2027 to do a final run-through.", "2027-03-15", "run-through"),
    ("en", "Home Insurance", "topic", "Remind me in 20 minutes to upload the claim photos.", "2026-10-18 14:20", "photo"),
    ("en", "Sleep Tracking", "topic", "Remind me tonight at 22:30 to put my phone away.", "2026-10-18 22:30", "phone"),
    ("en", "Volunteer Shifts", "topic", "Remind me on Wednesday at 8 to bring gloves to the food bank.", "2026-10-21 08:00", "glove"),
    ("tr", "Tekne Restorasyonu", "project", "Tekne için yarın 8'de zımpara kâğıdı almamı hatırlat.", "2026-10-19 08:00", "zımpara"),
    ("tr", "Mahalle Kütüphanesi", "project", "Mahalle kütüphanesi: cuma 15'te muhtarı aramamı hatırlat.", "2026-10-23 15:00", "muhtar"),
    ("tr", "Seramik Atölyesi", "project", "Seramik atölyesi için 1 saat sonra kil siparişine bakmamı hatırlat.", "2026-10-18 15:00", "kil"),
    ("tr", "Yayla Evi Tadilatı", "project", "Yayla evi: 1 Mayıs'ta yolun açılıp açılmadığına bakmamı hatırlat.", "2027-05-01", "yol"),
    ("tr", "Bütçe Takibi", "topic", "Bütçe için 10 dakika sonra faturaları girmemi hatırlat.", "2026-10-18 14:10", "fatura"),
    ("tr", "Papağanımız Limon", "topic", "Limon'u perşembe 9'da veterinere götürmemi hatırlat.", "2026-10-22 09:00", "veteriner"),
    # A reminder in one language for a note in the other.
    ("en", "Tekne Restorasyonu", "project", "Remind me on Saturday at 9 to call the sailmaker in İzmir.", "2026-10-24 09:00", "sail"),
    ("tr", "Japan Trip", "project", "Japonya gezisi için yarın 12'de vize fotoğrafı çektirmemi hatırlat.", "2026-10-19 12:00", "fotoğraf"),
]

# (message lang, note title, its kind, message, kind of the case, the tool it needs, a word the note keeps).
CROSS = [
    ("en", "Tekne Restorasyonu", "project", "Boat restoration: the hull got its first coat of antifouling.", "filing", "add_note_entry", "antifouling"),
    ("en", "Mahalle Kütüphanesi", "project", "For the neighbourhood library we picked wooden shelves instead, they look friendlier.", "decision", "record_decision", "wooden"),
    ("en", "Seramik Atölyesi", "project", "Ceramics studio: add a todo to buy aprons.", "todo", "add_todo", "apron"),
    ("en", "Yayla Evi Tadilatı", "project", "The builder did the survey of the highland house.", "todo-done", "complete_todo", None),
    ("en", "Bütçe Takibi", "topic", "Budget: the water bill was 350 lira this month.", "filing", "add_note_entry", "350"),
    ("en", "Papağanımız Limon", "topic", "Limon learned to whistle a tune.", "filing", "add_note_entry", "whistle"),
    ("en", "Tekne Restorasyonu", "project", "Boat restoration: the old paint is scraped off.", "todo-done", "complete_todo", None),
    ("en", "Mahalle Kütüphanesi", "project", "Add a todo to the neighbourhood library: find a second key.", "todo", "add_todo", "key"),
    ("tr", "Garage Workshop", "project", "Garaj atölyesi: tezgâhın üstüne raf taktık.", "filing", "add_note_entry", "raf"),
    ("tr", "Charity Bake Sale", "project", "Kermes için velilerden kek istedim, o iş tamam.", "todo-done", "complete_todo", None),
    ("tr", "Japan Trip", "project", "Japonya gezisi: konaklama için ryokan seçtik, daha otantik.", "decision", "record_decision", "ryokan"),
    ("tr", "Wedding Speech", "project", "Düğün konuşması için yapılacak: mikrofonu ayarla.", "todo", "add_todo", "mikrofon"),
    ("tr", "Home Insurance", "topic", "Konut sigortası: deprem teminatı da eklendi.", "filing", "add_note_entry", "deprem"),
    ("tr", "Sleep Tracking", "topic", "Uyku: bu hafta ortalama yedi buçuk saat uyudum.", "filing", "add_note_entry", "buçuk"),
    ("tr", "Volunteer Shifts", "topic", "Gıda bankası gönüllülüğüm artık cumartesi sabahları.", "filing", "add_note_entry", "cumartesi"),
    ("tr", "Garage Workshop", "project", "Garaj atölyesine delikli panoyu taktım.", "todo-done", "complete_todo", None),
]

CONTRAST = []

CHAT = [
    ("en", "thanks, that's perfect"), ("en", "awesome, thank you"), ("en", "all good, thanks"), ("en", "lovely, cheers"),
    ("en", "that's it for today"), ("en", "much appreciated"), ("en", "ok great"), ("en", "thanks again"),
    ("tr", "teşekkürler, harika oldu"), ("tr", "sağ olun"), ("tr", "tamamdır"), ("tr", "çok makbule geçti"),
    ("tr", "eyvallah, bu kadar"), ("tr", "harikasın, teşekkürler"), ("tr", "iyi ki varsın"),
]

DISTRACTORS = scenarios.DISTRACTORS
RECOVERIES = len(COLLECTIONS)
COLLECTION_PICKS = 3
NO_TOOL_WORDS = scenarios.NO_TOOL_WORDS

MIN_PER_KIND = 15


def main(argv):
    out = Path(next((a for a in argv if not a.startswith("--")), scenarios.ROOT / ".dev-home/train/scenarios-dpo.json"))
    dpo = scenarios.cases(random.Random(SEED), sys.modules[__name__])
    scenarios.check(dpo)
    holdout.disjoint(dpo, scenarios.cases(random.Random(7)))
    holdout.disjoint(dpo, scenarios.cases(random.Random(holdout.SEED), holdout))
    counts = collections.Counter(c["kind"] for c in dpo)
    thin = {kind: n for kind, n in counts.items() if n < MIN_PER_KIND}
    assert not thin, f"kinds under {MIN_PER_KIND}: {thin}"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dpo, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(dpo)} DPO scenarios -> {out}: {dict(sorted(counts.items()))}")


if __name__ == "__main__":
    main(sys.argv[1:])
