# Manga Translation Product Reset

- **status**: completed product-definition and source audit; implementation authority moved to the visual Reader plan
- **created**: 2026-07-21
- **source**: original thread review after the Reader text sheet exposed a product-definition mismatch
- **design authority**: [Manga Translation Design](../../manga-translation-design.md)

## Why This Reset Exists

The original conversation began with a full comic-page flow: image analysis, translation, and a translated result shown
in Reader. The first response explicitly proposed a translation overlay. When OCR complexity and quality were questioned,
the assistant unilaterally changed the first product milestone to a source/translation text panel. The user did not
explicitly approve replacing the comic-page result with a panel. Later research, documentation and implementation followed
that changed scope.

The previous plan therefore executed consistently but encoded the wrong product definition. This reset invalidates the
claim that the Reader text sheet is a completed manga-translation V1. It does not erase historical build/test evidence;
it reclassifies what that evidence proves.

## Product Contract

The current NextE product target is lightweight Reader translation assistance. “Lightweight” means low interaction cost,
safe fallback to the original page, bounded latency/cost, and automatic rendered-cache reuse. It does not mean a text
panel. The user keeps reading a comic page in Reader while translated text appears in the corresponding source regions
and the source text no longer competes with the translation. The primary result is a visual page, not a list of strings.

AI-assisted production of a finished translated comic is a later, separate product workflow. It shares the page
document, glossary, revisions, source treatment, layout and renderer, then adds region editing, manual QA, fine
typesetting, batch processing and export. Reader V1 must not absorb those production requirements, and the production
branch must not weaken Reader V1 into transcript-only output.

The analyzer/provider implementation is replaceable. A valid end-to-end page may combine whole-page vision, detection,
OCR, a text translator, background repair, and a renderer in any supported deployment shape. This freedom cannot change
the product result.

A structured page document remains the durable handoff between stages. A document without renderable geometry is an
analysis checkpoint. A text review surface is a secondary diagnostic/editor. Neither is a completed manga translation.

The shared path and explicit split are:

```text
analysis -> contextual translation -> source treatment -> layout -> renderable page -> visual draft
                                                                          |-> Reader assistance
                                                                          `-> production edit / QA / export
```

## Evidence Reclassification

| Existing area | Current evidence | Reset classification |
|---|---|---|
| API and experimental Codex OAuth transports, model catalog, quota cache | Auth, request and response plumbing are built and bounded | Keep as provider infrastructure candidate |
| `ComicPageDocument`, parser and persistent repository | Page identity, source/translation blocks, optional polygon and revisions survive cache/restart | Rework: renderable geometry and rendered-page identity must become explicit |
| Orchestrator, context budget, rolling summary, exact memory and consistency review | Request identity, dedupe, page ownership and bounded text context are tested | Keep as translation-stage candidates; none prove a visual page |
| `ComicResponsesPageAnalyzer` prompt v3 | Real provider returned bounded transcript/translation documents | Analysis-only: it declares `geometry=false`, `mask=false` and forces empty polygons |
| Reader `ComicTranslationSheet` and `翻译当前页` action | Real page produced a text list with cache/review state | Replace: this is the wrong primary product surface |
| 178/178 device tests and prior screenshots | Infrastructure behavior, cache, review filtering and page fences were exercised | Not product acceptance; no rendered translated comic page was proven |
| Completed manga-translation plans and roadmap wording | Accurately record work performed under the old scope | Historical evidence only; must not be used to claim manga translation V1 completion |

The audited implementation range is `9bf17dc5..c81247fd`. The central old V1 plan has been moved from `completed/` to
`archive/` and marked superseded. The remaining `completed/manga-translation-*` files prove their named technical slices
only under the plan-lifecycle rules; none defines the current product shape or authorizes restoring the text sheet.

## Source-Level Disposition

| Source boundary | Disposition | Reason / required change |
|---|---|---|
| Provider settings, API/Codex authentication, model catalogs and usage cache | Retain | Independent transport and credential plumbing; it does not decide the Reader result |
| `ComicResponsesPageAnalyzer` and `ComicResponsesProtocol` | Retain as analysis-only, then supplement | Current capability contract explicitly returns no geometry/mask; it may provide transcript, translation and context but cannot publish a page |
| `ComicTranslationOrchestrator`, context, exact memory, consistency and review services | Retain behind a narrower analysis/translation boundary | Request identity, dedupe and gallery context are useful; its current `ComicTranslationRunResult` ends too early at `ComicPageDocument` |
| `ComicPageDocument` and generated-document repository | Rework without discarding stored analysis | Optional polygons and placeholder render state are insufficient; region provenance, source-treatment/layout revisions and rendered-artifact identity need explicit ownership |
| `ComicTranslationRuntimeService` | Split | Keep file validation, hashing, explicit-action and provider selection; add region, layout, render and rendered-cache stages before returning a Reader-ready result |
| Reader route/page/file/UI epoch fences | Retain | They correctly prevent late results from appearing on another page |
| Reader `ComicTranslationSheet`, block rows and sheet-specific resources | Remove as the primary result | Loading/failure may remain page status; source/translation rows move only to an optional secondary review tool |
| Existing provider/parser/repository/orchestrator tests | Retain as supporting tests | They prove infrastructure only; new render identity, invalidation and visual Reader acceptance are required |
| Existing device screenshots and block-list checks | Retire as product evidence | They contain no translated visual comic page |

No source is retained merely because it was expensive to build. A retained component must sit entirely before the
corrected visual-result boundary or provide a safety/identity property that remains valid after the replacement.

## Required Architecture Before Feature Work

The corrected flow is:

```text
Reader local page
  -> staged route: renderable regions -> contextual translation -> source treatment / layout
  -> or whole-page render route: translated image output
  -> rendered-page cache
  -> Reader visual translated page
  -> optional secondary review/editor
