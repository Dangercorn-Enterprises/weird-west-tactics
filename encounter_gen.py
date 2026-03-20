"""
encounter_gen.py — Dustfall: The Ashen Frontier
Tactical encounter generator built on top of map_gen and lore_engine.

Combines a generated map with enemy composition, objectives, loot rewards,
and a narrative setup paragraph to produce a complete tactical encounter.

The encounter system is designed to be:
  - Self-contained: works without Claude API (fallback generators for all data)
  - World-aware: pulls from lore DB for consistent naming and faction coherence
  - Difficulty-scaled: player_level adjusts enemy count, tier, and loot quality
  - Narratively grounded: every encounter has a story reason to exist

Usage (library):
  from map_gen import generate_map
  from encounter_gen import generate_encounter

  m = generate_map("ghost_town", seed=42)
  enc = generate_encounter(m, player_level=3, faction="Uncanny")
  print(enc.narrative)
  print(enc.to_summary())

Usage (CLI):
  python encounter_gen.py --map-type ghost_town --level 3 --faction Ironclad --seed 42
  python encounter_gen.py --map-type cursed_ruins --level 5 --export encounter.json
  python encounter_gen.py --list-factions
"""

import argparse
import json
import random
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from map_gen import Map, generate_map, MAP_FACTIONS

# ------------------------------------------------------------------ #
# Difficulty scaling constants                                         #
# ------------------------------------------------------------------ #

# Each player level maps to: (min_enemies, max_enemies, tier_weights, loot_multiplier)
# tier_weights = {1: weight, 2: weight, 3: weight}
DIFFICULTY_TABLE = {
    1:  {"min_enemies": 2, "max_enemies": 3,  "tiers": {1: 90, 2: 10, 3: 0},  "loot_mult": 0.7},
    2:  {"min_enemies": 3, "max_enemies": 4,  "tiers": {1: 80, 2: 18, 3: 2},  "loot_mult": 0.8},
    3:  {"min_enemies": 3, "max_enemies": 5,  "tiers": {1: 65, 2: 30, 3: 5},  "loot_mult": 1.0},
    4:  {"min_enemies": 4, "max_enemies": 6,  "tiers": {1: 50, 2: 40, 3: 10}, "loot_mult": 1.2},
    5:  {"min_enemies": 4, "max_enemies": 7,  "tiers": {1: 35, 2: 50, 3: 15}, "loot_mult": 1.4},
    6:  {"min_enemies": 5, "max_enemies": 8,  "tiers": {1: 20, 2: 55, 3: 25}, "loot_mult": 1.6},
    7:  {"min_enemies": 5, "max_enemies": 9,  "tiers": {1: 10, 2: 55, 3: 35}, "loot_mult": 1.8},
    8:  {"min_enemies": 6, "max_enemies": 10, "tiers": {1: 5,  2: 50, 3: 45}, "loot_mult": 2.0},
    9:  {"min_enemies": 6, "max_enemies": 11, "tiers": {1: 0,  2: 45, 3: 55}, "loot_mult": 2.2},
    10: {"min_enemies": 7, "max_enemies": 12, "tiers": {1: 0,  2: 30, 3: 70}, "loot_mult": 2.5},
}

# Cap player level to table range
_MIN_LEVEL = 1
_MAX_LEVEL = 10


def _clamp_level(level: int) -> int:
    return max(_MIN_LEVEL, min(_MAX_LEVEL, level))


# ------------------------------------------------------------------ #
# Enemy archetype templates                                           #
# ------------------------------------------------------------------ #
# These are used when the lore DB has no generated enemies.
# Keyed by faction → list of enemy template dicts.
# Each template has: name, tier, hp_base, speed, behavior, weakness

