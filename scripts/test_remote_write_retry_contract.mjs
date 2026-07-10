#!/usr/bin/env node
/**
 * Contract for the remote-write transport boundary.
 *
 * EH does not provide idempotency keys for comments, votes, tags, favorites, archiver requests,
 * or profile writes. A lost response can therefore mean the server already accepted the write.
 * Keep retries restricted to explicitly read-only requests.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFileSync(join(ROOT, path), 'utf8')

const client = read('shared/src/main/ets/network/EhHttpClient.ets')
const php = read('shared/src/main/ets/network/EhApiPhpService.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')

const methodBody = (source, signature) => {
  const from = source.indexOf(signature)
  assert.notEqual(from, -1, `missing ${signature}`)
  const open = source.indexOf('{', from + signature.length)
  assert.notEqual(open, -1, `missing body for ${signature}`)

  let depth = 0
  let quote = ''
  let escaped = false
  let lineComment = false
  let blockComment = false
  for (let index = open; index < source.length; index++) {
    const char = source[index]
    const next = source[index + 1] ?? ''
    if (lineComment) {
      if (char === '\n') lineComment = false
      continue
    }
    if (blockComment) {
      if (char === '*' && next === '/') {
        blockComment = false
        index++
      }
      continue
    }
    if (quote.length > 0) {
      if (escaped) {
        escaped = false
      } else if (char === '\\') {
        escaped = true
      } else if (char === quote) {
        quote = ''
      }
      continue
    }
    if (char === '/' && next === '/') {
      lineComment = true
      index++
      continue
    }
    if (char === '/' && next === '*') {
      blockComment = true
      index++
      continue
    }
    if (char === '\'' || char === '"' || char === '`') {
      quote = char
      continue
    }
    if (char === '{') {
      depth++
    } else if (char === '}') {
      depth--
      if (depth === 0) return source.slice(open + 1, index)
    }
  }
  assert.fail(`unterminated body for ${signature}`)
}

const assertOnce = (source, signature) => {
  const body = methodBody(source, signature)
  assert.match(body, /requestTextOnceWithAxios\(/, `${signature} must be single-attempt`)
  assert.doesNotMatch(body, /requestTextWithAxios\(/, `${signature} must not enter the retry loop`)
}

const assertReadRetry = (source, signature) => {
  const body = methodBody(source, signature)
  assert.match(body, /requestTextWithAxios\(/, `${signature} must use the retry loop`)
  assert.match(body, /http_json_read_retry/, `${signature} must use the read-only retry event`)
}

assertOnce(client, '  async getTextOnce(')
assertOnce(client, '  async postJson(')
assertReadRetry(client, '  async postJsonReadOnly(')
assertOnce(client, '  async postFormUrlEncoded(')
assertOnce(client, '  async postLogin(')

for (const name of ['rateGallery', 'voteComment', 'tagGallery', 'addGalleryTags', 'setUserTag']) {
  const body = methodBody(php, `  static async ${name}(`)
  assert.match(body, /\.postJson\(/, `${name} must use single-attempt JSON POST`)
  assert.doesNotMatch(body, /\.postJsonReadOnly\(/, `${name} must not use retryable JSON POST`)
}

for (const name of ['showPage', 'galleryData', 'tagSuggest']) {
  const body = methodBody(php, `  static async ${name}(`)
  assert.match(body, /\.postJsonReadOnly\(/, `${name} must use retryable read-only JSON POST`)
}

for (const name of [
  'updateGalleryFavorite',
  'postGalleryComment',
  'addUserTag',
  'updateMyTagsTagset',
  'deleteUserTags',
  'saveUserConfig',
  'postProfileAction',
  'postArchiverForm',
]) {
  const prefix = name === 'postArchiverForm' ? '  private async ' : '  async '
  const body = methodBody(api, `${prefix}${name}(`)
  assert.match(body, /\.postFormUrlEncoded\(/, `${name} must use single-attempt form POST`)
}

const reset = methodBody(api, '  async resetImageLimits(')
assert.match(reset, /\.postFormUrlEncoded\(/, 'resetImageLimits POST action must be single-attempt')
assert.match(reset, /\.getTextOnce\(/, 'resetImageLimits GET action must be single-attempt')
assert.doesNotMatch(reset, /this\.fetch\(/, 'resetImageLimits must not route its action through retryable fetch')

const localArchiver = methodBody(api, '  async submitGalleryArchiverLocal(')
assert.equal(
  (localArchiver.match(/this\.postArchiverForm\(/g) ?? []).length,
  1,
  'one local archiver confirmation must submit exactly one protected request',
)
assert.doesNotMatch(localArchiver, /EhApiService\.delay\(/, 'local archiver must not auto-resubmit after an ambiguous response')

console.log('✓ remote-write retry contract: writes are single-attempt; explicit read-only requests retain retry')
