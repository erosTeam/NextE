#!/usr/bin/env node
/**
 * Contract for off-main-thread EH gallery-list parsing.
 *
 * The UI-facing services must not synchronously parse large gallery/search/favorites HTML pages on
 * the caller thread. The TaskPool helper returns serialized data and revives it into model classes so
 * existing consumers can keep using methods such as EhGallery.title().
 */
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const ok = (name, pass) => {
  if (!pass) {
    console.error(`FAIL ${name}`)
    process.exitCode = 1
  } else {
    console.log(`OK ${name}`)
  }
}

const task = read('shared/src/main/ets/parser/EhGalleryListParseTask.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')

ok('TaskPool helper imports @kit.ArkTS taskpool',
  /import \{ taskpool \} from '@kit\.ArkTS'/.test(task))

ok('parse worker is marked @Concurrent',
  /@Concurrent\s+function parseGalleryListJson\(html: string\): string \{[\s\S]*EhGalleryListParser\.parse\(html\)/.test(task))

ok('TaskPool helper serializes worker result instead of returning class instances across threads',
  /return JSON\.stringify\(EhGalleryListParser\.parse\(html\)\)/.test(task) &&
  /JSON\.parse\(raw\) as GalleryList/.test(task))

ok('TaskPool helper executes parser with typed taskpool.execute',
  /taskpool\.execute<\[string\], string>\(parseGalleryListJson, html\)/.test(task))

ok('TaskPool helper revives GalleryList and EhGallery model classes',
  /new GalleryList\(\)/.test(task) &&
  /new EhGallery\(raw\.gid, raw\.token\)/.test(task) &&
  /new SimpleTag\(raw\.text, raw\.translat, raw\.namespace\)/.test(task) &&
  /tag\.siteLabel = raw\.siteLabel/.test(task))

ok('EhApiService imports TaskPool parser helper',
  /import \{ EhGalleryListParseTask \} from '\.\.\/parser\/EhGalleryListParseTask'/.test(api))

ok('EhApiService uses async TaskPool parse for popular, toplist, normal list, and favorites',
  (api.match(/EhGalleryListParseTask\.parse\(resp\.body\)/g) || []).length >= 3 &&
  /const list: GalleryList = this\.registerInlineTagColors\(\s*await EhGalleryListParseTask\.parse\(body\),\s*userTagRequest,\s*\)/.test(api))

ok('EhApiService no longer imports or directly calls EhGalleryListParser.parse',
  !/import \{ EhGalleryListParser \}/.test(api) &&
  !/EhGalleryListParser\.parse\(/.test(api))

if (process.exitCode) process.exit(process.exitCode)
