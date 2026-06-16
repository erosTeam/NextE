#!/usr/bin/env node
// Contract test for EhMytagsParser. Mirrors the ArkTS regex EXACTLY. Synthetic + real fixture.
// Run: node scripts/test_mytags_parser_contract.mjs   (must report 0 failure(s))
import fs from 'fs'

const RE_TAG = '<div id="tagpreview_(\\d+)"[^>]*style="([^"]*)"[^>]*title="([^"]+)">([^<]*)</div>'
const RE_TAGSET_SELECT = /<select onchange="change_tagset[^>]*>([\s\S]*?)<\/select>/
const RE_TAGSET_OPTION = '<option value="(\\d+)"([^>]*)>([^(<]*?)\\s*\\((\\d+)\\)</option>'
function parse(html) {
  const out = { tags: [], tagSets: [], currentTagset: '', apiuid: '', apikey: '' }
  const re = new RegExp(RE_TAG, 'g')
  let m
  while ((m = re.exec(html)) !== null) {
    const col = m[2].match(/border-color:\s*(#[0-9a-fA-F]+)/)
    const txt = m[2].match(/(?:^|;)\s*color:\s*(#[0-9a-fA-F]+)/)
    const fill = m[2].match(/background[^:]*:[^;]*?(#[0-9a-fA-F]+)/)
    const w = html.match(new RegExp(`id="tagweight_${m[1]}"[^>]*value="(\\d+)"`))
    out.tags.push({
      tagId: m[1], tag: m[3], display: m[4],
      color: col ? col[1] : '',
      textColor: txt ? txt[1] : '',
      fillColor: fill ? fill[1] : (col ? col[1] : ''),
      weight: w ? +w[1] : 10,
      watched: new RegExp(`id="tagwatch_${m[1]}"[^>]*\\schecked`).test(html),
      hidden: new RegExp(`id="taghide_${m[1]}"[^>]*\\schecked`).test(html),
    })
  }
  const sel = html.match(RE_TAGSET_SELECT)
  if (sel) {
    const optRe = new RegExp(RE_TAGSET_OPTION, 'g')
    let o
    while ((o = optRe.exec(sel[1])) !== null) out.tagSets.push({ tagsetId: o[1], name: o[3].trim(), count: +o[4] })
    out.tagSets.sort((a, b) => { const av = parseInt(a.tagsetId, 10); const bv = parseInt(b.tagsetId, 10); return (isNaN(av) ? 0 : av) - (isNaN(bv) ? 0 : bv) }) // numeric id asc, NaN-safe (mirrors .ets)
    const cur = sel[1].match(/<option value="(\d+)"[^>]*selected/)
    out.currentTagset = cur ? cur[1] : ''
  }
  const uid = html.match(/var apiuid\s*=\s*(\d+)/); out.apiuid = uid ? uid[1] : ''
  const key = html.match(/var apikey\s*=\s*"([0-9a-f]+)"/); out.apikey = key ? key[1] : ''
  return out
}

let failures = 0
const fail = (m) => { console.error('✗ ' + m); failures++ }

// 1. Synthetic mirroring the real markup.
const synthetic = `
<script>var apiuid = 2007706; var apikey = "abcdef0123456789abcdef0123456789abcdef01";</script>
<div id="usertag_3437"><div><a href="/tag/language:chinese"><div id="tagpreview_3437" class="gt" style="color:#f1f1f1;border-color:#1357df;background:radial-gradient(#1357df,#3377FF)" title="language:chinese">chinese</div></a></div>
<div><input type="checkbox" id="tagwatch_3437"></div><div><input type="checkbox" id="taghide_3437"></div></div>
<div><input type="number" id="tagweight_3437" value="10"></div>
<div id="usertag_441609"><div><a href="/tag/artist:dittaya"><div id="tagpreview_441609" class="gt" style="border-color:#df4646" title="artist:dittaya">dittaya</div></a></div>
<div><input type="checkbox" id="tagwatch_441609"></div><div><input type="checkbox" id="taghide_441609" checked></div><div><input type="number" id="tagweight_441609" value="25"></div></div>
<div id="usertag_777"><div><a href="/tag/a:short"><div id="tagpreview_777" class="gt" style="border-color:#df4646" title="a:short">short</div></a></div>
<div><input type="checkbox" id="tagwatch_777"></div><div><input type="checkbox" id="taghide_777"></div><div><input type="number" id="tagweight_777" value="10"></div></div>
<select onchange="change_tagset(this.value)"><option value="2">Artist (82)</option><option value="1" selected="selected">TAG (38)</option></select>`
const syn = parse(synthetic)
if (syn.tags.length !== 3) fail(`synthetic: expected 3 tags, got ${syn.tags.length}`)
if (syn.tags[0] && (syn.tags[0].tag !== 'language:chinese' || syn.tags[0].color !== '#1357df')) fail(`syn tag0 wrong: ${JSON.stringify(syn.tags[0])}`)
// 3-color parse: text color (#f1f1f1), border (#1357df), fill = gradient start (#1357df) — not white-on-anything.
if (syn.tags[0] && (syn.tags[0].textColor !== '#f1f1f1' || syn.tags[0].fillColor !== '#1357df')) fail(`syn tag0 colors wrong: ${JSON.stringify(syn.tags[0])}`)
// A tag with only border-color (no fill/text) falls back: fillColor = border, textColor empty.
if (syn.tags[1] && (syn.tags[1].fillColor !== '#df4646' || syn.tags[1].textColor !== '')) fail(`syn tag1 colors wrong: ${JSON.stringify(syn.tags[1])}`)
if (syn.tags[1] && (syn.tags[1].tag !== 'artist:dittaya' || syn.tags[1].hidden !== true)) fail(`syn tag1 hidden not detected: ${JSON.stringify(syn.tags[1])}`)
if (syn.tags[0] && syn.tags[0].weight !== 10) fail(`syn tag0 weight: ${syn.tags[0].weight}`)
if (syn.tags[1] && syn.tags[1].weight !== 25) fail(`syn tag1 weight: ${syn.tags[1].weight}`)
if (syn.tagSets.length !== 2) fail(`syn tagSets: ${JSON.stringify(syn.tagSets)}`)
// DOM order is [2 Artist, 1 TAG]; after the numeric-id sort it must become [1 TAG, 2 Artist].
if (syn.tagSets[0] && (syn.tagSets[0].tagsetId !== '1' || syn.tagSets[0].name !== 'TAG')) fail(`syn tagset0 (sorted): ${JSON.stringify(syn.tagSets[0])}`)
if (syn.tagSets[1] && (syn.tagSets[1].tagsetId !== '2' || syn.tagSets[1].name !== 'Artist' || syn.tagSets[1].count !== 82)) fail(`syn tagset1 (sorted): ${JSON.stringify(syn.tagSets[1])}`)
if (syn.currentTagset !== '1') fail(`syn currentTagset: ${syn.currentTagset}`)
if (syn.apiuid !== '2007706') fail(`syn apiuid: ${syn.apiuid}`)
if (syn.apikey.length === 0) fail(`syn apikey empty`)

// 2. Real fixture.
const realPath = new URL('./fixtures/mytags_real.html', import.meta.url)
if (fs.existsSync(realPath)) {
  const real = parse(fs.readFileSync(realPath, 'utf8'))
  if (real.tags.length < 5) fail(`real: too few tags (${real.tags.length})`)
  if (!real.tags.every(t => t.tag.includes(':'))) fail('real: some tags missing namespace')
  if (real.apiuid.length === 0) fail('real: apiuid empty')
  if (real.apikey.length === 0) fail('real: apikey empty')
  if (real.tagSets.length < 1) fail('real: no tagSets parsed')
  if (!real.currentTagset) fail('real: no selected tagset')
  const watched = real.tags.filter(t => t.watched).length
  const hidden = real.tags.filter(t => t.hidden).length
  console.log(`  real fixture: ${real.tags.length} tags (${watched} watched, ${hidden} hidden), ${real.tagSets.length} tagsets (cur=${real.currentTagset}), apiuid+apikey ok`)
} else {
  console.log('  (real mytags fixture not present — synthetic only)')
}

// 3. Namespace prefix expansion (eros_fe prefixToNameSpaceMap) — short prefixes bucket as full names.
const NS_PREFIX = { a: 'artist', c: 'character', f: 'female', g: 'group', l: 'language', m: 'male', p: 'parody', r: 'reclass', o: 'other', x: 'mixed', cos: 'cosplayer', misc: 'misc' }
const expandNamespace = (ns) => { const k = ns.toLowerCase().trim(); return NS_PREFIX[k] !== undefined ? NS_PREFIX[k] : k }
// EhUsertag.namespace(): part before ':' (or 'misc' when absent), expanded.
const nsOf = (tag) => { const i = tag.indexOf(':'); return expandNamespace(i > 0 ? tag.substring(0, i) : 'misc') }
const nsCases = [['a:dittaya', 'artist'], ['artist:dittaya', 'artist'], ['f:big', 'female'], ['cos:foo', 'cosplayer'], ['language:chinese', 'language'], ['m:x', 'male'], ['misc:x', 'misc'], ['noNamespace', 'misc'], ['Artist:Caps', 'artist'], ['unknownns:z', 'unknownns']]
for (const [tag, expect] of nsCases) { if (nsOf(tag) !== expect) fail(`namespace('${tag}') = ${nsOf(tag)}, expected ${expect}`) }
// End-to-end: the short-prefix tag PARSED from the synthetic markup (title="a:short") expands to 'artist'.
if (syn.tags[2] && (syn.tags[2].tag !== 'a:short' || nsOf(syn.tags[2].tag) !== 'artist')) fail(`parsed short-prefix tag did not expand: ${JSON.stringify(syn.tags[2])} → ${syn.tags[2] && nsOf(syn.tags[2].tag)}`)

// 4. Structural: the .ets actually wires expansion + sort (guards against silent regressions).
const read = (p) => fs.readFileSync(new URL(p, import.meta.url), 'utf8')
const consts = read('../shared/src/main/ets/constants/EhConstants.ets')
if (!/static expandNamespace\(ns: string\)/.test(consts)) fail('EhConstants.expandNamespace missing')
if (!/m\.set\('a', 'artist'\)/.test(consts) || !/m\.set\('cos', 'cosplayer'\)/.test(consts)) fail('EhConstants prefix map incomplete')
if (!/tagNsColorMap\.get\(EhConstants\.expandNamespace\(ns\)\)/.test(consts)) fail('tagNamespaceColor does not expand prefix before color lookup')
const model = read('../shared/src/main/ets/model/EhMytags.ets')
if (!/EhConstants\.expandNamespace\(raw\)/.test(model)) fail('EhUsertag.namespace does not expand prefix')
const parser = read('../shared/src/main/ets/parser/EhMytagsParser.ets')
if (!/sets\.sort\(/.test(parser)) fail('EhMytagsParser does not sort tagsets by id')

if (failures === 0) { console.log('✓ mytags parser contract: all cases pass'); process.exit(0) }
else { console.error(`✗ mytags parser contract: ${failures} failure(s)`); process.exit(1) }
