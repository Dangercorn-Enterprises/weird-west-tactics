// =============================================
// WEIRD WEST TACTICS — GAME DATA v0.2
// =============================================

const ARCHETYPES = [
  { id:'gunslinger', icon:'🔫', name:'Gunslinger',
    desc:'A dead-eye with a six-shooter and nerves of steel.',
    bonuses:'+2 Deftness, +1 Quickness', statBonus:{deftness:2,quickness:1},
    weapons:[{name:'Peacemaker',desc:'Reliable six-shooter. Solid range and accuracy.',damage:[4,8],range:6,apCost:2,accuracy:75},
             {name:'Bowie Knife',desc:'Up close and personal. Fast but short range.',damage:[3,6],range:1,apCost:1,accuracy:85}],
    abilities:[],
    lore:'They say every bullet you fire carves a notch in your soul. You stopped counting a long time ago.' },
  { id:'hexslinger', icon:'🃏', name:'Hexslinger',
    desc:'Gambles with dark spirits for arcane power — and sometimes wins.',
    bonuses:'+2 Cognition, +1 Spirit', statBonus:{cognition:2,spirit:1},
    weapons:[{name:'Hex Bolt',desc:'Channels dark energy. Partially ignores cover.',damage:[3,7],range:5,apCost:2,accuracy:70},
             {name:'Derringer',desc:'Tiny holdout pistol. Last resort.',damage:[2,5],range:3,apCost:1,accuracy:65}],
    abilities:[{name:'Soul Drain',type:'heal',desc:'Steals life force from the void to mend wounds.',amount:[4,8],range:3,apCost:2}],
    lore:'You learned the old ways — dealing with spirits, playing poker for power. They always want a rematch.' },
  { id:'tinkerer', icon:'⚙', name:'Tinkerer',
    desc:'A genius inventor fueled by strange minerals and questionable sanity.',
    bonuses:'+2 Knowledge, +1 Cognition', statBonus:{knowledge:2,cognition:1},
    weapons:[{name:'Arc Pistol',desc:'Experimental energy weapon. High damage, unreliable.',damage:[5,12],range:5,apCost:2,accuracy:58},
             {name:'Wrench',desc:'Heavy tool. Surprisingly effective in melee.',damage:[2,5],range:1,apCost:1,accuracy:80}],
    abilities:[{name:'Deploy Turret',type:'turret',desc:'Places an auto-gun turret. Fires at enemies each turn. Limit: 1 active.',apCost:3,range:3,maxTurrets:1}],
    lore:'The strange ore whispers blueprints in your dreams. Machines that shouldn\'t work. But they do.' },
  { id:'preacher', icon:'✝', name:'Preacher',
    desc:'A person of faith whose prayers carry real, tangible power.',
    bonuses:'+2 Spirit, +1 Vigor', statBonus:{spirit:2,vigor:1},
    weapons:[{name:'Shotgun',desc:'Devastating at close range. Spread compensates for aim.',damage:[5,10],range:4,apCost:2,accuracy:65},
             {name:'Holy Smite',desc:'Divine wrath channeled through faith.',damage:[3,7],range:5,apCost:2,accuracy:70}],
    abilities:[{name:'Lay on Hands',type:'heal',desc:'Channel divine energy to mend an ally\'s wounds.',amount:[5,10],range:3,apCost:2}],
    lore:'When the world broke, your faith didn\'t. It hardened into something the darkness can\'t abide.' },
  { id:'lawdog', icon:'⭐', name:'Law Dog',
    desc:'Badge-carrying enforcer of order in a lawless world.',
    bonuses:'+2 Vigor, +1 Mien', statBonus:{vigor:2,mien:1},
    weapons:[{name:'Lever-Action Rifle',desc:'Reliable and accurate. Good range.',damage:[4,9],range:7,apCost:2,accuracy:72},
             {name:'Pistol Whip',desc:'Crack \'em with the butt of your gun.',damage:[2,5],range:1,apCost:1,accuracy:82}],
    abilities:[],
    lore:'The law may be dead everywhere else. But it ain\'t dead in you.' },
  { id:'drifter', icon:'🌵', name:'Drifter',
    desc:'A wanderer and survivor. No home — just instinct.',
    bonuses:'+1 Nimbleness, +1 Quickness, +1 Cognition', statBonus:{nimbleness:1,quickness:1,cognition:1},
    weapons:[{name:'Sawed-Off',desc:'Short range, high impact. Built for ambushes.',damage:[4,10],range:3,apCost:2,accuracy:68},
             {name:'Survival Knife',desc:'Kept sharp and always within reach.',damage:[3,6],range:1,apCost:1,accuracy:83}],
    abilities:[],
    lore:'You\'ve walked the wastes end to end. You don\'t belong anywhere — and that\'s kept you alive.' }
];

