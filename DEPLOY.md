# Dustfall — Deploy Guide

## Goal

Public demo at `dustfall.dangercorn.net` where anyone can:
- Try the character creator
- Play one tutorial scenario
- See the lore preview

## Option A: Static build (if index.html is self-contained)

```bash
cd "D:/Claude Projects/weird-west-tactics"
# Vercel static deploy
npx vercel deploy --prod
```

Check: does `index.html` load without the Python backend? If yes, this works.

If `index.html` needs `web.py` / `cli.py` / `lore_engine.py`, go to Option B.

## Option B: Full stack (Flask + static frontend)

Dockerfile:
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements_lore.txt character_creator/requirements.txt ./
RUN pip install -r requirements_lore.txt -r requirements.txt || true
COPY . .
EXPOSE 8080
CMD ["python", "web.py"]
```

Deploy on Fly.io / Render.com using the same pattern as Quilt.

## Option C: Itch.io page

For game indie-first marketing, ship a zipped HTML version to itch.io:
1. Zip the playable subset (character_creator + tactical combat HTML)
2. Upload to itch.io as "Dustfall: The Ashen Frontier - Early Prototype"
3. Free-with-donation or paid ($5) — both work for indie tactics
4. Gain wishlist signups via email collection

Expected audience: FFT/XCOM fans on itch.io, r/tacticalgames, Tactics & Strategy Weekly newsletter.

## SEO + landing

Separate `dustfall.dangercorn.net` landing:
- Hero: one-line pitch "The gods followed their people to America."
- Feature list (6 archetypes, grid combat, divine factions)
- Screenshot gallery
- Demo button
- Mailing list signup via Resend

Keep landing and app separate: landing loads in 100ms, app loads when you click Play.

## Future: Steam

When Dustfall grows out of "early prototype" status:
- Wrap in Electron or deploy to Steam direct
- Steam wishlist is where you want that $5 to eventually happen
- itch.io is the warm-up; Steam is the main stage

## Placeholders for release notes

- v0.1 — Early prototype: 6 archetypes, 1 tutorial scenario
- v0.2 — Original lore (DUSTFALL_BIBLE.md in repo) woven in
- v0.3 — Map editor + multiple mission types
- v0.4 — Campaign mode
- v1.0 — Steam release
