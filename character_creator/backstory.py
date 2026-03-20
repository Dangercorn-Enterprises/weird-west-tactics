"""
backstory.py — Dustfall Procedural Backstory Generator

Combines faction, archetype, origin town (from lore engine if available),
defining events, and secrets to produce a 2-3 paragraph backstory and
a character motivation.
"""

import random
import sys
from pathlib import Path

# Try to pull towns from the lore engine
_LORE_TOWNS_CACHE = None

def _get_lore_towns() -> list[str]:
    global _LORE_TOWNS_CACHE
    if _LORE_TOWNS_CACHE is not None:
        return _LORE_TOWNS_CACHE
    try:
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from lore_engine import LoreDB
        db = LoreDB()
        towns = db.get_town_names()
        _LORE_TOWNS_CACHE = towns if towns else _FALLBACK_TOWNS
    except Exception:
        _LORE_TOWNS_CACHE = _FALLBACK_TOWNS
    return _LORE_TOWNS_CACHE


_FALLBACK_TOWNS = [
    "Ashfall Crossing", "Rustwater", "Copper Springs", "Gallows Hill",
    "Ironblood Flats", "The Forgeworks", "Boneyard Junction",
    "Deadwater Ridge", "Thunder Mesa", "The Scorch",
    "Grimrock Gulch", "Cracked Hollow", "Dusty Crossroads",
    "Thunderheart", "Iron Pass",
]

DEFINING_EVENTS = [
    {
        "key": "fire",
        "text": "Your town burned. Not an accident — someone set it, for reasons you've spent years trying to understand. You got out. Most didn't.",
        "wound": "trust",
    },
    {
        "key": "betrayal",
        "text": "Someone you trusted sold you out to a faction with deep pockets and deeper grudges. You found out. They didn't like that.",
        "wound": "loyalty",
    },
    {
        "key": "divine_encounter",
        "text": "A god spoke to you directly — not a vision, not a fever dream. An actual conversation. You've never told anyone what was said.",
        "wound": "faith",
    },
    {
        "key": "ashfall_exposure",
        "text": "You spent too long near an Ashfall deposit — weeks, not hours. The corruption didn't take root, but it left marks. Different ones each month.",
        "wound": "body",
    },
    {
        "key": "war",
        "text": "You fought in the Syndicate Wars. On whatever side, it doesn't matter — the things you saw don't care which flag you were carrying.",
        "wound": "violence",
    },
    {
        "key": "lost_partner",
        "text": "Your partner — riding companion, spouse, business associate — is gone. The circumstances are complicated. You are still responsible.",
        "wound": "guilt",
    },
    {
        "key": "hollow_court",
        "text": "You encountered a Herald of the Sleeping One and lived. The encounter left you with knowledge you cannot unknow.",
        "wound": "sanity",
    },
    {
        "key": "wrong_side",
        "text": "You worked for the wrong faction. Did their dirty work. When you found out the full picture, you walked. They haven't forgotten.",
        "wound": "identity",
    },
    {
        "key": "miracle",
        "text": "You should have died — by all rights, you did die, briefly. Whatever brought you back didn't leave a note.",
        "wound": "mortality",
    },
    {
        "key": "discovery",
        "text": "You found something buried in the frontier that was not meant to be found. You can't unfind it, and you can't destroy it.",
        "wound": "knowledge",
    },
]

SECRETS = [
    "You are wanted under a different name in at least one territory. The crime was real. The circumstances were complicated.",
    "You have made a bargain with a divine entity — a small one, you told yourself. The terms are becoming clearer.",
    "Someone you love is working for the other side. You haven't decided what to do about it.",
    "You know where an Ashfall deposit is that no one else knows about. You haven't decided what to do about it either.",
    "The defining event you tell people about isn't true. The real one is worse.",
]

MOTIVATIONS = {
    "revenge": {
        "label": "Revenge",
        "description": "Someone specific wronged you — burned your home, killed your people, stole your name. You are going to find them.",
        "drives": "Every choice filters through one question: does this get me closer?",
    },
    "treasure": {
        "label": "Treasure",
        "description": "Not just money — something specific. A ledger. A device. A piece of land. Something worth crossing the worst country alive for.",
        "drives": "You're willing to take jobs you don't like, work with people you hate, if it builds toward the thing you're chasing.",
    },
    "redemption": {
        "label": "Redemption",
        "description": "You did something. You're not going to explain it here. You're trying to balance the ledger.",
        "drives": "You help people who can't help themselves. Not because it always works. Because you owe.",
    },
    "duty": {
        "label": "Duty",
        "description": "You serve something larger — a faction, a promise, a dead person's wishes. The obligation is real whether or not it's acknowledged.",
        "drives": "You keep going because stopping would mean the thing you sacrificed everything for didn't matter.",
    },
    "survival": {
        "label": "Survival",
        "description": "Simple. Stay alive. Keep the people you care about alive. Everything else is negotiable.",
        "drives": "You make pragmatic choices. You're not cruel — you just know what things cost.",
    },
}

