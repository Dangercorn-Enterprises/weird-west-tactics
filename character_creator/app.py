"""
app.py — Dustfall Character Creator Flask Application
Port 8445

Routes:
  GET  /                  — Character creator wizard
  POST /create            — Generate and save a character
  GET  /character/<id>    — Character sheet view
  GET  /gallery           — All created characters
  GET  /export/<id>       — PDF export
  GET  /api/random-name   — Random frontier name (AJAX)
  GET  /api/backstory     — Random backstory components (AJAX)
"""

import json
import os
import random
import sqlite3
import sys
import time
from pathlib import Path

from flask import (
    Flask, request, jsonify, render_template,
    redirect, url_for, abort, make_response
)

# Local imports
sys.path.insert(0, str(Path(__file__).parent))
from creator import (
    FACTIONS, ARCHETYPES, STATS, STAT_KEYS, TRAITS,
    STAT_POINT_POOL, STAT_MAX, STAT_MIN, APPEARANCES,
    generate_character, validate_stats, random_appearance
)
from backstory import (
    generate_backstory, get_all_events, get_all_secrets,
    get_all_motivations, MOTIVATIONS
)
from pdf_sheet import generate_pdf, REPORTLAB_AVAILABLE

# ------------------------------------------------------------------ #
# App setup                                                           #
# ------------------------------------------------------------------ #

BASE_DIR = Path(__file__).parent
DB_PATH = BASE_DIR / "characters.db"

app = Flask(__name__, template_folder="templates")
app.secret_key = os.getenv("DUSTFALL_SECRET", "ashfall-burns-hotter-than-coal")


@app.template_filter("timestamp_fmt")
def timestamp_fmt(ts):
    """Format a Unix timestamp as a human-readable date."""
    import datetime
    try:
        return datetime.datetime.fromtimestamp(float(ts)).strftime("%b %d, %Y")
    except Exception:
        return "—"

# ------------------------------------------------------------------ #
# Database                                                            #
# ------------------------------------------------------------------ #

def get_db():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS characters (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL,
                faction     TEXT NOT NULL,
                archetype   TEXT NOT NULL,
                stats_json  TEXT NOT NULL,
                traits_json TEXT NOT NULL,
                gear_json   TEXT NOT NULL,
                backstory   TEXT,
                motivation  TEXT,
                appearance_json TEXT,
                origin_town TEXT,
                secret      TEXT,
                event_json  TEXT,
                derived_json TEXT,
                created_at  REAL NOT NULL,
                is_seed     INTEGER DEFAULT 0
            );
        """)
        conn.commit()


def save_character(char: dict, is_seed: bool = False) -> int:
    with get_db() as conn:
        backstory_data = char.get("backstory_data", {})
        motivation = backstory_data.get("motivation") or {}
        cur = conn.execute(
            """INSERT INTO characters
               (name, faction, archetype, stats_json, traits_json, gear_json,
                backstory, motivation, appearance_json, origin_town, secret,
                event_json, derived_json, created_at, is_seed)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                char["name"],
                char["faction"],
                char["archetype"],
                json.dumps(char["stats"]),
                json.dumps(char["traits"]),
                json.dumps(char["gear"]),
                backstory_data.get("backstory", ""),
                json.dumps(motivation),
                json.dumps(char.get("appearance", {})),
                backstory_data.get("origin_town", ""),
                backstory_data.get("secret", ""),
                json.dumps(backstory_data.get("event", {})),
                json.dumps(char.get("derived", {})),
                time.time(),
                1 if is_seed else 0,
            )
        )
        conn.commit()
        return cur.lastrowid


def load_character(char_id: int) -> dict | None:
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM characters WHERE id=?", (char_id,)
        ).fetchone()
    if not row:
        return None
    return _row_to_dict(row)


def load_all_characters() -> list[dict]:
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM characters ORDER BY created_at DESC"
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


