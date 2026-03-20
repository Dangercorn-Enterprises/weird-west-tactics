"""
Dustfall Lore Engine — Web UI (Flask)
A game master tool for generating and browsing Dustfall world lore.

Usage:
  python web.py              # run on port 5555
  python web.py --port 5555

Routes:
  GET  /                     — dashboard: stats + quick-generate buttons
  GET  /towns                — browse all generated towns
  POST /towns/generate       — generate a new town
  GET  /towns/<name>         — view a single town
  GET  /quests               — browse all generated quests
  POST /quests/generate      — generate a new quest
  GET  /quests/<id>          — view a single quest
  GET  /items                — browse all generated items
  POST /items/generate       — generate a new item
  GET  /enemies              — browse all generated enemies
  POST /enemies/generate     — generate a new enemy
  GET  /export/<kind>        — export lore as Markdown
  GET  /api/<kind>           — JSON API for all lore
"""

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from flask import Flask, render_template_string, request, redirect, url_for, jsonify, Response
from lore_engine import LoreEngine, DEITIES, ARCHETYPES, ENEMY_FACTIONS, ITEM_TYPES_ALL, REGIONS, to_markdown
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET", "dustfall-ashlands-lore")
engine = LoreEngine()

# ------------------------------------------------------------------ #
# HTML templates (inline — no template folder needed)                 #
# ------------------------------------------------------------------ #

