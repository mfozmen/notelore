"""The held-out validation set (#599): scenarios built like the training ones
(`scenarios.py`), from notes, items and sentences of their own, so a model is
measured on what it never trained on. `main` checks that no note title,
message or listed item appears in the training scenarios or in
`eval/cases.json`, and that every kind has at least 15 cases.

    python tool/train/holdout.py [out.json]      (default eval/holdout.json)
    notelore_dev eval --cases=eval/holdout.json --greedy

Standard library only; the file is checked in, and the same seed always
writes the same one.
"""

import collections
import json
import random
import sys
from pathlib import Path

import scenarios

SEED = 599

COLLECTIONS = [
    ("en", "Novels on My List", "The Goldfinch — Donna Tartt",
     ["Cloud Atlas", "The Secret History", "Hamnet", "Normal People", "The Road"],
     ["Put {x} on my novels list.", "I'm about to start {x}."]),
    ("tr", "Okuma Listem", "Kürk Mantolu Adam",
     ["Yılanların Öcü", "Dokuzuncu Hariciye Koğuşu", "Fahim Bey ve Biz", "Sait Faik Hikâyeleri", "Kırmızı Saçlı Kadın"],
     ["Okuma listeme ekle: {x}.", "Sıradaki kitabım {x}."]),
    ("en", "Documentaries to Watch", "My Octopus Teacher",
     ["Free Solo", "Honeyland", "Fire of Love", "The Act of Killing", "Man on Wire"],
     ["Documentary to watch: {x}.", "Add {x} to the documentaries."]),
    ("tr", "Seyredilecek Belgeseller", "Gezegenimiz",
     ["Beyaz Cennet", "Göbeklitepe Belgeseli", "Kuşların Göçü", "Derin Mavi", "Toprak Ana"],
     ["İzlenecek belgesel: {x}.", "Belgesel listeme {x} eklensin."]),
    ("en", "Cocktails to Make", "Negroni",
     ["Paloma", "Espresso Martini", "Whiskey Sour", "Aperol Spritz", "Gimlet"],
     ["Cocktail to try making: {x}.", "Next cocktail for the list: {x}."]),
    ("tr", "Yapılacak Tatlılar", "Kazandibi",
     ["Aşure", "Revani", "Profiterol", "Şekerpare", "Tavuk göğsü"],
     ["Yapmak istediğim tatlı: {x}.", "Tatlı listesine {x} ekle."]),
    ("en", "Cities for a Long Weekend", "Bologna",
     ["Ghent", "Seville", "Kraków", "Bordeaux", "Tallinn"],
     ["A long weekend idea: {x}.", "Add {x} to the weekend cities."]),
    ("tr", "Kamp Yerleri", "Kaçkar Yaylaları",
     ["Kazdağları", "Saklıkent", "Abant Gölü", "Uludağ", "Kabak Koyu"],
     ["Kamp yapmak istediğim yer: {x}.", "Kamp yerlerine ekle: {x}."]),
    ("en", "Birthday Present Ideas", "A vinyl record for Sam",
     ["a hiking backpack for Leo", "a puzzle for Grandma", "a tea set for Maya", "a watch strap for Tom"],
     ["Birthday present idea: {x}.", "Note this present idea: {x}."]),
    ("tr", "Hediye Listesi", "Anneme bir şal",
     ["kardeşime kulaklık", "babaanneme bir gözlük zinciri", "eşime bir kahve makinesi", "yeğenime bir yapboz"],
     ["Hediye listesine yaz: {x}.", "Hediye için aklımda: {x}."]),
    ("en", "Apps to Try", "Obsidian",
     ["Raycast", "Arc browser", "Things 3", "Readwise", "Tailscale"],
     ["App to try: {x}.", "I want to try the app {x}."]),
    ("tr", "Dinlenecek Şarkılar", "Gesi Bağları",
     ["Uzun İnce Bir Yoldayım", "Sarı Gelin", "Kara Toprak", "Ah Bu Şarkıların Gözü Kör Olsun", "Bir Derdim Var"],
     ["Dinlenecek şarkı: {x}.", "Şarkı listesine {x} ekle."]),
    ("en", "Museums to Visit", "The Louvre",
     ["Rijksmuseum", "the Prado", "Tate Modern", "MoMA", "the Uffizi"],
     ["Museum I want to see: {x}.", "Add {x} to the museums list."]),
    ("tr", "Denenecek Kahveciler", "Kronotrop",
     ["Montag", "Petra Roasting", "Coffee Department", "Kahve Dünyası Moda", "Norm Coffee"],
     ["Denenecek kahveci: {x}.", "Kahveciler listesine ekle: {x}."]),
    ("en", "Skills to Learn", "Touch typing",
     ["woodworking", "sign language", "public speaking", "chess openings", "watercolour painting"],
     ["Skill I want to learn: {x}.", "Add {x} to the skills to learn."]),
]

