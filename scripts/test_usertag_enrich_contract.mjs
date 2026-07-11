// Contract test for the usertag → list-tag color enrichment logic (UserTagState + UserTagEnricher).
// Mirrors the ArkTS keying/lookup/enrich/hide so a regression in the rules is caught without a device.
// Hard rule under test: list tags are NEUTRAL unless the USER colored that exact tag — never by namespace.
import { readFileSync } from 'node:fs'

let failures = 0
function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    console.error(`✗ ${name}: got ${a}, expected ${e}`)
    failures++
  } else {
    console.log(`✓ ${name}`)
  }
}

// --- mirror of UserTagState.setTags() keying (ns:tag lowercased + plain-tag fallback) ---
function expandNamespace(ns) {
  const key = (ns || '').toLowerCase().trim()
  const map = new Map([
    ['a', 'artist'], ['c', 'character'], ['f', 'female'], ['g', 'group'], ['l', 'language'],
    ['m', 'male'], ['p', 'parody'], ['r', 'reclass'], ['o', 'other'], ['x', 'mixed'],
    ['cos', 'cosplayer'], ['misc', 'misc'],
  ])
  return map.get(key) || key
}
function compactNamespace(ns) {
  const full = expandNamespace(ns)
  const map = new Map([
    ['artist', 'a'], ['character', 'c'], ['female', 'f'], ['group', 'g'], ['language', 'l'],
    ['male', 'm'], ['parody', 'p'], ['reclass', 'r'], ['other', 'o'], ['mixed', 'x'],
    ['cosplayer', 'cos'], ['misc', 'misc'],
  ])
  return map.get(full) || full
}
function canonicalTagText(tag) {
  const raw = (tag || '').trim()
  const pipe = raw.indexOf('|')
  return pipe >= 0 ? raw.substring(0, pipe).trim() : raw
}
function setAlias(index, key, tag) {
  if (key.length > 0 && !index.has(key)) index.set(key, tag)
}
function buildIndex(usertags) {
  const index = new Map()
  for (const t of usertags) {
    const key = canonicalTagText(t.tag).toLowerCase().trim()
    if (key.length === 0) continue
    setAlias(index, key, t)
    const idx = key.indexOf(':')
    if (idx >= 0) {
      const ns = key.substring(0, idx).trim()
      const plain = key.substring(idx + 1).trim()
      if (plain.length > 0) {
        setAlias(index, `${expandNamespace(ns)}:${plain}`, t)
        setAlias(index, `${compactNamespace(ns)}:${plain}`, t)
        setAlias(index, plain, t)
      }
    }
  }
  return index
}

// --- mirror of UserTagState.lookup(): try "ns:tag" then plain "tag" ---
function lookup(index, namespace, tag) {
  const t = canonicalTagText(tag).toLowerCase().trim()
  const ns = (namespace || '').toLowerCase().trim()
  if (ns.length > 0) {
    for (const key of [`${ns}:${t}`, `${expandNamespace(ns)}:${t}`, `${compactNamespace(ns)}:${t}`]) {
      const full = index.get(key)
      if (full !== undefined) return full
    }
  }
  return index.get(t)
}
function lookupStore(store, namespace, tag) {
  return lookup(store.userIndex, namespace, tag) || lookup(store.inlineIndex, namespace, tag)
}
function ingestInline(store, simpleTags) {
  let changed = false
  for (const st of simpleTags) {
    if (!st.backgroundColor && !st.color) continue
    const tagText = canonicalTagText(st.text).trim()
    if (tagText.length === 0) continue
    const ns = expandNamespace(st.namespace).trim()
    const usertag = {
      tag: ns.length > 0 ? `${ns}:${tagText}` : tagText,
      fillColor: st.backgroundColor || '',
      color: st.backgroundColor || '',
      textColor: st.color || '',
      hidden: false,
    }
    const before = lookup(store.inlineIndex, st.namespace, st.text)
    buildIndex([usertag]).forEach((value, key) => {
      store.inlineIndex.set(key, value)
    })
    const after = lookup(store.inlineIndex, st.namespace, st.text)
    changed = changed || before === undefined ||
      (after !== undefined && (before.fillColor !== after.fillColor || before.textColor !== after.textColor))
  }
  return changed
}

