#!/usr/bin/env python3
"""Create a deterministic, page-identity inventory from local comic recordings.

This is intentionally an inventory, not a training exporter. OCR/translations recorded by
the app are observations, never ground truth. A reviewed catalog can assign recording
families to train/dev/holdout, while human labels remain separate from captured output.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
VALID_SPLITS = {"train", "dev", "holdout", "unassigned"}


def fail(message: str) -> None:
    raise SystemExit(f"comic dataset inventory: {message}")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain an object")
    return value


def required_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} is missing")
    return value


def required_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or value < 0:
        fail(f"{label} is invalid")
    return value


def load_catalog(path: Path | None) -> list[dict[str, Any]]:
    if path is None:
        return []
    raw = read_json(path)
    if raw.get("schemaVersion") != SCHEMA_VERSION:
        fail("catalog schemaVersion is unsupported")
    families = raw.get("families")
    if not isinstance(families, list):
        fail("catalog families must be an array")
    output: list[dict[str, Any]] = []
    ids: set[str] = set()
    for index, family in enumerate(families):
        if not isinstance(family, dict):
            fail(f"catalog family {index} must be an object")
        family_id = required_text(family.get("familyId"), f"catalog family {index} id")
        split = required_text(family.get("split"), f"catalog family {family_id} split")
        if family_id in ids or split not in VALID_SPLITS - {"unassigned"}:
            fail(f"catalog family {family_id} is invalid")
        prefixes = family.get("recordingIdPrefixes", [])
        hashes = family.get("imageHashes", [])
        if not isinstance(prefixes, list) or not isinstance(hashes, list):
            fail(f"catalog family {family_id} selectors must be arrays")
        if not prefixes and not hashes:
            fail(f"catalog family {family_id} needs a selector")
        if not all(isinstance(value, str) and value for value in prefixes + hashes):
            fail(f"catalog family {family_id} selector is invalid")
        ids.add(family_id)
        output.append({
            "familyId": family_id,
            "split": split,
            "recordingIdPrefixes": prefixes,
            "imageHashes": hashes,
        })
    return output


def assignment(recording_id: str, image_hash: str, catalog: list[dict[str, Any]]) -> tuple[str, str]:
    matches: list[dict[str, Any]] = []
    for family in catalog:
        prefix_match = any(recording_id.startswith(value) for value in family["recordingIdPrefixes"])
        hash_match = image_hash in family["imageHashes"]
        if prefix_match or hash_match:
            matches.append(family)
    if len(matches) > 1:
        fail(f"{recording_id} / {image_hash[:12]} matches more than one family")
    if not matches:
        return "unassigned", "unassigned"
    return matches[0]["familyId"], matches[0]["split"]


def timing_value(value: Any) -> int | None:
    return value if isinstance(value, int) and value >= 0 else None


def polygon_value(value: Any, label: str) -> list[dict[str, int]]:
    if not isinstance(value, list) or len(value) < 3:
        fail(f"{label} is invalid")
    points: list[dict[str, int]] = []
    for index, point in enumerate(value):
        if not isinstance(point, dict):
            fail(f"{label} point {index} is invalid")
        x = required_int(point.get("x"), f"{label} point {index} x")
        y = required_int(point.get("y"), f"{label} point {index} y")
        points.append({"x": x, "y": y})
    return points


def observe(
    analysis_path: Path,
    recording_root: Path,
    catalog: list[dict[str, Any]],
    include_text: bool,
) -> tuple[str, dict[str, Any]] | None:
    run_dir = analysis_path.parent
    render_path = run_dir / "render.json"
    manifest_path = run_dir / "manifest.json"
    if not render_path.is_file() or not manifest_path.is_file():
        return None
    analysis = read_json(analysis_path)
    render = read_json(render_path)
    manifest = read_json(manifest_path)
    document = analysis.get("document")
    if not isinstance(document, dict):
        fail(f"{analysis_path} document is invalid")
    image_hash = required_text(document.get("imageHash"), f"{analysis_path} imageHash")
    recording_id = required_text(manifest.get("recordingId"), f"{manifest_path} recordingId")
    blocks = document.get("blocks")
    layouts = render.get("layouts")
    if not isinstance(blocks, list) or not isinstance(layouts, list):
        fail(f"{run_dir} blocks or layouts are invalid")
    translation_map: dict[str, str] = {}
    translations = render.get("translations")
    if isinstance(translations, dict) and isinstance(translations.get("blocks"), list):
        for translation in translations["blocks"]:
            if not isinstance(translation, dict):
                fail(f"{render_path} translation block is invalid")
            block_id = required_text(translation.get("blockId"), f"{render_path} translation blockId")
            translated_text = translation.get("translatedText")
            if not isinstance(translated_text, str) or block_id in translation_map:
                fail(f"{render_path} translation block is invalid")
            translation_map[block_id] = translated_text
    family_id, split = assignment(recording_id, image_hash, catalog)
    kinds = Counter()
    source_origins = Counter()
    block_values: list[dict[str, Any]] = []
    for index, block in enumerate(blocks):
        if not isinstance(block, dict):
            fail(f"{analysis_path} block {index} is invalid")
        kind = str(block.get("kind", "other"))
        origin = str(block.get("sourceOrigin", "unknown"))
        kinds[kind] += 1
        source_origins[origin] += 1
        if include_text:
            block_id = str(block.get("blockId", ""))
            block_values.append({
                "blockId": block_id,
                "readingOrder": required_int(block.get("readingOrder"), f"{analysis_path} block {index} readingOrder"),
                "kind": kind,
                "sourceText": str(block.get("sourceText", "")),
                "normalizedSourceText": str(block.get("normalizedSourceText", "")),
                "translatedText": str(block.get("translatedText", "")) or translation_map.get(block_id, ""),
                "polygon": polygon_value(block.get("polygon"), f"{analysis_path} block {index} polygon"),
                "sourceOrigin": origin,
                "translationOrigin": str(block.get("translationOrigin", "unknown")),
            })
    timings = analysis.get("timings") if isinstance(analysis.get("timings"), dict) else {}
    render_timings = render.get("timings") if isinstance(render.get("timings"), dict) else {}
    observation: dict[str, Any] = {
        "recordingId": recording_id,
        "familyId": family_id,
        "split": split,
        "path": str(run_dir.relative_to(recording_root)),
        "pageIndex": required_int(document.get("pageIndex"), f"{analysis_path} pageIndex"),
        "backendId": str(analysis.get("backendId", "")),
        "profileId": str(analysis.get("profileId", "")),
        "analysisRevision": required_int(document.get("analysisRevision"), f"{analysis_path} analysisRevision"),
        "blockCount": len(blocks),
        "layoutCount": len(layouts),
        "blockKinds": dict(sorted(kinds.items())),
        "sourceOrigins": dict(sorted(source_origins.items())),
        "timingsMs": {
            "analysis": timing_value(timings.get("totalMs")),
            "render": timing_value(render_timings.get("totalMs")),
            "inpaint": timing_value(render_timings.get("inpaintMs")),
        },
        "renderStats": {
            "inpaintCallCount": timing_value(render_timings.get("inpaintCallCount")),
            "inpaintNativeCallMs": timing_value(render_timings.get("inpaintNativeCallMs")),
            "inpaintModelLoadMs": timing_value(render_timings.get("inpaintModelLoadMs")),
            "inpaintPreprocessingMs": timing_value(render_timings.get("inpaintPreprocessingMs")),
            "inpaintInferenceMs": timing_value(render_timings.get("inpaintInferenceMs")),
            "inpaintPostprocessingMs": timing_value(render_timings.get("inpaintPostprocessingMs")),
            "drawableGroupCount": timing_value(render_timings.get("drawableGroupCount")),
            "skippedGroupCount": timing_value(render_timings.get("skippedGroupCount")),
        },
        "assets": {
            "source": str(manifest.get("sourceImage", "source.jpg")),
            "rendered": str(manifest.get("renderedImage", "rendered.png")),
            "analysis": "analysis.json",
            "render": "render.json",
        },
    }
    if include_text:
        observation["observedBlocks"] = block_values
    page = {
        "sampleId": f"page-{image_hash}",
        "imageHash": image_hash,
        "imageWidth": required_int(document.get("imageWidth"), f"{analysis_path} imageWidth"),
        "imageHeight": required_int(document.get("imageHeight"), f"{analysis_path} imageHeight"),
        "labelState": "unlabeled",
        "observations": [observation],
    }
    return image_hash, page


def inventory(args: argparse.Namespace) -> dict[str, Any]:
    root = args.recording_root.resolve()
    if not root.is_dir():
        fail(f"recording root does not exist: {root}")
    catalog = load_catalog(args.catalog)
    pages: dict[str, dict[str, Any]] = {}
    skipped = 0
    for analysis_path in sorted(root.rglob("analysis.json")):
        value = observe(analysis_path, root, catalog, args.include_text)
        if value is None:
            skipped += 1
            continue
        image_hash, page = value
        current = pages.get(image_hash)
        if current is None:
            pages[image_hash] = page
            continue
        if current["imageWidth"] != page["imageWidth"] or current["imageHeight"] != page["imageHeight"]:
            fail(f"image identity {image_hash[:12]} has conflicting dimensions")
        current["observations"].extend(page["observations"])
    ordered_pages = [pages[key] for key in sorted(pages)]
    split_counts: Counter[str] = Counter()
    family_counts: Counter[str] = Counter()
    for page in ordered_pages:
        pairs = {(item["familyId"], item["split"]) for item in page["observations"]}
        assigned_pairs = {pair for pair in pairs if pair[1] != "unassigned"}
        if len(assigned_pairs) > 1:
            fail(f"image identity {page['imageHash'][:12]} crosses catalog families or splits")
        # Candidate/baseline recordings often use a different id from the catalogued primary
        # run. They still represent the same source image, so let an unassigned repeat inherit
        # the identity-level family. Two explicit assignments remain a hard leakage failure.
        family_id, split = (
            next(iter(assigned_pairs)) if assigned_pairs else ("unassigned", "unassigned")
        )
        page["familyId"] = family_id
        page["split"] = split
        split_counts[split] += 1
        family_counts[family_id] += 1
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "comic-recording-inventory",
        "recordingRoot": str(root),
        "observedTextIncluded": args.include_text,
        "summary": {
            "uniquePages": len(ordered_pages),
            "observations": sum(len(page["observations"]) for page in ordered_pages),
            "skippedIncompleteRuns": skipped,
            "bySplit": dict(sorted(split_counts.items())),
            "byFamily": dict(sorted(family_counts.items())),
        },
        "pages": ordered_pages,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recording-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--include-text", action="store_true")
    args = parser.parse_args()
    value = inventory(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(value["summary"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