PROJECTS = [
    ("en", "Home Studio", ["The studio is in the spare room."], [("monitors", "Yamaha HS5")],
     ["Buy acoustic panels"], ["Desk goes against the north wall.", "Budget is 1500 euros."],
     [("interface", "Focusrite Scarlett", "it is simple"), ("microphone", "Rode NT1", "low noise")],
     ["Order the cable kit", "Install the desk lamp"],
     ["I bought the acoustic panels for the home studio.", "Home studio: acoustic panels are bought."],
     "Home studio: I recorded a test take of the guitar.", "guitar"),
    ("en", "Book Club", ["We meet on the first Thursday of the month."], [("venue", "Corner café")],
     ["Pick the November book"], ["Eight members joined so far.", "Snacks rotate between members."],
     [("platform", "WhatsApp group", "everyone has it"), ("format", "Hybrid meetings", "two live abroad")],
     ["Make a reading schedule", "Print name cards"],
     ["We picked the November book for the book club.", "Book club: the November book is picked."],
     "Book club: I sent a welcome message to the new members.", "welcome"),
    ("en", "Bike Commute", ["The route is 9 km each way."], [("bike", "Gravel bike")],
     ["Fit the mudguards"], ["Office has a shower now.", "Ride takes 35 minutes."],
     [("lights", "Lezyne set", "bright enough"), ("lock", "Abus U-lock", "it is sturdy")],
     ["Buy a rain jacket", "Service the brakes"],
     ["The mudguards are fitted on the bike.", "Bike commute: I fitted the mudguards."],
     "Bike commute: I rode to work three days this week.", "three"),
    ("en", "Family Reunion", ["The reunion is in July."], [("date", "12 July")],
     ["Book the hall"], ["About 60 relatives will come.", "Aunt Rosa brings the photo albums."],
     [("caterer", "Lena's Kitchen", "good reviews"), ("music", "A local band", "more fun")],
     ["Send the invitations", "Make a seating plan"],
     ["I booked the hall for the family reunion.", "Family reunion: the hall is booked."],
     "Family reunion: I called the cousins in Canada.", "Canada"),
    ("tr", "Balkon Bahçesi", ["Balkon güneye bakıyor."], [("saksı", "Ahşap saksı")],
     ["Toprak satın al"], ["Domates ve fesleğen ekeceğiz.", "Sulama sabahları yapılacak."],
     [("tohum", "Yerli tohum", "daha dayanıklı"), ("gübre", "Solucan gübresi", "doğal")],
     ["Damla sulama kur", "Raf sistemi al"],
     ["Toprağı aldım, balkon bahçesi için o iş tamam.", "Balkon bahçesi: toprak alındı."],
     "Balkon bahçesi: fesleğenler filizlendi.", "fesleğen"),
    ("tr", "Ev Taşıma", ["Taşınma tarihi 15 Kasım."], [("nakliye", "Kardeşler Nakliyat")],
     ["Koli topla"], ["Yeni ev üç oda bir salon.", "İnternet hattı taşınacak."],
     [("boya", "Kırık beyaz", "ferah gösteriyor"), ("perde", "Keten perde", "ışığı yumuşatıyor")],
     ["Adres değişikliği bildir", "Anahtarı teslim et"],
     ["Kolileri topladım, taşınma için o iş bitti.", "Ev taşıma: koliler toplandı."],
     "Ev taşıma: eski dolabı komşuya verdim.", "dolab"),
    ("tr", "Yüksek Lisans Başvurusu", ["Başvurular Ocak'ta kapanıyor."], [("okul", "ODTÜ")],
     ["Niyet mektubunu yaz"], ["İki referans mektubu gerekiyor.", "ALES puanı 82."],
     [("bölüm", "Bilişsel bilim", "ilgimi çekiyor"), ("dil sınavı", "YDS", "daha kolay")],
     ["Transkript iste", "Danışmanla görüş"],
     ["Niyet mektubunu yazdım.", "Yüksek lisans başvurusu: niyet mektubu yazıldı, o iş tamam."],
     "Yüksek lisans başvurusu: hocama teşekkür e-postası attım.", "teşekkür"),
    ("tr", "Kafe Açılışı", ["Kafe Moda'da açılacak."], [("isim", "Pervane Kafe")],
     ["Kahve makinesini sipariş et"], ["Kirası aylık 40.000 lira.", "Altı masa sığıyor."],
     [("menü", "Kısa menü", "kalite için"), ("çekirdek", "Etiyopya çekirdeği", "meyvemsi tadı var")],
     ["Ruhsat başvurusu yap", "Tabelayı yaptır"],
     ["Kahve makinesini sipariş ettim.", "Kafe açılışı: kahve makinesi sipariş edildi."],
     "Kafe açılışı: logonun ilk taslağı geldi.", "logo"),
]

