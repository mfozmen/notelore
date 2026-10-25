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
     ["Order the timber"], ["The door faces south.", "Paint colour is sage green."],
     [("floor", "Concrete slab", "it lasts longer")], ["Get a building permit"],
     ["I ordered the timber for the garden shed.", "Garden shed: the timber is ordered."],
     "Garden shed: I cleared the old leaves from the site.", "leaves"),
    ("en", "Podcast Launch", ["First episode is about local history."], [("host", "Anchor")],
     ["Record the trailer"], ["We need a cover image.", "Episodes come out on Tuesdays."],
     [("microphone", "Shure MV7", "good value")], ["Write the show notes template"],
     ["The podcast trailer is recorded.", "Recorded the trailer for the podcast launch."],
     "Podcast launch: I made a list of five possible guests.", "guests"),
    ("tr", "Düğün Hazırlığı", ["Davetli sayısı 120 kişi."], [("mekan", "Bahçe düğünü")],
     ["Fotoğrafçıyla görüş"], ["Pasta çikolatalı olacak.", "Davetiyeler mavi renkte."],
     [("müzik", "Canlı orkestra", "daha samimi")], ["Gelinliği prova et"],
     ["Fotoğrafçıyla görüştüm, düğün hazırlığındaki o iş bitti.", "Düğün hazırlığı: fotoğrafçı görüşmesi yapıldı."],
     "Düğün hazırlığı: nikah şekerlerini sipariş ettim.", "şeker"),
    ("tr", "Mobil Uygulama", ["İlk sürüm sadece Android için."], [("backend", "Firebase")],
     ["Giriş ekranını tasarla"], ["Kullanıcılar e-postayla kaydolacak.", "Karanlık tema da olacak."],
     [("dil", "Kotlin", "ekip biliyor")], ["Play Store hesabı aç"],
     ["Mobil uygulamanın giriş ekranını tasarladım.", "Mobil uygulama: giriş ekranı tasarımı bitti."],
     "Mobil uygulama: ikon için üç taslak çizdim.", "ikon"),
    ("en", "Kitchen Renovation", ["New cabinets are oak."], [("countertop", "Quartz")],
     ["Measure the window"], ["The sink moves to the left wall.", "Budget: 8000 euros in total."],
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
    ("en", "Starting a new project: a vegetable patch behind the house, with raised beds.", r"^projects/[^/]*(vegetable|patch)[^/]*\.md$", "raised"),
    ("tr", "Yeni proje: çocuk odası için bir kitaplık yapacağım.", r"^projects/[^/]*kitaplik[^/]*\.md$", None),
    ("en", "New project: learn to bake sourdough bread with a rye starter.", r"^projects/[^/]*sourdough[^/]*\.md$", "rye"),
    ("tr", "Yeni bir proje başlatıyorum: bahçede arı kovanı, iki kovanla.", r"^projects/[^/]*(ari|kovan)[^/]*\.md$", None),
]

