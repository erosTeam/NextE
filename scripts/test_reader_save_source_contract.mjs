#!/usr/bin/env node
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const legacy = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const selectorStart = legacy.indexOf('private currentDisplayUrl(image: EhGalleryImage): string')
const selectorEnd = legacy.indexOf('private originalModeForIndex', selectorStart)
assert.ok(selectorStart >= 0 && selectorEnd > selectorStart, 'legacy display selector must exist')
const selector = legacy.slice(selectorStart, selectorEnd)
assert.match(selector, /if \(this\.isLocalReaderSource\(\)\) \{\s*return image\.imageUrl/)
assert.match(selector, /if \(this\.originalModeForPage\(image\.page\) && image\.originImageUrl\.length > 0\) \{\s*return image\.originImageUrl/)
assert.match(selector, /return image\.imageUrl/)

const legacySaveStart = legacy.indexOf('private async saveImagesSequential(indexes: number[]): Promise<void>')
const legacySaveEnd = legacy.indexOf('private saveImagesAtIndexes', legacySaveStart)
assert.ok(legacySaveStart >= 0 && legacySaveEnd > legacySaveStart, 'legacy save path must exist')
const legacySave = legacy.slice(legacySaveStart, legacySaveEnd)
assert.match(legacySave, /const alreadyResolvedUrl: string = this\.currentDisplayUrl\(image\)/)
assert.match(legacySave, /await this\.saveImageUrl\(alreadyResolvedUrl, title\)/)
assert.match(legacySave, /const imageUrl: string = await this\.resolveCurrentDisplayUrl\(image\)/)

const sharedSave = read('third_party/reader-kit/reader-core/src/main/ets/ReaderImageSave.ets')
assert.match(sharedSave, /snapshot\.phase !== 'ready' \|\| snapshot\.kind !== 'original' \|\| unit === null/)
assert.match(sharedSave, /asset\.kind !== 'original' \|\| asset\.phase !== 'displayed' \|\| asset\.saveUri\.length === 0/)
assert.match(sharedSave, /new ReaderImageSaveItem\(index, page\.key, frame\.slotId, asset\.assetRequestId, asset\.saveUri\)/)

const adapter = read('feature/reader/src/main/ets/lab/NextEReaderLabAdapter.ets')
assert.match(adapter, /ImagePipelineService\.loadReaderFile\(this\.context, url, key, 100, undefined, forceReload\)/)
assert.match(adapter, /new ReaderAsset\(result\.displayUri, \(\) => \{\}, new ReaderFileInformation\(result\.filePath, facts\)\)/)
assert.match(adapter, /asset\.saveUri = this\.url/)
assert.match(adapter, /asset\.saveUri = url/)
assert.match(adapter, /saveUri\(page: ReaderPage\): string \{\s*return this\.pages\.get\(page\.key\)\?\.imageUrl \?\? ''/)

const enhanced = read('feature/reader/src/main/ets/lab/NextEReaderSuperResolutionProvider.ets')
const translated = read('feature/reader/src/main/ets/lab/NextEReaderTranslationProvider.ets')
assert.match(enhanced, /new ReaderAsset\(`file:\/\/\$\{this\.path\}`/)
assert.match(translated, /new ReaderAsset\(`file:\/\/\$\{this\.path\}`/)
assert.match(enhanced, /asset\.saveUri = this\.saveUri/)
assert.match(translated, /asset\.saveUri = this\.saveUri/)
assert.match(enhanced, /saveUriForPage\(page\)/)
assert.match(translated, /saveUriForPage\(page\)/)

const host = read('feature/reader/src/main/ets/lab/NextEReaderLabPage.ets')
assert.match(host, /new ReaderSystemImageSaveHost\(context, async \(uri: string, path: string\): Promise<void> => \{\s*await EhHttpClient\.getInstance\(\)\.downloadBinaryToFile\(uri, path\)/)
assert.match(host, /\(page: ReaderPage\): string => adapter\.saveUri\(page\)/)

console.log('PASS NextE shared save captures the legacy export source while retaining displayed-frame cancellation')