TOPICS = [
    ("en", "Car Maintenance", ["The next service is at 60,000 km."], "The front tyres were rotated today.", "When is the next service?", "60,000"),
    ("tr", "Sağlık Kontrolleri", ["Kolesterol değeri normal çıktı."], "Diş kontrolü Aralık'ta yapılacak.", "Kolesterol sonucum nasıldı?", "normal"),
    ("en", "Side Business", ["The shop sells hand-made candles."], "We sold forty candles at the market.", "What does the shop sell?", "candles"),
    ("tr", "Kedimiz Tarçın", ["Tarçın'ın kısırlaştırması yapıldı."], "Tarçın artık yaş mama yiyor.", "Tarçın'ın kısırlaştırması yapıldı mı?", "yapıldı"),
    ("en", "Language Exchange", ["I practise Spanish with Lucía on Mondays."], "Lucía suggested we switch to video calls.", "Who do I practise Spanish with?", "Lucía"),
]

NEW_PROJECTS = [
    ("en", "New project: a treehouse for the kids, with a rope ladder.", r"^projects/[^/]*treehouse[^/]*\.md$", "rope"),
    ("en", "Starting a project to digitise our old family photos.", r"^projects/[^/]*(photo|digiti)[^/]*\.md$", None),
    ("en", "I'm starting a newsletter about urban cycling, monthly.", r"^projects/[^/]*newsletter[^/]*\.md$", "monthly"),
    ("en", "New project: build a small weather station with a Raspberry Pi.", r"^projects/[^/]*weather[^/]*\.md$", "Raspberry"),
    ("en", "Kicking off a project to repaint the fence this spring.", r"^projects/[^/]*fence[^/]*\.md$", None),
    ("en", "New project: a podcast about local football clubs.", r"^projects/[^/]*(podcast|football)[^/]*\.md$", "football"),
    ("en", "I want to start a project to learn the piano with an app.", r"^projects/[^/]*piano[^/]*\.md$", None),
    ("en", "New project: a photo book of our trip to Norway.", r"^projects/[^/]*(photo|norway)[^/]*\.md$", "Norway"),
    ("tr", "Yeni proje: mutfak için bir baharat rafı yapacağım.", r"^projects/[^/]*(baharat|raf)[^/]*\.md$", None),
    ("tr", "Yeni bir proje: köy evini yazlığa çevireceğiz.", r"^projects/[^/]*(koy|yazlik)[^/]*\.md$", None),
    ("tr", "Bir proje başlatıyorum: kendi kitabımı yazacağım, polisiye.", r"^projects/[^/]*kitab[^/]*\.md$", "polisiye"),
    ("tr", "Yeni proje: mahalle için bir kitap takas günü düzenleyeceğim.", r"^projects/[^/]*(takas|kitap)[^/]*\.md$", None),
    ("tr", "Yeni proje: bisikletle Kapadokya turu değil, Ege turu yapacağım.", r"^projects/[^/]*(ege|bisiklet|tur)[^/]*\.md$", None),
    ("tr", "Yeni bir proje: annem için bir yemek tarifleri sitesi.", r"^projects/[^/]*(tarif|site)[^/]*\.md$", None),
    ("tr", "Proje başlatıyorum: evde akvaryum kuracağım.", r"^projects/[^/]*akvaryum[^/]*\.md$", None),
]