BASE_TEMPLATE = """\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Dustfall Lore Engine — {{ title }}</title>
  <style>
    :root {
      --bg: #0d0a06;
      --surface: #1a1409;
      --border: #2d2010;
      --text: #d4c5a9;
      --text-dim: #7a6a4a;
      --accent: #d4a843;   /* Vulcan Brass */
      --red: #c0392b;
      --blue: #4ECDC4;
      --purple: #6B3FA0;
      --green: #2ecc71;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Georgia', serif; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* Header */
    .header {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      padding: 16px 32px;
      display: flex;
      align-items: center;
      gap: 24px;
    }
    .header-brand {
      font-size: 22px;
      font-weight: bold;
      color: var(--accent);
      letter-spacing: 2px;
      font-variant: small-caps;
    }
    .header-sub {
      font-size: 11px;
      color: var(--text-dim);
      text-transform: uppercase;
      letter-spacing: 2px;
    }
    .nav { margin-left: auto; display: flex; gap: 24px; }
    .nav a { font-size: 13px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px; }
    .nav a:hover { color: var(--accent); }
    .nav a.active { color: var(--accent); }

    /* Container */
    .container { max-width: 1100px; margin: 0 auto; padding: 32px 24px; }

    /* Section title */
    .section-title {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 3px;
      color: var(--text-dim);
      margin-bottom: 16px;
      padding-bottom: 8px;
      border-bottom: 1px solid var(--border);
    }

    /* Cards grid */
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; margin-bottom: 32px; }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: 20px;
    }
    .card-title { font-size: 16px; color: var(--accent); margin-bottom: 6px; font-variant: small-caps; }
    .card-meta { font-size: 11px; color: var(--text-dim); margin-bottom: 10px; text-transform: uppercase; letter-spacing: 1px; }
    .card-desc { font-size: 13px; color: var(--text); line-height: 1.6; }
    .card-link { display: inline-block; margin-top: 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; }

    /* Deity badges */
    .deity-badge {
      display: inline-block;
      font-size: 10px;
      padding: 2px 8px;
      border-radius: 2px;
      text-transform: uppercase;
      letter-spacing: 1px;
      font-weight: bold;
    }
    .deity-Vulcan { background: rgba(212,168,67,0.15); color: #d4a843; border: 1px solid rgba(212,168,67,0.3); }
    .deity-Perun { background: rgba(91,127,170,0.15); color: #8ba8d0; border: 1px solid rgba(91,127,170,0.3); }
    .deity-Baron { background: rgba(107,63,160,0.15); color: #a67fd0; border: 1px solid rgba(107,63,160,0.3); }
    .deity-Coyote { background: rgba(200,90,58,0.15); color: #e07050; border: 1px solid rgba(200,90,58,0.3); }
    .deity-Anansi { background: rgba(192,192,192,0.10); color: #b0b0b0; border: 1px solid rgba(192,192,192,0.2); }
    .deity-Sleeping { background: rgba(30,10,0,0.5); color: #555; border: 1px solid #222; }
    .deity-None { background: rgba(120,120,80,0.1); color: var(--text-dim); border: 1px solid var(--border); }

    /* Tier badges */
    .tier-1 { background: rgba(100,200,100,0.1); color: #80c080; border: 1px solid rgba(100,200,100,0.2); }
    .tier-2 { background: rgba(200,150,50,0.1); color: #c09030; border: 1px solid rgba(200,150,50,0.2); }
    .tier-3 { background: rgba(200,50,50,0.1); color: #c03030; border: 1px solid rgba(200,50,50,0.2); }

    /* Generate form */
    .gen-panel {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: 24px;
      margin-bottom: 32px;
    }
    .gen-panel h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 2px; color: var(--text-dim); margin-bottom: 16px; }
    .form-row { display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end; }
    .form-group { display: flex; flex-direction: column; gap: 4px; }
    .form-group label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-dim); }
    .form-group select, .form-group input {
      background: var(--bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 8px 12px;
      font-size: 13px;
      border-radius: 3px;
      min-width: 150px;
    }
    .btn {
      background: var(--accent);
      color: #0d0a06;
      border: none;
      padding: 9px 20px;
      font-size: 12px;
      font-weight: bold;
      text-transform: uppercase;
      letter-spacing: 1px;
      border-radius: 3px;
      cursor: pointer;
    }
    .btn:hover { background: #e8c060; }
    .btn-secondary {
      background: transparent;
      color: var(--text-dim);
      border: 1px solid var(--border);
    }
    .btn-secondary:hover { color: var(--accent); border-color: var(--accent); }

    /* Detail page */
    .detail-header { margin-bottom: 24px; }
    .detail-title { font-size: 28px; color: var(--accent); font-variant: small-caps; letter-spacing: 2px; }
    .detail-meta { font-size: 12px; color: var(--text-dim); margin-top: 6px; }
    .detail-section { margin-bottom: 24px; }
    .detail-section-label { font-size: 10px; text-transform: uppercase; letter-spacing: 2px; color: var(--text-dim); margin-bottom: 8px; }
    .detail-body { font-size: 14px; line-height: 1.8; }
    .detail-list { list-style: none; }
    .detail-list li { padding: 4px 0; padding-left: 16px; position: relative; }
    .detail-list li::before { content: "•"; position: absolute; left: 0; color: var(--accent); }
    .flavor-text { font-style: italic; color: var(--text-dim); border-left: 2px solid var(--accent); padding-left: 16px; margin: 16px 0; }

    /* Stats grid (dashboard) */
    .stats-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; margin-bottom: 32px; }
    .stat-card { background: var(--surface); border: 1px solid var(--border); border-radius: 4px; padding: 20px; text-align: center; }
    .stat-value { font-size: 36px; color: var(--accent); font-weight: bold; }
    .stat-label { font-size: 10px; text-transform: uppercase; letter-spacing: 2px; color: var(--text-dim); margin-top: 4px; }
    .quick-actions { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 32px; }

    /* Loading state */
    .generating { background: rgba(212,168,67,0.05); border: 1px solid rgba(212,168,67,0.2); padding: 24px; border-radius: 4px; text-align: center; color: var(--text-dim); }

    /* Ashfall accent */
    .ashfall-text { color: var(--blue); }
    .danger-text { color: var(--red); }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <div class="header-brand">Dustfall</div>
      <div class="header-sub">Lore Engine</div>
    </div>
    <nav class="nav">
      <a href="/" {% if active=='dashboard' %}class="active"{% endif %}>Dashboard</a>
      <a href="/towns" {% if active=='towns' %}class="active"{% endif %}>Towns</a>
      <a href="/quests" {% if active=='quests' %}class="active"{% endif %}>Quests</a>
      <a href="/items" {% if active=='items' %}class="active"{% endif %}>Items</a>
      <a href="/enemies" {% if active=='enemies' %}class="active"{% endif %}>Enemies</a>
    </nav>
  </div>
  <div class="container">
    {{ content }}
  </div>
</body>
</html>
"""


