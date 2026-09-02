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
  <p>Uploader exclusion quota: <strong>2</strong>/<strong>1,000</strong></p>
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
  <div id="catsel">
    <div><input type="hidden" name="ct_doujinshi" id="ct_doujinshi" value="0" /> <div id="ct_doujinshi_div" class="cs ct2" onclick="toggle_catdefault('doujinshi')">Doujinshi</div></div>
    <div><input type="hidden" name="ct_misc" id="ct_misc" value="1" /> <div id="ct_misc_div" class="cs ct1" onclick="toggle_catdefault('misc')">Misc</div></div>
  </div>
</form>
<h2>Excluded Languages</h2>
<table>
  <tr><th></th><th>Original</th><th>Translated</th><th>Rewrite</th></tr>
  <tr><td>Japanese</td><td></td><td><input type="checkbox" name="xl_1024" id="xl_1024" checked="checked" /></td><td><input type="checkbox" name="xl_2048" id="xl_2048" /></td></tr>
  <tr><td>English</td><td><input type="checkbox" name="xl_1" id="xl_1" /></td><td><input type="checkbox" name="xl_1025" id="xl_1025" checked="checked" /></td><td><input type="checkbox" name="xl_2049" id="xl_2049" /></td></tr>
</table>
`
const ROOT = process.cwd()
const src = readFileSync(join(ROOT, 'shared/src/main/ets/parser/EhUconfigParser.ets'), 'utf8')
const modelSrc = readFileSync(join(ROOT, 'shared/src/main/ets/model/EhProfileSettings.ets'), 'utf8')
const pageSrc = readFileSync(
  join(ROOT, 'feature/settings/src/main/ets/pages/EhProfileSettingsPage.ets'),
  'utf8',
)
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
const parseXuQuota = () => {
  const marker = html.match(/<textarea[^>]*(?:name|id)="xu"[\s\S]*?<\/textarea>/)
  if (!marker || marker.index === undefined) return []
  const tail = html.substring(marker.index + marker[0].length)
  const out = []
  const re = /<strong[^>]*>([\s\S]*?)<\/strong>/g
  let m
  while ((m = re.exec(tail)) !== null && out.length < 2) {
    const value = Number.parseInt(m[1].replace(/<[^>]*>/g, '').replace(/,/g, '').trim(), 10)
    if (!Number.isNaN(value)) out.push(value)
  }
  return out
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
// xl is a table: language name in the first <td>, checkboxes for original (<1024)/translated
// (1024..2047)/rewrite (>=2048).
const parseLanguages = () => {
  const start = html.indexOf('Excluded Languages')
  if (start < 0) return []
  const end = html.indexOf('</table>', start)
  const region = html.substring(start, end < 0 ? html.length : end)
  const out = []
  for (const row of region.match(/<tr[^>]*>[\s\S]*?<\/tr>/g) || []) {
    if (!row.includes('xl_')) continue
    const lang = ((row.match(/<td[^>]*>([\s\S]*?)<\/td>/) || ['', ''])[1]).replace(/<[^>]*>/g, '').trim()
    const re = /<input[^>]*name="xl_(\d+)"[^>]*>/g
    let m
    while ((m = re.exec(row)) !== null) {
      const ser = parseInt(m[1], 10)
      out.push({ ser, lang, excluded: m[0].includes('checked'), variant: ser >= 2048 ? 2 : ser >= 1024 ? 1 : 0 })
    }
  }
  return out
}

// Real EH capability shape: unavailable choices remain present with `disabled`; fields can also be
// present but disabled. The native editor must distinguish that from simple DOM presence.
const capabilityHtml = `
<label class="lr"><input type="radio" name="tr" value="0" checked="checked"><span></span>4</label>
<label class="lr"><input type="radio" name="tr" value="1" disabled><span></span>8</label>
<label class="lr"><input type="radio" name="tr" value="2" disabled="disabled"><span></span>20</label>
<label class="lr"><input type="radio" name="tr" value="3" disabled><span></span>40</label>
<label class="lr"><input type="radio" name="oi" value="0" checked="checked"><span></span>Resampled</label>
<label class="lr"><input type="radio" name="oi" value="1" disabled><span></span>Original</label>
<select name="ms">
  <option value="0" selected="selected">Align left</option>
  <option value="1" disabled>Align center</option>
</select>
<select name="qb" disabled>
  <option value="0" selected="selected">Disabled MPV</option>
