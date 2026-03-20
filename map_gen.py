"""
map_gen.py — Dustfall: The Ashen Frontier
Procedural tactical map generator for weird western combat encounters.

Generates grid-based tactical maps for use in the Dustfall combat system.
All maps are seeded for reproducibility and annotated with faction lore
pulled from the lore engine.

Map types:
  ghost_town     — abandoned buildings, saloon, jail, church, open streets
  canyon         — rock formations, narrow passages, high ground, ambush chokepoints
  mine_shaft     — underground tunnels, ore veins, cart tracks, dynamite caches
  desert_outpost — fort-like structure, watchtower, supply buildings
  cursed_ruins   — Weird West weirdness: ritual circles, floating debris, unstable geometry

Usage (library):
  from map_gen import generate_map
  m = generate_map("ghost_town", seed=42)
  print(m.to_ascii())
  print(m.describe())
  m.to_json()  # → dict for game engine

Usage (CLI):
  python map_gen.py --type ghost_town --seed 42 --preview
  python map_gen.py --type canyon --export map.json
  python map_gen.py --list-types
"""

import argparse
import json
import random
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ------------------------------------------------------------------ #
# Tile definitions                                                    #
# ------------------------------------------------------------------ #

# Each tile has:
#   symbol  — single ASCII character for CLI preview
#   passable — whether units can stand here
#   blocks_los — whether this tile blocks line-of-sight
#   cover   — None | "low" | "high" (defense modifier)
#   hazard  — whether stepping here causes damage
TILE_DEFS = {
    "floor":         {"symbol": ".", "passable": True,  "blocks_los": False, "cover": None,   "hazard": False},
    "wall":          {"symbol": "#", "passable": False, "blocks_los": True,  "cover": None,   "hazard": False},
    "cover_low":     {"symbol": "c", "passable": True,  "blocks_los": False, "cover": "low",  "hazard": False},
    "cover_high":    {"symbol": "C", "passable": False, "blocks_los": True,  "cover": "high", "hazard": False},
    "hazard":        {"symbol": "X", "passable": True,  "blocks_los": False, "cover": None,   "hazard": True},
    "spawn_player":  {"symbol": "P", "passable": True,  "blocks_los": False, "cover": None,   "hazard": False},
    "spawn_enemy":   {"symbol": "E", "passable": True,  "blocks_los": False, "cover": None,   "hazard": False},
    "loot":          {"symbol": "$", "passable": True,  "blocks_los": False, "cover": None,   "hazard": False},
    "objective":     {"symbol": "O", "passable": True,  "blocks_los": False, "cover": None,   "hazard": False},
    "door":          {"symbol": "+", "passable": True,  "blocks_los": True,  "cover": "low",  "hazard": False},
    "void":          {"symbol": " ", "passable": False, "blocks_los": False, "cover": None,   "hazard": False},
}

# ASCII display characters (for to_ascii output)
TILE_SYMBOLS = {k: v["symbol"] for k, v in TILE_DEFS.items()}

# ------------------------------------------------------------------ #
# Faction data (mirrors lore_engine constants, self-contained here)  #
# ------------------------------------------------------------------ #

# Map-level faction ownership affects spawn composition and flavor text.
# These align with ENEMY_FACTIONS in lore_engine.py.
MAP_FACTIONS = {
    "Dustfolk":  {
        # Generic settlers, traders, drifters — no divine alignment
        "color": "sun-bleached brown and trail-dust grey",
        "tone": "desperate but human",
        "spawn_flavor": "a cluster of makeshift barricades thrown up in the last hour",
    },
    "Ironclad": {
        # Forgeworks Syndicate — Vulcan's industrial arm
        "deity": "Vulcan",
        "color": "brass and Ashfall green",
        "tone": "industrial, organized, ruthless",
        "spawn_flavor": "a perimeter of steam-vented Ashfall canisters used as forward positions",
    },
    "Uncanny": {
        # The Harrowed — Baron Samedi's undead legion
        "deity": "Baron Samedi",
        "color": "bone white and shadow purple",
        "tone": "wrong in every way — things that move when they shouldn't",
        "spawn_flavor": "a ritual circle scratched in the earth, bodies arranged facing outward",
    },
    "Void": {
        # The Hollow Court — The Sleeping One's agents
        "deity": "The Sleeping One",
        "color": "deep black and cold ash",
        "tone": "annihilation as inevitability",
        "spawn_flavor": "absolute stillness — they were already here, waiting, long before you arrived",
    },
}

# ------------------------------------------------------------------ #
# Fallback town name fragments (used when lore DB is empty)          #
# ------------------------------------------------------------------ #

_TOWN_ADJECTIVES = [
    "Dusty", "Cracked", "Scorched", "Ironblood", "Grimrock",
    "Deadwater", "Coppergate", "Thunderpass", "Ashen", "Bonehollow",
]
_TOWN_SUFFIXES = [
    "Crossing", "Flats", "Springs", "Ridge", "Junction",
    "Creek", "Gulch", "Reach", "Hollow", "Station",
]

# ------------------------------------------------------------------ #
# Map dataclass                                                       #
# ------------------------------------------------------------------ #