def render_page(title: str, content: str, active: str = "dashboard") -> str:
    """Render the base template with given content."""
    return render_template_string(
        BASE_TEMPLATE,
        title=title,
        content=content,
        active=active,
    )


def _deity_badge(deity: str) -> str:
    if not deity or deity == "None":
        cls = "deity-None"
        label = "No Deity"
    elif "Baron" in deity:
        cls = "deity-Baron"
        label = "Baron Samedi"
    elif "Sleeping" in deity:
        cls = "deity-Sleeping"
        label = "The Sleeping One"
    else:
        cls = f"deity-{deity.split()[0]}"
        label = deity
    return f'<span class="deity-badge {cls}">{label}</span>'


def _tier_badge(tier: int) -> str:
    labels = {1: "Common", 2: "Veteran", 3: "Boss"}
    return f'<span class="deity-badge tier-{tier}">Tier {tier}: {labels.get(tier, "?")}</span>'


# ------------------------------------------------------------------ #
# Routes                                                              #
# ------------------------------------------------------------------ #

@app.route("/")
def dashboard():
    stats = engine.stats()
    recent_towns = engine.list_towns(limit=3)
    recent_quests = engine.list_quests(limit=3)

    stats_html = ""
    for k, v in stats.items():
        stats_html += f'<div class="stat-card"><div class="stat-value">{v}</div><div class="stat-label">{k.title()}</div></div>'

    town_cards = ""
    for t in recent_towns:
        deity = t.get("deity", "None")
        town_cards += f"""
        <div class="card">
          <div class="card-title">{t.get('name', '???')}</div>
          <div class="card-meta">{t.get('region', '')} &bull; {_deity_badge(deity)}</div>
          <div class="card-desc">{t.get('description', '')[:120]}...</div>
          <a href="/towns/{t.get('name', '')}" class="card-link">View Town &rarr;</a>
        </div>"""

    quest_cards = ""
    for q in recent_quests:
        quest_cards += f"""
        <div class="card">
          <div class="card-title">{q.get('title', '???')}</div>
          <div class="card-meta">{q.get('quest_type', '')} &bull; {q.get('city', '')} &bull; {_deity_badge(q.get('deity', 'None'))}</div>
          <div class="card-desc">{q.get('hook', '')[:120]}...</div>
        </div>"""

    content = f"""
    <div class="section-title">Lore Database</div>
    <div class="stats-grid">{stats_html}</div>

    <div class="quick-actions">
      <form method="POST" action="/towns/generate" style="display:inline">
        <button class="btn" type="submit">Generate Town</button>
      </form>
      <form method="POST" action="/quests/generate" style="display:inline">
        <button class="btn" type="submit">Generate Quest</button>
      </form>
      <form method="POST" action="/items/generate" style="display:inline">
        <button class="btn" type="submit">Generate Item</button>
      </form>
      <form method="POST" action="/enemies/generate" style="display:inline">
        <button class="btn" type="submit">Generate Enemy</button>
      </form>
      <a href="/export/towns" class="btn btn-secondary">Export Lore</a>
    </div>

    <div class="section-title">Recent Towns</div>
    <div class="grid">{town_cards or '<p style="color:var(--text-dim)">No towns generated yet. Click Generate Town above.</p>'}</div>

    <div class="section-title">Recent Quests</div>
    <div class="grid">{quest_cards or '<p style="color:var(--text-dim)">No quests generated yet.</p>'}</div>
    """
    return render_page("Dashboard", content, active="dashboard")


