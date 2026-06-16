#!/usr/bin/env node
// Contract test for EhFavcatListParser. Mirrors the ArkTS regex EXACTLY. Runs a synthetic
// fixture (always) + the real authed favorites.php fixture if present (gitignored).
// Run: node scripts/test_favcatlist_parser_contract.mjs   (must report 0 failure(s))
import fs from 'fs'

// --- EXACT mirror of EhFavcatListParser.RE_FP / parse() ---
const RE_FP = '<div class="fp"[^>]*favcat=(\\d+)\'[^>]*>\\s*<div[^>]*>(\\d+)</div>\\s*<div class="i"[^>]*title="([^"]*)"'
function parse(html) {
  const out = []
  const re = new RegExp(RE_FP, 'g')
  let m
  while ((m = re.exec(html)) !== null) {
    if (m[1] !== undefined && m[2] !== undefined && m[3] !== undefined) {
      out.push({ favId: m[1], favTitle: m[3], totNum: Number.parseInt(m[2], 10) })
    }
  }
  return out
}

let failures = 0
const fail = (msg) => { console.error('✗ ' + msg); failures++ }

// 1. Synthetic fixture mirroring the real favorites.php favcat bar structure.
const synthetic = `
<div class="ido"><h1>Favorites</h1><div class="nosel">
<div class="fp" onclick="document.location='https://e-hentai.org/favorites.php?favcat=0'" style="width:160px">
<div style="font-weight:bold">470</div><div class="i" style="background-position:0px -2px" title="F0"></div><div>F0</div></div>
<div class="fp" onclick="document.location='https://e-hentai.org/favorites.php?favcat=1'" style="width:160px">
<div style="font-weight:bold">1234</div><div class="i" style="background-position:0px -21px" title="本子"></div><div>本子</div></div>
</div></div>`
const syn = parse(synthetic)
if (syn.length !== 2) fail(`synthetic: expected 2 favcats, got ${syn.length}`)
if (syn[0] && (syn[0].favId !== '0' || syn[0].totNum !== 470 || syn[0].favTitle !== 'F0')) fail(`synthetic favcat0 wrong: ${JSON.stringify(syn[0])}`)
if (syn[1] && (syn[1].favId !== '1' || syn[1].totNum !== 1234 || syn[1].favTitle !== '本子')) fail(`synthetic favcat1 wrong: ${JSON.stringify(syn[1])}`)

// 2. Real fixture (only if captured — gitignored). Must yield exactly 10 favcats, ids 0..9.
const realPath = new URL('./fixtures/favorites_real.html', import.meta.url)
if (fs.existsSync(realPath)) {
  const real = parse(fs.readFileSync(realPath, 'utf8'))
  if (real.length !== 10) fail(`real fixture: expected 10 favcats, got ${real.length}`)
  real.forEach((f, i) => {
    if (f.favId !== String(i)) fail(`real favcat ${i}: favId=${f.favId}`)
    if (!Number.isFinite(f.totNum)) fail(`real favcat ${i}: totNum NaN`)
    if (f.favTitle.length === 0) fail(`real favcat ${i}: empty name`)
  })
  console.log(`  real fixture: parsed ${real.length} favcats (${real.map(f => f.favTitle).join(', ')})`)
  // favOrder: EhApiService extracts the active sort order from the inline_set `<option selected>`.
  const html = fs.readFileSync(realPath, 'utf8')
  const om = html.match(/<option value="([fp])" selected/)
  const favOrder = om ? `fs_${om[1]}` : ''
  if (favOrder !== 'fs_f' && favOrder !== 'fs_p') fail(`real fixture: favOrder parse → ${favOrder}`)
  else console.log(`  real fixture: favOrder = ${favOrder}`)
} else {
  console.log('  (real favorites fixture not present — synthetic only)')
}

// favOrder synthetic: both selected variants resolve to fs_f / fs_p.
const ordFp = '<select onchange="setfav"><option value="p" selected="selected">Published Time</option><option value="f">Favorited</option></select>'
const ordFf = '<select><option value="p">Published</option><option value="f" selected="selected">Favorited</option></select>'
const parseOrder = (h) => { const m = h.match(/<option value="([fp])" selected/); return m ? `fs_${m[1]}` : '' }
if (parseOrder(ordFp) !== 'fs_p') fail(`favOrder synthetic fs_p: ${parseOrder(ordFp)}`)
if (parseOrder(ordFf) !== 'fs_f') fail(`favOrder synthetic fs_f: ${parseOrder(ordFf)}`)

if (failures === 0) { console.log('✓ favcat-list parser contract: all cases pass'); process.exit(0) }
else { console.error(`✗ favcat-list parser contract: ${failures} failure(s)`); process.exit(1) }