_ENEMY_TEMPLATES = {
    "Dustfolk": [
        {
            "name": "Desperate Drifter",
            "tier": 1, "hp_base": 12, "speed": 4,
            "behavior": "Aggressive at close range, retreats behind cover when wounded",
            "weakness": "Flanking — panics when attacked from two directions",
            "divine_nature": None,
            "loot": ["Gold Coin Pouch", "Worn Revolver"],
        },
        {
            "name": "Hired Gun",
            "tier": 1, "hp_base": 16, "speed": 3,
            "behavior": "Uses cover methodically, suppresses player movement",
            "weakness": "Morale — breaks if leader is eliminated first",
            "divine_nature": None,
            "loot": ["Repeater Ammo", "Crude Map Fragment"],
        },
        {
            "name": "Bandit Captain",
            "tier": 2, "hp_base": 28, "speed": 4,
            "behavior": "Coordinates allies, calls retreats tactically, uses smoke bombs",
            "weakness": "Overconfidence — will pursue fleeing targets into bad positions",
            "divine_nature": None,
            "loot": ["Gold Bounty Stash", "Captain's Duster (Armor)"],
        },
    ],
    "Ironclad": [
        {
            "name": "Forgeworks Laborer",
            "tier": 1, "hp_base": 18, "speed": 3,
            "behavior": "Throws Ashfall grenades at range, brawls at melee",
            "weakness": "Ashfall corruption is unstable — hitting the grenade vest ends badly for them",
            "divine_nature": "Vulcan's blessing: fire resistance, Ashfall enhanced strikes",
            "loot": ["Ashfall Canister (Crude)", "Forgeworks Wages (Gold)"],
        },
        {
            "name": "Steam-Suit Enforcer",
            "tier": 2, "hp_base": 35, "speed": 2,
            "behavior": "Tanks incoming fire, pushes forward relentlessly",
            "weakness": "Steam joints are exposed — targeting the back reduces armor by half",
            "divine_nature": "Vulcan's blessing: steam-powered armor, heat aura",
            "loot": ["Forged Plate Segment", "Ashfall Core (Unstable)"],
        },
        {
            "name": "Forgeworks Overseer",
            "tier": 3, "hp_base": 55, "speed": 3,
            "behavior": "Summons reinforcements at half HP, uses Ashfall beam weapon",
            "weakness": "The beam weapon requires 2 turns to charge — interrupt or get behind cover",
            "divine_nature": "Vulcan's chosen: partial mechanical ascension, Ashfall channeling",
            "loot": ["Overseer's Brass Key", "Ashfall Beam Pistol (Damaged)"],
        },
    ],
    "Uncanny": [
        {
            "name": "Walkin' Dead",
            "tier": 1, "hp_base": 14, "speed": 3,
            "behavior": "Ignores pain, swarms targets, attracted to noise",
            "weakness": "Blessed ammunition halves their regeneration; destroying the Ashfall shard they carry stops it entirely",
            "divine_nature": "Baron Samedi's corruption: undeath, pain immunity, partial regeneration",
            "loot": ["Tarnished Silver Coin", "Ashfall Shard (Cold)"],
        },
        {
            "name": "Crossroads Revenant",
            "tier": 2, "hp_base": 26, "speed": 5,
            "behavior": "Teleports short distances between cover positions, ambushes isolated targets",
            "weakness": "Salt circles (consumable item) prevent the teleport for 2 turns",
            "divine_nature": "Baron Samedi's will: crossroads power, limited death-cheating",
            "loot": ["Death's Door Tonic", "Revenant's Bone Charm"],
        },
        {
            "name": "Harrowed Preacher",
            "tier": 3, "hp_base": 48, "speed": 3,
            "behavior": "Raises fallen allies as Tier 1 Walkin' Dead; sermons cause fear status",
            "weakness": "Cannot raise enemies that have been blessed — bring a Preacher",
            "divine_nature": "Baron Samedi's prophet: death channeling, resurrection liturgy",
            "loot": ["Samedi's Sermon (Cursed Artifact)", "Resurrection Dust (Rare Consumable)"],
        },
    ],
    "Void": [
        {
            "name": "Hollow Whisper",
            "tier": 1, "hp_base": 10, "speed": 6,
            "behavior": "Never attacks directly — debuffs, disorients, forces repositioning",
            "weakness": "Cannot exist in direct sunlight (hazard tiles powered by Ashfall damage it)",
            "divine_nature": "The Sleeping One's fragment: annihilation energy, dread aura",
            "loot": ["Void Dust (Rare Consumable)", "Fragment of Silence"],
        },
        {
            "name": "Hollow Court Evangelist",
            "tier": 2, "hp_base": 30, "speed": 4,
            "behavior": "Converts neutral enemies to Void allegiance; aura suppresses divine abilities",
            "weakness": "The Sleeping One's power is weakened by loud noise — explosives disorient them",
            "divine_nature": "The Sleeping One's herald: conversion preaching, divine suppression field",
            "loot": ["Court's Seal (Artifact)", "Ashfall Nullifier (Rare)"],
        },
        {
            "name": "Void Incarnate",
            "tier": 3, "hp_base": 65, "speed": 3,
            "behavior": "Rewrites local terrain each turn (floors become void); cannot be killed — must be sealed",
            "weakness": "Sealing requires placing three Ashfall charges at ritual circle points on the map",
            "divine_nature": "The Sleeping One given temporary flesh: reality erasure, infinite patience",
            "loot": ["Piece of the Sleeping One (Legendary Artifact)", "Void-Touched Gold"],
        },
    ],
}

