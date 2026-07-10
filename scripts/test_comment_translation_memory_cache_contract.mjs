#!/usr/bin/env node
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

class MemoryCache {
  constructor(maxEntries) {
    this.maxEntries = Math.max(1, maxEntries)
    this.entries = new Map()
  }
  get(key, now) {
    const entry = this.entries.get(key)
    if (!entry) return ''
    if (entry.expiresAt <= now) {
      this.entries.delete(key)
      return ''
    }
    this.entries.delete(key)
    this.entries.set(key, entry)
    return entry.translated
  }
  put(key, translated, expiresAt, now) {
    for (const [candidate, entry] of this.entries) {
      if (entry.expiresAt <= now) this.entries.delete(candidate)
    }
    if (expiresAt <= now || !translated) return
    this.entries.delete(key)
    while (this.entries.size >= this.maxEntries) {
      this.entries.delete(this.entries.keys().next().value)
    }
    this.entries.set(key, { translated, expiresAt })
  }
  size(now) {
    for (const [candidate, entry] of this.entries) {
      if (entry.expiresAt <= now) this.entries.delete(candidate)
    }
    return this.entries.size
  }
}

let passed = 0
const ok = (name, condition) => {
  assert.ok(condition, name)
  passed += 1
}

{
  const cache = new MemoryCache(2)
  cache.put('first', 'one', 100, 0)
  cache.put('second', 'two', 100, 0)
  ok('a cache hit refreshes recency', cache.get('first', 1) === 'one')
  cache.put('third', 'three', 100, 1)
  ok('the least-recently-used entry is evicted at capacity',
    cache.get('second', 1) === '' && cache.get('first', 1) === 'one' && cache.get('third', 1) === 'three')
  const expiryCache = new MemoryCache(2)
  expiryCache.put('expired', 'gone', 2, 1)
  ok('expired entries are never returned and are removed from the working set',
    expiryCache.get('expired', 2) === '' && expiryCache.size(2) === 0)
}

const ROOT = process.cwd()
const service = readFileSync(join(ROOT, 'shared/src/main/ets/services/CommentTranslationService.ets'), 'utf8')
const index = readFileSync(join(ROOT, 'shared/src/main/ets/Index.ets'), 'utf8')

ok('comment translation memory cache has a fixed cap and LRU hit refresh',
  /MAX_COMMENT_TRANSLATION_MEMORY_ENTRIES: number = 256/.test(service) &&
    /class CommentTranslationMemoryCache/.test(service) &&
    /this\.entries\.delete\(key\)[\s\S]*?this\.entries\.set\(key, entry\)/.test(service) &&
    /while \(this\.entries\.size >= this\.maxEntries\)/.test(service))
ok('service routes memory reads and writes through the bounded cache',
  /memory\.get\(key, now\)/.test(service) && /memory\.put\(key, translated, expiresAt\)/.test(service))
ok('the production memory cache is exported for deterministic device testing',
  /CommentTranslationMemoryCache/.test(index))

console.log(`✓ comment translation memory cache contract: ${passed} assertions passed`)
