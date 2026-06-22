#!/usr/bin/env node
/**
 * Contract test for the reader's N-ahead image precache (eros_fe forward preload), per-process reader
 * session seed cache, and the resolve service's in-flight/result dedup.
 *
 * `precacheIndices` mirrors ReaderViewModel.precacheAhead's range: pre-resolve [currentIndex+1 ..
 * min(currentIndex+PRECACHE_AHEAD, length-1)], skipping pages already resolved / not yet loaded.
 * Structural greps lock the VM trigger sites and the ImageResolveService coalescing.
 *
 * Run: node scripts/test_reader_precache_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

const PRECACHE_AHEAD = 2
// images: array of { imageUrl, sUrl } (mirror of EhGalleryImage's precache-relevant fields).
function precacheIndices(currentIndex, images) {
  const to = Math.min(currentIndex + PRECACHE_AHEAD, images.length - 1)
  const out = []
  for (let i = currentIndex + 1; i <= to; i++) {
    const img = images[i]
    if (img.imageUrl.length === 0 && img.sUrl.length > 0) out.push(i)
  }
  return out
}
const mk = (n, resolved = []) =>
  Array.from({ length: n }, (_, i) => ({ imageUrl: resolved.includes(i) ? 'http://x' : '', sUrl: `s${i}` }))

let failures = 0
const eqArr = (got, want, label) => {
  if (JSON.stringify(got) !== JSON.stringify(want)) { console.error(`✗ ${label}\n    got:  ${JSON.stringify(got)}\n    want: ${JSON.stringify(want)}`); failures++ }
}
const ok = (c, label) => { if (!c) { console.error(`✗ ${label}`); failures++ } }

// Mid-list: precache the next 2.
eqArr(precacheIndices(5, mk(100)), [6, 7], 'mid-list → next 2 pages')
// Near the end: clamp to the last index (no out-of-range).
eqArr(precacheIndices(98, mk(100)), [99], 'second-to-last → only the last page')
eqArr(precacheIndices(99, mk(100)), [], 'last page → nothing to precache')
// Already-resolved upcoming pages are skipped (no redundant resolve).
eqArr(precacheIndices(5, mk(100, [6])), [7], 'skips an already-resolved next page')
eqArr(precacheIndices(5, mk(100, [6, 7])), [], 'skips when both ahead already resolved')
// Page with no /s/ url (not yet loaded) is skipped.
{
  const imgs = mk(100)
  imgs[6].sUrl = ''
  eqArr(precacheIndices(5, imgs), [7], 'skips a page without an /s/ url (not loaded)')
}
// Start of gallery.
eqArr(precacheIndices(0, mk(10)), [1, 2], 'page 0 → precache 1,2')

// Structural wiring
const VM = readFileSync(join(ROOT, 'feature/reader/src/main/ets/viewmodel/ReaderViewModel.ets'), 'utf8')
const SVC = readFileSync(join(ROOT, 'shared/src/main/ets/services/ImageResolveService.ets'), 'utf8')
ok(VM.includes('const PRECACHE_AHEAD: number = 2'), 'VM: PRECACHE_AHEAD = 2')
ok(VM.includes('private precacheAhead('), 'VM: precacheAhead method')
ok(VM.includes('private precacheFrom('), 'VM: target-aware precacheFrom method')
ok(VM.includes('ImageResolveService.getInstance()'), 'VM: precache uses ImageResolveService')
ok((VM.match(/this\.precacheFrom\(/g) || []).length >= 4, 'VM: precache is triggered from target-aware sites (init/jump/onPageChange/auto-read)')
ok(VM.includes('img.imageUrl.length === 0 && img.sUrl.length > 0'), 'VM: precache skips resolved / unloaded pages')
ok(SVC.includes('private inFlight: Map<string, Promise<string>>'), 'SVC: in-flight promise map')
ok(SVC.includes('private resolved: Map<string, ImagePageResult>'), 'SVC: resolved /s/ result map')
ok(SVC.includes('this.resolved.get(image.sUrl)'), 'SVC: reuses cached /s/ resolve result')
ok(SVC.includes('resolve_memory_cache'), 'SVC: logs memory resolve-cache hits')
ok(SVC.includes('this.inFlight.get(image.sUrl)'), 'SVC: coalesces concurrent resolves by sUrl')
ok(SVC.includes('this.inFlight.delete(key)'), 'SVC: clears in-flight entry on settle')
ok(SVC.includes('private async doResolve('), 'SVC: resolve body split into doResolve')
ok(SVC.includes('if (!changeSource)'), 'SVC: 换源 bypasses the shared-promise cache')
ok(VM.includes('private static sessionCache: Map<string, ReaderSessionSnapshot>'), 'VM: per-gallery reader session cache')
ok(VM.includes('this.applySessionCache(fileCount)'), 'VM: init seeds from reader session cache before network load')
ok(VM.includes('this.publishSessionCache()'), 'VM: writes session cache as reader metadata advances')
ok(VM.includes('MAX_READER_SESSION_CACHE'), 'VM: cache is bounded')

if (failures > 0) { console.error(`\n✗ reader precache contract: ${failures} failure(s)`); process.exit(1) }
console.log('✓ reader precache contract: N-ahead range + skip-resolved/unloaded + session/resolve cache wiring locked')
