#!/usr/bin/env node
/**
 * Contract: BasicDataSource uses the batch LazyForEach DataChangeListener API family exclusively.
 *
 * ArkUI throws "onDatasetChange cannot be used with other interface" if the same listener receives
 * onDataReloaded()/onDataAdd() style calls and onDatasetChange() calls. NextE stays entirely on the
 * batch family: one page append is one ADD operation with index + count. Appending also keeps the
 * backing array stable. Optional item keys and consumer-specific resolvers are covered by behavior
 * tests rather than frozen here as implementation-shape contracts.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'shared/src/main/ets/utils/BasicDataSource.ets'), 'utf8')

assert.match(src, /setData\(items: T\[\]\): void \{[\s\S]*DataOperationType\.RELOAD/, 'setData should use the batch RELOAD operation')
assert.match(src, /appendData\(items: T\[\]\): void \{[\s\S]*const start: number = this\.items\.length[\s\S]*this\.items\.push\(items\[i\]\)[\s\S]*this\.notifyAdded\(start, items\)/, 'appendData should append in place and issue one batch add')
assert.match(src, /notifyAdded\(index: number, items: T\[\]\): void \{[\s\S]*DataOperationType\.ADD[\s\S]*index: index[\s\S]*count: items\.length[\s\S]*notifyDatasetChange/, 'batch add should carry the starting index and full appended count')
assert.doesNotMatch(src, /appendData\(items: T\[\]\): void \{[\s\S]*this\.items = this\.items\.concat\(items\)/, 'appendData should not copy all old rows with concat')
assert.match(src, /notifyDatasetChange\(operations: DataOperation\[\]\): void \{[\s\S]*onDatasetChange\(operations\)/, 'all listeners should receive batch operations')
assert.doesNotMatch(src, /\.onData(?:Reloaded|Add|Change|Delete|Move)\(/, 'BasicDataSource must not mix legacy listener callbacks into the batch family')

console.log('✓ basic data source listener contract passed')