# ------------------------------------------------------------------ #
# Objective templates per map type                                    #
# ------------------------------------------------------------------ #

_OBJECTIVE_TEMPLATES = {
    "ghost_town": [
        ("Eliminate", "Kill all enemies — {enemy_count} {faction} guns are in this town."),
        ("Recover", "Reach the objective marker and hold it for 3 turns while enemies contest it."),
        ("Survive", "Hold the spawn zone until the extraction timer (8 turns) expires."),
        ("Assassinate", "Eliminate the Tier {max_tier} leader before they can sound the alarm."),
    ],
    "canyon": [
        ("Break Through", "Reach the north edge of the map with at least 1 player alive."),
        ("Clear the Passage", "Eliminate all enemies holding the chokepoint."),
        ("Survive the Ambush", "Survive 6 turns until reinforcements arrive."),
        ("Secure the Ore", "Reach the objective (Ashfall deposit) and hold it for 2 turns."),
    ],
    "mine_shaft": [
        ("Plant the Charge", "Reach the objective and plant a dynamite charge. Then escape."),
        ("Rescue", "Reach the objective (prisoner location) and escort them to spawn zone."),
        ("Collapse the Mine", "Hold the objective for 3 turns while enemies pour in from tunnels."),
        ("Claim the Vein", "Collect loot from all {loot_count} ore caches without losing a squad member."),
    ],
    "desert_outpost": [
        ("Breach and Clear", "Eliminate all enemies inside the perimeter."),
        ("Capture the Command Post", "Reach the objective and hold it for 4 turns."),
        ("Destroy the Supply Cache", "Reach loot tiles and destroy them — enemies must not escape."),
        ("Hold the Gate", "Prevent enemy breakthrough for 5 turns."),
    ],
    "cursed_ruins": [
        ("Seal the Rift", "Activate the objective tile — and survive what comes out of it."),
        ("Disrupt the Ritual", "Destroy all ritual circle markers before the timer expires (5 turns)."),
        ("Survive the Summoning", "Survive 7 turns against escalating Void manifestations."),
        ("Recover the Relic", "Reach the objective tile and extract with the relic."),
    ],
}

# ------------------------------------------------------------------ #
# Reward tables                                                       #
# ------------------------------------------------------------------ #

_BASE_GOLD_BY_LEVEL = {
    1: 30,  2: 50,  3: 75,  4: 100, 5: 130,
    6: 165, 7: 200, 8: 240, 9: 285, 10: 340,
}

_LOOT_POOL_BY_TIER = {
    1: ["Revolver Ammo", "Field Bandage", "Ashfall Dust (Trace)", "Gold Coins (15)", "Trail Rations"],
    2: ["Crude Ashfall Shard", "Hex Shell (x3)", "Tonic of Speed", "Gold Coins (40)", "Worn Artifact Fragment"],
    3: ["Purified Ashfall Extract", "Blessed Ammunition (x6)", "Gold Coins (80)", "Legendary Artifact Component", "Divine Favor Token"],
}

# ------------------------------------------------------------------ #
# Encounter dataclass                                                 #
# ------------------------------------------------------------------ #

