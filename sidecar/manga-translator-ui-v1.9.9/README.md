# NextE manga-translator-ui sidecar compatibility patch

This directory does not contain the upstream application or model weights. It contains a narrow patch for
`manga-translator-ui v1.9.9` commit `696dc63bd0b4803f96cc3d4f844322cef4910f8e`.

The upstream `/translate/import/json` route returns HTTP 200 but ignores its `load_text` workflow parameters because
`prepare_translator_params()` returns them without applying them to the shared translator. The request consequently
runs detection, OCR, and the configured translator again instead of loading the submitted `translation` fields.

The patch applies workflow parameters for the duration of the serialized translator call and exposes the repaired
behavior at `/translate/import/json/nexte-load-text-v1`. The v2 compatibility route additionally converts JSON-restored
polygon coordinates to OpenCV's required integer type before rebuilding a mask after client-side region filtering, and
propagates swallowed load-text failures. NextE requires `/translate/import/json/nexte-load-text-v2` in OpenAPI capability
checks, so an older or unpatched service fails before a manga page is uploaded instead of producing a false-success image.

Run `scripts/build_manga_translator_ui_sidecar.sh` to clone or copy the pinned upstream revision, apply this patch, and
build the independent `nexte/manga-translator-ui:v1.9.9-nexte2` image. The builder derives from the pinned
`nexte/manga-translator-ui:v1.9.9` base image when it exists, or builds that base from the upstream Dockerfile first.
The sidecar remains a separate GPL-3.0 program; it is not linked into or packaged with the NextE HAP. Review the
upstream license before redistribution.