@app.route("/towns")
def towns_list():
    deity_filter = request.args.get("deity")
    towns = engine.list_towns(limit=50)
    if deity_filter and deity_filter != "all":
        towns = [t for t in towns if t.get("deity") == deity_filter]

    deity_options = "".join(f'<option value="{d}" {"selected" if deity_filter==d else ""}>{d}</option>' for d in list(DEITIES.keys()) + ["None"])

    cards = ""
    for t in towns:
        deity = t.get("deity", "None")
        cards += f"""
        <div class="card">
          <div class="card-title">{t.get('name', '???')}</div>
          <div class="card-meta">{t.get('region', 'Unknown')} &bull; {_deity_badge(deity)} &bull; {t.get('mood', 'Stable')}</div>
          <div class="card-desc">{t.get('description', '')[:160]}...</div>
          <a href="/towns/{t.get('name', '')}" class="card-link">View &rarr;</a>
        </div>"""

    region_options = "".join(f'<option value="{r}">{r}</option>' for r in REGIONS)
    deity_select_options = "<option value=''>Any Deity</option>" + "".join(f'<option value="{d}">{d}</option>' for d in DEITIES.keys())

    content = f"""
    <div class="gen-panel">
      <h2>Generate New Town</h2>
      <form method="POST" action="/towns/generate">
        <div class="form-row">
          <div class="form-group">
            <label>Deity Influence</label>
            <select name="deity">{deity_select_options}</select>
          </div>
          <div class="form-group">
            <label>Region</label>
            <select name="region"><option value="">Any Region</option>{region_options}</select>
          </div>
          <button class="btn" type="submit">Generate Town</button>
        </div>
      </form>
    </div>

    <div class="section-title">{len(towns)} Towns in the Ashlands</div>
    <div class="grid">{cards or '<p style="color:var(--text-dim)">No towns yet — generate one above.</p>'}</div>
    """
    return render_page("Towns", content, active="towns")


@app.route("/towns/generate", methods=["POST"])
def generate_town():
    deity = request.form.get("deity") or None
    region = request.form.get("region") or None
    town = engine.generate_town(deity=deity, region=region)
    return redirect(url_for("town_detail", name=town["name"]))


@app.route("/towns/<name>")
def town_detail(name: str):
    towns = engine.list_towns(limit=100)
    town = next((t for t in towns if t.get("name") == name), None)
    if not town:
        return render_page("Town Not Found", f"<p>No town named '{name}'</p>", active="towns")

    npcs_html = "".join(
        f'<li><strong>{n.get("name")}</strong> ({n.get("archetype", "?")}): {n.get("description", "")}</li>'
        for n in town.get("npcs", [])
    )
    factions_html = "".join(
        f'<li><strong>{f.get("name")}</strong> ({f.get("alignment", "neutral")}): {f.get("description", "")}</li>'
        for f in town.get("factions", [])
    )
    secrets_html = "".join(f'<li>{s}</li>' for s in town.get("secrets", []))
    services_html = ", ".join(town.get("services", []))

    content = f"""
    <div class="detail-header">
      <div class="detail-title">{town.get('name', '???')}</div>
      <div class="detail-meta">
        {_deity_badge(town.get('deity', 'None'))} &bull;
        {town.get('region', 'Unknown')} &bull;
        {town.get('population', '?')} &bull;
        Mood: <strong>{town.get('mood', 'Stable')}</strong>
      </div>
    </div>

    <div class="detail-section">
      <div class="detail-section-label">Description</div>
      <div class="detail-body">{town.get('description', '')}</div>
    </div>

    <div class="detail-section">
      <div class="detail-section-label">History</div>
      <div class="detail-body">{town.get('history', '')}</div>
    </div>

    <div class="detail-section">
      <div class="detail-section-label">Notable NPCs</div>
      <ul class="detail-list">{npcs_html or '<li>No notable NPCs recorded.</li>'}</ul>
    </div>

    <div class="detail-section">
      <div class="detail-section-label">Factions</div>
      <ul class="detail-list">{factions_html or '<li>No factions recorded.</li>'}</ul>
    </div>

    <div class="detail-section">
      <div class="detail-section-label">Secrets</div>
      <ul class="detail-list">{secrets_html or '<li>No secrets recorded.</li>'}</ul>
    </div>

    {f'<div class="detail-section"><div class="detail-section-label">Ashfall Presence</div><div class="detail-body ashfall-text">{town.get("ashfall_presence", "")}</div></div>' if town.get('ashfall_presence') else ''}

    {f'<div class="detail-section"><div class="detail-section-label">Rumor</div><div class="flavor-text">{town.get("rumor", "")}</div></div>' if town.get('rumor') else ''}

    {f'<div class="detail-section"><div class="detail-section-label">Services</div><div class="detail-body">{services_html}</div></div>' if services_html else ''}

    <div style="margin-top:32px">
      <a href="/towns" class="btn btn-secondary">&larr; All Towns</a>
      <a href="/export/towns" class="btn btn-secondary" style="margin-left:8px">Export Markdown</a>
    </div>
    """
    return render_page(town.get("name", "Town"), content, active="towns")


