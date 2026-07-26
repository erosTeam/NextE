#!/usr/bin/env python3
"""Rank recorded comic observations for the next real-page visual review.

This is deliberately a triage tool, not a quality score or a training exporter. It only
uses observable layout risk signals and never turns a recorded OCR/translation result into
ground truth. Its job is to send a reviewer first to pages where a real regression is most
likely to be visible.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CONFIRMED_CONTAINER_OUTCOMES = {"accepted", "accepted_rect_border"}


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset triage: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def rect(value: Any, label: str) -> tuple[float, float, float, float]:
    if not isinstance(value, dict):
        fail(f"{label} is invalid")
    values: list[float] = []
    for name in ("left", "top", "right", "bottom"):
        coordinate = value.get(name)
        if not isinstance(coordinate, (int, float)) or isinstance(coordinate, bool):
            fail(f"{label}.{name} is invalid")
        values.append(float(coordinate))
    if values[2] <= values[0] or values[3] <= values[1]:
        fail(f"{label} is empty")
    return values[0], values[1], values[2], values[3]


def intersects(left: tuple[float, float, float, float], right: tuple[float, float, float, float]) -> bool:
    return min(left[2], right[2]) > max(left[0], right[0]) and min(left[3], right[3]) > max(left[1], right[1])


def observation_row(page: dict[str, Any], observation: dict[str, Any]) -> dict[str, Any]:
    layouts = observation.get("renderLayouts", [])
    if not isinstance(layouts, list):
        fail("renderLayouts is invalid")
    layout_rects: list[tuple[float, float, float, float]] = []
    unconfirmed = 0
    constrained = 0
    small_font = 0
    for index, layout in enumerate(layouts):
        if not isinstance(layout, dict):
            fail(f"renderLayouts[{index}] is invalid")
        layout_rects.append(rect(layout.get("textRect"), f"renderLayouts[{index}].textRect"))
        outcome = layout.get("containerProbeOutcome", "")
        if not isinstance(outcome, str):
            fail(f"renderLayouts[{index}].containerProbeOutcome is invalid")
        if outcome and outcome not in CONFIRMED_CONTAINER_OUTCOMES:
            unconfirmed += 1
        if layout.get("shapeConstrained") is True:
            constrained += 1
        font_size = layout.get("fontSize")
        if isinstance(font_size, (int, float)) and not isinstance(font_size, bool) and font_size < 12:
            small_font += 1
    overlap_pairs = 0
    for left in range(len(layout_rects)):
        for right in range(left + 1, len(layout_rects)):
            if intersects(layout_rects[left], layout_rects[right]):
                overlap_pairs += 1
    stats = observation.get("renderStats", {})
    skipped = 0
    if isinstance(stats, dict) and isinstance(stats.get("skippedGroupCount"), int):
        skipped = max(0, stats["skippedGroupCount"])
    # Lexicographic ordering avoids converting these distinct facts into a fake universal score.
    priority = [skipped, overlap_pairs, unconfirmed, small_font]
    return {
        "sampleId": str(page.get("sampleId", "")),
        "familyId": str(page.get("familyId", "unassigned")),
        "split": str(page.get("split", "unassigned")),
        "recordingId": str(observation.get("recordingId", "")),
        "path": str(observation.get("path", "")),
        "pageIndex": observation.get("pageIndex"),
        "layoutCount": len(layouts),
        "skippedGroups": skipped,
        "overlappingTextRectPairs": overlap_pairs,
        "unconfirmedContainerLayouts": unconfirmed,
        "shapeConstrainedLayouts": constrained,
        "smallFontLayouts": small_font,
        "priority": priority,
    }


def priority_key(row: dict[str, Any]) -> tuple[int, int, int, int, str, int]:
    priority = row["priority"]
    return (
        -int(priority[0]),
        -int(priority[1]),
        -int(priority[2]),
        -int(priority[3]),
        str(row["recordingId"]),
        int(row["pageIndex"]) if isinstance(row["pageIndex"], int) else -1,
    )


def unique_pages(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_sample: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        sample_id = str(row["sampleId"])
        by_sample.setdefault(sample_id, []).append(row)
    output: list[dict[str, Any]] = []
    for sample_id in sorted(by_sample):
        observations = sorted(by_sample[sample_id], key=priority_key)
        selected = dict(observations[0])
        selected["observationCount"] = len(observations)
        selected["relatedRecordingIds"] = sorted({
            str(observation["recordingId"])
            for observation in observations
        })
        output.append(selected)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=30)
    args = parser.parse_args()
    if args.limit <= 0:
        fail("limit must be positive")
    inventory = read_object(args.inventory)
    if inventory.get("kind") != "comic-recording-inventory":
        fail("inventory kind is unsupported")
    pages = inventory.get("pages")
    if not isinstance(pages, list):
        fail("inventory pages are invalid")
    rows: list[dict[str, Any]] = []
    for page in pages:
        if not isinstance(page, dict):
            fail("inventory page is invalid")
        observations = page.get("observations")
        if not isinstance(observations, list):
            fail("inventory observations are invalid")
        for observation in observations:
            if isinstance(observation, dict):
                rows.append(observation_row(page, observation))
    ranked = sorted(unique_pages(rows), key=priority_key)
    output = {
        "schemaVersion": 1,
        "kind": "comic-recording-triage",
        "inventory": str(args.inventory),
        "ranking": "one highest-risk observation per page: skipped groups, overlapping layout rectangles, unconfirmed containers, small fonts",
        "summary": {
            "observations": len(rows),
            "uniquePages": len(ranked),
            "returned": min(args.limit, len(ranked)),
        },
        "observations": ranked[:args.limit],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(output["summary"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
