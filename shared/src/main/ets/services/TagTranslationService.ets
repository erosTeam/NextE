import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import util from '@ohos.util'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhGallery } from '../model/EhGallery'
import { EhTagSuggestion } from '../model/EhTagSuggestion'
import { SimpleTag } from '../model/SimpleTag'
import { TagGroup } from '../model/TagGroup'
import { LocalDataStore } from '../storage/LocalDataStore'
import {
  TAG_INTRO_IMAGE_DISABLE,
  TAG_INTRO_IMAGE_NON_H,
  TAG_INTRO_IMAGE_R18,
  TAG_INTRO_IMAGE_R18G,
} from '../state/TagTranslationSettingsState'

const RELEASE_API_URL: string = 'https://api.github.com/repos/EhTagTranslation/Database/releases/latest'
const CDN_RELEASE_API_URL: string =
  'https://ghproxy.homeboyc.cn/https://api.github.com/repos/EhTagTranslation/Database/releases/latest'
const CDN_PREFIX: string = 'https://ghproxy.homeboyc.cn/'
const DB_ASSET_NAME: string = 'db.raw.json.gz'
const TAG_DB_DIR: string = 'tag-translation'
const TAG_DB_GZ_FILE: string = 'db.raw.json.gz'
const TAG_DB_READ_CHUNK: number = 128 * 1024
const TAG_DB_MAX_BYTES: number = 100 * 1024 * 1024
const TAG_DB_CONNECT_TIMEOUT_MS: number = 15000
const TAG_DB_READ_TIMEOUT_MS: number = 30000
const META_VERSION_KEY: string = 'version'

const SQL_COUNT_TAG_TRANSLATIONS: string = 'SELECT COUNT(*) AS c FROM tag_translations'
const SQL_SELECT_TAG_VERSION: string =
  'SELECT value FROM tag_translation_meta WHERE key = ? LIMIT 1'
const SQL_SELECT_TAG_TRANSLATION: string =
  'SELECT name FROM tag_translations WHERE namespace = ? AND key = ? LIMIT 1'
const SQL_SELECT_TAG_TRANSLATION_BY_KEY: string =
  'SELECT name FROM tag_translations WHERE key = ? ORDER BY namespace ASC LIMIT 1'
const SQL_SELECT_TAG_INFO: string =
  'SELECT name, intro, links FROM tag_translations WHERE namespace = ? AND key = ? LIMIT 1'
const SQL_QUERY_TAG_TRANSLATIONS: string =
  'SELECT namespace, key, name FROM tag_translations ' +
  'WHERE namespace <> \'rows\' AND (key LIKE ? ESCAPE \'\\\' OR name LIKE ? ESCAPE \'\\\') ' +
  'ORDER BY last_use_time DESC, namespace ASC, key ASC LIMIT ?'
const SQL_QUERY_TAG_TRANSLATIONS_BY_NAMESPACE: string =
  'SELECT namespace, key, name FROM tag_translations ' +
  'WHERE namespace = ? AND (key LIKE ? ESCAPE \'\\\' OR name LIKE ? ESCAPE \'\\\') ' +
  'ORDER BY last_use_time DESC, key ASC LIMIT ?'
const SQL_CLEAR_TAG_TRANSLATIONS: string = 'DELETE FROM tag_translations'
const SQL_UPSERT_TAG_VERSION: string =
  'INSERT OR REPLACE INTO tag_translation_meta (key, value) VALUES (?, ?)'
const SQL_TOUCH_TAG_TRANSLATION: string =
  'UPDATE tag_translations SET last_use_time = ? WHERE namespace = ? AND key = ?'

class TagTranslationEntry {
  namespace: string = ''
  key: string = ''
  name: string = ''
  intro: string = ''
  links: string = ''
  lastUseTime: number = 0
}

class TagTranslationReleaseAsset {
  name: string = ''
  browser_download_url: string = ''
}

class TagTranslationRelease {
  tag_name: string = ''
  published_at: string = ''
  assets: TagTranslationReleaseAsset[] = []
}

class RawTagEntry {
  name: string = ''
  intro: string = ''
  links: string = ''
}

class RawTagNamespace {
  namespace: string = ''
  data: Record<string, RawTagEntry> = {}
}

