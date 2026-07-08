#!/usr/bin/env node
/**
 * Contract: BasicDataSource must not mix LazyForEach DataChangeListener API families.
 *
 * ArkUI throws "onDatasetChange cannot be used with other interface" if the same listener receives
 * onDataReloaded()/onDataAdd() style calls and onDatasetChange() calls. NextE's shared
 * BasicDataSource must stay on that same family because every gallery list uses it. Appending must
 * also keep the backing array stable; copying all existing rows during load-more is visible on long
 * gallery lists.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const src = readFileSync(join(ROOT, 'shared/src/main/ets/utils/BasicDataSource.ets'), 'utf8')

assert.match(src, /notifyReload\(\)[\s\S]*onDataReloaded\(\)/, 'setData/clear should notify reload through onDataReloaded')
assert.match(src, /appendData\(items: T\[\]\): void \{[\s\S]*const start: number = this\.items\.length[\s\S]*this\.items\.push\(items\[i\]\)[\s\S]*onDataAdd\(start\)/, 'appendData should append in place and notify through onDataAdd(start)')
assert.doesNotMatch(src, /appendData\(items: T\[\]\): void \{[\s\S]*this\.items = this\.items\.concat\(items\)/, 'appendData should not copy all old rows with concat')
assert.doesNotMatch(src, /onDatasetChange|DataOperationType/, 'BasicDataSource must not use onDatasetChange with the reload/add listener family')

console.log('✓ basic data source listener contract passed')
