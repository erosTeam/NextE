#!/usr/bin/env bash
set -euo pipefail

readonly container_name="${1:-nexte-manga-translator}"

if [[ "$(docker inspect --format '{{.State.Running}}' "${container_name}" 2>/dev/null || true)" != "true" ]]; then
  echo "Container is not running: ${container_name}" >&2
  exit 1
fi

docker exec "${container_name}" python -c '
import asyncio
from pathlib import Path

from manga_translator.config import Detector, Inpainter, Ocr
from manga_translator.detection import get_detector
from manga_translator.detection.yolo_obb import YOLOOBBDetector
from manga_translator.inpainting import get_inpainter
from manga_translator.ocr import get_ocr


async def prepare_models():
    await get_detector(Detector.default).download()
    await YOLOOBBDetector().download()
    await get_ocr(Ocr.ocr48px).download()
    await get_ocr(Ocr.mocr).download()
    await get_inpainter(Inpainter.lama_large).download()
    await get_inpainter(Inpainter.default).download()


asyncio.run(prepare_models())

required = [
    Path("/app/models/detection/detect-20241225.ckpt"),
    Path("/app/models/detection/ysgyolo_1.2_OS1.0.onnx"),
    Path("/app/models/ocr/ocr_ar_48px.ckpt"),
    Path("/app/models/ocr/alphabet-all-v7.txt"),
    Path("/app/models/ocr/manga_ocr/pytorch_model.bin"),
    Path("/app/models/inpainting/lamalarge.onnx"),
    Path("/app/models/inpainting/inpainting.ckpt"),
]
missing = [str(path) for path in required if not path.is_file()]
if missing:
    raise SystemExit("Missing prepared model files: " + ", ".join(missing))

total_bytes = sum(path.stat().st_size for path in required)
print(f"NextE sidecar models ready: {len(required)} required files, {total_bytes} bytes")
'