@dataclass
class Encounter:
    """
    A complete tactical encounter ready for game engine consumption.

    Attributes:
        map             — the Map object this encounter takes place on
        player_level    — the player level this encounter was balanced for
        faction         — enemy faction controlling this encounter
        enemies         — list of enemy dicts with stats and placement data
        objective_type  — short label (e.g., "Breach and Clear")
        objective_text  — full objective description shown to player
        rewards         — dict of gold_amount and loot_items list
        narrative       — flavor text paragraph shown at encounter start
        seed            — RNG seed used for this encounter (separate from map seed)
        difficulty_rating — computed difficulty score (1-10 scale)
    """
    map: Map
    player_level: int
    faction: str
    enemies: list[dict]
    objective_type: str
    objective_text: str
    rewards: dict
    narrative: str
    seed: int
    difficulty_rating: float = 0.0

    def to_summary(self) -> str:
        """
        Return a formatted text summary of the encounter for CLI display.
        """
        lines = [
            "=" * 55,
            f"  ENCOUNTER: {self.map.map_type.upper().replace('_', ' ')}",
            f"  {self.map.town_name or self.map.region} — {self.faction}",
            "=" * 55,
            "",
            "NARRATIVE",
            "-" * 40,
            self.narrative,
            "",
            "OBJECTIVE",
            "-" * 40,
            f"[{self.objective_type.upper()}] {self.objective_text}",
            "",
            f"ENEMIES ({len(self.enemies)} total, difficulty {self.difficulty_rating:.1f}/10)",
            "-" * 40,
        ]

        # Group enemies by tier
        by_tier: dict[int, list] = {}
        for e in self.enemies:
            t = e.get("tier", 1)
            by_tier.setdefault(t, []).append(e)

        for tier in sorted(by_tier.keys()):
            tier_label = {1: "Tier 1 — Standard", 2: "Tier 2 — Veteran", 3: "Tier 3 — Elite/Boss"}
            lines.append(f"  {tier_label.get(tier, f'Tier {tier}')}:")
            for e in by_tier[tier]:
                pos = e.get("spawn_position", "?")
                lines.append(f"    • {e['name']} (HP:{e['hp']} SPD:{e['speed']}) at {pos}")
                lines.append(f"      {e['behavior']}")
                lines.append(f"      Weakness: {e['weakness']}")
                if e.get("divine_nature"):
                    lines.append(f"      Divine: {e['divine_nature']}")

        lines += [
            "",
            "REWARDS",
            "-" * 40,
            f"  Gold: {self.rewards['gold']}",
            "  Loot:",
        ]
        for item in self.rewards["loot_items"]:
            lines.append(f"    • {item}")

        lines += [
            "",
            "MAP STATS",
            "-" * 40,
            f"  Size: {self.map.width}x{self.map.height} | Faction: {self.map.faction}",
            f"  Cover positions: {len(self.map.get_cover_positions())}",
            f"  Hazard tiles: {len(self.map.get_hazard_positions())}",
            f"  Loot caches: {len(self.map.get_loot_positions())}",
            f"  Player spawns: {len(self.map.get_spawn_points('player'))}",
            "=" * 55,
        ]

        return "\n".join(lines)

    def to_json(self) -> dict:
        """
        Serialize the encounter to a JSON-compatible dict.
        Includes the full map JSON as a nested structure.
        """
        return {
            "player_level": self.player_level,
            "faction": self.faction,
            "objective_type": self.objective_type,
            "objective_text": self.objective_text,
            "difficulty_rating": self.difficulty_rating,
            "narrative": self.narrative,
            "enemies": self.enemies,
            "rewards": self.rewards,
            "seed": self.seed,
            "map": self.map.to_json(),
            "generated_at": time.time(),
        }


# ------------------------------------------------------------------ #
# Enemy population logic                                              #
# ------------------------------------------------------------------ #

def _get_lore_enemies(faction: str, tier: int, limit: int = 10) -> list[dict]:
    """
    Try to pull enemy entries from the lore DB for this faction/tier.
    Returns empty list if DB unavailable or no matching entries.
    """
    try:
        from lore_engine import LoreDB
        db = LoreDB()
        # Get enemies matching this faction (any tier — we'll filter)
        enemies = db.get_enemies(faction=_map_faction_to_lore(faction), limit=limit)
        # Filter to matching tier or lower (higher tier enemies fill in)
        matching = [e for e in enemies if e.get("tier", 1) <= tier]
        return matching
    except Exception:
        return []


def _map_faction_to_lore(faction: str) -> Optional[str]:
    """
    Map map_gen faction name to lore_engine ENEMY_FACTIONS key.
    """
    mapping = {
        "Dustfolk":  "Wild",
        "Ironclad":  "Forgeworks Syndicate",
        "Uncanny":   "Harrowed",
        "Void":      "The Hollow Court",
    }
    return mapping.get(faction, faction)


def _weighted_tier(rng: random.Random, tier_weights: dict[int, int]) -> int:
    """Select a tier using the weighted probability table."""
    population = []
    for tier, weight in tier_weights.items():
        if weight > 0:
            population.extend([tier] * weight)
    return rng.choice(population) if population else 1


