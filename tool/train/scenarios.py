"""Training scenarios for the on-device model's fine-tune (#327).

Writes cases in the eval's format (`packages/notelore_core/lib/src/eval.dart`)
that `notelore_dev distill` plays with a teacher model, keeping only the turns
the scorer passes. Every note, title and sentence here is different from
`eval/cases.json`, so the student is never trained on the exam: `main` checks
that no message or note title overlaps.

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
     ["Saatleri Ayarlama Enstitüsü", "İnce Memed", "Masumiyet Müzesi", "Kuyucaklı Yusuf", "Aylak Adam", "Bereketli Topraklar Üzerinde"],
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
]

# Projects: (lang, title, notes, decisions, todos, facts, new decisions, new todos, done todo phrasing).
PROJECTS = [
    ("en", "Garden Shed", ["The shed will be 2 by 3 metres."], [("roof", "Metal sheet")],
     ["Order the timber"], ["The door faces south.", "Paint colour is sage green."],
     [("floor", "Concrete slab", "it lasts longer")], ["Get a building permit"], "I ordered the timber for the garden shed."),
    ("en", "Podcast Launch", ["First episode is about local history."], [("host", "Anchor")],
     ["Record the trailer"], ["We need a cover image.", "Episodes come out on Tuesdays."],
     [("microphone", "Shure MV7", "good value")], ["Write the show notes template"], "The podcast trailer is recorded."),
    ("tr", "Düğün Hazırlığı", ["Davetli sayısı 120 kişi."], [("mekan", "Bahçe düğünü")],
     ["Fotoğrafçıyla görüş"], ["Pasta çikolatalı olacak.", "Davetiyeler mavi renkte."],
     [("müzik", "Canlı orkestra", "daha samimi")], ["Gelinliği prova et"], "Fotoğrafçıyla görüştüm, düğün hazırlığındaki o iş bitti."),
    ("tr", "Mobil Uygulama", ["İlk sürüm sadece Android için."], [("backend", "Firebase")],
     ["Giriş ekranını tasarla"], ["Kullanıcılar e-postayla kaydolacak.", "Karanlık tema da olacak."],
     [("dil", "Kotlin", "ekip biliyor")], ["Play Store hesabı aç"], "Mobil uygulamanın giriş ekranını tasarladım."),
]

TOPICS = [
    ("en", "Health", ["Blood test results were normal."], "Started taking vitamin D in the mornings.", "What did the blood test show?", "normal"),
    ("tr", "Araba", ["Lastikler Kasım'da değişecek."], "Arabanın yağı 85.000 km'de değişti.", "Arabanın lastikleri ne zaman değişecek?", "Kasım"),
]


def cases(rng):
    out = []

    def add(case_id, kind, lang, notes, message, expect):
        out.append({"id": case_id, "kind": kind, "lang": lang, "notes": notes, "message": message, "expect": expect})

    for lang, title, first, items, templates in COLLECTIONS:
        p = path("topic", title)
        notes = {p: note(title, "topic", lang, notes=[first])}
        for i, item in enumerate(items):
            message = rng.choice(templates).format(x=item)
            add(f"coll-{slug(title)}-{i}", "collection", lang, notes, message, {"notes": {f"^{re.escape(p)}$": [item.split(" — ")[0]]}})
        add(f"q-{slug(title)}", "question", lang, notes,
            "Listede neler var?" if lang == "tr" else "What is on that list?",
            {"answer": [first.split(" — ")[0]]})

    for lang, title, nts, decs, todos, facts, new_decs, new_todos, done in PROJECTS:
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
        add(f"done-{slug(title)}", "todo-done", lang, notes, done, {"tools": ["complete_todo"], "notes": {pat: []}})
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
    for i, (lang, msg) in enumerate([("en", "Put this in the note."), ("tr", "Şunu da ekle."), ("en", "Save it there.")]):
        add(f"unclear-{i}", "unclear", lang, {}, msg, {"answer": ["?"]})
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
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(generated, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(generated)} scenarios -> {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