@dataclass
class Map:
    """
    A procedurally generated tactical map.

    Attributes:
        map_type    — which generator produced this map
        seed        — RNG seed used; same seed + type = identical map
        width       — number of columns
        height      — number of rows
        tiles       — 2D list [y][x] of tile-type strings
        metadata    — dict of lore/thematic data attached to this map
        faction     — which faction "owns" this map location
        town_name   — settlement name (if applicable to the map type)
        region      — world region name
    """
    map_type: str
    seed: int
    width: int
    height: int
    tiles: list[list[str]]            # tiles[y][x]
    metadata: dict = field(default_factory=dict)
    faction: str = "Dustfolk"
    town_name: str = ""
    region: str = "The Flats"

    # ---------------------------------------------------------------- #
    # Tile access helpers                                               #
    # ---------------------------------------------------------------- #

    def get_tile(self, x: int, y: int) -> str:
        """Return tile type at (x, y). Returns 'void' if out of bounds."""
        if 0 <= y < self.height and 0 <= x < self.width:
            return self.tiles[y][x]
        return "void"

    def set_tile(self, x: int, y: int, tile_type: str) -> None:
        """Set tile at (x, y) if in bounds."""
        if 0 <= y < self.height and 0 <= x < self.width:
            self.tiles[y][x] = tile_type

    def tiles_of_type(self, *tile_types: str) -> list[tuple[int, int]]:
        """Return all (x, y) positions matching any of the given tile types."""
        result = []
        for y in range(self.height):
            for x in range(self.width):
                if self.tiles[y][x] in tile_types:
                    result.append((x, y))
        return result

    # ---------------------------------------------------------------- #
    # Public API                                                        #
    # ---------------------------------------------------------------- #

    def get_spawn_points(self, faction: str = "player") -> list[tuple[int, int]]:
        """
        Return spawn point coordinates for the given faction.

        Args:
            faction — "player" returns spawn_player tiles;
                      anything else returns spawn_enemy tiles.

        Returns:
            List of (x, y) tuples.
        """
        tile_type = "spawn_player" if faction.lower() == "player" else "spawn_enemy"
        return self.tiles_of_type(tile_type)

    def get_cover_positions(self) -> list[tuple[int, int]]:
        """
        Return all tiles that provide cover (low or high).

        Returns:
            List of (x, y) tuples for cover_low and cover_high tiles.
        """
        return self.tiles_of_type("cover_low", "cover_high")

    def get_hazard_positions(self) -> list[tuple[int, int]]:
        """Return all hazard tile coordinates."""
        return self.tiles_of_type("hazard")

    def get_loot_positions(self) -> list[tuple[int, int]]:
        """Return all loot tile coordinates."""
        return self.tiles_of_type("loot")

    def get_objective_positions(self) -> list[tuple[int, int]]:
        """Return all objective tile coordinates."""
        return self.tiles_of_type("objective")

    # ---------------------------------------------------------------- #
    # Output formats                                                    #
    # ---------------------------------------------------------------- #

    def to_ascii(self) -> str:
        """
        Render the map as an ASCII string suitable for CLI preview.

        Legend is appended below the grid.
        """
        lines = []

        # Top border with map info
        header = f" {self.map_type.upper().replace('_', ' ')} — {self.town_name or self.region} "
        border_width = self.width + 2
        lines.append("=" * border_width)
        lines.append(header.center(border_width))
        lines.append(f" seed:{self.seed} | {self.width}x{self.height} | faction:{self.faction} ".center(border_width))
        lines.append("=" * border_width)

        # Grid rows
        for y in range(self.height):
            row_chars = [TILE_SYMBOLS.get(self.tiles[y][x], "?") for x in range(self.width)]
            lines.append("|" + "".join(row_chars) + "|")

        lines.append("=" * border_width)

        # Legend
        lines.append("")
        lines.append("LEGEND:")
        legend_items = [
            (".", "Floor"),
            ("#", "Wall"),
            ("c", "Low Cover (+1 def)"),
            ("C", "High Cover (+2 def, blocks LoS)"),
            ("X", "Hazard"),
            ("P", "Player Spawn"),
            ("E", "Enemy Spawn"),
            ("$", "Loot"),
            ("O", "Objective"),
            ("+", "Door"),
            (" ", "Void"),
        ]
        for sym, label in legend_items:
            lines.append(f"  {sym}  {label}")

        return "\n".join(lines)

    def to_json(self) -> dict:
        """
        Serialize the map to a JSON-compatible dict for game engine consumption.

        The returned structure includes:
          - Full tile grid
          - All special tile positions pre-indexed
          - Tile property data from TILE_DEFS
          - Map metadata and lore annotations
        """
        return {
            "map_type": self.map_type,
            "seed": self.seed,
            "width": self.width,
            "height": self.height,
            "faction": self.faction,
            "town_name": self.town_name,
            "region": self.region,
            "tiles": self.tiles,
            "tile_defs": TILE_DEFS,
            "spawn_points": {
                "player": self.get_spawn_points("player"),
                "enemy": self.get_spawn_points("enemy"),
            },
            "cover_positions": self.get_cover_positions(),
            "hazard_positions": self.get_hazard_positions(),
            "loot_positions": self.get_loot_positions(),
            "objective_positions": self.get_objective_positions(),
            "metadata": self.metadata,
            "generated_at": time.time(),
        }

    def describe(self) -> str:
        """
        Return a narrative description of the map location.

        Pulls from lore engine if available; falls back to template text.
        The description is flavor text suitable for display to the player
        when the encounter loads.
        """
        # Prefer a Claude-generated description stored in metadata
        if self.metadata.get("description"):
            return self.metadata["description"]

        # Fallback template descriptions keyed by map_type
        faction_data = MAP_FACTIONS.get(self.faction, MAP_FACTIONS["Dustfolk"])
        town_ref = self.town_name or self.region

        templates = {
            "ghost_town": (
                f"The town of {town_ref} died slow. Buildings lean against each other "
                f"like old men who've forgotten why they're still standing. Wind pushes "
                f"grit through empty windows. Somewhere a door swings on a broken hinge — "
                f"the only sound for miles. The {self.faction} have been here. "
                f"You can tell by {faction_data['spawn_flavor']}."
            ),
            "canyon": (
                f"The canyon walls rise fifty feet on either side, red rock striped with "
                f"the blue-green seam of old Ashfall deposits. The passage narrows ahead "
                f"to a chokepoint no wider than two men abreast. {town_ref} is a day's "
                f"ride behind you. The {self.faction} knew you were coming — "
                f"{faction_data['spawn_flavor']}."
            ),
            "mine_shaft": (
                f"The Ashfall smell hits you before the darkness does — that burnt-copper "
                f"reek, the blue glow pulsing from the ore veins. Cart tracks lead deeper "
                f"into the earth. Somewhere ahead, something moves. The {self.faction} "
                f"claimed these tunnels and left their mark: {faction_data['spawn_flavor']}."
            ),
            "desert_outpost": (
                f"The outpost crouches against the desert heat like it's trying to disappear "
                f"into the sand. Watchtower. Supply depot. A perimeter wall that's seen "
                f"better decades. This is {town_ref} territory — or it was. "
                f"The {self.faction} are here now, and they've made themselves comfortable: "
                f"{faction_data['spawn_flavor']}."
            ),
            "cursed_ruins": (
                f"The ruins of {town_ref} shouldn't be moving, but they are. Stones orbit "
                f"each other in lazy circles six feet off the ground. The Ashfall deposits "
                f"glow wrong here — too bright, the wrong color, pulsing in a rhythm that "
                f"matches nothing natural. The {self.faction} called this place sacred. "
                f"They left their mark in the only way they know: {faction_data['spawn_flavor']}."
            ),
        }

        return templates.get(
            self.map_type,
            f"A location in {town_ref}, held by the {self.faction}. The ground remembers things."
        )


