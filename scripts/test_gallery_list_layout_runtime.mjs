import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const studio = process.env.DEVECO_STUDIO_APP ?? '/Applications/DevEco-Studio.app'
const ts = require(process.env.TYPESCRIPT_PATH ?? path.join(studio, 'Contents/tools/hvigor/hvigor/node_modules/typescript'))
const root = fileURLToPath(new URL('../', import.meta.url))
const modules = new Map()
function actual(relative) {
  const filename = path.resolve(root, relative)
  if (modules.has(filename)) return modules.get(filename)
  const exports = {}
  modules.set(filename, exports)
  const source = fs.readFileSync(filename, 'utf8')
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, { exports, require: name => {
    assert.ok(name.startsWith('.'), `Unexpected platform dependency: ${name}`)
    return actual(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)))
  } }, { filename })
  return exports
}
const { EhConstants } = actual('shared/src/main/ets/constants/EhConstants.ets')
const { EhGalleryListParser } = actual('shared/src/main/ets/parser/EhGalleryListParser.ets')
const errors = actual('shared/src/main/ets/network/EhError.ets')
const classifier = actual('shared/src/main/ets/network/EhErrorClassifier.ets')
const favcats = actual('shared/src/main/ets/parser/EhFavcatListParser.ets')
const apiSource = fs.readFileSync(path.join(root, 'shared/src/main/ets/network/EhApiService.ets'), 'utf8')

// Neutral synthetic HTML models the relevant EH structures; it is not a captured issue #13 page.
const modeControl = mode => '<div id="dms"><select>' + ['m', 'p', 'l', 'e', 't'].map(value =>
  `<option value="${value}"${value === mode ? ' selected' : ''}>${value}</option>`).join('') + '</select></div>'
const orderControl = order => '<select>' + ['f', 'p'].map(value =>
  `<option value="${value}"${value === order ? ' selected' : ''}>${value}</option>`).join('') + '</select>'
const galleryUrl = id => `https://exhentai.org/g/${id}/a1b2/`
const imageUrl = id => `https://s.exhentai.org/fixture-${id}.jpg`
const compactRow = id => `<tr><td class="gl1c glcat"><div class="cn ct2">Doujinshi</div></td>` +
  `<td class="gl2c"><div class="glthumb"><div><img ${id === 111 ? `src="${imageUrl(id)}"` : `src="data:image/gif;base64,fixture" data-src="${imageUrl(id)}"`} style="height:250px;width:200px"></div></div></td>` +
  `<td class="gl3c glname"><a href="${galleryUrl(id)}"><div class="glink">Neutral fixture ${id}</div></a></td></tr>`
const body = (mode, order = '') => modeControl(mode) + (order ? orderControl(order) : '') + (
  mode === 'l' ? `<table class="itg gltc">${[111, 222].map(compactRow).join('')}</table>` :
  mode === 'e' ? `<table class="itg glte">${[111, 222].map(id => `<tr><td class="gl1e"><img src="${imageUrl(id)}"></td><td class="gl2e"><a href="${galleryUrl(id)}"><div class="glink">Neutral fixture ${id}</div></a><table><tr><td>language:english</td></tr></table></td></tr>`).join('')}</table>` :
  (mode === 'm' || mode === 'p') ? '<table class="itg gltm"><tr><td>Minimal fixture</td></tr></table>' :
  '<div class="itg gld"><div>Thumbnail fixture</div></div>')
const compact = body('l')
const query = { isEx: true, source: '', next: '', prev: '', seek: '', tl: 11, page: -1,
  fCats: 0, search: '', advancedEnabled: false, minRating: 0, pagesFrom: 0, pagesTo: 0,
  requireTorrent: false, showExpunged: false, disableLanguageFilter: false,
  disableUploaderFilter: false, disableTagFilter: false, applyToplistHiddenUserTags: false }