# A list with no note yet, while other lists are there (v3): a new note named
# for its kind, never another list. (lang, message, note path pattern, item).
NEW_LISTS = [
    ("en", "Album to listen to: Blue by Joni Mitchell.", r"^topics/[^/]*album[^/]*\.md$", "Blue"),
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


def cases(rng):
    out = []

    def add(case_id, kind, lang, notes, message, expect):
        out.append({"id": case_id, "kind": kind, "lang": lang, "notes": dict(notes), "message": message, "expect": expect})

    for c, (lang, title, first, items, templates) in enumerate(COLLECTIONS):
        p = path("topic", title)
        notes = {p: note(title, "topic", lang, notes=[first])}
        picked = rng.sample(items, 3)
        if c < 4:
            item = next(x for x in items if x not in picked)
            add(f"recover-{slug(title)}", "recovery", lang, notes, rng.choice(templates).format(x=item),
                {"notes": {f"^{re.escape(p)}$": [item.split(" — ")[0]]}, "answer_not": NO_TOOL_WORDS})
            out[-1]["fail_first_call"] = True
        for i, item in enumerate(picked):
            # One sentence an item: lists were over half of v2's turns, and it overfit on them.
            for j, template in enumerate(rng.sample(templates, 1)):
                add(f"coll-{slug(title)}-{i}-{j}", "collection", lang, notes, template.format(x=item),
                    {"notes": {f"^{re.escape(p)}$": [item.split(" — ")[0]]}})
        add(f"q-{slug(title)}", "question", lang, notes,
            f"{title} listesinde neler var?" if lang == "tr" else f"What is on my {title} list?",
            {"answer": [first.split(" — ")[0]]})

    for lang, title, nts, decs, todos, facts, new_decs, new_todos, done, other, other_word in PROJECTS:
        p = path("project", title)
        notes = {p: note(title, "project", lang, notes=nts, decisions=decs, todos=todos)}
        pat = f"^{re.escape(p)}$"
        for i, fact in enumerate(facts):
            add(f"file-{slug(title)}-{i}", "filing", lang, notes, f"{title}: {fact}", {"tools": ["add_note_entry"], "notes": {pat: [fact.split()[1]]}})
        for topic, value, why in new_decs:
            msg = f"{title}: we picked {value} for the {topic}, {why}." if lang == "en" else f"{title}: {topic} için {value} seçtik, {why}."
            add(f"dec-{slug(title)}", "decision", lang, notes, msg, {"tools": ["record_decision"], "notes": {pat: [value.split()[0]]}})
        for todo in new_todos:
            msg = f"Add a todo to {title}: {todo}." if lang == "en" else f"{title} için yapılacak: {todo}."
            add(f"todo-{slug(title)}", "todo", lang, notes, msg, {"tools": ["add_todo"], "notes": {pat: [todo.split()[-1]]}})
        for i, message in enumerate(done):
            add(f"done-{slug(title)}-{i}", "todo-done", lang, notes, message, {"tools": ["complete_todo"], "notes": {pat: []}})
        # Done, but no open todo says so: a dated entry, never a wrong tick (#349).
        add(f"done-other-{slug(title)}", "filing", lang, notes, other, {"tools": ["add_note_entry"], "notes": {pat: [other_word]}})
        topic, value = decs[0]
        q = f"What did we decide for the {title} {topic}?" if lang == "en" else f"{title} için {topic} ne seçmiştik?"
        add(f"q-dec-{slug(title)}", "question", lang, notes, q, {"answer": [value.split()[0]]})
        q = f"What is still open for {title}?" if lang == "en" else f"{title} için yapılacaklar neler?"
        add(f"q-todo-{slug(title)}", "question", lang, notes, q, {"answer": [todos[0].split()[-1]]})

    for lang, title, nts, fact, question, answer in TOPICS:
        p = path("topic", title)
        notes = {p: note(title, "topic", lang, notes=nts)}
        add(f"file-{slug(title)}", "filing", lang, notes, fact, {"notes": {f"^{re.escape(p)}$": [fact.split()[-1].rstrip(".")]}})
        add(f"q-{slug(title)}", "question", lang, notes, question, {"answer": [answer]})

    for i, (lang, msg) in enumerate([("en", "ok, thank you"), ("tr", "sağ ol"), ("en", "great, thanks a lot"), ("tr", "tamamdır, teşekkür ederim")]):
        add(f"chat-{i}", "chat", lang, {}, msg, {})
    # The note each reminder belongs to, as its project or topic case wrote it.
    written = {p: text for case in out for p, text in case["notes"].items()}
    for i, (lang, msg, at) in enumerate(PLANS):
        add(f"plan-{i}", "plan", lang, {}, msg,
            {"tools": ["add_reminder"], "notes": {r"^(topics|projects)/[^/]*\.md$": [at]}, "answer_not": ["?"]})
    for i, (lang, title, kind, msg, at, word) in enumerate(REMINDERS):
        p = path(kind, title)
        add(f"rem-{i}", "reminder", lang, {p: written[p]}, msg,
            {"tools": ["add_reminder"], "notes": {f"^{re.escape(p)}$": [at, word]}})
    for i, (lang, msg) in enumerate(UNCLEAR):
        add(f"unclear-{i}", "unclear", lang, {}, msg, {"answer": ["?"]})
    for i, (lang, msg, pattern, item) in enumerate(NEW_LISTS):
        add(f"newlist-{i}", "collection", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [item]}})
    for i, (lang, msg, pattern, item) in enumerate(FIRST_OF_KIND):
        add(f"newlist-first-{i}", "collection", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [item]}})
    for lang, titles, messages in MIXED_LISTS:
        notes = {path("topic", t): note(t, "topic", lang) for t in titles.values()}
        for i, (msg, kind, item) in enumerate(messages):
            p = path("topic", titles[kind])
            add(f"mixed-{lang}-{i}", "collection", lang, notes, msg, {"notes": {f"^{re.escape(p)}$": [item]}})
    for lang, now, later, messages in TWIN_LISTS:
        notes = {path("topic", t): note(t, "topic", lang) for t in (now, later)}
        for i, (msg, is_now, item) in enumerate(messages):
            p = path("topic", now if is_now else later)
            add(f"twin-{slug(now)}-{i}", "collection", lang, notes, msg, {"notes": {f"^{re.escape(p)}$": [item]}})
    for i, (lang, msg, pattern, word) in enumerate(NEW_PROJECTS):
        add(f"new-{i}", "new-note", lang, {}, msg, {"tools": ["create_note"], "notes": {pattern: [word] if word else []}})

    # Every workspace holds other notes too, so a case is passed by choosing the
    # right note, not by writing to the only one there (v1 learned that).
    pool = {p: text for case in out for p, text in case["notes"].items()}
    for case in out:
        # Never a note the case expects: a new list stays new, a choice stays one.
        # A plan may go in any note: its pattern matches all, so it gets distractors as they come.
        patterns = [] if case["kind"] == "plan" else case["expect"].get("notes", {})
        expected = [re.compile(pattern) for pattern in patterns]
        others = sorted(p for p in pool if p not in case["notes"] and not any(e.search(p) for e in expected))
        case["notes"].update({p: pool[p] for p in rng.sample(others, DISTRACTORS)})
    return out


