#!/usr/bin/env python3
"""Create a local v3 container-review template from one real recording.

The template contains observed candidate boxes only as review aids. It is rejected by
comic_visual_regression.py until every page is explicitly marked ``reviewed`` and the
reviewer has supplied independent target rectangles.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 3


def fail(message: str) -> None:
    raise SystemExit(f"comic container review template: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def bounded_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or value <= 0:
        fail(f"{label} is invalid")
    return value


def rect(value: Any) -> list[float] | None:
    if not isinstance(value, dict):
        return None
    coordinates: list[float] = []
    for name in ("left", "top", "right", "bottom"):
        coordinate = value.get(name)
        if not isinstance(coordinate, (int, float)) or isinstance(coordinate, bool):
            return None
        coordinates.append(float(coordinate))
    if coordinates[2] <= coordinates[0] or coordinates[3] <= coordinates[1]:
        return None
    return coordinates


def candidate_hints(render: dict[str, Any]) -> dict[int, dict[str, Any]]:
    values = render.get("layouts")
    if not isinstance(values, list):
        fail("render layouts are invalid")
    output: dict[int, dict[str, Any]] = {}
    for value in values:
        if not isinstance(value, dict):
            continue
        label = value.get("containerLabel")
        if not isinstance(label, int) or label <= 0 or label in output:
            continue
        text_rect = value.get("textRect")
        if not isinstance(text_rect, dict):
            continue
        hint: dict[str, Any] = {
            "textRect": rect(text_rect),
            "confidence": text_rect.get("containerConfidence"),
            "probeOutcome": text_rect.get("containerProbeOutcome"),
        }
        output[label] = hint
    return output


def label_rectangles(path: Path, width: int, height: int) -> dict[int, list[int]]:
    try:
        data = path.read_bytes()
    except OSError as error:
        fail(f"cannot read {path}: {error}")
    expected_bytes = width * height
    if len(data) != expected_bytes:
        fail(f"{path} has {len(data)} bytes, expected {expected_bytes}")
    bounds: dict[int, list[int]] = {}
    for index, label in enumerate(data):
        if label == 0:
            continue
        x = index % width
        y = index // width
        existing = bounds.get(label)
        if existing is None:
            bounds[label] = [x, y, x + 1, y + 1]
        else:
            existing[0] = min(existing[0], x)
            existing[1] = min(existing[1], y)
            existing[2] = max(existing[2], x + 1)
            existing[3] = max(existing[3], y + 1)
    return bounds


def page_template(run_dir: Path) -> dict[str, Any]:
    render = read_object(run_dir / "render.json")
    manifest = read_object(run_dir / "manifest.json")
    label_file = render.get("containerLabelsFile")
    bounds: dict[int, list[int]] = {}
    if isinstance(label_file, str) and label_file:
        width = bounded_int(render.get("containerLabelsWidth"), "containerLabelsWidth")
        height = bounded_int(render.get("containerLabelsHeight"), "containerLabelsHeight")
        bounds = label_rectangles(run_dir / label_file, width, height)
    else:
        source = render.get("source")
        if not isinstance(source, dict):
            fail(f"{run_dir} has neither labels nor source dimensions")
        width = bounded_int(source.get("imageWidth"), "source.imageWidth")
        height = bounded_int(source.get("imageHeight"), "source.imageHeight")
    hints = candidate_hints(render)
    candidates: list[dict[str, Any]] = []
    for label in sorted(bounds):
        candidate: dict[str, Any] = {"label": label, "rect": bounds[label]}
        hint = hints.get(label)
        if hint is not None:
            candidate["textRect"] = hint["textRect"]
            candidate["confidence"] = hint["confidence"]
            candidate["probeOutcome"] = hint["probeOutcome"]
        candidates.append(candidate)
    source_name = manifest.get("sourceImage", "source.webp")
    if not isinstance(source_name, str) or not source_name:
        source_name = "source.webp"
    return {
        "id": run_dir.name,
        "reviewState": "needs_review",
        "imageWidth": width,
        "imageHeight": height,
        "source": source_name,
        "targets": [],
        "candidates": candidates,
        "notes": "Add independently reviewed target rectangles, then set reviewState to reviewed.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recording-dir", type=Path, required=True)
    parser.add_argument("--fixture-set-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    recording_dir = args.recording_dir.expanduser().resolve()
    if not recording_dir.is_dir():
        fail(f"recording directory is missing: {recording_dir}")
    run_dirs = sorted(path.parent for path in recording_dir.glob("*/render.json"))
    if not run_dirs:
        fail("recording directory has no direct page render.json files")
    output = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "comic-container-review",
        "fixtureSetId": args.fixture_set_id,
        "recordingDir": str(recording_dir),
        "instructions": [
            "Candidate fields are observations, not ground truth.",
            "Review the local source and overlay, then add every true container to targets.",
            "Do not change candidate rectangles to hide misses.",
            "Set every page reviewState to reviewed before using this file for metrics.",
        ],
        "pages": [page_template(run_dir) for run_dir in run_dirs],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"pages": len(output["pages"]), "fixtureSetId": args.fixture_set_id}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