NEW_LISTS = [
    ("en", "Board book for the baby: Goodnight Moon.", r"^topics/[^/]*book[^/]*\.md$", "Goodnight Moon"),
    ("en", "Beer to try: a Belgian tripel.", r"^topics/[^/]*beer[^/]*\.md$", "tripel"),
    ("en", "Yoga pose to learn: crow pose.", r"^topics/[^/]*(yoga|pose)[^/]*\.md$", "crow"),
    ("en", "Video game to play: Hades.", r"^topics/[^/]*game[^/]*\.md$", "Hades"),
    ("tr", "Denenecek çay: Rize'den beyaz çay.", r"^topics/[^/]*cay[^/]*\.md$", "beyaz çay"),
    ("tr", "Oynamak istediğim oyun: Stardew Valley.", r"^topics/[^/]*oyun[^/]*\.md$", "Stardew"),
    ("tr", "Gitmek istediğim festival: Zeytinli Rock.", r"^topics/[^/]*festival[^/]*\.md$", "Zeytinli"),
    ("tr", "Almak istediğim plak: Barış Manço'nun 2023'ü.", r"^topics/[^/]*plak[^/]*\.md$", "2023"),
]

FIRST_OF_KIND = [
    ("en", "I'm reading Pride and Prejudice again.", r"^topics/[^/]*book[^/]*\.md$", "Pride and Prejudice"),
    ("en", "Tonight I'm watching Spirited Away.", r"^topics/[^/]*(film|movie)[^/]*\.md$", "Spirited Away"),
    ("en", "Recipe idea: black bean tacos.", r"^topics/[^/]*recipe[^/]*\.md$", "tacos"),
    ("en", "I'd love to visit Patagonia someday.", r"^topics/[^/]*(place|visit|travel)[^/]*\.md$", "Patagonia"),
    ("tr", "Şu sıralar Saatleri Kuran Adam okuyorum.", r"^topics/[^/]*kitap[^/]*\.md$", "Saatleri Kuran Adam"),
    ("tr", "Bu akşam Hababam Sınıfı'nı izleyeceğim.", r"^topics/[^/]*film[^/]*\.md$", "Hababam"),
    ("tr", "Tarif fikri: zeytinyağlı pırasa.", r"^topics/[^/]*tarif[^/]*\.md$", "pırasa"),
    ("tr", "Bir gün Assos'a gitmek istiyorum.", r"^topics/[^/]*(gez|yer)[^/]*\.md$", "Assos"),
]

MIXED_LISTS = [
    ("en", {"books": "Book Pile", "films": "Movie Night Picks", "recipes": "Dinner Ideas", "places": "Trip Ideas"}, [
        ("Started reading The Bee Sting.", "books", "Bee Sting"),
        ("Movie for Friday: The Holdovers.", "films", "Holdovers"),
        ("Dinner idea: mushroom stroganoff.", "recipes", "stroganoff"),
        ("I'd like to go to the Dolomites.", "places", "Dolomites"),
    ]),
    ("tr", {"books": "Kitaplık", "films": "Film Gecesi", "recipes": "Akşam Yemekleri", "places": "Gezi Fikirleri"}, [
        ("Bugün Çalıkuşu'nun devamı Ateşten Gömlek'e başladım.", "books", "Ateşten Gömlek"),
        ("Cuma akşamı izlenecek: Vizontele.", "films", "Vizontele"),
        ("Akşam yemeği fikri: fırında sebzeli tavuk.", "recipes", "sebzeli tavuk"),
        ("Gitmek istediğim yer: Nemrut Dağı.", "places", "Nemrut"),
    ]),
]

TWIN_LISTS = [
    ("en", "Reading Now", "Reading Someday", [
        ("I just began The Bell Jar.", True, "Bell Jar"),
        ("Some day I want to read Ulysses.", False, "Ulysses"),
    ]),
    ("tr", "Okuduklarım", "İleride Okuyacaklarım", [
        ("Şu an Mai ve Siyah'ı okuyorum.", True, "Mai ve Siyah"),
        ("İleride Yaprak Dökümü'nü okumak istiyorum.", False, "Yaprak Dökümü"),
    ]),
]

UNCLEAR = [
    ("en", "Note that."), ("en", "Add it to the list."), ("en", "Move that one over there."),
    ("en", "Same as last time."), ("en", "Update the thing."), ("en", "Tick it off."),
    ("en", "Write it in the other note."), ("en", "Remember this for me."),
    ("tr", "Bunu kaydet."), ("tr", "Şunu listeye ekle."), ("tr", "Geçen seferki gibi yap."),
    ("tr", "Onu değiştir."), ("tr", "Bunu oraya taşı."), ("tr", "Bitti, işaretle."),
    ("tr", "Şunu not et, unutmayayım."),
]

