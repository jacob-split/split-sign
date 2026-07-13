#!/usr/bin/env python3
"""Prepare the clean Payroc LOD PDF for use as a reusable DocuSeal master."""

from __future__ import annotations

import argparse
import io
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    reader = PdfReader(str(args.source))
    if len(reader.pages) != 1:
        raise RuntimeError("Payroc LOD source must be one page")

    page = reader.pages[0]
    page.pop("/Annots", None)

    overlay_bytes = io.BytesIO()
    overlay = canvas.Canvas(overlay_bytes, pagesize=(612, 792))
    overlay.setFillColorRGB(1, 1, 1)
    # Remove literal template prompts; DocuSeal semantic fields occupy these slots.
    # Keep the date mask below the heading so it cannot clip "EXHIBIT".
    overlay.rect(60, 675, 155, 30, fill=1, stroke=0)  # [DATE]
    overlay.rect(305, 124, 235, 22, fill=1, stroke=0)  # [NAME OF SELLER/MERCHANT]
    # Normalize the heading because older prepared masters used an oversized
    # date mask that covered its left edge.
    overlay.rect(145, 714, 330, 32, fill=1, stroke=0)
    overlay.setFillColorRGB(0, 0, 0)
    overlay.setFont("Times-Bold", 14)
    overlay.drawCentredString(306, 728, "EXHIBIT A / LETTER OF DIRECTION")
    overlay.setStrokeColorRGB(0, 0, 0)
    overlay.setLineWidth(0.6)
    overlay.line(326, 128, 505, 128)
    overlay.save()
    overlay_bytes.seek(0)
    page.merge_page(PdfReader(overlay_bytes).pages[0])

    writer = PdfWriter()
    writer.add_page(page)
    writer.write(str(args.destination))


if __name__ == "__main__":
    main()
