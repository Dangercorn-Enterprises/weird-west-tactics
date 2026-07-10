# DUSTFALL — economy datasheet (2026-07-10, generated from design.json)

*Analysis only, for the loot/economy session. Shop slices per town.gd (parity
with web): weapons[0:4] · armor[0:3] · consumables[0:3]. No prices changed.*

## Faucets (ALL income in the game)
- Starting gold: **300g**
- Marshal bounty (only repeatable income): **60 + 40×town_tier** → T1 100g · T2 140g · T3 180g; instant repeat, no cooldown
- Story battles, ambushes, boss reckonings: **0g** (XP/favor only)
- No selling, no loot drops, no other income.

- Marshal locations: 7/26 nodes: carson(T1), saltlake(T2), sandiego(T1), tucson(T1), tombstone(T2), elpaso(T2), sanantonio(T2)

## Sinks — one-time catalog (obtainable)

| item | price |
|---|---|
| Revolver | 60g |
| Rifle | 120g |
| Shotgun | 110g |
| Repeater | 100g |
| Leather Duster | 50g |
| Reinforced Vest | 120g |
| Ashfall Plating | 240g |
| Ashfall Chamber | 120g |
| Hair Trigger | 80g |
| Extended Barrel | 90g |
| Hollow Points | 100g |
| Horse Team | 150g |
| Camel Team | 220g |
| Clockwork Steed | 450g |

**One-copy total: 2010g.** Recruits: 90–160g each (roster cap 6 → up to 4 hires ≈ 500g).

### Kitting a full posse of 4
- Best-in-shop kit ×4 (Rifle + Ashfall Plating + Ashfall Chamber): **1920g**
- + best mount (Clockwork Steed): 450g (party-wide, one purchase)

## Sinks — recurring
- Doc heal: 40g (full party) · Saloon rest: 0g + 1 day (day counter is decorative — no cost)
- Bandages: 15g/use (consumable)
- Ashfall Charge: 40g/use (consumable)
- Smelling Salts: 25g/use (consumable)
- Shrine donation: 50g → +1 favor (the ONLY unbounded sink; favor caps in usefulness at ~3 per god)

## The unobtainable tail (statted, parity-tested, NO acquisition path)

| item | price | note |
|---|---|---|
| Ashfall Pistol | 200g | weapon |
| Steam Cannon | 260g | weapon |
| Hex Focus | 140g | weapon — ignoreCover |
| Blessed Vestments | 160g | armor |
| Clockwork Exo | 400g | armor |
| Tonic of Vigor | 30g | consumable (buff) — effect UNIMPLEMENTED |
| Holy Water | 35g | consumable (antiundead) — effect UNIMPLEMENTED |
| Coyote Dust | 50g | consumable (invis) — effect UNIMPLEMENTED |

Tail value if tier-unlocked at printed prices: **1160g** of gear (+consumables).

## The curve (why scarcity dies)
- Everything buyable once ≈ **2010g** ≈ **12 T3 bounties** (or ~21 T1).
- Best-kit-of-4 (1920g) ≈ 11 T3 bounties.
- Bounty pay never scales past tier; goods are finite; consumables + doc +
  shrine are the only recurring sinks (~<100g/fight even in heavy use).
- **Break-even point:** once the catalog is owned, every bounty is pure
  surplus — the audit's 'meaningless infinite faucet' point, now with numbers.

## Session levers (options, NOT recommendations — Njord's faucet≠sink catch stands)
- Prices are data (design.json cost fields) — repriceable without code.
- Tail items have prices already printed above — a tier-unlock needs only
  Tim's tier assignments + the slice change.
- Recurring-sink candidates seen in other memos: ammo, repair/durability,
  upkeep-per-day (day counter exists, reads nothing), boss uniques (drop, not
  purchase). Each changes the curve differently — session material.
