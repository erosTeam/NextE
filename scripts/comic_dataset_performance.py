#!/usr/bin/env python3
"""Summarise per-recording comic analysis/render timings from an inventory."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset performance: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def percentile(values: list[int], fraction: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, int((len(ordered) - 1) * fraction + 0.999999)))
    return ordered[index]


def median(values: list[int]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[middle])
    return (ordered[middle - 1] + ordered[middle]) / 2


def summary(values: list[int]) -> dict[str, float | int | None]:
    return {"count": len(values), "median": median(values), "p90": percentile(values, 0.9)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    inventory = read_object(args.inventory)
    if inventory.get("kind") != "comic-recording-inventory":
        fail("inventory kind is unsupported")
    pages = inventory.get("pages")
    if not isinstance(pages, list):
        fail("inventory pages are invalid")
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get("observations"), list):
            fail("inventory page is invalid")
        for observation in page["observations"]:
            if not isinstance(observation, dict) or not isinstance(observation.get("recordingId"), str):
                fail("inventory observation is invalid")
            merged = dict(observation)
            merged["familyId"] = page.get("familyId", "unassigned")
            merged["split"] = page.get("split", "unassigned")
            groups[observation["recordingId"]].append(merged)
    records: list[dict[str, Any]] = []
    for recording_id in sorted(groups):
        observations = groups[recording_id]
        families = {str(item["familyId"]) for item in observations}
        splits = {str(item["split"]) for item in observations}
        profiles = {str(item.get("profileId", "")) for item in observations}
        backends = {str(item.get("backendId", "")) for item in observations}
        if len(families) != 1 or len(splits) != 1 or len(profiles) != 1 or len(backends) != 1:
            fail(f"recording {recording_id} has inconsistent identity metadata")
        timings: dict[str, list[int]] = {"analysis": [], "render": [], "inpaint": []}
        render_stats: dict[str, list[int]] = {
            "inpaintCalls": [],
            "inpaintNativeCall": [],
            "inpaintModelLoad": [],
            "inpaintPreprocessing": [],
            "inpaintInference": [],
            "inpaintPostprocessing": [],
            "drawableGroups": [],
            "skippedGroups": [],
            "inpaintMsPerCall": [],
        }
        for item in observations:
            raw = item.get("timingsMs")
            if not isinstance(raw, dict):
                continue
            for key in timings:
                value = raw.get(key)
                if isinstance(value, int) and value >= 0:
                    timings[key].append(value)
            raw_stats = item.get("renderStats")
            if isinstance(raw_stats, dict):
                count = raw_stats.get("inpaintCallCount")
                if isinstance(count, int) and count >= 0:
                    render_stats["inpaintCalls"].append(count)
                    inpaint = raw.get("inpaint") if isinstance(raw, dict) else None
                    if isinstance(inpaint, int) and inpaint >= 0 and count > 0:
                        render_stats["inpaintMsPerCall"].append(round(inpaint / count))
                for input_key, output_key in (
                    ("inpaintNativeCallMs", "inpaintNativeCall"),
                    ("inpaintModelLoadMs", "inpaintModelLoad"),
                    ("inpaintPreprocessingMs", "inpaintPreprocessing"),
                    ("inpaintInferenceMs", "inpaintInference"),
                    ("inpaintPostprocessingMs", "inpaintPostprocessing"),
                    ("drawableGroupCount", "drawableGroups"),
                    ("skippedGroupCount", "skippedGroups"),
                ):
                    value = raw_stats.get(input_key)
                    if isinstance(value, int) and value >= 0:
                        render_stats[output_key].append(value)
        records.append({
            "recordingId": recording_id,
            "familyId": next(iter(families)),
            "split": next(iter(splits)),
            "backendId": next(iter(backends)),
            "profileId": next(iter(profiles)),
            "pages": len(observations),
            "blockCount": summary([int(item.get("blockCount", 0)) for item in observations]),
            "layoutCount": summary([int(item.get("layoutCount", 0)) for item in observations]),
            "timingsMs": {key: summary(value) for key, value in timings.items()},
            "renderStats": {key: summary(value) for key, value in render_stats.items()},
        })
    output = {
        "schemaVersion": 1,
        "kind": "comic-recording-performance",
        "inventory": str(args.inventory),
        "recordings": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"recordings": len(records)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
