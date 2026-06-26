#!/usr/bin/env node
/**
 * Contract for EhUconfigParser (read GET /uconfig.php → model → POST body).
 *
 * The .ets parser can't run under node, so this mirrors its regex over the fixture and asserts the
 * parsed values + the POST body, then structurally checks the .ets uses the same field→code mapping so
 * the mirror can't silently drift. The live on-device test is the ground truth for real EH HTML.
 * Run: node scripts/test_uconfig_parser_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// Inline synthetic fixture (scripts/fixtures/ is gitignored; the committed contract carries its own
// hard-gate fixture). Mirrors EH's real uconfig.php DOM for every selector EhUconfigParser relies on.
// The live on-device test is the ground truth for real EH HTML.
const html = `
<form id="profile_form" method="post">
  <select name="profile_set">
    <option value="1" selected="selected">My Profile</option>
    <option value="2">Reader Profile (Default)</option>
  </select>
</form>
<form id="outer" method="post">
  <input type="radio" name="uh" id="uh_0" value="0" />
  <input type="radio" name="uh" id="uh_1" value="1" checked="checked" />
  <input type="radio" name="xr" id="xr_0" value="0" />
  <input type="radio" name="xr" id="xr_1" value="1" />
  <input type="radio" name="xr" id="xr_2" value="2" checked="checked" />
  <input type="text" name="rx" value="1280" />
  <input type="text" name="ry" value="2000" />
  <input type="radio" name="tl" id="tl_0" value="0" checked="checked" />
  <input type="radio" name="tl" id="tl_1" value="1" />
  <input type="radio" name="ar" id="ar_0" value="0" checked="checked" />
  <input type="radio" name="dm" id="dm_0" value="0" />
  <input type="radio" name="dm" id="dm_2" value="2" checked="checked" />
  <input type="radio" name="fs" id="fs_0" value="0" checked="checked" />
  <input type="text" name="ru" value="RRGGB" />
  <input type="text" name="ft" value="10" />
  <input type="text" name="wt" value="20" />
  <textarea name="xu" id="xu">uploader1
uploader2</textarea>
  <input type="radio" name="rc" id="rc_0" value="0" checked="checked" />
  <input type="radio" name="lt" id="lt_0" value="0" checked="checked" />
  <input type="radio" name="ts" id="ts_0" value="0" />
  <input type="radio" name="ts" id="ts_1" value="1" checked="checked" />
  <input type="radio" name="tr" id="tr_0" value="0" checked="checked" />
  <input type="text" name="tp" value="100" />
  <input type="text" name="vp" value="0" />
  <input type="radio" name="cs" id="cs_0" value="0" checked="checked" />
  <input type="radio" name="sc" id="sc_0" value="0" checked="checked" />
  <input type="radio" name="tb" id="tb_0" value="0" checked="checked" />
  <input type="radio" name="pn" id="pn_0" value="0" checked="checked" />
  <input type="text" name="hh" value="" />
  <input type="radio" name="oi" id="oi_0" value="0" checked="checked" />
  <input type="radio" name="qb" id="qb_0" value="0" checked="checked" />
  <input type="radio" name="ms" id="ms_0" value="0" checked="checked" />
  <input type="radio" name="mt" id="mt_0" value="0" checked="checked" />
  <input type="text" name="favorite_0" value="Favorites 0" />
  <input type="text" name="favorite_1" value="To Read" />
  <input type="text" name="favorite_2" value="" />
  <input type="text" name="favorite_3" value="" />
  <input type="text" name="favorite_4" value="" />
  <input type="text" name="favorite_5" value="" />
  <input type="text" name="favorite_6" value="" />
  <input type="text" name="favorite_7" value="" />
  <input type="text" name="favorite_8" value="" />
  <input type="text" name="favorite_9" value="Art &amp; CG" />
  <div><input type="checkbox" name="xn_1" id="xn_1" value="1" checked="checked" /> reupload</div>
  <div><input type="checkbox" name="xn_2" id="xn_2" value="1" /> mosaic</div>
  <div><input type="checkbox" name="xn_3" id="xn_3" value="1" checked="checked" /> incomplete</div>
  <div><input type="checkbox" name="xl_1024" id="xl_1024" value="1" checked="checked" /> Japanese : Translated</div>
  <div><input type="checkbox" name="xl_2048" id="xl_2048" value="1" /> English : Rewrite</div>
</form>
`
const ROOT = process.cwd()
const src = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhUconfigParser.ets'), 'utf8')
let failures = 0
function ok(name, cond) {
  if (!cond) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

// ── Mirror of the parser ──
const parseRadio = (name) => {
  const re = new RegExp(`<input[^>]*name="${name}"[^>]*>`, 'g')
  let m
  while ((m = re.exec(html)) !== null) {
    if (m[0].includes('checked')) {
      const v = (m[0].match(/value="(\d+)"/) || [])[1]
      return v ? parseInt(v, 10) : 0
    }
  }
  return 0
}
const parseInput = (name) => {
  const m = html.match(new RegExp(`<input[^>]*name="${name}"[^>]*>`))
  if (!m) return ''
  return (m[0].match(/value="([^"]*)"/) || ['', ''])[1].replace(/&amp;/g, '&')
}
const parseTextarea = (name) => {
  const m = html.match(new RegExp(`<textarea[^>]*name="${name}"[^>]*>([\\s\\S]*?)</textarea>`))
  return m ? m[1].trim() : ''
}
const parseToggles = (prefix) => {
  const re = new RegExp(`(<input[^>]*id="${prefix}_(\\d+)"[^>]*>)([^<]*)`, 'g')
  const out = []
  let m
  while ((m = re.exec(html)) !== null) {
    out.push({ ser: parseInt(m[2], 10), name: m[3].trim(), excluded: m[1].includes('checked') })
  }
  return out
}

// ── Profiles ──
const selectBlock = (html.match(/<select[^>]*name="profile_set"[^>]*>([\s\S]*?)<\/select>/) || ['', ''])[1]
const profiles = []
let pm
const optRe = /<option[^>]*value="(\d+)"([^>]*)>([\s\S]*?)<\/option>/g
while ((pm = optRe.exec(selectBlock)) !== null) {
  const text = pm[3].trim()
  const isDefault = text.endsWith('(Default)')
  profiles.push({
    value: parseInt(pm[1], 10),
    name: isDefault ? text.replace(/\(Default\)\s*$/, '').trim() : text,
    selected: pm[2].includes('selected'),
    isDefault,
  })
}
ok('two profiles parsed', profiles.length === 2)
ok('selected profile is value 1 "My Profile"', profiles[0].value === 1 && profiles[0].selected && profiles[0].name === 'My Profile')
ok('default profile is value 2 "Reader Profile" (selected != default)', profiles[1].isDefault && !profiles[1].selected && profiles[1].name === 'Reader Profile')

// ── Radios ──
ok('uh=1 (checked index)', parseRadio('uh') === 1)
ok('xr=2', parseRadio('xr') === 2)
ok('tl=0', parseRadio('tl') === 0)
ok('dm=2 (non-contiguous index)', parseRadio('dm') === 2)
ok('ts=1', parseRadio('ts') === 1)

// ── Text inputs ──
ok('rx=1280', parseInput('rx') === '1280')
ok('ry=2000', parseInput('ry') === '2000')
ok('ft=10 / wt=20', parseInput('ft') === '10' && parseInput('wt') === '20')
ok('hh empty', parseInput('hh') === '')
ok('xu textarea newline-joined', parseTextarea('xu') === 'uploader1\nuploader2')

// ── Favorites ──
const fav = []
for (let i = 0; i <= 9; i++) fav.push(parseInput(`favorite_${i}`))
ok('favorite_0 name', fav[0] === 'Favorites 0')
ok('favorite_1 name', fav[1] === 'To Read')
ok('favorite_9 html-unescaped', fav[9] === 'Art & CG')

// ── xn / xl ──
const xn = parseToggles('xn')
const xl = parseToggles('xl')
ok('3 namespaces parsed', xn.length === 3)
ok('xn_1 excluded + named', xn[0].ser === 1 && xn[0].excluded && xn[0].name === 'reupload')
ok('xn_2 not excluded', xn[1].ser === 2 && !xn[1].excluded)
ok('xn_3 excluded', xn[2].ser === 3 && xn[2].excluded)
ok('xl_1024 excluded, xl_2048 not', xl[0].ser === 1024 && xl[0].excluded && xl[1].ser === 2048 && !xl[1].excluded)

// ── POST body ──
const body = []
body.push(`uh=${parseRadio('uh')}`, `xr=${parseRadio('xr')}`, `dm=${parseRadio('dm')}`)
body.push(`rx=${encodeURIComponent(parseInput('rx'))}`, `xu=${encodeURIComponent(parseTextarea('xu'))}`)
fav.forEach((v, i) => body.push(`favorite_${i}=${encodeURIComponent(v)}`))
xn.filter((x) => x.excluded).forEach((x) => body.push(`xn_${x.ser}=on`))
xl.filter((x) => x.excluded).forEach((x) => body.push(`xl_${x.ser}=on`))
body.push('apply=apply')
const joined = body.join('&')
ok('body has uh=1, xr=2, dm=2', joined.includes('uh=1') && joined.includes('xr=2') && joined.includes('dm=2'))
ok('body encodes newline in xu', joined.includes('xu=uploader1%0Auploader2'))
ok('body posts excluded toggles only', joined.includes('xn_1=on') && joined.includes('xn_3=on') && !joined.includes('xn_2=on') && joined.includes('xl_1024=on') && !joined.includes('xl_2048=on'))
ok('body ends with apply=apply', joined.endsWith('apply=apply'))

// ── Structural: .ets mirrors the same field→code mapping (mirror stays honest) ──
for (const code of ['uh', 'xr', 'tl', 'ar', 'dm', 'fs', 'rc', 'lt', 'ts', 'tr', 'cs', 'sc', 'tb', 'pn', 'oi', 'qb', 'ms', 'mt']) {
  ok(`.ets parses + posts radio ${code}`, src.includes(`parseRadio(html, '${code}')`) && new RegExp(`\`${code}=\\$`).test(src))
}
for (const code of ['rx', 'ry', 'ru', 'ft', 'wt', 'tp', 'vp', 'hh']) {
  ok(`.ets parses + posts input ${code}`, src.includes(`parseInput(html, '${code}')`) && src.includes(`'${code}',`))
}
ok('.ets posts apply=apply', src.includes("parts.push('apply=apply')"))
ok('.ets profile selection NOT in post body (sp cookie)', !src.includes('profile_set=') && !src.includes('sp='))

if (failures === 0) {
  console.log('✓ uconfig parser contract passed')
  process.exit(0)
}
console.error(`✗ uconfig parser contract: ${failures} failure(s)`)
process.exit(1)
