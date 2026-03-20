"""
creator.py — Dustfall Character Generator

Handles character creation logic:
- Factions (aligned with lore_engine.py world)
- Archetypes with starting gear
- Point-buy stat system (20 points, max 6 per stat)
- Traits (2 per character)
- Faction-based modifiers
"""

import json
import random

# ------------------------------------------------------------------ #
# World constants — aligned with lore_engine.py                      #
# ------------------------------------------------------------------ #

FACTIONS = {
    "Dustfolk": {
        "description": "Survivors, drifters, and settlers scraping a life from the ashen frontier. No divine patron — just grit and mutual need.",
        "deity": None,
        "territory": "The Flats, Rustwater, Copper Springs",
        "color": "#c8a96e",
        "accent": "#8b6914",
        "tone": "desperate but human",
        "stat_bonus": {"grit": 1},
        "flavor": "You've buried more friends than you can count. You stopped naming the graves after the third year.",
        "emblem": "◈",
    },
    "Ironclad": {
        "description": "The industrial arm of the Forgeworks Syndicate. Vulcan's chosen. They believe progress justifies everything — and they're winning.",
        "deity": "Vulcan",
        "territory": "The Forgeworks, Iron Pass",
        "color": "#7a6b3a",
        "accent": "#39ff14",
        "tone": "industrial, merciless",
        "stat_bonus": {"wrench": 1},
        "flavor": "The Ashfall doesn't burn you anymore. You're not sure what that means, and you've learned not to ask.",
        "emblem": "⚙",
    },
    "Uncanny": {
        "description": "Those touched by the weird — Coyote's tricksters, Baron Samedi's walkers, hexslingers and hedge witches. Power has a price.",
        "deity": "Multiple (Coyote, Baron Samedi, Anansi)",
        "territory": "The Boneyard, Trickster's Maze",
        "color": "#5a2d6e",
        "accent": "#cc44ff",
        "tone": "mercurial, dangerous",
        "stat_bonus": {"ghost": 1},
        "flavor": "The gods spoke to you once. You said yes before you heard the full terms. You're still paying.",
        "emblem": "⟁",
    },
    "Void": {
        "description": "Servants of The Sleeping One. They don't worship annihilation — they've seen what lies beneath and believe it's mercy.",
        "deity": "The Sleeping One",
        "territory": "The Scorch, The Deep Rift",
        "color": "#1a1a2e",
        "accent": "#4a4a8a",
        "tone": "cold, inevitable",
        "stat_bonus": {"iron": 1},
        "flavor": "You've heard the earth breathe. Once you hear it, you understand. The others just haven't listened yet.",
        "emblem": "⊗",
    },
}

