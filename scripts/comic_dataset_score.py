#!/usr/bin/env python3
"""Score observed comic recording text against the existing reviewed reference manifest."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset score: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def normalise(value: str) -> str:
    return re.sub(r"\s+", "", value).replace("？", "?")


def percent(numerator: int, denominator: int) -> float:
    return round(numerator * 10000 / denominator) / 100 if denominator else 100.0


def score_observation(
    page: dict[str, Any],
    observation: dict[str, Any],
    reference: dict[str, Any],
) -> dict[str, Any]:
    blocks = observation.get("observedBlocks")
    expected_blocks = reference.get("blocks")
    if not isinstance(blocks, list) or not isinstance(expected_blocks, list):
        fail("inventory must be created with --include-text and reference blocks must be an array")
    matched: set[int] = set()
    previous = -1
    missing = 0
    order_errors = 0
    required_term_errors = 0
    matched_count = 0
    for expected in expected_blocks:
        if not isinstance(expected, dict) or not isinstance(expected.get("sourceVariants"), list):
            fail("reference block is invalid")
        variants = {normalise(value) for value in expected["sourceVariants"] if isinstance(value, str)}
        match = -1
        for index, actual in enumerate(blocks):
            if index in matched or not isinstance(actual, dict):
                continue
            if normalise(str(actual.get("sourceText", ""))) in variants:
                match = index
                break
        if match < 0:
            missing += 1
            continue
        matched.add(match)
        matched_count += 1
        if match < previous:
            order_errors += 1
        previous = match
        terms = expected.get("requiredTranslationTerms", [])
        translated = str(blocks[match].get("translatedText", ""))
        if any(isinstance(term, str) and term not in translated for term in terms):
            required_term_errors += 1
    unexpected = len(blocks) - len(matched)
    return {
        "sampleId": page.get("sampleId", ""),
        "imageHash": page.get("imageHash", ""),
        "familyId": page.get("familyId", "unassigned"),
        "split": page.get("split", "unassigned"),
        "recordingId": observation.get("recordingId", ""),
        "path": observation.get("path", ""),
        "expectedBlocks": len(expected_blocks),
        "actualBlocks": len(blocks),
        "matchedSourceBlocks": matched_count,
        "missingSourceBlocks": missing,
        "unexpectedSourceBlocks": unexpected,
        "readingOrderErrors": order_errors,
        "requiredTranslationTermErrors": required_term_errors,
        "sourceRecallPercent": percent(matched_count, len(expected_blocks)),
        "sourcePrecisionPercent": percent(matched_count, len(blocks)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--reference-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    inventory = read_object(args.inventory)
    reference = read_object(args.reference_manifest)
    if inventory.get("kind") != "comic-recording-inventory" or not inventory.get("observedTextIncluded"):
        fail("inventory must be a text-inclusive comic recording inventory")
    pages = inventory.get("pages")
    reference_pages = reference.get("pages")
    if not isinstance(pages, list) or not isinstance(reference_pages, list):
        fail("inventory or reference pages are invalid")
    by_hash = {page.get("imageHash"): page for page in pages if isinstance(page, dict)}
    rows: list[dict[str, Any]] = []
    for expected in reference_pages:
        if not isinstance(expected, dict):
            fail("reference page is invalid")
        image_hash = expected.get("sha256")
        page = by_hash.get(image_hash)
        if not isinstance(image_hash, str) or page is None:
            fail(f"reference image is absent from inventory: {image_hash}")
        observations = page.get("observations")
        if not isinstance(observations, list) or not observations:
            fail(f"reference image has no observations: {image_hash}")
        for observation in observations:
            if isinstance(observation, dict):
                rows.append(score_observation(page, observation, expected))
    totals = {
        "observations": len(rows),
        "expectedBlocks": sum(row["expectedBlocks"] for row in rows),
        "actualBlocks": sum(row["actualBlocks"] for row in rows),
        "matchedSourceBlocks": sum(row["matchedSourceBlocks"] for row in rows),
        "missingSourceBlocks": sum(row["missingSourceBlocks"] for row in rows),
        "unexpectedSourceBlocks": sum(row["unexpectedSourceBlocks"] for row in rows),
        "readingOrderErrors": sum(row["readingOrderErrors"] for row in rows),
        "requiredTranslationTermErrors": sum(row["requiredTranslationTermErrors"] for row in rows),
    }
    totals["sourceRecallPercent"] = percent(totals["matchedSourceBlocks"], totals["expectedBlocks"])
    totals["sourcePrecisionPercent"] = percent(totals["matchedSourceBlocks"], totals["actualBlocks"])
    output = {
        "schemaVersion": 1,
        "kind": "comic-recording-score",
        "inventory": str(args.inventory),
        "referenceManifest": str(args.reference_manifest),
        "summary": totals,
        "observations": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(totals, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
