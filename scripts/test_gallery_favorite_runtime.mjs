import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = fileURLToPath(new URL('../', import.meta.url))
const source = fs.readFileSync(path.join(root, 'feature/gallery/src/main/ets/pages/GalleryDetailPage.ets'), 'utf8')
const tagSource = fs.readFileSync(path.join(root, 'feature/gallery/src/main/ets/components/GalleryTagsCard.ets'), 'utf8')
const modelSource = fs.readFileSync(path.join(root, 'feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets'), 'utf8')
function between(text, first, last) {
  const start = text.indexOf(first), end = text.indexOf(last, start)
  assert.ok(start >= 0 && end > start)
  return text.slice(start, end)
}
const flow = between(source, '  private retireRemoteFavoriteEditor()', '  private isRemoteFavoriteSlotSelected(')
const titles = between(source, '  private remoteFavoriteTitleFor(', '  private remoteFavoriteStatusText(')
const noteSave = between(source, '  private canSubmitRemoteFavorite()', '  @Builder\n  private FullTitleSheet()')
const copy = between(tagSource, '  private selectedTagKey()', '  private triggerLongPressHaptic()')
const preserve = between(modelSource, '  private preserveNewerFavoriteState(', '  applyRatingResult(')
const slots = ['0', '1'].map(favId => ({ favId, favTitle: `Folder ${favId}`, totNum: 0 }))
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b }); return { promise, resolve, reject } }
function fixture(options = {}) {
  const calls = [], events = [], toasts = [], copies = []
  let current = true, persist = async () => {}
  const request = { isEx: false, memberId: 'fixture-member', generation: 0 }
  const context = { exports: {}, Color: { Red: 'red' }, DETAIL_SHEET_REMOTE_FAVORITE: source.match(/const DETAIL_SHEET_REMOTE_FAVORITE: string = '([^']+)'/)[1], $r: key => key, AppStrings: { get: key => key },
    ThemeConstants: { SPACE_SM: 8, ANIM_DURATION: 400 },
    UserTagContextService: { captureActiveRequest: () => request, isCurrentAuthenticated: ref => current && ref === request },
    EhErrorText: { forUser: error => error.message },
    FavcatListSettings: { persist: (...args) => persist(...args) },
    EhApiService: { getInstance: () => ({
      getGalleryFavoriteInfo: async (...args) => { calls.push({ read: args }); return options.read ? options.read() : { favcats: slots, selectFavcat: options.oldCat ?? '0', favNote: options.oldNote ?? 'old note' } },
      updateGalleryFavorite: async payload => { calls.push({ write: payload }); if (options.write) await options.write(payload) },
    }) },
    pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (type, text) => ({ type, text }), getSystemPasteboard: () => ({ setDataSync: data => { if (options.copyError) throw new Error('fixture copy failure'); copies.push(data) } }) },
  }
  vm.runInNewContext(ts.transpileModule(`class Subject { ${flow} ${titles} ${noteSave} }; class Tag { ${copy} }; class Model { ${preserve} }; exports.Subject=Subject; exports.Tag=Tag; exports.Model=Model;`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context)
  const p = new context.exports.Subject()
  Object.assign(p, { params: { gid: 'fixture-gallery', token: 'fixture-token' }, auth: { isLogin: true },
    detailDisposed: false, detailSheetShown: true, detailSheetKind: 'remoteFavorite', remoteFavoriteRequest: request,
    remoteFavoriteSheetEpoch: 1, remoteFavoriteDraftRevision: 0, remoteFavoriteSlotsReady: true,
    remoteFavoriteSlots: slots, remoteFavoriteLoadingFavcats: false, remoteFavoriteSubmitting: false, remoteFavoriteError: '',
    remoteFavoriteSelectedCat: options.oldCat ?? '0', remoteFavoriteNote: options.oldNote ?? 'old note', remoteFavoriteLoadedNote: options.oldNote ?? 'old note',
    favoriteSlotCache: { update: value => events.push({ slots: value }) },
    favoriteMutation: { publish: (...value) => events.push({ mutation: value }) },
    vm: { gallery: { favcat: options.oldCat ?? '0', favTitle: 'Folder 0', favNote: options.oldNote ?? 'old note' },
      applyRemoteFavoriteState: (cat, title, note) => { p.vm.gallery = { favcat: cat, favTitle: title, favNote: note }; events.push({ apply: cat }) },
      refresh: async () => { throw new Error('Full detail refresh must not be part of favorite submission') },
    }, ctx: () => ({}), closeDetailSheet: () => { p.detailSheetShown = false; events.push({ closed: true }) },
    getUIContext: () => ({ getPromptAction: () => ({ openToast: async data => { toasts.push(data.message) } }) }),
  })
  const tag = new context.exports.Tag(); tag.selectedNamespace = 'language'; tag.selectedTagText = 'english'; tag.selectedTagDisplay = '英语'; tag.getUIContext = p.getUIContext
  const model = new context.exports.Model(); model.favoriteRevision = 0
  model.gallery = { favcat: '0', favTitle: 'Folder 0', favNote: 'old note', copy() { return { ...this } } }
  model.saveCurrentDetailCache = () => events.push({ cached: true })
  return { p, tag, model, calls, events, toasts, copies, request, expire: () => { current = false }, setPersist: fn => { persist = fn } }
}
const drain = () => new Promise(resolve => setImmediate(resolve))
for (const [label, oldCat, nextCat] of [['add', '', '1'], ['move', '0', '1'], ['note', '0', '0'], ['remove', '0', 'favdel']]) {
  test(`${label}: a confirmed write updates state/cache signal once without a full detail refresh`, async () => {
    const f = fixture({ oldCat }); f.p.remoteFavoriteNote = '  edited note  '
    await f.p.submitRemoteFavorite(nextCat)
    assert.equal(f.calls.filter(x => x.write).length, 1)
    assert.equal(f.p.vm.gallery.favcat, nextCat === 'favdel' ? '' : nextCat)
    assert.equal(f.p.vm.gallery.favNote, nextCat === 'favdel' ? '' : 'edited note')
    assert.equal(f.events.filter(x => x.mutation).length, 1)
    assert.equal(f.events.filter(x => x.closed).length, 1)
  })
}
test('folder tap adds or moves; clicking the current folder removes once', async () => {
  const f = fixture(); f.p.selectRemoteFavorite(slots[0]); await drain()
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].write.favcat, 'favdel'); assert.equal(f.p.vm.gallery.favcat, '')
  const added = fixture({ oldCat: '' }); added.p.selectRemoteFavorite(slots[0]); await drain(); assert.equal(added.calls[0].write.favcat, '0')
  const moved = fixture(); moved.p.selectRemoteFavorite(slots[1]); await drain(); assert.equal(moved.calls[0].write.favcat, '1')
})
test('note-only confirmation saves the note without toggling the current folder', async () => {
  const f = fixture(); assert.equal(f.p.canSubmitRemoteFavorite(), false); f.p.remoteFavoriteNote = 'new note'
  assert.equal(f.p.canSubmitRemoteFavorite(), true); await f.p.submitRemoteFavorite()
  assert.equal(f.calls[0].write.favcat, '0'); assert.equal(f.calls[0].write.favnote, 'new note')
})
test('pending submission keeps the old state visible and blocks repeated taps', async () => {
  const reply = deferred(); const f = fixture({ write: () => reply.promise }); const pending = f.p.submitRemoteFavorite('1')
  assert.equal(f.p.vm.gallery.favcat, '0'); await f.p.submitRemoteFavorite('1'); assert.equal(f.calls.length, 1)
  reply.resolve(); await pending; assert.equal(f.p.vm.gallery.favcat, '1')
})
for (const reason of ['HTTP 429', 'HTTP 503', 'lost response']) {
  test(`${reason}: failure retains the open sheet and edited note, with no retry or success mutation`, async () => {
    const f = fixture({ write: async () => { throw new Error(reason) } }); f.p.remoteFavoriteNote = 'keep this draft'
    await f.p.submitRemoteFavorite('1'); assert.equal(f.calls.length, 1); assert.equal(f.p.vm.gallery.favcat, '0')
    assert.equal(f.p.detailSheetShown, true); assert.equal(f.p.remoteFavoriteNote, 'keep this draft')
    assert.equal(f.events.filter(x => x.mutation).length, 0); assert.equal(f.p.remoteFavoriteError, reason)
  })
}
test('repeat-tap removal is single-flight and stale editors cannot remove', async () => {
  const reply = deferred(); const f = fixture({ write: () => reply.promise })
  f.p.selectRemoteFavorite(slots[0]); f.p.selectRemoteFavorite(slots[0]); assert.equal(f.calls.length, 1)
  assert.equal(f.p.vm.gallery.favcat, '0'); reply.resolve(); await drain(); assert.equal(f.p.vm.gallery.favcat, '')
  const expired = fixture(); expired.expire(); expired.p.selectRemoteFavorite(slots[0]); await drain(); assert.equal(expired.calls.length, 0)
})
test('failed repeat-tap removal preserves the category and note draft without retry', async () => {
  const f = fixture({ write: async () => { throw new Error('HTTP 429') } }); f.p.remoteFavoriteNote = 'keep draft'
  f.p.selectRemoteFavorite(slots[0]); await drain()
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].write.favcat, 'favdel')
  assert.equal(f.p.vm.gallery.favcat, '0'); assert.equal(f.p.remoteFavoriteNote, 'keep draft')
  assert.equal(f.p.detailSheetShown, true); assert.equal(f.events.filter(x => x.mutation).length, 0)
})
test('late folder data preserves note edits and does not enable writes before folder loading completes', async () => {
  const reply = deferred(); const f = fixture({ read: () => reply.promise }); f.p.remoteFavoriteSlotsReady = false
  const pending = f.p.refreshRemoteFavcats(); f.p.remoteFavoriteNote = 'user draft'; f.p.remoteFavoriteDraftRevision++
  f.p.selectRemoteFavorite(slots[1]); assert.equal(f.calls.filter(x => x.write).length, 0)
  reply.resolve({ favcats: slots, selectFavcat: '0', favNote: 'server note' }); await pending
  assert.equal(f.p.remoteFavoriteNote, 'user draft'); assert.equal(f.p.remoteFavoriteLoadedNote, 'server note'); assert.equal(f.p.remoteFavoriteSlotsReady, true)
})
test('account/site retirement, dismissal and Preferences awaits reject stale popup responses', async () => {
  for (const boundary of ['scope', 'dismiss', 'preferences']) {
    const reply = deferred(); const persist = deferred(); const f = fixture({ read: () => reply.promise })
    if (boundary === 'preferences') f.setPersist(() => persist.promise)
    const pending = f.p.refreshRemoteFavcats()
    if (boundary === 'scope') f.expire()
    if (boundary === 'dismiss') { f.p.remoteFavoriteSheetEpoch++; f.p.remoteFavoriteRequest = null }
    reply.resolve({ favcats: slots, selectFavcat: '1', favNote: 'stale note' })
    if (boundary === 'preferences') { await drain(); f.expire(); persist.resolve() }
    await pending; assert.equal(f.p.remoteFavoriteNote, 'old note'); assert.equal(f.events.filter(x => x.apply).length, 0)
  }
})
test('late write after a scope transition cannot change the new account or publish a mutation', async () => {
  const reply = deferred(); const f = fixture({ write: () => reply.promise }); const pending = f.p.submitRemoteFavorite('1')
  f.expire(); reply.resolve(); await pending; assert.equal(f.p.vm.gallery.favcat, '0'); assert.equal(f.events.length, 0)
})
test('a confirmed write after dismissal still updates the cache/state without closing another sheet', async () => {
  const reply = deferred(); const f = fixture({ write: () => reply.promise }); const pending = f.p.submitRemoteFavorite('1')
  f.p.detailDisposed = true; reply.resolve(); await pending; assert.equal(f.p.vm.gallery.favcat, '1'); assert.equal(f.events.filter(x => x.mutation).length, 1); assert.equal(f.toasts.length, 0)
})
test('a detail response started before a confirmed mutation cannot overwrite its folder, note or removal', () => {
  for (const cat of ['1', '']) {
    const f = fixture(); const run = { favoriteRevision: 0 }; f.model.applyRemoteFavoriteState(cat, 'new folder', 'new note')
    const response = { favcat: '0', favTitle: 'old folder', favNote: 'old note' }; f.model.preserveNewerFavoriteState(response, run)
    assert.equal(response.favcat, cat); assert.equal(response.favNote, 'new note'); assert.equal(f.events.filter(x => x.cached).length, 1)
  }
})
test('copy writes the original namespaced tag and reports success or failure accurately', () => {
  const f = fixture(); f.tag.copySelectedTag(); assert.equal(f.copies[0].text, 'language:english'); assert.equal(f.toasts[0], 'app.string.tag_info_copied')
  const failed = fixture({ copyError: true }); failed.tag.copySelectedTag(); assert.equal(failed.copies.length, 0); assert.equal(failed.toasts[0], 'app.string.tag_info_copy_failed')
})