// --- mirror of UserTagEnricher.enrichTags(): fill bg=fillColor, color=textColor on a match ---
function enrich(index, simpleTags) {
  for (const st of simpleTags) {
    const u = lookup(index, st.namespace, st.text)
    if (u !== undefined) {
      if ((u.fillColor || '').length > 0) st.backgroundColor = u.fillColor
      if ((u.textColor || '').length > 0) st.color = u.textColor
    }
  }
  return simpleTags
}

function isHidden(index, namespace, tag) {
  const u = lookup(index, namespace, tag)
  return u !== undefined && !!u.hidden
}

// ---------- fixtures (synthetic My Tags set) ----------
const USERTAGS = [
  { tag: 'female:big breasts', fillColor: '#330000', textColor: '#ffaaaa', hidden: false },
  { tag: 'f:huge breasts | 巨乳', fillColor: '#440000', textColor: '#ffbbbb', hidden: false },
  { tag: 'language:chinese', fillColor: '#001133', textColor: '#88aaff', hidden: false },
  { tag: 'parody:original', fillColor: '', textColor: '', hidden: true }, // hidden, no color
  { tag: 'lolicon', fillColor: '#220022', textColor: '#ff88ff', hidden: true }, // plain (no ns)
  { tag: '', fillColor: '#000000', textColor: '#ffffff', hidden: false }, // empty tag → ignored
]
const index = buildIndex(USERTAGS)
const store = { userIndex: index, inlineIndex: new Map() }

// ---------- 1. exact ns:tag match colors a chip ----------
let tags = enrich(index, [{ namespace: 'female', text: 'big breasts', color: '', backgroundColor: '' }])
check('ns:tag exact → bg', tags[0].backgroundColor, '#330000')
check('ns:tag exact → text', tags[0].color, '#ffaaaa')

// ---------- 2. case-insensitive match ----------
tags = enrich(index, [{ namespace: 'Female', text: 'BIG BREASTS', color: '', backgroundColor: '' }])
check('case-insensitive → bg', tags[0].backgroundColor, '#330000')

// ---------- 3. plain-tag fallback (list tag's namespace doesn't form a key, plain does) ----------
tags = enrich(index, [{ namespace: 'misc', text: 'lolicon', color: '', backgroundColor: '' }])
check('plain fallback → bg', tags[0].backgroundColor, '#220022')
check('plain fallback → text', tags[0].color, '#ff88ff')

// ---------- 3b. raw namespace aliases survive translated display labels ----------
tags = enrich(index, [{ namespace: 'female', text: 'huge breasts', color: '', backgroundColor: '' }])
check('short usertag key → full namespace lookup bg', tags[0].backgroundColor, '#440000')
tags = enrich(index, [{ namespace: 'f', text: 'big breasts', color: '', backgroundColor: '' }])
check('full usertag key → short namespace lookup bg', tags[0].backgroundColor, '#330000')
tags = enrich(index, [{ namespace: 'female', text: '巨乳', color: '', backgroundColor: '' }])
check('translated display is not a color key', tags[0].backgroundColor, '')

// ---------- 4. NO namespace coloring: an uncolored tag stays neutral (red line) ----------
tags = enrich(index, [{ namespace: 'artist', text: 'nobody', color: '', backgroundColor: '' }])
check('no match → bg stays empty', tags[0].backgroundColor, '')
check('no match → text stays empty', tags[0].color, '')

// ---------- 5. a hidden-but-uncolored usertag must NOT paint a color ----------
tags = enrich(index, [{ namespace: 'parody', text: 'original', color: '', backgroundColor: '' }])
check('hidden-no-color → bg stays empty', tags[0].backgroundColor, '')