# ------------------------------------------------------------------ #
# Map generator — internal helpers                                    #
# ------------------------------------------------------------------ #

def _blank_grid(width: int, height: int, fill: str = "floor") -> list[list[str]]:
    """Create a 2D grid filled with the specified tile type."""
    return [[fill for _ in range(width)] for _ in range(height)]


def _rect(tiles: list[list[str]], x1: int, y1: int, x2: int, y2: int, tile: str) -> None:
    """Fill a rectangle of tiles. Coordinates are inclusive."""
    height = len(tiles)
    width = len(tiles[0]) if tiles else 0
    for y in range(max(0, y1), min(height, y2 + 1)):
        for x in range(max(0, x1), min(width, x2 + 1)):
            tiles[y][x] = tile


def _border_walls(tiles: list[list[str]]) -> None:
    """Place impassable walls around the map perimeter."""
    height = len(tiles)
    width = len(tiles[0]) if tiles else 0
    _rect(tiles, 0, 0, width - 1, 0, "wall")
    _rect(tiles, 0, height - 1, width - 1, height - 1, "wall")
    _rect(tiles, 0, 0, 0, height - 1, "wall")
    _rect(tiles, width - 1, 0, width - 1, height - 1, "wall")


def _place_building(
    rng: random.Random,
    tiles: list[list[str]],
    x: int, y: int,
    bw: int, bh: int,
    has_door: bool = True,
    interior_cover: bool = True,
) -> None:
    """
    Place a rectangular building footprint with walls, optional door, and interior cover.

    The door is placed on one of the four sides at a random midpoint.
    Interior tiles are floor with a chance of low cover (barrels, furniture).
    """
    height = len(tiles)
    width = len(tiles[0]) if tiles else 0

    # Clamp to grid bounds
    x2 = min(x + bw - 1, width - 1)
    y2 = min(y + bh - 1, height - 1)
    if x2 <= x or y2 <= y:
        return

    # Walls
    _rect(tiles, x, y, x2, y, "wall")       # top
    _rect(tiles, x, y2, x2, y2, "wall")     # bottom
    _rect(tiles, x, y, x, y2, "wall")       # left
    _rect(tiles, x2, y, x2, y2, "wall")     # right

    # Interior floor
    _rect(tiles, x + 1, y + 1, x2 - 1, y2 - 1, "floor")

    # Interior cover objects (furniture, crates)
    if interior_cover and (x2 - x) > 2 and (y2 - y) > 2:
        interior_positions = [
            (ix, iy)
            for iy in range(y + 1, y2)
            for ix in range(x + 1, x2)
        ]
        cover_count = max(1, len(interior_positions) // 6)
        for pos in rng.sample(interior_positions, min(cover_count, len(interior_positions))):
            tiles[pos[1]][pos[0]] = "cover_low"

    # Door placement
    if has_door:
        side = rng.choice(["top", "bottom", "left", "right"])
        if side == "top" and x2 > x + 1:
            tiles[y][rng.randint(x + 1, x2 - 1)] = "door"
        elif side == "bottom" and x2 > x + 1:
            tiles[y2][rng.randint(x + 1, x2 - 1)] = "door"
        elif side == "left" and y2 > y + 1:
            tiles[rng.randint(y + 1, y2 - 1)][x] = "door"
        elif side == "right" and y2 > y + 1:
            tiles[rng.randint(y + 1, y2 - 1)][x2] = "door"


def _scatter_tiles(
    rng: random.Random,
    tiles: list[list[str]],
    tile_type: str,
    count: int,
    allowed_types: tuple = ("floor",),
    margin: int = 1,
) -> list[tuple[int, int]]:
    """
    Randomly place `count` tiles of `tile_type` on cells currently of `allowed_types`.

    Args:
        margin — minimum distance from map edge to place tiles

    Returns:
        List of (x, y) positions where tiles were placed.
    """
    height = len(tiles)
    width = len(tiles[0]) if tiles else 0

    candidates = [
        (x, y)
        for y in range(margin, height - margin)
        for x in range(margin, width - margin)
        if tiles[y][x] in allowed_types
    ]

    rng.shuffle(candidates)
    placed = []
    for x, y in candidates[:count]:
        tiles[y][x] = tile_type
        placed.append((x, y))
    return placed


def _place_spawns(
    rng: random.Random,
    tiles: list[list[str]],
    player_count: int = 4,
    enemy_count: int = 6,
) -> None:
    """
    Place player spawns on the south edge and enemy spawns on the north edge,
    on passable floor tiles.
    """
    height = len(tiles)
    width = len(tiles[0]) if tiles else 0

    # Player spawns — bottom third of map
    player_zone = [
        (x, y)
        for y in range(height * 2 // 3, height - 1)
        for x in range(1, width - 1)
        if tiles[y][x] == "floor"
    ]
    rng.shuffle(player_zone)
    for x, y in player_zone[:player_count]:
        tiles[y][x] = "spawn_player"

    # Enemy spawns — top third of map
    enemy_zone = [
        (x, y)
        for y in range(1, height // 3)
        for x in range(1, width - 1)
        if tiles[y][x] == "floor"
    ]
    rng.shuffle(enemy_zone)
    for x, y in enemy_zone[:enemy_count]:
        tiles[y][x] = "spawn_enemy"


def _get_town_name(rng: random.Random) -> str:
    """
    Try to pull an existing town name from the lore DB.
    Falls back to a generated name if the DB is empty or unavailable.
    """
    try:
        from lore_engine import LoreDB
        db = LoreDB()
        names = db.get_town_names()
        if names:
            return rng.choice(names)
    except Exception:
        pass

    # Fallback: generate a name from word fragments
    adj = rng.choice(_TOWN_ADJECTIVES)
    suf = rng.choice(_TOWN_SUFFIXES)
    return f"{adj} {suf}"


def _get_region(rng: random.Random) -> str:
    """Pull a random region name from lore_engine constants or return a default."""
    try:
        from lore_engine import REGIONS
        return rng.choice(REGIONS)
    except Exception:
        return "The Flats"


# ------------------------------------------------------------------ #
# Map type generators                                                 #
# ------------------------------------------------------------------ #

def _gen_ghost_town(rng: random.Random, width: int, height: int) -> tuple[list[list[str]], dict]:
    """
    Ghost town: a grid of abandoned buildings with open streets between them.

    Layout strategy:
    - Divide the map into a loose urban grid of 4-8 building footprints
    - Leave street corridors between them
    - Scatter cover objects (barrels, crates, wagon wreckage) in streets
    - Place a saloon (larger building), church (with cross-shaped footprint), jail
    - Hazard: collapsed structures, Ashfall-cracked ground
    """
    tiles = _blank_grid(width, height, "floor")
    _border_walls(tiles)

    metadata = {"buildings": [], "special": []}

    # Building placement grid: divide map into zones
    # We want 2-3 columns, 2-3 rows of buildings with street margins
    cols = 3 if width >= 24 else 2
    rows = 3 if height >= 18 else 2

    col_width = (width - 4) // cols
    row_height = (height - 4) // rows

    special_buildings = ["saloon", "church", "jail"]
    building_idx = 0

    for col in range(cols):
        for row in range(rows):
            # Base position for this zone
            zone_x = 2 + col * col_width
            zone_y = 2 + row * row_height

            # Randomize building size within zone (leave street margins)
            margin = 1
            bw = rng.randint(col_width // 2, col_width - margin - 1)
            bh = rng.randint(row_height // 2, row_height - margin - 1)

            # Offset within zone for natural placement
            offset_x = rng.randint(0, col_width - bw - margin)
            offset_y = rng.randint(0, row_height - bh - margin)

            bx = zone_x + offset_x
            by = zone_y + offset_y

            # Some buildings are "collapsed" — just rubble (cover_high walls, hazards)
            if rng.random() < 0.25:
                # Collapsed ruin — scatter debris
                for _ in range(rng.randint(2, 5)):
                    rx = rng.randint(bx, min(bx + bw, width - 2))
                    ry = rng.randint(by, min(by + bh, height - 2))
                    if tiles[ry][rx] == "floor":
                        tiles[ry][rx] = rng.choice(["cover_high", "cover_low", "hazard"])
                metadata["buildings"].append({"type": "collapsed_ruin", "x": bx, "y": by})
            else:
                # Standing building
                building_type = special_buildings[building_idx] if building_idx < len(special_buildings) else "building"
                _place_building(rng, tiles, bx, by, bw, bh, has_door=True, interior_cover=True)
                metadata["buildings"].append({"type": building_type, "x": bx, "y": by, "w": bw, "h": bh})
                building_idx += 1

    # Street cover: barrels, crates, wagon wreckage
    _scatter_tiles(rng, tiles, "cover_low", count=rng.randint(8, 14), allowed_types=("floor",))

    # Ashfall-cracked ground hazards on streets
    _scatter_tiles(rng, tiles, "hazard", count=rng.randint(3, 6), allowed_types=("floor",))

    # A loot cache (hidden stash in an alley)
    _scatter_tiles(rng, tiles, "loot", count=rng.randint(2, 4), allowed_types=("floor",))

    # Objective: center of the map (sheriff's office, or the saloon safe)
    obj_x, obj_y = width // 2, height // 2
    # Walk until we find a floor tile near center
    for dx, dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1),(2,0),(-2,0)]:
        if tiles[obj_y + dy][obj_x + dx] == "floor":
            tiles[obj_y + dy][obj_x + dx] = "objective"
            break

    # Spawn placement
    _place_spawns(rng, tiles, player_count=4, enemy_count=5)

    metadata["description"] = None  # filled by describe() dynamically
    metadata["tone"] = "abandoned, sun-bleached, silent except for wind"
    return tiles, metadata


def _gen_canyon(rng: random.Random, width: int, height: int) -> tuple[list[list[str]], dict]:
    """
    Canyon: narrow rock passages with high ground flanking the main corridor.

    Layout strategy:
    - Main floor corridor running roughly north-south through center
    - Rock wall formations on east and west flanks
    - High ground "ledge" tiles (cover_high) accessible via narrow paths
    - Chokepoints where corridor narrows to 2-3 tiles wide
    - Ambush positions on ledges with LoS over the main path
    - Ashfall ore veins in rock faces (loot)
    """
    tiles = _blank_grid(width, height, "wall")
    _border_walls(tiles)

    metadata = {"passages": [], "ledges": []}

    # Main corridor — winding path through center of map
    # Start at bottom center, wind to top center
    corridor_x = width // 2
    corridor_width_base = rng.randint(3, 5)

    for y in range(1, height - 1):
        # Occasionally shift the corridor left or right (canyon bends)
        if rng.random() < 0.25:
            corridor_x = max(3, min(width - 4, corridor_x + rng.choice([-1, 1])))

        # Chokepoint: narrow the corridor at random intervals
        if rng.random() < 0.15:
            corridor_width = max(2, corridor_width_base - 2)
        else:
            corridor_width = corridor_width_base + rng.randint(-1, 1)

        half = corridor_width // 2
        for x in range(max(1, corridor_x - half), min(width - 1, corridor_x + half + 1)):
            tiles[y][x] = "floor"

    # Rock formations: irregular wall clusters flanking the corridor
    for _ in range(rng.randint(8, 16)):
        rx = rng.choice([rng.randint(1, width // 3), rng.randint(width * 2 // 3, width - 2)])
        ry = rng.randint(1, height - 2)
        formation_size = rng.randint(1, 3)
        for dy in range(-formation_size, formation_size + 1):
            for dx in range(-formation_size, formation_size + 1):
                fx, fy = rx + dx, ry + dy
                if 1 <= fx < width - 1 and 1 <= fy < height - 1 and tiles[fy][fx] != "floor":
                    tiles[fy][fx] = "wall"

    # High ground ledges: cover_high positions adjacent to walls, overlooking corridor
    ledge_count = 0
    for y in range(2, height - 2):
        for x in range(1, width - 1):
            if tiles[y][x] == "floor":
                # Check if adjacent to a wall (potential ledge position)
                adj_walls = sum(
                    1 for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]
                    if tiles[y+dy][x+dx] == "wall"
                )
                if adj_walls >= 2 and rng.random() < 0.2 and ledge_count < 12:
                    tiles[y][x] = "cover_high"
                    metadata["ledges"].append((x, y))
                    ledge_count += 1

    # Low cover: fallen rocks, boulders in the corridor
    _scatter_tiles(rng, tiles, "cover_low", count=rng.randint(6, 10), allowed_types=("floor",))

    # Hazard: unstable ground, Ashfall-heated rock
    _scatter_tiles(rng, tiles, "hazard", count=rng.randint(2, 5), allowed_types=("floor",))

    # Loot: Ashfall ore veins (adjacent to walls, accessible from floor)
    _scatter_tiles(rng, tiles, "loot", count=rng.randint(2, 4), allowed_types=("floor",))

    # Objective: deep in the canyon (north section)
    obj_candidates = [
        (x, y) for y in range(1, height // 3)
        for x in range(1, width - 1)
        if tiles[y][x] == "floor"
    ]
    if obj_candidates:
        ox, oy = rng.choice(obj_candidates)
        tiles[oy][ox] = "objective"

    _place_spawns(rng, tiles, player_count=4, enemy_count=6)

    metadata["tone"] = "close, hot, every shadow a potential ambush"
    return tiles, metadata


def _gen_mine_shaft(rng: random.Random, width: int, height: int) -> tuple[list[list[str]], dict]:
    """
    Mine shaft: underground tunnel network with branching passages.

    Layout strategy:
    - Main shaft running vertically through map center
    - Side tunnels branching left and right at irregular intervals
    - Ore vein chambers (loot clusters) at tunnel ends
    - Cart track indicators on main shaft floor
    - Dynamite caches as hazard tiles
    - Ashfall glow zones (hazard) near ore deposits
    - Support columns (cover_high) at regular intervals
    """
    tiles = _blank_grid(width, height, "wall")
    _border_walls(tiles)

    metadata = {"tunnels": [], "chambers": []}

    # Main vertical shaft — 3 tiles wide down the center
    shaft_x = width // 2
    shaft_width = 3
    for y in range(1, height - 1):
        for x in range(shaft_x - 1, shaft_x + 2):
            if 0 < x < width - 1:
                tiles[y][x] = "floor"

    # Branch tunnels: horizontal side passages
    branch_rows = sorted(rng.sample(range(2, height - 2), k=min(5, height - 4)))
    for by in branch_rows:
        # Direction: left, right, or both
        dirs = rng.choice([["left"], ["right"], ["left", "right"]])
        for direction in dirs:
            tunnel_length = rng.randint(3, width // 3)
            if direction == "left":
                tx_start, tx_end = shaft_x - 2, shaft_x - 2 - tunnel_length
                x_range = range(max(1, tx_end), tx_start + 1)
            else:
                tx_start, tx_end = shaft_x + 2, shaft_x + 2 + tunnel_length
                x_range = range(tx_start, min(width - 1, tx_end + 1))

            for tx in x_range:
                for dy in range(-1, 2):
                    ty = by + dy
                    if 0 < ty < height - 1:
                        # Tunnel is 1 tile wide with occasional 2-wide sections
                        if dy == 0 or (abs(dy) == 1 and rng.random() < 0.2):
                            tiles[ty][tx] = "floor"

            metadata["tunnels"].append({"y": by, "direction": direction, "length": tunnel_length})

            # Chamber at tunnel end
            chamber_x = max(1, min(width - 3, tx_end if direction == "right" else tx_end - 1))
            chamber_w = rng.randint(2, 4)
            chamber_h = rng.randint(2, 3)
            _rect(tiles, chamber_x, by - 1, chamber_x + chamber_w, by + chamber_h, "floor")
            metadata["chambers"].append((chamber_x, by))

            # Ore vein loot in chambers
            for _ in range(rng.randint(1, 3)):
                lx = rng.randint(chamber_x, min(chamber_x + chamber_w, width - 2))
                ly = rng.randint(by - 1, min(by + chamber_h, height - 2))
                if tiles[ly][lx] == "floor":
                    tiles[ly][lx] = "loot"

    # Support columns in main shaft (cover_high at intervals)
    for y in range(3, height - 3, 4):
        col_x = rng.choice([shaft_x - 1, shaft_x + 1])
        if tiles[y][col_x] == "floor":
            tiles[y][col_x] = "cover_high"

    # Dynamite caches — hazard tiles
    _scatter_tiles(rng, tiles, "hazard", count=rng.randint(3, 6), allowed_types=("floor",))

    # Low cover: ore carts, support beams
    _scatter_tiles(rng, tiles, "cover_low", count=rng.randint(4, 8), allowed_types=("floor",))

    # Objective: deepest chamber (north end of map, tunnel terminus)
    obj_candidates = [
        (x, y) for y in range(1, height // 3)
        for x in range(1, width - 1)
        if tiles[y][x] == "floor"
    ]
    if obj_candidates:
        ox, oy = rng.choice(obj_candidates)
        tiles[oy][ox] = "objective"

    _place_spawns(rng, tiles, player_count=3, enemy_count=5)

    metadata["tone"] = "tight, dark, Ashfall glowing blue in the walls"
    return tiles, metadata


def _gen_desert_outpost(rng: random.Random, width: int, height: int) -> tuple[list[list[str]], dict]:
    """
    Desert outpost: fort-like compound with outer perimeter, interior buildings.

    Layout strategy:
    - Outer perimeter wall with gaps (gates) on north and south
    - Interior: main building (command center), supply depot, watchtower position
    - Watchtower: elevated position (cover_high cluster) at one corner
    - Courtyard floor space with cover objects scattered
    - Exterior approach terrain: low cover, hazards, open ground
    """
    tiles = _blank_grid(width, height, "floor")
    _border_walls(tiles)

    metadata = {"structures": [], "perimeter": {}}

    # Outer perimeter wall (inset from map edge)
    wall_margin = 3
    pw_x1 = wall_margin
    pw_y1 = wall_margin
    pw_x2 = width - wall_margin - 1
    pw_y2 = height - wall_margin - 1

    # Draw perimeter walls
    _rect(tiles, pw_x1, pw_y1, pw_x2, pw_y1, "wall")       # north wall
    _rect(tiles, pw_x1, pw_y2, pw_x2, pw_y2, "wall")       # south wall
    _rect(tiles, pw_x1, pw_y1, pw_x1, pw_y2, "wall")       # west wall
    _rect(tiles, pw_x2, pw_y1, pw_x2, pw_y2, "wall")       # east wall

    # Gates (openings in perimeter)
    gate_n_x = (pw_x1 + pw_x2) // 2
    gate_s_x = gate_n_x + rng.randint(-1, 1)
    for gx in range(gate_n_x - 1, gate_n_x + 2):
        if pw_x1 < gx < pw_x2:
            tiles[pw_y1][gx] = "floor"    # north gate
            tiles[pw_y2][gx] = "floor"    # south gate

    metadata["perimeter"] = {"x1": pw_x1, "y1": pw_y1, "x2": pw_x2, "y2": pw_y2}

    # Interior: main building (command post) — center-ish, north half
    main_w = rng.randint(5, 8)
    main_h = rng.randint(4, 6)
    main_x = (pw_x1 + pw_x2) // 2 - main_w // 2
    main_y = pw_y1 + 2
    _place_building(rng, tiles, main_x, main_y, main_w, main_h, has_door=True, interior_cover=True)
    metadata["structures"].append({"type": "command_post", "x": main_x, "y": main_y})

    # Supply depot — smaller, south side of interior
    supply_w = rng.randint(3, 5)
    supply_h = rng.randint(3, 4)
    supply_x = rng.randint(pw_x1 + 2, pw_x1 + (pw_x2 - pw_x1) // 3)
    supply_y = pw_y2 - supply_h - 2
    _place_building(rng, tiles, supply_x, supply_y, supply_w, supply_h, has_door=True, interior_cover=True)
    metadata["structures"].append({"type": "supply_depot", "x": supply_x, "y": supply_y})

    # Watchtower: cover_high cluster in one corner of the perimeter
    tower_corner = rng.choice(["ne", "nw"])
    if tower_corner == "ne":
        tower_x, tower_y = pw_x2 - 2, pw_y1 + 1
    else:
        tower_x, tower_y = pw_x1 + 1, pw_y1 + 1
    for dy in range(2):
        for dx in range(2):
            tx, ty = tower_x + dx, tower_y + dy
            if 0 < tx < width - 1 and 0 < ty < height - 1:
                tiles[ty][tx] = "cover_high"
    metadata["structures"].append({"type": "watchtower", "x": tower_x, "y": tower_y})

    # Courtyard cover: barrels, crates
    _scatter_tiles(rng, tiles, "cover_low",
                   count=rng.randint(6, 10),
                   allowed_types=("floor",),
                   margin=wall_margin + 1)

    # Exterior approach: scattered rocks and hazards outside perimeter
    for y in range(1, wall_margin):
        for x in range(1, width - 1):
            if rng.random() < 0.1:
                tiles[y][x] = "cover_low"
            elif rng.random() < 0.05:
                tiles[y][x] = "hazard"

    # Objective: inside command post
    tiles[main_y + main_h // 2][main_x + main_w // 2] = "objective"

    # Loot in supply depot
    _scatter_tiles(rng, tiles, "loot",
                   count=rng.randint(2, 3),
                   allowed_types=("floor",),
                   margin=wall_margin + 1)

    # Hazard: Ashfall canisters in courtyard
    _scatter_tiles(rng, tiles, "hazard",
                   count=rng.randint(2, 4),
                   allowed_types=("floor",),
                   margin=wall_margin + 1)

    _place_spawns(rng, tiles, player_count=4, enemy_count=6)

    metadata["tone"] = "exposed, tactical, the watchtower sees everything"
    return tiles, metadata


def _gen_cursed_ruins(rng: random.Random, width: int, height: int) -> tuple[list[list[str]], dict]:
    """
    Cursed ruins: Weird West weirdness — unstable geometry, ritual circles, floating debris.

    Layout strategy:
    - Irregular ruin fragments (partial walls, never complete structures)
    - Ritual circles: floor tiles arranged in ring patterns with objective/hazard center
    - Void tiles: areas of non-existence where the map geometry has collapsed
    - "Floating" cover_high islands surrounded by void
    - Ashfall corruption zones (hazard clusters with loot at center)
    - Unpredictable chokepoints that force tactical commitment
    """
    # Start with void, carve out navigable areas
    tiles = _blank_grid(width, height, "void")
    _border_walls(tiles)

    metadata = {"circles": [], "fragments": [], "corruption_zones": []}

    # Carve main traversable area — irregular connected regions
    # Use a random walk from center to establish base floor
    cx, cy = width // 2, height // 2
    tiles[cy][cx] = "floor"

    # Multiple random walks from center to create irregular floor areas
    for _ in range(4):
        x, y = cx, cy
        steps = rng.randint(20, 40)
        for _ in range(steps):
            dx, dy = rng.choice([(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)])
            nx, ny = x + dx, y + dy
            if 1 < nx < width - 2 and 1 < ny < height - 2:
                tiles[ny][nx] = "floor"
                # Occasionally widen the path
                if rng.random() < 0.4:
                    for wdx, wdy in rng.sample([(1,0),(-1,0),(0,1),(0,-1)], 2):
                        wx, wy = nx + wdx, ny + wdy
                        if 1 < wx < width - 2 and 1 < wy < height - 2:
                            tiles[wy][wx] = "floor"
                x, y = nx, ny

    # Ruin fragments: partial wall segments
    fragment_count = rng.randint(8, 15)
    for _ in range(fragment_count):
        fx = rng.randint(2, width - 4)
        fy = rng.randint(2, height - 4)
        flen = rng.randint(2, 5)
        fdir = rng.choice(["h", "v"])

        for i in range(flen):
            wx = fx + (i if fdir == "h" else 0)
            wy = fy + (i if fdir == "v" else 0)
            if 1 <= wx < width - 1 and 1 <= wy < height - 1:
                tiles[wy][wx] = "wall"
                metadata["fragments"].append((wx, wy))

    # Ritual circles: ring of floor tiles with hazard or objective center
    circle_count = rng.randint(2, 4)
    circle_radii = [3, 4]

    for circle_idx in range(circle_count):
        # Place circle somewhere on the floor
        circle_candidates = [
            (x, y) for y in range(4, height - 4) for x in range(4, width - 4)
            if tiles[y][x] == "floor"
        ]
        if not circle_candidates:
            continue

        cx_c, cy_c = rng.choice(circle_candidates)
        radius = rng.choice(circle_radii)

        # Carve circle floor and mark perimeter
        for ry in range(cy_c - radius - 1, cy_c + radius + 2):
            for rx in range(cx_c - radius - 1, cx_c + radius + 2):
                if 1 < rx < width - 1 and 1 < ry < height - 1:
                    dist = ((rx - cx_c) ** 2 + (ry - cy_c) ** 2) ** 0.5
                    if dist <= radius:
                        if abs(dist - radius) < 0.9:
                            # Ring perimeter — Ashfall ritual markers
                            tiles[ry][rx] = "cover_low"
                        elif dist < radius - 0.5:
                            tiles[ry][rx] = "floor"

        # Center of circle — first is objective, rest are hazards
        center_tile = "objective" if circle_idx == 0 else "hazard"
        tiles[cy_c][cx_c] = center_tile
        metadata["circles"].append({
            "x": cx_c, "y": cy_c,
            "radius": radius,
            "center": center_tile,
        })

    # Floating debris "islands": isolated cover_high surrounded by void
    island_count = rng.randint(3, 6)
    for _ in range(island_count):
        ix = rng.randint(2, width - 4)
        iy = rng.randint(2, height - 4)
        if tiles[iy][ix] == "void":
            # Small island: make a 1-2 tile floor patch surrounded by void
            island_size = rng.randint(1, 2)
            for dy in range(-island_size, island_size + 1):
                for dx in range(-island_size, island_size + 1):
                    nx, ny = ix + dx, iy + dy
                    if 1 < nx < width - 1 and 1 < ny < height - 1:
                        tiles[ny][nx] = "floor"
            tiles[iy][ix] = "cover_high"  # The floating debris piece itself

    # Corruption zones: Ashfall cluster with loot at center
    corruption_count = rng.randint(2, 4)
    for _ in range(corruption_count):
        zone_candidates = [
            (x, y) for y in range(2, height - 2) for x in range(2, width - 2)
            if tiles[y][x] == "floor"
        ]
        if not zone_candidates:
            continue
        zx, zy = rng.choice(zone_candidates)
        # Ring of hazard around loot center
        tiles[zy][zx] = "loot"
        for dx, dy in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,1),(-1,1),(1,-1)]:
            hx, hy = zx + dx, zy + dy
            if 0 < hx < width - 1 and 0 < hy < height - 1 and tiles[hy][hx] == "floor":
                tiles[hy][hx] = "hazard"
        metadata["corruption_zones"].append((zx, zy))

    _place_spawns(rng, tiles, player_count=3, enemy_count=4)

    metadata["tone"] = "wrong, sacred, the gods left scorch marks and did not look back"
    return tiles, metadata


# ------------------------------------------------------------------ #
# Generator dispatch table                                            #
# ------------------------------------------------------------------ #

_GENERATORS = {
    "ghost_town":     _gen_ghost_town,
    "canyon":         _gen_canyon,
    "mine_shaft":     _gen_mine_shaft,
    "desert_outpost": _gen_desert_outpost,
    "cursed_ruins":   _gen_cursed_ruins,
}

MAP_TYPE_DESCRIPTIONS = {
    "ghost_town":     "Abandoned settlement — buildings, saloon, church, jail, open streets",
    "canyon":         "Narrow rock passage — chokepoints, high ground, ambush positions",
    "mine_shaft":     "Underground tunnels — ore veins, cart tracks, dynamite caches",
    "desert_outpost": "Fort-like compound — perimeter wall, watchtower, supply depot",
    "cursed_ruins":   "Weird West anomaly — ritual circles, floating debris, unstable geometry",
}

# Faction weighting per map type (which faction is most likely to hold this location)
_MAP_FACTION_WEIGHTS = {
    "ghost_town":     {"Dustfolk": 40, "Ironclad": 25, "Uncanny": 25, "Void": 10},
    "canyon":         {"Dustfolk": 35, "Ironclad": 20, "Uncanny": 20, "Void": 25},
    "mine_shaft":     {"Dustfolk": 20, "Ironclad": 50, "Uncanny": 15, "Void": 15},
    "desert_outpost": {"Dustfolk": 30, "Ironclad": 45, "Uncanny": 15, "Void": 10},
    "cursed_ruins":   {"Dustfolk": 5,  "Ironclad": 10, "Uncanny": 35, "Void": 50},
}


def _weighted_choice(rng: random.Random, weights: dict[str, int]) -> str:
    """Choose a key from a dict of {key: weight} using weighted random selection."""
    population = []
    for key, weight in weights.items():
        population.extend([key] * weight)
    return rng.choice(population)


# ------------------------------------------------------------------ #
# Public API                                                          #
# ------------------------------------------------------------------ #

def generate_map(
    map_type: str,
    seed: Optional[int] = None,
    size: tuple[int, int] = (20, 15),
) -> Map:
    """
    Generate a procedural tactical map.

    Args:
        map_type — one of: ghost_town, canyon, mine_shaft, desert_outpost, cursed_ruins
        seed     — integer seed for reproducibility; random if None
        size     — (width, height) tuple; minimum (20, 15)

    Returns:
        Map object with all tile data, spawn points, and metadata populated.

    Raises:
        ValueError if map_type is not recognized.

    Example:
        m = generate_map("ghost_town", seed=42)
        print(m.to_ascii())
        data = m.to_json()
    """
    if map_type not in _GENERATORS:
        valid = ", ".join(_GENERATORS.keys())
        raise ValueError(f"Unknown map type '{map_type}'. Valid types: {valid}")

    # Enforce minimum size
    width = max(20, size[0])
    height = max(15, size[1])

    # Seed the RNG — same seed + type = identical map
    if seed is None:
        seed = random.randint(0, 2 ** 32 - 1)

    rng = random.Random(seed)

    # Run the appropriate generator
    generator_fn = _GENERATORS[map_type]
    tiles, metadata = generator_fn(rng, width, height)

    # Select faction based on map type affinity weights
    faction_weights = _MAP_FACTION_WEIGHTS.get(map_type, {"Dustfolk": 100})
    faction = _weighted_choice(rng, faction_weights)

    # Pull town name and region from lore engine (falls back to generated names)
    town_name = _get_town_name(rng)
    region = _get_region(rng)

    return Map(
        map_type=map_type,
        seed=seed,
        width=width,
        height=height,
        tiles=tiles,
        metadata=metadata,
        faction=faction,
        town_name=town_name,
        region=region,
    )


def list_map_types() -> dict[str, str]:
    """Return a dict of {map_type: description} for all available map types."""
    return dict(MAP_TYPE_DESCRIPTIONS)


# ------------------------------------------------------------------ #
# CLI entrypoint                                                      #
# ------------------------------------------------------------------ #

def _cli_main() -> None:
    parser = argparse.ArgumentParser(
        description="Dustfall procedural map generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python map_gen.py --type ghost_town --seed 42 --preview
  python map_gen.py --type canyon --export map.json
  python map_gen.py --type mine_shaft --size 28 20 --preview
  python map_gen.py --list-types
        """,
    )

    parser.add_argument("--type", dest="map_type", default="ghost_town",
                        help="Map type to generate (default: ghost_town)")
    parser.add_argument("--seed", type=int, default=None,
                        help="RNG seed for reproducibility (random if omitted)")
    parser.add_argument("--size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"),
                        default=[20, 15],
                        help="Map dimensions (default: 20 15)")
    parser.add_argument("--preview", action="store_true",
                        help="Print ASCII preview of the generated map")
    parser.add_argument("--export", metavar="FILE",
                        help="Export map as JSON to the specified file path")
    parser.add_argument("--describe", action="store_true",
                        help="Print the narrative description of the map")
    parser.add_argument("--list-types", action="store_true",
                        help="List all available map types and exit")

    args = parser.parse_args()

    if args.list_types:
        print("\nDustfall Map Types\n" + "=" * 40)
        for mtype, desc in list_map_types().items():
            print(f"  {mtype:<18} {desc}")
        print()
        return

    # Generate the map
    try:
        m = generate_map(args.map_type, seed=args.seed, size=tuple(args.size))
    except ValueError as e:
        print(f"Error: {e}")
        return

    print(f"\nGenerated: {m.map_type} | seed:{m.seed} | {m.width}x{m.height}")
    print(f"Town: {m.town_name} | Region: {m.region} | Faction: {m.faction}")

    # Count tile types for quick stats
    tile_counts: dict[str, int] = {}
    for row in m.tiles:
        for tile in row:
            tile_counts[tile] = tile_counts.get(tile, 0) + 1

    print(f"Spawns — Player: {len(m.get_spawn_points('player'))} | Enemy: {len(m.get_spawn_points('enemy'))}")
    print(f"Cover: {len(m.get_cover_positions())} | Loot: {len(m.get_loot_positions())} | Hazards: {len(m.get_hazard_positions())}")

    if args.describe:
        print(f"\n--- Narrative Description ---\n{m.describe()}\n")

    if args.preview:
        print()
        print(m.to_ascii())

    if args.export:
        export_path = Path(args.export)
        data = m.to_json()
        export_path.write_text(json.dumps(data, indent=2))
        print(f"\nExported to: {export_path.resolve()}")


if __name__ == "__main__":
    _cli_main()
