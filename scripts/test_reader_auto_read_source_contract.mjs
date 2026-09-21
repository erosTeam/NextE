import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const adapter = readFileSync(new URL('../feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets', import.meta.url), 'utf8')

function method(name) {
  const start = adapter.indexOf(`  async ${name}(`)
  assert.ok(start >= 0, `missing ${name}`)
  const body = adapter.indexOf('{', start)
  let depth = 0
  for (let index = body; index < adapter.length; index += 1) {
    if (adapter[index] === '{') depth += 1
    if (adapter[index] === '}' && --depth === 0) return adapter.slice(start, index + 1)
  }
  throw new Error(`unterminated ${name}`)
}

test('NextE keeps sUrl preview availability separate from automatic body-source readiness', () => {
  const page = method('page')
  const prepare = method('prepareAutoReadSource')
  assert.match(page, /if \(source\.sUrl\.length === 0\) throw new Error\('missing_eh_preview'\)/)
  assert.match(page, /page\.bodySourceReady = source\.imageUrl\.length > 0/)
  assert.match(prepare, /await ImageResolveService\.getInstance\(\)\.resolve\(source\)/)
  assert.match(prepare, /if \(source\.imageUrl\.length === 0\) throw new Error\('missing_eh_resolved_body_source'\)/)
  assert.match(prepare, /resolved\.bodySourceReady = true/)
  assert.doesNotMatch(prepare, /thumbnail\.available/)
})