def _row_to_dict(row) -> dict:
    d = dict(row)
    for key in ("stats_json", "traits_json", "gear_json", "appearance_json",
                "derived_json", "event_json"):
        col = key.replace("_json", "") if key != "event_json" else "event"
        try:
            d[col] = json.loads(d.get(key) or "{}")
        except Exception:
            d[col] = {}
        if key in d:
            del d[key]

    # motivation
    try:
        d["motivation"] = json.loads(d.get("motivation") or "{}")
    except Exception:
        d["motivation"] = {}

    return d


# ------------------------------------------------------------------ #
# Seed characters                                                     #
# ------------------------------------------------------------------ #

SEED_CHARACTERS = [
    # 1 — Dustfolk Gunslinger
    {
        "name": "Mara Stonechild",
        "faction": "Dustfolk",
        "archetype": "Gunslinger",
        "stats": {"grit": 3, "iron": 5, "ghost": 3, "tongue": 3, "wrench": 2, "trail": 4},
        "traits": ["Dead Eye", "Old Road"],
        "appearance": {
            "eyes": "pale blue (almost white)",
            "build": "lean and wire-tough",
            "marks": "missing the tip of the right index finger",
            "dress": "dust-caked trail coat, practical pockets",
        },
        "backstory_key": {
            "event_key": "lost_partner",
            "motivation_key": "revenge",
            "origin_town": "Copper Springs",
        },
    },
    # 2 — Ironclad Mechwright
    {
        "name": "Cassius Vane",
        "faction": "Ironclad",
        "archetype": "Mechwright",
        "stats": {"grit": 3, "iron": 3, "ghost": 2, "tongue": 2, "wrench": 6, "trail": 4},
        "traits": ["Jury Rig", "Iron Constitution"],
        "appearance": {
            "eyes": "amber, unsettling",
            "build": "broad-shouldered, deliberate",
            "marks": "Ashfall burn scar on the left hand",
            "dress": "Forgeworks-issue vest (stolen or earned — unclear)",
        },
        "backstory_key": {
            "event_key": "ashfall_exposure",
            "motivation_key": "treasure",
            "origin_town": "The Forgeworks",
        },
    },
    # 3 — Uncanny Hex-Slinger
    {
        "name": "Delilah Crow",
        "faction": "Uncanny",
        "archetype": "Hex-Slinger",
        "stats": {"grit": 2, "iron": 4, "ghost": 6, "tongue": 3, "wrench": 2, "trail": 3},
        "traits": ["Hex-Touched", "Blood Price"],
        "appearance": {
            "eyes": "black — no visible iris",
            "build": "slight — easy to underestimate",
            "marks": "grey streak through the hair — happened overnight, never explained",
            "dress": "black duster with a Void-touched lining",
        },
        "backstory_key": {
            "event_key": "divine_encounter",
            "motivation_key": "redemption",
            "origin_town": "The Boneyard",
        },
    },
    # 4 — Void Wanderer
    {
        "name": "Brother Ash",
        "faction": "Void",
        "archetype": "Wanderer",
        "stats": {"grit": 4, "iron": 3, "ghost": 4, "tongue": 4, "wrench": 2, "trail": 3},
        "traits": ["Void-Scarred", "Silver Tongue"],
        "appearance": {
            "eyes": "pale green, watchful",
            "build": "tall with a permanent stoop",
            "marks": "tattoo in a language nobody local speaks",
            "dress": "travel-worn pieces from three different territories",
        },
        "backstory_key": {
            "event_key": "hollow_court",
            "motivation_key": "duty",
            "origin_town": "The Scorch",
        },
    },
    # 5 — Dustfolk Medic
    {
        "name": "Vera Halfmoon",
        "faction": "Dustfolk",
        "archetype": "Medic",
        "stats": {"grit": 4, "iron": 2, "ghost": 3, "tongue": 5, "wrench": 3, "trail": 3},
        "traits": ["Steady Hand", "Pack Mule"],
        "appearance": {
            "eyes": "dark brown, sharp",
            "build": "compact and low to the ground",
            "marks": "three parallel claw marks across the collarbone",
            "dress": "working clothes, everything functional, nothing decorative",
        },
        "backstory_key": {
            "event_key": "war",
            "motivation_key": "survival",
            "origin_town": "Rustwater",
        },
    },
]


