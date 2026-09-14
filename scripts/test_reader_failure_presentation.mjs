import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript')
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const source = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderFailure.ets'), 'utf8')
const labels = new Map([
  ['reader_error_quota', 'Quota title'], ['reader_error_quota_hint', 'Quota hint'],
  ['reader_error_rate_limited', 'Rate title'], ['reader_error_rate_limited_hint', 'Rate hint'],
  ['image_load_failed', 'Generic title'], ['reader_retry_source_hint', 'Generic hint'],
])
const context = { exports: {}, require: name => {
  if (name === 'shared') return { AppStrings: { get: key => labels.get(key) ?? key } }
  if (name === '@reader-kit/core') return { ReaderAssetFailure: class {
    constructor(code, title = '', hint = '') { Object.assign(this, { code, title, hint }) }
  } }
  return {}
} }
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
} }).outputText, context)

const classify = message => ({ ...context.exports.NextEReaderFailure.from(new Error(message)) })
assert.deepEqual(classify('HTTP image509 quota'), { code: 'quota', title: 'Quota title', hint: 'Quota hint' })
assert.deepEqual(classify('HTTP 429 throttle'), { code: 'rateLimited', title: 'Rate title', hint: 'Rate hint' })
assert.deepEqual(classify('socket closed'), { code: 'generic', title: 'Generic title', hint: 'Generic hint' })

const adapter = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets'), 'utf8')
assert.match(adapter,
  /export class NextEReaderLabAdapter[\s\S]*?ReaderAssetFailureClassifier[\s\S]*?classify\(error: Error\): ReaderAssetFailure[\s\S]*?NextEReaderFailure\.from\(error\)/)
for (const file of [
  'NextEReaderImageBlockProvider.ets',
  'NextEReaderSuperResolutionProvider.ets',
  'NextEReaderTranslationProvider.ets',
]) {
  const text = fs.readFileSync(path.join(root, 'feature/reader/src/main/ets/lab', file), 'utf8')
  assert.doesNotMatch(text, /failure\(error: Error\)/)
}

const host = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderLabPage.ets'), 'utf8')
assert.match(host, /new ReaderPagedSession\(adapter, assetProvider, adapter, adapter\)/)
assert.match(host, /@Param labRequest: ReaderLabRequest \| null = null/)
assert.match(host, /lab === null\s*\? translationProvider\s*:\s*new ReaderLabAssetProbe/)

const hostRequest = fs.readFileSync(path.join(root,
  'feature/reader/src/main/ets/lab/NextEReaderHostRequest.ets'), 'utf8')
const productionRequest = hostRequest.slice(hostRequest.indexOf('export class NextEProductionReaderRequest'))
for (const field of ['failurePage', 'thumbnailFailurePage', 'shareProbe', 'informationProbe',
  'originalVariantProbe', 'assetFailureMessage', 'entryLayoutOverride', 'entryDirectionOverride']) {
  assert.doesNotMatch(productionRequest, new RegExp(`\\b${field}\\b`))
}

console.log('NextE shared-reader failure presentation passed')
