"""
Dustfall Lore Engine — CLI
A game master tool for generating Dustfall world lore.

Usage:
  python cli.py town                              # generate a random town
  python cli.py town --deity Vulcan               # generate a Vulcan-influenced town
  python cli.py town --deity "Baron Samedi" --region "The Boneyard"
  python cli.py town --list                       # list all generated towns

  python cli.py quest                             # generate a random quest
  python cli.py quest --city "Rustwater"          # quest in a specific city
  python cli.py quest --archetype Gunslinger      # quest for a specific archetype
  python cli.py quest --deity Coyote              # quest with Coyote involvement
  python cli.py quest --list                      # list all generated quests

  python cli.py item                              # generate a random item
  python cli.py item weapon                       # generate a weapon
  python cli.py item artifact --deity Anansi      # Anansi-touched artifact
  python cli.py item consumable --rarity Rare     # rare consumable
  python cli.py item --list                       # list all generated items

  python cli.py enemy                             # generate a random enemy
  python cli.py enemy --faction Harrowed          # Harrowed enemy
  python cli.py enemy --tier 2                    # veteran-tier enemy
  python cli.py enemy --tier 3                    # boss enemy
  python cli.py enemy --list                      # list all generated enemies

  python cli.py stats                             # lore database stats
  python cli.py export towns                      # export all towns as Markdown
  python cli.py export quests --out quests.md     # export quests to file
"""

import argparse
import json
import sys
from pathlib import Path

# Ensure project root on path
sys.path.insert(0, str(Path(__file__).parent))

from lore_engine import LoreEngine, DEITIES, ARCHETYPES, ENEMY_FACTIONS, ITEM_TYPES_ALL, REGIONS, to_markdown


def _print_town(t: dict):
    print(f"\n{'='*60}")
    print(f"  TOWN: {t.get('name', '???').upper()}")
    print(f"{'='*60}")
    print(f"  Region:     {t.get('region', '')}")
    print(f"  Deity:      {t.get('deity', 'None')}")
    print(f"  Population: {t.get('population', '')}")
    print(f"  Mood:       {t.get('mood', '')}")
    print()
    print(f"  {t.get('description', '')}")
    print()
    print(f"  HISTORY: {t.get('history', '')}")
    print()
    npcs = t.get("npcs", [])
    if npcs:
        print("  NOTABLE NPCs:")
        for npc in npcs:
            print(f"    • {npc.get('name')} ({npc.get('archetype', '?')}): {npc.get('description', '')}")
    secrets = t.get("secrets", [])
    if secrets:
        print("\n  SECRETS:")
        for s in secrets:
            print(f"    • {s}")
    if t.get("rumor"):
        print(f"\n  RUMOR IN THE SALOON: {t['rumor']}")
    print()


def _print_quest(q: dict):
    print(f"\n{'='*60}")
    print(f"  QUEST: {q.get('title', '???').upper()}")
    print(f"{'='*60}")
    print(f"  Type:       {q.get('quest_type', '')}")
    print(f"  Location:   {q.get('city', '')}")
    print(f"  Deity:      {q.get('deity', 'None')}")
    print(f"  Archetype:  {q.get('archetype', 'Any')}")
    print()
    print(f"  HOOK: {q.get('hook', '')}")
    print()
    print(f"  BACKGROUND: {q.get('background', '')}")
    objectives = q.get("objectives", [])
    if objectives:
        print("\n  OBJECTIVES:")
        for o in objectives:
            print(f"    • {o}")
    complications = q.get("complications", [])
    if complications:
        print("\n  COMPLICATIONS:")
        for c in complications:
            print(f"    • {c}")
    if q.get("twist"):
        print(f"\n  THE TWIST: {q['twist']}")
    if q.get("reward"):
        print(f"\n  REWARD: {q['reward']}")
    if q.get("divine_consequence"):
        print(f"\n  DIVINE CONSEQUENCE: {q['divine_consequence']}")
    print()


