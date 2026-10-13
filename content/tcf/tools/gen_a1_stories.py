#!/usr/bin/env python3
"""Writes the A1 story files from structured data (so the JSON cannot be
malformed). Run from the repo root:  python3 content/tcf/tools/gen_a1_stories.py
Then check with:  python3 content/tcf/tools/validate.py
The generated JSON files are the source of truth; edit them directly after the
first run if you prefer. This script is kept as a record of how they were made.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[3] / "flutter_app" / "assets" / "content" / "tcf" / "stories"
OUT.mkdir(parents=True, exist_ok=True)


def story(fid, title, title_en, minutes, summary, unit, sentences, words, keywords, quiz):
    d = {
        "id": fid, "title": title, "titleEn": title_en, "level": "A1", "minutes": minutes,
        "summary": summary, "unit": unit,
        "sentences": [{"fr": a, "en": b, **({"note": c} if c else {})} for a, b, c in sentences],
        "words": {
            k: {"en": v[0], **({"pos": v[1]} if len(v) > 1 and v[1] else {}), **({"sound": v[2]} if len(v) > 2 and v[2] else {})}
            for k, v in words.items()
        },
        "keywords": keywords,
        "quiz": [{"prompt": p, "options": o, "answer": a, "explain": e} for p, o, a, e in quiz],
    }
    (OUT / f"{fid}.json").write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


story("a1-nouvelle-voisine", "Une nouvelle voisine", "A new neighbour", 3,
      "Marc meets Nadia, the new neighbour who arrives with a suitcase.", "a1-u01",
      [("Il est sept heures du soir.", "It is seven in the evening.", ""),
       ("Marc est dans le couloir.", "Marc is in the hallway.", ""),
       ("Une femme arrive avec une valise.", "A woman arrives with a suitcase.", ""),
       ("« Bonsoir ! Je m'appelle Nadia. »", "\"Good evening! My name is Nadia.\"", ""),
       ("« Enchanté ! Je suis Marc. »", "\"Nice to meet you! I am Marc.\"", ""),
       ("Nadia est nouvelle dans l'immeuble.", "Nadia is new in the building.", ""),
       ("Elle habite au troisième étage.", "She lives on the third floor.", ""),
       ("Marc dit : « Bienvenue ! »", "Marc says: \"Welcome!\"", "")],
      {"il": ("he, it", "pronoun"), "est": ("is (être)", "verb"), "sept": ("seven",), "heures": ("hours, o'clock",),
       "du": ("of the",), "soir": ("evening", "noun, masculine", "swahr"), "marc": ("Marc (a man's name)",),
       "dans": ("in",), "le": ("the",), "couloir": ("hallway", "noun, masculine", "koo-LWAHR"), "une": ("a",),
       "femme": ("woman", "noun, feminine", "fam"), "arrive": ("arrives (arriver)", "verb"), "avec": ("with",),
       "valise": ("suitcase", "noun, feminine", "va-LEEZ"), "bonsoir": ("good evening", None, "bon-SWAHR"),
       "je": ("I", "pronoun"), "m'appelle": ("my name is (I call myself)",), "nadia": ("Nadia (a woman's name)",),
       "enchanté": ("nice to meet you", None, "ahn-shahn-TAY"), "suis": ("am (être)", "verb"),
       "nouvelle": ("new (feminine)", "adjective"), "l'immeuble": ("the building", "noun, masculine"),
       "elle": ("she", "pronoun"), "habite": ("lives (habiter)", "verb"), "au": ("to the, on the",),
       "troisième": ("third",), "étage": ("floor, storey", "noun, masculine", "ay-TAHZH"),
       "dit": ("says (dire)", "verb"), "bienvenue": ("welcome", None, "byen-vuh-NU")},
      ["couloir", "valise", "nouvelle", "habite", "étage", "bienvenue"],
      [("What time is it at the start of the story?", ["Seven in the evening", "Seven in the morning", "Eight in the evening", "Six in the evening"], 0, "Il est sept heures du soir means it is seven in the evening."),
       ("Who is new in the building?", ["Marc", "Nadia", "A man with a suitcase", "Nobody"], 1, "Nadia est nouvelle dans l'immeuble: Nadia is new in the building."),
       ("Where does Nadia live?", ["On the first floor", "On the second floor", "On the third floor", "In the hallway"], 2, "Elle habite au troisième étage: she lives on the third floor.")])

story("a1-au-depanneur", "Au dépanneur", "At the convenience store", 3,
      "Julie buys milk and bread at the corner store and pays by card.", "a1-u01",
      [("Julie entre dans le dépanneur.", "Julie goes into the convenience store.", "In Québec, a dépanneur (or dép) is a corner store. In France you would say épicerie or supérette."),
       ("Il y a du lait, du pain et des pommes.", "There is milk, bread and apples.", ""),
       ("Elle prend du lait.", "She takes some milk.", ""),
       ("Elle prend aussi du pain.", "She also takes some bread.", ""),
       ("À la caisse, le monsieur dit : « Bonjour ! »", "At the cash register, the man says: \"Hello!\"", ""),
       ("« Ça fait quatre dollars. »", "\"That's four dollars.\"", ""),
       ("Julie paie avec sa carte.", "Julie pays with her card.", ""),
       ("« Merci ! Bonne soirée ! »", "\"Thank you! Have a nice evening!\"", "")],
      {"julie": ("Julie (a woman's name)",), "entre": ("goes in (entrer)", "verb"), "dans": ("in, into",), "le": ("the",),
       "dépanneur": ("convenience store (Québec)", "noun, masculine", "day-pa-NUHR"), "il": ("he, it", "pronoun"),
       "y": ("there",), "a": ("has (avoir)", "verb"), "du": ("some, of the",), "lait": ("milk", "noun, masculine", "lay"),
       "pain": ("bread", "noun, masculine", "pan"), "et": ("and",), "des": ("some",), "pommes": ("apples", "noun, feminine"),
       "elle": ("she", "pronoun"), "prend": ("takes (prendre)", "verb"), "aussi": ("also",), "à": ("at, to",),
       "la": ("the",), "caisse": ("cash register", "noun, feminine", "kess"), "monsieur": ("man, sir, Mr.", "noun, masculine"),
       "dit": ("says (dire)", "verb"), "bonjour": ("hello",), "ça": ("that, it",), "fait": ("makes, is (faire)", "verb"),
       "quatre": ("four",), "dollars": ("dollars", "noun, masculine"), "paie": ("pays (payer)", "verb"), "avec": ("with",),
       "sa": ("her",), "carte": ("card", "noun, feminine"), "merci": ("thank you",), "bonne": ("good, nice (feminine)",),
       "soirée": ("evening (the whole evening)", "noun, feminine", "swa-RAY")},
      ["dépanneur", "lait", "pain", "caisse", "dollars", "carte"],
      [("What does Julie buy?", ["Milk and bread", "Apples and milk", "Bread and apples", "Only milk"], 0, "Elle prend du lait. Elle prend aussi du pain. She takes milk and also bread."),
       ("How much does she pay?", ["Two dollars", "Four dollars", "Five dollars", "Fourteen dollars"], 1, "Ça fait quatre dollars means that's four dollars."),
       ("How does Julie pay?", ["With cash", "With her card", "With her phone", "She does not pay"], 1, "Julie paie avec sa carte: Julie pays with her card.")])

story("a1-premier-jour", "Mon premier jour", "My first day", 3,
      "A newcomer takes the bus on a cold morning to start a new job.", "a1-u01",
      [("Aujourd'hui, c'est mon premier jour de travail.", "Today is my first day of work.", ""),
       ("Je prends l'autobus à sept heures.", "I take the bus at seven o'clock.", ""),
       ("Il fait froid, alors je porte un manteau.", "It is cold, so I wear a coat.", "Il fait froid is how French talks about the weather. It literally says it makes cold."),
       ("J'arrive au bureau à huit heures.", "I arrive at the office at eight o'clock.", ""),
       ("Ma gérante s'appelle Karine.", "My manager is called Karine.", "Many job titles have a feminine form: gérante for a woman, gérant for a man."),
       ("Elle dit : « Bonjour et bienvenue ! »", "She says: \"Hello and welcome!\"", ""),
       ("Je suis un peu nerveux, mais content.", "I am a little nervous, but happy.", ""),
       ("C'est une bonne journée !", "It is a good day!", "")],
      {"aujourd'hui": ("today",), "c'est": ("it is, this is",), "mon": ("my (masculine)",), "premier": ("first", "adjective"),
       "jour": ("day", "noun, masculine", "zhoor"), "de": ("of",), "travail": ("work", "noun, masculine", "tra-VAHY"),
       "je": ("I", "pronoun"), "prends": ("take (prendre)", "verb"), "l'autobus": ("the bus", "noun, masculine"),
       "à": ("at, to",), "sept": ("seven",), "heures": ("hours, o'clock",), "il": ("it, he", "pronoun"),
       "fait": ("makes, is (faire)", "verb"), "froid": ("cold", "adjective", "frwah"), "alors": ("so, then",),
       "porte": ("wear (porter)", "verb"), "un": ("a",), "manteau": ("coat", "noun, masculine", "mahn-TOH"),
       "j'arrive": ("I arrive (arriver)", "verb"), "au": ("at the, to the",), "bureau": ("office", "noun, masculine", "bu-ROH"),
       "huit": ("eight",), "ma": ("my (feminine)",), "gérante": ("manager (a woman)", "noun, feminine"),
       "s'appelle": ("is called (s'appeler)", "verb"), "karine": ("Karine (a woman's name)",), "elle": ("she", "pronoun"),
       "dit": ("says (dire)", "verb"), "bonjour": ("hello",), "et": ("and",), "bienvenue": ("welcome",),
       "suis": ("am (être)", "verb"), "peu": ("little",), "nerveux": ("nervous (a man)", "adjective"), "mais": ("but",),
       "content": ("happy", "adjective"), "une": ("a",), "bonne": ("good (feminine)",),
       "journée": ("day (the whole day)", "noun, feminine", "zhoor-NAY")},
      ["travail", "l'autobus", "froid", "manteau", "bureau", "gérante", "content"],
      [("How does the narrator get to work?", ["By car", "By bus", "On foot", "By train"], 1, "Je prends l'autobus: I take the bus."),
       ("Why does the narrator wear a coat?", ["It is raining", "It is cold", "It is a rule at work", "It is new"], 1, "Il fait froid, alors je porte un manteau: it is cold, so I wear a coat."),
       ("How does the narrator feel?", ["Only nervous", "Only tired", "A little nervous but happy", "Angry"], 2, "Je suis un peu nerveux, mais content: a little nervous, but happy.")])

story("a1-rendez-vous-clinique", "Un rendez-vous à la clinique", "An appointment at the clinic", 3,
      "Samira checks in at a clinic reception and shows her health card.", "a1-u01",
      [("Samira a un rendez-vous à la clinique.", "Samira has an appointment at the clinic.", ""),
       ("Elle entre dans la salle d'attente.", "She goes into the waiting room.", ""),
       ("La réceptionniste dit : « Bonjour, madame. »", "The receptionist says: \"Hello, madam.\"", ""),
       ("« Votre nom, s'il vous plaît ? »", "\"Your name, please?\"", "S'il vous plaît is the polite please. With a stranger you use vous."),
       ("« Je m'appelle Samira Haddad. »", "\"My name is Samira Haddad.\"", ""),
       ("« Votre carte d'assurance maladie, s'il vous plaît. »", "\"Your health insurance card, please.\"", "In Canada your carte d'assurance maladie (health card) is the card you show at every medical visit."),
       ("Samira donne sa carte.", "Samira gives her card.", ""),
       ("« Merci. Le docteur arrive dans cinq minutes. »", "\"Thank you. The doctor arrives in five minutes.\"", "")],
      {"samira": ("Samira (a woman's name)",), "a": ("has (avoir)", "verb"), "un": ("a",),
       "rendez-vous": ("appointment", "noun, masculine", "rahn-day-VOO"), "à": ("at, to",), "la": ("the",),
       "clinique": ("clinic", "noun, feminine", "kli-NEEK"), "elle": ("she", "pronoun"), "entre": ("goes in (entrer)", "verb"),
       "dans": ("in, into",), "salle": ("room", "noun, feminine", "sal"), "d'attente": ("of waiting",),
       "réceptionniste": ("receptionist", "noun"), "dit": ("says (dire)", "verb"), "bonjour": ("hello",),
       "madame": ("madam, Mrs.", "noun, feminine"), "votre": ("your (formal)",), "nom": ("last name", "noun, masculine"),
       "s'il": ("if it",), "vous": ("you (formal)", "pronoun"), "plaît": ("pleases (plaire)", "verb"),
       "je": ("I", "pronoun"), "m'appelle": ("my name is (I call myself)",), "haddad": ("Haddad (a family name)",),
       "carte": ("card", "noun, feminine"), "d'assurance": ("of insurance",), "maladie": ("illness, health", "noun, feminine"),
       "donne": ("gives (donner)", "verb"), "sa": ("her",), "merci": ("thank you",), "le": ("the",),
       "docteur": ("doctor", "noun, masculine", "dok-TUHR"), "arrive": ("arrives (arriver)", "verb"), "cinq": ("five",),
       "minutes": ("minutes", "noun, feminine")},
      ["rendez-vous", "clinique", "salle", "nom", "carte", "maladie", "docteur"],
      [("Where is Samira?", ["At a bank", "At a clinic", "At a school", "At a store"], 1, "Samira a un rendez-vous à la clinique: she has an appointment at the clinic."),
       ("What does the receptionist ask first?", ["Her card", "Her name", "Her address", "Her phone number"], 1, "Votre nom, s'il vous plaît ? means your name, please? The card comes next."),
       ("When does the doctor arrive?", ["In five minutes", "In fifteen minutes", "Now", "Tomorrow"], 0, "Le docteur arrive dans cinq minutes: the doctor arrives in five minutes.")])

(OUT.parent / "stories.json").write_text(
    json.dumps({"version": 1, "stories": ["a1-nouvelle-voisine.json", "a1-au-depanneur.json", "a1-premier-jour.json", "a1-rendez-vous-clinique.json"]}, indent=2) + "\n")
print("stories written to", OUT)
