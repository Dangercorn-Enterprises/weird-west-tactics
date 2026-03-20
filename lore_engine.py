"""
Dustfall Lore Engine
Generates consistent world lore for the Dustfall: The Ashen Frontier universe.

All generated lore is saved to SQLite so the world stays coherent across sessions.
The engine is world-aware — it reads existing lore before generating new content
to avoid contradictions.

Generators:
  - Town:    name, history, factions, secrets, notable NPCs, deity influence
  - Quest:   quest hooks fitting the weird western tone
  - Item:    weapons, artifacts, consumables with flavor text
  - Enemy:   enemy backstories, motivations, weaknesses, world connections

Usage:
  from lore_engine import LoreEngine
  engine = LoreEngine()
  town = engine.generate_town(deity="Vulcan", region="The Forgeworks")
  quest = engine.generate_quest(city=town["name"], archetype="Gunslinger")
  item = engine.generate_item(item_type="weapon", deity="Baron Samedi")
  enemy = engine.generate_enemy(faction="Harrowed", tier=2)
"""

import json
import logging
import os
import random
import re
import sqlite3
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

# ------------------------------------------------------------------ #
# World constants (from DUSTFALL_BIBLE.md)                           #
# ------------------------------------------------------------------ #

DEITIES = {
    "Vulcan":       {"domain": "Forge, fire, industry", "faction": "Forgeworks Syndicate", "corruption": "Dehumanization", "territory": "The Forgeworks", "color": "brass and green Ashfall glow"},
    "Perun":        {"domain": "Thunder, war, justice", "faction": "The Regulators", "corruption": "Fanaticism", "territory": "Thunderheart", "color": "storm blue and iron grey"},
    "Baron Samedi": {"domain": "Death, crossroads, resurrection", "faction": "The Harrowed", "corruption": "Undeath", "territory": "The Boneyard", "color": "purple shadow and bone white"},
    "Coyote":       {"domain": "Trickery, change, the wild", "faction": "Dust Walkers", "corruption": "Chaos", "territory": "The Trickster's Maze", "color": "shifting red sand"},
    "Anansi":       {"domain": "Stories, cunning, knowledge", "faction": "Los Tejedores", "corruption": "Manipulation", "territory": "Unknown", "color": "web-silver and shadow"},
    "The Sleeping One": {"domain": "Endings, the deep earth", "faction": "The Hollow Court", "corruption": "Annihilation", "territory": "The Scorch", "color": "deep black and cold ash"},
}

REGIONS = [
    "The Flats", "The Forgeworks", "The Boneyard", "Thunderheart",
    "The Trickster's Maze", "Rustwater", "The Scorch",
    "Iron Pass", "Copper Springs", "Gallows Hill", "The Deep Rift",
    "Dusty Crossroads", "Thunder Mesa",
]

ARCHETYPES = ["Gunslinger", "Hexslinger", "Tinkerer", "Preacher", "Law Dog", "Drifter"]

WEAPON_TYPES = ["revolver", "rifle", "shotgun", "repeater", "ashfall pistol", "steam cannon", "hex focus", "blade", "throwing knife"]

ITEM_TYPES_ALL = ["weapon", "artifact", "consumable", "armor", "trinket"]

ENEMY_FACTIONS = {
    "Harrowed":             {"deity": "Baron Samedi", "tier": 1},
    "Forgeworks Syndicate": {"deity": "Vulcan",       "tier": 1},
    "Dust Walkers":         {"deity": "Coyote",       "tier": 1},
    "The Regulators":       {"deity": "Perun",        "tier": 2},
    "Los Tejedores":        {"deity": "Anansi",       "tier": 2},
    "The Hollow Court":     {"deity": "The Sleeping One", "tier": 3},
    "Wild":                 {"deity": None,           "tier": 1},
}

TONE_NOTES = """
The world of Dustfall has these tonal qualities:
- Dark, sun-bleached, heat-baked. Nothing is clean or new.
- Oppressive heat, cracked earth, Ashfall machinery that hisses and occasionally screams.
- Violence is consequential. Death is real. Dark humor lives alongside genuine dread.
- Gods walk among mortals. Divine influence is visible — Vulcan's territory has brass-and-steam architecture, Baron Samedi's has permanent twilight.
- Ashfall: glowing blue-green mineral, burns hotter than coal, screams when ignited, corrupts living things with prolonged exposure.
- Think: American Gods meets The Good The Bad and The Ugly meets FFT's War of the Magi.
- Year: 1889. Frontier America. Steampunk. Gods made manifest by immigrant faith.
"""