def _print_item(item: dict):
    print(f"\n{'='*60}")
    print(f"  ITEM: {item.get('name', '???').upper()}")
    print(f"{'='*60}")
    print(f"  Type:    {item.get('item_type', '').title()}")
    print(f"  Deity:   {item.get('deity', 'None')}")
    print(f"  Rarity:  {item.get('rarity', '')}")
    print()
    if item.get("flavor_text"):
        print(f"  \"{item['flavor_text']}\"")
        print()
    print(f"  DESCRIPTION: {item.get('description', '')}")
    stats = item.get("stats", {})
    if stats:
        print("\n  STATS:")
        for k, v in stats.items():
            if v:
                print(f"    {k.replace('_', ' ').title()}: {v}")
    if item.get("lore_detail"):
        print(f"\n  LORE: {item['lore_detail']}")
    if item.get("corruption_effect"):
        print(f"\n  CORRUPTION: {item['corruption_effect']}")
    if item.get("acquisition"):
        print(f"\n  ACQUISITION: {item['acquisition']}")
    print()


def _print_enemy(e: dict):
    print(f"\n{'='*60}")
    print(f"  ENEMY: {e.get('name', '???').upper()}")
    print(f"{'='*60}")
    print(f"  Faction: {e.get('faction', '')}  |  Tier: {e.get('tier', 1)}  |  HP: {e.get('hp', '?')}  |  Speed: {e.get('speed', '?')}")
    print()
    if e.get("appearance"):
        print(f"  APPEARANCE: {e['appearance']}")
    if e.get("backstory"):
        print(f"\n  BACKSTORY: {e['backstory']}")
    if e.get("motivation"):
        print(f"\n  MOTIVATION: {e['motivation']}")
    weaknesses = e.get("weaknesses", [])
    if weaknesses:
        print("\n  WEAKNESSES:")
        for w in weaknesses:
            print(f"    • {w}")
    connections = e.get("world_connections", [])
    if connections:
        print("\n  WORLD CONNECTIONS:")
        for c in connections:
            print(f"    • {c}")
    if e.get("combat_behavior"):
        print(f"\n  COMBAT: {e['combat_behavior']}")
    if e.get("field_notes"):
        print(f"\n  FIELD NOTES: \"{e['field_notes']}\"")
    if e.get("loot"):
        print(f"\n  LOOT: {', '.join(e['loot'])}")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Dustfall Lore Engine — generate consistent world lore",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Deities: Vulcan, Perun, Baron Samedi, Coyote, Anansi, The Sleeping One