def _populate_enemies(
    rng: random.Random,
    faction: str,
    count: int,
    tier_weights: dict[int, int],
    spawn_positions: list[tuple[int, int]],
) -> list[dict]:
    """
    Build the enemy roster for this encounter.

    Order of preference for enemy data:
    1. Lore DB entries for this faction (world-consistent, Claude-generated)
    2. _ENEMY_TEMPLATES fallback (built-in, no DB required)

    Each enemy gets a spawn position assigned from the map's enemy spawn tiles.
    """
    enemies = []
    available_positions = list(spawn_positions)
    rng.shuffle(available_positions)

    for i in range(count):
        # Determine this enemy's tier
        tier = _weighted_tier(rng, tier_weights)

        # Try lore DB first
        lore_pool = _get_lore_enemies(faction, tier)
        template = None

        if lore_pool:
            # Pick a random lore enemy of the appropriate tier
            tier_pool = [e for e in lore_pool if e.get("tier", 1) == tier]
            if not tier_pool:
                tier_pool = lore_pool
            template = rng.choice(tier_pool)
            # Normalize lore DB fields to our expected structure
            enemy = {
                "name": template.get("name", "Unknown Enemy"),
                "tier": tier,
                "hp": template.get("hp", 12 + tier * 8),
                "speed": template.get("speed", rng.randint(3, 5)),
                "behavior": template.get("combat_behavior", "Engages nearest target"),
                "weakness": (template.get("weaknesses") or ["Flanking"])[0],
                "divine_nature": template.get("divine_nature"),
                "loot": template.get("loot", ["Gold Coins"]),
                "faction": faction,
                "source": "lore_db",
            }
        else:
            # Fallback to built-in templates
            template_pool = _ENEMY_TEMPLATES.get(faction, _ENEMY_TEMPLATES["Dustfolk"])
            # Filter to matching tier
            tier_pool = [t for t in template_pool if t["tier"] == tier]
            if not tier_pool:
                # Fall back to any tier if no exact match
                tier_pool = template_pool
            tmpl = rng.choice(tier_pool)

            # Apply small HP variance (±10%) for variety
            hp_variance = int(tmpl["hp_base"] * rng.uniform(0.9, 1.1))
            enemy = {
                "name": tmpl["name"],
                "tier": tier,
                "hp": hp_variance,
                "speed": tmpl["speed"] + rng.randint(-1, 1),
                "behavior": tmpl["behavior"],
                "weakness": tmpl["weakness"],
                "divine_nature": tmpl.get("divine_nature"),
                "loot": tmpl.get("loot", ["Gold Coins"]),
                "faction": faction,
                "source": "template",
            }

        # Assign spawn position
        if available_positions:
            enemy["spawn_position"] = available_positions.pop()
        else:
            enemy["spawn_position"] = None

        enemies.append(enemy)

    return enemies


# ------------------------------------------------------------------ #
# Reward calculation                                                  #
# ------------------------------------------------------------------ #

