#!/usr/bin/env python3
"""Validate reviewed comic ground-truth labels before scoring or training export."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


REVIEW_STATES = {"needs_review", "reviewed"}
PROCESS_KINDS = {"dialogue", "caption", "sfx", "other"}
NON_PROCESS_KINDS = {"artwork", "ignore"}
USAGE_SPLITS = {
    "train": {"train"},
    "dev": {"dev"},
    "evaluation": {"dev", "holdout"},
}


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset labels: {message}")


def read_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def valid_polygon(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) >= 3
        and all(
            isinstance(point, dict)
            and isinstance(point.get("x"), int)
            and isinstance(point.get("y"), int)
            and point["x"] >= 0
            and point["y"] >= 0
            for point in value
        )
    )


def validate_region(region: dict[str, Any], location: str, complete: bool) -> str:
    state = region.get("reviewState")
    if state not in REVIEW_STATES:
        fail(f"{location} has an invalid reviewState")
    if complete and state != "reviewed":
        fail(f"{location} remains unreviewed")
    truth = region.get("truth")
    if not isinstance(truth, dict):
        fail(f"{location} truth is invalid")
    should_process = truth.get("shouldProcess")
    if state == "needs_review":
        if should_process is not None:
            fail(f"{location} has partial truth while still needs_review")
        return "pending"
    if not isinstance(should_process, bool):
        fail(f"{location} reviewed truth needs boolean shouldProcess")
    kind = truth.get("kind")
    if should_process:
        if kind not in PROCESS_KINDS:
            fail(f"{location} processable truth needs a text kind")
        if not valid_polygon(truth.get("polygon")):
            fail(f"{location} processable truth needs a polygon")
        if not nonempty_text(truth.get("sourceTranscript")):
            fail(f"{location} processable truth needs sourceTranscript")
        references = truth.get("targetReferences")
        if not isinstance(references, list) or not references or not all(nonempty_text(item) for item in references):
            fail(f"{location} processable truth needs targetReferences")
        return "processable"
    if kind not in NON_PROCESS_KINDS:
        fail(f"{location} non-processable truth needs artwork or ignore kind")
    return "non_processable"


def validate_page(page: dict[str, Any], index: int, complete: bool) -> Counter[str]:
    sample_id = page.get("sampleId")
    if not nonempty_text(sample_id) or page.get("reviewState") not in REVIEW_STATES:
        fail(f"page {index} is invalid")
    if complete and page["reviewState"] != "reviewed":
        fail(f"page {sample_id} remains unreviewed")
    regions = page.get("candidateRegions")
    additional = page.get("additionalRegions")
    if not isinstance(regions, list) or not isinstance(additional, list):
        fail(f"page {sample_id} regions are invalid")
    ids: set[str] = set()
    counts: Counter[str] = Counter()
    for prefix, values in (("candidate", regions), ("additional", additional)):
        for region_index, region in enumerate(values):
            if not isinstance(region, dict):
                fail(f"page {sample_id} {prefix} region {region_index} is invalid")
            region_id = str(region.get("candidateId" if prefix == "candidate" else "regionId", ""))
            if not region_id or region_id in ids:
                fail(f"page {sample_id} has duplicate or empty region id")
            ids.add(region_id)
            counts[validate_region(region, f"page {sample_id} {prefix} {region_id}", complete)] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument("--usage", choices=sorted(USAGE_SPLITS), required=True)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    labels = read_object(args.labels)
    if labels.get("kind") != "comic-ground-truth-template":
        fail("label kind is unsupported")
    pages = labels.get("pages")
    if not isinstance(pages, list) or not pages:
        fail("labels need at least one page")
    allowed_splits = USAGE_SPLITS[args.usage]
    page_ids: set[str] = set()
    counts: Counter[str] = Counter()
    splits: Counter[str] = Counter()
    for index, page in enumerate(pages):
        if not isinstance(page, dict):
            fail(f"page {index} is invalid")
        sample_id = page.get("sampleId")
        if not isinstance(sample_id, str) or not sample_id or sample_id in page_ids:
            fail("labels have duplicate or empty sampleId")
        page_ids.add(sample_id)
        split = page.get("split")
        if split not in allowed_splits:
            fail(f"page {sample_id} split {split!r} is not allowed for {args.usage}")
        splits[str(split)] += 1
        counts.update(validate_page(page, index, args.require_complete))
    print(json.dumps({
        "pages": len(pages),
        "usage": args.usage,
        "complete": args.require_complete,
        "bySplit": dict(sorted(splits.items())),
        "regions": dict(sorted(counts.items())),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