class RawTagDatabase {
  data: RawTagNamespace[] = []
}

class PublicTextResponse {
  statusCode: number = 0
  body: string = ''
}

class TagSuggestionQuery {
  namespace: string = ''
  keyword: string = ''
}

export class TagTranslationStatus {
  rowCount: number = 0
  version: string = ''
}

export class TagTranslationInfo {
  namespace: string = ''
  key: string = ''
  name: string = ''
  intro: string = ''
  links: string = ''
  images: string[] = []
}

export class TagTranslationService {
  static translateFullTag(fullTag: string): string {
    const normalized: string = TagTranslationService.normalize(fullTag)
    return TagTranslationService.fallbackTranslate(normalized)
  }

  static async translateFullTagAsync(context: common.UIAbilityContext, fullTag: string): Promise<string> {
    const normalized: string = TagTranslationService.normalize(fullTag)
    const idx: number = normalized.indexOf(':')
    if (idx <= 0) {
      return TagTranslationService.fallbackTranslate(normalized)
    }
    const namespace: string = normalized.substring(0, idx)
    const key: string = normalized.substring(idx + 1)
    if (!(await TagTranslationService.hasRows(context))) {
      return TagTranslationService.fallbackTranslate(normalized)
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const args: relationalStore.ValueType[] = [namespace, key]
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_TAG_TRANSLATION, args)
    try {
      if (resultSet.goToFirstRow()) {
        const name: string = TagTranslationService.readNullableString(
          resultSet,
          resultSet.getColumnIndex('name'),
        )
        if (name.length > 0) {
          return TagTranslationService.stripNameMarkdown(name)
        }
      }
    } finally {
      resultSet.close()
    }
    return TagTranslationService.fallbackTranslate(normalized)
  }

  static async translateGalleryTags(
    context: common.UIAbilityContext,
    gallery: EhGallery,
  ): Promise<EhGallery> {
    const rows: EhGallery[] = await TagTranslationService.translateGalleries(context, [gallery])
    return rows.length > 0 ? rows[0] : gallery
  }

  static clearGalleryTranslations(gallery: EhGallery): EhGallery {
    const g: EhGallery = gallery.copy()
    for (let i = 0; i < g.simpleTags.length; i++) {
      g.simpleTags[i].translat = ''
    }
    for (let i = 0; i < g.tagGroups.length; i++) {
      const group: TagGroup = g.tagGroups[i]
      for (let j = 0; j < group.tags.length; j++) {
        group.tags[j].translat = ''
      }
    }
    return g
  }

  static clearGalleriesTranslations(galleries: EhGallery[]): EhGallery[] {
    return galleries.map((gallery: EhGallery) => TagTranslationService.clearGalleryTranslations(gallery))
  }

  static async translateGalleries(
    context: common.UIAbilityContext,
    galleries: EhGallery[],
  ): Promise<EhGallery[]> {
    if (galleries.length === 0) {
      return []
    }
    const cache: Map<string, string> = new Map<string, string>()
    const out: EhGallery[] = []
    for (let i = 0; i < galleries.length; i++) {
      const g: EhGallery = galleries[i].copy()
      for (let j = 0; j < g.simpleTags.length; j++) {
        await TagTranslationService.translateTagInPlace(context, g.simpleTags[j].namespace, g.simpleTags[j], cache, true)
      }
      for (let j = 0; j < g.tagGroups.length; j++) {
        const group: TagGroup = g.tagGroups[j]
        for (let k = 0; k < group.tags.length; k++) {
          await TagTranslationService.translateTagInPlace(context, group.namespace, group.tags[k], cache, false)
        }
      }
      out.push(g)
    }
    return out
  }

  static async searchSuggestions(
    context: common.UIAbilityContext,
    keyword: string,
    limit: number = 30,
  ): Promise<EhTagSuggestion[]> {
    const q: TagSuggestionQuery = TagTranslationService.suggestionQuery(keyword)
    if (q.keyword.length === 0) {
      return []
    }
    if (await TagTranslationService.hasRows(context)) {
      const rows: EhTagSuggestion[] = await TagTranslationService.queryRdbSuggestions(context, q, limit)
      if (rows.length > 0) {
        return rows
      }
    }
    return TagTranslationService.fallbackSuggestions(q.keyword, limit, q.namespace)
  }

