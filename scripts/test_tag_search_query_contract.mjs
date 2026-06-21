#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const constants = read('shared/src/main/ets/constants/EhConstants.ets')
const list = read('shared/src/main/ets/components/GalleryCard.ets')
const waterfall = read('shared/src/main/ets/components/GalleryWaterfallCard.ets')
const detailTags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const searchPage = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')

assert.match(constants, /static canonicalTagText\(tag: string\): string \{[\s\S]*raw\.indexOf\('\|'\)[\s\S]*raw\.substring\(0, pipe\)\.trim\(\)/)
assert.match(constants, /static exactTagSearchQuery\(namespace: string, tag: string\): string \{[\s\S]*EhConstants\.compactNamespace\(namespace\)[\s\S]*EhConstants\.canonicalTagText\(tag\)[\s\S]*ns === 'uploader'[\s\S]*return `\$\{ns\}:"\$\{text\}"`[\s\S]*return `\$\{ns\}:"\$\{text\}\$"`/)

for (const [name, src, call] of [
  ['GalleryCard', list, 't.namespace, t.text'],
  ['GalleryWaterfallCard', waterfall, 't.namespace, t.text'],
  ['GalleryTagsCard', detailTags, 'ns, t.text'],
  ['GallerySearchPage suggestions', searchPage, 's.namespace, s.text'],
]) {
  assert.ok(src.includes(`EhConstants.exactTagSearchQuery(${call})`), `${name} uses shared exact tag helper`)
}

// Mirror the tiny helper so the contract documents the intended EH query shape.
const canonical = (tag) => {
  const raw = tag.trim()
  const pipe = raw.indexOf('|')
  return pipe >= 0 ? raw.substring(0, pipe).trim() : raw
}
const compact = (ns) => ({ female: 'f', artist: 'a', uploader: 'uploader' }[ns.trim().toLowerCase()] || ns.trim().toLowerCase())
const query = (ns, tag) => {
  const n = compact(ns)
  const t = canonical(tag)
  return n === 'uploader' ? `${n}:"${t}"` : `${n}:"${t}$"`
}

assert.equal(query('female', 'big breasts'), 'f:"big breasts$"')
assert.equal(query('artist', 'foo | bar'), 'a:"foo$"')
assert.equal(query('uploader', 'name'), 'uploader:"name"')

console.log('✓ tag search query contract: pipe aliases normalize and EH tag searches use exact $ semantics')