ARCHETYPES = {
    "Gunslinger": {
        "description": "Born to the gun. Fastest draw west of the Rift. Iron nerves, quick hands, and enough confidence to bluff death itself.",
        "stat_priority": ["iron", "trail"],
        "starting_gear": [
            {"name": "Colt Peacemaker", "type": "weapon", "notes": "Revolver. Reliable as the grave."},
            {"name": "Winchester '73", "type": "weapon", "notes": "Rifle. Good for when they're far enough to think they're safe."},
            {"name": "Gun Belt (worn)", "type": "gear", "notes": "+1 draw speed. Holster's been resoled twice."},
        ],
        "flavor": "You don't look for fights. They find you, and you end them.",
        "emblem": "🔫",
    },
    "Scout": {
        "description": "Eyes forward, mouth shut. The frontier holds no secrets from someone who knows how to read dust and shadow.",
        "stat_priority": ["trail", "ghost"],
        "starting_gear": [
            {"name": "Hunting Bow", "type": "weapon", "notes": "Silent. Good for when sound gets you killed."},
            {"name": "Skinning Knife", "type": "weapon", "notes": "Close work. Don't let it come to that."},
            {"name": "Trail Pack", "type": "gear", "notes": "3 days rations. Rope. Compass that points mostly north."},
        ],
        "flavor": "You've tracked things that didn't want to be found. Some of them weren't human when you caught up.",
        "emblem": "👁",
    },
    "Medic": {
        "description": "Keeps the crew breathing long enough to make more bad decisions. Seen too much to be squeamish. Not seen enough to stop caring.",
        "stat_priority": ["grit", "tongue"],
        "starting_gear": [
            {"name": "Field Medkit", "type": "gear", "notes": "3 uses. Stops bleeding, sets bones, doesn't ask questions."},
            {"name": "Bone Saw", "type": "weapon", "notes": "Medical tool. Also a weapon if the day calls for it."},
            {"name": "Morphine Vials (x3)", "type": "consumable", "notes": "Removes one Wound condition. Habit-forming."},
        ],
        "flavor": "You've learned where the body breaks easiest. You use that knowledge to fix people. Usually.",
        "emblem": "✚",
    },
    "Mechwright": {
        "description": "Vulcan's children in spirit if not in faith. They build the impossible from salvage and spite. Ashfall is just fuel with a personality.",
        "stat_priority": ["wrench", "iron"],
        "starting_gear": [
            {"name": "Mechwright's Toolkit", "type": "gear", "notes": "Can repair, build, or disassemble almost anything given time."},
            {"name": "Prototype Device", "type": "weapon", "notes": "Unique to this character. Choose: steam lance / proximity mine / grapple cannon."},
            {"name": "Ashfall Shard (small)", "type": "consumable", "notes": "Power source. Glows blue-green. Hisses when cold."},
        ],
        "flavor": "The machine doesn't lie. The machine doesn't betray you. The machine does exactly what you built it to do.",
        "emblem": "⚙",
    },
    "Hex-Slinger": {
        "description": "Draws power from the divine crossroads — part gunfighter, part witch. The gods notice. Not all of them approve.",
        "stat_priority": ["ghost", "iron"],
        "starting_gear": [
            {"name": "Hex-Marked Revolver", "type": "weapon", "notes": "Chambers glow when divine energy is near. Shoots true against the unnatural."},
            {"name": "Bone Charm (worn)", "type": "trinket", "notes": "+1 Ghost. Warm when danger is close. Sometimes warm for no reason."},
            {"name": "Hex Components (x5)", "type": "consumable", "notes": "Chalk, iron filings, grave dirt. The raw material of minor workings."},
        ],
        "flavor": "The gods don't give you power for free. You're still figuring out the invoice.",
        "emblem": "⟁",
    },
    "Outlaw": {
        "description": "Wanted in three territories. The law says you're dangerous. They're right. They just don't know the half of it.",
        "stat_priority": ["iron", "ghost"],
        "starting_gear": [
            {"name": "Sawed-Off Shotgun", "type": "weapon", "notes": "Short range. Very convincing argument."},
            {"name": "Wanted Poster (self)", "type": "trinket", "notes": "The price on your head. Reminder of reputation."},
            {"name": "Outlaw's Duster", "type": "gear", "notes": "Hides the hardware. Low cover bonus. Lots of pockets."},
        ],
        "flavor": "Every door you walk through, someone reaches for iron. You've learned to reach first.",
        "emblem": "⚡",
    },
    "Lawdog": {
        "description": "Badge or no badge, you stand for something. Order. Justice. The law as it should be, not as the powerful want it.",
        "stat_priority": ["iron", "tongue"],
        "starting_gear": [
            {"name": "Marshal's Revolver", "type": "weapon", "notes": "Sanctioned by Perun's Regulators. Blessed against chaos-aligned enemies."},
            {"name": "Deputy's Badge", "type": "trinket", "notes": "Opens doors. Also closes them."},
            {"name": "Manacles (x2)", "type": "gear", "notes": "For taking them alive. Not always an option."},
        ],
        "flavor": "You've seen what happens when there's no law. You've decided that's not acceptable.",
        "emblem": "⭐",
    },
    "Wanderer": {
        "description": "No home. No faction. No allegiance but the road. The frontier is wide, and you intend to see all of it — or die trying.",
        "stat_priority": ["trail", "tongue"],
        "starting_gear": [
            {"name": "Battered Revolver", "type": "weapon", "notes": "Old. Reliable. Has a name you don't share."},
            {"name": "Traveler's Pack", "type": "gear", "notes": "Everything you own. Surprisingly not that much."},
            {"name": "Road Journals (x3)", "type": "trinket", "notes": "Maps, notes, names. The ones you can't forget."},
        ],
        "flavor": "You've been everywhere worth going. Now you're heading toward the places that aren't.",
        "emblem": "◎",
    },
}

STATS = {
    "grit": {
        "label": "Grit",
        "description": "Health, endurance, stubbornness. How much damage you can take before you fall.",
        "color": "#e05252",
        "icon": "♥",
    },
    "iron": {
        "label": "Iron",
        "description": "Combat ability. Accuracy, weapon handling, battlefield instinct.",
        "color": "#c0c0c0",
        "icon": "⚔",
    },
    "ghost": {
        "label": "Ghost",
        "description": "Stealth, perception, mystical sensitivity. Moving unseen and sensing what others miss.",
        "color": "#8888cc",
        "icon": "◈",
    },
    "tongue": {
        "label": "Tongue",
        "description": "Persuasion, deception, reading people. Getting what you want through words.",
        "color": "#cc8844",
        "icon": "◉",
    },
    "wrench": {
        "label": "Wrench",
        "description": "Technical skill, repair, improvisation. Making broken things work and working things break.",
        "color": "#44aacc",
        "icon": "⚙",
    },
    "trail": {
        "label": "Trail",
        "description": "Navigation, tracking, survival. Reading the land, finding paths, staying alive outside.",
        "color": "#88aa44",
        "icon": "◎",
    },
}

