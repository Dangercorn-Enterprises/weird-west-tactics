// =============================================
// DUSTFALL — HAUNTS SYSTEM v0.1
// Procedural supernatural encounter generator
// =============================================
//
// A "Haunt" is an encounter in the Ashen Frontier. It has:
//   - theme (the flavor: undead, automaton, eldritch, indigenous, frontier, environmental)
//   - location (dust town, canyon, rail line, ghost-rock mine, prairie, sanitarium)
//   - tier (1-5, difficulty scaling)
//   - enemies (roster, scaled to party size & tier)
//   - special_rule (one extra mechanic unique to this haunt)
//   - lore (narrative hook the GM reads aloud)
//   - loot_table (rewards on victory)
//
// The generator chooses theme + location compatible pairs, scales enemies to
// the party, and emits a JSON blob compatible with tactical-combat.html's
// createUnits() / state shape.

// =============================================
// BESTIARY — expanded enemies for the Haunt system
// =============================================
const HAUNTS_BESTIARY = {
  // --- UNDEAD ---
  walking_dead: {
    name: "Walkin' Dead",
    cls: "Undead",
    icon: "💀",
    hp: 12,
    ap: 3,
    stats: { deftness: 3, nimbleness: 3, quickness: 3, vigor: 8, spirit: 1 },
    weapons: [
      {
        name: "Rusty Claws",
        damage: [3, 6],
        range: 1,
        apCost: 1,
        accuracy: 70,
      },
    ],
    flavor:
      "Shambling, hungry, and patient. Bullets don't kill what was never alive.",
    tier: 1,
  },
  gravedigger: {
    name: "The Gravedigger",
    cls: "Undead",
    icon: "⚰",
    hp: 22,
    ap: 4,
    stats: { deftness: 5, nimbleness: 4, quickness: 4, vigor: 12, spirit: 6 },
    weapons: [
      {
        name: "Rusted Shovel",
        damage: [5, 10],
        range: 1,
        apCost: 2,
        accuracy: 80,
      },
      { name: "Grave Dust", damage: [3, 5], range: 3, apCost: 1, accuracy: 65 },
    ],
    special: "Heals 2 HP per turn while adjacent to a corpse.",
    flavor: "He buries them. Then he unburies them. Then they follow him.",
    tier: 3,
  },
  wraith: {
    name: "Prairie Wraith",
    cls: "Undead",
    icon: "👻",
    hp: 8,
    ap: 5,
    stats: { deftness: 5, nimbleness: 9, quickness: 9, vigor: 3, spirit: 8 },
    weapons: [
      {
        name: "Spectral Claw",
        damage: [2, 7],
        range: 1,
        apCost: 1,
        accuracy: 85,
      },
    ],
    special:
      "Ignores cover. Immune to normal bullets (needs Spirit-infused weapons or Hex Bolts).",
    flavor: "Cold breath on your neck. Then nothing. Then the bleeding starts.",
    tier: 2,
  },

  // --- AUTOMATON ---
  hellstromme_drone: {
    name: "Hellstromme Drone",
    cls: "Automaton",
    icon: "🤖",
    hp: 20,
    ap: 3,
    stats: { deftness: 6, nimbleness: 2, quickness: 4, vigor: 10, spirit: 0 },
    weapons: [
      {
        name: "Steam Cannon",
        damage: [6, 14],
        range: 5,
        apCost: 2,
        accuracy: 55,
      },
      {
        name: "Crushing Arm",
        damage: [4, 8],
        range: 1,
        apCost: 1,
        accuracy: 75,
      },
    ],
    flavor:
      "Built in Pittsburgh from ghost-rock and brass. You can hear it a mile off.",
    tier: 2,
  },
  iron_scorpion: {
    name: "Iron Scorpion",
    cls: "Automaton",
    icon: "🦂",
    hp: 14,
    ap: 5,
    stats: { deftness: 7, nimbleness: 6, quickness: 7, vigor: 6, spirit: 0 },
    weapons: [
      { name: "Venom Dart", damage: [3, 7], range: 4, apCost: 1, accuracy: 75 },
      { name: "Stinger", damage: [5, 9], range: 1, apCost: 2, accuracy: 80 },
    ],
    special: "Dart injects a toxin — target loses 1 AP next turn.",
    flavor:
      "A clockwork thing with a soul the size of a pinhead. It doesn't tire.",
    tier: 3,
  },
  boiler_walker: {
    name: "Boiler Walker",
    cls: "Automaton",
    icon: "🔥",
    hp: 32,
    ap: 3,
    stats: { deftness: 4, nimbleness: 1, quickness: 3, vigor: 14, spirit: 0 },
    weapons: [
      {
        name: "Flamethrower",
        damage: [7, 12],
        range: 3,
        apCost: 3,
        accuracy: 70,
      },
      { name: "Steam Vent", damage: [4, 6], range: 2, apCost: 1, accuracy: 85 },
    ],
    special:
      "When HP drops below 25%, explodes on its next turn for 10-18 damage in 2-tile radius.",
    flavor: "The shell holds steam at eight times pressure. You do the math.",
    tier: 4,
  },

  // --- FRONTIER ---
  outlaw_grunt: {
    name: "Saddle Bum",
    cls: "Outlaw",
    icon: "🤠",
    hp: 10,
    ap: 4,
    stats: { deftness: 5, nimbleness: 4, quickness: 4, vigor: 4, spirit: 3 },
    weapons: [
      {
        name: "Rusted Pistol",
        damage: [3, 6],
        range: 5,
        apCost: 2,
        accuracy: 55,
      },
      { name: "Knife", damage: [2, 5], range: 1, apCost: 1, accuracy: 75 },
    ],
    flavor: "A rider who chose the wrong trail. Still chose it, though.",
    tier: 1,
  },
  rattlesnake_bill: {
    name: "Rattlesnake Bill",
    cls: "Outlaw",
    icon: "🐍",
    hp: 16,
    ap: 4,
    stats: { deftness: 7, nimbleness: 6, quickness: 6, vigor: 5, spirit: 4 },
    weapons: [
      { name: "Winchester", damage: [4, 9], range: 7, apCost: 2, accuracy: 70 },
      { name: "Boot Knife", damage: [2, 5], range: 1, apCost: 1, accuracy: 80 },
    ],
    flavor:
      "Thirty-seven notches on his rifle. He'll take your notch count too.",
    tier: 2,
  },
  the_sheriff: {
    name: "Sheriff McClure",
    cls: "Outlaw",
    icon: "⭐",
    hp: 24,
    ap: 5,
    stats: { deftness: 8, nimbleness: 5, quickness: 6, vigor: 7, spirit: 6 },
    weapons: [
      { name: "Long Colt", damage: [5, 10], range: 6, apCost: 2, accuracy: 80 },
      { name: "Sawed-Off", damage: [4, 9], range: 3, apCost: 2, accuracy: 75 },
    ],
    special: "Rallies adjacent outlaws: +10 accuracy to their next shot.",
    flavor: "Wears a star that hasn't meant anything in ten years.",
    tier: 4,
  },

  // --- HARROWED (possessed / haunted beings) ---
  ghost_rider: {
    name: "Ghost Rider",
    cls: "Harrowed",
    icon: "🐎",
    hp: 18,
    ap: 6,
    stats: { deftness: 7, nimbleness: 8, quickness: 9, vigor: 5, spirit: 7 },
    weapons: [
      {
        name: "Flaming Lance",
        damage: [5, 11],
        range: 2,
        apCost: 2,
        accuracy: 75,
      },
    ],
    special:
      "Moves 2 tiles per 1 AP (mounted). Leaves a 1-tile fire trail behind.",
    flavor: "A rider whose horse died and rode on anyway.",
    tier: 3,
  },
  preachers_shadow: {
    name: "Preacher's Shadow",
    cls: "Harrowed",
    icon: "🕯",
    hp: 14,
    ap: 4,
    stats: { deftness: 5, nimbleness: 7, quickness: 7, vigor: 4, spirit: 9 },
    weapons: [
      {
        name: "Unholy Words",
        damage: [4, 8],
        range: 4,
        apCost: 2,
        accuracy: 70,
      },
    ],
    special:
      "Players within 2 tiles suffer -2 to their accuracy (prayer-cloud aura).",
    flavor: "What's left of a man who broke a vow to something older than God.",
    tier: 3,
  },

  // --- INDIGENOUS MYTH ---
  thunderbird_chick: {
    name: "Thunderbird Fledgling",
    cls: "Myth",
    icon: "🦅",
    hp: 16,
    ap: 6,
    stats: { deftness: 6, nimbleness: 9, quickness: 9, vigor: 5, spirit: 6 },
    weapons: [
      {
        name: "Lightning Cry",
        damage: [4, 9],
        range: 5,
        apCost: 2,
        accuracy: 70,
      },
      { name: "Talons", damage: [3, 6], range: 1, apCost: 1, accuracy: 80 },
    ],
    special:
      "Flying — ignores terrain. Thunderclap (once per fight): stuns all within 2 tiles for 1 turn.",
    flavor: "Its parent hasn't returned yet. It's hungry. It's angry.",
    tier: 4,
  },
  wendigo: {
    name: "Wendigo",
    cls: "Myth",
    icon: "🦌",
    hp: 36,
    ap: 5,
    stats: { deftness: 5, nimbleness: 7, quickness: 6, vigor: 12, spirit: 7 },
    weapons: [
      { name: "Hunger", damage: [7, 14], range: 1, apCost: 2, accuracy: 75 },
    ],
    special:
      "Inflicts 'Cold Dread' on hit: target loses 1 Spirit permanently (save on Spirit check).",
    flavor: "Once a man. Then he ate his kin. Now he cannot stop.",
    tier: 5,
  },

  // --- ELDRITCH ---
  void_eye: {
    name: "Void Eye",
    cls: "Eldritch",
    icon: "👁",
    hp: 8,
    ap: 3,
    stats: { deftness: 2, nimbleness: 2, quickness: 4, vigor: 3, spirit: 10 },
    weapons: [
      { name: "Gaze", damage: [3, 9], range: 6, apCost: 1, accuracy: 90 },
    ],
    special:
      "Looking at it costs 1 Spirit per turn. Cannot be blinded. Ignores cover.",
    flavor:
      "It's not an animal. It's the IDEA of being seen. It should not be here.",
    tier: 4,
  },
  dustskin: {
    name: "Dustskin",
    cls: "Eldritch",
    icon: "🌫",
    hp: 22,
    ap: 4,
    stats: { deftness: 4, nimbleness: 8, quickness: 6, vigor: 7, spirit: 8 },
    weapons: [
      {
        name: "Suffocating Grasp",
        damage: [4, 8],
        range: 1,
        apCost: 2,
        accuracy: 80,
      },
    ],
    special:
      "Half damage from bullets (dust reconstitutes). Full damage from fire or spirit weapons.",
    flavor: "It wears a man's shape, filled with the sand of forty graves.",
    tier: 4,
  },
};

