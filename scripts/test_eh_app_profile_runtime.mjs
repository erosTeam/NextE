import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)
const ts = require(process.env.TYPESCRIPT_PATH ?? `${process.env.DEVECO_STUDIO_APP ?? '/Applications/DevEco-Studio.app'}/Contents/tools/hvigor/hvigor/node_modules/typescript`)
const read = file => fs.readFileSync(new URL(`../shared/src/main/ets/${file}.ets`, import.meta.url), 'utf8')
const compile = (source, imports = {}) => {
  const context = { exports: {}, require: name => imports[name] ?? {} }
  vm.runInNewContext(ts.transpileModule(source.replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, ''), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText, context)
  return context.exports
}
const model = compile(read('model/EhProfileSettings'))
const errors = compile(read('network/EhError'))
function config(selected = 1, includeApp = true) {
  const out = new model.EhProfileSettings()
  out.profiles = [new model.EhProfile('Original', 1, selected === 1, true)]
  if (includeApp) out.profiles.push(new model.EhProfile('NextE', 2, selected === 2, false))
  out.selectedProfile = selected
  out.defaultProfile = 1
  return out
}
const scope = (memberId = 'fixture-account', isEx = false, generation = 1) => ({ memberId, passHash: 'fixture-secret', isEx, generation })
function fixture(options = {}) {
  let active = scope()
  let enabled = options.enabled ?? true
  let loggedIn = options.loggedIn ?? true
  const calls = []
  const persisted = []
  const settings = { revision: 1 }
  const serviceImports = {
    '../network/EhError': errors,
    '../network/EhCookieStore': { EhCookieStore: { getInstance: () => ({ isLogin: () => loggedIn }) } },
    '../state/EhAppProfileState': { connectEhAppProfile: () => ({ enabled }) },
    '../settings/EhAppProfileSettings': { EhAppProfileSettings: settings },
    '../diagnostics/DiagnosticLogger': { DiagnosticLogger: { info() {}, warn() {} } },
    './UserTagContextService': { UserTagContextService: {
      captureActiveRequest: () => ({ ...active }),
      isCurrentAuthenticated: request => loggedIn && ['memberId', 'passHash', 'isEx', 'generation'].every(key => request[key] === active[key]),
    }, UserTagRequestFence: { sameScope: (a, b) => ['memberId', 'passHash', 'isEx'].every(key => a[key] === b[key]) } },
    '../network/EhApiService': { EhApiService: { getInstance: () => ({
      async getUserConfig(isEx) { calls.push({ kind: 'read', isEx }); return options.read ? options.read(calls, control) : config() },
      async postProfileAction(isEx, action, profileSet, name) {
        calls.push({ kind: 'write', isEx, action, profileSet, name })
        return options.write ? options.write(calls, control) : config(2)
      },
    }) } },
    '../settings/CookieJarSettings': { CookieJarSettings: { async persistServerSelectedProfile(ctx, member, pass, isEx, id, fence) {
      if (options.beforePersist) await options.beforePersist(control)
      if (!fence()) return false
      if (options.persistFails) return false
      persisted.push({ member, isEx, id })
      return true
    } } },
  }
  const control = { setScope: value => { active = value }, disable: () => { enabled = false; settings.revision++ },
    changeRevision: () => settings.revision++, logout: () => { loggedIn = false } }
  const { EhAppProfileService: service } = compile(read('services/EhAppProfileService'), serviceImports)
  if (!options.uninitialized) service.initialize({})
  return { service, calls, persisted, ...control }
}

