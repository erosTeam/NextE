# Manga Translation Evaluation Set

- **status**: validated Phase 0 baseline
- **created**: 2026-07-20
- **fixture id**: `nexte-original-manga-eval-v1`

## Purpose And Ownership

This is a small original fixture for proving the evaluation pipeline before any real gallery image is uploaded.
Both pages were generated specifically for NextE from prompts that requested fictional characters and prohibited
existing franchises, third-party pages, logos and watermarks. Lossless source PNGs and test references live under
`entry/src/ohosTest/resources/rawfile/`. Production bundles reviewed JPEG derivatives and a separate manifest only for
the explicit provider-evaluation action; opening the page never uploads them.

The set is intentionally not a benchmark claim. It establishes a reproducible minimum for:

- vertical dialogue and Japanese reading order;
- furigana and a locked name mapping from `優` to `优`;
- small caption, station signage and handwritten date text;
- integrated sound effects and rain/background texture;
- two-page name consistency with explicit previous-page context.

## Files

| File | SHA-256 | Coverage |
|---|---|---|
| `comic_translation_eval_page_01.png` | `b12a64700e64a9e707152d0570a8af8c5296055226f953c769307cb59e3176a9` | Rainy station, caption, signage, SFX, vertical dialogue, furigana |
| `comic_translation_eval_page_02.png` | `72ee2ef048ec6035f0ade14f7a07c9f50302f377907076fa677b95977c0c246c` | Same characters, name reuse, vertical dialogue, handwriting, SFX |
| `comic_translation_eval_manifest.json` | verified during test compilation/run | Expected source variants, order and required translation terms |
| `comic_translation_live_eval_page_01.jpg` | `eede03d3c797c9278bc9b8f316998fdbb712c1ff9e5b9da0ac1972173bfe7388` | Production live-run derivative of page 1 |
| `comic_translation_live_eval_page_02.jpg` | `4223bca41e70b722708c480d4d1fd4dec2d5a6f6a42b77c084346050f7374751` | Production live-run derivative of page 2 |
| `comic_translation_live_eval_manifest.json` | verified before every live run | Production image identity and the same reference rules |

All images are 1024 × 1536. The two production JPEGs total about 1.6 MB. Each manifest is the reference truth; artwork
or derivatives must not be silently edited without updating hashes and re-reviewing every visible text block.
The 2026-07-21 live review corrected one reference omission: the clearly visible `月影駅 東口` sign on page 2 is now
an expected block in both manifests. The reference therefore contains 5 blocks on page 1 and 6 on page 2.

## Evaluation Rules

`ComicTranslationEvaluator.accuracy` compares the provider-neutral page document with the reference identity and:

- matches source blocks after whitespace normalization, allowing only the listed furigana/punctuation variants;
- reports missing and unexpected source blocks separately;
- reports matched blocks that arrive in the wrong reading order;
- checks required translation terms without pretending that one exact full-sentence translation is mandatory.

Structural parsing, transcript matching and translation quality remain separate results. A perfect fixture score does
not establish production quality, and a provider-reported confidence value never overrides a reference mismatch.

## Live-Run Boundary

A live run uploads these two synthetic pages and consumes the selected provider's quota. It must therefore be explicit,
record provider/model, image hashes, elapsed time, request outcome and returned structural/accuracy counts, and avoid
logging OAuth credentials or full provider responses. Real gallery pages remain out of scope until the user separately
authorizes their upload and the provider path passes this fixture boundary.

The live trigger cannot be implemented as a normal `entry@ohosTest` case that silently reuses production credentials.
Device evidence on 2026-07-20 showed that the test module receives an empty provider Preferences view even after it
starts the main `EntryAbility`; both bundle modules were installed, but `ComicPageAnalyzerFactory` still resolved the
default API path with no API key. This is a useful isolation boundary, not a reason to copy OAuth tokens between stores.

The production trigger now lives as one row at the end of the selected provider card. It remains disabled until the
provider and model are configured, then shows a native confirmation that states two bundled original samples will be
uploaded and quota will be consumed. Only the confirmation action starts a request; automatic page entry, model lookup
and quota refresh cannot start it.

The run processes page 1 first, passes its source/translation/summary plus the locked `優 -> 优` term into page 2,
verifies both JPEG hashes, and deletes each temporary cache file. Diagnostics contain only provider/model, bytes,
latency and aggregate structural/accuracy counts; credentials and complete responses are excluded.

## 2026-07-21 Codex Live Result

- Device selector `237` resolved live to `192.168.50.237:12345`; provider `codex-oauth-experimental`, model
  `gpt-5.6-luna`.
- The first request exposed `HTTP 400 unsupported_max_output_tokens`; the Codex request body was separated from the
  public Responses body and aligned with the current Codex field set. A later valid response exposed an invalid
  polygon even though this analyzer declares `geometry=false`; the text-only prompt now requires `polygon=[]`.
- Two subsequent runs returned valid documents for both pages. After the reference omission was corrected, the final
  run matched 10 of 11 blocks in 53,638 ms after uploading 1,649,657 bytes. Page 2 matched all 6 reviewed blocks;
  page 1 matched 4 of 5 and retained one SFX exact-transcript mismatch. Reading-order and required-name errors were 0.
- The result intentionally remains review-required instead of broadening punctuation/furigana variants into fuzzy
  matching. This proves failure visibility and stable document production, not general OCR accuracy.
- The settings page showed 7D remaining quota at 95% before the first real request and 94% after the live diagnostic
  series; no 5H window was returned, so none was displayed. Rounded quota UI is not a per-call cost measurement.