STAT_KEYS = list(STATS.keys())
STAT_POINT_POOL = 20
STAT_MAX = 6
STAT_MIN = 1

TRAITS = {
    "Dead Eye": {
        "description": "Bonus accuracy on aimed shots. Still costs the action.",
        "effect": "+2 Iron when spending an action to aim before shooting.",
        "faction_synergy": None,
        "archetype_synergy": ["Gunslinger", "Scout"],
        "cost": 1,
    },
    "Pack Mule": {
        "description": "Carries more than should be physically possible. Nobody asks how.",
        "effect": "+3 carry capacity. Can dual-wield two-handed weapons (once per session).",
        "faction_synergy": "Dustfolk",
        "archetype_synergy": ["Wanderer", "Medic"],
        "cost": 1,
    },
    "Hex-Touched": {
        "description": "Divine energy leaks through at inconvenient moments.",
        "effect": "Once per session: random magical effect. Equally likely to help or cause problems.",
        "faction_synergy": "Uncanny",
        "archetype_synergy": ["Hex-Slinger"],
        "cost": 1,
    },
    "Grudge": {
        "description": "You hold onto things. Specifically: everything that's ever wronged you.",
        "effect": "+2 Iron against a chosen faction. That faction knows your name.",
        "faction_synergy": None,
        "archetype_synergy": ["Outlaw", "Lawdog"],
        "cost": 1,
    },
    "Silver Tongue": {
        "description": "You can talk your way out of things that shouldn't be survivable through talking.",
        "effect": "+2 Tongue checks. Once per session: treat a failed persuasion as a success.",
        "faction_synergy": None,
        "archetype_synergy": ["Wanderer", "Lawdog"],
        "cost": 1,
    },
    "Iron Constitution": {
        "description": "Ashfall poisoning, disease, rough weather — your body refuses to acknowledge the problem.",
        "effect": "+2 Grit vs environmental hazards. Immune to Ashfall sickness (but not corruption).",
        "faction_synergy": "Ironclad",
        "archetype_synergy": ["Medic", "Mechwright"],
        "cost": 1,
    },
    "Ghost Step": {
        "description": "You move through spaces like you're not entirely there. Sometimes you're not.",
        "effect": "+2 Ghost for movement. Can move through difficult terrain without penalty.",
        "faction_synergy": "Uncanny",
        "archetype_synergy": ["Scout", "Outlaw"],
        "cost": 1,
    },
    "Jury Rig": {
        "description": "Improvisation is an art form. You've elevated it.",
        "effect": "+2 Wrench for emergency repairs. Can fix things without proper tools, once per encounter.",
        "faction_synergy": "Ironclad",
        "archetype_synergy": ["Mechwright"],
        "cost": 1,
    },
    "Old Road": {
        "description": "You know every trail, shortcut, and hidey-hole the frontier has to offer.",
        "effect": "+2 Trail checks. Party never gets lost. You always know the nearest water.",
        "faction_synergy": "Dustfolk",
        "archetype_synergy": ["Scout", "Wanderer"],
        "cost": 1,
    },
    "Blood Price": {
        "description": "You've made bargains with things that keep ledgers. The balance is always due.",
        "effect": "+3 to any stat check (player choice) once per session. Each use adds a secret consequence.",
        "faction_synergy": "Void",
        "archetype_synergy": ["Hex-Slinger"],
        "cost": 1,
    },
    "Steady Hand": {
        "description": "Surgeons and gunslingers both need this. You've got it.",
        "effect": "Ignore penalty for shooting into melee. Medical checks do not provoke attacks.",
        "faction_synergy": None,
        "archetype_synergy": ["Gunslinger", "Medic"],
        "cost": 1,
    },
    "Void-Scarred": {
        "description": "You've looked into the deep earth. It looked back. You're still standing.",
        "effect": "+2 Ghost vs Void/Hollow Court enemies. Sense proximity of Void energy (no roll).",
        "faction_synergy": "Void",
        "archetype_synergy": ["Hex-Slinger", "Wanderer"],
        "cost": 1,
    },
}

TRAIT_KEYS = list(TRAITS.keys())

