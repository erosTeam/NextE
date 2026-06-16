#!/usr/bin/env node
/**
 * Contract test for EhImagePageParser (/s/ image page → full-image URL + showKey + origin + nl).
 * Patterns mirror shared/src/main/ets/parser/EhImagePageParser.ets. Synthetic = hard gate;
 * real fixture (scripts/fixtures/image_page.html) = live smoke when present.
 *
 * Run: node scripts/test_image_page_parser_contract.mjs
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const g1 = (h, re) => { const m = h.match(re); return m && m[1] !== undefined ? m[1] : '' }
const RE = {
  img: /<img id="img" src="([^"]+)"/,
  showkey: /showkey="([^"]+)"/,
  origin: /<a href="(https:\/\/[^"]*\/fullimg[^"]*)"/,
  nl: /onclick="return nl\('([^']+)'\)/,
}

let failures = 0
const eq = (a, e, label) => { if (a !== e) { console.error(`  ✗ ${label}: expected ${JSON.stringify(e)}, got ${JSON.stringify(a)}`); failures++ } }
const ok = (c, label) => { if (!c) { console.error(`  ✗ ${label}`); failures++ } }

const SYN = `<div id="i3"><a id="loadfail" onclick="return nl('12500-494832')"><img id="img" src="https://x.hath.network/h/abcdef123/keystamp/0.jpg" style="" /></a></div>
<a href="https://e-hentai.org/fullimg/3987108/1/rp9fzq9altc/0.jpg">Download original</a>
<script>var showkey="kapjjdwaltc";</script>`

console.log('— synthetic —')
eq(g1(SYN, RE.img), 'https://x.hath.network/h/abcdef123/keystamp/0.jpg', 'imageUrl')
eq(g1(SYN, RE.showkey), 'kapjjdwaltc', 'showKey')
eq(g1(SYN, RE.origin), 'https://e-hentai.org/fullimg/3987108/1/rp9fzq9altc/0.jpg', 'originImageUrl')
eq(g1(SYN, RE.nl), '12500-494832', 'reloadKey')

const fx = join(ROOT, 'scripts/fixtures/image_page.html')
if (existsSync(fx)) {
  console.log('— real e-hentai.org image-page fixture —')
  const h = readFileSync(fx, 'utf8')
  ok(g1(h, RE.img).startsWith('https://'), 'real imageUrl is https')
  ok(g1(h, RE.showkey).length > 0, 'real showKey present')
  ok(g1(h, RE.nl).length > 0, 'real nl reload present')
  if (!failures) console.log(`  ✓ imageUrl=${g1(h, RE.img).slice(0, 42)}… showKey=${g1(h, RE.showkey)}`)
} else {
  console.log('— real fixture absent; synthetic-only —')
}

if (failures > 0) { console.error(`\n✗ image-page parser contract: ${failures} failure(s)`); process.exit(1) }
console.log('\n✓ image-page parser contract passed')
