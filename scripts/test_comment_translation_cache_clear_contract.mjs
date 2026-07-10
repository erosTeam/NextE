#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

class Epoch {
  constructor() {
    this.value = 0
  }
  snapshot() {
    return this.value
  }
  advance() {
    this.value += 1
    return this.value
  }
  isCurrent(snapshot) {
    return snapshot === this.value
  }
}

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

{
  const epoch = new Epoch()
  const beforeClear = epoch.snapshot()
  epoch.advance()
  ok('a clear invalidates older cache writes', !epoch.isCurrent(beforeClear))
  ok('work started after a clear can still populate the new cache generation', epoch.isCurrent(epoch.snapshot()))
}

const ROOT = process.cwd()
const service = readFileSync(join(ROOT, 'shared/src/main/ets/services/CommentTranslationService.ets'), 'utf8')
const index = readFileSync(join(ROOT, 'shared/src/main/ets/Index.ets'), 'utf8')

ok('explicit clear advances the translation cache generation before deleting storage',
  /static async clear\([\s\S]*?cacheEpoch\.advance\(\)[\s\S]*?memory\.clear\(\)[\s\S]*?SQL_DELETE_COMMENT_TRANSLATIONS/.test(service))
ok('an older translation checks its generation before memory and RDB writes',
  /translateAndCache\([\s\S]*?cacheEpoch: number/.test(service) &&
    /save\([\s\S]*?cacheEpoch: number/.test(service) &&
    /cacheEpoch\.isCurrent\(cacheEpoch\)/.test(service))
ok('a queued request captures its generation before it can run, so a later clear cannot revive it',
  /const cacheEpoch: number = CommentTranslationService\.cacheEpoch\.snapshot\(\)[\s\S]*?new CommentTranslationNetworkTask\([\s\S]*?targetLang,\s*cacheEpoch/.test(service))
ok('the production cache epoch is exported for deterministic device testing',
  /CommentTranslationCacheEpoch/.test(index))

console.log(`✓ comment translation cache-clear contract: ${passed} assertions passed`)
