#!/usr/bin/env python3
"""Build a local visual-regression report from real comic page artifacts.

The manifest and every referenced image are intentionally local inputs. Keep
them under an ignored artifact directory such as .hvigor/outputs; do not add
third-party manga pages, OCR text, translations, gallery identifiers, or hashes
to the repository.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import shutil
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import numpy as np
    from PIL import Image, ImageChops, ImageDraw
except ImportError as error:
    raise SystemExit(
        "comic_visual_regression.py requires Pillow and NumPy. "
        "Run it with the Codex workspace Python runtime or install the packages "
        "in an isolated development environment."
    ) from error


SCHEMA_VERSION = 1
DEFAULT_PIXEL_DELTA = 24
DEFAULT_NEAR_WHITE = 245
DEFAULT_SOURCE_WHITE = 235
DEFAULT_FLAT_BLOCK = 12
DEFAULT_TEXTURE_STD = 20.0
DEFAULT_FLAT_STD = 5.0
DEFAULT_COMPONENT_PIXELS = 24
HIGH_CONTAINER_CONFIDENCE = 0.65
THUMBNAIL_EDGE = 1400


@dataclass(frozen=True)
class ContainerCandidate:
    label: int
    confidence: float
    probe_outcome: str
    raw_coverage: float | None
    solidity: float | None
    area_ratio: float | None
    luminance_std: float | None


@dataclass(frozen=True)
class RectangularBorderProbe:
    outcome: str
    left_score: float
    right_score: float
    top_score: float
    bottom_score: float
    top_left_corner_score: float
    top_right_corner_score: float
    bottom_left_corner_score: float
    bottom_right_corner_score: float


@dataclass(frozen=True)
class SourceLayout:
    index: int
    rect: tuple[int, int, int, int]
    container_probe_outcome: str
    rectangular_border_probe_outcome: str


@dataclass(frozen=True)
class DocumentSourceBlock:
    index: int
    block_id: str
    rect: tuple[int, int, int, int]
    kind: str
    preserved: bool


@dataclass(frozen=True)
class GroupingSourceBlock:
    rect: tuple[int, int, int, int]
    style_hint: str
    text_length: int
    detector_region_indexes: tuple[int, ...]
    source_group_indexes: tuple[int, ...]
    detector_labels: tuple[str, ...]
    line_width_scale: float
    line_height_scale: float


@dataclass(frozen=True)
class RenderStageTimings:
    decode_ms: int
    mask_ms: int
    layout_ms: int
    inpaint_ms: int
    draw_ms: int
    encode_ms: int
    finalize_ms: int
    total_ms: int
    inpaint_call_count: int | None
    drawable_group_count: int
    skipped_group_count: int


@dataclass(frozen=True)
class PageInput:
    page_id: str
    category: str
    source_path: Path
    candidate_path: Path
    baseline_path: Path | None
    allowed_mask_path: Path | None
    glyph_mask_path: Path | None
    container_mask_path: Path | None
    container_labels_path: Path | None
    container_confidences: tuple[float, ...]
    container_candidates: tuple[ContainerCandidate, ...]
    container_probe_outcomes: tuple[str, ...]
    rectangular_border_probes: tuple[RectangularBorderProbe, ...]
    source_layouts: tuple[SourceLayout, ...]
    document_source_blocks: tuple[DocumentSourceBlock, ...]
    grouped_source_blocks: tuple[GroupingSourceBlock, ...]
    horizontal_merged_source_blocks: tuple[GroupingSourceBlock, ...]
    layout_count: int | None
    analysis_ms: int | None
    render_ms: int | None
    total_ms: int | None
    render_stages: RenderStageTimings | None
    comparison_rect: tuple[int, int, int, int] | None


@dataclass(frozen=True)
class Thresholds:
    pixel_delta: int
    near_white: int
    source_white: int
    flat_block: int
    texture_std: float
    flat_std: float
    minimum_component_pixels: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Score local real-page comic translation artifacts and build an HTML report."
    )
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--manifest", type=Path)
    inputs.add_argument(
        "--recording-dir",
        type=Path,
        help="A pulled ComicLocalVisualFileRecorder directory.",
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--fixture-set-id",
        default="on-device-recording-v1",
        help="Stable fixture-set identity used with --recording-dir.",
    )
    parser.add_argument(
        "--recording-category",
        default="on-device-recording",
        help="Category assigned to pages discovered through --recording-dir.",
    )
    parser.add_argument(
        "--baseline-report",
        type=Path,
        help="Optional report.json from an earlier run of the same fixture set.",
    )
    parser.add_argument(
        "--container-review",
        type=Path,
        help=(
            "Optional local JSON with either v1 candidate labels/counts or v2 "
            "target rectangles for spatially matched container review."
        ),
    )
    return parser.parse_args()


def require_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{label} must be an array")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value.strip()


def optional_string(value: Any, label: str) -> str | None:
    if value is None:
        return None
    return require_string(value, label)


def bounded_int(value: Any, fallback: int, minimum: int, maximum: int, label: str) -> int:
    if value is None:
        return fallback
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum or value > maximum:
        raise ValueError(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


def bounded_float(
    value: Any,
    fallback: float,
    minimum: float,
    maximum: float,
    label: str,
) -> float:
    if value is None:
        return fallback
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ValueError(f"{label} must be numeric")
    resolved = float(value)
    if not math.isfinite(resolved) or resolved < minimum or resolved > maximum:
        raise ValueError(f"{label} must be in [{minimum}, {maximum}]")
    return resolved


def optional_bounded_float(
    value: Any,
    minimum: float,
    maximum: float,
    label: str,
) -> float | None:
    if value is None:
        return None
    return bounded_float(value, minimum, minimum, maximum, label)


def resolve_input_path(manifest_path: Path, raw_path: str, label: str) -> Path:
    candidate = Path(raw_path).expanduser()
    if not candidate.is_absolute():
        candidate = manifest_path.parent / candidate
    resolved = candidate.resolve()
    if not resolved.is_file():
        raise ValueError(f"{label} does not exist: {resolved}")
    return resolved


def optional_rect(value: Any, label: str) -> tuple[int, int, int, int] | None:
    if value is None:
        return None
    values = require_list(value, label)
    if len(values) != 4:
        raise ValueError(f"{label} must contain [left, top, right, bottom]")
    resolved: list[int] = []
    for index, item in enumerate(values):
        if not isinstance(item, int) or isinstance(item, bool) or item < 0:
            raise ValueError(f"{label}[{index}] must be a non-negative integer")
        resolved.append(item)
    if resolved[2] <= resolved[0] or resolved[3] <= resolved[1]:
        raise ValueError(f"{label} must have positive width and height")
    return resolved[0], resolved[1], resolved[2], resolved[3]


def load_manifest(path: Path) -> tuple[str, str, Thresholds, list[PageInput]]:
    manifest_path = path.expanduser().resolve()
    raw = require_dict(json.loads(manifest_path.read_text(encoding="utf-8")), "manifest")
    if raw.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"manifest.schemaVersion must be {SCHEMA_VERSION}")
    fixture_set_id = require_string(raw.get("fixtureSetId"), "manifest.fixtureSetId")
    candidate_id = require_string(raw.get("candidateId"), "manifest.candidateId")
    threshold_raw = require_dict(raw.get("thresholds", {}), "manifest.thresholds")
    thresholds = Thresholds(
        pixel_delta=bounded_int(
            threshold_raw.get("pixelDelta"),
            DEFAULT_PIXEL_DELTA,
            1,
            255,
            "thresholds.pixelDelta",
        ),
        near_white=bounded_int(
            threshold_raw.get("nearWhite"),
            DEFAULT_NEAR_WHITE,
            1,
            255,
            "thresholds.nearWhite",
        ),
        source_white=bounded_int(
            threshold_raw.get("sourceWhite"),
            DEFAULT_SOURCE_WHITE,
            1,
            255,
            "thresholds.sourceWhite",
        ),
        flat_block=bounded_int(
            threshold_raw.get("flatBlock"),
            DEFAULT_FLAT_BLOCK,
            4,
            64,
            "thresholds.flatBlock",
        ),
        texture_std=bounded_float(
            threshold_raw.get("textureStd"),
            DEFAULT_TEXTURE_STD,
            0.0,
            127.0,
            "thresholds.textureStd",
        ),
        flat_std=bounded_float(
            threshold_raw.get("flatStd"),
            DEFAULT_FLAT_STD,
            0.0,
            127.0,
            "thresholds.flatStd",
        ),
        minimum_component_pixels=bounded_int(
            threshold_raw.get("minimumComponentPixels"),
            DEFAULT_COMPONENT_PIXELS,
            1,
            1000000,
            "thresholds.minimumComponentPixels",
        ),
    )
    raw_pages = require_list(raw.get("pages"), "manifest.pages")
    if not raw_pages:
        raise ValueError("manifest.pages must not be empty")
    seen_ids: set[str] = set()
    pages: list[PageInput] = []
    for index, raw_page_value in enumerate(raw_pages):
        raw_page = require_dict(raw_page_value, f"manifest.pages[{index}]")
        page_id = require_string(raw_page.get("id"), f"manifest.pages[{index}].id")
        if page_id in seen_ids:
            raise ValueError(f"duplicate page id: {page_id}")
        seen_ids.add(page_id)
        category = require_string(
            raw_page.get("category"),
            f"manifest.pages[{index}].category",
        )
        baseline_raw = optional_string(
            raw_page.get("baseline"),
            f"manifest.pages[{index}].baseline",
        )
        allowed_raw = optional_string(
            raw_page.get("allowedMask"),
            f"manifest.pages[{index}].allowedMask",
        )
        glyph_raw = optional_string(
            raw_page.get("glyphMask"),
            f"manifest.pages[{index}].glyphMask",
        )
        container_raw = optional_string(
            raw_page.get("containerMask"),
            f"manifest.pages[{index}].containerMask",
        )
        pages.append(
            PageInput(
                page_id=page_id,
                category=category,
                source_path=resolve_input_path(
                    manifest_path,
                    require_string(
                        raw_page.get("source"),
                        f"manifest.pages[{index}].source",
                    ),
                    f"manifest.pages[{index}].source",
                ),
                candidate_path=resolve_input_path(
                    manifest_path,
                    require_string(
                        raw_page.get("candidate"),
                        f"manifest.pages[{index}].candidate",
                    ),
                    f"manifest.pages[{index}].candidate",
                ),
                baseline_path=resolve_input_path(
                    manifest_path,
                    baseline_raw,
                    f"manifest.pages[{index}].baseline",
                )
                if baseline_raw is not None
                else None,
                allowed_mask_path=resolve_input_path(
                    manifest_path,
                    allowed_raw,
                    f"manifest.pages[{index}].allowedMask",
                )
                if allowed_raw is not None
                else None,
                glyph_mask_path=resolve_input_path(
                    manifest_path,
                    glyph_raw,
                    f"manifest.pages[{index}].glyphMask",
                )
                if glyph_raw is not None
                else None,
                container_mask_path=resolve_input_path(
                    manifest_path,
                    container_raw,
                    f"manifest.pages[{index}].containerMask",
                )
                if container_raw is not None
                else None,
                container_labels_path=None,
                container_confidences=(),
                container_candidates=(),
                container_probe_outcomes=(),
                rectangular_border_probes=(),
                source_layouts=(),
                document_source_blocks=(),
                grouped_source_blocks=(),
                horizontal_merged_source_blocks=(),
                layout_count=None,
                analysis_ms=None,
                render_ms=None,
                total_ms=None,
                render_stages=None,
                comparison_rect=optional_rect(
                    raw_page.get("comparisonRect"),
                    f"manifest.pages[{index}].comparisonRect",
                ),
            )
        )
    return fixture_set_id, candidate_id, thresholds, pages


def default_thresholds() -> Thresholds:
    return Thresholds(
        pixel_delta=DEFAULT_PIXEL_DELTA,
        near_white=DEFAULT_NEAR_WHITE,
        source_white=DEFAULT_SOURCE_WHITE,
        flat_block=DEFAULT_FLAT_BLOCK,
        texture_std=DEFAULT_TEXTURE_STD,
        flat_std=DEFAULT_FLAT_STD,
        minimum_component_pixels=DEFAULT_COMPONENT_PIXELS,
    )


def safe_recording_file(page_dir: Path, value: Any, label: str) -> Path:
    name = require_string(value, label)
    if Path(name).name != name:
        raise ValueError(f"{label} must be a file name")
    path = (page_dir / name).resolve()
    if path.parent != page_dir.resolve() or not path.is_file():
        raise ValueError(f"{label} does not exist: {path}")
    return path


def recording_allowed_mask(
    render: dict[str, Any],
    width: int,
    height: int,
    path: Path,
) -> None:
    layouts = require_list(render.get("layouts"), "recording render.layouts")
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    for layout_index, layout_value in enumerate(layouts):
        layout = require_dict(
            layout_value,
            f"recording render.layouts[{layout_index}]",
        )
        outline_raw = layout.get("outlineWidth", 0)
        if not isinstance(outline_raw, (int, float)) or isinstance(outline_raw, bool):
            raise ValueError(
                f"recording render.layouts[{layout_index}].outlineWidth must be numeric"
            )
        expansion = max(2, min(64, math.ceil(float(outline_raw)) + 2))
        rectangles = list(
            require_list(
                layout.get("treatmentRects"),
                f"recording render.layouts[{layout_index}].treatmentRects",
            )
        )
        rectangles.append(
            require_dict(
                layout.get("textRect"),
                f"recording render.layouts[{layout_index}].textRect",
            )
        )
        for rect_index, rect_value in enumerate(rectangles):
            rect = require_dict(
                rect_value,
                f"recording render.layouts[{layout_index}].rect[{rect_index}]",
            )
            coordinates: list[int] = []
            for key in ("left", "top", "right", "bottom"):
                raw = rect.get(key)
                if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                    raise ValueError(f"recording layout rectangle {key} must be numeric")
                coordinates.append(math.floor(float(raw)))
            left = max(0, coordinates[0] - expansion)
            top = max(0, coordinates[1] - expansion)
            right = min(width, coordinates[2] + expansion)
            bottom = min(height, coordinates[3] + expansion)
            if right > left and bottom > top:
                draw.rectangle((left, top, right - 1, bottom - 1), fill=255)
    path.parent.mkdir(parents=True, exist_ok=True)
    mask.save(path, format="PNG", optimize=True)


def recording_glyph_mask(
    page_dir: Path,
    render: dict[str, Any],
    width: int,
    height: int,
    path: Path,
) -> None:
    mask_width = bounded_int(
        render.get("textMaskWidth"),
        0,
        1,
        100000,
        "recording render.textMaskWidth",
    )
    mask_height = bounded_int(
        render.get("textMaskHeight"),
        0,
        1,
        100000,
        "recording render.textMaskHeight",
    )
    if (mask_width, mask_height) != (width, height):
        raise ValueError(
            "recording glyph mask dimensions "
            f"{(mask_width, mask_height)} do not match source dimensions "
            f"{(width, height)}"
        )
    raw_path = safe_recording_file(
        page_dir,
        render.get("textMaskFile"),
        "recording render.textMaskFile",
    )
    raw = raw_path.read_bytes()
    expected_size = mask_width * mask_height
    if len(raw) != expected_size:
        raise ValueError(
            f"recording glyph mask contains {len(raw)} bytes; "
            f"expected {expected_size}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.frombytes("L", (mask_width, mask_height), raw).point(
        lambda value: 255 if value else 0
    ).save(
        path,
        format="PNG",
        optimize=True,
    )


def recording_container_mask(
    page_dir: Path,
    render: dict[str, Any],
    width: int,
    height: int,
    path: Path,
) -> None:
    mask_width = bounded_int(
        render.get("containerMaskWidth"),
        0,
        1,
        100000,
        "recording render.containerMaskWidth",
    )
    mask_height = bounded_int(
        render.get("containerMaskHeight"),
        0,
        1,
        100000,
        "recording render.containerMaskHeight",
    )
    if (mask_width, mask_height) != (width, height):
        raise ValueError(
            "recording container mask dimensions "
            f"{(mask_width, mask_height)} do not match source dimensions "
            f"{(width, height)}"
        )
    raw_path = safe_recording_file(
        page_dir,
        render.get("containerMaskFile"),
        "recording render.containerMaskFile",
    )
    raw = raw_path.read_bytes()
    expected_size = mask_width * mask_height
    if len(raw) != expected_size:
        raise ValueError(
            f"recording container mask contains {len(raw)} bytes; "
            f"expected {expected_size}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.frombytes("L", (mask_width, mask_height), raw).point(
        lambda value: 255 if value else 0
    ).save(
        path,
        format="PNG",
        optimize=True,
    )


def recording_container_labels(
    page_dir: Path,
    render: dict[str, Any],
    width: int,
    height: int,
    path: Path,
) -> None:
    labels_width = bounded_int(
        render.get("containerLabelsWidth"),
        0,
        1,
        100000,
        "recording render.containerLabelsWidth",
    )
    labels_height = bounded_int(
        render.get("containerLabelsHeight"),
        0,
        1,
        100000,
        "recording render.containerLabelsHeight",
    )
    if (labels_width, labels_height) != (width, height):
        raise ValueError(
            "recording container label dimensions "
            f"{(labels_width, labels_height)} do not match source dimensions "
            f"{(width, height)}"
        )
    raw_path = safe_recording_file(
        page_dir,
        render.get("containerLabelsFile"),
        "recording render.containerLabelsFile",
    )
    raw = raw_path.read_bytes()
    expected_size = labels_width * labels_height
    if len(raw) != expected_size:
        raise ValueError(
            f"recording container labels contain {len(raw)} bytes; "
            f"expected {expected_size}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.frombytes("L", (labels_width, labels_height), raw).save(
        path,
        format="PNG",
        optimize=True,
    )


def recording_container_confidences(render: dict[str, Any]) -> tuple[float, ...]:
    layouts = require_list(render.get("layouts", []), "recording render.layouts")
    values: list[float] = []
    for index, layout_value in enumerate(layouts):
        layout = require_dict(layout_value, f"recording render.layouts[{index}]")
        text_rect = require_dict(
            layout.get("textRect"),
            f"recording render.layouts[{index}].textRect",
        )
        confidence = bounded_float(
            text_rect.get("containerConfidence"),
            0.0,
            0.0,
            1.0,
            f"recording render.layouts[{index}].textRect.containerConfidence",
        )
        if confidence > 0:
            values.append(confidence)
    return tuple(values)


def recording_container_probe_outcomes(render: dict[str, Any]) -> tuple[str, ...]:
    layouts = require_list(render.get("layouts", []), "recording render.layouts")
    values: list[str] = []
    for index, layout_value in enumerate(layouts):
        layout = require_dict(layout_value, f"recording render.layouts[{index}]")
        text_rect = require_dict(
            layout.get("textRect"),
            f"recording render.layouts[{index}].textRect",
        )
        raw_outcome = text_rect.get("containerProbeOutcome")
        if raw_outcome is None or raw_outcome == "":
            continue
        outcome = require_string(
            raw_outcome,
            f"recording render.layouts[{index}].textRect.containerProbeOutcome",
        )
        if outcome not in {
            "accepted",
            "probe_too_small",
            "no_seed",
            "touches_probe_edge",
            "area_too_small",
            "component_too_small",
            "safe_rect_too_small",
            "accepted_rect_border",
            "probe_error",
        }:
            raise ValueError(
                f"recording render.layouts[{index}] has unknown container outcome"
            )
        values.append(outcome)
    return tuple(values)


def recording_rectangular_border_probes(
    render: dict[str, Any],
) -> tuple[RectangularBorderProbe, ...]:
    layouts = require_list(render.get("layouts", []), "recording render.layouts")
    values: list[RectangularBorderProbe] = []
    valid_outcomes = {
        "accepted",
        "raw_rect_too_small",
        "score_too_low",
        "corner_score_too_low",
        "interior_too_small",
        "safe_rect_invalid",
    }
    for index, layout_value in enumerate(layouts):
        layout = require_dict(layout_value, f"recording render.layouts[{index}]")
        text_rect = require_dict(
            layout.get("textRect"),
            f"recording render.layouts[{index}].textRect",
        )
        raw_outcome = text_rect.get("rectBorderProbeOutcome")
        if raw_outcome is None or raw_outcome == "":
            continue
        outcome = require_string(
            raw_outcome,
            f"recording render.layouts[{index}].textRect.rectBorderProbeOutcome",
        )
        if outcome not in valid_outcomes:
            raise ValueError(
                f"recording render.layouts[{index}] has unknown rectangular border outcome"
            )

        def score(name: str) -> float:
            return bounded_float(
                text_rect.get(name),
                0.0,
                0.0,
                1.0,
                f"recording render.layouts[{index}].textRect.{name}",
            )

        values.append(
            RectangularBorderProbe(
                outcome=outcome,
                left_score=score("rectBorderLeftScore"),
                right_score=score("rectBorderRightScore"),
                top_score=score("rectBorderTopScore"),
                bottom_score=score("rectBorderBottomScore"),
                top_left_corner_score=score("rectBorderTopLeftCornerScore"),
                top_right_corner_score=score("rectBorderTopRightCornerScore"),
                bottom_left_corner_score=score("rectBorderBottomLeftCornerScore"),
                bottom_right_corner_score=score("rectBorderBottomRightCornerScore"),
            )
        )
    return tuple(values)


def recording_source_layouts(render: dict[str, Any]) -> tuple[SourceLayout, ...]:
    layouts = require_list(render.get("layouts", []), "recording render.layouts")
    values: list[SourceLayout] = []
    for index, layout_value in enumerate(layouts):
        layout = require_dict(layout_value, f"recording render.layouts[{index}]")
        source_rect_values = require_list(
            layout.get("sourceRects"),
            f"recording render.layouts[{index}].sourceRects",
        )
        if not source_rect_values:
            continue
        left = math.inf
        top = math.inf
        right = -math.inf
        bottom = -math.inf
        for rect_index, rect_value in enumerate(source_rect_values):
            rect = require_dict(
                rect_value,
                f"recording render.layouts[{index}].sourceRects[{rect_index}]",
            )

            def coordinate(name: str) -> float:
                return bounded_float(
                    rect.get(name),
                    0.0,
                    0.0,
                    100000.0,
                    (
                        f"recording render.layouts[{index}]."
                        f"sourceRects[{rect_index}].{name}"
                    ),
                )

            left = min(left, coordinate("left"))
            top = min(top, coordinate("top"))
            right = max(right, coordinate("right"))
            bottom = max(bottom, coordinate("bottom"))
        resolved = (
            int(math.floor(left)),
            int(math.floor(top)),
            int(math.ceil(right)),
            int(math.ceil(bottom)),
        )
        if resolved[2] <= resolved[0] or resolved[3] <= resolved[1]:
            raise ValueError(
                f"recording render.layouts[{index}] source rect is empty"
            )
        text_rect = require_dict(
            layout.get("textRect"),
            f"recording render.layouts[{index}].textRect",
        )
        values.append(
            SourceLayout(
                index=index + 1,
                rect=resolved,
                container_probe_outcome=str(
                    text_rect.get("containerProbeOutcome", "")
                ),
                rectangular_border_probe_outcome=str(
                    text_rect.get("rectBorderProbeOutcome", "")
                ),
            )
        )
    return tuple(values)


def recording_document_source_blocks(
    analysis: dict[str, Any],
) -> tuple[DocumentSourceBlock, ...]:
    document = require_dict(analysis.get("document"), "recording analysis.document")
    signals = require_list(
        document.get("qualitySignals", []),
        "recording analysis.document.qualitySignals",
    )
    preserved_ids: set[str] = set()
    for signal_index, signal_value in enumerate(signals):
        signal = require_dict(
            signal_value,
            f"recording analysis.document.qualitySignals[{signal_index}]",
        )
        block_id = str(signal.get("blockId", "")).strip()
        if block_id:
            preserved_ids.add(block_id)
    blocks = require_list(
        document.get("blocks"),
        "recording analysis.document.blocks",
    )
    values: list[DocumentSourceBlock] = []
    for index, block_value in enumerate(blocks):
        block = require_dict(
            block_value,
            f"recording analysis.document.blocks[{index}]",
        )
        block_id = require_string(
            block.get("blockId"),
            f"recording analysis.document.blocks[{index}].blockId",
        )
        polygon = require_list(
            block.get("polygon"),
            f"recording analysis.document.blocks[{index}].polygon",
        )
        if len(polygon) < 3:
            raise ValueError(
                f"recording analysis document block polygon is invalid: {block_id}"
            )
        xs: list[float] = []
        ys: list[float] = []
        for point_index, point_value in enumerate(polygon):
            point = require_dict(
                point_value,
                (
                    f"recording analysis.document.blocks[{index}]."
                    f"polygon[{point_index}]"
                ),
            )
            xs.append(
                bounded_float(
                    point.get("x"),
                    0.0,
                    0.0,
                    100000.0,
                    (
                        f"recording analysis.document.blocks[{index}]."
                        f"polygon[{point_index}].x"
                    ),
                )
            )
            ys.append(
                bounded_float(
                    point.get("y"),
                    0.0,
                    0.0,
                    100000.0,
                    (
                        f"recording analysis.document.blocks[{index}]."
                        f"polygon[{point_index}].y"
                    ),
                )
            )
        resolved = (
            int(math.floor(min(xs))),
            int(math.floor(min(ys))),
            int(math.ceil(max(xs))),
            int(math.ceil(max(ys))),
        )
        if resolved[2] <= resolved[0] or resolved[3] <= resolved[1]:
            raise ValueError(
                f"recording analysis document block rect is empty: {block_id}"
            )
        kind = str(block.get("kind", "")).strip()
        values.append(
            DocumentSourceBlock(
                index=index + 1,
                block_id=block_id,
                rect=resolved,
                kind=kind,
                preserved=block_id in preserved_ids or kind == "sfx",
            )
        )
    return tuple(values)


def recording_grouping_source_blocks(
    analysis: dict[str, Any],
    stage: str,
) -> tuple[GroupingSourceBlock, ...]:
    raw_stages = analysis.get("groupingStages")
    if raw_stages is None:
        return ()
    stages = require_dict(raw_stages, "recording analysis.groupingStages")
    raw_blocks = require_list(
        stages.get(stage, []),
        f"recording analysis.groupingStages.{stage}",
    )
    values: list[GroupingSourceBlock] = []
    for index, block_value in enumerate(raw_blocks):
        block = require_dict(
            block_value,
            f"recording analysis.groupingStages.{stage}[{index}]",
        )

        def coordinate(name: str) -> int:
            return bounded_int(
                block.get(name),
                0,
                0,
                100000,
                f"recording analysis.groupingStages.{stage}[{index}].{name}",
            )

        rect = (
            coordinate("left"),
            coordinate("top"),
            coordinate("right"),
            coordinate("bottom"),
        )
        if rect[2] <= rect[0] or rect[3] <= rect[1]:
            raise ValueError(
                f"recording analysis grouping block is empty: {stage}[{index}]"
            )
        region_values = require_list(
            block.get("detectorRegionIndexes", []),
            (
                f"recording analysis.groupingStages.{stage}[{index}]."
                "detectorRegionIndexes"
            ),
        )
        source_group_values = require_list(
            block.get("sourceGroupIndexes", []),
            (
                f"recording analysis.groupingStages.{stage}[{index}]."
                "sourceGroupIndexes"
            ),
        )
        label_values = require_list(
            block.get("detectorLabels", []),
            (
                f"recording analysis.groupingStages.{stage}[{index}]."
                "detectorLabels"
            ),
        )
        if len(region_values) != len(label_values):
            raise ValueError(
                f"recording analysis grouping provenance is inconsistent: "
                f"{stage}[{index}]"
            )
        region_indexes = tuple(
            bounded_int(
                value,
                0,
                0,
                100000,
                (
                    f"recording analysis.groupingStages.{stage}[{index}]."
                    f"detectorRegionIndexes[{offset}]"
                ),
            )
            for offset, value in enumerate(region_values)
        )
        source_group_indexes = tuple(
            bounded_int(
                value,
                0,
                0,
                100000,
                (
                    f"recording analysis.groupingStages.{stage}[{index}]."
                    f"sourceGroupIndexes[{offset}]"
                ),
            )
            for offset, value in enumerate(source_group_values)
        )
        labels = tuple(
            str(value).strip().lower()
            for value in label_values
        )
        values.append(
            GroupingSourceBlock(
                rect=rect,
                style_hint=str(block.get("styleHint", "")).strip(),
                text_length=bounded_int(
                    block.get("textLength"),
                    0,
                    0,
                    100000,
                    (
                        f"recording analysis.groupingStages.{stage}[{index}]."
                        "textLength"
                    ),
                ),
                detector_region_indexes=region_indexes,
                source_group_indexes=source_group_indexes,
                detector_labels=labels,
                line_width_scale=bounded_float(
                    block.get("lineWidthScale"),
                    0.0,
                    0.0,
                    100000.0,
                    (
                        f"recording analysis.groupingStages.{stage}[{index}]."
                        "lineWidthScale"
                    ),
                ),
                line_height_scale=bounded_float(
                    block.get("lineHeightScale"),
                    0.0,
                    0.0,
                    100000.0,
                    (
                        f"recording analysis.groupingStages.{stage}[{index}]."
                        "lineHeightScale"
                    ),
                ),
            )
        )
    return tuple(values)


def recording_render_stage_timings(
    render: dict[str, Any],
) -> RenderStageTimings | None:
    raw = render.get("timings")
    if raw is None:
        return None
    timings = require_dict(raw, "recording render.timings")

    def timing(name: str) -> int:
        return bounded_int(
            timings.get(name),
            0,
            0,
            3_600_000,
            f"recording render.timings.{name}",
        )

    return RenderStageTimings(
        decode_ms=timing("decodeMs"),
        mask_ms=timing("maskMs"),
        layout_ms=timing("layoutMs"),
        inpaint_ms=timing("inpaintMs"),
        draw_ms=timing("drawMs"),
        encode_ms=timing("encodeMs"),
        finalize_ms=timing("finalizeMs"),
        total_ms=timing("totalMs"),
        inpaint_call_count=(
            timing("inpaintCallCount")
            if "inpaintCallCount" in timings
            else None
        ),
        drawable_group_count=timing("drawableGroupCount"),
        skipped_group_count=timing("skippedGroupCount"),
    )


def recording_container_candidates(
    render: dict[str, Any],
) -> tuple[ContainerCandidate, ...]:
    layouts = require_list(render.get("layouts", []), "recording render.layouts")
    values: list[ContainerCandidate] = []
    for index, layout_value in enumerate(layouts):
        layout = require_dict(layout_value, f"recording render.layouts[{index}]")
        text_rect = require_dict(
            layout.get("textRect"),
            f"recording render.layouts[{index}].textRect",
        )
        confidence = bounded_float(
            text_rect.get("containerConfidence"),
            0.0,
            0.0,
            1.0,
            f"recording render.layouts[{index}].textRect.containerConfidence",
        )
        label = bounded_int(
            layout.get("containerLabel"),
            0,
            0,
            254,
            f"recording render.layouts[{index}].containerLabel",
        )
        if confidence > 0 and label > 0:
            values.append(
                ContainerCandidate(
                    label=label,
                    confidence=confidence,
                    probe_outcome=str(text_rect.get("containerProbeOutcome", "")),
                    raw_coverage=optional_bounded_float(
                        text_rect.get("containerRawCoverage"),
                        0.0,
                        1.0,
                        f"recording render.layouts[{index}].textRect.containerRawCoverage",
                    ),
                    solidity=optional_bounded_float(
                        text_rect.get("containerSolidity"),
                        0.0,
                        1.0,
                        f"recording render.layouts[{index}].textRect.containerSolidity",
                    ),
                    area_ratio=optional_bounded_float(
                        text_rect.get("containerAreaRatio"),
                        0.0,
                        1.0,
                        f"recording render.layouts[{index}].textRect.containerAreaRatio",
                    ),
                    luminance_std=optional_bounded_float(
                        text_rect.get("containerLuminanceStd"),
                        0.0,
                        255.0,
                        f"recording render.layouts[{index}].textRect.containerLuminanceStd",
                    ),
                )
            )
    return tuple(values)


def load_recording_timings(recording_dir: Path) -> dict[int, tuple[int, int, int]]:
    path = recording_dir / "timings.tsv"
    if not path.is_file():
        return {}
    timings: dict[int, tuple[int, int, int]] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 7:
            raise ValueError(f"{path}:{line_number}: invalid timing row")
        try:
            page_index = int(fields[0])
            analysis_ms = int(fields[4])
            render_ms = int(fields[5])
            total_ms = int(fields[6])
        except ValueError as error:
            raise ValueError(
                f"{path}:{line_number}: timing values must be integers"
            ) from error
        if (
            page_index < 0
            or analysis_ms < 0
            or render_ms < 0
            or total_ms != analysis_ms + render_ms
            or page_index in timings
        ):
            raise ValueError(f"{path}:{line_number}: unsafe timing values")
        timings[page_index] = (analysis_ms, render_ms, total_ms)
    return timings


def load_recording_dir(
    path: Path,
    output_dir: Path,
    fixture_set_id: str,
    category: str,
) -> tuple[str, str, Thresholds, list[PageInput]]:
    recording_dir = path.expanduser().resolve()
    if not recording_dir.is_dir():
        raise ValueError(f"recording directory does not exist: {recording_dir}")
    manifests = sorted(recording_dir.rglob("manifest.json"))
    if not manifests:
        raise ValueError("recording directory contains no manifest.json files")
    timings = load_recording_timings(recording_dir)
    pages: list[PageInput] = []
    candidate_id = recording_dir.name
    seen_ids: set[str] = set()
    for index, manifest_path in enumerate(manifests):
        raw = require_dict(
            json.loads(manifest_path.read_text(encoding="utf-8")),
            f"recording manifest {manifest_path}",
        )
        if raw.get("schemaVersion") != SCHEMA_VERSION:
            raise ValueError(f"{manifest_path}: unsupported recording schema")
        if index == 0:
            candidate_id = require_string(
                raw.get("recordingId"),
                f"{manifest_path}.recordingId",
            )
        rendered_name = raw.get("renderedImage")
        render_name = raw.get("render")
        analysis_name = raw.get("analysis")
        if not rendered_name or not render_name or not analysis_name:
            continue
        page_dir = manifest_path.parent.resolve()
        source_path = safe_recording_file(
            page_dir,
            raw.get("sourceImage"),
            f"{manifest_path}.sourceImage",
        )
        candidate_path = safe_recording_file(
            page_dir,
            rendered_name,
            f"{manifest_path}.renderedImage",
        )
        render_path = safe_recording_file(
            page_dir,
            render_name,
            f"{manifest_path}.render",
        )
        analysis_path = safe_recording_file(
            page_dir,
            analysis_name,
            f"{manifest_path}.analysis",
        )
        render = require_dict(
            json.loads(render_path.read_text(encoding="utf-8")),
            f"recording render {render_path}",
        )
        analysis = require_dict(
            json.loads(analysis_path.read_text(encoding="utf-8")),
            f"recording analysis {analysis_path}",
        )
        source = require_dict(render.get("source"), f"{render_path}.source")
        source_page_index = bounded_int(
            source.get("pageIndex"),
            0,
            0,
            100000,
            f"{render_path}.source.pageIndex",
        )
        width = bounded_int(
            source.get("imageWidth"),
            0,
            1,
            100000,
            f"{render_path}.source.imageWidth",
        )
        height = bounded_int(
            source.get("imageHeight"),
            0,
            1,
            100000,
            f"{render_path}.source.imageHeight",
        )
        page_id = page_dir.name
        if page_id in seen_ids:
            page_id = f"{page_id}-{index + 1}"
        seen_ids.add(page_id)
        allowed_mask = output_dir / "recording-inputs" / f"{safe_name(page_id)}-allowed.png"
        glyph_mask = output_dir / "recording-inputs" / f"{safe_name(page_id)}-glyph.png"
        recording_allowed_mask(render, width, height, allowed_mask)
        recording_glyph_mask(page_dir, render, width, height, glyph_mask)
        container_mask: Path | None = None
        if render.get("containerMaskFile"):
            container_mask = (
                output_dir / "recording-inputs" /
                f"{safe_name(page_id)}-container.png"
            )
            recording_container_mask(
                page_dir,
                render,
                width,
                height,
                container_mask,
            )
        container_labels: Path | None = None
        if render.get("containerLabelsFile"):
            container_labels = (
                output_dir / "recording-inputs" /
                f"{safe_name(page_id)}-container-labels.png"
            )
            recording_container_labels(
                page_dir,
                render,
                width,
                height,
                container_labels,
            )
        pages.append(
            PageInput(
                page_id=page_id,
                category=category,
                source_path=source_path,
                candidate_path=candidate_path,
                baseline_path=None,
                allowed_mask_path=allowed_mask,
                glyph_mask_path=glyph_mask,
                container_mask_path=container_mask,
                container_labels_path=container_labels,
                container_confidences=recording_container_confidences(render),
                container_candidates=recording_container_candidates(render),
                container_probe_outcomes=recording_container_probe_outcomes(render),
                rectangular_border_probes=recording_rectangular_border_probes(render),
                source_layouts=recording_source_layouts(render),
                document_source_blocks=recording_document_source_blocks(analysis),
                grouped_source_blocks=recording_grouping_source_blocks(
                    analysis,
                    "grouped",
                ),
                horizontal_merged_source_blocks=recording_grouping_source_blocks(
                    analysis,
                    "horizontalMerged",
                ),
                layout_count=len(
                    require_list(render.get("layouts", []), "recording render.layouts")
                ),
                analysis_ms=(
                    timings[source_page_index][0]
                    if source_page_index in timings
                    else None
                ),
                render_ms=(
                    timings[source_page_index][1]
                    if source_page_index in timings
                    else None
                ),
                total_ms=(
                    timings[source_page_index][2]
                    if source_page_index in timings
                    else None
                ),
                render_stages=recording_render_stage_timings(render),
                comparison_rect=None,
            )
        )
    if not pages:
        raise ValueError("recording directory contains no completed renders")
    return fixture_set_id, candidate_id, default_thresholds(), pages


def load_rgb(path: Path) -> tuple[Image.Image, np.ndarray]:
    image = Image.open(path).convert("RGB")
    return image, np.asarray(image, dtype=np.uint8)


def longest_expanded_dark_run(row: np.ndarray) -> int:
    if row.size <= 0:
        return 0
    expanded = row.copy()
    expanded[1:] |= row[:-1]
    expanded[:-1] |= row[1:]
    longest = 0
    current = 0
    for value in expanded:
        if bool(value):
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def horizontal_merge_members(
    grouped: tuple[GroupingSourceBlock, ...],
    merged_block: GroupingSourceBlock,
) -> list[GroupingSourceBlock]:
    merged_source_groups = set(merged_block.source_group_indexes)
    if merged_source_groups:
        members = [
            block
            for block in grouped
            if block.style_hint == "horizontal-ltr"
            and block.source_group_indexes
            and set(block.source_group_indexes).issubset(merged_source_groups)
        ]
    else:
        merged_regions = set(merged_block.detector_region_indexes)
        members = [
            block
            for block in grouped
            if block.style_hint == "horizontal-ltr"
            and block.detector_region_indexes
            and set(block.detector_region_indexes).issubset(merged_regions)
        ]
    members.sort(
        key=lambda block: (
            (block.rect[1] + block.rect[3]) / 2,
            block.rect[0],
        )
    )
    return members


def horizontal_separator_probes(
    source: np.ndarray,
    grouped: tuple[GroupingSourceBlock, ...],
    merged: tuple[GroupingSourceBlock, ...],
) -> list[dict[str, Any]]:
    if not grouped or not merged:
        return []
    height, width = source.shape[:2]
    grayscale = (
        source[:, :, 0].astype(np.float32) * 0.299
        + source[:, :, 1].astype(np.float32) * 0.587
        + source[:, :, 2].astype(np.float32) * 0.114
    )
    probes: list[dict[str, Any]] = []
    for merged_index, merged_block in enumerate(merged):
        merged_provenance_count = len(
            merged_block.source_group_indexes
            or merged_block.detector_region_indexes
        )
        if (
            merged_block.style_hint != "horizontal-ltr"
            or merged_provenance_count < 2
        ):
            continue
        members = horizontal_merge_members(grouped, merged_block)
        for boundary_index in range(len(members) - 1):
            upper = members[boundary_index]
            lower = members[boundary_index + 1]
            left = max(0, upper.rect[0], lower.rect[0])
            right = min(width, upper.rect[2], lower.rect[2])
            if right - left < 24:
                continue
            overlap = right - left
            overlap_ratio = overlap / max(
                1,
                min(
                    upper.rect[2] - upper.rect[0],
                    lower.rect[2] - lower.rect[0],
                ),
            )
            vertical_gap = lower.rect[1] - upper.rect[3]
            merged_width = max(1, merged_block.rect[2] - merged_block.rect[0])
            span_of_merged_width = overlap / merged_width
            if overlap_ratio < 0.5:
                continue
            boundary_center = int(round((upper.rect[3] + lower.rect[1]) / 2))
            search_radius = max(
                3,
                min(
                    12,
                    int(round(max(
                        upper.line_height_scale,
                        lower.line_height_scale,
                    ) * 0.28)),
                ),
            )
            top = max(0, boundary_center - search_radius)
            bottom = min(height, boundary_center + search_radius + 1)
            if bottom <= top:
                continue
            crop = grayscale[top:bottom, left:right]
            median = float(np.median(crop))
            dark_threshold = max(20.0, min(170.0, median - 32.0))
            dark = crop <= dark_threshold
            edge_top = max(1, top)
            edge_bottom = min(height - 1, bottom)
            edge = np.abs(
                grayscale[edge_top + 1:edge_bottom + 1, left:right]
                - grayscale[edge_top - 1:edge_bottom - 1, left:right]
            ) >= 36.0
            best_run = 0
            best_coverage = 0.0
            best_y = top
            for row_offset in range(dark.shape[0]):
                row = dark[row_offset]
                run = longest_expanded_dark_run(row)
                coverage = float(np.count_nonzero(row)) / max(1, row.size)
                if run > best_run or (run == best_run and coverage > best_coverage):
                    best_run = run
                    best_coverage = coverage
                    best_y = top + row_offset
            run_ratio = best_run / max(1, right - left)
            best_edge_run = 0
            best_edge_coverage = 0.0
            best_edge_y = edge_top
            for row_offset in range(edge.shape[0]):
                row = edge[row_offset]
                run = longest_expanded_dark_run(row)
                coverage = float(np.count_nonzero(row)) / max(1, row.size)
                if (
                    run > best_edge_run
                    or (
                        run == best_edge_run
                        and coverage > best_edge_coverage
                    )
                ):
                    best_edge_run = run
                    best_edge_coverage = coverage
                    best_edge_y = edge_top + row_offset
            edge_run_ratio = best_edge_run / max(1, right - left)
            probes.append(
                {
                    "mergedIndex": merged_index + 1,
                    "boundaryIndex": boundary_index + 1,
                    "upperRect": list(upper.rect),
                    "lowerRect": list(lower.rect),
                    "xRange": [left, right],
                    "searchYRange": [top, bottom],
                    "bestY": best_y,
                    "overlapRatio": round(overlap_ratio, 4),
                    "verticalGap": vertical_gap,
                    "spanOfMergedWidthRatio": round(span_of_merged_width, 4),
                    "localMedianLuminance": round(median, 2),
                    "darkThreshold": round(dark_threshold, 2),
                    "darkRunRatio": round(run_ratio, 4),
                    "darkCoverageRatio": round(best_coverage, 4),
                    "bestEdgeY": best_edge_y,
                    "edgeRunRatio": round(edge_run_ratio, 4),
                    "edgeCoverageRatio": round(best_edge_coverage, 4),
                    "strongSeparatorCandidate": (
                        vertical_gap >= 3
                        and span_of_merged_width >= 0.5
                        and (
                            (
                                run_ratio >= 0.55
                                and best_coverage >= 0.28
                            )
                            or (
                                edge_run_ratio >= 0.55
                                and best_edge_coverage >= 0.28
                            )
                        )
                    ),
                    "upperDetectorRegionIndexes":
                        list(upper.detector_region_indexes),
                    "lowerDetectorRegionIndexes":
                        list(lower.detector_region_indexes),
                    "upperSourceGroupIndexes":
                        list(upper.source_group_indexes),
                    "lowerSourceGroupIndexes":
                        list(lower.source_group_indexes),
                }
            )
    return probes


def unique_text_length_subset(
    candidates: list[GroupingSourceBlock],
    target: int,
) -> list[GroupingSourceBlock] | None:
    if target < 0:
        return None
    if target == 0:
        return []
    solutions: dict[int, list[tuple[int, ...]]] = {0: [()]}
    for candidate_index, candidate in enumerate(candidates):
        updates: dict[int, list[tuple[int, ...]]] = {}
        for subtotal, subtotal_solutions in list(solutions.items()):
            next_total = subtotal + candidate.text_length
            if next_total > target:
                continue
            next_solutions = updates.setdefault(next_total, [])
            for solution in subtotal_solutions:
                next_solutions.append(solution + (candidate_index,))
                if len(next_solutions) >= 2:
                    break
        for subtotal, subtotal_solutions in updates.items():
            existing = solutions.setdefault(subtotal, [])
            for solution in subtotal_solutions:
                if solution not in existing:
                    existing.append(solution)
                if len(existing) >= 2:
                    break
    matches = solutions.get(target, [])
    if len(matches) != 1:
        return None
    return [candidates[index] for index in matches[0]]


def horizontal_separator_split_plans(
    grouped: tuple[GroupingSourceBlock, ...],
    merged: tuple[GroupingSourceBlock, ...],
    probes: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    strong_probes: dict[int, list[dict[str, Any]]] = {}
    for probe in probes:
        if not probe["strongSeparatorCandidate"]:
            continue
        merged_index = int(probe["mergedIndex"])
        strong_probes.setdefault(merged_index, []).append(probe)
    plans: list[dict[str, Any]] = []
    for merged_index, merged_probes in sorted(strong_probes.items()):
        if merged_index < 1 or merged_index > len(merged):
            raise ValueError(
                f"separator split references missing merged block {merged_index}"
            )
        merged_block = merged[merged_index - 1]
        proven_members = horizontal_merge_members(grouped, merged_block)
        exact_membership = bool(merged_block.source_group_indexes)
        valid_boundaries = sorted(
            {
                int(probe["boundaryIndex"])
                for probe in merged_probes
                if 1 <= int(probe["boundaryIndex"]) < len(proven_members)
            }
        )
        if not valid_boundaries:
            continue
        separator_ys = sorted({
            int(round(
                (
                    int(probe["upperRect"][3])
                    + int(probe["lowerRect"][1])
                )
                / 2
            ))
            for probe in merged_probes
            if int(probe["boundaryIndex"]) in valid_boundaries
        })
        if exact_membership:
            unattributed_candidates: list[GroupingSourceBlock] = []
            unattributed_members: list[GroupingSourceBlock] | None = []
            attribution_resolved = True
        else:
            proven_text_length = sum(
                member.text_length
                for member in proven_members
            )
            missing_text_length = merged_block.text_length - proven_text_length
            unattributed_candidates = [
                block
                for block in grouped
                if block.style_hint == "horizontal-ltr"
                and not block.detector_region_indexes
                and merged_block.rect[0]
                <= (block.rect[0] + block.rect[2]) / 2
                <= merged_block.rect[2]
                and merged_block.rect[1]
                <= (block.rect[1] + block.rect[3]) / 2
                <= merged_block.rect[3]
            ]
            unattributed_members = unique_text_length_subset(
                unattributed_candidates,
                missing_text_length,
            )
            attribution_resolved = unattributed_members is not None
        members = list(proven_members)
        if unattributed_members is not None:
            members.extend(unattributed_members)
        members.sort(
            key=lambda block: (
                (block.rect[1] + block.rect[3]) / 2,
                block.rect[0],
            )
        )
        segments: list[list[GroupingSourceBlock]] = [
            []
            for _ in range(len(separator_ys) + 1)
        ]
        for member in members:
            center_y = (member.rect[1] + member.rect[3]) / 2
            segment_index = sum(
                center_y > separator_y
                for separator_y in separator_ys
            )
            segments[segment_index].append(member)
        serialized_segments: list[dict[str, Any]] = []
        for segment in segments:
            if not segment:
                continue
            detector_indexes = sorted({
                region
                for member in segment
                for region in member.detector_region_indexes
            })
            detector_labels = sorted({
                label
                for member in segment
                for label in member.detector_labels
                if label
            })
            source_group_indexes = sorted({
                source_group
                for member in segment
                for source_group in member.source_group_indexes
            })
            serialized_segments.append(
                {
                    "rect": [
                        min(member.rect[0] for member in segment),
                        min(member.rect[1] for member in segment),
                        max(member.rect[2] for member in segment),
                        max(member.rect[3] for member in segment),
                    ],
                    "memberCount": len(segment),
                    "textLength": sum(
                        member.text_length
                        for member in segment
                    ),
                    "detectorRegionIndexes": detector_indexes,
                    "sourceGroupIndexes": source_group_indexes,
                    "detectorLabels": detector_labels,
                }
            )
        if len(serialized_segments) < 2:
            continue
        segment_text_length = sum(
            int(segment["textLength"])
            for segment in serialized_segments
        )
        segment_detector_indexes = {
            int(region)
            for segment in serialized_segments
            for region in segment["detectorRegionIndexes"]
        }
        segment_source_group_indexes = {
            int(source_group)
            for segment in serialized_segments
            for source_group in segment["sourceGroupIndexes"]
        }
        text_length_preserved = segment_text_length == merged_block.text_length
        detector_provenance_preserved = (
            segment_detector_indexes
            == set(merged_block.detector_region_indexes)
        )
        source_group_provenance_preserved = (
            not exact_membership
            or segment_source_group_indexes
            == set(merged_block.source_group_indexes)
        )
        plans.append(
            {
                "mergedIndex": merged_index,
                "originalRect": list(merged_block.rect),
                "originalDetectorRegionIndexes":
                    list(merged_block.detector_region_indexes),
                "originalSourceGroupIndexes":
                    list(merged_block.source_group_indexes),
                "membershipSource": (
                    "source_group_indexes"
                    if exact_membership
                    else "detector_regions_with_text_length_fallback"
                ),
                "separatorBoundaryIndexes": valid_boundaries,
                "separatorYs": separator_ys,
                "segments": serialized_segments,
                "sourceBlockDelta": len(serialized_segments) - 1,
                "unattributedCandidateCount": len(unattributed_candidates),
                "unattributedMemberCount": (
                    len(unattributed_members)
                    if unattributed_members is not None
                    else 0
                ),
                "unattributedAttributionResolved": attribution_resolved,
                "sourceTextLength": merged_block.text_length,
                "segmentTextLength": segment_text_length,
                "textLengthPreserved": text_length_preserved,
                "detectorProvenancePreserved": detector_provenance_preserved,
                "sourceGroupProvenancePreserved":
                    source_group_provenance_preserved,
                "safeForCandidateGrouping": (
                    attribution_resolved
                    and len(serialized_segments) == len(separator_ys) + 1
                    and text_length_preserved
                    and detector_provenance_preserved
                    and source_group_provenance_preserved
                ),
            }
        )
    return plans


def load_allowed_mask(path: Path, size: tuple[int, int]) -> np.ndarray:
    mask_image = Image.open(path).convert("L")
    if mask_image.size != size:
        raise ValueError(
            f"allowed mask dimensions {mask_image.size} do not match page dimensions {size}"
        )
    return np.asarray(mask_image, dtype=np.uint8) >= 128


def load_glyph_mask(path: Path, size: tuple[int, int]) -> np.ndarray:
    mask_image = Image.open(path).convert("L")
    if mask_image.size != size:
        raise ValueError(
            f"glyph mask dimensions {mask_image.size} do not match page dimensions {size}"
        )
    return np.asarray(mask_image, dtype=np.uint8) >= 128


def load_container_mask(path: Path, size: tuple[int, int]) -> np.ndarray:
    mask_image = Image.open(path).convert("L")
    if mask_image.size != size:
        raise ValueError(
            f"container mask dimensions {mask_image.size} do not match page dimensions {size}"
        )
    return np.asarray(mask_image, dtype=np.uint8) >= 128


def load_container_labels(path: Path, size: tuple[int, int]) -> np.ndarray:
    labels_image = Image.open(path).convert("L")
    if labels_image.size != size:
        raise ValueError(
            f"container label dimensions {labels_image.size} do not match page dimensions {size}"
        )
    return np.asarray(labels_image, dtype=np.uint8)


def ensure_same_size(
    page_id: str,
    source: Image.Image,
    candidate: Image.Image,
    baseline: Image.Image | None,
) -> None:
    if source.size != candidate.size:
        raise ValueError(
            f"{page_id}: source dimensions {source.size} do not match "
            f"candidate dimensions {candidate.size}"
        )
    if baseline is not None and source.size != baseline.size:
        raise ValueError(
            f"{page_id}: source dimensions {source.size} do not match "
            f"baseline dimensions {baseline.size}"
        )


def percent(count: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return round(count * 100.0 / total, 4)


def changed_mask(source: np.ndarray, target: np.ndarray, pixel_delta: int) -> np.ndarray:
    delta = np.abs(source.astype(np.int16) - target.astype(np.int16))
    return np.max(delta, axis=2) >= pixel_delta


def component_measurements(
    mask: np.ndarray,
    minimum_pixels: int,
) -> tuple[int, int, list[tuple[int, int, int, int, int]]]:
    height, width = mask.shape
    visited = np.zeros(mask.shape, dtype=np.bool_)
    components: list[tuple[int, int, int, int, int]] = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or visited[y, x]:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[y, x] = True
            count = 0
            left = x
            top = y
            right = x
            bottom = y
            while queue:
                current_x, current_y = queue.popleft()
                count += 1
                left = min(left, current_x)
                top = min(top, current_y)
                right = max(right, current_x)
                bottom = max(bottom, current_y)
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if (
                        next_x < 0
                        or next_y < 0
                        or next_x >= width
                        or next_y >= height
                        or visited[next_y, next_x]
                        or not mask[next_y, next_x]
                    ):
                        continue
                    visited[next_y, next_x] = True
                    queue.append((next_x, next_y))
            if count >= minimum_pixels:
                components.append((count, left, top, right + 1, bottom + 1))
    components.sort(reverse=True)
    largest = components[0][0] if components else 0
    return len(components), largest, components


def flatness_collapse_mask(
    source: np.ndarray,
    candidate: np.ndarray,
    changed: np.ndarray,
    block_size: int,
    source_texture_std: float,
    candidate_flat_std: float,
) -> np.ndarray:
    height, width, _ = source.shape
    result = np.zeros((height, width), dtype=np.bool_)
    source_luma = (
        source[:, :, 0].astype(np.float32) * 0.299
        + source[:, :, 1].astype(np.float32) * 0.587
        + source[:, :, 2].astype(np.float32) * 0.114
    )
    candidate_luma = (
        candidate[:, :, 0].astype(np.float32) * 0.299
        + candidate[:, :, 1].astype(np.float32) * 0.587
        + candidate[:, :, 2].astype(np.float32) * 0.114
    )
    for top in range(0, height, block_size):
        bottom = min(height, top + block_size)
        for left in range(0, width, block_size):
            right = min(width, left + block_size)
            block_changed = changed[top:bottom, left:right]
            if block_changed.size == 0 or float(np.mean(block_changed)) < 0.45:
                continue
            source_std = float(np.std(source_luma[top:bottom, left:right]))
            candidate_std = float(np.std(candidate_luma[top:bottom, left:right]))
            if source_std >= source_texture_std and candidate_std <= candidate_flat_std:
                result[top:bottom, left:right] = True
    return result


def save_thumbnail(image: Image.Image, path: Path) -> None:
    thumbnail = image.copy()
    thumbnail.thumbnail((THUMBNAIL_EDGE, THUMBNAIL_EDGE), Image.Resampling.LANCZOS)
    thumbnail.save(path, format="PNG", optimize=True)


def save_overlay(
    candidate: Image.Image,
    changed: np.ndarray,
    introduced_white: np.ndarray,
    flatness_collapse: np.ndarray,
    components: list[tuple[int, int, int, int, int]],
    path: Path,
) -> None:
    base = candidate.convert("RGBA")
    width, height = candidate.size
    overlay = np.zeros((height, width, 4), dtype=np.uint8)
    overlay[changed] = [255, 188, 0, 90]
    overlay[introduced_white] = [255, 32, 32, 150]
    overlay[flatness_collapse] = [160, 32, 255, 125]
    overlay_image = Image.fromarray(overlay, mode="RGBA")
    merged = Image.alpha_composite(base, overlay_image)
    draw = ImageDraw.Draw(merged)
    for _, left, top, right, bottom in components[:8]:
        draw.rectangle((left, top, right - 1, bottom - 1), outline=(255, 0, 0, 255), width=3)
    save_thumbnail(merged.convert("RGB"), path)


def save_mask_overlay(
    source: Image.Image,
    mask: np.ndarray,
    path: Path,
    color: tuple[int, int, int, int],
) -> None:
    base = source.convert("RGBA")
    width, height = source.size
    overlay = np.zeros((height, width, 4), dtype=np.uint8)
    overlay[mask] = color
    merged = Image.alpha_composite(
        base,
        Image.fromarray(overlay, mode="RGBA"),
    )
    save_thumbnail(merged.convert("RGB"), path)


def save_container_label_overlay(
    source: Image.Image,
    labels: np.ndarray,
    path: Path,
) -> None:
    base = source.convert("RGBA")
    width, height = source.size
    overlay = np.zeros((height, width, 4), dtype=np.uint8)
    palette = (
        (52, 211, 153, 155),
        (59, 130, 246, 155),
        (250, 204, 21, 155),
        (244, 114, 182, 155),
        (168, 85, 247, 155),
        (249, 115, 22, 155),
    )
    for label in np.unique(labels):
        resolved = int(label)
        if resolved <= 0:
            continue
        overlay[labels == resolved] = palette[(resolved - 1) % len(palette)]
    merged = Image.alpha_composite(
        base,
        Image.fromarray(overlay, mode="RGBA"),
    )
    draw = ImageDraw.Draw(merged)
    for label in np.unique(labels):
        resolved = int(label)
        if resolved <= 0:
            continue
        ys, xs = np.nonzero(labels == resolved)
        if xs.size <= 0:
            continue
        center_x = int((int(xs.min()) + int(xs.max())) / 2)
        center_y = int((int(ys.min()) + int(ys.max())) / 2)
        draw.text(
            (center_x, center_y),
            str(resolved),
            fill=(255, 255, 255, 255),
            stroke_width=3,
            stroke_fill=(0, 0, 0, 255),
            anchor="mm",
        )
    save_thumbnail(merged.convert("RGB"), path)


def save_grouping_split_overlay(
    source: Image.Image,
    plans: list[dict[str, Any]],
    path: Path,
) -> None:
    canvas = source.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    palette = (
        (34, 211, 238, 255),
        (250, 204, 21, 255),
        (244, 114, 182, 255),
        (74, 222, 128, 255),
    )
    for plan in plans:
        original = [int(value) for value in plan["originalRect"]]
        draw.rectangle(
            (original[0], original[1], original[2] - 1, original[3] - 1),
            outline=(248, 113, 113, 255),
            width=4,
        )
        for segment_index, segment in enumerate(plan["segments"]):
            rect = [int(value) for value in segment["rect"]]
            color = palette[segment_index % len(palette)]
            draw.rectangle(
                (rect[0], rect[1], rect[2] - 1, rect[3] - 1),
                outline=color,
                width=4,
            )
            draw.text(
                (rect[0] + 4, rect[1] + 4),
                f"M{plan['mergedIndex']} S{segment_index + 1}",
                fill=color,
                stroke_width=2,
                stroke_fill=(0, 0, 0, 255),
            )
    save_thumbnail(canvas.convert("RGB"), path)


def metric_row(label: str, value: str) -> str:
    return f"<tr><th>{html.escape(label)}</th><td>{html.escape(value)}</td></tr>"


def relative_asset(path: Path, output_dir: Path) -> str:
    return path.relative_to(output_dir).as_posix()


def score_page(
    page: PageInput,
    thresholds: Thresholds,
    output_dir: Path,
    index: int,
) -> dict[str, Any]:
    source_image, source = load_rgb(page.source_path)
    candidate_image, candidate = load_rgb(page.candidate_path)
    baseline_image: Image.Image | None = None
    baseline: np.ndarray | None = None
    if page.baseline_path is not None:
        baseline_image, baseline = load_rgb(page.baseline_path)
    ensure_same_size(page.page_id, source_image, candidate_image, baseline_image)
    original_size = source_image.size
    separator_probes = horizontal_separator_probes(
        source,
        page.grouped_source_blocks,
        page.horizontal_merged_source_blocks,
    )
    separator_split_plans = horizontal_separator_split_plans(
        page.grouped_source_blocks,
        page.horizontal_merged_source_blocks,
        separator_probes,
    )
    allowed: np.ndarray | None = None
    if page.allowed_mask_path is not None:
        allowed = load_allowed_mask(page.allowed_mask_path, original_size)
    glyph_mask: np.ndarray | None = None
    if page.glyph_mask_path is not None:
        glyph_mask = load_glyph_mask(page.glyph_mask_path, original_size)
    container_mask: np.ndarray | None = None
    if page.container_mask_path is not None:
        container_mask = load_container_mask(page.container_mask_path, original_size)
    container_labels: np.ndarray | None = None
    if page.container_labels_path is not None:
        container_labels = load_container_labels(page.container_labels_path, original_size)
    if page.comparison_rect is not None:
        left, top, right, bottom = page.comparison_rect
        if right > original_size[0] or bottom > original_size[1]:
            raise ValueError(
                f"{page.page_id}: comparisonRect {page.comparison_rect} exceeds "
                f"page dimensions {original_size}"
            )
        source_image = source_image.crop(page.comparison_rect)
        candidate_image = candidate_image.crop(page.comparison_rect)
        source = source[top:bottom, left:right]
        candidate = candidate[top:bottom, left:right]
        if baseline_image is not None and baseline is not None:
            baseline_image = baseline_image.crop(page.comparison_rect)
            baseline = baseline[top:bottom, left:right]
        if allowed is not None:
            allowed = allowed[top:bottom, left:right]
        if glyph_mask is not None:
            glyph_mask = glyph_mask[top:bottom, left:right]
        if container_mask is not None:
            container_mask = container_mask[top:bottom, left:right]
        if container_labels is not None:
            container_labels = container_labels[top:bottom, left:right]
    width, height = source_image.size
    total_pixels = width * height
    changed = changed_mask(source, candidate, thresholds.pixel_delta)
    candidate_white = np.min(candidate, axis=2) >= thresholds.near_white
    source_was_white = np.min(source, axis=2) >= thresholds.source_white
    introduced_white = changed & candidate_white & ~source_was_white
    flatness_collapse = flatness_collapse_mask(
        source,
        candidate,
        changed,
        thresholds.flat_block,
        thresholds.texture_std,
        thresholds.flat_std,
    )
    component_count, largest_component, components = component_measurements(
        introduced_white,
        thresholds.minimum_component_pixels,
    )
    changed_pixels = int(np.count_nonzero(changed))
    introduced_white_pixels = int(np.count_nonzero(introduced_white))
    flatness_pixels = int(np.count_nonzero(flatness_collapse))
    outside_allowed_pixels: int | None = None
    if allowed is not None:
        outside_allowed_pixels = int(np.count_nonzero(changed & ~allowed))
    glyph_mask_pixels: int | None = None
    changed_inside_glyph_pixels: int | None = None
    if glyph_mask is not None:
        glyph_mask_pixels = int(np.count_nonzero(glyph_mask))
        changed_inside_glyph_pixels = int(np.count_nonzero(changed & glyph_mask))
    container_mask_pixels: int | None = None
    changed_outside_container_pixels: int | None = None
    glyph_outside_container_pixels: int | None = None
    if container_mask is not None:
        container_mask_pixels = int(np.count_nonzero(container_mask))
        changed_outside_container_pixels = int(
            np.count_nonzero(changed & ~container_mask)
        )
        if glyph_mask is not None:
            glyph_outside_container_pixels = int(
                np.count_nonzero(glyph_mask & ~container_mask)
            )
    container_candidate_results: list[dict[str, Any]] = []
    if container_labels is not None:
        for container_candidate in page.container_candidates:
            candidate_mask = container_labels == container_candidate.label
            candidate_pixels = int(np.count_nonzero(candidate_mask))
            if candidate_pixels <= 0:
                continue
            candidate_y, candidate_x = np.nonzero(candidate_mask)
            candidate_rect = [
                int(np.min(candidate_x)),
                int(np.min(candidate_y)),
                int(np.max(candidate_x)) + 1,
                int(np.max(candidate_y)) + 1,
            ]
            container_candidate_results.append(
                {
                    "label": container_candidate.label,
                    "confidence": round(container_candidate.confidence, 4),
                    "probeOutcome": container_candidate.probe_outcome,
                    "rawCoverage": (
                        round(container_candidate.raw_coverage, 4)
                        if container_candidate.raw_coverage is not None
                        else None
                    ),
                    "solidity": (
                        round(container_candidate.solidity, 4)
                        if container_candidate.solidity is not None
                        else None
                    ),
                    "areaRatio": (
                        round(container_candidate.area_ratio, 4)
                        if container_candidate.area_ratio is not None
                        else None
                    ),
                    "luminanceStd": (
                        round(container_candidate.luminance_std, 4)
                        if container_candidate.luminance_std is not None
                        else None
                    ),
                    "pixels": candidate_pixels,
                    "percent": percent(candidate_pixels, total_pixels),
                    "rect": candidate_rect,
                    "highConfidence":
                        container_candidate.confidence >= HIGH_CONTAINER_CONFIDENCE,
                }
            )
    container_probe_outcomes: dict[str, int] = {}
    for outcome in page.container_probe_outcomes:
        container_probe_outcomes[outcome] = container_probe_outcomes.get(outcome, 0) + 1
    rectangular_border_probes = [
        {
            "outcome": probe.outcome,
            "leftScore": round(probe.left_score, 4),
            "rightScore": round(probe.right_score, 4),
            "topScore": round(probe.top_score, 4),
            "bottomScore": round(probe.bottom_score, 4),
            "topLeftCornerScore": round(probe.top_left_corner_score, 4),
            "topRightCornerScore": round(probe.top_right_corner_score, 4),
            "bottomLeftCornerScore": round(probe.bottom_left_corner_score, 4),
            "bottomRightCornerScore": round(probe.bottom_right_corner_score, 4),
            "minimumScore": round(
                min(
                    probe.left_score,
                    probe.right_score,
                    probe.top_score,
                    probe.bottom_score,
                ),
                4,
            ),
            "minimumCornerScore": round(
                min(
                    probe.top_left_corner_score,
                    probe.top_right_corner_score,
                    probe.bottom_left_corner_score,
                    probe.bottom_right_corner_score,
                ),
                4,
            ),
        }
        for probe in page.rectangular_border_probes
    ]
    rectangular_border_probe_outcomes: dict[str, int] = {}
    for probe in page.rectangular_border_probes:
        rectangular_border_probe_outcomes[probe.outcome] = (
            rectangular_border_probe_outcomes.get(probe.outcome, 0) + 1
        )
    baseline_changed_pixels: int | None = None
    candidate_vs_baseline_pixels: int | None = None
    if baseline is not None:
        baseline_changed_pixels = int(
            np.count_nonzero(changed_mask(source, baseline, thresholds.pixel_delta))
        )
        candidate_vs_baseline_pixels = int(
            np.count_nonzero(changed_mask(baseline, candidate, thresholds.pixel_delta))
        )

    page_dir = output_dir / "assets" / f"{index + 1:02d}-{safe_name(page.page_id)}"
    page_dir.mkdir(parents=True, exist_ok=True)
    source_asset = page_dir / "source.png"
    candidate_asset = page_dir / "candidate.png"
    overlay_asset = page_dir / "overlay.png"
    save_thumbnail(source_image, source_asset)
    save_thumbnail(candidate_image, candidate_asset)
    save_overlay(
        candidate_image,
        changed,
        introduced_white,
        flatness_collapse,
        components,
        overlay_asset,
    )
    baseline_asset: Path | None = None
    if baseline_image is not None:
        baseline_asset = page_dir / "baseline.png"
        save_thumbnail(baseline_image, baseline_asset)
    glyph_mask_asset: Path | None = None
    if glyph_mask is not None:
        glyph_mask_asset = page_dir / "glyph-mask.png"
        save_mask_overlay(
            source_image,
            glyph_mask,
            glyph_mask_asset,
            (0, 220, 255, 185),
        )
    container_mask_asset: Path | None = None
    if container_mask is not None:
        container_mask_asset = page_dir / "container-mask.png"
        save_mask_overlay(
            source_image,
            container_mask,
            container_mask_asset,
            (52, 211, 153, 150),
        )
    container_labels_asset: Path | None = None
    if container_labels is not None:
        container_labels_asset = page_dir / "container-labels.png"
        save_container_label_overlay(
            source_image,
            container_labels,
            container_labels_asset,
        )
    grouping_split_asset: Path | None = None
    if separator_split_plans and page.comparison_rect is None:
        grouping_split_asset = page_dir / "grouping-split-plan.png"
        save_grouping_split_overlay(
            source_image,
            separator_split_plans,
            grouping_split_asset,
        )

    return {
        "id": page.page_id,
        "category": page.category,
        "width": width,
        "height": height,
        "sourceWidth": original_size[0],
        "sourceHeight": original_size[1],
        "comparisonRect": list(page.comparison_rect) if page.comparison_rect is not None else None,
        "analysisMs": page.analysis_ms,
        "renderMs": page.render_ms,
        "totalMs": page.total_ms,
        "renderStages": (
            {
                "decodeMs": page.render_stages.decode_ms,
                "maskMs": page.render_stages.mask_ms,
                "layoutMs": page.render_stages.layout_ms,
                "inpaintMs": page.render_stages.inpaint_ms,
                "drawMs": page.render_stages.draw_ms,
                "encodeMs": page.render_stages.encode_ms,
                "finalizeMs": page.render_stages.finalize_ms,
                "totalMs": page.render_stages.total_ms,
                "inpaintCallCount": page.render_stages.inpaint_call_count,
                "drawableGroupCount": page.render_stages.drawable_group_count,
                "skippedGroupCount": page.render_stages.skipped_group_count,
            }
            if page.render_stages is not None
            else None
        ),
        "sourceLayouts": [
            {
                "index": layout.index,
                "rect": list(layout.rect),
                "containerProbeOutcome": layout.container_probe_outcome,
                "rectangularBorderProbeOutcome":
                    layout.rectangular_border_probe_outcome,
            }
            for layout in page.source_layouts
        ],
        "documentSourceBlocks": [
            {
                "index": block.index,
                "blockId": block.block_id,
                "rect": list(block.rect),
                "kind": block.kind,
                "preserved": block.preserved,
            }
            for block in page.document_source_blocks
        ],
        "groupingStages": {
            "groupedBlocks": len(page.grouped_source_blocks),
            "horizontalMergedBlocks":
                len(page.horizontal_merged_source_blocks),
            "multiRegionHorizontalMergedBlocks": sum(
                1
                for block in page.horizontal_merged_source_blocks
                if block.style_hint == "horizontal-ltr"
                and len(block.detector_region_indexes) >= 2
            ),
            "horizontalSeparatorProbes": separator_probes,
            "strongSeparatorCandidates": sum(
                1
                for probe in separator_probes
                if probe["strongSeparatorCandidate"]
            ),
            "separatorSplitPlans": separator_split_plans,
            "separatorSplitOutputBlocks": sum(
                len(plan["segments"])
                for plan in separator_split_plans
                if plan["safeForCandidateGrouping"]
            ),
            "separatorSplitBlockDelta": sum(
                int(plan["sourceBlockDelta"])
                for plan in separator_split_plans
                if plan["safeForCandidateGrouping"]
            ),
            "safeSeparatorSplitPlans": sum(
                1
                for plan in separator_split_plans
                if plan["safeForCandidateGrouping"]
            ),
        },
        "changedPixels": changed_pixels,
        "changedPercent": percent(changed_pixels, total_pixels),
        "introducedWhitePixels": introduced_white_pixels,
        "introducedWhitePercent": percent(introduced_white_pixels, total_pixels),
        "introducedWhiteOfChangedPercent": percent(
            introduced_white_pixels,
            changed_pixels,
        ),
        "introducedWhiteComponents": component_count,
        "largestIntroducedWhiteComponentPixels": largest_component,
        "largestIntroducedWhiteComponentPercent": percent(
            largest_component,
            total_pixels,
        ),
        "flatnessCollapsePixels": flatness_pixels,
        "flatnessCollapsePercent": percent(flatness_pixels, total_pixels),
        "outsideAllowedPixels": outside_allowed_pixels,
        "outsideAllowedPercent": (
            percent(outside_allowed_pixels, total_pixels)
            if outside_allowed_pixels is not None
            else None
        ),
        "outsideAllowedOfChangedPercent": (
            percent(outside_allowed_pixels, changed_pixels)
            if outside_allowed_pixels is not None
            else None
        ),
        "glyphMaskPixels": glyph_mask_pixels,
        "glyphMaskPercent": (
            percent(glyph_mask_pixels, total_pixels)
            if glyph_mask_pixels is not None
            else None
        ),
        "changedInsideGlyphPercent": (
            percent(changed_inside_glyph_pixels, glyph_mask_pixels)
            if changed_inside_glyph_pixels is not None
            and glyph_mask_pixels is not None
            else None
        ),
        "containerMaskPixels": container_mask_pixels,
        "containerMaskPercent": (
            percent(container_mask_pixels, total_pixels)
            if container_mask_pixels is not None
            else None
        ),
        "changedOutsideContainerPercent": (
            percent(changed_outside_container_pixels, total_pixels)
            if changed_outside_container_pixels is not None
            else None
        ),
        "glyphOutsideContainerPercent": (
            percent(glyph_outside_container_pixels, glyph_mask_pixels)
            if glyph_outside_container_pixels is not None
            and glyph_mask_pixels is not None
            else None
        ),
        "containerDetections": len(page.container_confidences),
        "layoutCount": page.layout_count,
        "containerCandidateLayoutPercent": (
            percent(len(page.container_confidences), page.layout_count)
            if page.layout_count is not None
            else None
        ),
        "highConfidenceContainerDetections": sum(
            confidence >= HIGH_CONTAINER_CONFIDENCE
            for confidence in page.container_confidences
        ),
        "containerConfidenceMin": (
            round(min(page.container_confidences), 4)
            if page.container_confidences
            else None
        ),
        "containerConfidenceMean": (
            round(sum(page.container_confidences) / len(page.container_confidences), 4)
            if page.container_confidences
            else None
        ),
        "containerConfidenceMax": (
            round(max(page.container_confidences), 4)
            if page.container_confidences
            else None
        ),
        "containerCandidates": container_candidate_results,
        "containerProbeOutcomes": container_probe_outcomes,
        "rectangularBorderProbes": rectangular_border_probes,
        "rectangularBorderProbeOutcomes": rectangular_border_probe_outcomes,
        "baselineChangedPercent": (
            percent(baseline_changed_pixels, total_pixels)
            if baseline_changed_pixels is not None
            else None
        ),
        "candidateVsBaselinePercent": (
            percent(candidate_vs_baseline_pixels, total_pixels)
            if candidate_vs_baseline_pixels is not None
            else None
        ),
        "assets": {
            "source": relative_asset(source_asset, output_dir),
            "candidate": relative_asset(candidate_asset, output_dir),
            "baseline": (
                relative_asset(baseline_asset, output_dir)
                if baseline_asset is not None
                else None
            ),
            "overlay": relative_asset(overlay_asset, output_dir),
            "glyphMask": (
                relative_asset(glyph_mask_asset, output_dir)
                if glyph_mask_asset is not None
                else None
            ),
            "containerMask": (
                relative_asset(container_mask_asset, output_dir)
                if container_mask_asset is not None
                else None
            ),
            "containerLabels": (
                relative_asset(container_labels_asset, output_dir)
                if container_labels_asset is not None
                else None
            ),
            "groupingSplitPlan": (
                relative_asset(grouping_split_asset, output_dir)
                if grouping_split_asset is not None
                else None
            ),
        },
    }


def safe_name(value: str) -> str:
    result = "".join(character if character.isalnum() else "-" for character in value)
    result = result.strip("-")
    return result[:80] or "page"


def aggregate(results: list[dict[str, Any]]) -> dict[str, Any]:
    totals: dict[str, int] = {
        "pixels": 0,
        "changed": 0,
        "introducedWhite": 0,
        "flatnessCollapse": 0,
        "outsideAllowed": 0,
        "outsideAllowedPages": 0,
        "containerDetections": 0,
        "highConfidenceContainerDetections": 0,
        "layouts": 0,
        "layoutPages": 0,
        "analysisMs": 0,
        "renderMs": 0,
        "totalMs": 0,
        "timedPages": 0,
        "renderStagePages": 0,
        "renderStageDecodeMs": 0,
        "renderStageMaskMs": 0,
        "renderStageLayoutMs": 0,
        "renderStageInpaintMs": 0,
        "renderStageDrawMs": 0,
        "renderStageEncodeMs": 0,
        "renderStageFinalizeMs": 0,
        "renderStageTotalMs": 0,
        "drawableGroups": 0,
        "skippedGroups": 0,
        "inpaintCalls": 0,
        "inpaintCallPages": 0,
        "groupedSourceBlocks": 0,
        "horizontalMergedSourceBlocks": 0,
        "multiRegionHorizontalMergedBlocks": 0,
        "horizontalSeparatorProbes": 0,
        "strongSeparatorCandidates": 0,
        "separatorSplitPlans": 0,
        "separatorSplitOutputBlocks": 0,
        "separatorSplitBlockDelta": 0,
        "safeSeparatorSplitPlans": 0,
    }
    container_confidences: list[float] = []
    container_probe_outcomes: dict[str, int] = {}
    rectangular_border_probe_outcomes: dict[str, int] = {}
    rectangular_border_side_scores: list[float] = []
    rectangular_border_scores_by_side: dict[str, list[float]] = {
        "left": [],
        "right": [],
        "top": [],
        "bottom": [],
    }
    rectangular_border_minimum_scores: list[float] = []
    rectangular_border_corner_scores: list[float] = []
    rectangular_border_minimum_corner_scores: list[float] = []
    total_samples: list[int] = []
    categories: dict[str, dict[str, int]] = {}
    for result in results:
        pixels = int(result["width"]) * int(result["height"])
        totals["pixels"] += pixels
        totals["changed"] += int(result["changedPixels"])
        totals["introducedWhite"] += int(result["introducedWhitePixels"])
        totals["flatnessCollapse"] += int(result["flatnessCollapsePixels"])
        if result["outsideAllowedPixels"] is not None:
            totals["outsideAllowed"] += int(result["outsideAllowedPixels"])
            totals["outsideAllowedPages"] += 1
        totals["containerDetections"] += int(result["containerDetections"])
        totals["highConfidenceContainerDetections"] += int(
            result["highConfidenceContainerDetections"]
        )
        if result["layoutCount"] is not None:
            totals["layouts"] += int(result["layoutCount"])
            totals["layoutPages"] += 1
        grouping_stages = result["groupingStages"]
        totals["groupedSourceBlocks"] += int(grouping_stages["groupedBlocks"])
        totals["horizontalMergedSourceBlocks"] += int(
            grouping_stages["horizontalMergedBlocks"]
        )
        totals["multiRegionHorizontalMergedBlocks"] += int(
            grouping_stages["multiRegionHorizontalMergedBlocks"]
        )
        totals["horizontalSeparatorProbes"] += len(
            grouping_stages["horizontalSeparatorProbes"]
        )
        totals["strongSeparatorCandidates"] += int(
            grouping_stages["strongSeparatorCandidates"]
        )
        totals["separatorSplitPlans"] += len(
            grouping_stages["separatorSplitPlans"]
        )
        totals["separatorSplitOutputBlocks"] += int(
            grouping_stages["separatorSplitOutputBlocks"]
        )
        totals["separatorSplitBlockDelta"] += int(
            grouping_stages["separatorSplitBlockDelta"]
        )
        totals["safeSeparatorSplitPlans"] += int(
            grouping_stages["safeSeparatorSplitPlans"]
        )
        if result["totalMs"] is not None:
            totals["analysisMs"] += int(result["analysisMs"])
            totals["renderMs"] += int(result["renderMs"])
            totals["totalMs"] += int(result["totalMs"])
            totals["timedPages"] += 1
            total_samples.append(int(result["totalMs"]))
        render_stages = result["renderStages"]
        if isinstance(render_stages, dict):
            totals["renderStagePages"] += 1
            totals["renderStageDecodeMs"] += int(render_stages["decodeMs"])
            totals["renderStageMaskMs"] += int(render_stages["maskMs"])
            totals["renderStageLayoutMs"] += int(render_stages["layoutMs"])
            totals["renderStageInpaintMs"] += int(render_stages["inpaintMs"])
            totals["renderStageDrawMs"] += int(render_stages["drawMs"])
            totals["renderStageEncodeMs"] += int(render_stages["encodeMs"])
            totals["renderStageFinalizeMs"] += int(render_stages["finalizeMs"])
            totals["renderStageTotalMs"] += int(render_stages["totalMs"])
            if render_stages["inpaintCallCount"] is not None:
                totals["inpaintCalls"] += int(render_stages["inpaintCallCount"])
                totals["inpaintCallPages"] += 1
            totals["drawableGroups"] += int(render_stages["drawableGroupCount"])
            totals["skippedGroups"] += int(render_stages["skippedGroupCount"])
        confidence_mean = result["containerConfidenceMean"]
        if confidence_mean is not None:
            container_confidences.extend(
                [float(confidence_mean)] * int(result["containerDetections"])
            )
        for outcome, count in result["containerProbeOutcomes"].items():
            container_probe_outcomes[outcome] = (
                container_probe_outcomes.get(outcome, 0) + int(count)
            )
        for outcome, count in result["rectangularBorderProbeOutcomes"].items():
            rectangular_border_probe_outcomes[outcome] = (
                rectangular_border_probe_outcomes.get(outcome, 0) + int(count)
            )
        for probe in result["rectangularBorderProbes"]:
            for side in ("left", "right", "top", "bottom"):
                score = float(probe[f"{side}Score"])
                rectangular_border_side_scores.append(score)
                rectangular_border_scores_by_side[side].append(score)
            rectangular_border_minimum_scores.append(float(probe["minimumScore"]))
            rectangular_border_corner_scores.extend(
                [
                    float(probe["topLeftCornerScore"]),
                    float(probe["topRightCornerScore"]),
                    float(probe["bottomLeftCornerScore"]),
                    float(probe["bottomRightCornerScore"]),
                ]
            )
            rectangular_border_minimum_corner_scores.append(
                float(probe["minimumCornerScore"])
            )
        category = str(result["category"])
        category_result = categories.setdefault(
            category,
            {"pages": 0, "pixels": 0, "changed": 0, "introducedWhite": 0},
        )
        category_result["pages"] += 1
        category_result["pixels"] += pixels
        category_result["changed"] += int(result["changedPixels"])
        category_result["introducedWhite"] += int(result["introducedWhitePixels"])
    category_rows: list[dict[str, Any]] = []
    for category in sorted(categories):
        value = categories[category]
        category_rows.append(
            {
                "category": category,
                "pages": value["pages"],
                "changedPercent": percent(value["changed"], value["pixels"]),
                "introducedWhitePercent": percent(
                    value["introducedWhite"],
                    value["pixels"],
                ),
            }
        )
    total_samples.sort()
    timing_median: float | None = None
    if total_samples:
        middle = len(total_samples) // 2
        if len(total_samples) % 2 == 1:
            timing_median = float(total_samples[middle])
        else:
            timing_median = (
                total_samples[middle - 1] + total_samples[middle]
            ) / 2.0
    return {
        "pages": len(results),
        "changedPercent": percent(totals["changed"], totals["pixels"]),
        "introducedWhitePercent": percent(
            totals["introducedWhite"],
            totals["pixels"],
        ),
        "flatnessCollapsePercent": percent(
            totals["flatnessCollapse"],
            totals["pixels"],
        ),
        "outsideAllowedPercent": (
            percent(totals["outsideAllowed"], totals["pixels"])
            if totals["outsideAllowedPages"] > 0
            else None
        ),
        "outsideAllowedPages": totals["outsideAllowedPages"],
        "containerDetections": totals["containerDetections"],
        "highConfidenceContainerDetections": totals[
            "highConfidenceContainerDetections"
        ],
        "layoutCount": totals["layouts"] if totals["layoutPages"] > 0 else None,
        "groupedSourceBlocks": totals["groupedSourceBlocks"],
        "horizontalMergedSourceBlocks": totals[
            "horizontalMergedSourceBlocks"
        ],
        "multiRegionHorizontalMergedBlocks": totals[
            "multiRegionHorizontalMergedBlocks"
        ],
        "horizontalSeparatorProbes": totals["horizontalSeparatorProbes"],
        "strongSeparatorCandidates": totals["strongSeparatorCandidates"],
        "separatorSplitPlans": totals["separatorSplitPlans"],
        "separatorSplitOutputBlocks": totals["separatorSplitOutputBlocks"],
        "separatorSplitBlockDelta": totals["separatorSplitBlockDelta"],
        "safeSeparatorSplitPlans": totals["safeSeparatorSplitPlans"],
        "containerCandidateLayoutPercent": (
            percent(totals["containerDetections"], totals["layouts"])
            if totals["layoutPages"] > 0
            else None
        ),
        "containerConfidenceMean": (
            round(sum(container_confidences) / len(container_confidences), 4)
            if container_confidences
            else None
        ),
        "containerProbeOutcomes": container_probe_outcomes,
        "rectangularBorderProbeOutcomes": rectangular_border_probe_outcomes,
        "rectangularBorderProbeCount": len(rectangular_border_minimum_scores),
        "rectangularBorderSideScoreMean": (
            round(
                sum(rectangular_border_side_scores) /
                len(rectangular_border_side_scores),
                4,
            )
            if rectangular_border_side_scores
            else None
        ),
        "rectangularBorderScoreMeanBySide": (
            {
                side: round(sum(scores) / len(scores), 4)
                for side, scores in rectangular_border_scores_by_side.items()
            }
            if rectangular_border_side_scores
            else None
        ),
        "rectangularBorderMinimumScoreMean": (
            round(
                sum(rectangular_border_minimum_scores) /
                len(rectangular_border_minimum_scores),
                4,
            )
            if rectangular_border_minimum_scores
            else None
        ),
        "rectangularBorderMinimumScoreMin": (
            round(min(rectangular_border_minimum_scores), 4)
            if rectangular_border_minimum_scores
            else None
        ),
        "rectangularBorderCornerScoreMean": (
            round(
                sum(rectangular_border_corner_scores) /
                len(rectangular_border_corner_scores),
                4,
            )
            if rectangular_border_corner_scores
            else None
        ),
        "rectangularBorderMinimumCornerScoreMean": (
            round(
                sum(rectangular_border_minimum_corner_scores) /
                len(rectangular_border_minimum_corner_scores),
                4,
            )
            if rectangular_border_minimum_corner_scores
            else None
        ),
        "timedPages": totals["timedPages"],
        "analysisMsMean": (
            round(totals["analysisMs"] / totals["timedPages"], 1)
            if totals["timedPages"] > 0
            else None
        ),
        "renderMsMean": (
            round(totals["renderMs"] / totals["timedPages"], 1)
            if totals["timedPages"] > 0
            else None
        ),
        "totalMsMean": (
            round(totals["totalMs"] / totals["timedPages"], 1)
            if totals["timedPages"] > 0
            else None
        ),
        "totalMsMedian": timing_median,
        "totalMsMin": min(total_samples) if total_samples else None,
        "totalMsMax": max(total_samples) if total_samples else None,
        "renderTimePercent": (
            percent(totals["renderMs"], totals["totalMs"])
            if totals["timedPages"] > 0
            else None
        ),
        "renderStagePages": totals["renderStagePages"],
        "renderStageMsMean": (
            {
                "decode": round(
                    totals["renderStageDecodeMs"] / totals["renderStagePages"],
                    1,
                ),
                "mask": round(
                    totals["renderStageMaskMs"] / totals["renderStagePages"],
                    1,
                ),
                "layout": round(
                    totals["renderStageLayoutMs"] / totals["renderStagePages"],
                    1,
                ),
                "inpaint": round(
                    totals["renderStageInpaintMs"] / totals["renderStagePages"],
                    1,
                ),
                "draw": round(
                    totals["renderStageDrawMs"] / totals["renderStagePages"],
                    1,
                ),
                "encode": round(
                    totals["renderStageEncodeMs"] / totals["renderStagePages"],
                    1,
                ),
                "finalize": round(
                    totals["renderStageFinalizeMs"] / totals["renderStagePages"],
                    1,
                ),
                "total": round(
                    totals["renderStageTotalMs"] / totals["renderStagePages"],
                    1,
                ),
            }
            if totals["renderStagePages"] > 0
            else None
        ),
        "renderStagePercent": (
            {
                "decode": percent(
                    totals["renderStageDecodeMs"],
                    totals["renderStageTotalMs"],
                ),
                "mask": percent(
                    totals["renderStageMaskMs"],
                    totals["renderStageTotalMs"],
                ),
                "layout": percent(
                    totals["renderStageLayoutMs"],
                    totals["renderStageTotalMs"],
                ),
                "inpaint": percent(
                    totals["renderStageInpaintMs"],
                    totals["renderStageTotalMs"],
                ),
                "draw": percent(
                    totals["renderStageDrawMs"],
                    totals["renderStageTotalMs"],
                ),
                "encode": percent(
                    totals["renderStageEncodeMs"],
                    totals["renderStageTotalMs"],
                ),
                "finalize": percent(
                    totals["renderStageFinalizeMs"],
                    totals["renderStageTotalMs"],
                ),
            }
            if totals["renderStagePages"] > 0
            else None
        ),
        "drawableGroupMean": (
            round(totals["drawableGroups"] / totals["renderStagePages"], 1)
            if totals["renderStagePages"] > 0
            else None
        ),
        "inpaintCallMean": (
            round(totals["inpaintCalls"] / totals["inpaintCallPages"], 1)
            if totals["inpaintCallPages"] > 0
            else None
        ),
        "skippedGroupCount": totals["skippedGroups"],
        "categories": category_rows,
    }


def apply_container_review(
    path: Path,
    fixture_set_id: str,
    results: list[dict[str, Any]],
    summary: dict[str, Any],
) -> None:
    review_path = path.expanduser().resolve()
    raw = require_dict(
        json.loads(review_path.read_text(encoding="utf-8")),
        "container review",
    )
    review_schema_version = raw.get("schemaVersion")
    if review_schema_version not in (SCHEMA_VERSION, 2):
        raise ValueError("container review schemaVersion is unsupported")
    if require_string(raw.get("fixtureSetId"), "container review.fixtureSetId") != fixture_set_id:
        raise ValueError("container review fixtureSetId does not match")
    review_pages = require_list(raw.get("pages"), "container review.pages")
    result_by_id = {str(result["id"]): result for result in results}
    reviewed_ids: set[str] = set()
    expected_total = 0
    accepted_total = 0
    rejected_total = 0
    high_accepted = 0
    high_rejected = 0
    eligible_target_total = 0
    merged_source_target_total = 0
    preserved_source_target_total = 0
    preserved_merged_source_target_total = 0
    unrendered_source_target_total = 0
    unrendered_merged_source_target_total = 0
    missing_source_target_total = 0
    eligible_target_matched = 0
    review_by_probe_outcome: dict[str, dict[str, int]] = {}
    for page_index, page_value in enumerate(review_pages):
        page_review = require_dict(
            page_value,
            f"container review.pages[{page_index}]",
        )
        page_id = require_string(
            page_review.get("id"),
            f"container review.pages[{page_index}].id",
        )
        if page_id in reviewed_ids or page_id not in result_by_id:
            raise ValueError(f"container review page is unknown or duplicated: {page_id}")
        reviewed_ids.add(page_id)
        result = result_by_id[page_id]
        observed_candidates = {
            int(candidate["label"]): candidate
            for candidate in result["containerCandidates"]
        }
        if review_schema_version == 2:
            target_values = require_list(
                page_review.get("targets"),
                f"container review.pages[{page_index}].targets",
            )
            targets: list[dict[str, Any]] = []
            target_ids: set[str] = set()
            for target_index, target_value in enumerate(target_values):
                target = require_dict(
                    target_value,
                    (
                        f"container review.pages[{page_index}]."
                        f"targets[{target_index}]"
                    ),
                )
                target_id = require_string(
                    target.get("id"),
                    (
                        f"container review.pages[{page_index}]."
                        f"targets[{target_index}].id"
                    ),
                )
                target_rect = optional_rect(
                    target.get("rect"),
                    (
                        f"container review.pages[{page_index}]."
                        f"targets[{target_index}].rect"
                    ),
                )
                if target_id in target_ids or target_rect is None:
                    raise ValueError(
                        f"container review target is invalid: {page_id}#{target_id}"
                    )
                target_ids.add(target_id)
                targets.append({"id": target_id, "rect": list(target_rect)})
            expected_count = len(targets)
            target_source_status: list[dict[str, Any]] = []
            eligible_target_ids: set[str] = set()
            for target in targets:
                target_rect = target["rect"]
                target_left = int(target_rect[0])
                target_top = int(target_rect[1])
                target_right = int(target_rect[2])
                target_bottom = int(target_rect[3])
                target_area = max(
                    1,
                    (target_right - target_left) * (target_bottom - target_top),
                )
                contained_layouts: list[int] = []
                merged_layouts: list[int] = []
                for source_layout in result["sourceLayouts"]:
                    source_rect = source_layout["rect"]
                    source_left = int(source_rect[0])
                    source_top = int(source_rect[1])
                    source_right = int(source_rect[2])
                    source_bottom = int(source_rect[3])
                    intersection_width = max(
                        0,
                        min(source_right, target_right) -
                        max(source_left, target_left),
                    )
                    intersection_height = max(
                        0,
                        min(source_bottom, target_bottom) -
                        max(source_top, target_top),
                    )
                    intersection = intersection_width * intersection_height
                    source_area = max(
                        1,
                        (source_right - source_left) *
                        (source_bottom - source_top),
                    )
                    source_coverage = intersection / source_area
                    target_coverage = intersection / target_area
                    source_center_x = (source_left + source_right) / 2
                    source_center_y = (source_top + source_bottom) / 2
                    center_inside = (
                        target_left <= source_center_x <= target_right and
                        target_top <= source_center_y <= target_bottom
                    )
                    if center_inside and source_coverage >= 0.75:
                        contained_layouts.append(int(source_layout["index"]))
                    elif target_coverage >= 0.5:
                        merged_layouts.append(int(source_layout["index"]))
                contained_document_blocks: list[int] = []
                merged_document_blocks: list[int] = []
                preserved_document_blocks: set[int] = set()
                for document_block in result["documentSourceBlocks"]:
                    source_rect = document_block["rect"]
                    source_left = int(source_rect[0])
                    source_top = int(source_rect[1])
                    source_right = int(source_rect[2])
                    source_bottom = int(source_rect[3])
                    intersection_width = max(
                        0,
                        min(source_right, target_right) -
                        max(source_left, target_left),
                    )
                    intersection_height = max(
                        0,
                        min(source_bottom, target_bottom) -
                        max(source_top, target_top),
                    )
                    intersection = intersection_width * intersection_height
                    source_area = max(
                        1,
                        (source_right - source_left) *
                        (source_bottom - source_top),
                    )
                    source_coverage = intersection / source_area
                    target_coverage = intersection / target_area
                    source_center_x = (source_left + source_right) / 2
                    source_center_y = (source_top + source_bottom) / 2
                    center_inside = (
                        target_left <= source_center_x <= target_right and
                        target_top <= source_center_y <= target_bottom
                    )
                    document_index = int(document_block["index"])
                    if bool(document_block["preserved"]):
                        preserved_document_blocks.add(document_index)
                    if center_inside and source_coverage >= 0.75:
                        contained_document_blocks.append(document_index)
                    elif target_coverage >= 0.5:
                        merged_document_blocks.append(document_index)
                if contained_layouts:
                    source_status = "eligible"
                    eligible_target_ids.add(str(target["id"]))
                    eligible_target_total += 1
                elif merged_layouts:
                    source_status = "merged_source"
                    merged_source_target_total += 1
                elif any(
                    index in preserved_document_blocks
                    for index in contained_document_blocks
                ):
                    source_status = "preserved_source"
                    preserved_source_target_total += 1
                elif any(
                    index in preserved_document_blocks
                    for index in merged_document_blocks
                ):
                    source_status = "preserved_merged_source"
                    preserved_merged_source_target_total += 1
                elif contained_document_blocks:
                    source_status = "unrendered_source"
                    unrendered_source_target_total += 1
                elif merged_document_blocks:
                    source_status = "unrendered_merged_source"
                    unrendered_merged_source_target_total += 1
                else:
                    source_status = "missing_source"
                    missing_source_target_total += 1
                target_source_status.append(
                    {
                        "targetId": target["id"],
                        "status": source_status,
                        "containedLayoutIndices": contained_layouts,
                        "mergedLayoutIndices": merged_layouts,
                        "containedDocumentBlockIndices":
                            contained_document_blocks,
                        "mergedDocumentBlockIndices":
                            merged_document_blocks,
                        "preservedDocumentBlockIndices": sorted(
                            preserved_document_blocks.intersection(
                                contained_document_blocks + merged_document_blocks
                            )
                        ),
                    }
                )
            matched_labels: set[int] = set()
            matched_targets: set[str] = set()
            matches: list[dict[str, Any]] = []
            match_options: list[tuple[float, int, str]] = []
            for label, candidate in observed_candidates.items():
                candidate_rect = candidate.get("rect")
                if not isinstance(candidate_rect, list) or len(candidate_rect) != 4:
                    raise ValueError(
                        f"container candidate rect is unavailable: {page_id}#{label}"
                    )
                candidate_left = int(candidate_rect[0])
                candidate_top = int(candidate_rect[1])
                candidate_right = int(candidate_rect[2])
                candidate_bottom = int(candidate_rect[3])
                candidate_area = max(
                    1,
                    (candidate_right - candidate_left) *
                    (candidate_bottom - candidate_top),
                )
                for target in targets:
                    target_rect = target["rect"]
                    target_left = int(target_rect[0])
                    target_top = int(target_rect[1])
                    target_right = int(target_rect[2])
                    target_bottom = int(target_rect[3])
                    intersection_width = max(
                        0,
                        min(candidate_right, target_right) -
                        max(candidate_left, target_left),
                    )
                    intersection_height = max(
                        0,
                        min(candidate_bottom, target_bottom) -
                        max(candidate_top, target_top),
                    )
                    intersection = intersection_width * intersection_height
                    target_area = max(
                        1,
                        (target_right - target_left) * (target_bottom - target_top),
                    )
                    overlap = intersection / min(candidate_area, target_area)
                    if overlap >= 0.5:
                        match_options.append(
                            (overlap, label, str(target["id"]))
                        )
            match_options.sort(reverse=True)
            for overlap, label, target_id in match_options:
                if label in matched_labels or target_id in matched_targets:
                    continue
                matched_labels.add(label)
                matched_targets.add(target_id)
                observed_candidates[label]["accepted"] = True
                observed_candidates[label]["matchedTargetId"] = target_id
                observed_candidates[label]["targetOverlapPercent"] = percent(overlap, 1)
                matches.append(
                    {
                        "label": label,
                        "targetId": target_id,
                        "overlapPercent": percent(overlap, 1),
                    }
                )
            for label, candidate in observed_candidates.items():
                if label not in matched_labels:
                    candidate["accepted"] = False
            accepted_count = len(matched_labels)
            rejected_count = len(observed_candidates) - accepted_count
            for label, candidate in observed_candidates.items():
                probe_outcome = str(candidate["probeOutcome"])
                probe_review = review_by_probe_outcome.setdefault(
                    probe_outcome,
                    {"accepted": 0, "rejected": 0},
                )
                if label in matched_labels:
                    probe_review["accepted"] += 1
                    if candidate["highConfidence"]:
                        high_accepted += 1
                else:
                    probe_review["rejected"] += 1
                    if candidate["highConfidence"]:
                        high_rejected += 1
            result["containerReview"] = {
                "expectedContainers": expected_count,
                "acceptedCandidates": accepted_count,
                "rejectedCandidates": rejected_count,
                "missedContainers": expected_count - accepted_count,
                "matches": matches,
                "missedTargetIds": sorted(target_ids - matched_targets),
                "targetSourceStatus": target_source_status,
            }
            eligible_target_matched += len(eligible_target_ids & matched_targets)
            expected_total += expected_count
            accepted_total += accepted_count
            rejected_total += rejected_count
            continue
        expected_count = bounded_int(
            page_review.get("expectedContainers"),
            0,
            0,
            10000,
            f"container review.pages[{page_index}].expectedContainers",
        )
        candidate_reviews = require_list(
            page_review.get("candidates"),
            f"container review.pages[{page_index}].candidates",
        )
        reviewed_labels: set[int] = set()
        accepted_count = 0
        rejected_count = 0
        for candidate_index, candidate_value in enumerate(candidate_reviews):
            candidate_review = require_dict(
                candidate_value,
                (
                    f"container review.pages[{page_index}]."
                    f"candidates[{candidate_index}]"
                ),
            )
            label = bounded_int(
                candidate_review.get("label"),
                0,
                1,
                254,
                (
                    f"container review.pages[{page_index}]."
                    f"candidates[{candidate_index}].label"
                ),
            )
            accepted = candidate_review.get("accepted")
            if (
                not isinstance(accepted, bool)
                or label in reviewed_labels
                or label not in observed_candidates
            ):
                raise ValueError(
                    f"container review candidate is invalid: {page_id}#{label}"
                )
            reviewed_labels.add(label)
            observed_candidates[label]["accepted"] = accepted
            probe_outcome = str(observed_candidates[label]["probeOutcome"])
            probe_review = review_by_probe_outcome.setdefault(
                probe_outcome,
                {"accepted": 0, "rejected": 0},
            )
            if accepted:
                accepted_count += 1
                probe_review["accepted"] += 1
                if observed_candidates[label]["highConfidence"]:
                    high_accepted += 1
            else:
                rejected_count += 1
                probe_review["rejected"] += 1
                if observed_candidates[label]["highConfidence"]:
                    high_rejected += 1
        if reviewed_labels != set(observed_candidates):
            raise ValueError(f"container review is incomplete for page: {page_id}")
        if accepted_count > expected_count:
            raise ValueError(f"container review accepts too many candidates: {page_id}")
        result["containerReview"] = {
            "expectedContainers": expected_count,
            "acceptedCandidates": accepted_count,
            "rejectedCandidates": rejected_count,
            "missedContainers": expected_count - accepted_count,
        }
        expected_total += expected_count
        accepted_total += accepted_count
        rejected_total += rejected_count
    reviewed_candidates = accepted_total + rejected_total
    summary["containerReview"] = {
        "reviewedPages": len(reviewed_ids),
        "expectedContainers": expected_total,
        "acceptedCandidates": accepted_total,
        "rejectedCandidates": rejected_total,
        "missedContainers": expected_total - accepted_total,
        "candidatePrecisionPercent": (
            percent(accepted_total, reviewed_candidates)
            if reviewed_candidates > 0
            else None
        ),
        "candidateRecallPercent": (
            percent(accepted_total, expected_total)
            if expected_total > 0
            else None
        ),
        "highConfidenceAccepted": high_accepted,
        "highConfidenceRejected": high_rejected,
        "highConfidencePrecisionPercent": (
            percent(high_accepted, high_accepted + high_rejected)
            if high_accepted + high_rejected > 0
            else None
        ),
        "highConfidenceRecallPercent": (
            percent(high_accepted, expected_total)
            if expected_total > 0
            else None
        ),
        "byProbeOutcome": review_by_probe_outcome,
    }
    if review_schema_version == 2:
        summary["containerReview"]["eligibleTargets"] = eligible_target_total
        summary["containerReview"]["mergedSourceTargets"] = merged_source_target_total
        summary["containerReview"]["preservedSourceTargets"] = (
            preserved_source_target_total
        )
        summary["containerReview"]["preservedMergedSourceTargets"] = (
            preserved_merged_source_target_total
        )
        summary["containerReview"]["unrenderedSourceTargets"] = (
            unrendered_source_target_total
        )
        summary["containerReview"]["unrenderedMergedSourceTargets"] = (
            unrendered_merged_source_target_total
        )
        summary["containerReview"]["missingSourceTargets"] = missing_source_target_total
        summary["containerReview"]["eligibleMatchedTargets"] = eligible_target_matched
        summary["containerReview"]["eligibleRecallPercent"] = (
            percent(eligible_target_matched, eligible_target_total)
            if eligible_target_total > 0
            else None
        )


def metric_delta(candidate: Any, baseline: Any) -> float | None:
    if candidate is None or baseline is None:
        return None
    if not isinstance(candidate, (int, float)) or isinstance(candidate, bool):
        return None
    if not isinstance(baseline, (int, float)) or isinstance(baseline, bool):
        return None
    return round(float(candidate) - float(baseline), 4)


def load_baseline_report(
    path: Path,
    fixture_set_id: str,
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    baseline_path = path.expanduser().resolve()
    raw = require_dict(
        json.loads(baseline_path.read_text(encoding="utf-8")),
        "baseline report",
    )
    if raw.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"baseline report schemaVersion must be {SCHEMA_VERSION}")
    if raw.get("fixtureSetId") != fixture_set_id:
        raise ValueError("baseline report fixtureSetId does not match the manifest")
    pages = require_list(raw.get("pages"), "baseline report.pages")
    by_id: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(pages):
        page = require_dict(value, f"baseline report.pages[{index}]")
        page_id = require_string(page.get("id"), f"baseline report.pages[{index}].id")
        by_id[page_id] = page
    return by_id, require_dict(raw.get("summary"), "baseline report.summary")


def apply_baseline_comparison(
    results: list[dict[str, Any]],
    summary: dict[str, Any],
    baseline_pages: dict[str, dict[str, Any]],
    baseline_summary: dict[str, Any],
) -> None:
    metric_names = (
        "changedPercent",
        "introducedWhitePercent",
        "largestIntroducedWhiteComponentPercent",
        "flatnessCollapsePercent",
        "outsideAllowedPercent",
    )
    missing: list[str] = []
    for result in results:
        page_id = str(result["id"])
        baseline = baseline_pages.get(page_id)
        if baseline is None:
            missing.append(page_id)
            continue
        deltas: dict[str, float | None] = {}
        for metric_name in metric_names:
            deltas[metric_name] = metric_delta(
                result.get(metric_name),
                baseline.get(metric_name),
            )
        result["baselineReportDelta"] = deltas
    summary_deltas: dict[str, float | None] = {}
    for metric_name in (
        "changedPercent",
        "introducedWhitePercent",
        "flatnessCollapsePercent",
        "outsideAllowedPercent",
    ):
        summary_deltas[metric_name] = metric_delta(
            summary.get(metric_name),
            baseline_summary.get(metric_name),
        )
    summary["baselineReportDelta"] = summary_deltas
    summary["baselineMissingPages"] = missing


def page_section(result: dict[str, Any]) -> str:
    assets = require_dict(result["assets"], "result.assets")
    images: list[str] = []
    for label, key in (
        ("Source", "source"),
        ("Glyph mask on source", "glyphMask"),
        ("Container mask on source", "containerMask"),
        ("Container candidates on source", "containerLabels"),
        ("Recording grouping split plan", "groupingSplitPlan"),
        ("Baseline", "baseline"),
        ("Candidate", "candidate"),
        ("Overlay", "overlay"),
    ):
        value = assets.get(key)
        if value is None:
            continue
        images.append(
            "<figure>"
            f"<img src=\"{html.escape(str(value))}\" alt=\"{html.escape(label)}\">"
            f"<figcaption>{html.escape(label)}</figcaption>"
            "</figure>"
        )
    rows = [
        metric_row("Dimensions", f"{result['width']} × {result['height']}"),
        metric_row("Changed", f"{result['changedPercent']:.4f}%"),
        metric_row(
            "Introduced white",
            f"{result['introducedWhitePercent']:.4f}% page / "
            f"{result['introducedWhiteOfChangedPercent']:.4f}% changed",
        ),
        metric_row(
            "White components",
            f"{result['introducedWhiteComponents']} / "
            f"largest {result['largestIntroducedWhiteComponentPercent']:.4f}%",
        ),
        metric_row(
            "Texture-to-flat collapse",
            f"{result['flatnessCollapsePercent']:.4f}%",
        ),
    ]
    if result["totalMs"] is not None:
        rows.append(
            metric_row(
                "Device timing",
                f"analysis {result['analysisMs']} ms / "
                f"render {result['renderMs']} ms / total {result['totalMs']} ms",
            )
        )
    if result["outsideAllowedPercent"] is not None:
        rows.append(
            metric_row(
                "Outside allowed mask",
                f"{result['outsideAllowedPercent']:.4f}% page / "
                f"{result['outsideAllowedOfChangedPercent']:.4f}% changed",
            )
        )
    if result["glyphMaskPercent"] is not None:
        rows.append(
            metric_row(
                "Glyph mask",
                f"{result['glyphMaskPercent']:.4f}% page / "
                f"{result['changedInsideGlyphPercent']:.4f}% changed inside mask",
            )
        )
    if result["containerMaskPercent"] is not None:
        rows.append(
            metric_row(
                "Container mask",
                f"{result['containerMaskPercent']:.4f}% page / "
                f"{result['changedOutsideContainerPercent']:.4f}% changed outside",
            )
        )
        if result["glyphOutsideContainerPercent"] is not None:
            rows.append(
                metric_row(
                    "Glyph outside container",
                    f"{result['glyphOutsideContainerPercent']:.4f}% glyph mask",
                )
            )
    if result["containerDetections"] > 0:
        layout_suffix = ""
        if result["containerCandidateLayoutPercent"] is not None:
            layout_suffix = (
                f" / {result['containerCandidateLayoutPercent']:.2f}% of "
                f"{result['layoutCount']} rendered layouts"
            )
        rows.append(
            metric_row(
                "Container detections",
                f"{result['containerDetections']} observed / "
                f"{result['highConfidenceContainerDetections']} at ≥ "
                f"{HIGH_CONTAINER_CONFIDENCE:.2f}{layout_suffix}",
            )
        )
    if result["containerProbeOutcomes"]:
        rows.append(
            metric_row(
                "Container probe outcomes",
                " / ".join(
                    f"{name} {count}"
                    for name, count in sorted(result["containerProbeOutcomes"].items())
                ),
            )
        )
    if result["rectangularBorderProbeOutcomes"]:
        rows.append(
            metric_row(
                "Rectangular border probes",
                " / ".join(
                    f"{name} {count}"
                    for name, count in sorted(
                        result["rectangularBorderProbeOutcomes"].items()
                    )
                ),
            )
        )
        for index, probe in enumerate(result["rectangularBorderProbes"]):
            rows.append(
                metric_row(
                    f"Rectangular probe #{index + 1}",
                    f"{probe['outcome']} / left {probe['leftScore']:.4f} / "
                    f"right {probe['rightScore']:.4f} / "
                    f"top {probe['topScore']:.4f} / "
                    f"bottom {probe['bottomScore']:.4f} / "
                    f"corners {probe['topLeftCornerScore']:.4f},"
                    f"{probe['topRightCornerScore']:.4f},"
                    f"{probe['bottomLeftCornerScore']:.4f},"
                    f"{probe['bottomRightCornerScore']:.4f}",
                )
            )
    grouping_stages = result["groupingStages"]
    if grouping_stages["groupedBlocks"] > 0:
        rows.append(
            metric_row(
                "Horizontal grouping probes",
                f"{grouping_stages['groupedBlocks']} grouped blocks / "
                f"{grouping_stages['multiRegionHorizontalMergedBlocks']} "
                "multi-region merged blocks / "
                f"{len(grouping_stages['horizontalSeparatorProbes'])} boundaries / "
                f"{grouping_stages['strongSeparatorCandidates']} strong candidates / "
                f"{grouping_stages['safeSeparatorSplitPlans']}/"
                f"{len(grouping_stages['separatorSplitPlans'])} safe split plans / "
                f"+{grouping_stages['separatorSplitBlockDelta']} source blocks",
            )
        )
        for plan in grouping_stages["separatorSplitPlans"]:
            segment_rects = " | ".join(
                ",".join(str(value) for value in segment["rect"])
                for segment in plan["segments"]
            )
            rows.append(
                metric_row(
                    f"Recording split merged #{plan['mergedIndex']}",
                    f"{','.join(str(value) for value in plan['originalRect'])} → "
                    f"{segment_rects} / "
                    f"{'safe' if plan['safeForCandidateGrouping'] else 'blocked'} / "
                    f"text {plan['segmentTextLength']}/{plan['sourceTextLength']}",
                )
            )
    if result["containerCandidates"]:
        for candidate in result["containerCandidates"]:
            feature_parts = [
                f"confidence {candidate['confidence']:.4f}",
                f"page {candidate['percent']:.4f}%",
            ]
            if candidate["probeOutcome"]:
                feature_parts.append(f"probe {candidate['probeOutcome']}")
            if candidate["rawCoverage"] is not None:
                feature_parts.append(f"raw coverage {candidate['rawCoverage']:.4f}")
            if candidate["solidity"] is not None:
                feature_parts.append(f"solidity {candidate['solidity']:.4f}")
            if candidate["areaRatio"] is not None:
                feature_parts.append(f"probe area {candidate['areaRatio']:.4f}")
            if candidate["luminanceStd"] is not None:
                feature_parts.append(f"luma σ {candidate['luminanceStd']:.3f}")
            if "accepted" in candidate:
                feature_parts.append(
                    "review accepted" if candidate["accepted"] else "review rejected"
                )
            rows.append(
                metric_row(
                    f"Container #{candidate['label']}",
                    " / ".join(feature_parts),
                )
            )
        rows.append(
            metric_row(
                "Container confidence",
                f"{result['containerConfidenceMin']:.4f} min / "
                f"{result['containerConfidenceMean']:.4f} mean / "
                f"{result['containerConfidenceMax']:.4f} max",
            )
        )
    container_review = result.get("containerReview")
    if isinstance(container_review, dict):
        source_status_suffix = ""
        target_source_status = container_review.get("targetSourceStatus")
        if isinstance(target_source_status, list):
            status_counts: dict[str, int] = {}
            for value in target_source_status:
                if not isinstance(value, dict):
                    continue
                status = str(value.get("status", "unknown"))
                status_counts[status] = status_counts.get(status, 0) + 1
            source_status_suffix = (
                " / source " +
                ", ".join(
                    f"{status} {count}"
                    for status, count in sorted(status_counts.items())
                )
            )
        rows.append(
            metric_row(
                "Container review",
                f"expected {container_review['expectedContainers']} / "
                f"accepted {container_review['acceptedCandidates']} / "
                f"rejected {container_review['rejectedCandidates']} / "
                f"missed {container_review['missedContainers']}"
                f"{source_status_suffix}",
            )
        )
    if result["candidateVsBaselinePercent"] is not None:
        rows.append(
            metric_row(
                "Candidate vs baseline",
                f"{result['candidateVsBaselinePercent']:.4f}%",
            )
        )
    baseline_report_delta = result.get("baselineReportDelta")
    if isinstance(baseline_report_delta, dict):
        rows.append(
            metric_row(
                "Δ introduced white",
                format_delta(baseline_report_delta.get("introducedWhitePercent")),
            )
        )
        rows.append(
            metric_row(
                "Δ largest white component",
                format_delta(
                    baseline_report_delta.get(
                        "largestIntroducedWhiteComponentPercent"
                    )
                ),
            )
        )
        rows.append(
            metric_row(
                "Δ texture-to-flat collapse",
                format_delta(baseline_report_delta.get("flatnessCollapsePercent")),
            )
        )
    return (
        "<section class=\"page\">"
        f"<h2>{html.escape(str(result['id']))}</h2>"
        f"<p class=\"category\">{html.escape(str(result['category']))}</p>"
        f"<div class=\"images\">{''.join(images)}</div>"
        f"<table>{''.join(rows)}</table>"
        "</section>"
    )


def format_delta(value: Any) -> str:
    if value is None:
        return "n/a"
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return "n/a"
    return f"{float(value):+.4f} pp"


def format_percent(value: Any) -> str:
    if value is None:
        return "n/a"
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return "n/a"
    return f"{float(value):.2f}%"


def write_html(
    output_dir: Path,
    fixture_set_id: str,
    candidate_id: str,
    summary: dict[str, Any],
    results: list[dict[str, Any]],
) -> None:
    category_rows = "".join(
        "<tr>"
        f"<td>{html.escape(str(row['category']))}</td>"
        f"<td>{row['pages']}</td>"
        f"<td>{row['changedPercent']:.4f}%</td>"
        f"<td>{row['introducedWhitePercent']:.4f}%</td>"
        "</tr>"
        for row in summary["categories"]
    )
    baseline_delta = summary.get("baselineReportDelta")
    baseline_paragraph = ""
    if isinstance(baseline_delta, dict):
        baseline_paragraph = (
            "<p>Baseline deltas: introduced white "
            f"{html.escape(format_delta(baseline_delta.get('introducedWhitePercent')))}, "
            "texture-to-flat collapse "
            f"{html.escape(format_delta(baseline_delta.get('flatnessCollapsePercent')))}."
            "</p>"
        )
    container_paragraph = ""
    if summary["containerDetections"] > 0:
        layout_summary = ""
        if summary["containerCandidateLayoutPercent"] is not None:
            layout_summary = (
                f" · {summary['containerCandidateLayoutPercent']:.2f}% of "
                f"{summary['layoutCount']} rendered layouts"
            )
        container_paragraph = (
            f"<p>Container observations: {summary['containerDetections']} detected · "
            f"{summary['highConfidenceContainerDetections']} at ≥ "
            f"{HIGH_CONTAINER_CONFIDENCE:.2f} · mean confidence "
            f"{summary['containerConfidenceMean']:.4f}{layout_summary}.</p>"
        )
    probe_paragraph = ""
    if summary["containerProbeOutcomes"]:
        probe_paragraph = (
            "<p>Container probe outcomes: "
            + " · ".join(
                f"{html.escape(name)} {count}"
                for name, count in sorted(summary["containerProbeOutcomes"].items())
            )
            + ".</p>"
        )
    if summary["rectangularBorderProbeOutcomes"]:
        side_means = summary["rectangularBorderScoreMeanBySide"]
        probe_paragraph += (
            "<p>Rectangular border probes: "
            + " · ".join(
                f"{html.escape(name)} {count}"
                for name, count in sorted(
                    summary["rectangularBorderProbeOutcomes"].items()
                )
            )
            + f" · side-score mean "
            f"{summary['rectangularBorderSideScoreMean']:.4f} · minimum-score mean "
            f"{summary['rectangularBorderMinimumScoreMean']:.4f} · minimum "
            f"{summary['rectangularBorderMinimumScoreMin']:.4f} · "
            f"left/right/top/bottom means {side_means['left']:.4f}/"
            f"{side_means['right']:.4f}/{side_means['top']:.4f}/"
            f"{side_means['bottom']:.4f} · corner mean "
            f"{summary['rectangularBorderCornerScoreMean']:.4f} · "
            f"minimum-corner mean "
            f"{summary['rectangularBorderMinimumCornerScoreMean']:.4f}.</p>"
        )
    timing_paragraph = ""
    if summary["timedPages"] > 0:
        timing_paragraph = (
            f"<p>Device timing ({summary['timedPages']} pages): analysis mean "
            f"{summary['analysisMsMean']:.1f} ms · render mean "
            f"{summary['renderMsMean']:.1f} ms · total mean "
            f"{summary['totalMsMean']:.1f} ms · median "
            f"{summary['totalMsMedian']:.1f} ms · range "
            f"{summary['totalMsMin']}–{summary['totalMsMax']} ms · render "
            f"{summary['renderTimePercent']:.2f}% of measured time.</p>"
        )
    if summary["renderStagePages"] > 0:
        stage_means = summary["renderStageMsMean"]
        stage_percent = summary["renderStagePercent"]
        call_summary = (
            f", {summary['inpaintCallMean']:.1f} inpaint calls/page"
            if summary["inpaintCallMean"] is not None
            else ""
        )
        timing_paragraph += (
            f"<p>Backend render stages ({summary['renderStagePages']} pages, "
            f"{summary['drawableGroupMean']:.1f} drawable groups/page"
            f"{call_summary}): inpaint "
            f"{stage_means['inpaint']:.1f} ms ({stage_percent['inpaint']:.2f}%) · "
            f"layout {stage_means['layout']:.1f} ms "
            f"({stage_percent['layout']:.2f}%) · encode "
            f"{stage_means['encode']:.1f} ms "
            f"({stage_percent['encode']:.2f}%) · decode "
            f"{stage_means['decode']:.1f} ms "
            f"({stage_percent['decode']:.2f}%).</p>"
        )
    review_paragraph = ""
    container_review = summary.get("containerReview")
    if isinstance(container_review, dict):
        source_breakdown = ""
        if "eligibleTargets" in container_review:
            source_breakdown = (
                f" Source-grounded split: {container_review['eligibleTargets']} "
                f"eligible targets, {container_review['mergedSourceTargets']} merged "
                f"render sources, "
                f"{container_review['preservedMergedSourceTargets']} preserved merged "
                f"sources, {container_review['missingSourceTargets']} without a document "
                f"source; eligible-target recall "
                f"{format_percent(container_review['eligibleRecallPercent'])}."
            )
        review_paragraph = (
            f"<p>Manual container review ({container_review['reviewedPages']} pages): "
            f"{container_review['acceptedCandidates']} accepted / "
            f"{container_review['rejectedCandidates']} rejected / "
            f"{container_review['missedContainers']} missed · candidate precision "
            f"{format_percent(container_review['candidatePrecisionPercent'])} · recall "
            f"{format_percent(container_review['candidateRecallPercent'])} · ≥ "
            f"{HIGH_CONTAINER_CONFIDENCE:.2f} precision "
            f"{format_percent(container_review['highConfidencePrecisionPercent'])} · recall "
            f"{format_percent(container_review['highConfidenceRecallPercent'])}."
            f"{html.escape(source_breakdown)}</p>"
        )
    grouping_paragraph = ""
    if summary["groupedSourceBlocks"] > 0:
        grouping_paragraph = (
            f"<p>Horizontal grouping diagnostics: "
            f"{summary['groupedSourceBlocks']} grouped source blocks · "
            f"{summary['multiRegionHorizontalMergedBlocks']} multi-region merged "
            f"blocks · {summary['horizontalSeparatorProbes']} tested boundaries · "
            f"{summary['strongSeparatorCandidates']} strong separator candidates · "
            f"{summary['safeSeparatorSplitPlans']}/{summary['separatorSplitPlans']} "
            "provenance-safe candidate split plans producing "
            f"{summary['separatorSplitOutputBlocks']} blocks "
            f"(+{summary['separatorSplitBlockDelta']}). "
            "These are recording-only A/B plans, not production split decisions.</p>"
        )
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Comic visual regression — {html.escape(candidate_id)}</title>
  <style>
    :root {{ color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; }}
    body {{ margin: 0; background: #111318; color: #f3f4f6; }}
    main {{ max-width: 1500px; margin: 0 auto; padding: 28px; }}
    h1, h2 {{ margin: 0 0 8px; }}
    .lead, .category {{ color: #aeb4c0; }}
    .summary, .page {{ background: #1b1f27; border: 1px solid #303643;
      border-radius: 16px; padding: 20px; margin: 20px 0; }}
    .images {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 14px; align-items: start; }}
    figure {{ margin: 0; }}
    img {{ display: block; width: 100%; max-height: 760px; object-fit: contain;
      background: #090a0d; border-radius: 10px; }}
    figcaption {{ margin-top: 6px; color: #c9ced8; }}
    table {{ width: 100%; border-collapse: collapse; margin-top: 16px; }}
    th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid #303643; }}
    th {{ color: #b9c0cc; width: 260px; }}
    .legend span {{ display: inline-block; margin-right: 18px; }}
    .yellow {{ color: #ffbc00; }} .red {{ color: #ff5555; }} .purple {{ color: #c46cff; }}
  </style>
</head>
<body>
<main>
  <h1>Comic visual regression</h1>
  <p class="lead">{html.escape(fixture_set_id)} · {html.escape(candidate_id)}</p>
  <section class="summary">
    <h2>Summary</h2>
    <p>{summary['pages']} pages · changed {summary['changedPercent']:.4f}% ·
      introduced white {summary['introducedWhitePercent']:.4f}% ·
      texture-to-flat collapse {summary['flatnessCollapsePercent']:.4f}%</p>
    {container_paragraph}
    {probe_paragraph}
    {timing_paragraph}
    {grouping_paragraph}
    {review_paragraph}
    {baseline_paragraph}
    <p class="legend"><span class="yellow">■ changed</span>
      <span class="red">■ introduced white</span>
      <span class="purple">■ texture-to-flat collapse</span></p>
    <table>
      <tr><th>Category</th><th>Pages</th><th>Changed</th><th>Introduced white</th></tr>
      {category_rows}
    </table>
  </section>
  {''.join(page_section(result) for result in results)}
</main>
</body>
</html>
"""
    (output_dir / "report.html").write_text(document, encoding="utf-8")