def _calculate_rewards(
    rng: random.Random,
    player_level: int,
    enemies: list[dict],
    loot_count: int,
    loot_multiplier: float,
) -> dict:
    """
    Calculate encounter rewards based on player level, enemy composition,
    and number of map loot caches.

    Higher tier enemies and more loot caches = better rewards.
    """
    base_gold = _BASE_GOLD_BY_LEVEL.get(player_level, 100)

    # Bonus gold for higher tier enemies
    tier_bonus = sum(
        {1: 0, 2: 15, 3: 40}.get(e.get("tier", 1), 0)
        for e in enemies
    )
    total_gold = int((base_gold + tier_bonus) * loot_multiplier)

    # Collect loot from enemy loot tables
    loot_items = []
    for enemy in enemies:
        enemy_loot = enemy.get("loot", [])
        # Each enemy drops one item from their loot table with a probability
        if enemy_loot and rng.random() < (0.4 + enemy.get("tier", 1) * 0.15):
            loot_items.append(rng.choice(enemy_loot))

    # Additional loot from map caches
    cache_tier = min(3, max(1, player_level // 3 + 1))
    cache_pool = _LOOT_POOL_BY_TIER.get(cache_tier, _LOOT_POOL_BY_TIER[1])
    cache_loot_count = min(loot_count, rng.randint(1, 3))
    for _ in range(cache_loot_count):
        loot_items.append(rng.choice(cache_pool))

    # Deduplicate while preserving order
    seen = set()
    unique_loot = []
    for item in loot_items:
        if item not in seen:
            seen.add(item)
            unique_loot.append(item)

    return {
        "gold": total_gold,
        "loot_items": unique_loot or ["Ashfall Dust (Trace)", "Gold Coins (15)"],
        "xp": player_level * 20 + len(enemies) * 8,
    }


# ------------------------------------------------------------------ #
# Narrative generation                                                #
# ------------------------------------------------------------------ #

def _build_narrative(
    rng: random.Random,
    map_obj: Map,
    faction: str,
    enemies: list[dict],
    objective_type: str,
) -> str:
    """
    Build the encounter's narrative setup paragraph.

    Tries to use lore engine town/faction context for specificity.
    Falls back to per-map-type template text.
    """
    faction_data = MAP_FACTIONS.get(faction, MAP_FACTIONS["Dustfolk"])
    town_ref = map_obj.town_name or map_obj.region

    # Try to pull town lore from DB for richer context
    town_context = ""
    try:
        from lore_engine import LoreDB
        db = LoreDB()
        towns = db.get_towns(limit=20)
        matching = [t for t in towns if t.get("name") == map_obj.town_name]
        if matching:
            town_data = matching[0]
            town_context = f"{town_data.get('description', '')} {town_data.get('rumor', '')}"
    except Exception:
        pass

    # Enemy composition flavor
    tier3_enemies = [e for e in enemies if e.get("tier") == 3]
    tier2_enemies = [e for e in enemies if e.get("tier") == 2]
    named_threat = (
        tier3_enemies[0]["name"] if tier3_enemies
        else tier2_enemies[0]["name"] if tier2_enemies
        else enemies[0]["name"] if enemies
        else "unknown threat"
    )

    # Faction-specific opening lines
    faction_openings = {
        "Dustfolk": f"Word reached you three towns back: {town_ref} has been taken.",
        "Ironclad": f"Vulcan's industry never rests. The Forgeworks Syndicate has moved on {town_ref} and they brought hardware.",
        "Uncanny": f"There are things that shouldn't walk. They're walking through {town_ref} now.",
        "Void": f"They call it Quiet before a Hollow Court advance. The birds left {town_ref} two days ago.",
    }

    faction_middles = {
        "Dustfolk": (
            f"It's not a faction job — just desperate people making desperate choices. "
            f"The {named_threat} is running the show, and they don't plan to negotiate."
        ),
        "Ironclad": (
            f"The {named_threat} is coordinating the operation — part of a larger push "
            f"to claim the Ashfall deposits in this territory for Vulcan's expansion. "
            f"They've set up {faction_data['spawn_flavor']}."
        ),
        "Uncanny": (
            f"The {named_threat} is somewhere in there, and where they go, the dead follow. "
            f"Baron Samedi is watching this one personally. "
            f"You can tell by {faction_data['spawn_flavor']}."
        ),
        "Void": (
            f"The {named_threat} doesn't fight — it converts, it silences, it ends. "
            f"The Sleeping One is making a move, and {town_ref} is the opening gambit. "
            f"They left their signature: {faction_data['spawn_flavor']}."
        ),
    }

    objective_closers = {
        "Eliminate":          "There's only one way this ends. Make sure you're the one still breathing.",
        "Recover":            "The objective is buried in there somewhere. Get to it. Hold it. Don't die doing it.",
        "Survive":            "You don't need to win. You need to last. Eight turns. That's all.",
        "Assassinate":        "One target. Clean. Everything else is collateral.",
        "Break Through":      "Don't stop. Don't engage unless you have to. The other side of that canyon is survival.",
        "Clear the Passage":  "Until the passage is clear, nothing moves. Make it clear.",
        "Plant the Charge":   "In. Plant it. Out. Don't look back when it goes.",
        "Rescue":             "Someone is in there waiting for you to come through. Don't let them wait forever.",
        "Breach and Clear":   "Hit the perimeter, move through fast, leave nobody standing.",
        "Seal the Rift":      "The rift shouldn't be open. Someone made a very bad decision. Your job is to make it the last bad decision they ever make.",
        "Disrupt the Ritual": "They need time to finish it. You're the reason they don't get it.",
    }

    opening = faction_openings.get(faction, f"Trouble in {town_ref}.")
    middle = faction_middles.get(faction, f"The {named_threat} is dug in and ready.")
    closer = objective_closers.get(objective_type, "Do what needs doing.")

    # Weave in town context if we have it
    if town_context:
        # Use the first sentence of town context as color
        first_sentence = town_context.split(".")[0].strip()
        if first_sentence:
            middle = f"{first_sentence}. {middle}"

    return f"{opening} {middle} {closer}"


# ------------------------------------------------------------------ #
# Difficulty rating                                                   #
# ------------------------------------------------------------------ #

def _compute_difficulty(
    enemies: list[dict],
    map_obj: Map,
    player_level: int,
) -> float:
    """
    Compute a 1-10 difficulty rating for display purposes.

    Factors:
    - Enemy count relative to player level baseline
    - Tier composition (higher tier = harder)
    - Map hazard count (more hazards = harder)
    - Map type (cursed_ruins hardest, ghost_town easiest)
    """
    # Enemy power score
    enemy_power = sum(
        {1: 1.0, 2: 2.5, 3: 5.0}.get(e.get("tier", 1), 1.0)
        for e in enemies
    )

    # Baseline: player_level * 1.5 = "fair" enemy power score
    baseline = player_level * 1.5
    power_ratio = enemy_power / max(baseline, 1.0)

    # Hazard modifier (each hazard tile = slight difficulty bump)
    hazard_mod = min(0.5, len(map_obj.get_hazard_positions()) * 0.05)

    # Map type modifier
    map_type_mod = {
        "ghost_town":     0.0,
        "desert_outpost": 0.1,
        "canyon":         0.2,
        "mine_shaft":     0.2,
        "cursed_ruins":   0.5,
    }.get(map_obj.map_type, 0.0)

    raw = (power_ratio * 5.0) + hazard_mod + map_type_mod
    return round(min(10.0, max(1.0, raw)), 1)


# ------------------------------------------------------------------ #
# Objective selection                                                 #
# ------------------------------------------------------------------ #

def _select_objective(
    rng: random.Random,
    map_type: str,
    enemies: list[dict],
    loot_positions: list,
) -> tuple[str, str]:
    """
    Select and format an objective for the encounter.

    Returns:
        (objective_type, objective_text) tuple
    """
    templates = _OBJECTIVE_TEMPLATES.get(map_type, _OBJECTIVE_TEMPLATES["ghost_town"])
    obj_type_raw, obj_text_raw = rng.choice(templates)

    max_tier = max((e.get("tier", 1) for e in enemies), default=1)
    obj_text = obj_text_raw.format(
        enemy_count=len(enemies),
        faction=enemies[0]["faction"] if enemies else "unknown",
        max_tier=max_tier,
        loot_count=len(loot_positions),
    )

    return obj_type_raw, obj_text


# ------------------------------------------------------------------ #
# Public API                                                          #
# ------------------------------------------------------------------ #

def generate_encounter(
    map_obj: Map,
    player_level: int = 3,
    faction: Optional[str] = None,
    seed: Optional[int] = None,
) -> Encounter:
    """
    Generate a complete tactical encounter for the given map.

    Args:
        map_obj      — a Map object from generate_map()
        player_level — player level (1-10) for difficulty scaling
        faction      — override the faction (defaults to map.faction)
        seed         — RNG seed for encounter (separate from map seed)

    Returns:
        Encounter object with enemies, objective, rewards, and narrative.

    Example:
        from map_gen import generate_map
        from encounter_gen import generate_encounter

        m = generate_map("ghost_town", seed=42)
        enc = generate_encounter(m, player_level=3)
        print(enc.narrative)
        print(enc.to_summary())
    """
    player_level = _clamp_level(player_level)

    if seed is None:
        seed = random.randint(0, 2 ** 32 - 1)

    rng = random.Random(seed)

    # Use provided faction or fall back to map's faction
    effective_faction = faction if faction in MAP_FACTIONS else map_obj.faction
    if effective_faction not in MAP_FACTIONS:
        effective_faction = "Dustfolk"

    # Look up difficulty parameters for this level
    diff = DIFFICULTY_TABLE[player_level]
    enemy_count = rng.randint(diff["min_enemies"], diff["max_enemies"])
    tier_weights = diff["tiers"]
    loot_multiplier = diff["loot_mult"]

    # Get spawn positions from the map
    spawn_positions = map_obj.get_spawn_points("enemy")

    # Build enemy roster
    enemies = _populate_enemies(
        rng,
        faction=effective_faction,
        count=enemy_count,
        tier_weights=tier_weights,
        spawn_positions=spawn_positions,
    )

    # Select objective
    objective_type, objective_text = _select_objective(
        rng,
        map_type=map_obj.map_type,
        enemies=enemies,
        loot_positions=map_obj.get_loot_positions(),
    )

    # Calculate rewards
    rewards = _calculate_rewards(
        rng,
        player_level=player_level,
        enemies=enemies,
        loot_count=len(map_obj.get_loot_positions()),
        loot_multiplier=loot_multiplier,
    )

    # Build narrative
    narrative = _build_narrative(
        rng,
        map_obj=map_obj,
        faction=effective_faction,
        enemies=enemies,
        objective_type=objective_type,
    )

    # Compute difficulty rating
    difficulty_rating = _compute_difficulty(enemies, map_obj, player_level)

    return Encounter(
        map=map_obj,
        player_level=player_level,
        faction=effective_faction,
        enemies=enemies,
        objective_type=objective_type,
        objective_text=objective_text,
        rewards=rewards,
        narrative=narrative,
        seed=seed,
        difficulty_rating=difficulty_rating,
    )


def list_factions() -> dict[str, dict]:
    """Return all available factions with their metadata."""
    return {
        k: {
            "deity": v.get("deity", "None"),
            "tone": v["tone"],
            "color": v["color"],
        }
        for k, v in MAP_FACTIONS.items()
    }


# ------------------------------------------------------------------ #
# CLI entrypoint                                                      #
# ------------------------------------------------------------------ #

def _cli_main() -> None:
    parser = argparse.ArgumentParser(
        description="Dustfall encounter generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python encounter_gen.py --map-type ghost_town --level 3 --faction Ironclad --seed 42
  python encounter_gen.py --map-type cursed_ruins --level 5 --preview
  python encounter_gen.py --map-type canyon --level 7 --export encounter.json
  python encounter_gen.py --list-factions
        """,
    )

    parser.add_argument("--map-type", dest="map_type", default="ghost_town",
                        help="Map type to generate (default: ghost_town)")
    parser.add_argument("--level", type=int, default=3,
                        help="Player level 1-10 for difficulty scaling (default: 3)")
    parser.add_argument("--faction", default=None,
                        help="Override enemy faction (Dustfolk, Ironclad, Uncanny, Void)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Shared seed for both map and encounter (random if omitted)")
    parser.add_argument("--map-seed", type=int, default=None,
                        help="Separate seed for map only (overrides --seed for map)")
    parser.add_argument("--encounter-seed", type=int, default=None,
                        help="Separate seed for encounter only (overrides --seed for encounter)")
    parser.add_argument("--size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"),
                        default=[20, 15],
                        help="Map dimensions (default: 20 15)")
    parser.add_argument("--preview", action="store_true",
                        help="Print ASCII map preview")
    parser.add_argument("--export", metavar="FILE",
                        help="Export full encounter as JSON to the specified file")
    parser.add_argument("--list-factions", action="store_true",
                        help="List all available factions and exit")

    args = parser.parse_args()

    if args.list_factions:
        print("\nDustfall Factions\n" + "=" * 50)
        for fname, fdata in list_factions().items():
            deity = fdata.get("deity", "None")
            print(f"  {fname:<12}  deity:{deity:<22} {fdata['tone']}")
        print()
        return

    # Seed handling
    shared_seed = args.seed
    map_seed = args.map_seed or shared_seed
    enc_seed = args.encounter_seed or shared_seed

    # Generate map
    try:
        m = generate_map(args.map_type, seed=map_seed, size=tuple(args.size))
    except ValueError as e:
        print(f"Error: {e}")
        return

    # Generate encounter
    enc = generate_encounter(m, player_level=args.level, faction=args.faction, seed=enc_seed)

    # Display summary
    print(enc.to_summary())

    if args.preview:
        print()
        print(m.to_ascii())

    if args.export:
        export_path = Path(args.export)
        data = enc.to_json()
        export_path.write_text(json.dumps(data, indent=2))
        print(f"\nExported to: {export_path.resolve()}")


if __name__ == "__main__":
    _cli_main()