const STATS = [
  {id:'deftness',name:'Deftness',desc:'Shooting accuracy, hand-eye coordination'},
  {id:'nimbleness',name:'Nimbleness',desc:'Dodge chance, agility, climbing'},
  {id:'strength',name:'Strength',desc:'Melee damage bonus, carrying capacity'},
  {id:'quickness',name:'Quickness',desc:'Initiative, reaction speed, action points'},
  {id:'vigor',name:'Vigor',desc:'Health pool, damage resistance, endurance'},
  {id:'cognition',name:'Cognition',desc:'Perception, awareness, ability accuracy'},
  {id:'knowledge',name:'Knowledge',desc:'Crafting, science, medicine, lore'},
  {id:'mien',name:'Mien',desc:'Charisma, intimidation, leadership'},
  {id:'spirit',name:'Spirit',desc:'Willpower, guts, resistance to fear/magic'}
];

const EDGES = [
  {id:'nerves',name:'Nerves of Steel',effect:'Immune to fear effects below Terror 3',cost:2},
  {id:'fleet',name:'Fleet-Footed',effect:'+1 movement range per turn',cost:1},
  {id:'thick',name:'Thick Skinned',effect:'+2 damage resistance',cost:2},
  {id:'lucky',name:'Devil\'s Own Luck',effect:'Re-roll one failed check per encounter',cost:3},
  {id:'quick_draw',name:'Quick Draw',effect:'+3 initiative on first turn',cost:2},
  {id:'ghost_sight',name:'Ghost Sight',effect:'Can see invisible and ethereal beings',cost:2},
  {id:'belongings',name:'Belongings',effect:'Start with an extra rare item',cost:1},
  {id:'veteran',name:'Veteran',effect:'+1 to all stats (max 10)',cost:4}
];

const HINDRANCES = [
  {id:'wanted',name:'Wanted',effect:'Bounty hunters pursue you regularly',reward:2},
  {id:'nightmares',name:'Night Terrors',effect:'Reduced healing from rest',reward:1},
  {id:'oath',name:'Oath',effect:'Bound to a code you cannot break',reward:1},
  {id:'haunted',name:'Haunted',effect:'A dark spirit whispers to you. It wants control.',reward:3},
  {id:'lame',name:'Lame',effect:'-1 movement range permanently',reward:2},
  {id:'bloodthirsty',name:'Bloodthirsty',effect:'Must pass Spirit check to show mercy',reward:2},
  {id:'poverty',name:'Poverty',effect:'Start with minimal equipment',reward:1},
  {id:'enemy',name:'Enemy',effect:'A powerful foe is hunting you',reward:2}
];

const PREGEN = {
  gunslinger:{name:'Silas Crowe',stats:{deftness:8,nimbleness:5,strength:4,quickness:7,vigor:5,cognition:4,knowledge:2,mien:3,spirit:4}},
  hexslinger:{name:'Mama Josette',stats:{deftness:4,nimbleness:4,strength:2,quickness:5,vigor:4,cognition:7,knowledge:5,mien:4,spirit:7}},
  tinkerer:{name:'Doc Kettleman',stats:{deftness:5,nimbleness:3,strength:3,quickness:5,vigor:4,cognition:6,knowledge:8,mien:2,spirit:3}},
  preacher:{name:'Sister Mara',stats:{deftness:4,nimbleness:4,strength:3,quickness:5,vigor:6,cognition:4,knowledge:4,mien:4,spirit:8}},
  lawdog:{name:'Marshal Tom Bell',stats:{deftness:6,nimbleness:4,strength:5,quickness:5,vigor:7,cognition:5,knowledge:3,mien:6,spirit:3}},
  drifter:{name:'Coyote Jane',stats:{deftness:5,nimbleness:6,strength:4,quickness:6,vigor:5,cognition:6,knowledge:3,mien:3,spirit:4}}
};

const COVER_DEF = {0:0, 2:40, 3:20};
const COVER_LABELS = {0:'No Cover', 2:'Full Cover (+40% defense)', 3:'Half Cover (+20% defense)'};
const TERRAIN_ICONS = {1:'🪨', 2:'🪵', 3:'🌵'};

const GRID_W = 12, GRID_H = 10;