@app.route("/quests")
def quests_list():
    quests = engine.list_quests(limit=50)
    cards = "".join(f"""
    <div class="card">
      <div class="card-title">{q.get('title', '???')}</div>
      <div class="card-meta">{q.get('quest_type', '?')} &bull; {q.get('city', '?')} &bull; {_deity_badge(q.get('deity', 'None'))}</div>
      <div class="card-desc">{q.get('hook', '')[:150]}...</div>
    </div>""" for q in quests)

    city_options = "<option value=''>Any City</option>" + "".join(f'<option value="{n}">{n}</option>' for n in engine.db.get_town_names())
    arch_options = "<option value=''>Any Archetype</option>" + "".join(f'<option value="{a}">{a}</option>' for a in ARCHETYPES)
    deity_options = "<option value=''>Any Deity</option>" + "".join(f'<option value="{d}">{d}</option>' for d in DEITIES.keys())

    content = f"""
    <div class="gen-panel">
      <h2>Generate New Quest</h2>
      <form method="POST" action="/quests/generate">
        <div class="form-row">
          <div class="form-group"><label>City</label><select name="city">{city_options}</select></div>
          <div class="form-group"><label>Archetype</label><select name="archetype">{arch_options}</select></div>
          <div class="form-group"><label>Deity</label><select name="deity">{deity_options}</select></div>
          <button class="btn" type="submit">Generate Quest</button>
        </div>
      </form>
    </div>
    <div class="section-title">{len(quests)} Quests</div>
    <div class="grid">{cards or '<p style="color:var(--text-dim)">No quests yet.</p>'}</div>
    """
    return render_page("Quests", content, active="quests")


@app.route("/quests/generate", methods=["POST"])
def generate_quest():
    quest = engine.generate_quest(
        city=request.form.get("city") or None,
        archetype=request.form.get("archetype") or None,
        deity=request.form.get("deity") or None,
    )
    return redirect(url_for("quests_list"))


@app.route("/items")
def items_list():
    itype = request.args.get("type")
    items = engine.list_items(item_type=itype, limit=60)
    cards = "".join(f"""
    <div class="card">
      <div class="card-title">{i.get('name', '???')}</div>
      <div class="card-meta">{i.get('item_type', '?').title()} &bull; {_deity_badge(i.get('deity', 'None'))} &bull; {i.get('rarity', '?')}</div>
      <div class="card-desc"><em>{i.get('flavor_text', '')[:100]}</em></div>
    </div>""" for i in items)

    type_options = "<option value=''>All Types</option>" + "".join(f'<option value="{t}" {"selected" if itype==t else ""}>{t.title()}</option>' for t in ITEM_TYPES_ALL)
    deity_options = "<option value=''>Any Deity</option>" + "".join(f'<option value="{d}">{d}</option>' for d in DEITIES.keys())
    rarity_options = "".join(f'<option value="{r}">{r}</option>' for r in ["Common", "Uncommon", "Rare", "Legendary"])

    content = f"""
    <div class="gen-panel">
      <h2>Generate New Item</h2>
      <form method="POST" action="/items/generate">
        <div class="form-row">
          <div class="form-group"><label>Item Type</label><select name="item_type">{type_options.replace("All Types", "weapon")}</select></div>
          <div class="form-group"><label>Deity</label><select name="deity">{deity_options}</select></div>
          <div class="form-group"><label>Rarity</label><select name="rarity"><option value="">Any Rarity</option>{rarity_options}</select></div>
          <button class="btn" type="submit">Generate Item</button>
        </div>
      </form>
    </div>
    <div class="section-title">{len(items)} Items</div>
    <div class="grid">{cards or '<p style="color:var(--text-dim)">No items yet.</p>'}</div>
    """
    return render_page("Items", content, active="items")