</select>
<input type="text" name="rx" value="0">
<input type="text" name="hh" value="" disabled>
<input type="checkbox" name="xn_1" id="xn_1" value="1" disabled> reupload
`
const isDisabled = (tag) => /(?:^|\s)disabled(?:\s*=|\s|>)/.test(tag)
const parseEnabledOptions = (source) => {
  const out = new Map()
  const push = (code, value) => {
    const values = out.get(code) || []
    if (!values.includes(value)) values.push(value)
    out.set(code, values)
  }
  const radios = /(<input type="radio" name="([a-z]+)" value="(\d+)"[^>]*>)\s*(?:<span><\/span>)?\s*([^<]*)<\/label>/g
  let m
  while ((m = radios.exec(source)) !== null) {
    if (!isDisabled(m[1])) push(m[2], parseInt(m[3], 10))
  }
  const selects = /(<select name="([a-z]+)"[^>]*>)([\s\S]*?)<\/select>/g
  while ((m = selects.exec(source)) !== null) {
    if (isDisabled(m[1])) continue
    const options = /(<option value="(\d+)"[^>]*>)([\s\S]*?)<\/option>/g
    let option
    while ((option = options.exec(m[3])) !== null) {
      if (!isDisabled(option[1])) push(m[2], parseInt(option[2], 10))
    }
  }
  return out
}
const parseFieldPresence = (source, enabledOnly) => {
  const out = []
  const re = /<(?:input|select|textarea)[^>]*name="([a-z0-9_-]+)"[^>]*>/g
  let m
  while ((m = re.exec(source)) !== null) {
    if ((!enabledOnly || !isDisabled(m[0])) && !out.includes(m[1])) out.push(m[1])
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
const xuQuota = parseXuQuota()
ok('xu quota parsed from post-xu strong values', xuQuota.length === 2 && xuQuota[0] === 2 && xuQuota[1] === 1000)

// ── Favorites ──
const fav = []
for (let i = 0; i <= 9; i++) fav.push(parseInput(`favorite_${i}`))
ok('favorite_0 name', fav[0] === 'Favorites 0')
ok('favorite_1 name', fav[1] === 'To Read')
ok('favorite_9 html-unescaped', fav[9] === 'Art & CG')

// ── xn (namespaces, id-based) / xl (language table) ──
const xn = parseToggles('xn')
const xl = parseLanguages()
ok('3 namespaces parsed', xn.length === 3)
ok('xn_1 excluded + named', xn[0].ser === 1 && xn[0].excluded && xn[0].name === 'reupload')
ok('xn_2 not excluded', xn[1].ser === 2 && !xn[1].excluded)
ok('xn_3 excluded', xn[2].ser === 3 && xn[2].excluded)
// ── ct (front-page categories) ──
const cats = []
{
  const re = /<input[^>]*name="ct_([a-z-]+)"[^>]*value="(\d)"[^>]*>/g
  let m
  while ((m = re.exec(html)) !== null) {
    cats.push({ key: `ct_${m[1]}`, hidden: m[2] === '1' })
  }
}
ok('2 categories parsed', cats.length === 2)
ok('ct_doujinshi shown (0), ct_misc hidden (1)', cats[0].key === 'ct_doujinshi' && !cats[0].hidden && cats[1].key === 'ct_misc' && cats[1].hidden)

ok('5 language toggles across 2 rows', xl.length === 5)
ok('Japanese·translated (1024) excluded, variant 1', xl[0].ser === 1024 && xl[0].lang === 'Japanese' && xl[0].excluded && xl[0].variant === 1)
ok('Japanese·rewrite (2048) not excluded, variant 2', xl[1].ser === 2048 && xl[1].variant === 2 && !xl[1].excluded)
ok('English·original (1) variant 0, English·translated (1025) excluded', xl[2].ser === 1 && xl[2].lang === 'English' && xl[2].variant === 0 && !xl[2].excluded && xl[3].ser === 1025 && xl[3].excluded && xl[3].variant === 1)

// ── Disabled capability controls ──
const enabledOptions = parseEnabledOptions(capabilityHtml)
const presentFields = parseFieldPresence(capabilityHtml, false)
const enabledFields = parseFieldPresence(capabilityHtml, true)
ok('disabled thumbnail rows are excluded, leaving only 4', JSON.stringify(enabledOptions.get('tr')) === '[0]')
ok('disabled original-image value is excluded', JSON.stringify(enabledOptions.get('oi')) === '[0]')
ok('disabled select option is excluded', JSON.stringify(enabledOptions.get('ms')) === '[0]')
ok('disabled select field has no enabled options', !enabledOptions.has('qb'))
ok('disabled field remains present but is not editable', presentFields.includes('hh') && !enabledFields.includes('hh'))
ok('enabled field remains editable', enabledFields.includes('rx'))

// ── POST body ──
const body = []
body.push(`uh=${parseRadio('uh')}`, `xr=${parseRadio('xr')}`, `dm=${parseRadio('dm')}`)
body.push(`rx=${encodeURIComponent(parseInput('rx'))}`, `xu=${encodeURIComponent(parseTextarea('xu'))}`)
fav.forEach((v, i) => body.push(`favorite_${i}=${encodeURIComponent(v)}`))
cats.forEach((c) => body.push(`${c.key}=${c.hidden ? '1' : '0'}`))
xn.filter((x) => x.excluded).forEach((x) => body.push(`xn_${x.ser}=on`))
xl.filter((x) => x.excluded).forEach((x) => body.push(`xl_${x.ser}=on`))
body.push('apply=apply')
const joined = body.join('&')
ok('body has uh=1, xr=2, dm=2', joined.includes('uh=1') && joined.includes('xr=2') && joined.includes('dm=2'))
ok('body encodes newline in xu', joined.includes('xu=uploader1%0Auploader2'))
ok('body posts excluded toggles only', joined.includes('xn_1=on') && joined.includes('xn_3=on') && !joined.includes('xn_2=on') && joined.includes('xl_1024=on') && joined.includes('xl_1025=on') && !joined.includes('xl_2048=on'))
ok('body ends with apply=apply', joined.endsWith('apply=apply'))

// ── Structural: .ets mirrors the same field→code mapping (mirror stays honest) ──
for (const code of ['uh', 'xr', 'tl', 'ar', 'dm', 'fs', 'rc', 'lt', 'ts', 'tr', 'cs', 'sc', 'tb', 'pn', 'oi', 'qb', 'ms', 'mt']) {
  ok(
    `.ets parses + capability-gates radio ${code}`,
    src.includes(`parseRadio(html, '${code}')`) && src.includes(`pushRadio(parts, s, '${code}',`),
  )
}
for (const code of ['rx', 'ry', 'ru', 'ft', 'wt', 'tp', 'vp', 'hh']) {
  ok(
    `.ets parses + capability-gates input ${code}`,
    src.includes(`parseInput(html, '${code}')`) && src.includes(`pushText(parts, s, '${code}',`),
  )
}
ok('.ets posts apply=apply', src.includes("parts.push('apply=apply')"))
ok('.ets profile selection NOT in post body (sp cookie)', !src.includes('profile_set=') && !src.includes('sp='))
ok('.ets parses the xl language table with variant by id range', src.includes('parseLanguages') && src.includes("indexOf('Excluded Languages')") && /ser >= 2048 \? 2 : ser >= 1024 \? 1 : 0/.test(src))
ok('.ets parses + posts front-page categories (ct_*)', src.includes('parseCategories') && /name="ct_/.test(src) && src.includes('${c.key}=${c.hidden'))
ok('body posts ct visibility 0/1', joined.includes('ct_doujinshi=0') && joined.includes('ct_misc=1'))
ok('.ets parses options (radios + selects) WITH page labels + field-name presence', src.includes('parseControlOptions') && src.includes('parseFieldNames') && /type="radio" name=[^]*value="[^]*<\/label>/.test(src) && src.includes('<select name='))
ok('.ets excludes disabled controls from enabled options and fields', src.includes('parseEnabledFieldNames') && src.includes('EhUconfigParser.disabled(') && src.includes('private static disabled('))
ok('.ets POST body omits unavailable radios and fields', src.includes('s.radioValueEnabled(code, value)') && src.includes('s.enabledFieldNames.indexOf(code) >= 0'))
ok('model exposes enabled radio-value lookup', modelSrc.includes('radioValueEnabled(code: string, value: number)'))
ok('native dropdown disables groups with fewer than two enabled choices', pageSrc.includes('dropdownMenuEnabled: this.options.length > 1') && pageSrc.includes('isEnabled: this.options.length > 1'))
for (const code of ['oi', 'qb', 'mt']) {
  ok(`native switch ${code} checks its target capability`, pageSrc.includes(`this.switchEnabled('${code}', target)`))
}
for (const code of ['rx', 'ry', 'tp', 'vp', 'ft', 'wt', 'ru', 'hh', 'xu']) {
  ok(`native field ${code} checks editability`, pageSrc.includes(`this.fieldEnabled('${code}')`))
}
ok('.ets parses xu quota into model', src.includes('parseXuQuota') && src.includes('s.xuQuotaUsing') && src.includes('s.xuQuotaMax'))

if (failures === 0) {
  console.log('✓ uconfig parser contract passed')
  process.exit(0)
}
console.error(`✗ uconfig parser contract: ${failures} failure(s)`)
process.exit(1)