Archetypes: Gunslinger, Hexslinger, Tinkerer, Preacher, Law Dog, Drifter
Factions: Harrowed, Forgeworks Syndicate, Dust Walkers, The Regulators, Los Tejedores, The Hollow Court
Item types: weapon, artifact, consumable, armor, trinket
        """,
    )

    subparsers = parser.add_subparsers(dest="command")

    # ---- town ----
    town_p = subparsers.add_parser("town", help="Generate or list towns")
    town_p.add_argument("--deity", help="Deity influence (e.g. Vulcan, Perun)")
    town_p.add_argument("--region", help="Region (e.g. 'The Forgeworks')")
    town_p.add_argument("--list", action="store_true", help="List generated towns")
    town_p.add_argument("--json", action="store_true", help="Output as JSON")
    town_p.add_argument("--markdown", action="store_true", help="Output as Markdown")
    town_p.add_argument("--out", help="Write output to file")

    # ---- quest ----
    quest_p = subparsers.add_parser("quest", help="Generate or list quests")
    quest_p.add_argument("--city", help="City for the quest")
    quest_p.add_argument("--archetype", help="Target archetype")
    quest_p.add_argument("--deity", help="Deity involvement")
    quest_p.add_argument("--list", action="store_true", help="List generated quests")
    quest_p.add_argument("--json", action="store_true", help="Output as JSON")
    quest_p.add_argument("--markdown", action="store_true", help="Output as Markdown")
    quest_p.add_argument("--out", help="Write output to file")

    # ---- item ----
    item_p = subparsers.add_parser("item", help="Generate or list items")
    item_p.add_argument("type", nargs="?", default="weapon", choices=ITEM_TYPES_ALL, help="Item type")
    item_p.add_argument("--deity", help="Deity alignment")
    item_p.add_argument("--rarity", choices=["Common", "Uncommon", "Rare", "Legendary"])
    item_p.add_argument("--list", action="store_true", help="List generated items")
    item_p.add_argument("--json", action="store_true", help="Output as JSON")
    item_p.add_argument("--markdown", action="store_true", help="Output as Markdown")
    item_p.add_argument("--out", help="Write output to file")

    # ---- enemy ----
    enemy_p = subparsers.add_parser("enemy", help="Generate or list enemies")
    enemy_p.add_argument("--faction", choices=list(ENEMY_FACTIONS.keys()), help="Enemy faction")
    enemy_p.add_argument("--tier", type=int, choices=[1, 2, 3], default=1, help="Enemy tier (1=common, 2=veteran, 3=boss)")
    enemy_p.add_argument("--list", action="store_true", help="List generated enemies")
    enemy_p.add_argument("--json", action="store_true", help="Output as JSON")
    enemy_p.add_argument("--markdown", action="store_true", help="Output as Markdown")
    enemy_p.add_argument("--out", help="Write output to file")

    # ---- stats ----
    subparsers.add_parser("stats", help="Show lore database stats")

    # ---- export ----
    export_p = subparsers.add_parser("export", help="Export lore to Markdown")
    export_p.add_argument("kind", choices=["towns", "quests", "items", "enemies"], help="What to export")
    export_p.add_argument("--out", help="Output file path")
    export_p.add_argument("--limit", type=int, default=50)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    engine = LoreEngine()

    # ---- TOWN ----
    if args.command == "town":
        if args.list:
            towns = engine.list_towns(limit=30)
            print(f"\n{len(towns)} towns in the Ashlands:\n")
            for t in towns:
                print(f"  • {t.get('name')} ({t.get('region', '?')}) — {t.get('deity', 'No deity')}")
            return

        data = engine.generate_town(deity=args.deity, region=args.region)
        output = _format_output(data, "town", args)
        if output:
            _write_output(output, args.out)
        else:
            _print_town(data)

    # ---- QUEST ----
    elif args.command == "quest":
        if args.list:
            quests = engine.list_quests(city=args.city, limit=30)
            print(f"\n{len(quests)} quests on record:\n")
            for q in quests:
                print(f"  • {q.get('title')} [{q.get('quest_type', '?')}] in {q.get('city', '?')}")
            return

        data = engine.generate_quest(city=args.city, archetype=args.archetype, deity=args.deity)
        output = _format_output(data, "quest", args)
        if output:
            _write_output(output, args.out)
        else:
            _print_quest(data)

    # ---- ITEM ----
    elif args.command == "item":
        if args.list:
            items = engine.list_items(item_type=args.type, limit=30)
            itype = f" ({args.type})" if args.type != "weapon" or hasattr(args, "type") else ""
            print(f"\n{len(items)} items in the armory{itype}:\n")
            for i in items:
                print(f"  • {i.get('name')} [{i.get('rarity', '?')}] — {i.get('deity', 'no deity')}")
            return

        data = engine.generate_item(item_type=args.type, deity=args.deity, rarity=args.rarity)
        output = _format_output(data, "item", args)
        if output:
            _write_output(output, args.out)
        else:
            _print_item(data)

    # ---- ENEMY ----
    elif args.command == "enemy":
        if args.list:
            enemies = engine.list_enemies(faction=args.faction, limit=30)
            print(f"\n{len(enemies)} enemies in the bestiary:\n")
            for e in enemies:
                print(f"  • {e.get('name')} [T{e.get('tier', 1)}] — {e.get('faction', '?')}")
            return

        data = engine.generate_enemy(faction=args.faction, tier=args.tier)
        output = _format_output(data, "enemy", args)
        if output:
            _write_output(output, args.out)
        else:
            _print_enemy(data)

    # ---- STATS ----
    elif args.command == "stats":
        stats = engine.stats()
        print("\n  Dustfall Lore Database\n  " + "="*30)
        for k, v in stats.items():
            print(f"  {k.title()}: {v}")
        print()

    # ---- EXPORT ----
    elif args.command == "export":
        md = engine.export_markdown(args.kind, limit=args.limit)
        if args.out:
            Path(args.out).write_text(md, encoding="utf-8")
            print(f"Exported {args.kind} to {args.out}")
        else:
            print(md)


def _format_output(data: dict, kind: str, args) -> Optional[str]:
    """Return formatted output string if --json or --markdown was requested, else None."""
    if hasattr(args, "json") and args.json:
        return json.dumps(data, indent=2)
    if hasattr(args, "markdown") and args.markdown:
        return to_markdown(data, kind)
    return None


def _write_output(text: str, out_path: Optional[str]):
    if out_path:
        Path(out_path).write_text(text, encoding="utf-8")
        print(f"Written to {out_path}")
    else:
        print(text)


if __name__ == "__main__":
    main()