const favorites = { isEx: true, favcat: 'a', next: '', prev: '', seek: '', page: -1, from: '', search: '', order: '' }
function fixture(reply, profileReady = true) {
  const calls = []
  let currentScope = true
  const get = async (url, once) => {
    calls.push({ url, once })
    const response = await reply(url, calls.length, { expireScope: () => { currentScope = false } })
    return typeof response === 'string' ? { statusCode: 200, body: response } : response
  }
  const context = { exports: {}, require: name => {
    if (name === './EhHttpClient') return { EhHttpClient: { getInstance: () => ({
      getText: url => get(url, false), getTextOnce: url => get(url, true),
    }) } }
    if (name === '../services/EhAppProfileService') return { EhAppProfileService: { ensureSelected: async () => profileReady, listFailure: () => new errors.EhError(errors.EhErrorKind.RateLimited, 'fixture profile rate limit') } }
    if (name === './EhError') return errors
    if (name === './EhErrorClassifier') return classifier
    if (name === '../constants/EhConstants') return { EhConstants }
    if (name === '../parser/EhGalleryListParser') return { EhGalleryListParser }
    if (name === '../parser/EhGalleryListParseTask') return { EhGalleryListParseTask: { parse: async html => EhGalleryListParser.parse(html) } }
    if (name === '../parser/EhFavcatListParser') return favcats
    if (name === '../services/UserTagContextService') return { UserTagContextService: {
      captureActiveRequest: () => ({}), isCurrentScope: () => currentScope,
    } }
    return {}
  } }
  vm.runInNewContext(ts.transpileModule(apiSource, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, context)
  const api = context.exports.EhApiService.getInstance()
  // Isolate transport/layout parsing from independent local filtering and tag-color caches.
  api.filterHidden = list => list
  api.filterLocalBlocked = list => list
  api.registerInlineTagColors = list => list
  return { api, calls }
}
function assertTwoCovers(list) {
  assert.deepEqual(Array.from(list.gallerys, gallery => gallery.gid), ['111', '222'])
  assert.deepEqual(Array.from(list.gallerys, gallery => gallery.thumbUrl), [imageUrl(111), imageUrl(222)])
}

for (const mode of ['m', 'p', 'e', 't']) {
  test(`selected ${mode} is normalized for all gallery routes and favorites`, async () => {
    for (const source of ['', 'watched', 'popular', 'toplist', 'favorites']) {
      const { api, calls } = fixture(url => new URL(url).searchParams.get('inline_set') === 'dm_l' ? compact : body(mode))
      const list = source === 'favorites' ? await api.getFavoritesList(favorites) : await api.getGalleryList({ ...query, source })
      assertTwoCovers(list)
      assert.equal(calls.length, 2, source)
      assert.deepEqual(calls.map(call => call.once), [false, true])
      const first = new URL(calls[0].url)
      const corrected = new URL(calls[1].url)
      assert.equal(corrected.searchParams.get('inline_set'), 'dm_l')
      corrected.searchParams.delete('inline_set')
      assert.equal(corrected.href, first.href)
      assert.equal(first.hostname, source === 'toplist' ? 'e-hentai.org' : 'exhentai.org')
    }
  })
}

test('search, filters, cursor/date and favorites page/from survive correction', async () => {
  const { api, calls } = fixture((url, number) => number % 2 === 0 ? compact : body('e'))
  await api.getGalleryList({ ...query, search: 'language:chinese 测试', fCats: 7, next: '111', seek: '2026-10-01',
    advancedEnabled: true, minRating: 3, pagesFrom: 12, pagesTo: 100, requireTorrent: true,
    showExpunged: true, disableLanguageFilter: true, disableUploaderFilter: true, disableTagFilter: true })
  const first = new URL(calls[0].url)
  const corrected = new URL(calls[1].url)
  for (const [key, value] of first.searchParams) assert.equal(corrected.searchParams.get(key), value, key)
  assert.equal(corrected.searchParams.get('f_search'), 'language:chinese 测试')
  assert.equal(corrected.searchParams.get('next'), '111')
  assert.equal(corrected.searchParams.get('seek'), '2026-10-01')
  assert.equal(corrected.searchParams.get('advsearch'), '1')
  assert.equal(corrected.searchParams.get('f_cats'), '7')
  await api.getFavoritesList({ ...favorites, favcat: '3', search: '测试', page: 2, from: '222' })
  const favFirst = new URL(calls[2].url)
  const favCorrected = new URL(calls[3].url)
  for (const [key, value] of favFirst.searchParams) assert.equal(favCorrected.searchParams.get(key), value, key)
  assert.equal(favCorrected.searchParams.get('page'), '2')
  assert.equal(favCorrected.searchParams.get('from'), '222')
  assert.equal(favCorrected.searchParams.get('favcat'), '3')
})

test('Compact and legitimate empty searches do not write preferences', async () => {
  for (const html of [compact + orderControl('f'), '<p>No hits found</p>', modeControl('l') + '<p>No matching galleries</p>']) {
    const { api, calls } = fixture(() => html)
    const list = await api.getGalleryList(query)
    assert.equal(calls.length, 1)
    assert.equal(calls[0].once, false)
    assert.equal(list.gallerys.length, html.startsWith(modeControl('l')) && html.includes('glthumb') ? 2 : 0)
  }
})

test('display detection tolerates option attribute order and quoting, and distinguishes sorting', () => {
  for (const selected of ['value="e" selected', "selected='selected' value='e'", 'selected value=e', 'VALUE="E" SELECTED=""']) {
    const html = `<select><option value="l">Compact</option><option ${selected}>Extended</option></select>`
    assert.equal(EhGalleryListParser.needsCompactLayout(html), true, selected)
  }
  assert.equal(EhGalleryListParser.needsCompactLayout(orderControl('f') + compact), false)
  assert.equal(EhGalleryListParser.needsCompactLayout('<p>No matching galleries</p>'), false)
  assert.equal(EhGalleryListParser.needsCompactLayout('<table class="unknown"></table>'), false)
  for (const classes of ['itg gltm', 'glte itg', 'gld itg extra']) {
    assert.equal(EhGalleryListParser.needsCompactLayout(`<div class='${classes}'></div>`), true, classes)
  }
})

test('still-unsupported response fails once instead of returning truncated rows or retrying indefinitely', async () => {
  const { api, calls } = fixture(() => body('e'))
  await assert.rejects(api.getGalleryList(query), error => error.kind === errors.EhErrorKind.ParseFailure)
  assert.deepEqual(calls.map(call => call.once), [false, true])
})

for (const status of [429, 503]) {
  test(`preference correction HTTP ${status} is classified and uses a single attempt`, async () => {
    const { api, calls } = fixture((url, count) => count === 1 ? body('e') : { statusCode: status, body: 'fixture failure' })
    await assert.rejects(api.getGalleryList(query), error => error.kind === (status === 429 ? errors.EhErrorKind.RateLimited : errors.EhErrorKind.ServerError))
    assert.deepEqual(calls.map(call => call.once), [false, true])
  })
}

test('lost correction response remains a network failure and is not replayed', async () => {
  const { api, calls } = fixture((url, count) => {
    if (count === 1) return body('t')
    throw new Error('fixture lost response')
  })
  await assert.rejects(api.getGalleryList(query), error => error.kind === errors.EhErrorKind.Network)
  assert.deepEqual(calls.map(call => call.once), [false, true])
})

test('account/site transition while reading prevents layout or sort preference writes', async () => {
  for (const isFavorites of [false, true]) {
    const { api, calls } = fixture((url, count, context) => {
      context.expireScope()
      return isFavorites ? body('l', 'p') : body('e')
    })
    const result = isFavorites ? api.getFavoritesList({ ...favorites, order: 'fs_f' }) : api.getGalleryList(query)
    await assert.rejects(result, error => error.kind === errors.EhErrorKind.Network)
    assert.equal(calls.length, 1)
    assert.equal(new URL(calls[0].url).searchParams.has('inline_set'), false)
  }
})

test('favorites sorting and layout correction each send once, preserve filters and avoid duplicate inline_set', async () => {
  const { api, calls } = fixture((url, count) => count === 1 ? body('l', 'p') : count === 2 ? body('e', 'f') : body('l', 'f'))
  const list = await api.getFavoritesList({ ...favorites, order: 'fs_f', search: '测试', favcat: '4', seek: '2026-10-01' })
  assertTwoCovers(list)
  assert.equal(list.favOrder, 'fs_f')
  assert.deepEqual(calls.map(call => call.once), [false, true, true])
  assert.deepEqual(calls.map(call => new URL(call.url).searchParams.get('inline_set')), [null, 'fs_f', 'dm_l'])
  for (const call of calls) {
    const params = new URL(call.url).searchParams
    assert.ok(params.getAll('inline_set').length <= 1)
    assert.equal(params.get('favcat'), '4')
    assert.equal(params.get('f_search'), '测试')
    assert.equal(params.get('seek'), '2026-10-01')
  }
})


test('profile failure keeps its typed cause and sends no gallery or preference request', async () => {
  const { api, calls } = fixture(() => compact, false)
  await assert.rejects(api.getGalleryList(query), error => error.kind === errors.EhErrorKind.RateLimited)
  assert.equal(calls.length, 0)
})