# From 2026-10-18 14:00, a Sunday.
PLANS = [
    ("en", "Tomorrow evening I'm going to the cinema.", "2026-10-19"),
    ("en", "On Tuesday I'm visiting my grandmother.", "2026-10-20"),
    ("en", "Thursday at 20:00 I have a dinner with old friends.", "2026-10-22 20:00"),
    ("en", "I'm going to the opera on 7 November.", "2026-11-07"),
    ("en", "Saturday I'll watch the Formula 1 race.", "2026-10-24"),
    ("en", "Next Monday at 9 I have a job interview.", "2026-10-26 09:00"),
    ("en", "On 31 October I'm going to a Halloween party.", "2026-10-31"),
    ("en", "Friday at 18:30 I'm meeting Jonas for a run.", "2026-10-23 18:30"),
    ("tr", "Yarın öğlen kuaföre gideceğim.", "2026-10-19"),
    ("tr", "Salı günü İzmir'e gideceğim.", "2026-10-20"),
    ("tr", "Çarşamba saat 19'da sinemaya gideceğim.", "2026-10-21 19:00"),
    ("tr", "29 Ekim'de fener alayına katılacağım.", "2026-10-29"),
    ("tr", "Cuma akşamı derbiyi izleyeceğim.", "2026-10-23"),
    ("tr", "Pazartesi saat 10'da diş hekimine gideceğim.", "2026-10-19 10:00"),
    ("tr", "5 Kasım'da İstanbul'a dönüyorum.", "2026-11-05"),
]

REMINDERS = [
    ("en", "Home Studio", "project", "Remind me tomorrow at 11 to call the acoustics shop for the home studio.", "2026-10-19 11:00", "acoustic"),
    ("en", "Book Club", "project", "Book club: remind me in 3 hours to send the meeting link.", "2026-10-18 17:00", "link"),
    ("en", "Bike Commute", "project", "Remind me on Wednesday at 7 to pump the bike tyres.", "2026-10-21 07:00", "tyre"),
    ("en", "Family Reunion", "project", "Family reunion: remind me on 1 December to confirm the caterer.", "2026-12-01", "caterer"),
    ("en", "Car Maintenance", "topic", "Remind me in 30 minutes to check the car's oil.", "2026-10-18 14:30", "oil"),
    ("en", "Side Business", "topic", "Remind me on Saturday at 8 to load the candles into the car.", "2026-10-24 08:00", "candle"),
    ("en", "Language Exchange", "topic", "Remind me tomorrow at 18:00 to prepare questions for Lucía.", "2026-10-19 18:00", "Lucía"),
    ("tr", "Balkon Bahçesi", "project", "Balkon bahçesi için yarın 9'da fidanları sulamamı hatırlat.", "2026-10-19 09:00", "fidan"),
    ("tr", "Ev Taşıma", "project", "Ev taşıma: perşembe 14'te nakliyeciyi aramamı hatırlat.", "2026-10-22 14:00", "nakliye"),
    ("tr", "Yüksek Lisans Başvurusu", "project", "Yüksek lisans için 2 saat sonra hocama e-posta atmayı hatırlat.", "2026-10-18 16:00", "e-posta"),
    ("tr", "Kafe Açılışı", "project", "Kafe açılışı: 10 Kasım'da kira sözleşmesini imzalamayı hatırlat.", "2026-11-10", "sözleşme"),
    ("tr", "Sağlık Kontrolleri", "topic", "Cuma 8.30'da kan tahlili için aç gitmemi hatırlat.", "2026-10-23 08:30", "tahlil"),
    ("tr", "Kedimiz Tarçın", "topic", "Tarçın için 15 dakika sonra mama vermeyi hatırlat.", "2026-10-18 14:15", "mama"),
    # A reminder in one language for a note in the other.
    ("en", "Ev Taşıma", "project", "Remind me on Tuesday at 10 to cancel the internet at the old flat.", "2026-10-20 10:00", "internet"),
    ("tr", "Bike Commute", "project", "Bisiklet için yarın 17'de zinciri yağlamamı hatırlat.", "2026-10-19 17:00", "zincir"),
]