  static async lookupTagInfo(
    context: common.UIAbilityContext,
    namespace: string,
    key: string,
    introImageLevel: string = TAG_INTRO_IMAGE_NON_H,
  ): Promise<TagTranslationInfo | null> {
    const ns: string = EhConstants.expandNamespace(namespace).trim()
    const tagKey: string = TagTranslationService.cleanTagQueryText(key).toLowerCase()
    if (ns.length === 0 || tagKey.length === 0 || !(await TagTranslationService.hasRows(context))) {
      return null
    }
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const args: relationalStore.ValueType[] = [ns, tagKey]
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_SELECT_TAG_INFO, args)
    try {
      if (!resultSet.goToFirstRow()) {
        return null
      }
      const info: TagTranslationInfo = new TagTranslationInfo()
      info.namespace = ns
      info.key = tagKey
      info.name = TagTranslationService.stripNameMarkdown(
        TagTranslationService.readNullableString(resultSet, resultSet.getColumnIndex('name')),
      )
      const rawIntro: string = TagTranslationService.readNullableString(resultSet, resultSet.getColumnIndex('intro'))
      const rawLinks: string = TagTranslationService.readNullableString(resultSet, resultSet.getColumnIndex('links'))
      const filteredIntro: string = TagTranslationService.filterIntroImages(
        await TagTranslationService.translateInlineCodeTags(context, rawIntro),
        introImageLevel,
      )
      info.intro = filteredIntro.trim()
      info.images = TagTranslationService.extractMarkdownImageUrls(filteredIntro)
      info.links = rawLinks.trim()
      return info
    } finally {
      resultSet.close()
    }
  }

  static async status(context: common.UIAbilityContext): Promise<TagTranslationStatus> {
    const out: TagTranslationStatus = new TagTranslationStatus()
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    let countSet: relationalStore.ResultSet | null = null
    let versionSet: relationalStore.ResultSet | null = null
    try {
      countSet = await store.querySql(SQL_COUNT_TAG_TRANSLATIONS)
      if (countSet.goToFirstRow()) {
        out.rowCount = countSet.getLong(countSet.getColumnIndex('c'))
      }
      const args: relationalStore.ValueType[] = [META_VERSION_KEY]
      versionSet = await store.querySql(SQL_SELECT_TAG_VERSION, args)
      if (versionSet.goToFirstRow()) {
        out.version = TagTranslationService.readNullableString(
          versionSet,
          versionSet.getColumnIndex('value'),
        )
      }
    } finally {
      if (countSet !== null) {
        countSet.close()
      }
      if (versionSet !== null) {
        versionSet.close()
      }
    }
    return out
  }

  static async touchSuggestion(context: common.UIAbilityContext, s: EhTagSuggestion): Promise<void> {
    if (s.namespace.length === 0 || s.text.length === 0) {
      return
    }
    try {
      const store: relationalStore.RdbStore = await LocalDataStore.open(context)
      const args: relationalStore.ValueType[] = [
        Date.now(),
        EhConstants.expandNamespace(s.namespace),
        s.text.trim().toLowerCase(),
      ]
      await store.executeSql(SQL_TOUCH_TAG_TRANSLATION, args)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('tag-translation', 'touch_failed', e.message)
    }
  }

  static async updateFromLatestRelease(
    context: common.UIAbilityContext,
    useCdn: boolean = false,
  ): Promise<number> {
    const release: TagTranslationRelease = await TagTranslationService.fetchLatestRelease(useCdn)
    const assetUrl: string = TagTranslationService.findDbAssetUrl(release)
    if (assetUrl.length === 0) {
      throw new Error('tag translation asset missing')
    }
    const downloadUrl: string = useCdn ? `${CDN_PREFIX}${assetUrl}` : assetUrl
    const gzPath: string = TagTranslationService.localGzPath(context)
    TagTranslationService.ensureDir(TagTranslationService.localDir(context))
    DiagnosticLogger.info('tag-translation', 'download_start', DB_ASSET_NAME)
    await TagTranslationService.downloadPublicFile(downloadUrl, gzPath)
    const rawJson: string = await TagTranslationService.readGzipText(gzPath)
    const rows: TagTranslationEntry[] = TagTranslationService.parseRawDatabase(rawJson)
    await TagTranslationService.replaceRows(context, rows, TagTranslationService.releaseVersion(release))
    DiagnosticLogger.info('tag-translation', 'update_done', `${rows.length} rows`)
    return rows.length
  }

  static parseRawDatabase(rawJson: string): TagTranslationEntry[] {
    let raw: Object
    try {
      raw = JSON.parse(rawJson) as Object
    } catch (error) {
      throw new Error('tag translation: invalid JSON')
    }
    const db: RawTagDatabase = raw as RawTagDatabase
    const namespaces: RawTagNamespace[] = db.data !== undefined && db.data !== null ? db.data : []
    const rows: TagTranslationEntry[] = []
    namespaces.forEach((group: RawTagNamespace) => {
      const namespace: string = EhConstants.expandNamespace(TagTranslationService.safeString(group.namespace))
      if (namespace.length === 0 || group.data === undefined || group.data === null) {
        return
      }
      Object.keys(group.data).forEach((rawKey: string) => {
        const key: string = TagTranslationService.safeString(rawKey).toLowerCase()
        const value: RawTagEntry = group.data[rawKey] as RawTagEntry
        if (key.length === 0 || value === undefined || value === null) {
          return
        }
        const row: TagTranslationEntry = new TagTranslationEntry()
        row.namespace = namespace
        row.key = key
        row.name = TagTranslationService.safeString(value.name)
        row.intro = TagTranslationService.safeString(value.intro)
        row.links = TagTranslationService.safeString(value.links)
        rows.push(row)
      })
    })
    return rows
  }

  private static async translateTagInPlace(
    context: common.UIAbilityContext,
    namespace: string,
    tag: SimpleTag,
    cache: Map<string, string>,
    includePrefix: boolean,
  ): Promise<void> {
    if (namespace.length === 0 || tag.text.length === 0) {
      return
    }
    const fullTag: string = `${namespace}:${tag.text}`
    let translated: string | undefined = cache.get(fullTag)
    if (translated === undefined) {
      translated = await TagTranslationService.translateFullTagAsync(context, fullTag)
      cache.set(fullTag, translated)
    }
    if (translated.length > 0) {
      tag.translat = includePrefix ? EhConstants.localizedTagDisplay(namespace, translated) : translated
    }
  }

  private static async hasRows(context: common.UIAbilityContext): Promise<boolean> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const resultSet: relationalStore.ResultSet = await store.querySql(SQL_COUNT_TAG_TRANSLATIONS)
    try {
      if (!resultSet.goToFirstRow()) {
        return false
      }
      return resultSet.getLong(resultSet.getColumnIndex('c')) > 0
    } finally {
      resultSet.close()
    }
  }

  private static async queryRdbSuggestions(
    context: common.UIAbilityContext,
    query: TagSuggestionQuery,
    limit: number,
  ): Promise<EhTagSuggestion[]> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const like: string = `%${TagTranslationService.escapeLike(query.keyword)}%`
    const args: relationalStore.ValueType[] = query.namespace.length > 0
      ? [query.namespace, like, like, limit]
      : [like, like, limit]
    const sql: string = query.namespace.length > 0
      ? SQL_QUERY_TAG_TRANSLATIONS_BY_NAMESPACE
      : SQL_QUERY_TAG_TRANSLATIONS
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, args)
    const rows: EhTagSuggestion[] = []
    try {
      const nsIndex: number = resultSet.getColumnIndex('namespace')
      const keyIndex: number = resultSet.getColumnIndex('key')
      const nameIndex: number = resultSet.getColumnIndex('name')
      while (resultSet.goToNextRow()) {
        const namespace: string = resultSet.getString(nsIndex)
        const key: string = resultSet.getString(keyIndex)
        const name: string = TagTranslationService.stripNameMarkdown(
          TagTranslationService.readNullableString(resultSet, nameIndex),
        )
        if (namespace.length > 0 && key.length > 0) {
          rows.push(new EhTagSuggestion(namespace, key, name))
        }
      }
    } finally {
      resultSet.close()
    }
    return rows
  }

  private static async replaceRows(
    context: common.UIAbilityContext,
    rows: TagTranslationEntry[],
    version: string,
  ): Promise<void> {
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    store.beginTransaction()
    try {
      await store.executeSql(SQL_CLEAR_TAG_TRANSLATIONS)
      const chunk: relationalStore.ValuesBucket[] = []
      for (let i = 0; i < rows.length; i++) {
        chunk.push(TagTranslationService.toBucket(rows[i]))
        if (chunk.length >= 500) {
          await store.batchInsert('tag_translations', chunk)
          chunk.splice(0, chunk.length)
        }
      }
      if (chunk.length > 0) {
        await store.batchInsert('tag_translations', chunk)
      }
      const metaArgs: relationalStore.ValueType[] = [META_VERSION_KEY, version]
      await store.executeSql(SQL_UPSERT_TAG_VERSION, metaArgs)
      store.commit()
    } catch (error) {
      store.rollBack()
      throw error as Error
    }
  }

  private static toBucket(row: TagTranslationEntry): relationalStore.ValuesBucket {
    return {
      'namespace': row.namespace,
      'key': row.key,
      'name': row.name,
      'intro': row.intro,
      'links': row.links,
      'last_use_time': row.lastUseTime,
    }
  }

  private static async fetchLatestRelease(useCdn: boolean): Promise<TagTranslationRelease> {
    const resp: PublicTextResponse =
      await TagTranslationService.getPublicText(useCdn ? CDN_RELEASE_API_URL : RELEASE_API_URL)
    if (resp.statusCode !== 200) {
      throw new Error(`tag translation release HTTP ${resp.statusCode}`)
    }
    let raw: Object
    try {
      raw = JSON.parse(resp.body) as Object
    } catch (error) {
      throw new Error('tag translation release: invalid JSON')
    }
    return raw as TagTranslationRelease
  }

  private static async getPublicText(url: string): Promise<PublicTextResponse> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/vnd.github+json,application/json,*/*',
        'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
        'Accept-Encoding': 'gzip',
      }
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: TAG_DB_CONNECT_TIMEOUT_MS,
        readTimeout: TAG_DB_READ_TIMEOUT_MS,
        usingCache: false,
      })
      const body: string = typeof resp.result === 'string' ? resp.result as string : ''
      return { statusCode: resp.responseCode as number, body: body }
    } finally {
      req.destroy()
    }
  }

  private static async downloadPublicFile(url: string, filePath: string): Promise<number> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/gzip,application/octet-stream,*/*',
        'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
      }
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: TAG_DB_MAX_BYTES,
        connectTimeout: TAG_DB_CONNECT_TIMEOUT_MS,
        readTimeout: TAG_DB_READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      if (code !== 200) {
        throw new Error(`tag translation asset HTTP ${code}`)
      }
      if (typeof resp.result === 'string') {
        throw new Error('tag translation asset is not binary')
      }
      const bytes: ArrayBuffer = resp.result as ArrayBuffer
      return TagTranslationService.writeArrayBuffer(filePath, bytes)
    } finally {
      req.destroy()
    }
  }

  private static writeArrayBuffer(filePath: string, bytes: ArrayBuffer): number {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      return fileIo.writeSync((file as fileIo.File).fd, bytes)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static findDbAssetUrl(release: TagTranslationRelease): string {
    const assets: TagTranslationReleaseAsset[] =
      release.assets !== undefined && release.assets !== null ? release.assets : []
    for (let i = 0; i < assets.length; i++) {
      const asset: TagTranslationReleaseAsset = assets[i]
      if (asset.name === DB_ASSET_NAME && asset.browser_download_url.length > 0) {
        return asset.browser_download_url
      }
    }
    return ''
  }

  private static releaseVersion(release: TagTranslationRelease): string {
    return `${TagTranslationService.safeString(release.tag_name)} ${TagTranslationService.safeString(release.published_at)}`.trim()
  }

  private static async readGzipText(path: string): Promise<string> {
    const gzip: zlib.GZip = zlib.createGZipSync()
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    let text: string = ''
    await gzip.gzopen(path, 'rb')
    try {
      while (true) {
        const buffer: ArrayBuffer = new ArrayBuffer(TAG_DB_READ_CHUNK)
        const size: number = await gzip.gzread(buffer)
        if (size <= 0) {
          break
        }
        text = text + decoder.decodeToString(new Uint8Array(buffer, 0, size), { stream: true })
      }
      text = text + decoder.decodeToString(new Uint8Array(new ArrayBuffer(0)), { stream: false })
    } finally {
      await gzip.gzclose()
    }
    return text
  }

  private static localDir(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${TAG_DB_DIR}`
  }

  private static localGzPath(context: common.UIAbilityContext): string {
    return `${TagTranslationService.localDir(context)}/${TAG_DB_GZ_FILE}`
  }

  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      if (!fileIo.accessSync(dir)) {
        throw error as Error
      }
    }
  }

  private static readNullableString(resultSet: relationalStore.ResultSet, columnIndex: number): string {
    if (resultSet.isColumnNull(columnIndex)) {
      return ''
    }
    return resultSet.getString(columnIndex)
  }

  private static escapeLike(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_')
  }

  private static safeString(value: string | null | undefined): string {
    return typeof value === 'string' ? value.trim() : ''
  }

  private static stripNameMarkdown(value: string): string {
    return value.replace(/!\[(\S+)?\]\(.+?\)(\s+)?(\S+)/g, '$3').trim()
  }

  private static async translateInlineCodeTags(context: common.UIAbilityContext, intro: string): Promise<string> {
    if (intro.length === 0) {
      return ''
    }
    const regCode: RegExp = /`(([\w:]+\s+?)*[\w:]+)`/g
    const translations: Map<string, string> = new Map<string, string>()
    let match: RegExpExecArray | null = regCode.exec(intro)
    while (match !== null) {
      const raw: string = match[1]
      if (!translations.has(raw)) {
        const name: string = await TagTranslationService.lookupCodeTagName(context, raw)
        if (name.length > 0 && name !== raw) {
          translations.set(raw, `${name} (${raw})`)
        }
      }
      match = regCode.exec(intro)
    }
    return intro.replace(regCode, (_m: string, raw: string): string => {
      const translated: string | undefined = translations.get(raw)
      return translated === undefined ? ` ${raw} ` : ` ${translated} `
    })
  }

  private static async lookupCodeTagName(context: common.UIAbilityContext, raw: string): Promise<string> {
    const text: string = raw.trim().toLowerCase()
    if (text.length === 0) {
      return ''
    }
    const idx: number = text.indexOf(':')
    const store: relationalStore.RdbStore = await LocalDataStore.open(context)
    const sql: string = idx > 0 ? SQL_SELECT_TAG_TRANSLATION : SQL_SELECT_TAG_TRANSLATION_BY_KEY
    const args: relationalStore.ValueType[] = idx > 0
      ? [EhConstants.expandNamespace(text.substring(0, idx)), TagTranslationService.cleanTagQueryText(text.substring(idx + 1))]
      : [TagTranslationService.cleanTagQueryText(text)]
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, args)
    try {
      if (resultSet.goToFirstRow()) {
        return TagTranslationService.stripNameMarkdown(
          TagTranslationService.readNullableString(resultSet, resultSet.getColumnIndex('name')),
        )
      }
    } finally {
      resultSet.close()
    }
    return raw
  }

  static filterIntroImages(intro: string, level: string): string {
    const regR18g: RegExp = /!\[((\S+)?)\]\(##\s+?"(.+?)"\)/g
    const regR18And18g: RegExp = /!\[((\S+)?)\]\(##?\s+?"(.+?)"\)/g
    const regAll: RegExp = /!\[((\S+)?)\]\((.+?)\)/g
    switch (level) {
      case TAG_INTRO_IMAGE_DISABLE:
        return intro.replace(regAll, '')
      case TAG_INTRO_IMAGE_R18:
        return intro
          .replace(regR18g, '')
          .replace(regR18And18g, (_m: string, _alt0: string, alt: string, url: string): string => `![${alt}](${url})`)
      case TAG_INTRO_IMAGE_R18G:
        return intro.replace(regR18And18g, (_m: string, _alt0: string, alt: string, url: string): string => `![${alt}](${url})`)
      default:
        return intro.replace(regR18And18g, '')
    }
  }

  static extractMarkdownImageUrls(value: string): string[] {
    const urls: string[] = []
    const regImage: RegExp = /!\[([^\]]*)\]\(([^)]+)\)/g
    let match: RegExpExecArray | null = regImage.exec(value)
    while (match !== null) {
      const url: string = match[2].trim()
      if (url.length > 0 && url.indexOf('##') !== 0) {
        urls.push(url)
      }
      match = regImage.exec(value)
    }
    return urls
  }

  private static normalize(fullTag: string): string {
    const text: string = fullTag.trim().toLowerCase()
    const idx: number = text.indexOf(':')
    if (idx <= 0) {
      return `misc:${TagTranslationService.cleanTagQueryText(text)}`
    }
    const ns: string = EhConstants.expandNamespace(text.substring(0, idx))
    const tag: string = TagTranslationService.cleanTagQueryText(text.substring(idx + 1))
    return `${ns}:${tag}`
  }

  private static suggestionQuery(raw: string): TagSuggestionQuery {
    const out: TagSuggestionQuery = new TagSuggestionQuery()
    const text: string = raw.trim().toLowerCase()
    const idx: number = text.indexOf(':')
    if (idx > 0) {
      out.namespace = EhConstants.expandNamespace(text.substring(0, idx))
      out.keyword = TagTranslationService.cleanTagQueryText(text.substring(idx + 1))
      return out
    }
    out.keyword = TagTranslationService.cleanTagQueryText(text)
    return out
  }

  private static cleanTagQueryText(value: string): string {
    let tag: string = EhConstants.canonicalTagText(value).trim().toLowerCase()
    if (tag.startsWith('"')) {
      tag = tag.substring(1).trim()
    }
    if (tag.endsWith('"')) {
      tag = tag.substring(0, tag.length - 1).trim()
    }
    if (tag.endsWith('$')) {
      tag = tag.substring(0, tag.length - 1).trim()
    }
    if (tag.endsWith('"')) {
      tag = tag.substring(0, tag.length - 1).trim()
    }
    return tag
  }

  private static fallbackTranslate(normalized: string): string {
    switch (normalized) {
      case 'language:chinese':
        return '中文'
      case 'language:japanese':
        return '日文'
      case 'language:english':
        return '英文'
      case 'language:translated':
        return '已翻译'
      case 'female:big breasts':
        return '巨乳'
      case 'female:sole female':
        return '单女主'
      case 'female:paizuri':
        return '乳交'
      case 'female:group':
        return '群交'
      case 'male:sole male':
        return '单男主'
      case 'misc:full color':
        return '全彩'
      case 'misc:uncensored':
        return '无码'
      case 'other:multi-work series':
        return '多作品系列'
      default:
        return ''
    }
  }

  private static fallbackSuggestions(keyword: string, limit: number, namespace: string = ''): EhTagSuggestion[] {
    const seeds: EhTagSuggestion[] = [
      new EhTagSuggestion('language', 'chinese', '中文'),
      new EhTagSuggestion('language', 'japanese', '日文'),
      new EhTagSuggestion('language', 'english', '英文'),
      new EhTagSuggestion('language', 'translated', '已翻译'),
      new EhTagSuggestion('female', 'big breasts', '巨乳'),
      new EhTagSuggestion('female', 'sole female', '单女主'),
      new EhTagSuggestion('female', 'paizuri', '乳交'),
      new EhTagSuggestion('female', 'group', '群交'),
      new EhTagSuggestion('male', 'sole male', '单男主'),
      new EhTagSuggestion('misc', 'full color', '全彩'),
      new EhTagSuggestion('misc', 'uncensored', '无码'),
      new EhTagSuggestion('other', 'multi-work series', '多作品系列'),
    ]
    const out: EhTagSuggestion[] = []
    for (let i = 0; i < seeds.length && out.length < limit; i++) {
      const s: EhTagSuggestion = seeds[i]
      if (namespace.length > 0 && s.namespace !== namespace) {
        continue
      }
      if (
        s.text.indexOf(keyword) >= 0 ||
        s.displayName.indexOf(keyword) >= 0 ||
        s.label().indexOf(keyword) >= 0
      ) {
        out.push(s)
      }
    }
    return out
  }
}