// =============================================
// HAUNTS — encounter templates
// =============================================
const HAUNTS = [
  {
    id: "drowned_preacher",
    name: "The Drowned Preacher",
    tier: 3,
    theme: "undead",
    locations: ["dust_town", "sanitarium"],
    lore: "The flood came in 1872. Pastor Whitt stood on the pulpit as the water rose. He's still preaching.",
    roster: (tier) => [
      { tpl: "preachers_shadow", count: 1 },
      { tpl: "walking_dead", count: 2 + Math.floor(tier / 2) },
    ],
    special_rule: {
      name: "Holy Ground",
      desc: "If the Preacher is defeated while a player occupies the pulpit tile (center of map), that player gains +1 to all Spirit checks for the rest of the campaign.",
    },
    loot_table: [
      {
        item: "Waterlogged Bible",
        rarity: "uncommon",
        effect: "+1 Spirit once per rest",
      },
      {
        item: "Silver Cross",
        rarity: "rare",
        effect: "Spirit-weapon tag on melee attacks",
      },
    ],
  },
  {
    id: "iron_graveyard",
    name: "The Iron Graveyard",
    tier: 4,
    theme: "automaton",
    locations: ["canyon", "ghost_rock_mine"],
    lore: "Hellstromme Industries buried its failures out here. The failures kept working.",
    roster: (tier) => [
      { tpl: "boiler_walker", count: 1 },
      { tpl: "hellstromme_drone", count: 2 },
      { tpl: "iron_scorpion", count: Math.max(1, tier - 2) },
    ],
    special_rule: {
      name: "Ghost-Rock Veins",
      desc: "Highlighted tiles are ghost-rock outcrops. Standing on one restores 1 AP at turn start, but deals 2 HP/turn (radiation).",
    },
    loot_table: [
      {
        item: "Raw Ghost-Rock",
        rarity: "common",
        effect: "Crafting component",
      },
      {
        item: "Intact Drone Core",
        rarity: "rare",
        effect: "Tinkerer can build a turret in 1 turn (vs 3)",
      },
    ],
  },
  {
    id: "the_9_12_from_hellstromme",
    name: "The 9:12 from Hellstromme",
    tier: 4,
    theme: "harrowed",
    locations: ["rail_line"],
    lore: "The train left Pittsburgh on time. It has not arrived. You are on it now. The conductor punches your ticket — three red holes.",
    roster: (tier) => [
      { tpl: "ghost_rider", count: 1 },
      { tpl: "walking_dead", count: 3 },
      { tpl: "wraith", count: 1 + Math.floor(tier / 3) },
    ],
    special_rule: {
      name: "Moving Train",
      desc: "The map scrolls 1 tile toward the left each enemy turn. Units that fall off the east edge are Gone.",
    },
    loot_table: [
      {
        item: "Conductor's Watch",
        rarity: "rare",
        effect: "+3 initiative on first turn (Quick Draw stacks)",
      },
      {
        item: "Engineer's Cap",
        rarity: "uncommon",
        effect: "Immune to Cold Dread",
      },
    ],
  },
  {
    id: "thunder_roost",
    name: "Thunder Roost",
    tier: 5,
    theme: "myth",
    locations: ["canyon", "prairie"],
    lore: "The elders warned you. The rocks are thunder-stones; this is the Thunderbird's nest. Something is very hungry.",
    roster: (tier) => [
      { tpl: "thunderbird_chick", count: 1 },
      { tpl: "wraith", count: 2 },
    ],
    special_rule: {
      name: "Electric Air",
      desc: "Every ranged weapon fired gets +10% crit chance but -10% accuracy. Metal armor: 50% chance to draw one Lightning Cry automatically to the wearer per turn.",
    },
    loot_table: [
      {
        item: "Thunder-stone",
        rarity: "legendary",
        effect: "+2 damage to all electrical/lightning attacks",
      },
      {
        item: "Fledgling Feather",
        rarity: "rare",
        effect: "Grants 1 use of 'Flight' (move across impassable terrain)",
      },
    ],
  },
  {
    id: "dust_storm_ambush",
    name: "The Dust Storm",
    tier: 2,
    theme: "frontier",
    locations: ["prairie", "dust_town"],
    lore: "A twister rolls in out of the south. Bandits use the cover. You don't.",
    roster: (tier) => [
      { tpl: "rattlesnake_bill", count: 1 },
      { tpl: "outlaw_grunt", count: 3 + tier },
    ],
    special_rule: {
      name: "Zero Visibility",
      desc: "Sight range capped at 3 tiles. Ranged attacks beyond 3 tiles auto-miss. Stealth class bonuses doubled.",
    },
    loot_table: [
      { item: "Bandit Cache", rarity: "common", effect: "$50 or 1 weapon mod" },
      {
        item: "Rattlesnake's Bandana",
        rarity: "uncommon",
        effect: "+1 accuracy in dust storms",
      },
    ],
  },
  {
    id: "the_last_sermon",
    name: "The Last Sermon",
    tier: 3,
    theme: "undead",
    locations: ["dust_town", "sanitarium"],
    lore: "The congregation gathers every Sunday. They died in 1879. They are still here.",
    roster: (tier) => [
      { tpl: "preachers_shadow", count: 1 },
      { tpl: "walking_dead", count: 4 + Math.floor(tier / 2) },
      { tpl: "gravedigger", count: 1 },
    ],
    special_rule: {
      name: "Sacred Echo",
      desc: "Preacher-archetype players gain +2 damage and can cast Lay on Hands at 0 AP cost. Others suffer -1 Spirit while in the church.",
    },
    loot_table: [
      {
        item: "Tarnished Chalice",
        rarity: "uncommon",
        effect: "Heal 2 HP once per rest",
      },
      {
        item: "The Sermon Book",
        rarity: "rare",
        effect: "Preacher learns 'Holy Smite'",
      },
    ],
  },
  {
    id: "cracked_earth",
    name: "Cracked Earth",
    tier: 5,
    theme: "eldritch",
    locations: ["canyon", "ghost_rock_mine"],
    lore: "The canyon opened wider last night. Things crawled out. They wear our shapes but they are not ours.",
    roster: (tier) => [
      { tpl: "void_eye", count: 2 },
      { tpl: "dustskin", count: 2 },
      { tpl: "wendigo", count: Math.max(1, Math.floor(tier / 3)) },
    ],
    special_rule: {
      name: "Reality Thin",
      desc: "At the end of each round, roll 1d6 per player. On a 1, that player swaps positions with a random unit on the map. On a 6, gains 1 AP next turn.",
    },
    loot_table: [
      {
        item: "Fragment of Elsewhere",
        rarity: "legendary",
        effect: "Once per session: relocate any unit 5 tiles",
      },
      {
        item: "Dust-Silk Scarf",
        rarity: "rare",
        effect: "Immune to one status effect per encounter",
      },
    ],
  },
  {
    id: "outlaw_ambush",
    name: "The Hanging Tree",
    tier: 1,
    theme: "frontier",
    locations: ["prairie"],
    lore: "A man swings from the big oak. He's been there a week. Watching. His friends are in the rocks.",
    roster: (tier) => [{ tpl: "outlaw_grunt", count: 3 + tier }],
    special_rule: {
      name: "Cover Rich",
      desc: "All rocks on the map provide +30% cover (normal: 20%).",
    },
    loot_table: [
      {
        item: "Outlaw's Boots",
        rarity: "common",
        effect: "+1 movement on dirt tiles",
      },
      {
        item: "Noose",
        rarity: "uncommon",
        effect: "Used as a rope tool: climb walls or lasso (1 AP)",
      },
    ],
  },
  {
    id: "cold_mine",
    name: "The Cold Mine",
    tier: 4,
    theme: "myth",
    locations: ["ghost_rock_mine"],
    lore: "The miners came out and wouldn't stop shivering. The ones who went back in never came out.",
    roster: (tier) => [
      { tpl: "wendigo", count: 1 },
      { tpl: "wraith", count: 2 + Math.floor(tier / 3) },
    ],
    special_rule: {
      name: "Cold Dread",
      desc: "Every player loses 1 Spirit per round (save on 3+ d6). At 0 Spirit, player becomes 'Numb' — cannot use abilities but takes -2 damage.",
    },
    loot_table: [
      {
        item: "Wendigo Claw",
        rarity: "rare",
        effect: "+2 damage to Myth-class enemies",
      },
      {
        item: "Miner's Flask",
        rarity: "common",
        effect: "Removes one Cold Dread stack per use",
      },
    ],
  },
  {
    id: "failed_experiment",
    name: "The Failed Experiment",
    tier: 3,
    theme: "automaton",
    locations: ["sanitarium"],
    lore: "Dr. Strycker's lab went quiet six months ago. The rumbling, however, never stopped. Someone should check.",
    roster: (tier) => [
      { tpl: "hellstromme_drone", count: 1 },
      { tpl: "iron_scorpion", count: 2 + Math.floor(tier / 2) },
      { tpl: "boiler_walker", count: Math.max(0, tier - 3) },
    ],
    special_rule: {
      name: "Steam Pipes",
      desc: "Attacking a pipe tile (highlighted) vents scalding steam, dealing 4-8 damage in 3-tile area and destroying the pipe.",
    },
    loot_table: [
      {
        item: "Dr. Strycker's Notes",
        rarity: "rare",
        effect: "Tinkerer unlocks 'Arc Pistol' upgrade",
      },
      { item: "Gear Assembly", rarity: "common", effect: "Crafting component" },
    ],
  },
];

