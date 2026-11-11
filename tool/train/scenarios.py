"""Training scenarios for the on-device model's fine-tune (#327).

Writes cases in the eval's format (`packages/notelore_core/lib/src/eval.dart`)
that `notelore_dev distill` plays with a teacher model, keeping only the turns
the scorer passes. Every note, title and sentence here is different from
`eval/cases.json`, so the student is never trained on the exam: `main` checks
that no message or note title overlaps. Each case's workspace also holds other
notes, so it is passed by choosing the right note, and `main` checks that its
expectation names exactly one of them.

    python tool/train/scenarios.py [out.json] [--seed=N]

Standard library only; the same seed always writes the same file.
"""

import json
import random
import re
import sys
import unicodedata
from pathlib import Path

TR_MAP = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")


def slug(title):
    """The note file name Notelore gives a title (store/notes.dart)."""
    text = unicodedata.normalize("NFKD", title.translate(TR_MAP)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


HEADINGS = {
    "en": ("Decisions", "Notes", "Todo"),
    "tr": ("Kararlar", "Notlar", "Yapılacaklar"),
}


def note(title, kind, lang, notes=(), decisions=(), todos=()):
    """A note in the Notelore format: front matter, then the known sections."""
    dec, nts, todo = HEADINGS[lang]
    parts = [
        f"---\ntitle: {title}\nkind: {kind}\ncreated: 2026-09-01\nupdated: 2026-10-01\ntags: []\n---\n# {title}\n"
    ]
    if decisions:
        parts.append(f"\n## {dec}\n" + "".join(f"- 2026-09-10 — **{t}**: {v}.\n" for t, v in decisions))
    if notes:
        parts.append(f"\n## {nts}\n" + "".join(f"- 2026-09-15: {n}\n" for n in notes))
    if todos:
        parts.append(f"\n## {todo}\n" + "".join(f"- [ ] 2026-10-20: {t}\n" for t in todos))
    return "".join(parts)


def path(kind, title):
    return f"{'projects' if kind == 'project' else 'topics'}/{slug(title)}.md"


# Collections: (lang, title, existing item, what is added, sentence templates).
COLLECTIONS = [
    ("tr", "Okuduğum Kitaplar", "Tutunamayanlar — Oğuz Atay",
     ["Sinekli Bakkal", "İnce Memed", "Masumiyet Müzesi", "Kuyucaklı Yusuf", "Aylak Adam", "Bereketli Topraklar Üzerinde"],
     ["{x} kitabına başladım.", "Şimdi {x} okuyorum.", "Elimde {x} var, onu okuyorum."]),
    ("en", "Books I'm Reading", "Klara and the Sun — Kazuo Ishiguro",
     ["The Overstory", "Piranesi", "A Gentleman in Moscow", "Educated", "The Remains of the Day", "Station Eleven"],
     ["Started reading {x}.", "I'm halfway through {x}.", "Currently reading {x}."]),
    ("tr", "İzlenecek Filmler", "Kış Uykusu",
     ["Ahlat Ağacı", "Babam ve Oğlum", "Uzak", "Eşkıya", "Bir Zamanlar Anadolu'da"],
     ["İzlemek istediğim bir film: {x}.", "{x} filmini izlemek istiyorum.", "Listeme {x} filmini ekle."]),
    ("en", "Films to Watch", "Past Lives",
     ["Aftersun", "Drive My Car", "The Zone of Interest", "Anatomy of a Fall", "Columbus"],
     ["Film to watch later: {x}.", "Add {x} to my watch list.", "I want to see {x}."]),
    ("en", "Recipes to Try", "Shakshuka with feta",
     ["miso glazed salmon", "pumpkin risotto", "chickpea curry", "lemon ricotta pancakes"],
     ["Recipe to try: {x}.", "Save this recipe idea: {x}."]),
    ("tr", "Denenecek Tarifler", "Fırında karnıyarık",
     ["mercimek köftesi", "zeytinyağlı enginar", "fırın sütlaç", "kuru fasulye"],
     ["Denenecek tarif: {x}.", "Tarif fikri: {x}."]),
    ("tr", "Gidilecek Yerler", "Mardin",
     ["Safranbolu", "Ayvalık", "Kaş", "Datça", "Amasra"],
     ["Bir gün gitmek istediğim yer: {x}.", "Gidilecek yerlere ekle: {x}."]),
    ("en", "Places to Visit", "Lisbon",
     ["Kyoto", "Ljubljana", "Porto", "Tbilisi", "Valparaíso"],
     ["One day I want to visit {x}.", "Add {x} to places to visit."]),
    ("en", "Gift Ideas", "A fountain pen for Dad",
     ["a wool scarf for my sister", "a cookbook for Ali", "a plant pot for Mom"],
     ["Gift idea: {x}.", "Note a gift idea: {x}."]),
    ("en", "Podcasts to Try", "Hardcore History",
     ["Radiolab", "99% Invisible", "Hidden Brain", "Song Exploder"],
     ["Podcast to try: {x}.", "Someone recommended the podcast {x}."]),
    ("tr", "Dinlenecek Albümler", "Kayahan — Benim Şarkılarım",
     ["Gülümse", "Dönence", "Peki Peki Anladık", "Ben Bir Ceviz Ağacıyım"],
     ["Dinlenecek albüm: {x}.", "{x} albümünü dinlemek istiyorum."]),
    ("en", "Board Games to Buy", "Catan",
     ["Wingspan", "Azul", "Ticket to Ride", "Carcassonne"],
     ["Board game to get: {x}.", "Add {x} to the board games list."]),
    ("tr", "Öğrenilecek Konular", "Temel istatistik",
     ["Rust dili", "Gitar akorları", "İspanyolca", "Fotoğraf pozlama"],
     ["Öğrenmek istediğim konu: {x}.", "Öğreneceklerime ekle: {x}."]),
    ("en", "Restaurants to Try", "Mikla",
     ["Neolokal", "Çiya Sofrası", "Karaköy Lokantası", "Aheste"],
     ["Restaurant to try: {x}.", "Heard good things about {x}, I want to eat there."]),
    ("tr", "Okunacak Makaleler", "Attention Is All You Need",
     ["AlphaFold makalesi", "Dropout makalesi", "ResNet makalesi"],
     ["Okunacak makale: {x}.", "Şu makaleyi okumalıyım: {x}."]),
]

# Projects: (lang, title, notes, decisions, todos, facts, new decisions, new todos,
# ways to say the first todo is done, something done that is no todo, a word it leaves).
PROJECTS = [
    ("en", "Garden Shed", ["The shed will be 2 by 3 metres."], [("roof", "Metal sheet")],
     ["Order the timber"], ["The door faces south.", "The neighbour lends us his ladder."],
     [("floor", "Concrete slab", "it lasts longer")], ["Get a building permit"],
     ["I ordered the timber for the garden shed.", "Garden shed: the timber is ordered."],
     "Garden shed: I cleared the old leaves from the site.", "leaves"),
    ("en", "Podcast Launch", ["First episode is about local history."], [("host", "Anchor")],
     ["Record the trailer"], ["The intro music is a short piano piece.", "Episodes come out on Tuesdays."],
     [("microphone", "Shure MV7", "good value")], ["Write the show notes template"],
     ["The podcast trailer is recorded.", "Recorded the trailer for the podcast launch."],
     "Podcast launch: I made a list of five possible guests.", "guests"),
    ("tr", "Düğün Hazırlığı", ["Davetli sayısı 120 kişi."], [("mekan", "Bahçe düğünü")],
     ["Fotoğrafçıyla görüş"], ["Gelinin annesi Ankara'dan gelecek.", "Davetiyeler mavi renkte."],
     [("müzik", "Canlı orkestra", "daha samimi")], ["Gelinliği prova et"],
     ["Fotoğrafçıyla görüştüm, düğün hazırlığındaki o iş bitti.", "Düğün hazırlığı: fotoğrafçı görüşmesi yapıldı."],
     "Düğün hazırlığı: nikah şekerlerini sipariş ettim.", "şeker"),
    ("tr", "Mobil Uygulama", ["İlk sürüm sadece Android için."], [("backend", "Firebase")],
     ["Giriş ekranını tasarla"], ["Kullanıcılar e-postayla kaydolacak.", "Karanlık tema da olacak."],
     [("dil", "Kotlin", "ekip biliyor")], ["Play Store hesabı aç"],
     ["Mobil uygulamanın giriş ekranını tasarladım.", "Mobil uygulama: giriş ekranı tasarımı bitti."],
     "Mobil uygulama: ikon için üç taslak çizdim.", "ikon"),
    ("en", "Kitchen Renovation", ["New cabinets are oak."], [("countertop", "Quartz")],
     ["Measure the window"], ["The floor under the sink has water damage.", "Budget: 8000 euros in total."],
     [("tiles", "Terracotta", "it looks warmer")], ["Book the electrician"],
     ["I measured the window for the kitchen.", "Kitchen renovation: the window is measured."],
     "Kitchen renovation: I took the old fridge to the recycling centre.", "fridge"),
    ("tr", "Yaz Tatili", ["Tatil Ağustos'ta."], [("otel", "Butik otel")],
     ["Uçak biletlerini ayarla"], ["Kaş'ta beş gece kalacağız.", "Araç kiralama da yapılacak."],
     [("ulaşım", "Uçak", "daha hızlı")], ["Valizi hazırla"],
     ["Uçak biletlerini ayarladım, tatil için o iş tamam.", "Yaz tatili: uçak biletleri ayarlandı."],
     "Yaz tatili: güneş kremi ve şapka aldım.", "krem"),
    ("en", "Marathon Training", ["Race day is in April."], [("shoes", "Brooks Ghost")],
     ["Sign up for the race"], ["Long runs are on Sundays.", "Target pace is 5:30 per km."],
     [("plan", "Higdon novice", "it fits my schedule")], ["Buy energy gels"],
     ["I signed up for the race.", "Marathon training: race registration is done."],
     "Marathon training: I ran 18 km this morning.", "18"),
    ("tr", "Blog Sitesi", ["Site Hugo ile yapılacak."], [("hosting", "Netlify")],
     ["Alan adını kaydet"], ["İlk yazı yapay zekâ üzerine.", "Haftada bir yazı çıkacak."],
     [("tema", "PaperMod", "sade ve hızlı")], ["Hakkımda sayfasını yaz"],
     ["Alan adını kaydettim.", "Blog sitesinin alan adı kaydedildi, o iş bitti."],
     "Blog sitesi: logo için renkleri seçtim.", "logo"),
]

TOPICS = [
    ("en", "Health", ["Blood test results were normal."], "Started taking vitamin D in the mornings.", "What did the blood test show?", "normal"),
    ("tr", "Araba", ["Lastikler Kasım'da değişecek."], "Arabanın yağı 85.000 km'de değişti.", "Arabanın lastikleri ne zaman değişecek?", "Kasım"),
    ("en", "Apartment", ["The rent is due on the 5th."], "The landlord said the heating is fixed next week.", "When is the rent due?", "5th"),
    ("tr", "Köpeğimiz Pamuk", ["Pamuk'un aşısı Mart'ta."], "Pamuk artık günde iki kez yürüyüşe çıkıyor.", "Pamuk'un aşısı ne zaman?", "Mart"),
    ("en", "Freelance Work", ["My day rate is 450 euros."], "A new client wants a logo by Friday.", "What is my day rate?", "450"),
]

# New projects in passing: (lang, message, note path pattern, a word the note keeps).
NEW_PROJECTS = [
    ("en", "New project: restore an old sailing dinghy.", r"^projects/[^/]*(dinghy|sail)[^/]*\.md$", None),
    ("en", "Starting a project to build a bird feeder with my daughter.", r"^projects/[^/]*(bird|feeder)[^/]*\.md$", None),
    ("en", "New project: a small online shop for my prints.", r"^projects/[^/]*(shop|print)[^/]*\.md$", "prints"),
    ("tr", "Yeni proje: balkona bir hamak kuracağım.", r"^projects/[^/]*hamak[^/]*\.md$", None),
    ("tr", "Bir proje başlatıyorum: aile ağacımızı çıkaracağım.", r"^projects/[^/]*(aile|agac)[^/]*\.md$", None),
    ("tr", "Yeni proje: eski bisikletimi yenileyeceğim.", r"^projects/[^/]*bisiklet[^/]*\.md$", None),
    ("en", "Starting a new project: a vegetable patch behind the house, with raised beds.", r"^projects/[^/]*(vegetable|patch)[^/]*\.md$", "raised"),
    ("tr", "Yeni proje: çocuk odası için bir kitaplık yapacağım.", r"^projects/[^/]*kitaplik[^/]*\.md$", None),
    ("en", "New project: learn to bake sourdough bread with a rye starter.", r"^projects/[^/]*sourdough[^/]*\.md$", "rye"),
    ("tr", "Yeni bir proje başlatıyorum: bahçede arı kovanı, iki kovanla.", r"^projects/[^/]*(ari|kovan)[^/]*\.md$", None),
]

# A list with no note yet, while other lists are there (v3): a new note named
# for its kind, never another list. (lang, message, note path pattern, item).
NEW_LISTS = [
    ("en", "Album to listen to: Blue by Joni Mitchell.", r"^topics/[^/]*(album|music)[^/]*\.md$", "Blue"),
    ("en", "Wine to try: a Georgian Saperavi.", r"^topics/[^/]*wine[^/]*\.md$", "Saperavi"),
    ("en", "Hiking trail idea: the Lycian Way, first stage.", r"^topics/[^/]*(hik|trail)[^/]*\.md$", "Lycian"),
    ("en", "Course to take: an evening pottery class.", r"^topics/[^/]*(course|class)[^/]*\.md$", "pottery"),
    ("en", "Series to watch: Slow Horses.", r"^topics/[^/]*(series|show)[^/]*\.md$", "Slow Horses"),
    ("en", "Houseplant I'd like to get: a fiddle-leaf fig.", r"^topics/[^/]*plant[^/]*\.md$", "fig"),
    ("tr", "İzlenecek dizi: Bir Başkadır.", r"^topics/[^/]*dizi[^/]*\.md$", "Bir Başkadır"),
    ("tr", "Denenecek şarap: bir Öküzgözü.", r"^topics/[^/]*sarap[^/]*\.md$", "Öküzgözü"),
    ("tr", "Yürüyüş rotası fikri: Likya Yolu'nun ilk etabı.", r"^topics/[^/]*(yuruyus|rota)[^/]*\.md$", "Likya"),
    ("tr", "Almak istediğim bitki: bir paşa kılıcı.", r"^topics/[^/]*bitki[^/]*\.md$", "paşa kılıcı"),
    ("tr", "Katılmak istediğim kurs: seramik atölyesi.", r"^topics/[^/]*kurs[^/]*\.md$", "seramik"),
    ("tr", "Dinlenecek podcast: Medyascope.", r"^topics/[^/]*podcast[^/]*\.md$", "Medyascope"),
]

# A book or film read now, with no list for it yet (v4, #474): a list named
# for its kind, never a note named after the book. (lang, message, pattern, item).
# Never an item of eval/cases.json: the student must not see the exam's books.
FIRST_OF_KIND = [
    ("tr", "Şu an Beyaz Gemi okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Beyaz Gemi"),
    ("tr", "Bu akşam Kelebeğin Rüyası'nı izleyeceğim.", r"^topics/[^/]*film[^/]*\.md$", "Kelebeğin Rüyası"),
    ("en", "I'm reading Demon Copperhead.", r"^topics/[^/]*book[^/]*\.md$", "Demon Copperhead"),
    ("en", "Watching Perfect Blue tonight.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Perfect Blue"),
    # v5: the kinds the eval misses most, so the list is named for the kind, never the item.
    ("tr", "Dün gece Suç ve Ceza'ya başladım.", r"^topics/[^/]*kitap[^/]*\.md$", "Suç ve Ceza"),
    ("tr", "Elimde Sefiller var, yavaş yavaş okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Sefiller"),
    ("tr", "Yolda Tehlikeli Oyunlar'ı okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Tehlikeli Oyunlar"),
    ("en", "Just picked up Lessons in Chemistry, reading it now.", r"^topics/[^/]*book[^/]*\.md$", "Lessons in Chemistry"),
    ("en", "On the train I'm reading Tomorrow, and Tomorrow, and Tomorrow.", r"^topics/[^/]*book[^/]*\.md$", "Tomorrow"),
    ("en", "Reading The Midnight Library these days.", r"^topics/[^/]*book[^/]*\.md$", "Midnight Library"),
    ("tr", "Hafta sonu Sevmek Zamanı filmini izlemek istiyorum.", r"^topics/[^/]*film[^/]*\.md$", "Sevmek Zamanı"),
    ("tr", "İzlemek istediğim film: Masumiyet.", r"^topics/[^/]*film[^/]*\.md$", "Masumiyet"),
    ("en", "Movie I want to see: Paterson.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Paterson"),
    ("en", "Someone told me to watch In the Mood for Love.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Mood for Love"),
    ("tr", "Tarif fikri: fırında patatesli köfte.", r"^topics/[^/]*tarif[^/]*\.md$", "köfte"),
    ("en", "Recipe idea: roasted cauliflower with tahini.", r"^topics/[^/]*recipe[^/]*\.md$", "cauliflower"),
    ("tr", "Bir gün Bozcaada'ya gitmek istiyorum.", r"^topics/[^/]*(gez|yer)[^/]*\.md$", "Bozcaada"),
    ("en", "Place I'd love to visit one day: the Faroe Islands.", r"^topics/[^/]*(place|visit|travel)[^/]*\.md$", "Faroe"),
    ("en", "Gift idea for my brother: a pocket knife.", r"^topics/[^/]*gift[^/]*\.md$", "pocket knife"),
    ("tr", "Hediye fikri: babama bir termos.", r"^topics/[^/]*hediye[^/]*\.md$", "termos"),
]

# Several lists of different kinds in one workspace (v5): each item goes to the
# list of its kind, never to another list that happens to be there.
# (lang, {kind: title}, [(message, kind, item)]).
MIXED_LISTS = [
    ("en", {"books": "Reading List", "films": "Watchlist", "recipes": "Cooking Ideas", "places": "Travel Wishlist"}, [
        ("Started The Covenant of Water last night.", "books", "Covenant of Water"),
        ("I should read Small Things Like These.", "books", "Small Things"),
        ("Film for the weekend: Perfect Strangers.", "films", "Perfect Strangers"),
        ("I want to watch Fallen Leaves.", "films", "Fallen Leaves"),
        ("Recipe to try: shakshuka with chickpeas.", "recipes", "chickpeas"),
        ("Cooking idea: brown butter gnocchi.", "recipes", "gnocchi"),
        ("I'd love to see Hokkaido in winter.", "places", "Hokkaido"),
        ("Add Lake Bled to the places I want to go.", "places", "Bled"),
    ]),
    ("tr", {"books": "Kitap Listem", "films": "Film Listem", "recipes": "Yemek Fikirleri", "places": "Seyahat Planları"}, [
        ("Bugün Kuyucaklı Yusuf'a başladım, ama bu sefer sesli kitap.", "books", "Kuyucaklı Yusuf"),
        ("Okumak istediğim kitap: Bir Bilim Adamının Romanı.", "books", "Bilim Adamının Romanı"),
        ("Bu hafta sonu Kader filmini izleyeceğim.", "films", "Kader"),
        ("İzlenecek film: Gönül Yarası.", "films", "Gönül Yarası"),
        ("Yemek fikri: ıspanaklı börek.", "recipes", "börek"),
        ("Denemek istediğim tarif: nohutlu pilav.", "recipes", "nohutlu pilav"),
        ("Bir gün Uzungöl'e gitmek istiyorum.", "places", "Uzungöl"),
        ("Gezilecek yer: Ani Harabeleri.", "places", "Ani"),
    ]),
]

# A turn whose first tool call fails (v4, #474): the call is fixed and the
# turn goes on, in the user's language; the answer names no tool and no
# error. Played with the eval's fail_first_call.
NO_TOOL_WORDS = ["list_notes", "search_notes", "related_notes", "add_note_entry", "sorry", "error", "hata"]

# Two lists of one kind (v3): what is read now and what is for later; the
# sentence says which. (lang, now title, later title, [(message, now?, item)]).
TWIN_LISTS = [
    ("en", "Books on My Nightstand", "Books for Later", [
        ("I just started The Name of the Wind.", True, "Name of the Wind"),
        ("Reading Never Let Me Go at the moment.", True, "Never Let Me Go"),
        ("Someday I'd like to read Middlemarch.", False, "Middlemarch"),
        ("A friend recommended Pachinko, I'll read it later.", False, "Pachinko"),
    ]),
    ("tr", "Şu An Okuduklarım", "Sonra Okunacaklar", [
        ("Bugün Puslu Kıtalar Atlası'na başladım.", True, "Puslu Kıtalar Atlası"),
        ("Şu sıralar Yaban'ı okuyorum.", True, "Yaban"),
        ("İleride Çalıkuşu'nu okumak istiyorum.", False, "Çalıkuşu"),
        ("Bir arkadaşım Huzur'u önerdi, sonra okuyacağım.", False, "Huzur"),
    ]),
]

# Too vague to file (v3): the answer is a question, and no note changes.
UNCLEAR = [
    ("en", "Put this in the note."), ("tr", "Şunu da ekle."), ("en", "Save it there."),
    ("en", "Write that down for the project."), ("en", "Change it to the other one."),
    ("en", "Add the thing we talked about."), ("en", "Mark it as done."),
    ("tr", "Onu da projeye yaz."), ("tr", "Diğerini seçtik, onu kaydet."),
    ("tr", "Bunu bir yere yaz."), ("tr", "Onu bitirdim, işaretle."), ("tr", "Şunu güncelle."),
]

# Reminders (#430, #434), worked out from the minute the eval says it is,
# 2026-10-18 14:00, a Sunday: (lang, note title, kind, message, "YYYY-MM-DD[ HH:MM]", a word).
# Plans the user states (v4, #478): a reminder on the day, saved without
# asking, for the whole day when no time is said. The model on the device
# cannot search, so every day here is known from the message itself.
# (lang, message, "YYYY-MM-DD[ HH:MM]"), from 2026-10-18 14:00, a Sunday.
PLANS = [
    ("en", "Tuesday evening I'm going to a pottery workshop.", "2026-10-20"),
    ("en", "Thursday at 18:00 I'm playing tennis with Ana.", "2026-10-22 18:00"),
    ("en", "On 2 November I'm flying to Berlin.", "2026-11-02"),
    ("en", "Next Saturday I'll go to the farmers' market.", "2026-10-24"),
    ("tr", "Salı akşamı yoga dersine gideceğim.", "2026-10-20"),
    ("tr", "Cuma saat 20'de arkadaşlarla yemeğe çıkacağım.", "2026-10-23 20:00"),
    ("tr", "3 Kasım'da İzmir'e uçacağım.", "2026-11-03"),
    ("tr", "Pazartesi sabah 9'da kombi servisi gelecek.", "2026-10-19 09:00"),
    ("tr", "Yarın akşam tiyatroya gideceğim.", "2026-10-19"),
    ("tr", "Perşembe günü Ankara'ya gideceğim.", "2026-10-22"),
    ("tr", "Cumartesi saat 21'de annemlerle konsere gideceğim.", "2026-10-24 21:00"),
    ("en", "On Friday I'm going to the book fair.", "2026-10-23"),
    ("en", "I'll watch the cup final on 30 October.", "2026-10-30"),
    ("en", "Wednesday at 19:30 I'm going to a jazz night.", "2026-10-21 19:30"),
]

REMINDERS = [
    ("en", "Garden Shed", "project", "Remind me tomorrow at 8 to call the timber yard about the garden shed.", "2026-10-19 08:00", "timber"),
    ("en", "Podcast Launch", "project", "Podcast launch: remind me in 2 hours to email the first guest.", "2026-10-18 16:00", "guest"),
    ("tr", "Düğün Hazırlığı", "project", "Düğün hazırlığı için yarın 10'da pastaneyi aramamı hatırlat.", "2026-10-19 10:00", "pasta"),
    ("tr", "Mobil Uygulama", "project", "Mobil uygulama: 30 dakika sonra test sürümünü yüklemeyi hatırlat.", "2026-10-18 14:30", "test"),
    ("en", "Kitchen Renovation", "project", "Remind me on Friday at 17:30 to pick up the kitchen tiles.", "2026-10-23 17:30", "tile"),
    ("tr", "Yaz Tatili", "project", "Yaz tatili: 1 Kasım'da pasaportların süresine bakmamı hatırlat.", "2026-11-01", "pasaport"),
    ("en", "Marathon Training", "project", "Marathon training: remind me in 45 minutes to stretch.", "2026-10-18 14:45", "stretch"),
    ("tr", "Blog Sitesi", "project", "Blog sitesi için 20 dakika sonra yazıyı yayınlamamı hatırlat.", "2026-10-18 14:20", "yazı"),
    ("en", "Health", "topic", "Remind me on 3 November at 9 to book the next blood test.", "2026-11-03 09:00", "blood"),
    ("tr", "Köpeğimiz Pamuk", "topic", "Pamuk için 5 Mart'ta saat 11'de veterineri aramamı hatırlat.", "2027-03-05 11:00", "veteriner"),
    ("en", "Apartment", "topic", "Remind me in 5 minutes to pay the rent for the apartment.", "2026-10-18 14:05", "rent"),
    ("tr", "Araba", "topic", "Araba için 2 saat sonra lastikçiyi aramamı hatırlat.", "2026-10-18 16:00", "lastik"),
]

# Other notes every case's workspace gets beside its own, like the eval's shared notes.
DISTRACTORS = 4

# Kinds of list, by the words of their slugs in both languages: a list of the
# case's kind is never a distractor, since adding to it would be right too.
THEMES = {
    "books": r"kitap|book|read|okudu|okunacak",
    "films": r"film|movie|watch|izlenecek|dizi|series|show",
    "recipes": r"tarif|recipe|cook|yemek",
    "places": r"yer|place|visit|travel|seyahat|gez",
    "gifts": r"gift|hediye",
    "music": r"album|music|muzik",
    "podcasts": r"podcast",
    "games": r"game|oyun",
    "restaurants": r"restaurant|restoran",
    "learning": r"ogren|course|class|kurs",
    "hiking": r"hik|trail|yuruyus|rota",
    "wine": r"wine|sarap",
    "plants": r"plant|bitki",
}


def themes(text):
    """The list kinds a topic path names; also takes a pattern that spells out "topics/"."""
    if "topics/" not in text:
        return set()
    return {theme for theme, words in THEMES.items() if re.search(words, text)}

# How many collections also get a case whose first tool call fails.
RECOVERIES = 10

# Items of each collection that get a case: two since v6, so lists stop
# outweighing the decisions (v5 filed everything into the reading list).
COLLECTION_PICKS = 2

# Contrast sets (v6): one note, five messages that each need a different first action.
# (lang, title, kind, notes, decisions, todos, [(message, kind, tool or None to ask, word kept)]).
CONTRAST = [
    ("en", "Attic Conversion", "project", ["The attic gets a skylight."], [("insulation", "Sheep wool")], ["Call the roofer"], [
        ("I called the roofer about the attic.", "todo-done", "complete_todo", None),
        ("Attic conversion: I still need to order the skylight.", "todo", "add_todo", "skylight"),
        ("For the attic we picked oak for the floor, it is warmer.", "decision", "record_decision", "oak"),
        ("Attic conversion: the beams are in better shape than we thought.", "filing", "add_note_entry", "beams"),
        ("Put that in the attic thing.", "unclear", None, None),
    ]),
    ("en", "Bakery Side Gig", "project", ["We bake on Saturdays."], [("oven", "Deck oven")], ["Print price labels"], [
        ("The price labels for the bakery are printed.", "todo-done", "complete_todo", None),
        ("Bakery side gig: add a todo to buy paper bags.", "todo", "add_todo", "bags"),
        ("Bakery: we chose rye flour from the mill on the hill, better taste.", "decision", "record_decision", "rye"),
        ("Bakery side gig: we sold out of croissants by ten.", "filing", "add_note_entry", "croissants"),
        ("Change the bakery one.", "unclear", None, None),
    ]),
    ("en", "Thesis Writing", "project", ["Chapter two is about methods."], [("citation style", "APA")], ["Email the supervisor"], [
        ("I emailed my supervisor about the thesis.", "todo-done", "complete_todo", None),
        ("Thesis: I have to book a room for the defence.", "todo", "add_todo", "defence"),
        ("Thesis writing: we went with LaTeX over Word, the formulas look better.", "decision", "record_decision", "LaTeX"),
        ("Thesis: the survey got 212 answers.", "filing", "add_note_entry", "212"),
        ("Add it to the thesis.", "unclear", None, None),
    ]),
    ("en", "Van Life Build", "project", ["The van is a 2014 Transit."], [("bed", "Fixed platform")], ["Buy solar panels"], [
        ("Bought the solar panels for the van.", "todo-done", "complete_todo", None),
        ("Van build: add a todo to fit a roof vent.", "todo", "add_todo", "vent"),
        ("For the van we picked a diesel heater, it is cheaper to run.", "decision", "record_decision", "diesel"),
        ("Van life build: the floor took three days to level.", "filing", "add_note_entry", "level"),
        ("Do the van thing we said.", "unclear", None, None),
    ]),
    ("en", "Choir Concert", "project", ["The concert is in the old church."], [("encore", "Ave Maria")], ["Print the programme"], [
        ("The concert programme is printed.", "todo-done", "complete_todo", None),
        ("Choir concert: I need to rent extra chairs.", "todo", "add_todo", "chairs"),
        ("For the choir concert we chose candles over spotlights, it feels warmer.", "decision", "record_decision", "candles"),
        ("Choir concert: the tenors rehearse on Thursdays now.", "filing", "add_note_entry", "Thursday"),
        ("Note that for the choir.", "unclear", None, None),
    ]),
    ("en", "Fishing Trip", "project", ["We go to the lake in May."], [("boat", "Rowing boat")], ["Renew the licence"], [
        ("I renewed the fishing licence.", "todo-done", "complete_todo", None),
        ("Fishing trip: add buying new hooks to the list.", "todo", "add_todo", "hooks"),
        ("For the fishing trip we picked the north shore, fewer people.", "decision", "record_decision", "north"),
        ("Fishing trip: Omar is bringing his tent.", "filing", "add_note_entry", "Omar"),
        ("Save it with the trip.", "unclear", None, None),
    ]),
    ("tr", "Bahçe Duvarı", "project", ["Duvar taş olacak."], [("harç", "Kireç harcı")], ["Ustayla konuş"], [
        ("Ustayla konuştum, bahçe duvarındaki o iş tamam.", "todo-done", "complete_todo", None),
        ("Bahçe duvarı için yapılacak: kum siparişi ver.", "todo", "add_todo", "kum"),
        ("Bahçe duvarı için dere taşı seçtik, daha doğal duruyor.", "decision", "record_decision", "dere"),
        ("Bahçe duvarı: temel kazısı iki gün sürdü.", "filing", "add_note_entry", "kazı"),
        ("Bunu duvara ekle.", "unclear", None, None),
    ]),
    ("tr", "Dernek Kuruluşu", "project", ["Kurucu üye sayısı yedi."], [("isim", "Mahalle Dayanışma Derneği")], ["Tüzüğü yaz"], [
        ("Tüzüğü yazdım, dernek için o iş bitti.", "todo-done", "complete_todo", None),
        ("Dernek kuruluşu: banka hesabı açmam gerekiyor.", "todo", "add_todo", "banka"),
        ("Dernek için muhasebeci olarak Selin Hanım'ı seçtik, uygun fiyatlı.", "decision", "record_decision", "Selin"),
        ("Dernek kuruluşu: ilk toplantıya on iki kişi geldi.", "filing", "add_note_entry", "toplantı"),
        ("Onu derneğe yaz.", "unclear", None, None),
    ]),
    ("tr", "Kitap Çevirisi", "project", ["Çeviri Almancadan yapılıyor."], [("yayınevi", "Yapı Kredi")], ["Sözleşmeyi imzala"], [
        ("Çeviri sözleşmesini imzaladım.", "todo-done", "complete_todo", None),
        ("Kitap çevirisi için yapılacak: terim listesi hazırla.", "todo", "add_todo", "terim"),
        ("Çeviride ikinci tekil şahıs yerine resmi dili seçtik, metne uyuyor.", "decision", "record_decision", "resmi"),
        ("Kitap çevirisi: üçüncü bölüm bitti.", "filing", "add_note_entry", "üçüncü"),
        ("Şunu çeviriye ekle.", "unclear", None, None),
    ]),
    ("tr", "Okul Gezisi", "project", ["Gezi Bursa'ya."], [("otobüs", "Özel otobüs")], ["Velilerden izin al"], [
        ("Velilerden izinleri aldım, gezi için o iş tamam.", "todo-done", "complete_todo", None),
        ("Okul gezisi: öğle yemeği için yer ayırtmalıyım.", "todo", "add_todo", "öğle"),
        ("Okul gezisi için müze olarak Tofaş Müzesi'ni seçtik, çocuklar arabaları seviyor.", "decision", "record_decision", "Tofaş"),
        ("Okul gezisi: otuz iki öğrenci katılıyor.", "filing", "add_note_entry", "otuz"),
        ("Geziye şunu da yaz.", "unclear", None, None),
    ]),
    ("tr", "Bisiklet Kulübü", "project", ["Kulüp her pazar sürüyor."], [("rota", "Sahil yolu")], ["Forma siparişi ver"], [
        ("Formaları sipariş ettim, kulüp için o iş tamam.", "todo-done", "complete_todo", None),
        ("Bisiklet kulübü: ilk yardım çantası almam lazım.", "todo", "add_todo", "çanta"),
        ("Kulüp için buluşma yeri olarak iskeleyi seçtik, herkese yakın.", "decision", "record_decision", "iskele"),
        ("Bisiklet kulübü: geçen pazar 64 km sürdük.", "filing", "add_note_entry", "64"),
        ("Kulübe onu da ekle.", "unclear", None, None),
    ]),
    ("tr", "Ev Kliması", "topic", ["Klima salonda."], [("marka", "Inverter model")], ["Filtreyi temizle"], [
        ("Klimanın filtresini temizledim.", "todo-done", "complete_todo", None),
        ("Klima için yapılacak: gaz kontrolü yaptır.", "todo", "add_todo", "gaz"),
        ("Klima için yıllık bakım anlaşması yaptık, daha ucuz.", "decision", "record_decision", "bakım"),
        ("Klima: gece modunda çok sessiz çalışıyor.", "filing", "add_note_entry", "sessiz"),
        ("Bunu klimaya yaz.", "unclear", None, None),
    ]),
]

# A message in one language about a note in the other (v6, #604).
CROSS = [
    ("en", "Düğün Hazırlığı", "project", "Wedding prep: the cake will have three tiers.", "filing", "add_note_entry", "three"),
    ("en", "Mobil Uygulama", "project", "For the mobile app we picked Supabase instead, it is open source.", "decision", "record_decision", "Supabase"),
    ("en", "Yaz Tatili", "project", "Summer holiday: add a todo to book the rental car.", "todo", "add_todo", "car"),
    ("en", "Blog Sitesi", "project", "I registered the blog's domain.", "todo-done", "complete_todo", None),
    ("en", "Araba", "topic", "The car's brake pads were changed today.", "filing", "add_note_entry", "brake"),
    ("en", "Köpeğimiz Pamuk", "topic", "Pamuk weighs 18 kg now.", "filing", "add_note_entry", "18"),
    ("tr", "Garden Shed", "project", "Bahçe kulübesi: kapıyı kırmızıya boyadık.", "filing", "add_note_entry", "kırmızı"),
    ("tr", "Podcast Launch", "project", "Podcast için yapılacak: kapak görselini bitir.", "todo", "add_todo", "kapak"),
    ("tr", "Kitchen Renovation", "project", "Mutfak tadilatında pencereyi ölçtüm.", "todo-done", "complete_todo", None),
    ("tr", "Marathon Training", "project", "Maraton için ayakkabı olarak Hoka seçtik, daha yumuşak.", "decision", "record_decision", "Hoka"),
    ("tr", "Health", "topic", "Sağlık: tansiyonum bugün 11'e 7 çıktı.", "filing", "add_note_entry", "11"),
    ("tr", "Freelance Work", "topic", "Serbest iş: yeni müşteri logoyu beğendi.", "filing", "add_note_entry", "logo"),
]

CHAT = [
    ("en", "ok, thank you"), ("tr", "sağ ol"), ("en", "great, thanks a lot"), ("tr", "tamamdır, teşekkür ederim"),
    ("en", "brilliant, thanks"), ("en", "that's all for now"), ("en", "cheers!"),
    ("tr", "eyvallah"), ("tr", "tamam, şimdilik bu kadar"), ("tr", "çok sağ ol, harikasın"),
]

# v8 (#604): more of every table, weighted to the kinds the student misses
# (unclear, todo-done, plan, cross-language), so the data reaches 1,500 turns.
PROJECTS += [
    ("en", "Boat Restoration", ["The hull is fibreglass."], [("engine", "Outboard 15 hp")],
     ["Sand the deck"], ["The mast needs new rigging.", "Two coats of varnish are enough."],
     [("paint", "Antifouling blue", "it lasts two seasons")], ["Buy a new tiller"],
     ["I sanded the deck of the boat.", "Boat restoration: the deck is sanded."],
     "Boat restoration: I found the original logbook in a drawer.", "logbook"),
    ("en", "Home Office", ["The desk goes by the window."], [("chair", "Herman Miller Aeron")],
     ["Run a network cable"], ["The room gets sun until noon.", "A plant would brighten the corner."],
     [("lamp", "BenQ ScreenBar", "it saves desk space")], ["Hang the shelves"],
     ["I ran the network cable to the home office.", "Home office: the network cable is in."],
     "Home office: I sold the old printer online.", "printer"),
    ("en", "Community Garden", ["We have twelve plots."], [("water", "Rain barrels")],
     ["Fix the gate"], ["The compost bin is full again.", "Mrs Patel grows the best tomatoes."],
     [("fence", "Willow hurdles", "they look natural")], ["Order wood chips"],
     ["I fixed the gate at the community garden.", "Community garden: the gate is fixed."],
     "Community garden: I planted garlic in plot four.", "garlic"),
    ("en", "Family Photo Book", ["It covers 2010 to 2020."], [("printer", "Blurb")],
     ["Scan the old prints"], ["Grandma's photos are in the blue box.", "Each chapter is one year."],
     [("cover", "Linen hardcover", "it feels special")], ["Write the captions"],
     ["I scanned the old prints for the photo book.", "Family photo book: the old prints are scanned."],
     "Family photo book: I picked a font for the titles.", "font"),
    ("en", "Woodworking Bench", ["The top is beech."], [("vise", "Leg vise")],
     ["Flatten the top"], ["The legs are 90 cm tall.", "Dog holes are 20 mm wide."],
     [("finish", "Danish oil", "it is easy to repair")], ["Buy two holdfasts"],
     ["I flattened the bench top.", "Woodworking bench: the top is flat now."],
     "Woodworking bench: I sharpened all the chisels.", "chisels"),
    ("en", "Neighbourhood Newsletter", ["It comes out monthly."], [("format", "Two A4 pages")],
     ["Collect the event dates"], ["The bakery wants an advert.", "Printing costs 40 euros."],
     [("delivery", "Volunteers on bikes", "it is free")], ["Ask for a photo of the mural"],
     ["I collected the event dates for the newsletter.", "Neighbourhood newsletter: the event dates are collected."],
     "Neighbourhood newsletter: I wrote the piece about the new playground.", "playground"),
    ("en", "Board Game Design", ["Two to four players."], [("theme", "Deep sea exploration")],
     ["Print a prototype"], ["Each playtest takes 45 minutes.", "The dice felt too random."],
     [("cards", "Linen finish", "they shuffle better")], ["Write the rulebook"],
     ["I printed a prototype of the board game.", "Board game design: the prototype is printed."],
     "Board game design: I drew a new map tile.", "tile"),
    ("en", "Charity Run", ["The run raises money for the shelter."], [("route", "Park loop")],
     ["Book the park"], ["Forty runners signed up.", "The shelter sends two volunteers."],
     [("medals", "Wooden medals", "they are cheaper")], ["Set up water stations"],
     ["I booked the park for the charity run.", "Charity run: the park is booked."],
     "Charity run: I designed the start banner.", "banner"),
    ("tr", "Kahve Dükkanı", ["Dükkan Moda'da olacak."], [("makine", "La Marzocco")],
     ["Kira sözleşmesini oku"], ["Kira aylık 40 bin lira.", "Vitrin camı değişecek."],
     [("çekirdek", "Etiyopya", "daha meyvemsi")], ["Tabela için teklif al"],
     ["Kira sözleşmesini okudum, dükkan için o iş tamam.", "Kahve dükkanı: kira sözleşmesi okundu."],
     "Kahve dükkanı: barista için iki kişiyle görüştüm.", "barista"),
    ("tr", "Sokak Kütüphanesi", ["Kutu parkın girişinde."], [("malzeme", "Ahşap kutu")],
     ["Belediyeden izin al"], ["Bağışlanan kitaplar elli tane oldu.", "Kutunun kapağı cam olacak."],
     [("boya", "Sarı", "uzaktan görünüyor")], ["Kutuya bir tabela as"],
     ["Belediyeden izni aldım, sokak kütüphanesi için o iş tamam.", "Sokak kütüphanesi: belediye izni alındı."],
     "Sokak kütüphanesi: kutuya ilk kitapları yerleştirdim.", "ilk"),
    ("tr", "Yoga Stüdyosu", ["Stüdyo ikinci katta."], [("zemin", "Mantar zemin")],
     ["Matları sipariş et"], ["Sabah dersleri dolu.", "Akşam grubu sekiz kişi."],
     [("müzik", "Tibet çanları", "daha sakin")], ["Web sitesi için fotoğraf çektir"],
     ["Matları sipariş ettim, stüdyo için o iş tamam.", "Yoga stüdyosu: matlar sipariş edildi."],
     "Yoga stüdyosu: duvarları açık yeşile boyadık.", "yeşil"),
    ("tr", "Köy Evi Onarımı", ["Ev taş ve ahşap."], [("çatı", "Kiremit")],
     ["Ustadan fiyat al"], ["Tavan kirişleri sağlam çıktı.", "Kuyu suyu içilebilir."],
     [("pencere", "Ahşap doğrama", "eve yakışıyor")], ["Elektrik tesisatını yenile"],
     ["Ustadan fiyatı aldım, köy evi için o iş bitti.", "Köy evi onarımı: ustadan fiyat alındı."],
     "Köy evi onarımı: bahçedeki eski fırını temizledim.", "fırın"),
    ("tr", "Satranç Turnuvası", ["Turnuva okulda yapılacak."], [("süre", "On beş dakika")],
     ["Satranç saatlerini topla"], ["Kırk öğrenci kayıt oldu.", "Hakem Murat Bey olacak."],
     [("ödül", "Kitap seti", "çocuklar seviyor")], ["Madalyaları sipariş et"],
     ["Satranç saatlerini topladım, turnuva için o iş tamam.", "Satranç turnuvası: saatler toplandı."],
     "Satranç turnuvası: eşleşme tablosunu hazırladım.", "tablo"),
    ("tr", "Arıcılık", ["İki kovanımız var."], [("ırk", "Kafkas arısı")],
     ["Maske ve eldiven al"], ["Kovanlar bahçenin güneyinde.", "İlk hasat 12 kilo bal verdi."],
     [("çerçeve", "Ahşap çerçeve", "arılar alışık")], ["Kışlık şurup hazırla"],
     ["Maske ve eldiveni aldım, arıcılık için o iş tamam.", "Arıcılık: maske ve eldiven alındı."],
     "Arıcılık: kovanların etrafına lavanta diktim.", "lavanta"),
    ("tr", "Mahalle Pazarı", ["Pazar her cumartesi kurulacak."], [("yer", "Okul bahçesi")],
     ["Tezgahları say"], ["Yirmi üretici katılacak.", "Resim köşesi çocuklar için."],
     [("saat", "Sabah dokuz", "serin oluyor")], ["Afiş bastır"],
     ["Tezgahları saydım, mahalle pazarı için o iş tamam.", "Mahalle pazarı: tezgahlar sayıldı."],
     "Mahalle pazarı: belediyeyle elektrik için konuştum.", "elektrik"),
    ("tr", "Ehliyet Kursu", ["Kurs Ekim'de başladı."], [("vites", "Otomatik")],
     ["Sağlık raporu al"], ["Direksiyon dersleri salı günleri.", "Teori sınavı Kasım'da."],
     [("hoca", "Ayşe Hanım", "çok sabırlı")], ["Vesikalık fotoğraf çektir"],
     ["Sağlık raporunu aldım, ehliyet için o iş bitti.", "Ehliyet kursu: sağlık raporu alındı."],
     "Ehliyet kursu: ilk direksiyon dersinde park ettim.", "park"),
]

TOPICS += [
    ("en", "Garden Pond", ["The pond has six goldfish."], "The water lily finally flowered.", "How many goldfish are in the pond?", "six"),
    ("tr", "Akvaryum", ["Akvaryum 120 litre."], "Akvaryumun filtresi bugün değişti.", "Akvaryum kaç litre?", "120"),
    ("en", "Pension", ["I pay in 300 euros a month."], "The pension statement came, it grew by 6 percent.", "How much do I pay into my pension?", "300"),
    ("tr", "Ev Kredisi", ["Kredi faizi yüzde 2,5."], "Kredinin son taksidi Haziran 2031'de.", "Ev kredisinin faizi ne kadar?", "2,5"),
]

UNCLEAR += [
    ("en", "Add it to that list."), ("en", "Move it over there."), ("en", "Change the date on it."),
    ("en", "Note the usual."), ("en", "Do the same as last time."), ("en", "Write it under his name."),
    ("en", "Put the second one in."), ("en", "Update that note with it."),
    ("tr", "Bunu öbür tarafa al."), ("tr", "Aynısını yine yaz."), ("tr", "Tarihini değiştir."),
    ("tr", "Onu listeye koy."), ("tr", "Geçen seferki gibi kaydet."), ("tr", "İkincisini ekle."),
    ("tr", "Onunkine yaz."), ("tr", "Şu notu düzelt."),
]

PLANS += [
    ("en", "Monday at 7 I'm taking the early train to Leeds.", "2026-10-19 07:00"),
    ("en", "On Wednesday I have a dentist appointment.", "2026-10-21"),
    ("en", "Saturday at 10:30 I'm meeting Sam for brunch.", "2026-10-24 10:30"),
    ("en", "On 5 November I start my new job.", "2026-11-05"),
    ("en", "Tomorrow at 15:00 I have a call with the bank.", "2026-10-19 15:00"),
    ("en", "On Friday at 19:00 I'm hosting a dinner.", "2026-10-23 19:00"),
    ("tr", "Çarşamba günü dişçiye gideceğim.", "2026-10-21"),
    ("tr", "Yarın saat 15'te bankayla görüşmem var.", "2026-10-19 15:00"),
    ("tr", "Cumartesi sabah 10'da kahvaltıya gideceğim.", "2026-10-24 10:00"),
    ("tr", "5 Kasım'da yeni işe başlıyorum.", "2026-11-05"),
    ("tr", "Salı saat 18:30'da veli toplantısı var.", "2026-10-20 18:30"),
    ("tr", "Perşembe akşamı sinemaya gideceğim.", "2026-10-22"),
]

REMINDERS += [
    ("en", "Boat Restoration", "project", "Remind me tomorrow at 9 to call the sailmaker about the boat.", "2026-10-19 09:00", "sailmaker"),
    ("en", "Home Office", "project", "Home office: remind me in an hour to measure the alcove.", "2026-10-18 15:00", "alcove"),
    ("en", "Community Garden", "project", "Remind me on Saturday at 10 to water the community garden.", "2026-10-24 10:00", "water"),
    ("en", "Charity Run", "project", "Charity run: remind me in 15 minutes to email the sponsors.", "2026-10-18 14:15", "sponsor"),
    ("en", "Board Game Design", "project", "Remind me on 1 November to send the board game to the testers.", "2026-11-01", "tester"),
    ("en", "Woodworking Bench", "project", "Woodworking bench: remind me tomorrow at 18:00 to glue the top.", "2026-10-19 18:00", "glue"),
    ("tr", "Kahve Dükkanı", "project", "Kahve dükkanı için yarın 11'de muhasebeciyi aramamı hatırlat.", "2026-10-19 11:00", "muhasebe"),
    ("tr", "Yoga Stüdyosu", "project", "Yoga stüdyosu: 2 saat sonra ders programını paylaşmamı hatırlat.", "2026-10-18 16:00", "program"),
    ("tr", "Arıcılık", "project", "Arıcılık için cumartesi saat 8'de kovanlara bakmamı hatırlat.", "2026-10-24 08:00", "kovan"),
    ("tr", "Ehliyet Kursu", "project", "Ehliyet kursu: 10 dakika sonra sınav ücretini yatırmamı hatırlat.", "2026-10-18 14:10", "ücret"),
    ("tr", "Satranç Turnuvası", "project", "Satranç turnuvası için 4 Kasım'da okulu aramamı hatırlat.", "2026-11-04", "okul"),
    ("tr", "Köy Evi Onarımı", "project", "Köy evi için yarın sabah 7'de nakliyeciyi aramamı hatırlat.", "2026-10-19 07:00", "nakliye"),
]

CONTRAST += [
    ("en", "Pottery Studio", "project", ["The kiln is in the garage."], [("clay", "Stoneware")], ["Buy glaze"], [
        ("I bought the glaze for the pottery studio.", "todo-done", "complete_todo", None),
        ("Pottery studio: I need to fix the wheel pedal.", "todo", "add_todo", "pedal"),
        ("For the pottery studio we went with an electric kiln, gas is too risky.", "decision", "record_decision", "electric"),
        ("Pottery studio: the first bowls cracked in the kiln.", "filing", "add_note_entry", "bowls"),
        ("Put that with the pottery.", "unclear", None, None),
    ]),
    ("en", "Bathroom Remodel", "project", ["The bath stays where it is."], [("tiles", "White subway")], ["Pick a vanity"], [
        ("Picked the vanity for the bathroom.", "todo-done", "complete_todo", None),
        ("Bathroom remodel: add a todo to replace the extractor fan.", "todo", "add_todo", "fan"),
        ("For the bathroom we chose a walk-in shower, it is easier to clean.", "decision", "record_decision", "shower"),
        ("Bathroom remodel: the plumber found an old lead pipe.", "filing", "add_note_entry", "lead"),
        ("Update the bathroom one.", "unclear", None, None),
    ]),
    ("en", "Science Fair", "project", ["The fair is in March."], [("topic", "Water filters")], ["Buy test strips"], [
        ("Bought the test strips for the science fair.", "todo-done", "complete_todo", None),
        ("Science fair: I still have to print the poster.", "todo", "add_todo", "poster"),
        ("For the science fair we chose sand and charcoal layers, they filter best.", "decision", "record_decision", "charcoal"),
        ("Science fair: the third filter made the water clear.", "filing", "add_note_entry", "clear"),
        ("Add it to the fair stuff.", "unclear", None, None),
    ]),
    ("en", "Food Truck", "project", ["We sell burritos."], [("truck", "Used Citroen HY")], ["Get a food licence"], [
        ("Got the food licence for the truck.", "todo-done", "complete_todo", None),
        ("Food truck: add a todo to design the menu board.", "todo", "add_todo", "menu"),
        ("For the food truck we picked corn tortillas, they are gluten free.", "decision", "record_decision", "corn"),
        ("Food truck: we sold 80 burritos at the Friday market.", "filing", "add_note_entry", "80"),
        ("Write that for the truck.", "unclear", None, None),
    ]),
    ("en", "Garage Band", "project", ["We rehearse in Leo's garage."], [("name", "The Late Buses")], ["Fix the bass amp"], [
        ("The bass amp is fixed.", "todo-done", "complete_todo", None),
        ("Garage band: we need to book a gig at the pub.", "todo", "add_todo", "pub"),
        ("Garage band: we chose to play only originals, covers bore us.", "decision", "record_decision", "originals"),
        ("Garage band: the new song is in D minor.", "filing", "add_note_entry", "minor"),
        ("Do the band thing.", "unclear", None, None),
    ]),
    ("en", "Wedding Anniversary", "project", ["It is our tenth."], [("place", "Seaside cottage")], ["Book the cottage"], [
        ("Booked the cottage for our anniversary.", "todo-done", "complete_todo", None),
        ("Anniversary: I still need to order flowers.", "todo", "add_todo", "flowers"),
        ("For the anniversary we picked a tasting menu dinner, it feels special.", "decision", "record_decision", "tasting"),
        ("Wedding anniversary: my sister will look after the kids.", "filing", "add_note_entry", "sister"),
        ("Save that for the anniversary.", "unclear", None, None),
    ]),
    ("tr", "Dükkan Tabelası", "project", ["Tabela ışıklı olacak."], [("renk", "Lacivert")], ["Tabelacıyı ara"], [
        ("Tabelacıyı aradım, tabela için o iş tamam.", "todo-done", "complete_todo", None),
        ("Dükkan tabelası: ölçüleri almam gerekiyor.", "todo", "add_todo", "ölçü"),
        ("Tabela için yazı tipi olarak el yazısını seçtik, daha sıcak.", "decision", "record_decision", "el yazı"),
        ("Dükkan tabelası: belediye izni iki hafta sürüyor.", "filing", "add_note_entry", "belediye"),
        ("Bunu tabelaya yaz.", "unclear", None, None),
    ]),
    ("tr", "Bebek Odası", "project", ["Oda kuzeye bakıyor."], [("duvar", "Açık gri")], ["Beşiği kur"], [
        ("Beşiği kurdum, bebek odası için o iş bitti.", "todo-done", "complete_todo", None),
        ("Bebek odası için yapılacak: perde al.", "todo", "add_todo", "perde"),
        ("Bebek odası için ahşap oyuncakları seçtik, daha güvenli.", "decision", "record_decision", "ahşap"),
        ("Bebek odası: halı çok yumuşak geldi.", "filing", "add_note_entry", "halı"),
        ("Onu odaya ekle.", "unclear", None, None),
    ]),
    ("tr", "Tiyatro Oyunu", "project", ["Oyun iki perde."], [("sahne", "Okul salonu")], ["Kostümleri dik"], [
        ("Kostümleri diktim, oyun için o iş tamam.", "todo-done", "complete_todo", None),
        ("Tiyatro oyunu: dekor için boya almalıyım.", "todo", "add_todo", "boya"),
        ("Oyunda müziği canlı çalmaya karar verdik, daha etkileyici.", "decision", "record_decision", "canlı"),
        ("Tiyatro oyunu: ikinci perdenin provası iyi geçti.", "filing", "add_note_entry", "prova"),
        ("Şunu oyuna yaz.", "unclear", None, None),
    ]),
    ("tr", "Kamp Malzemeleri", "topic", ["Çadır dört kişilik."], [("ocak", "Gazlı ocak")], ["Uyku tulumunu yıka"], [
        ("Uyku tulumunu yıkadım.", "todo-done", "complete_todo", None),
        ("Kamp malzemeleri için yapılacak: kafa lambası al.", "todo", "add_todo", "lamba"),
        ("Kamp için şişme mat yerine köpük mat seçtik, patlamıyor.", "decision", "record_decision", "köpük"),
        ("Kamp malzemeleri: çadırın bir direği eğildi.", "filing", "add_note_entry", "çadır"),
        ("Bunu kampa ekle.", "unclear", None, None),
    ]),
    ("tr", "Emeklilik Planı", "topic", ["Emekliliğe on yıl var."], [("fon", "Endeks fonu")], ["Danışmanla görüş"], [
        ("Danışmanla görüştüm, emeklilik için o iş tamam.", "todo-done", "complete_todo", None),
        ("Emeklilik planı için yapılacak: BES sözleşmesini incele.", "todo", "add_todo", "BES"),
        ("Emeklilik için aylık birikimi beş bin lira yapmaya karar verdik, bütçeye uyuyor.", "decision", "record_decision", "bin"),
        ("Emeklilik planı: fon bu yıl yüzde 30 kazandırdı.", "filing", "add_note_entry", "30"),
        ("Onu plana yaz.", "unclear", None, None),
    ]),
    ("tr", "Yeni Bilgisayar", "topic", ["Bütçe 50 bin lira."], [("işletim sistemi", "Linux")], ["Fiyatları karşılaştır"], [
        ("Fiyatları karşılaştırdım, bilgisayar için o iş bitti.", "todo-done", "complete_todo", None),
        ("Yeni bilgisayar için yapılacak: eski diski yedekle.", "todo", "add_todo", "yedek"),
        ("Yeni bilgisayar için 32 GB bellek seçtik, ileride yetsin.", "decision", "record_decision", "32"),
        ("Yeni bilgisayar: mağaza kargoyu çarşamba yapacak.", "filing", "add_note_entry", "kargo"),
        ("Bilgisayara şunu ekle.", "unclear", None, None),
    ]),
]

CROSS += [
    ("en", "Kahve Dükkanı", "project", "Coffee shop: the espresso machine arrives on Monday.", "filing", "add_note_entry", "espresso"),
    ("en", "Arıcılık", "project", "For the beekeeping we picked a plastic queen excluder, it is easier to clean.", "decision", "record_decision", "plastic"),
    ("en", "Yoga Stüdyosu", "project", "I ordered the mats for the yoga studio.", "todo-done", "complete_todo", None),
    ("en", "Ehliyet Kursu", "project", "Driving course: add a todo to practise parallel parking.", "todo", "add_todo", "parking"),
    ("tr", "Boat Restoration", "project", "Tekne restorasyonu: güverteyi zımparaladım.", "todo-done", "complete_todo", None),
    ("tr", "Charity Run", "project", "Yardım koşusu için yapılacak: sponsor listesini hazırla.", "todo", "add_todo", "sponsor"),
    ("tr", "Home Office", "project", "Çalışma odası: masa lambası çok iyi oldu.", "filing", "add_note_entry", "lamba"),
    ("tr", "Community Garden", "project", "Topluluk bahçesi için kompost yerine solucan gübresi seçtik, daha temiz.", "decision", "record_decision", "solucan"),
]
# Shapes from the maintainer's own use (#737), every name, place, amount and
# link invented: long voice-style Turkish, a topic opened on first mention, a
# liked repository with its link, an official procedure, a split bill, an
# early-morning trip, a feature idea for an app project.
TOPICS += [
    ("tr", "Ortak Masraflar", ["Ev arkadaşlarıyla internet faturası 600 lira, üçe bölünüyor."],
     "Cumartesi pazardan 450 liralık alışveriş yaptık, üç kişiye bölünce kişi başı 150 lira düştü.", "İnternet faturası ne kadar?", "600"),
    ("tr", "Resmi İşlemler", ["Pasaport yenileme için nüfus müdürlüğünden randevu alınıyor."],
     "Ehliyet yenilemek için önce aile hekiminden sağlık raporu almak gerekiyor, rapor iki gün içinde sisteme düşüyormuş.",
     "Pasaport yenileme randevusu nereden alınıyor?", "nüfus"),
    ("tr", "Yazı Fikirleri", ["Uzaktan çalışmanın yalnızlığı üzerine bir yazı."],
     "Kendi sitemde yayımlamak için yeni bir yazı fikri: gereksiz toplantılar.", "Uzaktan çalışma hakkında hangi yazı fikri vardı?", "yalnız"),
    ("tr", "Beğendiğim Repolar", ["https://github.com/example/notes-cli — terminalde not tutma aracı."],
     "Şu repoyu da beğendim, fotoğraflardan metin çıkarıyor ve tamamen yerelde çalışıyor: https://github.com/example/ocr-local",
     "Terminalde not tutma aracının linki neydi?", "notes-cli"),
    ("en", "Useful Repos", ["https://github.com/example/feed-reader — a tiny RSS reader."],
     "Found a nice repo that turns screenshots into Markdown, all offline: https://github.com/example/shot2md",
     "Which repo was the RSS reader?", "feed-reader"),
    ("tr", "Adres Defteri", ["Kuzenim Deniz: Lale Sokak No 4, Yeşilköy."],
     "Tamircinin adresi: Sanayi Sitesi 3. Blok No 12, kapı numarası 7.", "Deniz'in adresi ne?", "Lale"),
]

PROJECTS += [
    ("tr", "Tarif Uygulaması", ["Uygulama tarifleri fotoğraftan okuyacak."], [("veritabanı", "SQLite")],
     ["Ekran taslaklarını çiz"],
     ["Uygulama, malzemeler bitince onları alışveriş listesine kendisi eklemeli.",
      "Kullanıcı tarifin porsiyonunu değiştirince miktarlar da ona göre güncellenmeli."],
     [("tasarım", "Material 3", "Android'de doğal duruyor")], ["Beta testçileri bul"],
     ["Ekran taslaklarını çizdim, tarif uygulaması için o iş tamam.", "Tarif uygulaması: ekran taslakları çizildi."],
     "Tarif uygulaması: rakip üç uygulamayı inceledim.", "rakip"),
]

NEW_LISTS += [
    ("tr", "Bir blog yazısı fikrim var: yapay zekâyla yazılmış metinleri insanların nasıl fark ettiğini anlatmak.",
     r"^topics/[^/]*(blog|yazi|fikir)[^/]*\.md$", "fark"),
    ("tr", "Güzel bir repo buldum, PDF'leri sesli kitaba çeviriyor: https://github.com/example/pdf2audio",
     r"^topics/[^/]*(repo|github|arac)[^/]*\.md$", "pdf2audio"),
    ("en", "Nice repo I found, it syncs dotfiles across machines: https://github.com/example/dotsync",
     r"^topics/[^/]*(repo|github|tool)[^/]*\.md$", "dotsync"),
    ("tr", "Vize başvurusu için önce konsolosluktan randevu almak gerekiyor, sonuç yaklaşık 15 günde çıkıyor.",
     r"^topics/[^/]*vize[^/]*\.md$", "15"),
    ("tr", "Akşam yemeğinde 90 euro ödedik, dört kişiye bölünce kişi başı 22,50 euro düştü.",
     r"^topics/[^/]*(masraf|harcama|hesap)[^/]*\.md$", "22,50"),
    ("en", "We paid 72 euros for the taxi, split three ways that's 24 each.",
     r"^topics/[^/]*(expense|cost|split)[^/]*\.md$", "24"),
]

PLANS += [
    ("tr", "Perşembe sabah 5'te havalimanına çıkacağım, Atina uçuşum var.", "2026-10-22 05:00"),
    ("en", "Saturday at 6 I'm leaving for the airport, my flight to Lisbon is at nine.", "2026-10-24 06:00"),
]

REMINDERS += [
    ("tr", "Resmi İşlemler", "topic", "Pazartesi sabah 8'de nüfus müdürlüğünü aramamı hatırlat.", "2026-10-19 08:00", "nüfus"),
    ("tr", "Ortak Masraflar", "topic", "Ayın 1'inde kirayı bölüştürmeyi hatırlat.", "2026-11-01", "kira"),
]

# v9 (#604): more scenarios, weighted to collection, the student's weakest kind
# (v8: 54/73 held-out): a new list beside lists of other kinds, which of several
# similar lists, twin lists, cross-language lists; plus decisions and questions
# phrased without the note's title.
NEW_LISTS += [
    ("en", "Cheese to try: a smoked Scamorza.", r"^topics/[^/]*cheese[^/]*\.md$", "Scamorza"),
    ("en", "Whisky to try: a peated Islay single malt.", r"^topics/[^/]*whisk[^/]*\.md$", "Islay"),
    ("en", "Perfume I'd like to smell in a shop: Terre d'Hermès.", r"^topics/[^/]*(perfume|fragrance|scent)[^/]*\.md$", "Terre"),
    ("en", "Baby name we like: Elodie.", r"^topics/[^/]*name[^/]*\.md$", "Elodie"),
    ("en", "Knitting pattern to try: a cabled beanie.", r"^topics/[^/]*knit[^/]*\.md$", "beanie"),
    ("en", "LEGO set I want: the bonsai tree.", r"^topics/[^/]*lego[^/]*\.md$", "bonsai"),
    ("en", "Bird I want to spot this spring: a hoopoe.", r"^topics/[^/]*bird[^/]*\.md$", "hoopoe"),
    ("en", "Magic trick I want to show the kids: the French drop.", r"^topics/[^/]*(magic|trick)[^/]*\.md$", "French drop"),
    ("en", "Chess opening to study: the Caro-Kann.", r"^topics/[^/]*(chess|opening)[^/]*\.md$", "Caro-Kann"),
    ("en", "Font I like for headings: Fraunces.", r"^topics/[^/]*(font|typeface)[^/]*\.md$", "Fraunces"),
    ("en", "Side project idea: a CLI that renames photos by date.", r"^topics/[^/]*(idea|side)[^/]*\.md$", "renames"),
    ("en", "Word I want to remember: sonder.", r"^topics/[^/]*(word|vocab)[^/]*\.md$", "sonder"),
    ("en", "Quote I liked: the obstacle is the way.", r"^topics/[^/]*quote[^/]*\.md$", "obstacle"),
    ("en", "Mechanical keyboard I'm eyeing: a Keychron Q1.", r"^topics/[^/]*keyboard[^/]*\.md$", "Keychron"),
    ("en", "Newsletter to subscribe to: Money Stuff.", r"^topics/[^/]*newsletter[^/]*\.md$", "Money Stuff"),
    ("en", "YouTube channel to follow: Practical Engineering.", r"^topics/[^/]*(youtube|channel)[^/]*\.md$", "Practical Engineering"),
    ("en", "Camera lens I'd like: a 35mm f/1.8.", r"^topics/[^/]*(lens|camera)[^/]*\.md$", "35mm"),
    ("tr", "Denenecek peynir: Ezine'den eski kaşar.", r"^topics/[^/]*peynir[^/]*\.md$", "kaşar"),
    ("tr", "Bebek ismi fikri: Defne.", r"^topics/[^/]*(isim|bebek)[^/]*\.md$", "Defne"),
    ("tr", "Denemek istediğim parfüm: bir vetiver kokusu.", r"^topics/[^/]*(parfum|koku)[^/]*\.md$", "vetiver"),
    ("tr", "Örgü modeli fikri: burgulu bere.", r"^topics/[^/]*orgu[^/]*\.md$", "bere"),
    ("tr", "Almak istediğim lego seti: bir deniz feneri.", r"^topics/[^/]*lego[^/]*\.md$", "deniz feneri"),
    ("tr", "Bu bahar görmek istediğim kuş: arıkuşu.", r"^topics/[^/]*kus[^/]*\.md$", "arıkuşu"),
    ("tr", "Sihirbazlık numarası fikri: kaybolan bozuk para.", r"^topics/[^/]*(sihir|numara)[^/]*\.md$", "bozuk para"),
    ("tr", "Çalışacağım satranç açılışı: Sicilya savunması.", r"^topics/[^/]*(satranc|acilis)[^/]*\.md$", "Sicilya"),
    ("tr", "Beğendiğim yazı tipi: IBM Plex Sans.", r"^topics/[^/]*(yazi|font)[^/]*\.md$", "Plex"),
    ("tr", "Yan proje fikri: durağa gelen otobüsleri gösteren bir ekran.", r"^topics/[^/]*(fikir|proje)[^/]*\.md$", "otobüs"),
    ("tr", "Aklımda kalsın diye bir kelime: yakamoz.", r"^topics/[^/]*kelime[^/]*\.md$", "yakamoz"),
    ("tr", "Hoşuma giden bir söz: damlaya damlaya göl olur.", r"^topics/[^/]*(soz|alinti)[^/]*\.md$", "damlaya"),
    ("tr", "Almak istediğim klavye: sessiz tuşlu bir mekanik klavye.", r"^topics/[^/]*klavye[^/]*\.md$", "sessiz"),
    ("tr", "Abone olmak istediğim bülten: haftalık bir bilim bülteni.", r"^topics/[^/]*bulten[^/]*\.md$", "bilim"),
    ("tr", "Takip edilecek YouTube kanalı: Usta Marangoz.", r"^topics/[^/]*(youtube|kanal)[^/]*\.md$", "Usta Marangoz"),
    ("tr", "Almak istediğim objektif: 50mm f/1.8.", r"^topics/[^/]*(objektif|kamera)[^/]*\.md$", "50mm"),
]

FIRST_OF_KIND += [
    ("en", "Just started Remarkably Bright Creatures.", r"^topics/[^/]*book[^/]*\.md$", "Remarkably Bright"),
    ("en", "Finished the first chapter of The Thursday Murder Club tonight.", r"^topics/[^/]*book[^/]*\.md$", "Thursday Murder Club"),
    ("en", "My sister lent me Circe, I'm reading it now.", r"^topics/[^/]*book[^/]*\.md$", "Circe"),
    ("en", "Watching Paddington 2 with the kids tonight.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Paddington"),
    ("en", "Film recommendation from work: The Lunchbox.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Lunchbox"),
    ("en", "Recipe I want to make: pork belly bao buns.", r"^topics/[^/]*recipe[^/]*\.md$", "bao"),
    ("en", "Saw a recipe for a crispy gnocchi traybake, want to try it.", r"^topics/[^/]*recipe[^/]*\.md$", "traybake"),
    ("en", "Someday I want to see the northern lights in Tromsø.", r"^topics/[^/]*(place|visit|travel)[^/]*\.md$", "Tromsø"),
    ("en", "I'd love to walk around Granada one day.", r"^topics/[^/]*(place|visit|travel)[^/]*\.md$", "Granada"),
    ("en", "Gift idea for Mum's birthday: a silk pillowcase.", r"^topics/[^/]*gift[^/]*\.md$", "pillowcase"),
    ("en", "Podcast someone recommended: Revisionist History.", r"^topics/[^/]*podcast[^/]*\.md$", "Revisionist"),
    ("en", "Restaurant to try: a Georgian place called Supra.", r"^topics/[^/]*restaurant[^/]*\.md$", "Supra"),
    ("en", "Album to listen to properly: Kind of Blue.", r"^topics/[^/]*(album|music)[^/]*\.md$", "Kind of Blue"),
    ("tr", "Bu aralar Benim Adım Kırmızı'yı okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Benim Adım Kırmızı"),
    ("tr", "Annemin önerdiği Sessiz Ev'e başladım.", r"^topics/[^/]*kitap[^/]*\.md$", "Sessiz Ev"),
    ("tr", "Metroda Kafamda Bir Tuhaflık okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Tuhaflık"),
    ("tr", "Bu gece Muhsin Bey'i izleyeceğim.", r"^topics/[^/]*film[^/]*\.md$", "Muhsin Bey"),
    ("tr", "Arkadaşım Tabutta Rövaşata'yı önerdi, izlemek istiyorum.", r"^topics/[^/]*film[^/]*\.md$", "Rövaşata"),
    ("tr", "Denenecek yemek: fırında kabak mücveri.", r"^topics/[^/]*(tarif|yemek)[^/]*\.md$", "mücver"),
    ("tr", "Yapmak istediğim tarif: cevizli tarhana çorbası.", r"^topics/[^/]*(tarif|yemek)[^/]*\.md$", "tarhana"),
    ("tr", "Bir gün Kemaliye'ye gitmek istiyorum.", r"^topics/[^/]*(gez|yer)[^/]*\.md$", "Kemaliye"),
    ("tr", "Gezmek istediğim yer: Şirince.", r"^topics/[^/]*(gez|yer)[^/]*\.md$", "Şirince"),
    ("tr", "Kardeşime hediye fikri: bir deri cüzdan.", r"^topics/[^/]*hediye[^/]*\.md$", "cüzdan"),
    ("tr", "Dinlenecek podcast: Bir Şehir Bir Hikâye.", r"^topics/[^/]*podcast[^/]*\.md$", "Bir Şehir"),
    ("tr", "Gidilecek restoran: Kadıköy'de Lokanta Nar.", r"^topics/[^/]*(restoran|lokanta)[^/]*\.md$", "Lokanta Nar"),
    ("tr", "Dinlemek istediğim albüm: Gece Yolcuları.", r"^topics/[^/]*(album|muzik)[^/]*\.md$", "Gece Yolcuları"),
]

MIXED_LISTS += [
    ("en", {"books": "Books by the Bed", "podcasts": "Podcast Queue", "restaurants": "Restaurants Nearby", "gifts": "Gift Ideas for Friends"}, [
        ("Started Wolf Hall on the bus today.", "books", "Wolf Hall"),
        ("Next up: The Dutch House.", "books", "Dutch House"),
        ("Podcast to queue: Darknet Diaries.", "podcasts", "Darknet Diaries"),
        ("I should listen to Planet Money.", "podcasts", "Planet Money"),
        ("Restaurant to try near us: Osteria Lupa.", "restaurants", "Osteria Lupa"),
        ("Heard the new ramen bar Kumo is great, want to go.", "restaurants", "Kumo"),
        ("Gift idea for Ece: a pottery class voucher.", "gifts", "voucher"),
        ("For Jonah's birthday: a field guide to mushrooms.", "gifts", "mushrooms"),
    ]),
    ("en", {"films": "Films for Sunday", "places": "Travel Someday", "recipes": "Weeknight Recipes", "music": "Albums to Hear"}, [
        ("Film for Sunday afternoon: Cinema Paradiso.", "films", "Cinema Paradiso"),
        ("I want to watch Roman Holiday again.", "films", "Roman Holiday"),
        ("Someday: a road trip through Scotland.", "places", "Scotland"),
        ("I'd love to visit Oaxaca.", "places", "Oaxaca"),
        ("Weeknight recipe to try: sheet pan fajitas.", "recipes", "fajitas"),
        ("Quick dinner idea: peanut noodles.", "recipes", "peanut"),
        ("Album to hear in full: Rumours.", "music", "Rumours"),
        ("I should finally listen to OK Computer.", "music", "OK Computer"),
    ]),
    ("tr", {"books": "Başucu Kitapları", "podcasts": "Dinlenecek Podcastler", "restaurants": "Gidilecek Restoranlar", "gifts": "Hediye Fikirleri"}, [
        ("Başucumda şimdi Kuyruklu Yıldız Altında Bir İzdivaç var.", "books", "İzdivaç"),
        ("Okumak istediğim kitap: Bir Tereddüdün Romanı.", "books", "Tereddüdün"),
        ("Dinlenecek podcast: Kayıp Arşiv.", "podcasts", "Kayıp Arşiv"),
        ("Şu podcasti dinlemeliyim: Gece Masalları.", "podcasts", "Gece Masalları"),
        ("Gidilecek restoran: Karaköy'de Balıkçı Selim.", "restaurants", "Balıkçı Selim"),
        ("Moda'da yeni bir meyhane açılmış, Asmalı Avlu, gitmek istiyorum.", "restaurants", "Asmalı Avlu"),
        ("Ablama hediye: seramik bir vazo.", "gifts", "vazo"),
        ("Hediye fikri: dedeme büyüteçli bir okuma lambası.", "gifts", "okuma lambası"),
    ]),
    ("tr", {"films": "Hafta Sonu Filmleri", "places": "Gezi Hayalleri", "recipes": "Hafta İçi Yemekleri", "music": "Dinlenecek Müzikler"}, [
        ("Hafta sonu izlenecek: Masumlar Apartmanı.", "films", "Masumlar Apartmanı"),
        ("Şu filmi izlemek istiyorum: Ayla.", "films", "Ayla"),
        ("Bir gün Van Gölü'nün etrafını dolaşmak istiyorum.", "places", "Van Gölü"),
        ("Gezilecek yer: Harran.", "places", "Harran"),
        ("Hafta içi yemeği: fırında mantarlı makarna.", "recipes", "mantarlı makarna"),
        ("Kolay akşam yemeği fikri: ıspanaklı yumurta.", "recipes", "ıspanaklı yumurta"),
        ("Dinlenecek albüm: Moğollar'ın ilk albümü.", "music", "Moğollar"),
        ("Şu albümü baştan sona dinlemeliyim: Anadolu Pop Derlemesi.", "music", "Anadolu Pop"),
    ]),
]

# Twin lists beyond now and later: done and to do, one person and another, work and fun.
TWIN_LISTS += [
    ("en", "Films Watched This Year", "Films for Later", [
        ("Watched Oppenheimer last night, loved it.", True, "Oppenheimer"),
        ("Just saw The Iron Claw at the cinema.", True, "Iron Claw"),
        ("Want to watch Godzilla Minus One sometime.", False, "Godzilla"),
        ("Someone said I must see Prisoners, adding it for later.", False, "Prisoners"),
    ]),
    ("en", "Places I've Been", "Places I Want to Go", [
        ("We got back from Sarajevo last week.", True, "Sarajevo"),
        ("Spent the weekend in Bruges.", True, "Bruges"),
        ("One day I'd like to see Petra.", False, "Petra"),
        ("Dream trip: the Azores.", False, "Azores"),
    ]),
    ("en", "Recipes That Worked", "Recipes to Try Later", [
        ("Made the cardamom buns again, they came out great.", True, "cardamom"),
        ("The aubergine parmigiana worked really well.", True, "parmigiana"),
        ("Want to try a Thai green curry sometime.", False, "green curry"),
        ("Saw a recipe for French onion soup, will try it later.", False, "onion soup"),
    ]),
    ("en", "Gift Ideas for Mom", "Gift Ideas for Dad", [
        ("Mom would love a reading light.", True, "reading light"),
        ("For Mom: a cashmere cardigan.", True, "cardigan"),
        ("Dad needs a new toolbox.", False, "toolbox"),
        ("Gift for Dad: a good pair of gardening gloves.", False, "gardening gloves"),
    ]),
    ("en", "Work Reading", "Fun Reading", [
        ("For work I'm reading The Phoenix Project.", True, "Phoenix Project"),
        ("Started Team Topologies for the job.", True, "Team Topologies"),
        ("Just for fun I'm reading Good Omens.", False, "Good Omens"),
        ("Holiday read: The Rosie Project.", False, "Rosie Project"),
    ]),
    ("tr", "İzlediğim Filmler", "İzlenecekler", [
        ("Dün akşam Babamın Sesi'ni izledim, çok güzeldi.", True, "Babamın Sesi"),
        ("Geçen hafta Kurak Günler'i izledim.", True, "Kurak Günler"),
        ("İzlemek istediğim film: Annemin Şarkısı.", False, "Annemin Şarkısı"),
        ("Bir ara Klondike'ı izlemeliyim.", False, "Klondike"),
    ]),
    ("tr", "Gittiğim Yerler", "Gitmek İstediğim Yerler", [
        ("Geçen ay Beypazarı'na gittik.", True, "Beypazarı"),
        ("Hafta sonu Cumalıkızık'taydık.", True, "Cumalıkızık"),
        ("Bir gün Ihlara Vadisi'ni görmek istiyorum.", False, "Ihlara"),
        ("Gitmek istediğim yer: Kekova.", False, "Kekova"),
    ]),
    ("tr", "Annem İçin Hediyeler", "Babam İçin Hediyeler", [
        ("Anneme bir bitki çayı seti alabilirim.", True, "bitki çayı"),
        ("Annem için hediye: yün terlik.", True, "terlik"),
        ("Babama bir el feneri iyi olur.", False, "el feneri"),
        ("Babam için hediye: satranç takımı.", False, "satranç"),
    ]),
    ("tr", "Bitirdiğim Kitaplar", "Okunacak Kitaplar", [
        ("Kiralık Konak'ı bitirdim.", True, "Kiralık Konak"),
        ("Dün gece Fareler ve İnsanlar'ı bitirdim.", True, "Fareler ve İnsanlar"),
        ("Okunacaklara ekle: Dava.", False, "Dava"),
        ("Bir ara Yabancı'yı okumak istiyorum.", False, "Yabancı"),
    ]),
    ("tr", "İş İçin Okuduklarım", "Keyif İçin Okuduklarım", [
        ("İş için Derin Çalışma'yı okuyorum.", True, "Derin Çalışma"),
        ("İş için şu an Atomik Alışkanlıklar okuyorum.", True, "Atomik"),
        ("Keyif için Martı Jonathan Livingston okuyorum.", False, "Martı"),
        ("Tatilde keyfine okumak için: Kumarbaz.", False, "Kumarbaz"),
    ]),
]

COLLECTIONS += [
    ("en", "Wines to Try", "Rioja Reserva",
     ["a Greek Assyrtiko", "a Portuguese Vinho Verde", "a Lebanese red", "an Austrian Grüner"],
     ["Wine to try: {x}.", "Add {x} to the wines to try."]),
    ("en", "Hiking Trails", "Carpathian ridge walk",
     ["the West Highland Way", "the Kumano Kodo", "the Via Dinarica", "the Tour du Mont Blanc"],
     ["Trail to hike one day: {x}.", "Add {x} to my hiking trails."]),
    ("en", "Houseplants Wishlist", "Monstera",
     ["a rubber fig", "a ZZ plant", "a peace lily", "a calathea"],
     ["Plant I'd like: {x}.", "Houseplant to get: {x}."]),
    ("en", "Series to Binge", "Mad Men",
     ["Severance", "Shōgun", "The Bear", "Blue Eye Samurai"],
     ["Series to binge: {x}.", "Add {x} to the series list."]),
    ("en", "Online Courses", "Intro to Linear Algebra",
     ["a watercolour course", "a course on Python testing", "a first aid course", "a bookkeeping course"],
     ["Course to take: {x}.", "I'd like to sign up for {x}."]),
    ("tr", "Denenecek Şaraplar", "Kalecik Karası",
     ["bir Narince", "bir Boğazkere", "bir Emir", "bir Sultaniye"],
     ["Denenecek şarap: {x}.", "Şarap listeme {x} ekle."]),
    ("tr", "Yürüyüş Rotaları", "Belgrad Ormanı turu",
     ["Evliya Çelebi Yolu", "Frig Vadisi", "Karia Yolu", "Aziz Pavlus Yolu"],
     ["Yürümek istediğim rota: {x}.", "Rotalara ekle: {x}."]),
    ("tr", "Alınacak Bitkiler", "Kauçuk",
     ["bir orkide", "bir sukulent", "bir zamioculcas", "bir aloe vera"],
     ["Bitki listeme ekle: {x}.", "Eve almak istediğim bitki: {x}."]),
    ("tr", "İzlenecek Diziler", "Leyla ile Mecnun",
     ["Masum", "Kulüp", "Yalancı", "Şahsiyet"],
     ["Dizi listeme {x} ekle.", "Şu diziyi izlemeliyim: {x}."]),
    ("tr", "Katılmak İstediğim Kurslar", "Fotoğrafçılık kursu",
     ["ebru kursu", "ahşap oymacılığı kursu", "işaret dili kursu", "yüzme kursu"],
     ["Kurslara ekle: {x}.", "Gitmek istediğim kurs: {x}."]),
]

# A list item in one language for a list in the other.
CROSS += [
    ("en", "Okuduğum Kitaplar", "topic", "I'm reading The Bastard of Istanbul now.", "collection", "add_note_entry", "Bastard of Istanbul"),
    ("en", "İzlenecek Filmler", "topic", "Film to watch: Climates.", "collection", "add_note_entry", "Climates"),
    ("en", "Denenecek Tarifler", "topic", "Recipe to try: stuffed peppers with rice.", "collection", "add_note_entry", "peppers"),
    ("en", "Gidilecek Yerler", "topic", "Add Bodrum to the places to visit.", "collection", "add_note_entry", "Bodrum"),
    ("en", "Dinlenecek Albümler", "topic", "Album to listen to: Işık Doğudan Yükselir.", "collection", "add_note_entry", "Doğudan"),
    ("en", "Öğrenilecek Konular", "topic", "Something I want to learn: calligraphy.", "collection", "add_note_entry", "calligraphy"),
    ("en", "Okunacak Makaleler", "topic", "Paper to read: the BERT paper.", "collection", "add_note_entry", "BERT"),
    ("en", "Denenecek Şaraplar", "topic", "Wine to try: a Papazkarası.", "collection", "add_note_entry", "Papazkarası"),
    ("tr", "Books I'm Reading", "topic", "Şu an Dorian Gray'in Portresi'ni okuyorum.", "collection", "add_note_entry", "Dorian Gray"),
    ("tr", "Films to Watch", "topic", "İzlenecek film: Roma.", "collection", "add_note_entry", "Roma"),
    ("tr", "Recipes to Try", "topic", "Denenecek tarif: limonlu kuskus salatası.", "collection", "add_note_entry", "kuskus"),
    ("tr", "Places to Visit", "topic", "Bir gün Saraybosna'ya gitmek istiyorum.", "collection", "add_note_entry", "Saraybosna"),
    ("tr", "Gift Ideas", "topic", "Hediye fikri: kuzenime bir bulmaca kitabı.", "collection", "add_note_entry", "bulmaca"),
    ("tr", "Podcasts to Try", "topic", "Denenecek podcast: Serial.", "collection", "add_note_entry", "Serial"),
    ("tr", "Board Games to Buy", "topic", "Alınacak kutu oyunu: Codenames.", "collection", "add_note_entry", "Codenames"),
    ("tr", "Restaurants to Try", "topic", "Gidilecek restoran: Lokanta 1741.", "collection", "add_note_entry", "1741"),
]

# Rows shaped like CROSS; some are cross-language on purpose, like CROSS itself: a decision said without "we
# picked", and a question naming the subject rather than the note (no tool:
# the answer must hold the word).
ON_NOTE = [
    ("en", "Garden Shed", "project", "Garden shed: switching the roof to cedar shingles.", "decision", "record_decision", "cedar"),
    ("en", "Podcast Launch", "project", "Podcast launch moves hosting to Buzzsprout.", "decision", "record_decision", "Buzzsprout"),
    ("en", "Kitchen Renovation", "project", "We're going with brass handles for the kitchen cabinets.", "decision", "record_decision", "brass"),
    ("en", "Marathon Training", "project", "Marathon training: settled on a Garmin Forerunner as the watch.", "decision", "record_decision", "Garmin"),
    ("en", "Boat Restoration", "project", "Boat restoration: the outboard is out, we're going electric with a Torqeedo.", "decision", "record_decision", "Torqeedo"),
    ("en", "Home Office", "project", "Home office: final call on the desk, a walnut sit-stand desk.", "decision", "record_decision", "walnut"),
    ("en", "Community Garden", "project", "Community garden goes with drip irrigation from now on.", "decision", "record_decision", "drip"),
    ("en", "Family Photo Book", "project", "For the photo book, Saal Digital instead of Blurb.", "decision", "record_decision", "Saal"),
    ("en", "Charity Run", "project", "Charity run: the route changes to the riverside path.", "decision", "record_decision", "riverside"),
    ("en", "Board Game Design", "project", "Board game design: the theme is now space salvage, not deep sea.", "decision", "record_decision", "salvage"),
    ("tr", "Mobil Uygulama", "project", "Mobil uygulama artık Firebase yerine Appwrite kullanacak.", "decision", "record_decision", "Appwrite"),
    ("tr", "Düğün Hazırlığı", "project", "Düğün hazırlığı: davetiyede kararımız kraft kâğıt oldu.", "decision", "record_decision", "kraft"),
    ("tr", "Yaz Tatili", "project", "Yaz tatilinde butik otelden vazgeçtik, pansiyonda kalacağız.", "decision", "record_decision", "pansiyon"),
    ("tr", "Blog Sitesi", "project", "Blog sitesini Netlify'dan Cloudflare Pages'e taşıyoruz.", "decision", "record_decision", "Cloudflare"),
    ("tr", "Kahve Dükkanı", "project", "Kahve dükkanında fincanlar için karar: el yapımı seramik.", "decision", "record_decision", "seramik"),
    ("tr", "Köy Evi Onarımı", "project", "Köy evinin çatısında kiremit yerine taş plaka kullanacağız.", "decision", "record_decision", "taş"),
    ("tr", "Satranç Turnuvası", "project", "Satranç turnuvası: süre artık 10 dakika artı 5 saniye.", "decision", "record_decision", "saniye"),
    ("tr", "Ehliyet Kursu", "project", "Ehliyet kursunda manuel vitese geçmeye karar verdim.", "decision", "record_decision", "manuel"),
    ("tr", "Tarif Uygulaması", "project", "Tarif uygulamasında veritabanını SQLite'tan Isar'a çeviriyoruz.", "decision", "record_decision", "Isar"),
    ("tr", "Arıcılık", "project", "Arıcılıkta karar kıldık: kışın kovanları straforla saracağız.", "decision", "record_decision", "strafor"),
    ("en", "Kitchen Renovation", "project", "Which countertop did we go with?", "question", None, "Quartz"),
    ("en", "Marathon Training", "project", "What running shoes did I decide on?", "question", None, "Brooks"),
    ("en", "Home Office", "project", "Which office chair did we choose?", "question", None, "Aeron"),
    ("en", "Garden Shed", "project", "What roof material did we pick for the shed?", "question", None, "Metal"),
    ("en", "Podcast Launch", "project", "Where is the podcast hosted?", "question", None, "Anchor"),
    ("en", "Family Photo Book", "project", "Which printer are we using for the photo book?", "question", None, "Blurb"),
    ("en", "Woodworking Bench", "project", "What kind of vise did I settle on?", "question", None, "Leg"),
    ("en", "Community Garden", "project", "How many plots do we have at the garden?", "question", None, "twelve"),
    ("en", "Boat Restoration", "project", "What is the hull made of?", "question", None, "fibreglass"),
    ("en", "Health", "topic", "Did I note anything about my blood test?", "question", None, "normal"),
    ("tr", "Mobil Uygulama", "project", "Backend olarak ne kullanıyorduk?", "question", None, "Firebase"),
    ("tr", "Düğün Hazırlığı", "project", "Düğüne kaç davetli geliyordu?", "question", None, "120"),
    ("tr", "Blog Sitesi", "project", "Siteyi nerede barındırıyoruz?", "question", None, "Netlify"),
    ("tr", "Kahve Dükkanı", "project", "Hangi espresso makinesini seçmiştik?", "question", None, "Marzocco"),
    ("tr", "Yoga Stüdyosu", "project", "Stüdyonun zemini ne olacaktı?", "question", None, "Mantar"),
    ("tr", "Arıcılık", "project", "Hangi arı ırkını seçtik?", "question", None, "Kafkas"),
    ("tr", "Ehliyet Kursu", "project", "Otomatik mi manuel mi seçmiştim?", "question", None, "Otomatik"),
    ("tr", "Köy Evi Onarımı", "project", "Köy evinin çatısı ne olacaktı?", "question", None, "Kiremit"),
    ("tr", "Araba", "topic", "Lastikler ne zaman değişecekti?", "question", None, "Kasım"),
    ("tr", "Mahalle Pazarı", "project", "Pazar nerede kurulacaktı?", "question", None, "Okul"),
    ("en", "Kahve Dükkanı", "project", "Where will the coffee shop be?", "question", None, "Moda"),
    ("tr", "Home Office", "project", "Çalışma odası için hangi sandalyeyi seçtik?", "question", None, "Aeron"),
    ("en", "Mobil Uygulama", "project", "Which backend does the mobile app use?", "question", None, "Firebase"),
]


# About me (v10, #604): neither v8's nor v9's data has an about-me turn. Both
# models remember a new fact but call remember_about_me where a listed one
# changes, gains a detail or is already there, so updates and known facts weigh
# most. Distilled with the full prompt: the device model has no about-me tools.
REMEMBER, UPDATE, KNOWN, FORGET = "remember", "update", "known", "forget"
ABOUT_ME = [
    # (lang, facts by section, message, what it should do, words about-me.md then holds)
    ("tr", {"family": ["Evliyim, eşim Burcu."]}, "Bu arada Kadıköy'de oturuyorum.", REMEMBER, ["## Ev", "Kadıköy"]),
    ("tr", {"work": ["Bir bankada analistim."]}, "Annemin adı Nermin, babamınki Hüseyin.", REMEMBER, ["## Aile", "Nermin"]),
    ("tr", {"home": ["Eskişehir'de oturuyorum."]}, "Bir mimarlık ofisinde proje yöneticisi olarak çalışıyorum.", REMEMBER, ["## İş", "mimarlık"]),
    ("tr", {"family": ["İki kızım var."]}, "Bana Can diye hitap etmeni isterim, Cankat uzun geliyor.", REMEMBER, ["Can"]),
    ("tr", {}, "Kardeşim Oğuz Almanya'da yaşıyor, Köln'de.", REMEMBER, ["Oğuz"]),
    ("tr", {"work": ["Öğretmenim."]}, "Okul müdürümüzün adı Sevgi Hanım.", REMEMBER, ["Sevgi"]),
    ("tr", {"family": ["Eşim Gamze."]}, "Vejetaryenim, yemek önerirken bunu bil.", REMEMBER, ["ejetaryen"]),
    ("tr", {"home": ["Antalya'da yaşıyorum."]}, "Oğlum Efe 4 yaşında, anaokuluna gidiyor.", REMEMBER, ["## Aile", "Efe"]),
    ("en", {"family": ["My husband is Marco."]}, "I work as a nurse at St. Mary's hospital.", REMEMBER, ["## Work", "nurse"]),
    ("en", {"work": ["I'm a freelance translator."]}, "We live in Leeds, near the university.", REMEMBER, ["## Home", "Leeds"]),
    ("en", {"home": ["I live in Porto."]}, "My daughter Lina is 10 and my son Oskar is 6.", REMEMBER, ["## Family", "Lina", "Oskar"]),
    ("en", {}, "Please call me Jo, nobody uses Johanna.", REMEMBER, ["Jo"]),
    ("en", {"family": ["I'm married to Grace."]}, "My sister Hannah lives in Dublin and teaches piano.", REMEMBER, ["Hannah"]),
    ("en", {"work": ["I run a small bakery."]}, "My business partner at the bakery is Felix.", REMEMBER, ["Felix"]),
    ("en", {"home": ["I live in Ghent."]}, "I don't drink coffee, only tea, keep that in mind for suggestions.", REMEMBER, ["tea"]),
    ("en", {}, "I'm a software tester at a game studio in Łódź.", REMEMBER, ["## Work", "Łódź"]),

    ("tr", {"family": ["Evliyim ve bir oğlum var."]}, "Oğlumun adı Kerem.", UPDATE, ["Kerem"]),
    ("tr", {"family": ["Eşim Burcu."]}, "Burcu bu yıl öğretmenliğe başladı.", UPDATE, ["öğretmen"]),
    ("tr", {"home": ["Eskişehir'de oturuyorum."]}, "Geçen hafta Bursa'ya taşındık.", UPDATE, ["Bursa"]),
    ("tr", {"work": ["Bir bankada analistim."]}, "Bankadan ayrıldım, artık bir sigorta şirketinde risk uzmanıyım.", UPDATE, ["sigorta"]),
    ("tr", {"family": ["Kızım Defne 5 yaşında."]}, "Defne bugün 6 yaşına bastı.", UPDATE, ["6"]),
    ("tr", {"family": ["Bir kız kardeşim var."]}, "Kız kardeşimin adı Melis.", UPDATE, ["Melis"]),
    ("tr", {"home": ["Ankara'da, Çankaya'da oturuyorum."]}, "Çankaya'dan Etimesgut'a taşındık.", UPDATE, ["Etimesgut"]),
    ("tr", {"work": ["Yazılım geliştiriciyim."]}, "Bu ay takım liderliğine terfi ettim.", UPDATE, ["lider"]),
    ("tr", {"family": ["Annem Nermin, Sivas'ta yaşıyor."]}, "Annem artık Sivas'ta değil, bizimle birlikte yaşıyor.", UPDATE, ["birlikte"]),
    ("tr", {"other": ["Bana Mehmet diye hitap et."]}, "Artık bana Memo de, herkes öyle diyor.", UPDATE, ["Memo"]),
    ("tr", {"family": ["Evliyim."]}, "Eşimin adı Tuba.", UPDATE, ["Tuba"]),
    ("tr", {"family": ["Oğlum Efe anaokuluna gidiyor."]}, "Efe bu yıl ilkokula başladı.", UPDATE, ["ilkokul"]),
    ("tr", {"work": ["Öğretmenim."]}, "Lisede matematik öğretmeniyim bu arada.", UPDATE, ["matematik"]),
    ("tr", {"home": ["Bir apartman dairesinde oturuyorum."]}, "Daireden çıktık, bahçeli bir eve geçtik.", UPDATE, ["bahçeli"]),
    ("en", {"family": ["I have a daughter."]}, "My daughter's name is Freya.", UPDATE, ["Freya"]),
    ("en", {"family": ["I'm married."]}, "My wife's name is Noor.", UPDATE, ["Noor"]),
    ("en", {"home": ["I live in Leeds."]}, "We moved from Leeds to York in the spring.", UPDATE, ["York"]),
    ("en", {"work": ["I'm a junior designer at Brightline."]}, "I got promoted to senior designer at Brightline.", UPDATE, ["senior"]),
    ("en", {"family": ["My son Oskar is 6."]}, "Oskar is 7 now.", UPDATE, ["7"]),
    ("en", {"work": ["I work at a bookshop."]}, "I left the bookshop, I'm a librarian at the city library now.", UPDATE, ["librarian"]),
    ("en", {"family": ["I have a brother."]}, "My brother is called Ravi.", UPDATE, ["Ravi"]),
    ("en", {"other": ["Call me Johanna."]}, "Actually, just call me Jo from now on.", UPDATE, ["Jo"]),
    ("en", {"home": ["I live in a flat in Porto."]}, "We bought a house in Matosinhos and moved last week.", UPDATE, ["Matosinhos"]),
    ("en", {"family": ["My husband Marco is a chef."]}, "Marco opened his own restaurant this year.", UPDATE, ["restaurant"]),
    ("en", {"work": ["I'm a nurse."]}, "I'm a nurse on the children's ward, by the way.", UPDATE, ["children"]),
    ("en", {"family": ["We have a dog."]}, "Our dog is called Biscuit.", UPDATE, ["Biscuit"]),
    ("en", {"family": ["My mum lives in Cork."]}, "Mum moved in with us in Galway last month.", UPDATE, ["Galway"]),

    ("tr", {"home": ["Kadıköy'de, Moda'da oturuyorum."]}, "Bu arada Kadıköy'de yaşıyorum.", KNOWN, []),
    ("tr", {"family": ["Eşim Gamze, iki kızımız var."]}, "Eşimin adı Gamze.", KNOWN, []),
    ("tr", {"work": ["Bir bankada analistim."]}, "Bankada analist olarak çalışıyorum.", KNOWN, []),
    ("tr", {"family": ["Oğlum Kerem 9 yaşında."]}, "Oğlum Kerem dokuz yaşında.", KNOWN, []),
    ("tr", {"other": ["Bana Can diye hitap et."]}, "Bana Can de.", KNOWN, []),
    ("tr", {"home": ["Eskişehir'de oturuyorum."]}, "Eskişehir'de yaşıyorum, bilgin olsun.", KNOWN, []),
    ("en", {"home": ["I live in York."]}, "I live in York, just so you know.", KNOWN, []),
    ("en", {"family": ["My wife is Noor."]}, "Noor is my wife.", KNOWN, []),
    ("en", {"work": ["I'm a librarian at the city library."]}, "I work at the city library.", KNOWN, []),
    ("en", {"family": ["My daughter Freya is 4."]}, "Freya is four.", KNOWN, []),
    ("en", {"other": ["I don't drink coffee, only tea."]}, "Remember, no coffee for me, just tea.", KNOWN, []),
    ("en", {"work": ["I run a small bakery with Felix."]}, "Felix and I run the bakery together.", KNOWN, []),

    ("tr", {"family": ["Eşim Gamze."], "other": ["Bana Can diye hitap et."]}, "Bana Can deme artık, o bilgiyi sil.", FORGET, []),
    ("tr", {"home": ["Bursa'da oturuyorum."], "work": ["Bir sigorta şirketinde çalışıyorum."]}, "Sigorta şirketinde çalıştığım bilgisi yanlış, unut onu.", FORGET, []),
    ("tr", {"family": ["Bir kız kardeşim var, Melis."]}, "Kız kardeşimle ilgili bilgiyi kaldır lütfen.", FORGET, []),
    ("tr", {"other": ["Vejetaryenim."]}, "Vejetaryen değilim, o yanlış kaydedilmiş, sil.", FORGET, []),
    ("en", {"other": ["Call me Jo."]}, "Forget the bit about calling me Jo.", FORGET, []),
    ("en", {"family": ["My brother Ravi lives in Pune."]}, "Please remove what you know about my brother.", FORGET, []),
    ("en", {"work": ["I'm a nurse on the children's ward."]}, "That nurse thing is wrong, forget it.", FORGET, []),
    ("en", {"home": ["I live in Ghent."]}, "Forget where I live.", FORGET, []),
]

# A fact in a note, moved to About me when the user asks: (lang, facts, note
# title, its entry, message, words about-me.md then holds).
ABOUT_ME_MOVES = [
    ("tr", {"family": ["Eşim Burcu."]}, "Ev İşleri", "Ev adresim: Bahçelievler Mah. 1453 Sokak No: 7, Çankaya.",
     "Ev İşleri notundaki adresimi Hakkımda'ya taşı.", ["1453 Sokak"]),
    ("tr", {"work": ["Ar-Ge biriminde çalışıyorum."]}, "Çalışma Notları", "Yöneticim Levent Bey, Ar-Ge biriminde.",
     "Çalışma notlarımdaki yöneticimin adını hakkımdaki bilgilere ekle, nottan da kaldır.", ["Levent"]),
    ("tr", {"family": ["Annem Nermin."]}, "Aile Doğum Günleri", "Annemin doğum günü 14 Mart.",
     "Annemin doğum gününü Aile Doğum Günleri notundan Hakkımda'ya taşı.", ["14 Mart"]),
    ("tr", {"family": ["Kızım Defne 7 yaşında."]}, "Okul İşleri", "Kızım Defne 2-B sınıfında, öğretmeni Aylin Hanım.",
     "Okul işleri notunda Defne'nin sınıfı yazıyor, onu Hakkımda'ya al.", ["2-B"]),
    ("tr", {"home": ["Ankara'da oturuyorum."]}, "Taşınma", "Yeni adresimiz: Gazi Cad. No: 12, Etimesgut.",
     "Taşınma notundaki yeni adresimizi hakkımdaki bilgilere taşı.", ["Gazi Cad"]),
    ("en", {"family": ["My wife is Noor."]}, "Admin Stuff", "My home address is 4 Harbour Row, Galway.",
     "Move my home address from Admin Stuff into About me.", ["Harbour Row"]),
    ("en", {"work": ["I'm a designer at Brightline."]}, "Work Notes", "My line manager is Dana Whitfield.",
     "Put my manager's name from Work Notes into About me and take it out of the note.", ["Dana"]),
    ("en", {"family": ["My daughter Lina is 10."]}, "School Run", "Lina is in year 5, her teacher is Mr Okafor.",
     "Move Lina's class from the School Run note to About me.", ["year 5"]),
    ("en", {"home": ["I live in York."]}, "Moving House", "Our new address: 22 Mill Lane, York.",
     "Take our new address from Moving House and keep it in About me.", ["Mill Lane"]),
    ("en", {"family": ["I'm married to Grace."]}, "Family Notes", "My father-in-law is called Bernard.",
     "Move my father-in-law's name from Family Notes into About me.", ["Bernard"]),
]

# Not about the user: a plan with someone the facts name, a thing they own, a
# project's work, a question the facts answer, or health, which is asked about
# first. (lang, facts, note title and kind or None, message, tool or None, word)
ABOUT_ME_NOT = [
    ("tr", {"family": ["Eşim Burcu."]}, ("Aile Planları", "topic"), "Eşimle cumartesi akşamı tiyatroya gideceğiz.", "add_reminder", "Burcu"),
    ("tr", {"family": ["Oğlum Kerem 9 yaşında."]}, ("Aile Planları", "topic"), "Oğlumun pazartesi saat 4'te dişçi randevusu var.", "add_reminder", "Kerem"),
    ("tr", {"family": ["Annem Nermin."]}, ("Aile Planları", "topic"), "Annemle pazar günü kahvaltıya gideceğiz.", "add_reminder", "Nermin"),
    ("en", {"family": ["My wife is Noor."]}, ("Family Plans", "topic"), "My wife and I are going to a concert on Friday night.", "add_reminder", "Noor"),
    ("en", {"family": ["My son Oskar is 7."]}, ("Family Plans", "topic"), "My son has football practice on Wednesday at 5.", "add_reminder", "Oskar"),
    ("en", {"family": ["My mum is Ellen."]}, ("Family Plans", "topic"), "Taking my mum to the eye doctor on Tuesday at 10.", "add_reminder", "Ellen"),
    ("tr", {"home": ["Bursa'da oturuyorum."]}, ("Otomobil Bakımı", "topic"), "Arabanın lastik basıncı önde 2.3 bar olmalı.", "add_note_entry", "2.3"),
    ("tr", {"home": ["Bahçeli bir evde oturuyorum."]}, ("Ev Bakımı", "topic"), "Kombinin modeli Vaillant ecoTEC, servisi yılda bir.", "add_note_entry", "Vaillant"),
    ("en", {"home": ["I live in York."]}, ("Car", "topic"), "The car takes 5W-30 oil, next change at 60,000 km.", "add_note_entry", "5W-30"),
    ("en", {"home": ["I live in a house in Matosinhos."]}, ("House Maintenance", "topic"), "The boiler is a Baxi 800, serviced every October.", "add_note_entry", "Baxi"),
    ("tr", {"work": ["Bir mimarlık ofisinde proje yöneticisiyim."]}, ("Kütüphane Projesi", "project"), "Kütüphane projesinde cephe için tuğlayı seçtik.", "record_decision", "tuğla"),
    ("tr", {"work": ["Takım lideriyim."]}, ("Kurye Uygulaması", "project"), "Kurye uygulaması için yapılacak: giriş ekranını yeniden tasarla.", "add_todo", "giriş"),
    ("en", {"work": ["I'm a senior designer at Brightline."]}, ("Brightline Rebrand", "project"), "Brightline rebrand: we picked teal as the main colour because it tested best.", "record_decision", "teal"),
    ("en", {"work": ["I run a small bakery with Felix."]}, ("Bakery Website", "project"), "Add a todo to the bakery website: upload the new menu photos.", "add_todo", "photos"),
    ("tr", {"family": ["Kızım Defne 6 yaşında."]}, None, "Kızım kaç yaşındaydı?", None, "6"),
    ("tr", {"home": ["Bursa'da, Görükle'de oturuyorum."]}, None, "Hangi semtte oturduğumu biliyor musun?", None, "Görükle"),
    ("en", {"work": ["I'm a librarian at the city library."]}, None, "Where do I work again?", None, "library"),
    ("en", {"family": ["My brother Ravi lives in Pune."]}, None, "Which city does my brother live in?", None, "Pune"),
    ("tr", {"home": ["Eskişehir'de oturuyorum."]}, None, "Şeker hastasıyım bu arada.", None, "?"),
    ("en", {"work": ["I'm a freelance translator."]}, None, "I have asthma, by the way.", None, "?"),
]

ABOUT_ME_TOOLS = ["remember_about_me", "update_about_me", "forget_about_me"]
SECTIONS = {"work": ("Work", "İş"), "home": ("Home", "Ev"), "family": ("Family", "Aile"),
            "health": ("Health", "Sağlık"), "other": ("Other", "Diğer")}


def about_me(facts, lang):
    """about-me.md as the app writes it (store/about_me.dart)."""
    parts = ["# About me", ""]
    for key, (en, tr) in SECTIONS.items():
        if key in facts:
            parts += [f"## {tr if lang == 'tr' else en}", ""] + [f"- {fact}" for fact in facts[key]] + [""]
    return "\n".join(parts).rstrip("\n") + "\n"


# A new list beside a list of another kind: a book list being all there is
# makes no film a book (v9's misses on the cases). (lang, the list there,
# message, the new list's path, item)
NEW_BESIDE = [
    ("en", "Novels for the Summer", "Film I want to see: Aftersun.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Aftersun"),
    ("en", "Novels for the Summer", "Recipe to try: miso aubergine.", r"^topics/[^/]*recipe[^/]*\.md$", "miso"),
    ("en", "Weekend Film Picks", "Album to listen to: Blue Rev by Alvvays.", r"^topics/[^/]*(album|music)[^/]*\.md$", "Blue Rev"),
    ("en", "Trips I Want to Take", "Podcast to check out: Song Exploder.", r"^topics/[^/]*podcast[^/]*\.md$", "Song Exploder"),
    ("en", "Dinner Recipes", "Board game to buy: Cascadia.", r"^topics/[^/]*game[^/]*\.md$", "Cascadia"),
    ("en", "Gifts for Friends", "Book to read: Piranesi.", r"^topics/[^/]*(book|read)[^/]*\.md$", "Piranesi"),
    ("tr", "Yaz İçin Romanlar", "İzlemek istediğim film: Kuru Otlar Üstüne.", r"^topics/[^/]*film[^/]*\.md$", "Kuru Otlar"),
    ("tr", "Yaz İçin Romanlar", "Denenecek tarif: fırında karnabahar.", r"^topics/[^/]*tarif[^/]*\.md$", "karnabahar"),
    ("tr", "Hafta Sonu Filmleri", "Dinlenecek albüm: Dünya Yalan Söylüyor.", r"^topics/[^/]*(album|muzik)[^/]*\.md$", "Dünya Yalan"),
    ("tr", "Gitmek İstediğim Şehirler", "Dinlemek istediğim podcast: Medyascope Kültür.", r"^topics/[^/]*podcast[^/]*\.md$", "Medyascope"),
    ("tr", "Akşam Yemeği Tarifleri", "Alınacak kutu oyunu: Azul.", r"^topics/[^/]*oyun[^/]*\.md$", "Azul"),
    ("tr", "Arkadaşlara Hediyeler", "Okumak istediğim kitap: Kürk Mantolu Madonna.", r"^topics/[^/]*(kitap|okuma)[^/]*\.md$", "Kürk Mantolu"),
]

def cases(rng, t=None):
    """The cases [t]'s tables make (this module's by default; the held-out set
    passes its own, #599)."""
    t = t or sys.modules[__name__]
    out = []

    def add(case_id, kind, lang, notes, message, expect):
        out.append({"id": case_id, "kind": kind, "lang": lang, "notes": dict(notes), "message": message, "expect": expect})

    for c, (lang, title, first, items, templates) in enumerate(t.COLLECTIONS):
        p = path("topic", title)
        notes = {p: note(title, "topic", lang, notes=[first])}
        picked = rng.sample(items, t.COLLECTION_PICKS)
        if c < t.RECOVERIES:
            item = next(x for x in items if x not in picked)
            add(f"recover-{slug(title)}", "recovery", lang, notes, rng.choice(templates).format(x=item),
                {"notes": {f"^{re.escape(p)}$": [item.split(" — ")[0]]}, "answer_not": t.NO_TOOL_WORDS})
            out[-1]["fail_first_call"] = True
        for i, item in enumerate(picked):
            # One sentence an item: lists were over half of v2's turns, and it overfit on them.
            for j, template in enumerate(rng.sample(templates, 1)):
                add(f"coll-{slug(title)}-{i}-{j}", "collection", lang, notes, template.format(x=item),
                    {"notes": {f"^{re.escape(p)}$": [item.split(" — ")[0]]}})
        add(f"q-{slug(title)}", "question", lang, notes,
            f"{title} listesinde neler var?" if lang == "tr" else f"What is on my {title} list?",
            {"answer": [first.split(" — ")[0]]})

    for lang, title, nts, decs, todos, facts, new_decs, new_todos, done, other, other_word in t.PROJECTS:
        p = path("project", title)
        notes = {p: note(title, "project", lang, notes=nts, decisions=decs, todos=todos)}
        pat = f"^{re.escape(p)}$"
        for i, fact in enumerate(facts):
            add(f"file-{slug(title)}-{i}", "filing", lang, notes, f"{title}: {fact}", {"tools": ["add_note_entry"], "tools_not": ["complete_todo"], "notes": {pat: [fact.split()[1]]}})
        for i, (topic, value, why) in enumerate(new_decs):
            msg = f"{title}: we picked {value} for the {topic}, {why}." if lang == "en" else f"{title}: {topic} için {value} seçtik, {why}."
            add(f"dec-{slug(title)}{f'-{i}' if i else ''}", "decision", lang, notes, msg, {"tools": ["record_decision"], "notes": {pat: [value.split()[0]]}})
        for i, todo in enumerate(new_todos):
            msg = f"Add a todo to {title}: {todo}." if lang == "en" else f"{title} için yapılacak: {todo}."
            add(f"todo-{slug(title)}{f'-{i}' if i else ''}", "todo", lang, notes, msg, {"tools": ["add_todo"], "notes": {pat: [todo.split()[-1]]}})
        for i, message in enumerate(done):
            add(f"done-{slug(title)}-{i}", "todo-done", lang, notes, message, {"tools": ["complete_todo"], "notes": {pat: []}})
        # Done, but no open todo says so: a dated entry, never a wrong tick (#349). The
        # entry's result names a todo it matches, so the note need not be read first.
        add(f"done-other-{slug(title)}", "filing", lang, notes, other,
            {"tools": ["add_note_entry"], "tools_not": ["complete_todo"], "notes": {pat: [other_word]}})
        topic, value = decs[0]
        q = f"What did we decide for the {title} {topic}?" if lang == "en" else f"{title} için {topic} ne seçmiştik?"
        add(f"q-dec-{slug(title)}", "question", lang, notes, q, {"answer": [value.split()[0]]})
        q = f"What is still open for {title}?" if lang == "en" else f"{title} için yapılacaklar neler?"
        add(f"q-todo-{slug(title)}", "question", lang, notes, q, {"answer": [todos[0].split()[-1]]})

    for lang, title, nts, fact, question, answer in t.TOPICS:
        p = path("topic", title)
        notes = {p: note(title, "topic", lang, notes=nts)}
        add(f"file-{slug(title)}", "filing", lang, notes, fact,
            {"tools_not": ["complete_todo"], "notes": {f"^{re.escape(p)}$": [fact.split()[-1].rstrip(".")]}})
        add(f"q-{slug(title)}", "question", lang, notes, question, {"answer": [answer]})

    for i, (lang, msg) in enumerate(t.CHAT):
        add(f"chat-{i}", "chat", lang, {}, msg, {})
    # The note each reminder belongs to, as its project or topic case wrote it.
    written = {p: text for case in out for p, text in case["notes"].items()}
    for i, (lang, msg, at) in enumerate(t.PLANS):
        add(f"plan-{i}", "plan", lang, {}, msg,
            {"tools": ["add_reminder"], "notes": {r"^(topics|projects)/[^/]*\.md$": [at]}, "answer_not": ["?"]})
    for i, (lang, title, kind, msg, at, word) in enumerate(t.REMINDERS):
        p = path(kind, title)
        add(f"rem-{i}", "reminder", lang, {p: written[p]}, msg,
            {"tools": ["add_reminder"], "notes": {f"^{re.escape(p)}$": [at, word]}})
    for i, (lang, msg) in enumerate(t.UNCLEAR):
        add(f"unclear-{i}", "unclear", lang, {}, msg, {"answer": ["?"]})
    for i, (lang, msg, pattern, item) in enumerate(t.NEW_LISTS):
        add(f"newlist-{i}", "collection", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [item]}})
    for i, (lang, msg, pattern, item) in enumerate(t.FIRST_OF_KIND):
        add(f"newlist-first-{i}", "collection", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [item]}})
    for k, (lang, titles, messages) in enumerate(t.MIXED_LISTS):
        notes = {path("topic", t): note(t, "topic", lang) for t in titles.values()}
        # The first two sets keep their v5 ids, which earlier training rows carry.
        tag = lang if k < 2 else slug(next(iter(titles.values())))
        for i, (msg, kind, item) in enumerate(messages):
            p = path("topic", titles[kind])
            add(f"mixed-{tag}-{i}", "collection", lang, notes, msg, {"notes": {f"^{re.escape(p)}$": [item]}})
    for lang, now, later, messages in t.TWIN_LISTS:
        notes = {path("topic", t): note(t, "topic", lang) for t in (now, later)}
        for i, (msg, is_now, item) in enumerate(messages):
            p = path("topic", now if is_now else later)
            add(f"twin-{slug(now)}-{i}", "collection", lang, notes, msg, {"notes": {f"^{re.escape(p)}$": [item]}})
    for lang, title, kind, nts, decs, todos, messages in t.CONTRAST:
        p = path(kind, title)
        notes = {p: note(title, kind, lang, notes=nts, decisions=decs, todos=todos)}
        for i, (msg, case_kind, tool, word) in enumerate(messages):
            expect = ({"answer": ["?"]} if tool is None else
                      {"tools": [tool], "notes": {f"^{re.escape(p)}$": [word] if word else []}})
            add(f"contrast-{slug(title)}-{i}", case_kind, lang, notes, msg, expect)
    # A message in one language about a note in the other (#599).
    for prefix, rows in (("cross", t.CROSS), ("note", t.ON_NOTE)):
        for i, (lang, title, kind, msg, case_kind, tool, word) in enumerate(rows):
            p = path(kind, title)
            expect = ({"answer": [word]} if tool is None else
                      {"tools": [tool], "notes": {f"^{re.escape(p)}$": [word] if word else []}})
            add(f"{prefix}-{i}", case_kind, lang, {p: written[p]}, msg, expect)
    for i, (lang, msg, pattern, word) in enumerate(t.NEW_PROJECTS):
        add(f"new-{i}", "new-note", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [word] if word else []}})

    for i, (lang, existing, msg, pattern, item) in enumerate(getattr(t, "NEW_BESIDE", ())):
        add(f"newlist-other-{i}", "collection", lang, {path("topic", existing): note(existing, "topic", lang)}, msg,
            {"tools": ["create_note"], "notes": {pattern: [item]}})
    me = r"^about-me\.md$"
    for i, (lang, facts, msg, act, words) in enumerate(getattr(t, "ABOUT_ME", ())):
        notes = {"about-me.md": about_me(facts, lang)}
        expect = ({"tools_not": ABOUT_ME_TOOLS[:2] + ["add_note_entry", "create_note"]} if act == KNOWN else
                  {"tools": [f"{act}_about_me"], "tools_not": [x for x in ABOUT_ME_TOOLS if x != f"{act}_about_me"],
                   "notes": {me: words}})
        add(f"aboutme-{act}-{i}", "about-me", lang, notes, msg, expect)
    for i, (lang, facts, title, entry, msg, words) in enumerate(getattr(t, "ABOUT_ME_MOVES", ())):
        p = path("topic", title)
        notes = {"about-me.md": about_me(facts, lang), p: note(title, "topic", lang, notes=[entry])}
        add(f"aboutme-move-{i}", "about-me", lang, notes, msg,
            {"tools": ["remember_about_me"], "notes": {me: words, f"^{re.escape(p)}$": []}})
    for i, (lang, facts, where, msg, tool, word) in enumerate(getattr(t, "ABOUT_ME_NOT", ())):
        notes = {"about-me.md": about_me(facts, lang)}
        if where is None:
            expect = {"tools_not": ABOUT_ME_TOOLS, "answer": [word]}
        else:
            title, kind = where
            p = path(kind, title)
            notes[p] = note(title, kind, lang)
            expect = {"tools": [tool], "tools_not": ABOUT_ME_TOOLS, "notes": {f"^{re.escape(p)}$": [word]}}
        add(f"aboutme-not-{i}", "about-me", lang, notes, msg, expect)

    # Every workspace holds other notes too, so a case is passed by choosing the
    # right note, not by writing to the only one there (v1 learned that).
    pool = {p: text for case in out for p, text in case["notes"].items() if p != "about-me.md"}
    for case in out:
        # Never a note the case expects: a new list stays new, a choice stays one.
        # A plan may go in any note: its pattern matches all, so it gets distractors as they come.
        patterns = [] if case["kind"] == "plan" else case["expect"].get("notes", {})
        expected = [re.compile(pattern) for pattern in patterns]
        kinds = set().union(*(themes(p) for p in patterns))
        others = sorted(p for p in pool if p not in case["notes"] and not any(e.search(p) for e in expected)
                        and not themes(p) & kinds)
        case["notes"].update({p: pool[p] for p in rng.sample(others, t.DISTRACTORS)})
    return out


