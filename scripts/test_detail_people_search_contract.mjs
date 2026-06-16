#!/usr/bin/env node
/**
 * Contract test for "tap a person → search their uploads" on the detail surface:
 *   shared/src/main/ets/state/SearchActionState.ets   (publishQuery: token-prefixed bus payload)
 *   feature/gallery/.../components/GalleryHeaderCard.ets   (uploader onClick → onUploader)
 *   feature/gallery/.../components/GalleryCommentsCard.ets  (author onClick → onAuthor)
 *   feature/gallery/.../pages/GalleryDetailPage.ets         (searchUploader / openSimilar via publishQuery)
 *   feature/gallery/.../pages/GalleryCommentsPage.ets       (full-page author tap)
 *
 * The functions below are copy-equal to that logic (no UI/nav — pure bus payload round-trip):
 *   • publishQuery prefixes a unique numeric token so the bus refires for a repeated query.
 *   • consumers strip the token at the FIRST ':' — the token has no colon, so colons INSIDE the
 *     query (`uploader:foo`, `title:"a:b"`) survive intact.
 *   • uploader search is eros_fe's namespaced search, QUOTED — `uploader:"<name>"` (trimmed) — so a
 *     multi-word username matches exactly instead of tokenizing into separate terms.
 * If the .ets logic changes, mirror it here.
 *
 * Run: node scripts/test_detail_people_search_contract.mjs   (exit 1 on any failure)
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// Mirror of SearchActionState.publishQuery (token = Date.now(); here a fixed digit string).
const TOKEN = '1718000000000'
const publishQuery = (query) => `${TOKEN}:${query}`
// Mirror of the consumer strip (Index.handlePendingEhUrl / GallerySearchPage.consumePendingQuery).
const stripToken = (pq) => {
  const sep = pq.indexOf(':')
  return sep >= 0 ? pq.substring(sep + 1) : pq
}
// Mirror of GalleryDetailPage.searchUploader / GalleryCommentsPage.searchUploader (QUOTED, eros_fe).
const uploaderQuery = (name) => {
  const n = name.trim()
  return n.length === 0 ? null : `uploader:"${n}"`
}
// Mirror of openSimilar.
const similarQuery = (short) => (short.length === 0 ? null : `title:"${short}"`)

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

// 1. uploader round-trip: publish → strip recovers exactly the QUOTED `uploader:"<name>"`
{
  ok('uploader recovered+quoted', stripToken(publishQuery(uploaderQuery('Foo'))) === 'uploader:"Foo"')
  ok('uploader trimmed', stripToken(publishQuery(uploaderQuery('  Bar  '))) === 'uploader:"Bar"')
  // the parity fix: a multi-word username is quoted so EH matches it exactly (not John + Doe).
  ok('multi-word uploader quoted', uploaderQuery('John Doe') === 'uploader:"John Doe"')
  ok('uploader with spaces preserved', stripToken(publishQuery(uploaderQuery('Some User'))) === 'uploader:"Some User"')
  ok('empty uploader → no query', uploaderQuery('   ') === null)
}

// 2. colons inside the query survive the first-colon token strip
{
  ok('title with quotes+colon survives', stripToken(publishQuery(similarQuery('a:b c'))) === 'title:"a:b c"')
  ok('uploader name containing colon survives', stripToken(publishQuery(uploaderQuery('odd:name'))) === 'uploader:"odd:name"')
}

// 3. token format: numeric prefix + ':' so a repeated query still refires (different token → different payload)
{
  const p = publishQuery('uploader:X')
  ok('payload is <digits>:<query>', /^\d+:uploader:X$/.test(p))
  // a different token (later Date.now) yields a different string for the SAME query
  ok('distinct token → distinct payload', `1718000000001:uploader:X` !== p)
  ok('same query recovered regardless of token', stripToken(`999:uploader:X`) === 'uploader:X')
}

// 4. similar (title) query unchanged by the refactor to publishQuery
{
  ok('similar builds title quote', similarQuery('My Title') === 'title:"My Title"')
  ok('empty short → no similar', similarQuery('') === null)
}

// 5. structural: the wiring exists across all five files
{
  const read = (p) => readFileSync(join(ROOT, p), 'utf8')
  const state = read('shared/src/main/ets/state/SearchActionState.ets')
  ok('SearchActionState.publishQuery exists', /publishQuery\(query: string\): void/.test(state))
  ok('publishQuery prefixes a token', /this\.pendingQuery = `\$\{Date\.now\(\)\}:\$\{query\}`/.test(state))

  const header = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')
  ok('header has onUploader event', /@Event onUploader: \(name: string\) => void/.test(header))
  ok('header uploader is tappable', /this\.onUploader\(this\.gallery\.uploader\)/.test(header))

  const card = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
  ok('comments card has onAuthor event', /@Event onAuthor: \(name: string\) => void/.test(card))
  ok('comment author is tappable', /this\.onAuthor\(c\.author\)/.test(card))

  const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
  ok('detail has searchUploader', /searchUploader\(name: string\)/.test(detail))
  ok('detail uploader search is quoted', /publishQuery\(`uploader:"\$\{n\}"`\)/.test(detail))
  ok('openSimilar uses publishQuery (quoted title)', /publishQuery\(`title:"\$\{short\}"`\)/.test(detail))
  ok('detail wires header onUploader', /onUploader: \(name: string\) =>/.test(detail))
  ok('detail wires comment onAuthor', /onAuthor: \(name: string\) =>/.test(detail))

  const page = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
  ok('comments page has searchUploader', /searchUploader\(name: string\)/.test(page))
  ok('comments page uploader search is quoted', /publishQuery\(`uploader:"\$\{n\}"`\)/.test(page))
  ok('comments page wires onAuthor', /onAuthor: \(name: string\) =>/.test(page))
}

console.log(`✓ detail people-search contract: ${passed} assertions passed`)
