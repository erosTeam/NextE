#!/usr/bin/env node
/**
 * Contract for the gallery torrent list lane.
 *
 * Run: node scripts/test_gallery_torrents_contract.mjs
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

let failures = 0
function ok(cond, label, detail = '') {
  if (!cond) {
    failures++
    console.error(`  ✗ ${label}`)
    if (detail) console.error(`    ${detail}`)
  }
}
function eq(actual, expected, label) {
  try {
    assert.deepEqual(actual, expected)
  } catch {
    failures++
    console.error(`  ✗ ${label}`)
    console.error(`    expected: ${JSON.stringify(expected)}`)
    console.error(`    actual:   ${JSON.stringify(actual)}`)
  }
}

console.log('— gallery torrents contract —')

const parserSrc = read('shared/src/main/ets/parser/EhGalleryTorrentParser.ets')
const routeSrc = read('shared/src/main/ets/model/RouteParams.ets')
const apiSrc = read('shared/src/main/ets/network/EhApiService.ets')
const constantsSrc = read('shared/src/main/ets/constants/EhConstants.ets')
const entrySrc = read('entry/src/main/ets/pages/Index.ets')
const detailSrc = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const pageSrc = read('feature/gallery/src/main/ets/pages/GalleryTorrentsPage.ets')
const galleryIndexSrc = read('feature/gallery/src/main/ets/Index.ets')
const sharedIndexSrc = read('shared/src/main/ets/Index.ets')

ok(/export class EhGalleryTorrent/.test(read('shared/src/main/ets/model/EhGalleryTorrent.ets')), 'torrent row model exists')
ok(/export class EhGalleryTorrentList/.test(read('shared/src/main/ets/model/EhGalleryTorrent.ets')), 'torrent list model exists')
ok(/export class EhGalleryTorrentParser/.test(parserSrc), 'torrent parser exists')
ok(/RE_TOKEN[\s\S]*\?:get\|torrent/.test(parserSrc), 'parser extracts ehtracker token from /get|torrent/<token>/ links')
ok(/RE_HASH[\s\S]*\[0-9a-f\]\{40\}/.test(parserSrc), 'parser extracts 40-char torrent hash')
ok(/labelValue\(form, 'Posted'\)/.test(parserSrc), 'parser extracts Posted')
ok(/labelValue\(form, 'Seeds'\)/.test(parserSrc), 'parser extracts Seeds')
ok(/labelValue\(form, 'Peers'\)/.test(parserSrc), 'parser extracts Peers')
ok(/labelValue\(form, 'Downloads'\)/.test(parserSrc), 'parser extracts Downloads')
ok(/HtmlSelectorUtils\.htmlUnescape/.test(parserSrc), 'parser unescapes torrent names')

ok(/EH_TORRENT_URL:\s*string\s*=\s*'https:\/\/ehtracker\.org\/get'/.test(constantsSrc), 'EH torrent base matches eros_fe')
ok(/EX_TORRENT_URL:\s*string\s*=\s*'https:\/\/exhentai\.org\/torrent'/.test(constantsSrc), 'EX torrent base matches eros_fe')
ok(/static torrentBaseUrl\(isEx: boolean\)/.test(constantsSrc), 'torrentBaseUrl(isEx) helper exists')

ok(/export class GalleryTorrentsParams/.test(routeSrc), 'GalleryTorrentsParams exists')
ok(/GalleryTorrentsParams/.test(sharedIndexSrc), 'shared barrel exports GalleryTorrentsParams')
ok(/EhGalleryTorrentParser/.test(sharedIndexSrc), 'shared barrel exports torrent parser')
ok(/EhGalleryTorrent, EhGalleryTorrentList/.test(sharedIndexSrc), 'shared barrel exports torrent models')

ok(/getGalleryTorrents\(gid: string, token: string, isEx: boolean\)/.test(apiSrc), 'EhApiService exposes getGalleryTorrents')
ok(/\/gallerytorrents\.php\?gid=\$\{gid\}&t=\$\{token\}/.test(apiSrc), 'API builds eros_fe gallerytorrents.php URL')
ok(/EhGalleryTorrentParser\.parse\(resp\.body\)/.test(apiSrc), 'API parses torrent response')

ok(/export \{ GalleryTorrentsPage \}/.test(galleryIndexSrc), 'gallery barrel exports GalleryTorrentsPage')
ok(/GalleryTorrentsPage/.test(entrySrc) && /name === 'GalleryTorrents'[\s\S]*?GalleryTorrentsPage\(\)/.test(entrySrc), 'entry registers GalleryTorrents route')
ok(/private openTorrents\(\): void/.test(detailSrc), 'detail page can open torrent route')
ok(/new GalleryTorrentsParams\([\s\S]*?this\.vm\.gallery\.torrentCount/.test(detailSrc), 'detail passes gid/token/site/title/count to torrent page')
ok(/Number\.parseInt\(this\.vm\.gallery\.torrentCount/.test(detailSrc), 'detail gates torrent entry on numeric count')
ok(/torrentTitle\(this\.vm\.gallery\.torrentCount\)/.test(detailSrc), 'detail shows count in torrent link')

ok(/getGalleryTorrents/.test(pageSrc), 'torrent page loads through EhApiService')
ok(/torrentBaseUrl\(this\.params\.isEx\).*\.torrent/.test(pageSrc), 'torrent page builds shareable .torrent URL')
ok(/magnet:\?xt=urn:btih/.test(pageSrc), 'torrent page builds magnet link')
ok(/ShareUtil\.shareUrl\(this\.ctx\(\), this\.torrentUrl/.test(pageSrc), 'torrent page shares torrent URL')
ok(/ShareUtil\.shareUrl\(this\.ctx\(\), this\.magnetUrl/.test(pageSrc), 'torrent page shares magnet URL')

const expectedKeys = [
  'gallery_torrents',
  'gallery_torrents_empty',
  'gallery_torrent_share_file',
  'gallery_torrent_share_magnet',
]
for (const locale of [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]) {
  const text = read(locale)
  for (const key of expectedKeys) {
    ok(text.includes(`"name": "${key}"`), `${locale} contains ${key}`)
  }
}

// Executable mirror of the parser contract on synthetic eros_fe-shaped HTML.
const html = `
<div id="torrentinfo"><div>
<form><div><table><tbody>
<tr><td><span>Posted:</span> <span>2026-06-18 01:02</span></td><td><span>Size:</span> 123.4 MiB</td><td></td><td><span>Seeds:</span> 9</td><td><span>Peers:</span> 2</td><td><span>Downloads:</span> 45</td></tr>
<tr><td><span>Uploader:</span> uploader&amp;name</td></tr>
<tr><td><a href="https://ehtracker.org/get/7654321/0123456789abcdef0123456789abcdef01234567.torrent">File &amp; Name.torrent</a></td></tr>
</tbody></table></div></form>
</div></div>`
const form = /<form\b[\s\S]*?<\/form>/g.exec(html)?.[0] ?? ''
const link = /<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/i.exec(form)
const hash = /([0-9a-f]{40})/i.exec(link?.[1] ?? '')?.[1]?.toLowerCase() ?? ''
const token = /\/(?:get|torrent)\/(\d+)\//i.exec(form)?.[1] ?? ''
const clean = (s) => unescape(s.replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim()
const label = (name) => {
  if (name === 'Uploader') {
    return clean(/Uploader:\s*(?:<\/span>)?\s*([^<]*)/i.exec(form)?.[1] ?? '')
  }
  const text = clean(form)
  const needle = `${name}:`
  const start = text.indexOf(needle)
  if (start < 0) return ''
  const from = start + needle.length
  const labels = ['Posted:', 'Size:', 'Seeds:', 'Peers:', 'Downloads:', 'Uploader:']
  let end = -1
  for (const l of labels) {
    const idx = text.indexOf(l, from)
    if (idx >= 0 && (end < 0 || idx < end)) end = idx
  }
  return text.slice(from, end >= 0 ? end : text.length).trim()
}
const unescape = (s) => s.replace(/&amp;/g, '&')
eq({
  token,
  hash,
  name: clean(link?.[2] ?? ''),
  posted: label('Posted'),
  sizeText: label('Size'),
  seeds: label('Seeds'),
  peers: label('Peers'),
  downloads: label('Downloads'),
  uploader: unescape(label('Uploader')),
}, {
  token: '7654321',
  hash: '0123456789abcdef0123456789abcdef01234567',
  name: 'File & Name.torrent',
  posted: '2026-06-18 01:02',
  sizeText: '123.4 MiB',
  seeds: '9',
  peers: '2',
  downloads: '45',
  uploader: 'uploader&name',
}, 'synthetic parser mirror extracts token/hash/display fields')

if (failures > 0) {
  console.error(`gallery torrents contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log('gallery torrents contract passed')