const MAP = [
  [0,0,0,0,0,0,0,0,0,0,0,0],
  [0,0,0,3,0,0,0,0,3,0,0,0],
  [0,0,0,0,0,2,2,0,0,0,0,0],
  [0,3,0,0,0,1,1,0,0,0,3,0],
  [0,0,0,0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0,0,0,0],
  [0,3,0,0,0,1,1,0,0,0,3,0],
  [0,0,0,0,0,2,2,0,0,0,0,0],
  [0,0,0,3,0,0,0,0,3,0,0,0],
  [0,0,0,0,0,0,0,0,0,0,0,0],
];

function createEnemies() {
  return [
    { id:'e0',name:'Walkin\' Dead',cls:'Undead',icon:'💀',x:10,y:1,
      hp:12,maxHp:12,ap:3,maxAp:3,
      stats:{deftness:3,nimbleness:3,strength:6,quickness:3,vigor:8,cognition:2,knowledge:1,mien:1,spirit:1},
      weapons:[{name:'Rusty Claws',desc:'Rotten fingers that still rend flesh.',damage:[3,6],range:1,apCost:1,accuracy:70}],
      abilities:[],edges:[],hindrances:[],hunkered:false,overwatch:false,turretsDeployed:0 },
    { id:'e1',name:'Rattlesnake Bill',cls:'Outlaw',icon:'🤠',x:10,y:3,
      hp:16,maxHp:16,ap:4,maxAp:4,
      stats:{deftness:7,nimbleness:6,strength:5,quickness:6,vigor:5,cognition:5,knowledge:3,mien:4,spirit:4},
      weapons:[{name:'Winchester',desc:'Well-oiled rifle.',damage:[4,9],range:7,apCost:2,accuracy:70},
               {name:'Boot Knife',desc:'Hidden blade.',damage:[2,5],range:1,apCost:1,accuracy:80}],
      abilities:[],edges:[],hindrances:[],hunkered:false,overwatch:false,turretsDeployed:0 },
    { id:'e2',name:'Iron Sentinel',cls:'Automaton',icon:'🤖',x:10,y:5,
      hp:22,maxHp:22,ap:3,maxAp:3,
      stats:{deftness:6,nimbleness:2,strength:8,quickness:4,vigor:10,cognition:4,knowledge:1,mien:0,spirit:0},
      weapons:[{name:'Steam Cannon',desc:'Pressurized death.',damage:[6,14],range:5,apCost:2,accuracy:55},
               {name:'Crushing Arm',desc:'Hydraulic force.',damage:[4,8],range:1,apCost:1,accuracy:75}],
      abilities:[],edges:[],hindrances:[],hunkered:false,overwatch:false,turretsDeployed:0 },
    { id:'e3',name:'Shade',cls:'Spirit',icon:'👻',x:10,y:7,
      hp:10,maxHp:10,ap:5,maxAp:5,
      stats:{deftness:5,nimbleness:8,strength:2,quickness:8,vigor:3,cognition:6,knowledge:3,mien:5,spirit:7},
      weapons:[{name:'Spectral Touch',desc:'Chilling grasp from beyond.',damage:[2,6],range:1,apCost:1,accuracy:80}],
      abilities:[],edges:[],hindrances:[],hunkered:false,overwatch:false,turretsDeployed:0 }
  ];
}

function makeUnit(charData, idx, side) {
  const arch = ARCHETYPES.find(a => a.id === charData.archetype) || ARCHETYPES[0];
  const stats = {};
  STATS.forEach(s => {
    stats[s.id] = 3; // default
    if (charData.stats) {
      if (charData.stats[s.id] !== undefined) stats[s.id] = charData.stats[s.id];
      if (charData.stats[s.name] !== undefined) stats[s.id] = charData.stats[s.name];
    }
  });
  const baseAp = 3 + Math.floor(stats.quickness / 4);
  const baseHp = 10 + stats.vigor * 2;
  return {
    id:`${side}${idx}`, name:charData.name||arch.name, cls:arch.name, icon:arch.icon,
    archetype:arch.id, x:side==='p'?1:10, y:side==='p'?[1,4,7][idx]:[1,3,5,7][idx],
    hp:baseHp, maxHp:baseHp, ap:baseAp, maxAp:baseAp, stats,
    weapons:JSON.parse(JSON.stringify(arch.weapons)),
    abilities:arch.abilities?JSON.parse(JSON.stringify(arch.abilities)):[],
    edges:charData.edges||[], hindrances:charData.hindrances||[],
    hunkered:false, overwatch:false, turretsDeployed:0
  };
}
