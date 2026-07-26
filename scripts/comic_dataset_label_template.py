#!/usr/bin/env python3
"""Create an unreviewed ground-truth template from recorded comic observations.

The emitted candidate text, category, and geometry are review aids only. They are
deliberately separated from the empty truth fields so captured OCR/model output can
never silently become training or evaluation truth.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset label template: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def candidate_region(block: dict[str, Any]) -> dict[str, Any]:
    polygon = block.get("polygon")
    if not isinstance(polygon, list):
        fail("inventory was not generated with geometry-bearing observed blocks")
    return {
        "candidateId": str(block.get("blockId", "")),
        "candidate": {
            "readingOrder": block.get("readingOrder"),
            "kind": str(block.get("kind", "other")),
            "polygon": polygon,
            "sourceText": str(block.get("sourceText", "")),
            "normalizedSourceText": str(block.get("normalizedSourceText", "")),
            "translatedText": str(block.get("translatedText", "")),
            "sourceOrigin": str(block.get("sourceOrigin", "unknown")),
            "translationOrigin": str(block.get("translationOrigin", "unknown")),
        },
        "reviewState": "needs_review",
        "truth": {
            "shouldProcess": None,
            "kind": None,
            "polygon": [],
            "sourceTranscript": "",
            "targetReferences": [],
            "visualLabels": [],
            "notes": "",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--family", required=True)
    parser.add_argument("--recording-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    inventory = read_object(args.inventory)
    if inventory.get("kind") != "comic-recording-inventory" or not inventory.get("observedTextIncluded"):
        fail("inventory must be a text-inclusive comic recording inventory")
    pages = inventory.get("pages")
    if not isinstance(pages, list):
        fail("inventory pages are invalid")

    template_pages: list[dict[str, Any]] = []
    for page in pages:
        if not isinstance(page, dict) or page.get("familyId") != args.family:
            continue
        observations = page.get("observations")
        if not isinstance(observations, list):
            fail("inventory page observations are invalid")
        matches = [item for item in observations if isinstance(item, dict) and item.get("recordingId") == args.recording_id]
        if len(matches) != 1:
            fail(f"{page.get('sampleId', 'unknown')} needs exactly one observation for {args.recording_id}")
        observation = matches[0]
        blocks = observation.get("observedBlocks")
        if not isinstance(blocks, list):
            fail(f"{page.get('sampleId', 'unknown')} lacks observed blocks")
        template_pages.append({
            "sampleId": str(page.get("sampleId", "")),
            "imageHash": str(page.get("imageHash", "")),
            "imageWidth": page.get("imageWidth"),
            "imageHeight": page.get("imageHeight"),
            "familyId": args.family,
            "split": str(page.get("split", "unassigned")),
            "reviewState": "needs_review",
            "provenance": {
                "recordingId": args.recording_id,
                "path": str(observation.get("path", "")),
                "assets": observation.get("assets", {}),
            },
            "candidateRegions": [candidate_region(item) for item in blocks if isinstance(item, dict)],
            "additionalRegions": [],
            "pageNotes": "",
        })
    if not template_pages:
        fail(f"no pages found for family {args.family}")

    output = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "comic-ground-truth-template",
        "sourceInventory": str(args.inventory),
        "selection": {"familyId": args.family, "recordingId": args.recording_id},
        "instructions": [
            "Candidate fields are observations, not ground truth.",
            "Fill truth only after reviewing the source image and rendered output.",
            "Use additionalRegions for missed text; never edit candidates to conceal misses.",
            "Keep this file separate from held-out score inputs until reviewState is complete.",
        ],
        "pages": template_pages,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"pages": len(template_pages), "familyId": args.family}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
