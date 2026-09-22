
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = p => fs.readFileSync(path.join(root, p), 'utf8')

const surface = read('third_party/reader-kit/reader-ui/src/main/ets/ReaderSurface.ets')
const session = read('third_party/reader-kit/reader-core/src/main/ets/ReaderPagedSession.ets')

test('rail and slider onSeek route through the animated pager command', () => {
  const seekCalls = [...surface.matchAll(/this\.session\.seekSource\(/g)].length
  const animated = [...surface.matchAll(/this\.seekWithAnimation\(/g)].length
  assert.ok(seekWithAnimationDefined(surface), 'seekWithAnimation must be defined')
  assert.ok(animated >= 2, 'both onSeek callbacks must use seekWithAnimation')
})

function seekWithAnimationDefined(source) {
  return /private seekWithAnimation\(/.test(source)
}

test('seekWithAnimation prefers the pager command and respects pageTurnAnimation=false', () => {
  const body = surface.slice(
    surface.indexOf('private seekWithAnimation'),
    surface.indexOf('private requestMove'),
  )
  assert.match(body, /new ReaderPagerCommand/, 'adjacent target must go through pager command')
  assert.match(body, /if \(!this\.pageTurnAnimation\)/, 'must respect pageTurnAnimation=false')
  assert.match(body, /seekSource\(index, unit, navigation\)/, 'fallback to raw seek must remain')
})

test('session exposes displayIndexForSource for the animated seek', () => {
  assert.match(session, /displayIndexForSource\(sourceIndex: number\): number \| null/)
})