test('disabled, logged-out and uninitialized paths make no remote requests', async () => {
  for (const options of [{ enabled: false }, { loggedIn: false }, { uninitialized: true }]) {
    const f = fixture(options)
    assert.equal(await f.service.ensureSelected(), true)
    assert.equal(f.calls.length, 0)
  }
})
test('existing NextE is selected once and the website default stays unchanged', async () => {
  const f = fixture()
  assert.equal(await f.service.ensureSelected(), true)
  assert.deepEqual(f.calls, [{ kind: 'read', isEx: false }, { kind: 'write', isEx: false, action: '', profileSet: '2', name: '' }])
  assert.deepEqual(f.persisted, [{ member: 'fixture-account', isEx: false, id: '2' }])
  assert.equal(await f.service.ensureSelected(), true)
  assert.equal(f.calls.length, 2)
  assert.ok(f.calls.every(call => call.action !== 'default'))
})
test('already selected NextE only reads and persists the server-confirmed ID', async () => {
  const f = fixture({ read: () => config(2) })
  assert.equal(await f.service.ensureSelected(), true)
  assert.equal(f.calls.length, 1)
  assert.equal(f.persisted[0].id, '2')
})
test('absent NextE is created once and its confirmed selection is persisted', async () => {
  const f = fixture({ read: () => config(1, false) })
  assert.equal(await f.service.ensureSelected(), true)
  assert.deepEqual(f.calls[1], { kind: 'write', isEx: false, action: 'create', profileSet: '', name: 'NextE' })
  assert.equal(f.persisted[0].id, '2')
})
test('empty or duplicate profile lists do not create or choose an arbitrary profile', async () => {
  for (const mode of ['empty', 'duplicate']) {
    const f = fixture({ read: () => { const c = config(); if (mode === 'empty') c.profiles = []; else c.profiles.push(new model.EhProfile('NextE', 3, false, false)); return c } })
    assert.equal(await f.service.ensureSelected(), false)
    assert.equal(f.calls.length, 1)
    assert.equal(f.persisted.length, 0)
  }
})
test('concurrent callers share one successful or failed preparation', async () => {
  for (const fails of [false, true]) {
    let release
    const wait = new Promise(resolve => { release = resolve })
    const f = fixture({ read: async () => { await wait; if (fails) throw new Error('fixture read failed'); return config(2) } })
    const results = [f.service.ensureSelected(), f.service.ensureSelected(), f.service.ensureSelected()]
    release()
    assert.deepEqual(await Promise.all(results), [!fails, !fails, !fails])
    assert.equal(f.calls.length, 1)
  }
})
test('lost create response is read back; confirmed success is accepted without replay', async () => {
  let reads = 0
  const f = fixture({ read: () => ++reads === 1 ? config(1, false) : config(2), write: () => { throw new Error('fixture lost response') } })
  assert.equal(await f.service.ensureSelected(), true)
  assert.deepEqual(f.calls.map(call => call.kind), ['read', 'write', 'read'])
  assert.equal(f.persisted.length, 1)
})
test('unconfirmed creation is never automatically repeated, including another refresh', async () => {
  const f = fixture({ read: () => config(1, false), write: () => { throw new Error('fixture lost response') } })
  assert.equal(await f.service.ensureSelected(), false)
  assert.equal(await f.service.ensureSelected(), false)
  assert.equal(f.calls.filter(call => call.kind === 'write').length, 1)
  assert.equal(f.persisted.length, 0)
})
test('a later read may select the confirmed created profile instead of creating another', async () => {
  let reads = 0
  let writes = 0
  const f = fixture({ read: () => ++reads <= 2 ? config(1, false) : config(), write: () => { if (++writes === 1) throw new Error('fixture lost response'); return config(2) } })
  assert.equal(await f.service.ensureSelected(), false)
  assert.equal(await f.service.ensureSelected(), true)
  assert.deepEqual(f.calls.filter(call => call.kind === 'write').map(call => call.action), ['create', ''])
})
test('account/site changes, logout and disabling prevent stale read responses from writing', async () => {
  for (const change of ['account', 'site', 'logout', 'disable', 'aba']) {
    const f = fixture({ read: (calls, control) => {
      if (change === 'account') control.setScope(scope('other-account'))
      if (change === 'site') control.setScope(scope('fixture-account', true, 2))
      if (change === 'logout') control.logout()
      if (change === 'disable') control.disable()
      if (change === 'aba') control.setScope(scope('fixture-account', false, 3))
      return config()
    } })
    assert.equal(await f.service.ensureSelected(), false, change)
    assert.equal(f.calls.length, 1)
    assert.equal(f.persisted.length, 0)
  }
})
test('disable or account transition at the Preferences await cannot persist sp', async () => {
  for (const change of ['disable', 'account']) {
    const f = fixture({ read: () => config(2), beforePersist: control => change === 'disable' ? control.disable() : control.setScope(scope('other-account')) })
    assert.equal(await f.service.ensureSelected(), false)
    assert.equal(f.persisted.length, 0)
  }
})
test('unselected write response and persistence failure are not reported as ready', async () => {
  for (const options of [{ write: () => config() }, { persistFails: true }]) {
    const f = fixture(options)
    assert.equal(await f.service.ensureSelected(), false)
    assert.equal(f.persisted.length, 0)
  }
})
test('new account/site scope and a new preference revision reconcile independently', async () => {
  const f = fixture({ read: () => config(2) })
  assert.equal(await f.service.ensureSelected(), true)
  f.setScope(scope('other-account', true, 2))
  assert.equal(await f.service.ensureSelected(), true)
  f.changeRevision()
  assert.equal(await f.service.ensureSelected(), true)
  assert.equal(f.calls.length, 3)
  assert.deepEqual(f.persisted.map(item => item.member), ['fixture-account', 'other-account', 'other-account'])
})

test('actual settings default to enabled, persist false, restore it and roll back failed saves', async () => {
  const state = { enabled: true }
  const values = new Map()
  let failSave = false
  const store = { getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
    putSync: (key, value) => { if (failSave) throw new Error('fixture persistence failure'); values.set(key, value) }, flushSync() {} }
  const { EhAppProfileSettings: settings } = compile(read('settings/EhAppProfileSettings'), {
    '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    '../constants/StorageKeys': { StorageKeys: { STORE_SETTINGS: 'fixture', EH_APP_PROFILE_ENABLED: 'profileEnabled' } },
    '../state/EhAppProfileState': { connectEhAppProfile: () => state },
    '../diagnostics/DiagnosticLogger': { DiagnosticLogger: { warn() {} } },
  })
  await settings.restore({})
  assert.equal(state.enabled, true)
  await settings.setEnabled({}, false)
  assert.equal(values.get('profileEnabled'), false)
  state.enabled = true
  await settings.restore({})
  assert.equal(state.enabled, false)
  failSave = true
  await assert.rejects(settings.setEnabled({}, true), /fixture persistence failure/)
  assert.equal(state.enabled, false)
})


test('preparation failures retain their real typed cause for the list consumer', async () => {
  const f = fixture({ read: () => { throw new errors.EhError(errors.EhErrorKind.RateLimited, 'fixture 429') } })
  assert.equal(await f.service.ensureSelected(), false)
  assert.equal(f.service.listFailure().kind, errors.EhErrorKind.RateLimited)
  f.setScope(scope('other-account'))
  assert.equal(f.service.listFailure().kind, errors.EhErrorKind.Network)
})