# ------------------------------------------------------------------ #
# SQLite schema                                                       #
# ------------------------------------------------------------------ #

class LoreDB:
    def __init__(self, db_path: Optional[Path] = None):
        base = Path(__file__).parent
        self._path = db_path or base / "lore" / "lore.db"
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self._path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._init_schema()

    def _init_schema(self):
        self._conn.executescript("""
            CREATE TABLE IF NOT EXISTS towns (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL UNIQUE,
                deity       TEXT,
                region      TEXT,
                mood        TEXT DEFAULT 'Stable',
                population  TEXT,
                data_json   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS quests (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                title       TEXT NOT NULL,
                city        TEXT,
                deity       TEXT,
                archetype   TEXT,
                quest_type  TEXT,
                data_json   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS items (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL UNIQUE,
                item_type   TEXT NOT NULL,
                deity       TEXT,
                rarity      TEXT,
                data_json   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS enemies (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL UNIQUE,
                faction     TEXT,
                tier        INTEGER DEFAULT 1,
                data_json   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS npcs (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL UNIQUE,
                town        TEXT,
                archetype   TEXT,
                data_json   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
        """)
        self._conn.commit()

    def save_town(self, data: dict) -> int:
        cur = self._conn.execute(
            """INSERT INTO towns (name, deity, region, mood, population, data_json, created_at)
               VALUES (?,?,?,?,?,?,?)
               ON CONFLICT(name) DO UPDATE SET data_json=excluded.data_json, created_at=excluded.created_at""",
            (data.get("name"), data.get("deity"), data.get("region"),
             data.get("mood", "Stable"), data.get("population"), json.dumps(data), time.time()),
        )
        self._conn.commit()
        return cur.lastrowid

    def save_quest(self, data: dict) -> int:
        cur = self._conn.execute(
            """INSERT INTO quests (title, city, deity, archetype, quest_type, data_json, created_at)
               VALUES (?,?,?,?,?,?,?)""",
            (data.get("title"), data.get("city"), data.get("deity"),
             data.get("archetype"), data.get("quest_type"), json.dumps(data), time.time()),
        )
        self._conn.commit()
        return cur.lastrowid

    def save_item(self, data: dict) -> int:
        cur = self._conn.execute(
            """INSERT INTO items (name, item_type, deity, rarity, data_json, created_at)
               VALUES (?,?,?,?,?,?)
               ON CONFLICT(name) DO UPDATE SET data_json=excluded.data_json""",
            (data.get("name"), data.get("item_type"), data.get("deity"),
             data.get("rarity"), json.dumps(data), time.time()),
        )
        self._conn.commit()
        return cur.lastrowid

    def save_enemy(self, data: dict) -> int:
        cur = self._conn.execute(
            """INSERT INTO enemies (name, faction, tier, data_json, created_at)
               VALUES (?,?,?,?,?)
               ON CONFLICT(name) DO UPDATE SET data_json=excluded.data_json""",
            (data.get("name"), data.get("faction"), data.get("tier", 1),
             json.dumps(data), time.time()),
        )
        self._conn.commit()
        return cur.lastrowid

    def get_towns(self, limit: int = 20) -> list[dict]:
        rows = self._conn.execute(
            "SELECT data_json FROM towns ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
        return [json.loads(r["data_json"]) for r in rows]

    def get_quests(self, city: Optional[str] = None, limit: int = 20) -> list[dict]:
        if city:
            rows = self._conn.execute(
                "SELECT data_json FROM quests WHERE city=? ORDER BY created_at DESC LIMIT ?",
                (city, limit),
            ).fetchall()
        else:
            rows = self._conn.execute(
                "SELECT data_json FROM quests ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return [json.loads(r["data_json"]) for r in rows]

    def get_items(self, item_type: Optional[str] = None, limit: int = 30) -> list[dict]:
        if item_type:
            rows = self._conn.execute(
                "SELECT data_json FROM items WHERE item_type=? ORDER BY created_at DESC LIMIT ?",
                (item_type, limit),
            ).fetchall()
        else:
            rows = self._conn.execute(
                "SELECT data_json FROM items ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return [json.loads(r["data_json"]) for r in rows]

    def get_enemies(self, faction: Optional[str] = None, limit: int = 30) -> list[dict]:
        if faction:
            rows = self._conn.execute(
                "SELECT data_json FROM enemies WHERE faction=? ORDER BY created_at DESC LIMIT ?",
                (faction, limit),
            ).fetchall()
        else:
            rows = self._conn.execute(
                "SELECT data_json FROM enemies ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return [json.loads(r["data_json"]) for r in rows]

    def get_town_names(self) -> list[str]:
        rows = self._conn.execute("SELECT name FROM towns ORDER BY created_at DESC").fetchall()
        return [r["name"] for r in rows]

    def get_all_names(self) -> dict:
        return {
            "towns": self.get_town_names(),
            "items": [r["name"] for r in self._conn.execute("SELECT name FROM items").fetchall()],
            "enemies": [r["name"] for r in self._conn.execute("SELECT name FROM enemies").fetchall()],
            "npcs": [r["name"] for r in self._conn.execute("SELECT name FROM npcs").fetchall()],
        }

    def stats(self) -> dict:
        return {
            "towns": self._conn.execute("SELECT COUNT(*) FROM towns").fetchone()[0],
            "quests": self._conn.execute("SELECT COUNT(*) FROM quests").fetchone()[0],
            "items": self._conn.execute("SELECT COUNT(*) FROM items").fetchone()[0],
            "enemies": self._conn.execute("SELECT COUNT(*) FROM enemies").fetchone()[0],
            "npcs": self._conn.execute("SELECT COUNT(*) FROM npcs").fetchone()[0],
        }


# ------------------------------------------------------------------ #
# Output formatters                                                   #
# ------------------------------------------------------------------ #

def to_markdown(data: dict, kind: str) -> str:
    """Format a lore dict to Markdown."""
    lines = [f"# {data.get('name', data.get('title', 'Untitled'))}", ""]

    if kind == "town":
        lines += [
            f"**Region:** {data.get('region', 'Unknown')}",
            f"**Deity Influence:** {data.get('deity', 'Neutral')}",
            f"**Population:** {data.get('population', 'Unknown')}",
            f"**Mood:** {data.get('mood', 'Stable')}",
            "",
            "## History",
            data.get("history", ""),
            "",
            "## Description",
            data.get("description", ""),
            "",
            "## Factions Present",
        ]
        for f in data.get("factions", []):
            lines.append(f"- **{f.get('name')}** ({f.get('alignment', 'neutral')}): {f.get('description', '')}")
        lines += ["", "## Notable NPCs"]
        for npc in data.get("npcs", []):
            lines.append(f"- **{npc.get('name')}** ({npc.get('archetype', 'unknown')}): {npc.get('description', '')}")
        lines += ["", "## Secrets"]
        for s in data.get("secrets", []):
            lines.append(f"- {s}")
        if data.get("ashfall_presence"):
            lines += ["", f"## Ashfall Presence", data["ashfall_presence"]]

    elif kind == "quest":
        lines += [
            f"**Type:** {data.get('quest_type', 'Unknown').upper()}",
            f"**Location:** {data.get('city', 'Unknown')}",
            f"**Deity Thread:** {data.get('deity', 'None')}",
            f"**Recommended Archetype:** {data.get('archetype', 'Any')}",
            "",
            "## Hook",
            data.get("hook", ""),
            "",
            "## Background",
            data.get("background", ""),
            "",
            "## Objectives",
        ]
        for o in data.get("objectives", []):
            lines.append(f"- {o}")
        lines += ["", "## Complications"]
        for c in data.get("complications", []):
            lines.append(f"- {c}")
        if data.get("reward"):
            lines += ["", "## Reward", data["reward"]]
        if data.get("divine_consequence"):
            lines += ["", "## Divine Consequence", data["divine_consequence"]]

    elif kind == "item":
        lines += [
            f"**Type:** {data.get('item_type', 'Unknown').title()}",
            f"**Deity:** {data.get('deity', 'None')}",
            f"**Rarity:** {data.get('rarity', 'Common').title()}",
            "",
            "## Flavor Text",
            f"*{data.get('flavor_text', '')}*",
            "",
            "## Description",
            data.get("description", ""),
        ]
        if data.get("stats"):
            lines += ["", "## Stats"]
            for k, v in data["stats"].items():
                lines.append(f"- **{k.title()}:** {v}")
        if data.get("lore_detail"):
            lines += ["", "## Lore", data["lore_detail"]]
        if data.get("corruption_effect"):
            lines += ["", "## Corruption Effect", data["corruption_effect"]]

    elif kind == "enemy":
        lines += [
            f"**Faction:** {data.get('faction', 'Wild')}",
            f"**Tier:** {data.get('tier', 1)}",
            "",
            "## Appearance",
            data.get("appearance", ""),
            "",
            "## Backstory",
            data.get("backstory", ""),
            "",
            "## Motivation",
            data.get("motivation", ""),
            "",
            "## Weaknesses",
        ]
        for w in data.get("weaknesses", []):
            lines.append(f"- {w}")
        lines += ["", "## World Connections"]
        for c in data.get("world_connections", []):
            lines.append(f"- {c}")
        if data.get("combat_behavior"):
            lines += ["", "## Combat Behavior", data["combat_behavior"]]
        if data.get("divine_nature"):
            lines += ["", "## Divine Nature", data["divine_nature"]]

    return "\n".join(lines)


# ------------------------------------------------------------------ #
# Claude prompt builders                                              #
# ------------------------------------------------------------------ #

def _world_context(db: LoreDB) -> str:
    """Build a brief world context string from existing lore for consistency."""
    names = db.get_all_names()
    existing = ""
    if names["towns"]:
        existing += f"Existing towns: {', '.join(names['towns'][:10])}\n"
    if names["npcs"]:
        existing += f"Known NPCs: {', '.join(names['npcs'][:10])}\n"
    if names["items"]:
        existing += f"Known items: {', '.join(names['items'][:10])}\n"
    if names["enemies"]:
        existing += f"Known enemies: {', '.join(names['enemies'][:10])}\n"
    return existing


def _town_prompt(deity: Optional[str], region: Optional[str], db: LoreDB) -> str:
    deity_info = ""
    if deity and deity in DEITIES:
        d = DEITIES[deity]
        deity_info = f"""
Deity Influence: {deity} — {d['domain']}
  Faction: {d['faction']}
  Corruption: {d['corruption']}
  Visual influence: {d['color']}
"""

    existing = _world_context(db)

    return f"""You are a lore writer for Dustfall: The Ashen Frontier.

{TONE_NOTES}

{deity_info}
Region: {region or 'The Flats (contested, no dominant deity)'}

Existing world context (do not reuse these names):
{existing}

Generate a new frontier town for this world. Output ONLY a JSON object with these exact fields:
{{
  "name": "unique town name (frontier western with a hint of divine influence)",
  "deity": "{deity or 'None (neutral)'}",
  "region": "{region or 'The Flats'}",
  "population": "Small (50-200) | Medium (200-500) | Large (500-2000)",
  "mood": "Thriving | Stable | Tense | Under Siege",
  "description": "2-3 sentence atmospheric description — heat, dust, divine influence visible in architecture",
  "history": "2-3 sentences: how this town came to exist, what conflict or opportunity spawned it",
  "factions": [
    {{"name": "faction name", "alignment": "friendly|hostile|neutral", "description": "1 sentence"}}
  ],
  "npcs": [
    {{"name": "NPC name", "archetype": "archetype or role", "description": "1 sentence — personality + secret hint"}}
  ],
  "secrets": ["secret 1", "secret 2", "secret 3"],
  "ashfall_presence": "1 sentence on Ashfall deposits or their absence and what that means",
  "services": ["service 1", "service 2", "service 3"],
  "rumor": "the most dangerous rumor circulating in the saloon right now"
}}

The name must be unique frontier-western with divine influence showing.
NPCs should have interesting secrets that could become quest hooks.
Secrets should tie to the gods, Ashfall, or the Sleeping One.
"""


def _quest_prompt(city: Optional[str], archetype: Optional[str], deity: Optional[str], db: LoreDB) -> str:
    towns = db.get_town_names()
    town_ref = city or (random.choice(towns) if towns else "Rustwater")

    archetype_note = f"Tailored for: {archetype}" if archetype else "For any archetype"
    deity_note = f"Deity thread: {deity}" if deity else "May involve any deity"

    existing = _world_context(db)

    return f"""You are a quest designer for Dustfall: The Ashen Frontier.

{TONE_NOTES}

Location: {town_ref}
{archetype_note}
{deity_note}

Existing world context:
{existing}

Generate a quest hook for this weird western world. Output ONLY a JSON object:
{{
  "title": "evocative quest title in frontier-western style",
  "quest_type": "Bounty | Rescue | Assault | Defense | Escort | Stealth | Choice | Divine Trial",
  "city": "{town_ref}",
  "deity": "{deity or 'None'}",
  "archetype": "{archetype or 'Any'}",
  "hook": "The thing the player hears in the saloon / sees on the bounty board. 2-3 compelling sentences.",
  "background": "What's actually going on behind the scenes. 2-3 sentences. Should be darker/more complex than the hook implies.",
  "objectives": ["primary objective", "optional objective 1", "optional objective 2"],
  "complications": ["complication that makes this not simple", "moral complication", "divine complication if any"],
  "enemies": ["enemy type 1", "enemy type 2"],
  "reward": "Gold amount + any special item or reputation gain",
  "divine_consequence": "What the relevant deity thinks of how you handled this. Or null if no deity involvement.",
  "twist": "The reveal that recontextualizes everything when the player gets halfway through"
}}

Quests should:
- Feel dangerous and morally grey
- Have a weird element (divine influence, Ashfall, something impossible)
- Tie into the larger war between the gods
- Leave the player with a choice that has real consequences
"""


def _item_prompt(item_type: str, deity: Optional[str], rarity: Optional[str], db: LoreDB) -> str:
    deity_note = ""
    if deity and deity in DEITIES:
        d = DEITIES[deity]
        deity_note = f"Deity: {deity} — {d['domain']}. Corruption: {d['corruption']}."

    existing_items = db.get_items(item_type=item_type, limit=10)
    existing_names = [i.get("name") for i in existing_items]
    names_note = f"Do not reuse these names: {', '.join(existing_names)}" if existing_names else ""

    return f"""You are an item designer for Dustfall: The Ashen Frontier.

{TONE_NOTES}

{deity_note}
Item type: {item_type}
Rarity: {rarity or 'choose appropriately (Common/Uncommon/Rare/Legendary)'}
{names_note}

Generate a unique {item_type} for this world. Output ONLY a JSON object:
{{
  "name": "unique item name — frontier western with divine or Ashfall flavoring",
  "item_type": "{item_type}",
  "deity": "{deity or 'None (or choose based on lore fit)'}",
  "rarity": "Common | Uncommon | Rare | Legendary",
  "flavor_text": "1-2 evocative sentences in italics — what a frontiersman would say about this item",
  "description": "Physical description: what it looks like, materials, how it was made",
  "stats": {{
    "damage_range": "X-Y (for weapons)",
    "accuracy": "XX% (for weapons)",
    "special_property": "what makes this item mechanically interesting",
    "range": "X tiles (for weapons)"
  }},
  "lore_detail": "2-3 sentences of world lore — who made it, where it's been, what legend surrounds it",
  "acquisition": "How a player might find or acquire this — loot, purchase, reward, divine grant",
  "corruption_effect": "If deity-aligned: what happens if you use this too much? Or null.",
  "tags": ["tag1", "tag2"]
}}

Item should feel dangerous, worn, and frontier-appropriate.
If Ashfall-powered, it should have the blue-green glow and that dangerous energy.
If deity-aligned, the deity's influence should be visible and have a cost.
"""


def _enemy_prompt(faction: Optional[str], tier: int, db: LoreDB) -> str:
    faction_note = ""
    if faction and faction in ENEMY_FACTIONS:
        f = ENEMY_FACTIONS[faction]
        deity = f.get("deity")
        if deity and deity in DEITIES:
            d = DEITIES[deity]
            faction_note = f"Faction: {faction} (serves {deity} — {d['domain']}). Corruption: {d['corruption']}."

    tier_guide = {
        1: "Tier 1 — Common encounter: 8-20 HP, basic threat",
        2: "Tier 2 — Veteran: 18-30 HP, tactical challenge",
        3: "Tier 3 — Boss: 30-60 HP, multi-phase, unique mechanics",
    }

    existing_enemies = db.get_enemies(faction=faction, limit=10)
    existing_names = [e.get("name") for e in existing_enemies]
    names_note = f"Do not reuse: {', '.join(existing_names)}" if existing_names else ""

    return f"""You are an enemy designer for Dustfall: The Ashen Frontier.

{TONE_NOTES}

{faction_note}
{tier_guide.get(tier, tier_guide[1])}
{names_note}

Generate a unique enemy for this world. Output ONLY a JSON object:
{{
  "name": "enemy name — evocative, frontier-western, divine-touched",
  "faction": "{faction or 'Wild'}",
  "tier": {tier},
  "hp": <number>,
  "speed": <1-8>,
  "appearance": "What the player sees when this enemy appears. Unsettling, specific, evocative.",
  "backstory": "Who or what was this before? What divine or Ashfall event created this enemy?",
  "motivation": "What does this enemy want? What drives its behavior beyond 'kill player'?",
  "weaknesses": ["weakness 1 (specific, exploitable)", "weakness 2"],
  "world_connections": ["connection to world lore 1", "connection to ongoing divine conflict"],
  "combat_behavior": "1-2 sentences on how this enemy fights — tactics, positioning, special moves",
  "divine_nature": "What deity power does this enemy channel, if any? What does fighting them feel like?",
  "loot": ["loot option 1", "loot option 2"],
  "field_notes": "What a veteran frontiersman knows about surviving an encounter with this enemy — one piece of hard-won advice"
}}

The enemy should:
- Have a personal tragedy or story that makes killing them feel meaningful
- Connect to the larger divine war in some way
- Have a weakness that rewards tactical play and world knowledge
- Feel specific to the Ashlands — not generic fantasy
"""


# ------------------------------------------------------------------ #
# Main Engine                                                         #
# ------------------------------------------------------------------ #

class LoreEngine:
    """
    Dustfall lore generation engine.
    Reads existing lore from SQLite before generating new content
    to maintain world consistency.
    """

    def __init__(self, db_path: Optional[Path] = None, model: Optional[str] = None):
        self.db = LoreDB(db_path)
        self._model = model or os.getenv("ANTHROPIC_MODEL", "claude-opus-4-5")
        self._api_key = os.getenv("ANTHROPIC_API_KEY", "")

    def _call_claude(self, prompt: str, max_tokens: int = 1500) -> Optional[dict]:
        """Call Claude and parse JSON response. Returns None on failure."""
        if not self._api_key:
            logger.warning("[lore] ANTHROPIC_API_KEY not set — using fallback generator")
            return None

        try:
            import anthropic
            client = anthropic.Anthropic(api_key=self._api_key)
            msg = client.messages.create(
                model=self._model,
                max_tokens=max_tokens,
                messages=[{"role": "user", "content": prompt}],
            )
            text = msg.content[0].text if msg.content else ""
            return _parse_json_response(text)
        except ImportError:
            logger.warning("[lore] anthropic package not installed")
            return None
        except Exception as exc:
            logger.error(f"[lore] Claude call failed: {exc}")
            return None

    def generate_town(
        self,
        deity: Optional[str] = None,
        region: Optional[str] = None,
    ) -> dict:
        """Generate a new town. Saves to DB. Returns dict."""
        prompt = _town_prompt(deity, region, self.db)
        data = self._call_claude(prompt, max_tokens=1800)
        if data is None:
            data = _fallback_town(deity, region, self.db)

        data["_generated_at"] = time.time()
        self.db.save_town(data)
        logger.info(f"[lore] Town generated: {data.get('name')}")
        return data

    def generate_quest(
        self,
        city: Optional[str] = None,
        archetype: Optional[str] = None,
        deity: Optional[str] = None,
    ) -> dict:
        """Generate a quest hook. Saves to DB. Returns dict."""
        prompt = _quest_prompt(city, archetype, deity, self.db)
        data = self._call_claude(prompt, max_tokens=1500)
        if data is None:
            data = _fallback_quest(city, archetype, deity, self.db)

        data["_generated_at"] = time.time()
        self.db.save_quest(data)
        logger.info(f"[lore] Quest generated: {data.get('title')}")
        return data

    def generate_item(
        self,
        item_type: str = "weapon",
        deity: Optional[str] = None,
        rarity: Optional[str] = None,
    ) -> dict:
        """Generate an item with flavor text. Saves to DB. Returns dict."""
        if item_type not in ITEM_TYPES_ALL:
            item_type = "weapon"

        prompt = _item_prompt(item_type, deity, rarity, self.db)
        data = self._call_claude(prompt, max_tokens=1200)
        if data is None:
            data = _fallback_item(item_type, deity, rarity)

        data["_generated_at"] = time.time()
        self.db.save_item(data)
        logger.info(f"[lore] Item generated: {data.get('name')}")
        return data

    def generate_enemy(
        self,
        faction: Optional[str] = None,
        tier: int = 1,
    ) -> dict:
        """Generate an enemy backstory. Saves to DB. Returns dict."""
        prompt = _enemy_prompt(faction, tier, self.db)
        data = self._call_claude(prompt, max_tokens=1500)
        if data is None:
            data = _fallback_enemy(faction, tier)

        data["_generated_at"] = time.time()
        self.db.save_enemy(data)
        logger.info(f"[lore] Enemy generated: {data.get('name')}")
        return data

    def list_towns(self, limit: int = 20) -> list[dict]:
        return self.db.get_towns(limit)

    def list_quests(self, city: Optional[str] = None, limit: int = 20) -> list[dict]:
        return self.db.get_quests(city=city, limit=limit)

    def list_items(self, item_type: Optional[str] = None, limit: int = 30) -> list[dict]:
        return self.db.get_items(item_type=item_type, limit=limit)

    def list_enemies(self, faction: Optional[str] = None, limit: int = 30) -> list[dict]:
        return self.db.get_enemies(faction=faction, limit=limit)

    def stats(self) -> dict:
        return self.db.stats()

    def export_markdown(self, kind: str, limit: int = 50) -> str:
        """Export all lore of a given kind to Markdown."""
        if kind == "towns":
            items = self.db.get_towns(limit)
        elif kind == "quests":
            items = self.db.get_quests(limit=limit)
        elif kind == "items":
            items = self.db.get_items(limit=limit)
        elif kind == "enemies":
            items = self.db.get_enemies(limit=limit)
        else:
            return "# Unknown lore type\n"

        kind_single = kind.rstrip("s")
        parts = [f"# Dustfall Lore: {kind.title()}\n"]
        for item in items:
            parts.append(to_markdown(item, kind_single))
            parts.append("\n---\n")
        return "\n".join(parts)


# ------------------------------------------------------------------ #
# JSON parser                                                         #
# ------------------------------------------------------------------ #

def _parse_json_response(text: str) -> Optional[dict]:
    """Extract and parse JSON from Claude's response."""
    text = text.strip()
    # Find outermost { }
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        # Try to fix common issues: trailing commas, single quotes
        cleaned = re.sub(r",(\s*[}\]])", r"\1", text[start:end + 1])
        try:
            return json.loads(cleaned)
        except Exception:
            return None


# ------------------------------------------------------------------ #
# Fallback generators (no Claude needed)                             #
# ------------------------------------------------------------------ #

_TOWN_ADJECTIVES = ["Dusty", "Cracked", "Scorched", "Ashfall", "Ironblood", "Grimrock", "Deadwater", "Bonehollow", "Coppergate", "Thunderpass"]
_TOWN_SUFFIXES = ["Crossing", "Flats", "Springs", "Ridge", "Junction", "Creek", "Gulch", "Reach", "Hollow"]


def _fallback_town(deity: Optional[str], region: Optional[str], db: LoreDB) -> dict:
    existing = db.get_town_names()
    name = None
    for adj in random.sample(_TOWN_ADJECTIVES, len(_TOWN_ADJECTIVES)):
        for suf in random.sample(_TOWN_SUFFIXES, len(_TOWN_SUFFIXES)):
            candidate = f"{adj} {suf}"
            if candidate not in existing:
                name = candidate
                break
        if name:
            break
    if not name:
        name = f"New Settlement {len(existing) + 1}"

    deity_str = deity or "None"
    return {
        "name": name,
        "deity": deity_str,
        "region": region or "The Flats",
        "population": random.choice(["Small (50-200)", "Medium (200-500)"]),
        "mood": random.choice(["Stable", "Tense"]),
        "description": f"A sun-bleached settlement clinging to the edge of {region or 'the flats'}. The kind of place where everyone knows everyone else's secrets and nobody talks about them.",
        "history": f"Founded three years back by prospectors chasing an Ashfall deposit that turned out to be real. The {'divine influence' if deity else 'lack of any god's blessing'} has shaped this place in ways the founders didn't expect.",
        "factions": [{"name": "The Old Guard", "alignment": "neutral", "description": "The original settlers, trying to keep order"}],
        "npcs": [{"name": "Marta Bones", "archetype": "Saloon Keeper", "description": "Knows everything, sells information for the right price"}],
        "secrets": ["There's an Ashfall deposit under the saloon floor", "The town marshal is wanted in two territories", "Something walks the streets after midnight"],
        "ashfall_presence": "A thin seam of Ashfall runs beneath the eastern quarter. The ground glows faintly at night.",
        "services": ["Saloon", "General Store", "Stables"],
        "rumor": "Someone's been stealing from the Ashfall mine and leaving payment in a dead language.",
    }


def _fallback_quest(city: Optional[str], archetype: Optional[str], deity: Optional[str], db: LoreDB) -> dict:
    towns = db.get_town_names()
    city = city or (random.choice(towns) if towns else "Rustwater")
    types = ["Bounty", "Rescue", "Assault", "Defense", "Choice"]
    return {
        "title": f"The {random.choice(['Devil', 'Hollow', 'Ashen', 'Iron', 'Dead'])} {random.choice(['Debt', 'Road', 'Contract', 'Bargain', 'Deal'])}",
        "quest_type": random.choice(types),
        "city": city,
        "deity": deity or "None",
        "archetype": archetype or "Any",
        "hook": f"A man with no shadow walked into {city}'s saloon last night and pinned a contract to the wall with a bone knife. Twenty gold to whoever brings him what's described inside.",
        "background": "The contract is written in blood and details the location of a buried Ashfall cache. The man is a Herald of the Sleeping One, and the 'cache' is actually a sealed rift. Opening it would be very bad.",
        "objectives": ["Investigate the contract", "Find the cache location", "Decide what to do with the rift"],
        "complications": ["The man with no shadow is watching", "A Harrowed crew got there first", "The rift is already partially open"],
        "enemies": ["Herald of the Hollow Court", "Walkin' Dead (corrupted prospectors)"],
        "reward": "120 gold + reputation with the deity you sided with",
        "divine_consequence": "Whatever god you helped remembers. The others don't forget.",
        "twist": "The original letter writer was a Regulator marshal who died ten years ago. The Sleeping One has been planning this for a decade.",
    }


def _fallback_item(item_type: str, deity: Optional[str], rarity: Optional[str]) -> dict:
    names_by_type = {
        "weapon": ["The Ashfall Judgment", "Cracked Bone Revolver", "The Widow's Tongue", "Ironheart Repeater"],
        "artifact": ["The Eye of Samedi", "Coyote's Coin", "Vulcan's Thumbscrew", "The Weaver's Thread"],
        "consumable": ["Ashfall Extract (Purified)", "Death's Door Tonic", "Coyote Dust (Aged)", "Perun's Thunder Draught"],
        "armor": ["The Hollow Duster", "Blessed Vestments of Rustwater", "Forgeworks Plating (Mark II)"],
        "trinket": ["Anansi's Web Fragment", "A Tooth from the Sleeping One", "Perun's Lightning-Struck Coin"],
    }
    name = random.choice(names_by_type.get(item_type, names_by_type["weapon"]))
    return {
        "name": name,
        "item_type": item_type,
        "deity": deity or "None",
        "rarity": rarity or "Uncommon",
        "flavor_text": "They say it was found in the Scorch, still warm. They say a lot of things out here.",
        "description": f"A {item_type} that shows clear Ashfall influence — the characteristic blue-green luminescence pulses faintly in the dark.",
        "stats": {"special_property": "Ashfall-charged: deals bonus damage to divine-aligned enemies"},
        "lore_detail": "Nobody knows who made it. The markings on the grip don't match any known craftsman's hand.",
        "acquisition": "Found as loot on a Tier 2 or higher enemy, or purchased at a Forgeworks-aligned settlement",
        "corruption_effect": "Extended use draws the attention of whichever god's domain it touches",
        "tags": [item_type, deity.lower().replace(" ", "_") if deity else "ashfall"],
    }


def _fallback_enemy(faction: Optional[str], tier: int) -> dict:
    faction = faction or "Wild"
    return {
        "name": f"The {random.choice(['Hollow', 'Cracked', 'Ashen', 'Iron'])} {random.choice(['Revenant', 'Drifter', 'Prophet', 'Marshal'])}",
        "faction": faction,
        "tier": tier,
        "hp": 12 + tier * 8,
        "speed": random.randint(3, 6),
        "appearance": "Sun-blackened, moving wrong. The kind of thing that used to be a person.",
        "backstory": "Found the wrong Ashfall deposit. Asked the wrong deity for help. Got exactly what they asked for.",
        "motivation": "Finish what they started before they died. The god that took them won't let the task go unfinished.",
        "weaknesses": ["Blessed ammunition (Preacher's blessing)", "Destroy the Ashfall shard they carry — it's sustaining them"],
        "world_connections": ["Connected to a failed quest in this region", "Used to be a local"],
        "combat_behavior": "Aggressive, ignores pain, targets the nearest player character with the highest Mien stat.",
        "divine_nature": f"Channeling {ENEMY_FACTIONS.get(faction, {}).get('deity') or 'corrupted Ashfall energy'}.",
        "loot": ["Ashfall Shard", "Old Marshal's Star (tarnished)"],
        "field_notes": "Don't hesitate. Whatever you knew about who they were before — that thing is gone.",
    }