// ---------- 6. hide detection ----------
check('isHidden ns:tag', isHidden(index, 'parody', 'original'), true)
check('isHidden plain', isHidden(index, '', 'lolicon'), true)
check('isHidden false for colored-only', isHidden(index, 'female', 'big breasts'), false)
check('isHidden false for unknown', isHidden(index, 'artist', 'nobody'), false)

// ---------- 7. empty-tag usertag was ignored (no '' key) ----------
check('empty usertag ignored', index.has(''), false)

// ---------- 8. anyHidden + gallery hide-filter (eros_fe needHide) ----------
function anyHidden(idx, tags) {
  return tags.some((t) => isHidden(idx, t.namespace, t.text))
}
const galA = { gid: 'A', simpleTags: [{ namespace: 'parody', text: 'original' }] } // hidden (ns:tag)
const galB = { gid: 'B', simpleTags: [{ namespace: 'female', text: 'big breasts' }] } // colored, not hidden
const galC = { gid: 'C', simpleTags: [{ namespace: 'misc', text: 'lolicon' }] } // hidden (plain fallback)
check('anyHidden true (ns:tag hidden)', anyHidden(index, galA.simpleTags), true)
check('anyHidden true (plain hidden)', anyHidden(index, galC.simpleTags), true)
check('anyHidden false (colored only)', anyHidden(index, galB.simpleTags), false)
const kept = [galA, galB, galC].filter((g) => !anyHidden(index, g.simpleTags)).map((g) => g.gid)
check('hide-filter removes hidden galleries', kept, ['B'])

// ---------- 9. list inline colours feed a fallback index for later detail-page chips ----------
const inlineChanged = ingestInline(store, [
  { namespace: 'artist', text: 'puyoucha', color: '#f1f1f1', backgroundColor: '#e91e63' },
])
check('inline color ingest reports change', inlineChanged, true)
const inlineHit = lookupStore(store, 'artist', 'puyoucha')
check('inline color lookup bg', inlineHit?.fillColor, '#e91e63')
check('inline color lookup text', inlineHit?.textColor, '#f1f1f1')
check('inline compact namespace lookup bg', lookupStore(store, 'a', 'puyoucha')?.fillColor, '#e91e63')
check('inline colours do not make tag hidden', lookupStore(store, 'artist', 'puyoucha')?.hidden, false)
check('hasAny semantics remain MyTags-only for hide filtering', store.userIndex.size > 0, true)

const storeSource = readFileSync(new URL('../shared/src/main/ets/state/UserTagStore.ets', import.meta.url), 'utf8')
const apiSource = readFileSync(new URL('../shared/src/main/ets/network/EhApiService.ets', import.meta.url), 'utf8')
const contextSource = readFileSync(new URL('../shared/src/main/ets/services/UserTagContextService.ets', import.meta.url), 'utf8')
check('source uses raw canonical tag text', /EhConstants\.canonicalTagText\((t|tag)\.tag\)/.test(storeSource), true)
check('source indexes expanded namespace alias', /EhConstants\.expandNamespace\(ns\)/.test(storeSource), true)
check('source indexes compact namespace alias', /EhConstants\.compactNamespace\(ns\)/.test(storeSource), true)
check('source lookup never reads translated display fields', /\.translate|\.display/.test(storeSource), false)
check('source keeps inline colour fallback index', /private inlineIndex: Map<string, EhUsertag>/.test(storeSource), true)
check('source ingests inline SimpleTag colours', /ingestInlineTags\(tags: SimpleTag\[\]\)/.test(storeSource), true)
check('network registers inline list tag colours after parse for its initiating context', /registerInlineTagColors\(\s*await EhGalleryListParseTask\.parse\(resp\.body\),\s*userTagRequest,\s*\)/.test(apiSource), true)
check('inline fallback writes require the initiating scope to remain current', /static ingestInlineTags\(request: UserTagRequestContext, tags: SimpleTag\[\]\): boolean\s*\{\s*if \(!UserTagContextService\.isCurrentScope\(request\)\)/.test(contextSource), true)

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`)
  process.exit(1)
}
console.log('\nusertag enrich contract: all checks passed')