MOTIVATION_KEYS = list(MOTIVATIONS.keys())

# Faction-specific backstory openers
FACTION_OPENERS = {
    "Dustfolk": [
        "You were born on the frontier, and you'll probably die on it — you've made your peace with that.",
        "There's no record of you anywhere. No ledger, no deed, no registry. You like it that way.",
        "You've moved camp seventeen times in the last decade. Home is wherever the bedroll lands.",
    ],
    "Ironclad": [
        "The Syndicate gave you work when no one else would. You're still not sure if that's debt or leverage.",
        "You believe in the work — the machines, the progress, the power Ashfall makes possible. The cost is... complicated.",
        "Vulcan's mark is on everything you touch. Not literally. Not yet.",
    ],
    "Uncanny": [
        "The first time the Weird touched you, you thought you were losing your mind. Now you know better.",
        "The gods are real. You've met at least one. 'Meeting' is a generous word for what happened.",
        "Power comes from somewhere. You stopped asking where after the answer got too specific.",
    ],
    "Void": [
        "Most people feel it as a distant unease — the deep earth breathing. You hear words.",
        "You're not trying to end the world. You're trying to understand what comes after.",
        "The Sleeping One doesn't demand worship. It demands acknowledgment. You've given that. The rest followed.",
    ],
}

# Archetype-specific backstory beats
ARCHETYPE_BEATS = {
    "Gunslinger": "Your hands have always known what to do — the calculation, the angle, the timing. You didn't choose the gun. It chose you, early.",
    "Scout": "You learned to read the frontier before you could read a book. The dust tells you things people don't.",
    "Medic": "You've had your hands in wounds that shouldn't be survivable. You've saved people you shouldn't have been able to save. You've lost people you should have.",
    "Mechwright": "You understand machines the way other people understand animals — their moods, their limits, what they're trying to tell you when they start making that sound.",
    "Hex-Slinger": "The gun and the hex developed together, each making the other stranger. You've stopped trying to separate them.",
    "Outlaw": "The law decided what you were before you had a say in it. You've been operating accordingly ever since.",
    "Lawdog": "Someone has to hold the line. You've decided that someone is you, and you've been paying the price for that decision in the currency of lost sleep.",
    "Wanderer": "The road is the only thing that's been constant. You've stopped calling it running away. You've started calling it looking.",
}


def generate_backstory(
    name: str,
    faction: str,
    archetype: str,
    origin_town: str | None = None,
    event_key: str | None = None,
    secret_index: int | None = None,
    motivation_key: str | None = None,
) -> dict:
    """
    Generate a full backstory for a character.
    Returns dict with: backstory (str), motivation (dict), event (dict),
    secret (str), origin_town (str).
    """

    # Pull towns from lore engine or fallback
    towns = _get_lore_towns()
    town = origin_town or random.choice(towns)

    # Pick event
    event = next(
        (e for e in DEFINING_EVENTS if e["key"] == event_key), None
    ) or random.choice(DEFINING_EVENTS)

    # Pick secret
    idx = secret_index if (secret_index is not None and 0 <= secret_index < len(SECRETS)) else random.randint(0, len(SECRETS) - 1)
    secret = SECRETS[idx]

    # Pick motivation
    motivation = MOTIVATIONS.get(motivation_key) or random.choice(list(MOTIVATIONS.values()))

    # Build backstory text
    opener_pool = FACTION_OPENERS.get(faction, FACTION_OPENERS["Dustfolk"])
    opener = random.choice(opener_pool)
    beat = ARCHETYPE_BEATS.get(archetype, "You came to the frontier looking for something. You're still looking.")

    para1 = f"{opener} You came out of {town} — or what's left of it. {beat}"

    para2 = f"{event['text']} That was the line. Before that, you had a life. After it, you had a direction."

    para3 = (
        f"Now you move through the frontier with a purpose that most people can't read in your face. "
        f"{motivation['drives']} "
        f"You don't explain yourself. People who need the explanation wouldn't understand it anyway."
    )

    backstory_text = f"{para1}\n\n{para2}\n\n{para3}"

    return {
        "origin_town": town,
        "event": event,
        "secret": secret,
        "motivation": motivation,
        "backstory": backstory_text,
    }


def get_all_events() -> list[dict]:
    return DEFINING_EVENTS


def get_all_secrets() -> list[str]:
    return SECRETS


def get_all_motivations() -> dict:
    return MOTIVATIONS
