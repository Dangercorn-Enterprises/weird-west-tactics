# DUSTFALL — tuning dial map (2026-07-10, 1000 runs/cell, seed 1337)

*Analysis only — no game data changed. Player = positional bot (upper-bound-ish;
humans land below, so treat IN-BAND cells as "at most this hard"). Bands:
story 0.7–0.85 · ambush 0.8–0.9 · boss 0.45–0.65.
**bold** = cell lands in its band. XP = avg kills×10 + 25×WR (gross inflow to
the deployed pool per fight — watch it climb with hp dials: longer fights vs
the Deacon mean more raised adds killed). ±~1.6pt CI at 1000 runs.*


## Dial: enemy HP ×mult

| encounter (band) | ×1.0 | ×1.1 | ×1.2 | ×1.3 | ×1.4 | ×1.5 |
|---|---|---|---|---|---|---|
| skirmish (story) | 100.0% r3.8 k4.0 xp65 | 100.0% r3.9 k4.0 xp65 | 100.0% r4.0 k4.0 xp65 | 99.9% r4.2 k4.0 xp65 | 99.8% r4.3 k4.0 xp65 | 100.0% r4.2 k4.0 xp65 |
| vanguard (story) | 99.0% r3.6 k4.0 xp65 | 98.4% r3.7 k4.0 xp64 | 98.8% r3.8 k4.0 xp64 | 98.8% r3.9 k4.0 xp65 | 95.7% r4.1 k3.9 xp63 | 94.8% r4.2 k3.9 xp63 |
| deacon (boss) | 75.9% r6.4 k6.1 xp80 | 75.4% r6.5 k6.1 xp80 | 74.7% r6.6 k6.1 xp80 | 75.4% r6.7 k6.1 xp80 | **55.9% r6.5 k5.7 xp71** | 44.8% r6.5 k5.3 xp64 |
| foreman (boss) | 96.9% r6.9 k4.8 xp72 | 93.8% r7.2 k4.8 xp71 | 91.3% r7.7 k4.8 xp71 | 87.6% r8.0 k4.7 xp69 | 85.9% r8.4 k4.7 xp69 | 83.9% r8.2 k4.7 xp68 |
| weaver (boss) | 93.7% r5.2 k4.3 xp67 | 94.3% r5.4 k4.4 xp67 | 95.5% r5.6 k4.4 xp68 | 95.9% r5.7 k4.3 xp67 | 89.7% r6.3 k4.5 xp67 | 86.8% r6.4 k4.5 xp66 |
| hollow (boss) | 95.8% r5.6 k4.5 xp69 | 94.5% r5.6 k4.4 xp67 | 94.5% r5.5 k4.3 xp66 | 89.7% r6.2 k4.5 xp68 | 85.9% r6.3 k4.5 xp66 | 82.9% r6.5 k4.5 xp65 |
| finale4 (boss) | 91.1% r5.9 k6.6 xp89 | 89.9% r6.3 k6.5 xp88 | 85.1% r6.8 k6.6 xp87 | 85.2% r7.0 k6.7 xp88 | 87.3% r7.3 k6.7 xp89 | 90.8% r7.6 k6.8 xp91 |
| trailT1 (ambush) | 100.0% r3.3 k3.0 xp55 | 100.0% r3.5 k3.0 xp55 | 100.0% r3.5 k3.0 xp55 | 99.8% r3.7 k3.0 xp55 | 99.8% r4.0 k3.0 xp55 | 99.7% r4.2 k3.0 xp55 |
| wildT2 (ambush) | 98.8% r3.7 k3.0 xp55 | 99.3% r3.7 k3.0 xp55 | 98.6% r3.8 k3.0 xp54 | 97.1% r3.9 k3.0 xp54 | 96.3% r4.0 k3.0 xp54 | 94.6% r4.1 k2.9 xp53 |

## Dial: enemy AIM ×mult