APPEARANCES = {
    "eyes": [
        "weathered grey", "pale blue (almost white)", "dark brown, sharp",
        "one brown one green", "pale green, watchful", "amber, unsettling",
        "black — no visible iris", "bloodshot, never fully closed"
    ],
    "build": [
        "lean and wire-tough", "broad-shouldered, deliberate",
        "slight — easy to underestimate", "compact and low to the ground",
        "tall with a permanent stoop", "heavyset, still fast",
    ],
    "marks": [
        "Ashfall burn scar on the left hand",
        "a brand on the neck — someone else's mark",
        "three parallel claw marks across the collarbone",
        "missing the tip of the right index finger",
        "no visible scars (somehow)",
        "tattoo in a language nobody local speaks",
        "grey streak through the hair — happened overnight, never explained",
        "left ear partially gone — old knife work",
    ],
    "dress": [
        "dust-caked trail coat, practical pockets",
        "Forgeworks-issue vest (stolen or earned — unclear)",
        "black duster with a Void-touched lining",
        "frontier finery — once nice, now just tough",
        "working clothes, everything functional, nothing decorative",
        "travel-worn pieces from three different territories",
    ],
}


def generate_character(name: str, faction: str, archetype: str,
                        stats: dict, traits: list[str],
                        appearance: dict | None = None) -> dict:
    """
    Validate and assemble a character dict.
    Returns the character dict or raises ValueError on invalid input.
    """
    if faction not in FACTIONS:
        raise ValueError(f"Unknown faction: {faction}")
    if archetype not in ARCHETYPES:
        raise ValueError(f"Unknown archetype: {archetype}")

    # Validate stats
    for k in STAT_KEYS:
        if k not in stats:
            raise ValueError(f"Missing stat: {k}")
        if not (STAT_MIN <= stats[k] <= STAT_MAX):
            raise ValueError(f"Stat {k}={stats[k]} out of range ({STAT_MIN}-{STAT_MAX})")
    total = sum(stats[k] for k in STAT_KEYS)
    # Apply faction bonus before checking — faction bonus is applied post-buy
    if total != STAT_POINT_POOL:
        raise ValueError(f"Stats total {total}, expected {STAT_POINT_POOL}")

    # Validate traits
    if len(traits) != 2:
        raise ValueError("Must select exactly 2 traits")
    for t in traits:
        if t not in TRAITS:
            raise ValueError(f"Unknown trait: {t}")

    # Apply faction stat bonus
    faction_bonus = FACTIONS[faction].get("stat_bonus", {})
    final_stats = dict(stats)
    for stat, bonus in faction_bonus.items():
        final_stats[stat] = min(final_stats[stat] + bonus, STAT_MAX + 1)  # Faction bonus can exceed cap

    # Build character
    archetype_data = ARCHETYPES[archetype]
    faction_data = FACTIONS[faction]

    character = {
        "name": name,
        "faction": faction,
        "archetype": archetype,
        "stats": final_stats,
        "base_stats": stats,  # Pre-faction-bonus
        "traits": traits,
        "gear": archetype_data["starting_gear"],
        "appearance": appearance or _random_appearance(),
        "derived": {
            "max_hp": 10 + (final_stats["grit"] * 2),
            "initiative": final_stats["iron"] + final_stats["ghost"],
            "carry_cap": 6 + final_stats["grit"],
            "wounds_max": 3,
        },
        "faction_flavor": faction_data["flavor"],
        "archetype_flavor": archetype_data["flavor"],
    }

    return character


def _random_appearance() -> dict:
    return {
        "eyes": random.choice(APPEARANCES["eyes"]),
        "build": random.choice(APPEARANCES["build"]),
        "marks": random.choice(APPEARANCES["marks"]),
        "dress": random.choice(APPEARANCES["dress"]),
    }


def random_appearance() -> dict:
    return _random_appearance()


def validate_stats(stats: dict) -> tuple[bool, str]:
    """Returns (valid, error_message). error_message is '' on success."""
    total = 0
    for k in STAT_KEYS:
        v = stats.get(k, 0)
        if not isinstance(v, int) or v < STAT_MIN or v > STAT_MAX:
            return False, f"{STATS[k]['label']} must be between {STAT_MIN} and {STAT_MAX}"
        total += v
    if total != STAT_POINT_POOL:
        diff = STAT_POINT_POOL - total
        if diff > 0:
            return False, f"{diff} point(s) unspent — distribute all {STAT_POINT_POOL} points"
        else:
            return False, f"{abs(diff)} point(s) over budget — max total is {STAT_POINT_POOL}"
    return True, ""