```

Before implementation, the design must name ownership and identity for the region result, mask/repair result, text layout,
render profile, rendered artifact and failure fallback. A provider that only returns transcript/translation can participate
in analysis but cannot be the entire V1 path.

A provider that directly returns a validated translated image is different: it can implement a complete whole-page
render route without block geometry, provided it preserves the original artwork, records full artifact/provider identity,
and passes the same rendered-page cache and Reader acceptance. The current Responses/Codex analyzer returns text only and
does not yet implement that capability.

For the Reader branch, the first renderer target is a **non-destructive cached derivative page**: the original cached
gallery image is never overwritten; a renderer combines source-treatment patches and translated text into a separate
local artifact that Reader can display through its existing image/zoom/navigation path. This keeps Reader integration
small and makes a cache hit independent of provider availability. Production mode may later retain editable layers and
export durable final images, but those ownership and export rules are outside Reader V1.

The first complete route uses a versioned `manga-translator-ui`-compatible sidecar profile. The sidecar performs
detection/OCR and later source treatment/rendering through its documented export/import workflow. NextE sends the
normalized blocks, the page image and gallery context to the selected API or Codex translation provider, validates
block-id-complete translations, then supplies them to the sidecar renderer. This is protocol interoperation only; no
GPL implementation or model weight is incorporated into the app. Sidecar URL/auth, translation-provider credentials
and Codex credentials remain separate settings and storage domains.

This route is selected because it closes the visual product loop with an existing staged workflow instead of inventing
an unproven mobile detector/inpainter. It is an initial externally assisted route, not a permanent requirement: an
on-device region/render implementation or another compatible backend can replace it behind the same interfaces.

The implementation sequence is fixed:

1. define region, source-treatment, layout, render-profile and rendered-artifact identities plus invalidation rules;
2. prove a deterministic renderer on the legal fixture with reviewed regions and translations, without provider work;
3. implement the sidecar export adapter, normalize its regions, and keep its backend-specific render template only as
   bounded regenerable adapter data;
4. split contextual text translation from whole-page analysis so the selected API/Codex provider returns translations
   keyed to the normalized blocks, optionally using the page image for visual context;
5. send the reviewed translations through the sidecar import/render adapter and validate the returned image identity,
   dimensions, MIME and size before caching it;
6. retain the current whole-page vision route as a transcript/translation cross-check candidate, not as the geometry
   source or visual fallback;
7. compose all stages without letting an analysis-only result reach Reader;
8. replace the Reader sheet publication with the derivative visual page, then validate cache, failure fallback and
   page/route fences;
9. keep transcript/translation inspection only as an optional secondary review path.

Steps 1–7 are infrastructure evidence, not V1 completion. V1 closes only after step 8 passes the visual acceptance below.

## First Accepted Slice: Lightweight Reader Translation

The first slice is one fixed, legally usable manga page translated to Chinese inside the real Reader. It must preserve
Reader zoom/pan/page navigation, place translated text in the corresponding source regions, prevent source text from
competing with the translation, retain the original page on failure, and reopen from a rendered-page cache without a
model call.

Acceptance requires same-page original/translated screenshots plus real Reader interaction evidence on the user-selected
device. Parser tests, document dumps, source/translation lists, builds and provider responses are supporting evidence only.

## Closure

The product contract, mature sidecar route, source disposition, first accepted slice and legacy-plan authority cleanup
are complete. Implementation continues under the active
[Visual Reader V1 Plan](../active/manga-translation-reader-visual-v1.md). No later plan may silently change the visual
page result to a text panel when a technical stage is difficult.
