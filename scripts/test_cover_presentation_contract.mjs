#!/usr/bin/env node
/**
 * Contract for gallery cover PRESENTATION (EhThumbnail + its callers).
 *
 * User-flagged regression: loaded gallery header covers were rendered as a real image strip inside a
 * taller grey container. The grey frame was a layout slot/backdrop accidentally made visible. The product
 * rule is NOT "crop/fill the cover"; it is: keep the real EH cover proportion and apply rounded clipping
 * to the visible image itself. Layout slots may reserve space, but must be transparent after a real image
 * is loaded.
 *
 * Run: node scripts/test_cover_presentation_contract.mjs   (exit 1 on any failure)
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    failures++
    console.error(`✗ ${msg}`)
  }
}

const thumb = read('shared/src/main/ets/components/EhThumbnail.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const internalRoutes = read('shared/src/main/ets/constants/InternalQaRoutes.ets')
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
const entryIndex = read('entry/src/main/ets/pages/Index.ets')
const moduleJson = read('entry/src/main/module.json5')
const probePage = read('entry/src/main/ets/pages/CoverFallbackProbePage.ets')
const parser = read('shared/src/main/ets/parser/EhGalleryDetailParser.ets')
const headerCard = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')
const gridCard = read('shared/src/main/ets/components/GalleryGridCard.ets')

// 1) The detail parser must preserve EH cover dimensions from #gd1 style. Without them the header can
// only contain an unknown-aspect image inside a fixed box, which was the source of the grey slab.
ok(/RE_COVER_STYLE/.test(parser), 'detail parser reads the cover style block, not only the URL')
ok(/RE_STYLE_W/.test(parser) && /RE_STYLE_H/.test(parser), 'detail parser extracts cover width/height from style')
ok(/g\.imgWidth\s*=\s*Number\.parseInt\(wM\[1\],\s*10\)/.test(parser), 'detail parser stores cover width on EhGallery.imgWidth')
ok(/g\.imgHeight\s*=\s*Number\.parseInt\(hM\[1\],\s*10\)/.test(parser), 'detail parser stores cover height on EhGallery.imgHeight')

// 2) EhThumbnail has a source-size path for containFit covers: the outer slot is only layout, and the
// visible Image gets width/height from the real source aspect.
ok(/@Param\s+sourceWidth:\s*number\s*=\s*0/.test(thumb), 'EhThumbnail accepts sourceWidth')
ok(/@Param\s+sourceHeight:\s*number\s*=\s*0/.test(thumb), 'EhThumbnail accepts sourceHeight')
ok(/hasSourceSize\(\)/.test(thumb), 'EhThumbnail gates real-aspect sizing on known source dimensions')
ok(/fittedWidth\(\)/.test(thumb) && /fittedHeight\(\)/.test(thumb), 'EhThumbnail computes visible image size from source aspect')
ok(/this\.containFit\s*&&\s*this\.hasSourceSize\(\)/.test(thumb), 'containFit + known source dimensions uses the transparent-slot real-image branch')
ok(/Image\(EhConstants\.cdnThumb\(this\.url\)\)[\s\S]*?\.width\(this\.fittedWidth\(\)\)[\s\S]*?\.height\(this\.fittedHeight\(\)\)[\s\S]*?\.objectFit\(ImageFit\.Fill\)[\s\S]*?\.borderRadius\(this\.radius\)[\s\S]*?\.clip\(true\)/.test(thumb), 'visible loaded image is sized to real aspect and clipped to its own radius')
ok(/Stack\(\{ alignContent: Alignment\.Center \}\)[\s\S]*?\.width\(this\.thumbWidth\)[\s\S]*?\.height\(this\.thumbHeight\)[\s\S]*?\.overlay\(this\.coverOverlay\(\)/.test(thumb), 'fixed header slot is a transparent alignment slot with loading/error overlay')

// 3) Loading and error fallbacks must be explicit placeholder states, not an accidental empty loaded slot.
ok(/@Local\s+loaded:\s*boolean\s*=\s*false/.test(thumb), 'EhThumbnail tracks the loading/loaded state')
ok(/@Local\s+failed:\s*boolean\s*=\s*false/.test(thumb), 'EhThumbnail tracks the image error state separately')
ok(/onUrlChange\(\)[\s\S]*?this\.loaded\s*=\s*false[\s\S]*?this\.failed\s*=\s*false/.test(thumb), 'recycled rows reset both loaded and failed state when URL changes')
ok(/if\s*\(!this\.loaded\s*&&\s*!this\.failed\)/.test(thumb), 'spinner is shown only while loading, not after an error')
ok(/errorOverlay\(\)[\s\S]*?if\s*\(this\.failed\)[\s\S]*?SymbolGlyph\(\$r\('sys\.symbol\.picture'\)\)[\s\S]*?ThemeConstants\.TEXT_TERTIARY/.test(thumb), 'error fallback shows an explicit tertiary image marker')
ok((thumb.match(/this\.failed\s*=\s*true/g) || []).length >= 4, 'every Image onError path marks the thumbnail failed')
ok((thumb.match(/this\.failed\s*=\s*false/g) || []).length >= 5, 'onUrlChange and every onComplete path clears failed state')
ok((thumb.match(/\.overlay\(this\.coverOverlay\(\),\s*\{ align:\s*Alignment\.Center \}\)/g) || []).length >= 4, 'every thumbnail branch uses the combined loading/error overlay')
ok(!/\.overlay\(this\.loaderOverlay\(\)/.test(thumb), 'no branch bypasses the error marker by using the loader overlay directly')
ok(/THUMBNAIL_VISUAL_LOADING/.test(thumb) && /THUMBNAIL_VISUAL_ERROR/.test(thumb), 'EhThumbnail exposes deterministic visual states for device evidence')
ok(/@Param\s+visualState:\s*number\s*=\s*THUMBNAIL_VISUAL_AUTO/.test(thumb), 'EhThumbnail visualState defaults to AUTO production behavior')
ok(/visualState\s*!==\s*THUMBNAIL_VISUAL_AUTO[\s\S]*?ThemeConstants\.COVER_PLACEHOLDER[\s\S]*?\.overlay\(this\.coverOverlay\(\)/.test(thumb), 'forced visual states still use the real cover placeholder and overlay path')

// 4) Header cover must pass the parsed dimensions so a wide/flat cover does not become a grey tall box.
ok(/sourceWidth:\s*this\.gallery\.imgWidth/.test(headerCard), 'GalleryHeaderCard passes gallery.imgWidth into EhThumbnail')
ok(/sourceHeight:\s*this\.gallery\.imgHeight/.test(headerCard), 'GalleryHeaderCard passes gallery.imgHeight into EhThumbnail')
ok(/containFit:\s*true/.test(headerCard), 'GalleryHeaderCard still fits the whole cover, no crop/fill policy')

// 5) This fix must not invent a blanket fill/crop policy for grid cards. Existing grid cover remains its
// own context; the header fix is about real-aspect fitting inside a transparent slot.
ok(!/sourceWidth/.test(gridCard) && !/sourceHeight/.test(gridCard), 'GalleryGridCard is not forced into the detail-header source-slot path')
ok(!/ImageFit\.Cover[\s\S]*header/i.test(headerCard), 'GalleryHeaderCard does not introduce a header Cover/crop policy')

// 6) Device visual evidence route: hidden QA path renders the real component states without exposing a
// public deep-link skill or altering ordinary navigation.
ok(/COVER_FALLBACK_PROBE_URI:\s*string\s*=\s*'nexte:\/\/qa\/cover-fallback'/.test(internalRoutes), 'internal QA route has a stable cover-fallback URI')
ok(/InternalQaRoutes/.test(sharedIndex), 'shared barrel exports the internal QA route constant')
ok(/THUMBNAIL_VISUAL_LOADING/.test(sharedIndex) && /THUMBNAIL_VISUAL_ERROR/.test(sharedIndex), 'shared barrel exports thumbnail visual-state constants')
ok(/uri\s*===\s*InternalQaRoutes\.COVER_FALLBACK_PROBE_URI[\s\S]*?publishPendingEhUrl/.test(entryAbility), 'EntryAbility accepts the explicit internal QA URI')
ok(/InternalQaRoutes\.COVER_FALLBACK_PROBE_URI[\s\S]*?pushPathByName\('CoverFallbackProbe'/.test(entryIndex), 'Index routes the internal QA URI to the probe page')
ok(/name\s*===\s*'CoverFallbackProbe'[\s\S]*?CoverFallbackProbePage\(\)/.test(entryIndex), 'CoverFallbackProbe is a registered nav destination')
ok(/EhThumbnail\(\{[\s\S]*?visualState:\s*state/.test(probePage), 'probe page renders the real EhThumbnail visualState path')
ok(/THUMBNAIL_VISUAL_LOADING/.test(probePage) && /THUMBNAIL_VISUAL_ERROR/.test(probePage), 'probe page renders both loading and error states')
ok(/HdsNavDestination\(\)/.test(probePage), 'probe page wraps its content in HdsNavDestination like other pushed pages')
ok(!/nexte:\/\/qa\/cover-fallback/.test(moduleJson), 'internal QA URI is not exposed as a public module skill')

if (failures === 0) {
  console.log('✓ cover presentation contract: loaded header cover uses real-aspect visible image; loading/error fallbacks and QA probe use the distinct cover placeholder')
  process.exit(0)
}
console.error(`✗ cover presentation contract: ${failures} failure(s)`)
process.exit(1)