def seed_characters():
    """Insert pre-made characters if DB is empty."""
    with get_db() as conn:
        count = conn.execute("SELECT COUNT(*) FROM characters").fetchone()[0]
    if count > 0:
        return

    for seed in SEED_CHARACTERS:
        bk = seed.pop("backstory_key", {})
        char = generate_character(
            name=seed["name"],
            faction=seed["faction"],
            archetype=seed["archetype"],
            stats=seed["stats"],
            traits=seed["traits"],
            appearance=seed.get("appearance"),
        )
        backstory_data = generate_backstory(
            name=seed["name"],
            faction=seed["faction"],
            archetype=seed["archetype"],
            origin_town=bk.get("origin_town"),
            event_key=bk.get("event_key"),
            motivation_key=bk.get("motivation_key"),
        )
        char["backstory_data"] = backstory_data
        save_character(char, is_seed=True)


# ------------------------------------------------------------------ #
# Random name generator                                               #
# ------------------------------------------------------------------ #

_FIRST_NAMES = [
    "Mara", "Cassidy", "Delilah", "Vera", "Hattie", "Elsa", "Rowena",
    "Jesse", "Caleb", "Eli", "Colt", "Silas", "Rufus", "Clay", "Amos",
    "Jasper", "Obadiah", "Brother", "The", "Dutch", "Emmett",
]
_LAST_NAMES = [
    "Stonechild", "Vane", "Crow", "Halfmoon", "Ash", "Dusk", "Ember",
    "Graves", "Ironsides", "Blackwater", "Coldrain", "Salt", "Flint",
    "Bonner", "Hollowell", "Scorch", "Ridge", "Ashford", "Creed",
]


def random_frontier_name() -> str:
    return f"{random.choice(_FIRST_NAMES)} {random.choice(_LAST_NAMES)}"


# ------------------------------------------------------------------ #
# Routes                                                              #
# ------------------------------------------------------------------ #

@app.route("/")
def index():
    return render_template(
        "index.html",
        factions=FACTIONS,
        archetypes=ARCHETYPES,
        stats=STATS,
        stat_keys=STAT_KEYS,
        traits=TRAITS,
        appearances=APPEARANCES,
        stat_point_pool=STAT_POINT_POOL,
        stat_max=STAT_MAX,
        stat_min=STAT_MIN,
        events=get_all_events(),
        secrets=get_all_secrets(),
        motivations=get_all_motivations(),
    )


@app.route("/create", methods=["POST"])
def create():
    data = request.form

    name = data.get("name", "").strip()
    if not name:
        name = random_frontier_name()

    faction = data.get("faction", "Dustfolk")
    archetype = data.get("archetype", "Wanderer")

    # Parse stats from form
    stats = {}
    for k in STAT_KEYS:
        try:
            stats[k] = int(data.get(f"stat_{k}", STAT_MIN))
        except (ValueError, TypeError):
            stats[k] = STAT_MIN

    # Validate stats
    valid, err = validate_stats(stats)
    if not valid:
        return render_template(
            "index.html",
            error=err,
            factions=FACTIONS,
            archetypes=ARCHETYPES,
            stats=STATS,
            stat_keys=STAT_KEYS,
            traits=TRAITS,
            appearances=APPEARANCES,
            stat_point_pool=STAT_POINT_POOL,
            stat_max=STAT_MAX,
            stat_min=STAT_MIN,
            events=get_all_events(),
            secrets=get_all_secrets(),
            motivations=get_all_motivations(),
            form_data=data,
        ), 400

    # Parse traits
    traits = data.getlist("traits")
    if len(traits) != 2:
        return render_template(
            "index.html",
            error="Select exactly 2 traits.",
            factions=FACTIONS,
            archetypes=ARCHETYPES,
            stats=STATS,
            stat_keys=STAT_KEYS,
            traits=TRAITS,
            appearances=APPEARANCES,
            stat_point_pool=STAT_POINT_POOL,
            stat_max=STAT_MAX,
            stat_min=STAT_MIN,
            events=get_all_events(),
            secrets=get_all_secrets(),
            motivations=get_all_motivations(),
            form_data=data,
        ), 400

    # Appearance
    appearance = {
        "eyes": data.get("app_eyes", random.choice(APPEARANCES["eyes"])),
        "build": data.get("app_build", random.choice(APPEARANCES["build"])),
        "marks": data.get("app_marks", random.choice(APPEARANCES["marks"])),
        "dress": data.get("app_dress", random.choice(APPEARANCES["dress"])),
    }

    try:
        char = generate_character(
            name=name,
            faction=faction,
            archetype=archetype,
            stats=stats,
            traits=traits,
            appearance=appearance,
        )
    except ValueError as e:
        return render_template(
            "index.html",
            error=str(e),
            factions=FACTIONS,
            archetypes=ARCHETYPES,
            stats=STATS,
            stat_keys=STAT_KEYS,
            traits=TRAITS,
            appearances=APPEARANCES,
            stat_point_pool=STAT_POINT_POOL,
            stat_max=STAT_MAX,
            stat_min=STAT_MIN,
            events=get_all_events(),
            secrets=get_all_secrets(),
            motivations=get_all_motivations(),
            form_data=data,
        ), 400

    # Backstory
    event_key = data.get("event_key")
    motivation_key = data.get("motivation_key")
    backstory_data = generate_backstory(
        name=name,
        faction=faction,
        archetype=archetype,
        event_key=event_key or None,
        motivation_key=motivation_key or None,
    )
    char["backstory_data"] = backstory_data

    char_id = save_character(char)
    return redirect(url_for("character_sheet", char_id=char_id))