def reset_output(path: Path) -> Path:
    output = path.expanduser().resolve()
    if output.exists():
        if not output.is_dir():
            raise ValueError(f"output exists and is not a directory: {output}")
        shutil.rmtree(output)
    output.mkdir(parents=True)
    return output


def main() -> int:
    args = parse_args()
    try:
        output_dir = reset_output(args.output)
        if args.manifest is not None:
            fixture_set_id, candidate_id, thresholds, pages = load_manifest(args.manifest)
        else:
            fixture_set_id, candidate_id, thresholds, pages = load_recording_dir(
                args.recording_dir,
                output_dir,
                require_string(args.fixture_set_id, "--fixture-set-id"),
                require_string(args.recording_category, "--recording-category"),
            )
        results: list[dict[str, Any]] = []
        for index, page in enumerate(pages):
            results.append(score_page(page, thresholds, output_dir, index))
        summary = aggregate(results)
        if args.container_review is not None:
            apply_container_review(
                args.container_review,
                fixture_set_id,
                results,
                summary,
            )
        if args.baseline_report is not None:
            baseline_pages, baseline_summary = load_baseline_report(
                args.baseline_report,
                fixture_set_id,
            )
            apply_baseline_comparison(
                results,
                summary,
                baseline_pages,
                baseline_summary,
            )
        report = {
            "schemaVersion": SCHEMA_VERSION,
            "fixtureSetId": fixture_set_id,
            "candidateId": candidate_id,
            "thresholds": {
                "pixelDelta": thresholds.pixel_delta,
                "nearWhite": thresholds.near_white,
                "sourceWhite": thresholds.source_white,
                "flatBlock": thresholds.flat_block,
                "textureStd": thresholds.texture_std,
                "flatStd": thresholds.flat_std,
                "minimumComponentPixels": thresholds.minimum_component_pixels,
            },
            "summary": summary,
            "pages": results,
        }
        (output_dir / "report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        write_html(output_dir, fixture_set_id, candidate_id, summary, results)
        print(
            json.dumps(
                {
                    "report": str(output_dir / "report.html"),
                    "json": str(output_dir / "report.json"),
                    "pages": summary["pages"],
                    "changedPercent": summary["changedPercent"],
                    "introducedWhitePercent": summary["introducedWhitePercent"],
                    "flatnessCollapsePercent": summary["flatnessCollapsePercent"],
                },
                ensure_ascii=False,
            )
        )
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"comic visual regression failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