ROOT = Path(__file__).resolve().parents[2]


def main(argv):
    out = Path(next((a for a in argv if not a.startswith("--")), ROOT / ".dev-home/train/scenarios.json"))
    seed = int(next((a.split("=", 1)[1] for a in argv if a.startswith("--seed=")), "7"))
    generated = cases(random.Random(seed))
    exam = json.loads((ROOT / "eval/cases.json").read_text(encoding="utf-8"))
    norm = lambda text: unicodedata.normalize("NFC", text).casefold()
    exam_messages = {norm(c["message"]) for c in exam["cases"]}
    exam_titles = {re.search(r"^title: (.*)$", t, re.M).group(1) for t in exam["notes"].values()}
    for case in generated:
        assert norm(case["message"]) not in exam_messages, case["id"]
        for text in case["notes"].values():
            assert re.search(r"^title: (.*)$", text, re.M).group(1) not in exam_titles, case["id"]
    assert len({c["id"] for c in generated}) == len(generated), "duplicate ids"
    for case in generated:
        for pattern in case["expect"].get("notes", {}):
            matching = sum(bool(re.search(pattern, p)) for p in case["notes"])
            # A new note or list must not be there yet; any other case names exactly one note.
            if case["kind"] == "plan":
                continue  # any note may hold a plan: a new one, or one that fits
            new = case["kind"] == "new-note" or case["id"].startswith("newlist-")
            assert matching == (0 if new else 1), case["id"]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(generated, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(generated)} scenarios -> {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
