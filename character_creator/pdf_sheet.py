"""
pdf_sheet.py — Dustfall PDF Character Sheet Generator

Generates a printable, frontier-styled character sheet using ReportLab.
Portrait layout, aged-paper aesthetic, stats table, traits, backstory.
"""

import io
import json
from pathlib import Path

try:
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.units import inch
    from reportlab.lib.colors import HexColor, black, white
    from reportlab.pdfgen.canvas import Canvas
    from reportlab.platypus import (
        SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    )
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
    REPORTLAB_AVAILABLE = True
except ImportError:
    REPORTLAB_AVAILABLE = False


# Color palette — aged frontier document
C_PAPER = HexColor("#f4e9c8") if REPORTLAB_AVAILABLE else None
C_INK = HexColor("#2a1a08") if REPORTLAB_AVAILABLE else None
C_RUST = HexColor("#8b3a1a") if REPORTLAB_AVAILABLE else None
C_SHADOW = HexColor("#4a3020") if REPORTLAB_AVAILABLE else None
C_GRIT = HexColor("#c85252") if REPORTLAB_AVAILABLE else None
C_IRON = HexColor("#909090") if REPORTLAB_AVAILABLE else None
C_GHOST = HexColor("#7878cc") if REPORTLAB_AVAILABLE else None
C_TONGUE = HexColor("#cc8844") if REPORTLAB_AVAILABLE else None
C_WRENCH = HexColor("#44aacc") if REPORTLAB_AVAILABLE else None
C_TRAIL = HexColor("#88aa44") if REPORTLAB_AVAILABLE else None

STAT_COLORS = {
    "grit": C_GRIT,
    "iron": C_IRON,
    "ghost": C_GHOST,
    "tongue": C_TONGUE,
    "wrench": C_WRENCH,
    "trail": C_TRAIL,
}

STAT_LABELS = {
    "grit": "GRIT",
    "iron": "IRON",
    "ghost": "GHOST",
    "tongue": "TONGUE",
    "wrench": "WRENCH",
    "trail": "TRAIL",
}


