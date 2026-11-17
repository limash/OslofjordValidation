"""Styles and building blocks of a report PDF, read from the figures and CSV tables in `output/<REPORT>/`."""
import csv
import os
import sys
from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle)

HERE = Path(__file__).resolve().parent.parent / "output" / os.environ["REPORT"]
FIG = HERE / "figures"

OUT = Path(sys.argv[1])

# Noto Sans covers Ø, å, °, -, about  which the built-in Helvetica does not.
NOTO = Path("/usr/share/fonts/truetype/noto")
for name, file in (("DejaVu", "NotoSans-Regular.ttf"), ("DejaVu-Bold", "NotoSans-Bold.ttf"), ("DejaVu-Oblique", "NotoSans-Italic.ttf")):
    pdfmetrics.registerFont(TTFont(name, str(NOTO / file)))
pdfmetrics.registerFontFamily("DejaVu", normal="DejaVu", bold="DejaVu-Bold", italic="DejaVu-Oblique")

base = getSampleStyleSheet()
body = ParagraphStyle("body", parent=base["BodyText"], fontName="DejaVu", fontSize=9.5, leading=13.2, spaceAfter=5)
small = ParagraphStyle("small", parent=body, fontSize=8, leading=10.5)
caption = ParagraphStyle("caption", parent=body, fontSize=8.5, leading=11.5, textColor=colors.HexColor("#333333"), spaceBefore=3, spaceAfter=10)
h1 = ParagraphStyle("h1", parent=base["Heading1"], fontName="DejaVu-Bold", fontSize=15, leading=19, spaceBefore=10, spaceAfter=6, textColor=colors.HexColor("#1b3a5c"))
h2 = ParagraphStyle("h2", parent=base["Heading2"], fontName="DejaVu-Bold", fontSize=11.5, leading=15, spaceBefore=8, spaceAfter=4, textColor=colors.HexColor("#1b3a5c"))
title = ParagraphStyle("title", parent=h1, fontSize=20, leading=25, alignment=TA_LEFT)
bullet = ParagraphStyle("bullet", parent=body, leftIndent=12, bulletIndent=2)
cell = ParagraphStyle("cell", parent=body, fontSize=7.8, leading=9.6, spaceAfter=0)
cellb = ParagraphStyle("cellb", parent=cell, fontName="DejaVu-Bold")

WIDTH = A4[0] - 3.6 * cm


def para(text, style=body):
    return Paragraph(text, style)


def bullets(items):
    return [Paragraph(item, bullet, bulletText="•") for item in items]


def figure(path, text, width=WIDTH, max_height=19 * cm):
    w, h = PILImage.open(path).size
    scale = min(width / w, max_height / h)
    return KeepTogether([Image(str(path), width=w * scale, height=h * scale), Paragraph(text, caption)])


def table(rows, widths=None, header_rows=1):
    data = [[Paragraph(str(c), cellb if r < header_rows else cell) for c in row] for r, row in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=header_rows, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, header_rows - 1), colors.HexColor("#dde6f0")),
        ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#9aa7b5")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("ROWBACKGROUNDS", (0, header_rows), (-1, -1), [colors.white, colors.HexColor("#f5f7fa")]),
    ]))
    return t


def read(name):
    """A CSV of the report's `tables/`, or else of its `data/`."""
    path = HERE / "tables" / name
    with open(path if path.exists() else HERE / "data" / name) as f:
        return list(csv.DictReader(f))


def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("DejaVu", 7.5)
    canvas.setFillColor(colors.grey)
    canvas.drawString(1.8 * cm, 1.1 * cm, "FjordSim · oslofjorden_validation · preliminary validation, days 0–298 (2014-04-01 to 2015-01-24)")
    canvas.drawRightString(A4[0] - 1.8 * cm, 1.1 * cm, f"{doc.page}")
    canvas.restoreState()

