import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { test } from 'node:test'
import vm from 'node:vm'
const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = new URL('../', import.meta.url)
function compile(source) {
  const exports = {}
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
  } }).outputText, { exports, console })
  return exports
}
const page = readFileSync(new URL('feature/reader/src/main/ets/lab/NextEReaderLabPage.ets', root), 'utf8')
const method = page.slice(page.indexOf('  private retireAbandonedOpening()'), page.indexOf('  aboutToDisappear()', page.indexOf('  private retireAbandonedOpening()')))
const Host = compile(`export class Host { ${method} }`).Host
function host(phase = 'asset', navigation = 7) {
  let releases = 0
  const value = new Host()
  value.rootOwnedEntryTarget = true
  value.rootOpeningNavigation = 7
  value.entryTransition = { phase: 'cancelled', target: null, matches: part => part.sourceIndex === 2 }
  value.session = { snapshot: () => ({ phase: 'ready', navigationRevision: navigation,
    frames: [{ part: { sourceIndex: 2 }, asset: { phase } }] }) }
  value.readerThumbnailTransition = { releaseCancelledOpening: () => releases++ }
  return { value, releases: () => releases }
}
test('geometry cancellation keeps same-page loading preview without target geometry', () => {
  for (const phase of ['idle', 'asset', 'decoding']) {
    const run = host(phase); run.value.retireAbandonedOpening(); assert.equal(run.releases(), 0)
  }
})
test('navigation relinquishes old preview even while old page stays in neighboring frame window', () => {
  const run = host('asset', 8); run.value.retireAbandonedOpening(); assert.equal(run.releases(), 1)
})
test('terminal failure and suppression expose existing terminal UI', () => {
  for (const phase of ['failed', 'suppressed']) {
    const run = host(phase); run.value.retireAbandonedOpening(); assert.equal(run.releases(), 1)
  }
})
test('legacy and active entry do not use cancellation retirement', () => {
  const legacy = host(); legacy.value.rootOwnedEntryTarget = false; legacy.value.retireAbandonedOpening(); assert.equal(legacy.releases(), 0)
  const active = host(); active.value.entryTransition.phase = 'waiting'; active.value.retireAbandonedOpening(); assert.equal(active.releases(), 0)
})