@app.route("/items/generate", methods=["POST"])
def generate_item():
    engine.generate_item(
        item_type=request.form.get("item_type", "weapon"),
        deity=request.form.get("deity") or None,
        rarity=request.form.get("rarity") or None,
    )
    return redirect(url_for("items_list"))


@app.route("/enemies")
def enemies_list():
    faction_filter = request.args.get("faction")
    enemies = engine.list_enemies(faction=faction_filter, limit=60)
    cards = "".join(f"""
    <div class="card">
      <div class="card-title">{e.get('name', '???')}</div>
      <div class="card-meta">{_tier_badge(e.get('tier', 1))} &bull; {e.get('faction', 'Wild')}</div>
      <div class="card-desc">{e.get('appearance', '')[:140]}</div>
    </div>""" for e in enemies)

    faction_options = "<option value=''>All Factions</option>" + "".join(f'<option value="{f}" {"selected" if faction_filter==f else ""}>{f}</option>' for f in ENEMY_FACTIONS.keys())
    tier_options = "".join(f'<option value="{t}">{["Common", "Veteran", "Boss"][t-1]}</option>' for t in [1,2,3])
    gen_faction_options = "<option value=''>Random Faction</option>" + "".join(f'<option value="{f}">{f}</option>' for f in ENEMY_FACTIONS.keys())

    content = f"""
    <div class="gen-panel">
      <h2>Generate New Enemy</h2>
      <form method="POST" action="/enemies/generate">
        <div class="form-row">
          <div class="form-group"><label>Faction</label><select name="faction">{gen_faction_options}</select></div>
          <div class="form-group"><label>Tier</label><select name="tier">{tier_options}</select></div>
          <button class="btn" type="submit">Generate Enemy</button>
        </div>
      </form>
    </div>
    <div class="section-title">{len(enemies)} Enemies</div>
    <div class="grid">{cards or '<p style="color:var(--text-dim)">No enemies yet.</p>'}</div>
    """
    return render_page("Enemies", content, active="enemies")


@app.route("/enemies/generate", methods=["POST"])
def generate_enemy():
    engine.generate_enemy(
        faction=request.form.get("faction") or None,
        tier=int(request.form.get("tier", 1)),
    )
    return redirect(url_for("enemies_list"))


# ------------------------------------------------------------------ #
# Export routes                                                       #
# ------------------------------------------------------------------ #

@app.route("/export/<kind>")
def export_lore(kind: str):
    if kind not in ("towns", "quests", "items", "enemies"):
        return "Unknown lore type", 404
    md = engine.export_markdown(kind)
    return Response(
        md,
        mimetype="text/plain; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=dustfall_{kind}.md"},
    )


# ------------------------------------------------------------------ #
# JSON API                                                            #
# ------------------------------------------------------------------ #

@app.route("/api/towns")
def api_towns():
    return jsonify(engine.list_towns(limit=100))

@app.route("/api/quests")
def api_quests():
    return jsonify(engine.list_quests(limit=100))

@app.route("/api/items")
def api_items():
    return jsonify(engine.list_items(limit=100))

@app.route("/api/enemies")
def api_enemies():
    return jsonify(engine.list_enemies(limit=100))

@app.route("/api/stats")
def api_stats():
    return jsonify(engine.stats())


# ------------------------------------------------------------------ #
# Entry point                                                         #
# ------------------------------------------------------------------ #

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Dustfall Lore Engine Web UI")
    parser.add_argument("--port", type=int, default=5555)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    print(f"\nDustfall Lore Engine running at http://{args.host}:{args.port}")
    print("The Ashlands await.\n")
    app.run(host=args.host, port=args.port, debug=True)
