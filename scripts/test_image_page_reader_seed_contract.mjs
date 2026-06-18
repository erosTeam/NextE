#!/usr/bin/env node
/**
 * Contract for reusing a parsed /s/ image page when opening the Reader.
 *
 * The /s/ route resolver has already fetched the target image page and parsed the one-shot full-image
 * URL. Reader should reuse that exact target image after it has loaded the target preview slot,
 * but must not treat the single image as a loaded preview page set or block first paint on neighbors.
 *
 * Run: node scripts/test_image_page_reader_seed_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')
let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}
const eq = (name, got, expected) => {
  assert.deepStrictEqual(got, expected, name)
  passed++
}

function exactSeedImage(seedImages, seedLoadedPages, startIndex) {
  if (seedImages.length === 0 || seedLoadedPages > 0 || startIndex < 0) return null
  const seed = seedImages[0]
  if (seed.page !== startIndex + 1 || seed.imageUrl.length === 0) return null
  return { ...seed }
}

function applyExactSeed(images, index, seed) {
  if (index < 0 || index >= images.length) return images
  const merged = { ...images[index] }
  for (const key of ['imgkey', 'sUrl', 'imageUrl', 'originImageUrl', 'showKey', 'reloadKey']) {
    if (seed[key].length > 0) merged[key] = seed[key]
  }
  return images.map((img, i) => (i === index ? merged : img))
}

{
  const seed = {
    page: 37,
    imgkey: 'targetkey',
    sUrl: 'https://e-hentai.org/s/targetkey/3989982-37',
    imageUrl: 'https://ehgt.org/full/target.jpg',
    originImageUrl: 'https://e-hentai.org/fullimg.php?gid=3989982&page=37',
    showKey: 'show-target',
    reloadKey: 'nl-target',
  }
  const exact = exactSeedImage([seed], 0, 36)
  ok('single /s/ seed is accepted for its absolute start index', exact !== null)
  const loaded = [
    { page: 36, imgkey: 'old36', sUrl: 's36', imageUrl: '', originImageUrl: '', showKey: '', reloadKey: '', thumbUrl: 't36' },
    { page: 37, imgkey: 'old37', sUrl: 's37', imageUrl: '', originImageUrl: '', showKey: '', reloadKey: '', thumbUrl: 't37' },
  ]
  const out = applyExactSeed(loaded, 1, exact)
  eq('exact seed overlays only the target item', out.map((i) => i.page), [36, 37])
  eq('target keeps preview metadata while gaining the parsed full URL', out[1].thumbUrl, 't37')
  eq('target full image URL comes from parsed /s/ page', out[1].imageUrl, 'https://ehgt.org/full/target.jpg')
  eq('neighbor page is untouched', out[0].imgkey, 'old36')
}

ok('single /s/ seed is rejected when it is marked as contiguous previews', exactSeedImage([{ page: 37, imageUrl: 'x' }], 2, 36) === null)
ok('single /s/ seed is rejected when it does not match start index', exactSeedImage([{ page: 38, imageUrl: 'x' }], 0, 36) === null)
ok('single /s/ seed without parsed imageUrl is rejected', exactSeedImage([{ page: 37, imageUrl: '' }], 0, 36) === null)

const vmSrc = read('feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets')
const applyExactBody = vmSrc.match(/private applyExactSeed[\s\S]*?\n  }\n\n  \/\*\*/)?.[0] ?? ''
ok('VM derives exact seed before contiguous seed handling', /const exactSeed: EhGalleryImage \| null = this\.exactSeedImage\(seedImages, seedLoadedPages, startIndex\)[\s\S]*this\.applySeed/.test(vmSrc))
ok('VM applies exact seed after target-first ensureLoaded has loaded the target slot', /await this\.ensureLoaded\(startIndex\)[\s\S]*this\.applyExactSeed\(startIndex, exactSeed\)/.test(vmSrc))
ok('VM does not wait for target+2 before overlaying exact /s/ seed', !/await this\.ensureLoaded\(startIndex \+ 2\)[\s\S]*this\.applyExactSeed\(startIndex, exactSeed\)/.test(vmSrc))
ok('VM warms neighbor preview pages after the live index is settled', /private warmPreviewAhead\(index: number\): void[\s\S]*const target: number = index \+ PRECACHE_AHEAD[\s\S]*this\.ensureLoaded\(target\)/.test(vmSrc))
ok('VM rejects exact seed when seedLoadedPages indicates contiguous preview seed', /seedLoadedPages > 0/.test(vmSrc))
ok('VM exact seed function body was found', applyExactBody.length > 0)
ok('VM exact seed does not mutate previewPage/perPage/exhausted', !/this\.previewPage/.test(applyExactBody) && !/this\.perPage/.test(applyExactBody) && !/this\.exhausted/.test(applyExactBody))
ok('VM merges exact seed into a copy of the loaded target image', /const merged: EhGalleryImage = this\.images\[index\]\.copy\(\)/.test(vmSrc))

const readerImagePageSrc = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
ok('Reader image page keeps fast path for pre-resolved imageUrl', /this\.image\.imageUrl\.length > 0[\s\S]*\? this\.image\.imageUrl[\s\S]*await this\.downloadImage\(remoteUrl, serial\)/.test(readerImagePageSrc))

console.log(`✓ image-page reader seed contract: ${passed} assertions passed`)