def generate_pdf(character: dict) -> bytes:
    """
    Generate a PDF character sheet for a Dustfall character.
    Returns bytes of the PDF.
    Raises RuntimeError if ReportLab is not available.
    """
    if not REPORTLAB_AVAILABLE:
        raise RuntimeError("reportlab is not installed. Run: pip install reportlab")

    buf = io.BytesIO()
    c = Canvas(buf, pagesize=letter)
    W, H = letter  # 612 x 792

    def page_one():
        # Background
        c.setFillColor(C_PAPER)
        c.rect(0, 0, W, H, fill=1, stroke=0)

        # Aged edge effect — darkened borders
        c.setFillColor(HexColor("#c4a86a"))
        for edge_w, edge_h in [(20, H), (W - 20, H)]:
            pass  # Skip gradient edges for simplicity — use solid borders

        # Outer border
        c.setStrokeColor(C_RUST)
        c.setLineWidth(3)
        c.rect(18, 18, W - 36, H - 36, fill=0, stroke=1)
        c.setLineWidth(1)
        c.rect(22, 22, W - 44, H - 44, fill=0, stroke=1)

        # ---- HEADER ----
        c.setFillColor(C_RUST)
        c.rect(30, H - 90, W - 60, 60, fill=1, stroke=0)

        c.setFillColor(C_PAPER)
        c.setFont("Helvetica-Bold", 22)
        c.drawCentredString(W / 2, H - 58, "DUSTFALL: THE ASHEN FRONTIER")
        c.setFont("Helvetica", 11)
        c.drawCentredString(W / 2, H - 74, "CHARACTER DOSSIER")

        # ---- CHARACTER NAME ----
        c.setFillColor(C_INK)
        c.setFont("Helvetica-Bold", 28)
        name = character.get("name", "UNKNOWN")
        c.drawCentredString(W / 2, H - 120, name.upper())

        # Faction + Archetype line
        c.setFont("Helvetica", 13)
        c.setFillColor(C_SHADOW)
        faction = character.get("faction", "Unknown")
        archetype = character.get("archetype", "Unknown")
        c.drawCentredString(W / 2, H - 140, f"{faction.upper()}  ·  {archetype.upper()}")

        # Divider
        c.setStrokeColor(C_RUST)
        c.setLineWidth(1.5)
        c.line(40, H - 150, W - 40, H - 150)

        # ---- STATS BLOCK ----
        stats = character.get("stats", {})
        derived = character.get("derived", {})

        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(C_RUST)
        c.drawString(40, H - 168, "CORE STATISTICS")

        stat_x_start = 40
        stat_y = H - 230
        stat_w = 80
        stat_h = 50
        stat_gap = 10
        stat_keys = ["grit", "iron", "ghost", "tongue", "wrench", "trail"]

        for i, key in enumerate(stat_keys):
            x = stat_x_start + i * (stat_w + stat_gap)
            val = stats.get(key, 1)
            color = STAT_COLORS.get(key, C_INK)

            # Box
            c.setFillColor(C_PAPER)
            c.setStrokeColor(color)
            c.setLineWidth(2)
            c.rect(x, stat_y, stat_w, stat_h, fill=1, stroke=1)

            # Label
            c.setFillColor(color)
            c.setFont("Helvetica-Bold", 8)
            c.drawCentredString(x + stat_w / 2, stat_y + stat_h - 12, STAT_LABELS[key])

            # Value
            c.setFillColor(C_INK)
            c.setFont("Helvetica-Bold", 26)
            c.drawCentredString(x + stat_w / 2, stat_y + 10, str(val))

            # Pip dots
            c.setFillColor(color)
            for p in range(6):
                pip_x = x + 8 + p * 11
                pip_y = stat_y + stat_h - 22
                if p < val:
                    c.circle(pip_x, pip_y, 4, fill=1, stroke=0)
                else:
                    c.setStrokeColor(color)
                    c.setFillColor(C_PAPER)
                    c.circle(pip_x, pip_y, 4, fill=1, stroke=1)
                    c.setFillColor(color)

        # Derived stats
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(C_RUST)
        c.drawString(40, H - 260, "DERIVED")

        derived_y = H - 290
        derived_items = [
            ("MAX HP", derived.get("max_hp", "—")),
            ("INITIATIVE", derived.get("initiative", "—")),
            ("CARRY", derived.get("carry_cap", "—")),
            ("WOUNDS", f"0 / {derived.get('wounds_max', 3)}"),
        ]
        for i, (label, val) in enumerate(derived_items):
            dx = 40 + i * 130
            c.setFillColor(C_SHADOW)
            c.setFont("Helvetica", 8)
            c.drawString(dx, derived_y, label)
            c.setFillColor(C_INK)
            c.setFont("Helvetica-Bold", 16)
            c.drawString(dx, derived_y - 18, str(val))

        # Divider
        c.setStrokeColor(HexColor("#c4a86a"))
        c.setLineWidth(1)
        c.line(40, H - 310, W - 40, H - 310)

        # ---- TRAITS ----
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(C_RUST)
        c.drawString(40, H - 328, "TRAITS")

        traits = character.get("traits", [])
        trait_y = H - 345
        try:
            from creator import TRAITS as TRAIT_DATA
        except ImportError:
            TRAIT_DATA = {}

        for t in traits[:2]:
            td = TRAIT_DATA.get(t, {})
            c.setFillColor(C_INK)
            c.setFont("Helvetica-Bold", 11)
            c.drawString(50, trait_y, t)
            c.setFont("Helvetica", 9)
            c.setFillColor(C_SHADOW)
            effect = td.get("effect", "")
            if effect:
                c.drawString(60, trait_y - 13, effect)
            trait_y -= 35

        # Divider
        c.setStrokeColor(HexColor("#c4a86a"))
        c.line(40, trait_y - 5, W - 40, trait_y - 5)

        # ---- GEAR ----
        gear_y = trait_y - 25
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(C_RUST)
        c.drawString(40, gear_y, "STARTING GEAR")

        gear_items = character.get("gear", [])
        gear_y -= 15
        for item in gear_items:
            c.setFillColor(C_INK)
            c.setFont("Helvetica-Bold", 10)
            c.drawString(50, gear_y, f"• {item.get('name', 'Item')}")
            c.setFont("Helvetica-Oblique", 8)
            c.setFillColor(C_SHADOW)
            c.drawString(60, gear_y - 12, item.get("notes", ""))
            gear_y -= 28

        # Divider
        c.setStrokeColor(HexColor("#c4a86a"))
        c.line(40, gear_y - 5, W - 40, gear_y - 5)

        # ---- APPEARANCE ----
        app_y = gear_y - 25
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(C_RUST)
        c.drawString(40, app_y, "APPEARANCE")

        app_data = character.get("appearance", {})
        app_lines = [
            ("Eyes", app_data.get("eyes", "—")),
            ("Build", app_data.get("build", "—")),
            ("Marks", app_data.get("marks", "—")),
            ("Dress", app_data.get("dress", "—")),
        ]
        app_y -= 15
        col_w = (W - 80) / 2
        for i, (label, val) in enumerate(app_lines):
            col = i % 2
            row = i // 2
            ax = 40 + col * col_w
            ay = app_y - row * 20
            c.setFont("Helvetica-Bold", 8)
            c.setFillColor(C_SHADOW)
            c.drawString(ax, ay, f"{label}:")
            c.setFont("Helvetica", 8)
            c.setFillColor(C_INK)
            c.drawString(ax + 40, ay, val)

        # ---- FOOTER ----
        c.setFont("Helvetica", 7)
        c.setFillColor(HexColor("#aaaaaa"))
        c.drawCentredString(W / 2, 30, "DUSTFALL: THE ASHEN FRONTIER  ·  DANGERCORN ENTERPRISES  ·  YEAR 1889")

    def page_two():
        c.showPage()

        # Background
        c.setFillColor(C_PAPER)
        c.rect(0, 0, W, H, fill=1, stroke=0)

        # Border
        c.setStrokeColor(C_RUST)
        c.setLineWidth(3)
        c.rect(18, 18, W - 36, H - 36, fill=0, stroke=1)
        c.setLineWidth(1)
        c.rect(22, 22, W - 44, H - 44, fill=0, stroke=1)

        # Header
        c.setFillColor(C_RUST)
        c.rect(30, H - 70, W - 60, 40, fill=1, stroke=0)
        c.setFillColor(C_PAPER)
        c.setFont("Helvetica-Bold", 14)
        name = character.get("name", "UNKNOWN")
        c.drawCentredString(W / 2, H - 44, f"{name.upper()}  ·  HISTORY & BACKGROUND")

        # ---- BACKSTORY ----
        c.setFillColor(C_RUST)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(40, H - 90, "BACKGROUND")

        backstory = character.get("backstory", "No backstory recorded.")
        paragraphs = backstory.split("\n\n")

        text_y = H - 110
        c.setFont("Helvetica-Oblique", 9)
        c.setFillColor(C_INK)

        for para in paragraphs:
            para = para.strip()
            if not para:
                continue
            # Simple word wrap
            words = para.split()
            line = ""
            max_w = W - 100
            for word in words:
                test = f"{line} {word}".strip()
                if c.stringWidth(test, "Helvetica-Oblique", 9) < max_w:
                    line = test
                else:
                    c.drawString(50, text_y, line)
                    text_y -= 13
                    line = word
            if line:
                c.drawString(50, text_y, line)
                text_y -= 13
            text_y -= 8  # paragraph gap

        # Divider
        c.setStrokeColor(HexColor("#c4a86a"))
        c.setLineWidth(1)
        c.line(40, text_y - 5, W - 40, text_y - 5)

        # ---- MOTIVATION ----
        mot_y = text_y - 25
        c.setFillColor(C_RUST)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(40, mot_y, "MOTIVATION")

        motivation = character.get("motivation", {})
        if isinstance(motivation, dict):
            mot_label = motivation.get("label", "Unknown")
            mot_desc = motivation.get("description", "")
            mot_drives = motivation.get("drives", "")
        else:
            mot_label = str(motivation)
            mot_desc = ""
            mot_drives = ""

        c.setFillColor(C_INK)
        c.setFont("Helvetica-Bold", 12)
        c.drawString(50, mot_y - 18, mot_label.upper())
        c.setFont("Helvetica", 9)
        c.setFillColor(C_SHADOW)
        c.drawString(50, mot_y - 33, mot_desc)
        c.setFont("Helvetica-Oblique", 9)
        c.drawString(50, mot_y - 46, mot_drives)

        # Divider
        c.setStrokeColor(HexColor("#c4a86a"))
        c.line(40, mot_y - 60, W - 40, mot_y - 60)

        # ---- NOTES / WOUNDS BOX ----
        notes_y = mot_y - 80
        c.setFillColor(C_RUST)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(40, notes_y, "WOUNDS & CONDITIONS")

        wound_y = notes_y - 20
        for i in range(3):
            wx = 50 + i * 150
            c.setStrokeColor(C_RUST)
            c.setLineWidth(1.5)
            c.rect(wx, wound_y - 25, 130, 25, fill=0, stroke=1)
            c.setFillColor(C_SHADOW)
            c.setFont("Helvetica", 8)
            c.drawString(wx + 5, wound_y - 10, f"WOUND {i + 1}")

        # Notes section
        notes_box_y = wound_y - 60
        c.setFillColor(C_RUST)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(40, notes_box_y, "FIELD NOTES")

        c.setStrokeColor(HexColor("#c4a86a"))
        c.setLineWidth(0.5)
        line_start = notes_box_y - 20
        for i in range(8):
            ly = line_start - i * 18
            c.line(50, ly, W - 50, ly)

        # ---- FOOTER ----
        c.setFont("Helvetica", 7)
        c.setFillColor(HexColor("#aaaaaa"))
        c.drawCentredString(W / 2, 30, "DUSTFALL: THE ASHEN FRONTIER  ·  DANGERCORN ENTERPRISES  ·  YEAR 1889")

    page_one()
    page_two()
    c.save()

    buf.seek(0)
    return buf.read()