// =============================================
// LOCATIONS (maps / environments)
// =============================================
const HAUNT_LOCATIONS = {
  dust_town: {
    name: "Dust Town",
    desc: "A dying settlement. Broken buildings, narrow streets.",
  },
  canyon: {
    name: "Red Canyon",
    desc: "High walls, sharp drops, abundant cover behind rocks.",
  },
  rail_line: {
    name: "The Rail Line",
    desc: "A stretch of the Transcontinental. Exposed, windy.",
  },
  ghost_rock_mine: {
    name: "Ghost-Rock Mine",
    desc: "Tunnels and shafts, ghost-rock veins everywhere.",
  },
  prairie: {
    name: "Open Prairie",
    desc: "Flat grassland. Minimal cover. Long sight lines.",
  },
  sanitarium: {
    name: "The Sanitarium",
    desc: "A ruin that was a hospital. Or was it?",
  },
};

// =============================================
// GENERATOR
// =============================================
/**
 * Generate a Haunt encounter.
 * @param {Object} opts
 *   tier: 1-5 (party power level)
 *   theme: optional lock to one theme; else random
 *   location: optional lock to one location; else picked from haunt's compatible list
 *   seed: optional number for reproducibility
 */
function generateHaunt(opts = {}) {
  const tier = Math.max(1, Math.min(5, opts.tier || 2));

  // Pick a haunt compatible with the tier (within ±1 tier)
  let candidates = HAUNTS.filter((h) => Math.abs(h.tier - tier) <= 1);
  if (opts.theme) candidates = candidates.filter((h) => h.theme === opts.theme);
  if (!candidates.length) candidates = HAUNTS;

  const rand = mulberry32(opts.seed || Date.now());
  const haunt = candidates[Math.floor(rand() * candidates.length)];

  // Pick location
  const locations = haunt.locations || Object.keys(HAUNT_LOCATIONS);
  let locId = opts.location;
  if (!locId || !locations.includes(locId)) {
    locId = locations[Math.floor(rand() * locations.length)];
  }
  const location = { id: locId, ...HAUNT_LOCATIONS[locId] };

  // Build enemy roster
  const roster =
    typeof haunt.roster === "function" ? haunt.roster(tier) : haunt.roster;
  const enemies = [];
  let idCounter = 1;
  for (const entry of roster) {
    const tpl = HAUNTS_BESTIARY[entry.tpl];
    if (!tpl) continue;
    for (let i = 0; i < entry.count; i++) {
      const e = {
        id: `e${idCounter++}`,
        name: tpl.name,
        cls: tpl.cls,
        icon: tpl.icon,
        x: 8 + Math.floor(rand() * 4),
        y: 1 + Math.floor(rand() * 7),
        hp: tpl.hp,
        maxHp: tpl.hp,
        ap: tpl.ap,
        maxAp: tpl.ap,
        stats: { ...tpl.stats },
        weapons: JSON.parse(JSON.stringify(tpl.weapons)),
        special: tpl.special || null,
        flavor: tpl.flavor || null,
      };
      enemies.push(e);
    }
  }

  return {
    haunt_id: haunt.id,
    name: haunt.name,
    tier,
    theme: haunt.theme,
    location,
    lore: haunt.lore,
    special_rule: haunt.special_rule,
    enemies,
    loot_table: haunt.loot_table || [],
    generated_at: new Date().toISOString(),
  };
}

// Seeded PRNG (mulberry32) — deterministic if seed provided
function mulberry32(a) {
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Export for Node (scheduler / tooling). Browser: globals.
if (typeof module !== "undefined" && module.exports) {
  module.exports = { HAUNTS, HAUNTS_BESTIARY, HAUNT_LOCATIONS, generateHaunt };
}