@app.route("/character/<int:char_id>")
def character_sheet(char_id: int):
    char = load_character(char_id)
    if not char:
        abort(404)
    return render_template(
        "character.html",
        char=char,
        stats=STATS,
        stat_keys=STAT_KEYS,
        factions=FACTIONS,
        archetypes=ARCHETYPES,
        traits=TRAITS,
        reportlab_available=REPORTLAB_AVAILABLE,
    )


@app.route("/gallery")
def gallery():
    characters = load_all_characters()
    return render_template(
        "gallery.html",
        characters=characters,
        factions=FACTIONS,
        archetypes=ARCHETYPES,
    )


@app.route("/export/<int:char_id>")
def export_pdf(char_id: int):
    char = load_character(char_id)
    if not char:
        abort(404)

    if not REPORTLAB_AVAILABLE:
        return "ReportLab not installed. Run: pip install reportlab", 503

    # Rebuild the char dict format pdf_sheet expects
    pdf_char = {
        "name": char["name"],
        "faction": char["faction"],
        "archetype": char["archetype"],
        "stats": char["stats"],
        "traits": char["traits"],
        "gear": char["gear"],
        "appearance": char["appearance"],
        "derived": char["derived"],
        "backstory": char.get("backstory", ""),
        "motivation": char.get("motivation", {}),
    }

    pdf_bytes = generate_pdf(pdf_char)
    safe_name = char["name"].replace(" ", "_").lower()

    response = make_response(pdf_bytes)
    response.headers["Content-Type"] = "application/pdf"
    response.headers["Content-Disposition"] = f'attachment; filename="dustfall_{safe_name}.pdf"'
    return response


# ---- AJAX endpoints ----

@app.route("/api/random-name")
def api_random_name():
    return jsonify({"name": random_frontier_name()})


@app.route("/api/backstory")
def api_backstory():
    """Returns random backstory components for live preview."""
    events = get_all_events()
    secrets = get_all_secrets()
    motivations = get_all_motivations()
    return jsonify({
        "event": random.choice(events),
        "secret": random.choice(secrets),
        "motivation": random.choice(list(motivations.values())),
    })


@app.route("/api/archetype/<archetype_key>")
def api_archetype(archetype_key: str):
    arch = ARCHETYPES.get(archetype_key)
    if not arch:
        return jsonify({"error": "Unknown archetype"}), 404
    return jsonify(arch)


# ------------------------------------------------------------------ #
# Startup                                                             #
# ------------------------------------------------------------------ #

def main():
    init_db()
    seed_characters()
    app.run(host="0.0.0.0", port=8445, debug=True)


if __name__ == "__main__":
    main()