# (message lang, note title, its kind, message, kind of the case, the tool it needs, a word the note keeps).
CROSS = [
    ("en", "Balkon Bahçesi", "project", "Balcony garden: the tomatoes got their first flowers.", "filing", "add_note_entry", "tomato"),
    ("en", "Ev Taşıma", "project", "For the house move we picked Kardeşler Nakliyat's bigger truck, more room.", "decision", "record_decision", "truck"),
    ("en", "Kafe Açılışı", "project", "Café opening: add a todo to hire a barista.", "todo", "add_todo", "barista"),
    ("en", "Yüksek Lisans Başvurusu", "project", "I wrote the statement of purpose for the master's application.", "todo-done", "complete_todo", None),
    ("en", "Sağlık Kontrolleri", "topic", "Health checks: my blood pressure was 12 over 8 today.", "filing", "add_note_entry", "12"),
    ("en", "Kedimiz Tarçın", "topic", "Tarçın weighs 4.2 kg now.", "filing", "add_note_entry", "4.2"),
    ("en", "Ev Taşıma", "project", "House move: the boxes are packed.", "todo-done", "complete_todo", None),
    ("en", "Balkon Bahçesi", "project", "Add a todo to the balcony garden: buy a watering can.", "todo", "add_todo", "can"),
    ("tr", "Home Studio", "project", "Ev stüdyosu: masayı kuzey duvarı yerine pencerenin önüne koyduk.", "filing", "add_note_entry", "pencere"),
    ("tr", "Book Club", "project", "Kitap kulübü için Kasım kitabını seçtik, o iş tamam.", "todo-done", "complete_todo", None),
    ("tr", "Bike Commute", "project", "Bisikletle işe gidiş: kilit için Kryptonite seçtik, daha hafif.", "decision", "record_decision", "Kryptonite"),
    ("tr", "Family Reunion", "project", "Aile buluşması için yapılacak: otobüs kirala.", "todo", "add_todo", "otobüs"),
    ("tr", "Car Maintenance", "topic", "Arabanın akü değişimi bugün yapıldı.", "filing", "add_note_entry", "akü"),
    ("tr", "Language Exchange", "topic", "Lucía ile dil pratiği artık perşembe akşamları.", "filing", "add_note_entry", "perşembe"),
    ("tr", "Side Business", "topic", "Mum dükkanı: kokulu mumlar en çok satanlar.", "filing", "add_note_entry", "kokulu"),
    ("tr", "Home Studio", "project", "Ev stüdyosu için akustik panelleri aldım.", "todo-done", "complete_todo", None),
]

CHAT = [
    ("en", "thanks a ton!"), ("en", "perfect, thank you"), ("en", "cool, that's all"), ("en", "nice one"),
    ("en", "got it, thanks"), ("en", "thank you so much"), ("en", "great, cheers"), ("en", "ok that's fine"),
    ("tr", "çok teşekkürler"), ("tr", "süper, sağ ol"), ("tr", "tamam, bu kadar"), ("tr", "eline sağlık"),
    ("tr", "çok iyi, teşekkür ederim"), ("tr", "oldu, sağ olasın"), ("tr", "harika"),
]

DISTRACTORS = scenarios.DISTRACTORS
RECOVERIES = len(COLLECTIONS)
NO_TOOL_WORDS = scenarios.NO_TOOL_WORDS

MIN_PER_KIND = 15


def disjoint(held, training):
    """No note title or message of [held] in [training], and no item a held
    collection case expects named in a training message."""
    def titles(cases):
        return {scenarios.title_of(t) for c in cases for t in c["notes"].values()}

    def messages(cases):
        return {scenarios.norm(c["message"]) for c in cases}

    shared = titles(held) & titles(training)
    assert not shared, f"titles in training: {sorted(shared)}"
    shared = messages(held) & messages(training)
    assert not shared, f"messages in training: {sorted(shared)}"
    said = " ".join(messages(training))
    for case in held:
        if case["kind"] != "collection":
            continue
        for facts in case["expect"].get("notes", {}).values():
            for fact in facts:
                assert scenarios.norm(fact) not in said, (case["id"], fact)


def main(argv):
    out = Path(next((a for a in argv if not a.startswith("--")), scenarios.ROOT / "eval/holdout.json"))
    held = scenarios.cases(random.Random(SEED), sys.modules[__name__])
    scenarios.check(held)
    disjoint(held, scenarios.cases(random.Random(7)))
    counts = collections.Counter(c["kind"] for c in held)
    thin = {kind: n for kind, n in counts.items() if n < MIN_PER_KIND}
    assert not thin, f"kinds under {MIN_PER_KIND}: {thin}"
    out.write_text(json.dumps(held, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(held)} held-out scenarios -> {out}: {dict(sorted(counts.items()))}")


if __name__ == "__main__":
    main(sys.argv[1:])