| encounter (band) | ×1.0 | ×1.1 | ×1.2 | ×1.3 | ×1.4 | ×1.5 |
|---|---|---|---|---|---|---|
| skirmish (story) | 100.0% r3.8 k4.0 xp65 | 100.0% r3.7 k4.0 xp65 | 100.0% r3.7 k4.0 xp65 | 100.0% r3.7 k4.0 xp65 | 100.0% r3.8 k4.0 xp65 | 100.0% r3.8 k4.0 xp65 |
| vanguard (story) | 99.0% r3.6 k4.0 xp65 | 98.5% r3.6 k4.0 xp64 | 98.7% r3.6 k4.0 xp64 | 98.9% r3.6 k4.0 xp65 | 98.9% r3.6 k4.0 xp65 | 99.0% r3.6 k4.0 xp65 |
| deacon (boss) | 75.9% r6.4 k6.1 xp80 | 71.2% r6.3 k5.9 xp77 | 69.0% r6.1 k5.8 xp75 | 67.3% r6.1 k5.7 xp74 | 65.7% r6.0 k5.6 xp73 | 66.1% r6.0 k5.6 xp73 |
| foreman (boss) | 96.9% r6.9 k4.8 xp72 | 94.8% r6.9 k4.7 xp71 | 93.9% r7.0 k4.7 xp71 | 92.0% r7.0 k4.7 xp70 | 93.3% r7.0 k4.7 xp70 | 90.0% r6.9 k4.6 xp69 |
| weaver (boss) | 93.7% r5.2 k4.3 xp67 | 92.6% r5.2 k4.3 xp66 | 90.2% r5.2 k4.2 xp65 | 89.8% r5.3 k4.2 xp64 | 89.9% r5.3 k4.2 xp64 | 89.1% r5.2 k4.1 xp64 |
| hollow (boss) | 95.8% r5.6 k4.5 xp69 | 92.8% r5.5 k4.4 xp67 | 92.8% r5.4 k4.3 xp67 | 89.2% r5.5 k4.3 xp65 | 88.3% r5.4 k4.2 xp64 | 89.2% r5.5 k4.2 xp65 |
| finale4 (boss) | 91.1% r5.9 k6.6 xp89 | 86.9% r6.0 k6.5 xp86 | 83.1% r6.0 k6.3 xp84 | 76.1% r6.0 k6.3 xp82 | 73.1% r5.9 k6.2 xp80 | 70.8% r5.9 k6.2 xp79 |
| trailT1 (ambush) | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 |
| wildT2 (ambush) | 98.8% r3.7 k3.0 xp55 | 98.9% r3.6 k3.0 xp55 | 98.3% r3.6 k3.0 xp54 | 97.7% r3.6 k3.0 xp54 | 97.2% r3.6 k3.0 xp54 | 96.8% r3.6 k3.0 xp54 |

## Dial: enemy DMG ×mult

| encounter (band) | ×1.0 | ×1.1 | ×1.2 | ×1.3 | ×1.4 | ×1.5 |
|---|---|---|---|---|---|---|
| skirmish (story) | 100.0% r3.8 k4.0 xp65 | 99.8% r3.8 k4.0 xp65 | 99.9% r3.8 k4.0 xp65 | 99.7% r3.8 k4.0 xp65 | 99.7% r3.8 k4.0 xp65 | 99.6% r3.8 k4.0 xp65 |
| vanguard (story) | 99.0% r3.6 k4.0 xp65 | 98.9% r3.6 k4.0 xp65 | 98.3% r3.6 k4.0 xp64 | 98.5% r3.6 k4.0 xp64 | 98.4% r3.6 k4.0 xp64 | 98.0% r3.6 k4.0 xp64 |
| deacon (boss) | 75.9% r6.4 k6.1 xp80 | 73.9% r6.3 k6.0 xp78 | 74.1% r6.2 k6.0 xp78 | 71.5% r6.2 k5.9 xp77 | 70.3% r6.1 k5.8 xp76 | 72.0% r6.1 k5.8 xp76 |
| foreman (boss) | 96.9% r6.9 k4.8 xp72 | 95.6% r6.9 k4.7 xp71 | 94.8% r7.0 k4.7 xp71 | 94.2% r6.9 k4.7 xp71 | 92.3% r6.9 k4.7 xp70 | 89.1% r7.0 k4.6 xp69 |
| weaver (boss) | 93.7% r5.2 k4.3 xp67 | 92.2% r5.1 k4.2 xp65 | 92.9% r5.1 k4.2 xp66 | 92.5% r5.2 k4.2 xp66 | 93.7% r5.2 k4.2 xp66 | 91.6% r5.1 k4.2 xp65 |
| hollow (boss) | 95.8% r5.6 k4.5 xp69 | 94.9% r5.4 k4.4 xp68 | 92.5% r5.4 k4.3 xp67 | 93.1% r5.4 k4.4 xp67 | 92.7% r5.5 k4.4 xp67 | 91.2% r5.5 k4.3 xp66 |
| finale4 (boss) | 91.1% r5.9 k6.6 xp89 | 88.3% r5.9 k6.5 xp87 | 87.8% r6.0 k6.5 xp87 | 82.3% r5.9 k6.4 xp84 | 82.5% r6.0 k6.4 xp85 | 78.3% r5.9 k6.3 xp82 |
| trailT1 (ambush) | 100.0% r3.3 k3.0 xp55 | 100.0% r3.3 k3.0 xp55 | 99.9% r3.3 k3.0 xp55 | 99.8% r3.4 k3.0 xp55 | 99.5% r3.4 k3.0 xp55 | 99.5% r3.4 k3.0 xp55 |
| wildT2 (ambush) | 98.8% r3.7 k3.0 xp55 | 98.6% r3.6 k3.0 xp54 | 98.0% r3.6 k3.0 xp54 | 97.3% r3.6 k3.0 xp54 | 97.6% r3.6 k3.0 xp54 | 97.8% r3.6 k3.0 xp54 |

## How to read this in the session
- Find the row for each fight, walk right until the cell bolds — that's the
  global multiplier that lands it in band FOR THE BOT; a human lands lower,
  so the honest target is usually one step left of the bolded cell.
- If a row never bolds on one dial, that fight needs a different dial (or a
  comp change — a data edit, not a rules edit).
- ROUNDS climbing with hp dials + XP climbing in the deacon row = the raise
  conveyor paying out in longer fights; the P0 farm closure changes this row.
- Timeout rates were ~0 across the sweep unless noted.
