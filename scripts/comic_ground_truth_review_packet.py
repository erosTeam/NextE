#!/usr/bin/env python3
"""Build a local, read-only visual packet for a comic ground-truth template.

The packet deliberately does not alter the template or create truth. It puts the source,
recorded candidate polygons, layout boxes, and rendered output next to one another so a
single, independent review pass can fill the template without treating OCR output as truth.
"""

from __future__ import annotations

import argparse
import html
import json
import shutil
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"comic ground-truth review packet: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} is invalid")
    return value


def positive_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or value <= 0:
        fail(f"{label} is invalid")
    return value


def safe_copy(source: Path, destination: Path) -> None:
    if not source.is_file():
        fail(f"asset is missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def polygon_points(value: Any, label: str) -> str:
    if not isinstance(value, list) or len(value) < 3:
        fail(f"{label} is invalid")
    points: list[str] = []
    for index, point in enumerate(value):
        if not isinstance(point, dict):
            fail(f"{label}[{index}] is invalid")
        x = point.get("x")
        y = point.get("y")
        if not isinstance(x, int) or not isinstance(y, int):
            fail(f"{label}[{index}] is invalid")
        points.append(f"{x},{y}")
    return " ".join(points)


def rect_svg(value: Any, color: str, label: str) -> str:
    if not isinstance(value, dict):
        fail(f"{label} is invalid")
    fields = {name: value.get(name) for name in ("left", "top", "right", "bottom")}
    if not all(isinstance(number, (int, float)) for number in fields.values()):
        fail(f"{label} is invalid")
    width = float(fields["right"]) - float(fields["left"])
    height = float(fields["bottom"]) - float(fields["top"])
    if width <= 0 or height <= 0:
        fail(f"{label} is empty")
    return (
        f'<rect class="layout" stroke="{color}" x="{fields["left"]}" '
        f'y="{fields["top"]}" width="{width}" height="{height}"/>'
    )


def page_overlay(page: dict[str, Any]) -> str:
    width = positive_int(page.get("imageWidth"), "page imageWidth")
    height = positive_int(page.get("imageHeight"), "page imageHeight")
    parts: list[str] = []
    regions = page.get("candidateRegions")
    if not isinstance(regions, list):
        fail("page candidateRegions is invalid")
    for index, region in enumerate(regions):
        if not isinstance(region, dict):
            fail(f"candidateRegions[{index}] is invalid")
        candidate = region.get("candidate")
        if not isinstance(candidate, dict):
            fail(f"candidateRegions[{index}].candidate is invalid")
        candidate_id = text(region.get("candidateId"), f"candidateRegions[{index}].candidateId")
        points = polygon_points(candidate.get("polygon"), f"candidateRegions[{index}].polygon")
        first = candidate["polygon"][0]
        parts.append(
            '<polygon class="candidate" points="%s"/><text class="candidate-label" x="%s" y="%s">%s</text>'
            % (points, first["x"], max(14, first["y"] - 3), html.escape(candidate_id))
        )
        layouts = region.get("candidateLayouts", [])
        if not isinstance(layouts, list):
            fail(f"candidateRegions[{index}].candidateLayouts is invalid")
        for layout_index, layout in enumerate(layouts):
            if not isinstance(layout, dict):
                fail(f"candidateRegions[{index}].candidateLayouts[{layout_index}] is invalid")
            parts.append(rect_svg(layout.get("textRect"), "#ff9f1c", "layout textRect"))
    return (
        f'<svg class="overlay" viewBox="0 0 {width} {height}" aria-hidden="true">'
        + "".join(parts)
        + "</svg>"
    )


def page_card(
    page: dict[str, Any],
    recording_root: Path,
    asset_root: Path,
    packet_root: Path,
    index: int,
) -> str:
    provenance = page.get("provenance")
    if not isinstance(provenance, dict):
        fail("page provenance is invalid")
    recorded_path = Path(text(provenance.get("path"), "page provenance path"))
    source_dir = recorded_path if recorded_path.is_absolute() else recording_root / recorded_path
    assets = provenance.get("assets")
    if not isinstance(assets, dict):
        fail("page assets are invalid")
    source_name = text(assets.get("source"), "source asset")
    rendered_name = text(assets.get("rendered"), "rendered asset")
    key = f"page-{index:02d}"
    source_target = asset_root / f"{key}-source{Path(source_name).suffix}"
    rendered_target = asset_root / f"{key}-rendered{Path(rendered_name).suffix}"
    safe_copy(source_dir / source_name, source_target)
    safe_copy(source_dir / rendered_name, rendered_target)
    source_relative = source_target.relative_to(packet_root).as_posix()
    rendered_relative = rendered_target.relative_to(packet_root).as_posix()
    sample_id = text(page.get("sampleId"), "page sampleId")
    candidate_count = len(page.get("candidateRegions", []))
    return f"""
<article id="{html.escape(key)}">
  <h2>{html.escape(sample_id)}</h2>
  <p>{candidate_count} recorded candidate regions. Cyan: source candidate; amber: rendered layout.</p>
  <div class="grid">
    <figure class="source"><img src="{html.escape(source_relative)}" alt="source {html.escape(sample_id)}">{page_overlay(page)}</figure>
    <figure><img src="{html.escape(rendered_relative)}" alt="rendered {html.escape(sample_id)}"></figure>
  </div>
</article>"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    template = read_object(args.template.expanduser().resolve())
    if template.get("kind") != "comic-ground-truth-template":
        fail("template kind is invalid")
    pages = template.get("pages")
    if not isinstance(pages, list) or not pages:
        fail("template pages are invalid")
    inventory_path = Path(text(template.get("sourceInventory"), "template sourceInventory"))
    inventory = read_object(inventory_path)
    recording_root = Path(text(inventory.get("recordingRoot"), "inventory recordingRoot"))
    if not recording_root.is_dir():
        fail(f"inventory recordingRoot is missing: {recording_root}")
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    asset_root = output / "assets"
    cards = [
        page_card(page, recording_root, asset_root, output, index)
        for index, page in enumerate(pages)
    ]
    document = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Comic ground-truth review</title>
<style>
body{background:#101216;color:#e9edf2;font:15px system-ui,sans-serif;margin:0 auto;max-width:1500px;padding:24px}
article{border-top:1px solid #39414a;padding:20px 0}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}figure{margin:0;position:relative}img{display:block;width:100%;height:auto}.overlay{inset:0;position:absolute;width:100%;height:100%;pointer-events:none}.candidate{fill:none;stroke:#21d4fd;stroke-width:3}.candidate-label{fill:#21d4fd;font:18px monospace;paint-order:stroke;stroke:#101216;stroke-width:4}.layout{fill:none;stroke-width:3;stroke-dasharray:9 6}p{color:#b8c2cc}@media(max-width:900px){.grid{grid-template-columns:1fr}}
</style></head><body>
<h1>Read-only comic ground-truth review packet</h1>
<p>Use this packet only to inspect the source and recorded output. Edit the paired JSON template independently; do not copy candidates into truth without visual review.</p>
""" + "\n".join(cards) + "</body></html>\n"
    (output / "index.html").write_text(document, encoding="utf-8")
    print(json.dumps({"pages": len(pages), "packet": str(output / "index.html")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
