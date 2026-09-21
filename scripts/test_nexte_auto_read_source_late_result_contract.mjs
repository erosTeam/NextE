import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const source = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')
const launch = source('../third_party/reader-kit/reader-ui/src/main/ets/ReaderLabLaunch.ets')
const probe = source('../feature/reader/src/main/ets/lab/NextEReaderAutoReadSourceProbe.ets')
const page = source('../feature/reader/src/main/ets/lab/NextEReaderLabPage.ets')
const adapter = source('../feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets')
const session = source('../third_party/reader-kit/reader-core/src/main/ets/ReaderPagedSession.ets')
const productionRequest = source('../feature/reader/src/main/ets/lab/NextEReaderHostRequest.ets')

test('auto-read source late-result probe is Debug-Want-only and disabled by default', () => {
  assert.match(launch, /autoReadSourceProbe: string = ''/)
  assert.match(launch, /const autoReadSourceProbe = want\.parameters\['readerLabAutoReadSourceProbe'\]/)
  assert.match(launch, /request\.autoReadSourceProbe = request\.readingChrome && typeof autoReadSourceProbe === 'string' &&[\s\S]{0,80}autoReadSourceProbe === 'delay-once'/)
  assert.doesNotMatch(productionRequest, /autoReadSourceProbe/)
})

test('probe delegates once to NextE host bridge then deliberately returns one late resolved page', () => {
  assert.match(probe, /implements ReaderAutoReadSourceHost/)
  assert.match(probe, /const inject = !this\.injected && this\.mode === 'delay-once'/)
  assert.match(probe, /const resolved = await this\.host\.prepareAutoReadSource\(page, cancellation\)/)
  assert.match(probe, /setTimeout\(resolve, 3000\)/)
  assert.match(probe, /delayed_result source=\$\{page\.sourceIndex\} cancelled=\$\{cancellation\.isCancelled\(\)\}/)
  assert.match(probe, /return resolved/)
  assert.doesNotMatch(probe, /cancellation\.check\(\)/)
})

test('NextE uses the wrapped real bridge only for the explicit probe and core retires stale completions', () => {
  assert.match(page, /lab\?\.autoReadSourceProbe === 'delay-once'/)
  assert.match(page, /new NextEReaderAutoReadSourceProbe\(adapter, lab\.autoReadSourceProbe\) : adapter/)
  assert.match(page, /new ReaderPagedSession\(adapter, assetProvider, adapter, adapter, autoReadSourceHost\)/)
  assert.match(adapter, /async prepareAutoReadSource\(page: ReaderPage, cancellation: ReaderCancellation\)/)
  assert.match(adapter, /await ImageResolveService\.getInstance\(\)\.resolve\(source\)/)
  assert.match(session, /if \(!this\.autoReadSourceCurrent\(targetUnit, targetIndex, part\.sourceIndex, generation, cancellation\)[\s\S]{0,220}return/)
})