ROOT = Path(__file__).resolve().parents[2]


def main(argv):
    out = Path(next((a for a in argv if not a.startswith("--")), ROOT / ".dev-home/train/scenarios.json"))
    seed = int(next((a.split("=", 1)[1] for a in argv if a.startswith("--seed=")), "7"))
    generated = cases(random.Random(seed))
    check(generated)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(generated, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(generated)} scenarios -> {out}")


def norm(text):
    return unicodedata.normalize("NFC", text).casefold()


def title_of(text):
    found = re.search(r"^title: (.*)$", text, re.M)
    return found and found.group(1)  # about-me.md has no front matter


def check(generated):
    """No message or note title of the exam, unique ids, and every expectation
    names exactly one note of its workspace (none for a new note or list)."""
    exam_messages, exam_titles = set(), set()
    for name in ("cases.json", "about-me.json"):
        exam = json.loads((ROOT / "eval" / name).read_text(encoding="utf-8"))
        exam_messages |= {norm(c["message"]) for c in exam["cases"]}
        notes = [*exam["notes"].values(), *(t for c in exam["cases"] for t in c.get("notes", {}).values())]
        exam_titles |= {title_of(t) for t in notes} - {None}
    for case in generated:
        assert norm(case["message"]) not in exam_messages, case["id"]
        for text in case["notes"].values():
            assert title_of(text) not in exam_titles, case["id"]
    assert len({c["id"] for c in generated}) == len(generated), "duplicate ids"
    for case in generated:
        for pattern in case["expect"].get("notes", {}):
            matching = sum(bool(re.search(pattern, p)) for p in case["notes"])
            # A new note or list must not be there yet; any other case names exactly one note.
            if case["kind"] == "plan":
                continue  # any note may hold a plan: a new one, or one that fits
            new = case["kind"] == "new-note" or case["id"].startswith("newlist-")
            assert matching == (0 if new else 1), case["id"]


if __name__ == "__main__":
    main(sys.argv[1:])
