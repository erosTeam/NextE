import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { taskpool, util } from '@kit.ArkTS'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { DownloadQueueSettings } from '../settings/DownloadQueueSettings'
import { ArchiveImageService } from './ArchiveImageService'

export class DownloadExportFormat {
  static readonly ZIP: string = 'zip'
  static readonly CBZ: string = 'cbz'
  static readonly EPUB: string = 'epub'
  static readonly PDF: string = 'pdf'
  static readonly HTMLZ: string = 'htmlz'
}

export class DownloadExportFile {
  fileName: string = ''
  filePath: string = ''
  description: string = ''
}

class DownloadExportEntry {
  sourcePath: string = ''
  entryName: string = ''
}

class ZipStoreEntry {
  name: string = ''
  sourcePath: string = ''
  contentText: string = ''
}

class PngIdatRange {
  offset: number = 0
  length: number = 0
}

class PdfImageInfo {
  sourcePath: string = ''
  kind: string = ''
  width: number = 0
  height: number = 0
  bits: number = 8
  colors: number = 3
  colorSpace: string = '/DeviceRGB'
  pngColorType: number = -1
  paletteHex: string = ''
  paletteColors: number = 0
  streamLength: number = 0
  alphaStreamLength: number = 0
  useDecodedRgba: boolean = false
  idatRanges: PngIdatRange[] = []
}

@Concurrent
function writeZipStoreFileTask(filePath: string, entriesJson: string): string {
  const fileChunkSize: number = 256 * 1024
  const rawEntries: Record<string, string>[] = JSON.parse(entriesJson) as Record<string, string>[]
  const crcTable: number[] = []

  const ensureCrcTable = (): void => {
    if (crcTable.length > 0) {
      return
    }
    for (let i: number = 0; i < 256; i++) {
      let crc: number = i
      for (let bit: number = 0; bit < 8; bit++) {
        crc = (crc & 1) !== 0 ? (0xedb88320 ^ (crc >>> 1)) : (crc >>> 1)
      }
      crcTable.push(crc >>> 0)
    }
  }
  const updateCrc = (seed: number, bytes: Uint8Array): number => {
    ensureCrcTable()
    let crc: number = seed
    for (let i: number = 0; i < bytes.byteLength; i++) {
      crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8)
    }
    return crc
  }
  const crc32 = (bytes: Uint8Array): number => {
    return (updateCrc(0xffffffff, bytes) ^ 0xffffffff) >>> 0
  }
  const writeBytes = (file: fileIo.File, bytes: Uint8Array): void => {
    if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
      fileIo.writeSync(file.fd, bytes.buffer)
      return
    }
    const exact: Uint8Array = bytes.slice(0, bytes.byteLength)
    fileIo.writeSync(file.fd, exact.buffer)
  }
  const put16 = (bytes: Uint8Array, offset: number, value: number): void => {
    bytes[offset] = value & 0xff
    bytes[offset + 1] = (value >>> 8) & 0xff
  }
  const put32 = (bytes: Uint8Array, offset: number, value: number): void => {
    bytes[offset] = value & 0xff
    bytes[offset + 1] = (value >>> 8) & 0xff
    bytes[offset + 2] = (value >>> 16) & 0xff
    bytes[offset + 3] = (value >>> 24) & 0xff
  }
  const localHeader = (nameBytes: Uint8Array, crc: number, size: number): Uint8Array => {
    const bytes: Uint8Array = new Uint8Array(30 + nameBytes.byteLength)
    put32(bytes, 0, 0x04034b50)
    put16(bytes, 4, 20)
    put16(bytes, 6, 0x0800)
    put16(bytes, 8, 0)
    put16(bytes, 10, 0)
    put16(bytes, 12, 0)
    put32(bytes, 14, crc)
    put32(bytes, 18, size)
    put32(bytes, 22, size)
    put16(bytes, 26, nameBytes.byteLength)
    put16(bytes, 28, 0)
    bytes.set(nameBytes, 30)
    return bytes
  }
  const centralHeader = (nameBytes: Uint8Array, crc: number, size: number, localHeaderOffset: number): Uint8Array => {
    const bytes: Uint8Array = new Uint8Array(46 + nameBytes.byteLength)
    put32(bytes, 0, 0x02014b50)
    put16(bytes, 4, 20)
    put16(bytes, 6, 20)
    put16(bytes, 8, 0x0800)
    put16(bytes, 10, 0)
    put16(bytes, 12, 0)
    put16(bytes, 14, 0)
    put32(bytes, 16, crc)
    put32(bytes, 20, size)
    put32(bytes, 24, size)
    put16(bytes, 28, nameBytes.byteLength)
    put16(bytes, 30, 0)
    put16(bytes, 32, 0)
    put16(bytes, 34, 0)
    put16(bytes, 36, 0)
    put32(bytes, 38, 0)
    put32(bytes, 42, localHeaderOffset)
    bytes.set(nameBytes, 46)
    return bytes
  }
  const endRecord = (count: number, centralSize: number, centralOffset: number): Uint8Array => {
    const bytes: Uint8Array = new Uint8Array(22)
    put32(bytes, 0, 0x06054b50)
    put16(bytes, 4, 0)
    put16(bytes, 6, 0)
    put16(bytes, 8, count)
    put16(bytes, 10, count)
    put32(bytes, 12, centralSize)
    put32(bytes, 16, centralOffset)
    put16(bytes, 20, 0)
    return bytes
  }
  const fileStats = (path: string): number[] => {
    let source: fileIo.File | null = null
    try {
      source = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(fileChunkSize)
      let crc: number = 0xffffffff
      let size: number = 0
      while (true) {
        const bytesRead: number = fileIo.readSync(source.fd, buffer, { length: fileChunkSize })
        if (bytesRead <= 0) {
          break
        }
        crc = updateCrc(crc, new Uint8Array(buffer, 0, bytesRead))
        size += bytesRead
      }
      return [(crc ^ 0xffffffff) >>> 0, size]
    } finally {
      if (source !== null) {
        fileIo.closeSync(source)
      }
    }
  }
  const writeFileContent = (out: fileIo.File, sourcePath: string): void => {
    let source: fileIo.File | null = null
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(fileChunkSize)
      while (true) {
        const bytesRead: number = fileIo.readSync(source.fd, buffer, { length: fileChunkSize })
        if (bytesRead <= 0) {
          break
        }
        fileIo.writeSync(out.fd, buffer, { length: bytesRead })
      }
    } finally {
      if (source !== null) {
        fileIo.closeSync(source)
      }
    }
  }

  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    let offset: number = 0
    const centralRecords: Uint8Array[] = []
    for (let i: number = 0; i < rawEntries.length; i++) {
      const raw: Record<string, string> = rawEntries[i]
      const name: string = raw.name
      const sourcePath: string = raw.sourcePath
      const contentText: string = raw.contentText
      const nameBytes: Uint8Array = new util.TextEncoder().encodeInto(name)
      let crc: number = 0
      let size: number = 0
      if (contentText.length > 0) {
        const contentBytes: Uint8Array = new util.TextEncoder().encodeInto(contentText)
        crc = crc32(contentBytes)
        size = contentBytes.byteLength
        writeBytes(file, localHeader(nameBytes, crc, size))
        writeBytes(file, contentBytes)
      } else {
        const stats: number[] = fileStats(sourcePath)
        crc = stats[0]
        size = stats[1]
        writeBytes(file, localHeader(nameBytes, crc, size))
        writeFileContent(file, sourcePath)
      }
      centralRecords.push(centralHeader(nameBytes, crc, size, offset))
      offset += 30 + nameBytes.byteLength + size
    }
    const centralOffset: number = offset
    let centralSize: number = 0
    for (let i: number = 0; i < centralRecords.length; i++) {
      writeBytes(file, centralRecords[i])
      centralSize += centralRecords[i].byteLength
    }
    writeBytes(file, endRecord(rawEntries.length, centralSize, centralOffset))
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
  return ''
}

export class DownloadExportService {
  private static exportFile(fileName: string, filePath: string, description: string): DownloadExportFile {
    const out: DownloadExportFile = new DownloadExportFile()
    out.fileName = fileName
    out.filePath = filePath
    out.description = description
    return out
  }

  private static fileMtime(path: string): number {
    const stat: fileIo.Stat = fileIo.statSync(path)
    return stat.mtime
  }

  private static newestEntryMtime(entries: DownloadExportEntry[]): number {
    let newest: number = 0
    for (let i: number = 0; i < entries.length; i++) {
      const mtime: number = DownloadExportService.fileMtime(entries[i].sourcePath)
      if (mtime > newest) {
        newest = mtime
      }
    }
    return newest
  }

  private static reusableExportFile(
    fileName: string,
    filePath: string,
    description: string,
    sourceMtime: number,
  ): DownloadExportFile | null {
    try {
      const stat: fileIo.Stat = fileIo.statSync(filePath)
      // ponytail: mtime freshness is enough for completed downloads; add a manifest only if stale exports are observed.
      if (stat.size > 0 && stat.mtime >= sourceMtime) {
        DiagnosticLogger.info(
          'download',
          'download_export_reuse',
          `pathHash=${DiagnosticLogger.ownerHash(filePath)} size=${stat.size}`,
        )
        return DownloadExportService.exportFile(fileName, filePath, description)
      }
    } catch (_error) {
    }
    return null
  }

  static async exportGallery(
    context: common.UIAbilityContext,
    task: DownloadGalleryTask,
    format: string,
  ): Promise<DownloadExportFile> {
    const entries: DownloadExportEntry[] = DownloadExportService.galleryEntries(task)
    if (entries.length === 0) {
      throw new Error('no downloaded files')
    }
    const ext: string = DownloadExportService.exportExt(format)
    const title: string = task.displayTitle()
    const fileName: string = `${DownloadExportService.safeBaseName(title, task.gid)}.${ext}`
    const filePath: string = `${await DownloadExportService.exportDir(context)}/${fileName}`
    const reusable: DownloadExportFile | null =
      DownloadExportService.reusableExportFile(fileName, filePath, title, DownloadExportService.newestEntryMtime(entries))
    if (reusable !== null) {
      return reusable
    }
    DownloadExportService.unlinkIfExists(filePath)
    if (format === DownloadExportFormat.PDF) {
      await PdfImageWriter.write(filePath, entries)
    } else if (format === DownloadExportFormat.EPUB) {
      await ZipStoreWriter.write(filePath, DownloadExportService.epubZipEntries(title, entries))
    } else if (format === DownloadExportFormat.HTMLZ) {
      await ZipStoreWriter.write(filePath, DownloadExportService.htmlZipEntries(title, entries))
    } else {
      await ZipStoreWriter.write(filePath, DownloadExportService.galleryZipEntries(entries))
    }
    return DownloadExportService.exportFile(fileName, filePath, title)
  }

  static async exportArchiver(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
    format: string,
  ): Promise<DownloadExportFile> {
    const entries: DownloadExportEntry[] = DownloadExportService.pathEntries(
      await ArchiveImageService.imagePathsForTask(context, task),
    )
    if (entries.length === 0) {
      throw new Error('archive has no readable images')
    }
    const ext: string = DownloadExportService.exportExt(format)
    const title: string = task.displayTitle()
    const fileName: string = `${DownloadExportService.safeBaseName(title, task.gid)}.${ext}`
    const filePath: string = `${await DownloadExportService.exportDir(context)}/${fileName}`
    const reusable: DownloadExportFile | null =
      DownloadExportService.reusableExportFile(fileName, filePath, title, DownloadExportService.newestEntryMtime(entries))
    if (reusable !== null) {
      return reusable
    }
    DownloadExportService.unlinkIfExists(filePath)
    if (format === DownloadExportFormat.PDF) {
      await PdfImageWriter.write(filePath, entries)
    } else if (format === DownloadExportFormat.EPUB) {
      await ZipStoreWriter.write(filePath, DownloadExportService.epubZipEntries(title, entries))
    } else if (format === DownloadExportFormat.HTMLZ) {
      await ZipStoreWriter.write(filePath, DownloadExportService.htmlZipEntries(title, entries))
    } else {
      await ZipStoreWriter.write(filePath, DownloadExportService.galleryZipEntries(entries))
    }
    return DownloadExportService.exportFile(fileName, filePath, title)
  }

  static originalArchiverFile(task: DownloadArchiverTask): DownloadExportFile {
    if (task.filePath.length === 0) {
      throw new Error('archive file missing')
    }
    fileIo.statSync(task.filePath)
    const out: DownloadExportFile = new DownloadExportFile()
    out.fileName = task.fileName.length > 0 ? task.fileName :
      `${DownloadExportService.safeBaseName(task.displayTitle(), task.gid)}${DownloadExportService.fileExt(task.filePath)}`
    out.filePath = task.filePath
    out.description = task.displayTitle()
    return out
  }

  static async exportArchiverOriginal(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<DownloadExportFile> {
    const source: DownloadExportFile = DownloadExportService.originalArchiverFile(task)
    const filePath: string = `${await DownloadExportService.exportDir(context)}/${source.fileName}`
    const reusable: DownloadExportFile | null =
      DownloadExportService.reusableExportFile(source.fileName, filePath, source.description,
        DownloadExportService.fileMtime(source.filePath))
    if (reusable !== null) {
      return reusable
    }
    DownloadExportService.unlinkIfExists(filePath)
    await DownloadExportService.copyFile(source.filePath, filePath)
    return DownloadExportService.exportFile(source.fileName, filePath, source.description)
  }

  private static pathEntries(paths: string[]): DownloadExportEntry[] {
    const entries: DownloadExportEntry[] = []
    for (let i: number = 0; i < paths.length; i++) {
      const entry: DownloadExportEntry = new DownloadExportEntry()
      entry.sourcePath = paths[i]
      entry.entryName = `${DownloadExportService.pageName(i + 1)}${DownloadExportService.fileExt(paths[i])}`
      entries.push(entry)
    }
    return entries
  }

  private static exportExt(format: string): string {
    if (format === DownloadExportFormat.EPUB) {
      return 'epub'
    }
    if (format === DownloadExportFormat.PDF) {
      return 'pdf'
    }
    if (format === DownloadExportFormat.HTMLZ) {
      return 'htmlz'
    }
    if (format === DownloadExportFormat.CBZ) {
      return 'cbz'
    }
    return 'zip'
  }

  private static galleryEntries(task: DownloadGalleryTask): DownloadExportEntry[] {
    const seeds: DownloadImageSeed[] = task.imageSeeds.slice()
    seeds.sort((a: DownloadImageSeed, b: DownloadImageSeed) => a.page - b.page)
    const entries: DownloadExportEntry[] = []
    for (let i: number = 0; i < seeds.length; i++) {
      const seed: DownloadImageSeed = seeds[i]
      if (seed.filePath.length === 0 || seed.bytesWritten <= 0) {
        continue
      }
      fileIo.statSync(seed.filePath)
      const entry: DownloadExportEntry = new DownloadExportEntry()
      entry.sourcePath = seed.filePath
      entry.entryName = `${DownloadExportService.pageName(seed.page > 0 ? seed.page : entries.length + 1)}${DownloadExportService.fileExt(seed.filePath)}`
      entries.push(entry)
    }
    return entries
  }

  private static galleryZipEntries(entries: DownloadExportEntry[]): ZipStoreEntry[] {
    const zipEntries: ZipStoreEntry[] = []
    for (let i: number = 0; i < entries.length; i++) {
      const source: DownloadExportEntry = entries[i]
      const entry: ZipStoreEntry = new ZipStoreEntry()
      entry.name = source.entryName
      entry.sourcePath = source.sourcePath
      zipEntries.push(entry)
    }
    return zipEntries
  }

  private static htmlZipEntries(title: string, entries: DownloadExportEntry[]): ZipStoreEntry[] {
    const zipEntries: ZipStoreEntry[] = []
    zipEntries.push(DownloadExportService.textEntry('index.html', DownloadExportService.htmlIndex(title, entries)))
    zipEntries.push(DownloadExportService.textEntry(
      'style.css',
      'html,body{margin:0;padding:0;background:#111;color:#f5f5f5;}main{margin:0 auto;max-width:100%;}' +
        'img{display:block;width:100%;height:auto;margin:0 auto;}',
    ))
    for (let i: number = 0; i < entries.length; i++) {
      const source: DownloadExportEntry = entries[i]
      const imageEntry: ZipStoreEntry = new ZipStoreEntry()
      imageEntry.name = `images/${source.entryName}`
      imageEntry.sourcePath = source.sourcePath
      zipEntries.push(imageEntry)
    }
    return zipEntries
  }

  private static epubZipEntries(title: string, entries: DownloadExportEntry[]): ZipStoreEntry[] {
    const zipEntries: ZipStoreEntry[] = []
    zipEntries.push(DownloadExportService.textEntry('mimetype', 'application/epub+zip'))
    zipEntries.push(DownloadExportService.textEntry(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n' +
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n' +
        '  <rootfiles>\n' +
        '    <rootfile full-path="OEBPS/metadata.opf" media-type="application/oebps-package+xml"/>\n' +
        '  </rootfiles>\n' +
        '</container>\n',
    ))
    zipEntries.push(DownloadExportService.textEntry(
      'OEBPS/content/resources/index.css',
      'html,body{margin:0;padding:0;background:#000;}img{display:block;width:100%;height:auto;}\n',
    ))
    for (let i: number = 0; i < entries.length; i++) {
      const source: DownloadExportEntry = entries[i]
      const imageEntry: ZipStoreEntry = new ZipStoreEntry()
      imageEntry.name = `OEBPS/content/resources/${source.entryName}`
      imageEntry.sourcePath = source.sourcePath
      zipEntries.push(imageEntry)
      zipEntries.push(DownloadExportService.textEntry(
        `OEBPS/content/page_${DownloadExportService.pageName(i + 1)}.xhtml`,
        DownloadExportService.epubPage(source.entryName),
      ))
    }
    zipEntries.push(DownloadExportService.textEntry(
      'OEBPS/metadata.opf',
      DownloadExportService.epubOpf(title, entries),
    ))
    zipEntries.push(DownloadExportService.textEntry(
      'OEBPS/toc.ncx',
      DownloadExportService.epubToc(title, entries.length),
    ))
    return zipEntries
  }

  private static textEntry(name: string, text: string): ZipStoreEntry {
    const entry: ZipStoreEntry = new ZipStoreEntry()
    entry.name = name
    entry.contentText = text
    return entry
  }

  private static epubPage(imageName: string): string {
    const escaped: string = DownloadExportService.escapeXml(imageName)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' +
      '<!DOCTYPE html>\n' +
      '<html xmlns="http://www.w3.org/1999/xhtml">\n' +
      '<head><title></title><link rel="stylesheet" type="text/css" href="resources/index.css"/></head>\n' +
      `<body><img src="resources/${escaped}" alt=""/></body>\n` +
      '</html>\n'
  }

  private static epubOpf(title: string, entries: DownloadExportEntry[]): string {
    const safeTitle: string = DownloadExportService.escapeXml(title)
    let manifest: string = '<item id="css" href="content/resources/index.css" media-type="text/css"/>\n'
    let spine: string = ''
    for (let i: number = 0; i < entries.length; i++) {
      const pageName: string = DownloadExportService.pageName(i + 1)
      const imageName: string = entries[i].entryName
      manifest += `<item id="img_${pageName}" href="content/resources/${DownloadExportService.escapeXml(imageName)}" media-type="${DownloadExportService.mediaType(imageName)}"/>\n`
      manifest += `<item id="page_${pageName}" href="content/page_${pageName}.xhtml" media-type="application/xhtml+xml"/>\n`
      spine += `<itemref idref="page_${pageName}"/>\n`
    }
    const coverName: string = entries.length > 0 ? entries[0].entryName : ''
    const coverMeta: string = coverName.length > 0 ? '<meta name="cover" content="img_0001"/>\n' : ''
    return '<?xml version="1.0" encoding="UTF-8"?>\n' +
      '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">\n' +
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n' +
      `<dc:title>${safeTitle}</dc:title>\n` +
      `<dc:identifier id="bookid">${DownloadExportService.escapeXml(`nexte-${Date.now()}`)}</dc:identifier>\n` +
      '<dc:language>und</dc:language>\n' +
      coverMeta +
      '</metadata>\n' +
      '<manifest>\n' +
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n' +
      manifest +
      '</manifest>\n' +
      '<spine toc="ncx">\n' +
      spine +
      '</spine>\n' +
      '</package>\n'
  }

  private static epubToc(title: string, count: number): string {
    const safeTitle: string = DownloadExportService.escapeXml(title)
    let nav: string = ''
    for (let i: number = 0; i < count; i++) {
      const pageName: string = DownloadExportService.pageName(i + 1)
      nav += `<navPoint id="nav_${pageName}" playOrder="${i + 1}"><navLabel><text>${i + 1}</text></navLabel><content src="content/page_${pageName}.xhtml"/></navPoint>\n`
    }
    return '<?xml version="1.0" encoding="UTF-8"?>\n' +
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n' +
      '<head><meta name="dtb:uid" content="nexte"/></head>\n' +
      `<docTitle><text>${safeTitle}</text></docTitle>\n` +
      '<navMap>\n' +
      nav +
      '</navMap>\n' +
      '</ncx>\n'
  }

  private static htmlIndex(title: string, entries: DownloadExportEntry[]): string {
    const safeTitle: string = DownloadExportService.escapeXml(title)
    let body: string = ''
    for (let i: number = 0; i < entries.length; i++) {
      const imageName: string = DownloadExportService.escapeXml(entries[i].entryName)
      body += `<img src="images/${imageName}" alt="${i + 1}"/>\n`
    }
    return '<!doctype html>\n' +
      '<html lang="und">\n' +
      '<head>\n' +
      '<meta charset="utf-8"/>\n' +
      '<meta name="viewport" content="width=device-width, initial-scale=1"/>\n' +
      `<title>${safeTitle}</title>\n` +
      '<link rel="stylesheet" href="style.css"/>\n' +
      '</head>\n' +
      '<body><main>\n' +
      body +
      '</main></body>\n' +
      '</html>\n'
  }

  private static mediaType(path: string): string {
    const lower: string = path.toLowerCase()
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp'
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif'
    }
    return 'image/jpeg'
  }

  private static fileExt(path: string): string {
    const slash: number = path.lastIndexOf('/')
    const dot: number = path.lastIndexOf('.')
    if (dot > slash && dot < path.length - 1) {
      return path.substring(dot).toLowerCase()
    }
    return '.jpg'
  }

  private static pageName(page: number): string {
    return page.toString().padStart(4, '0')
  }

  private static safeBaseName(title: string, fallback: string): string {
    const source: string = title.length > 0 ? title : fallback
    let out: string = ''
    for (let i: number = 0; i < source.length && out.length < 96; i++) {
      const ch: string = source.charAt(i)
      if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' ||
        ch === '"' || ch === '<' || ch === '>' || ch === '|') {
        out += '_'
      } else {
        out += ch
      }
    }
    return out.length > 0 ? out : 'download'
  }

  private static escapeXml(text: string): string {
    return text.replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;')
  }

  private static async exportDir(context: common.UIAbilityContext): Promise<string> {
    return await DownloadQueueSettings.ensureDownloadExportDir(context)
  }

  private static unlinkIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path)
    } catch (_error) {
    }
  }

  private static async copyFile(sourcePath: string, targetPath: string): Promise<void> {
    let src: fileIo.File | null = null
    let dest: fileIo.File | null = null
    try {
      src = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY)
      dest = fileIo.openSync(targetPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      await fileIo.copyFile(src.fd, dest.fd)
    } finally {
      if (src !== null) {
        fileIo.closeSync(src)
      }
      if (dest !== null) {
        fileIo.closeSync(dest)
      }
    }
  }
}

class PdfImageWriter {
  private static readonly CHUNK_SIZE: number = 256 * 1024
  private static readonly KIND_JPEG: string = 'jpeg'
  private static readonly KIND_PNG: string = 'png'

  static async write(filePath: string, entries: DownloadExportEntry[]): Promise<void> {
    const images: PdfImageInfo[] = []
    for (let i: number = 0; i < entries.length; i++) {
      images.push(PdfImageWriter.imageInfo(entries[i].sourcePath))
    }
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      const objectCount: number = 2 + images.length * 4
      const offsets: number[] = []
      for (let i: number = 0; i <= objectCount; i++) {
        offsets.push(0)
      }
      let offset: number = 0
      offset += PdfImageWriter.writeAscii(file, '%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n')
      offset = PdfImageWriter.writeObject(file, offsets, 1, offset,
        '<< /Type /Catalog /Pages 2 0 R >>\n')
      offset = PdfImageWriter.writeObject(file, offsets, 2, offset,
        PdfImageWriter.pagesObject(images.length))
      for (let i: number = 0; i < images.length; i++) {
        const pageId: number = PdfImageWriter.pageObjectId(i)
        const imageId: number = PdfImageWriter.imageObjectId(i)
        const alphaId: number = PdfImageWriter.alphaObjectId(i)
        const contentId: number = PdfImageWriter.contentObjectId(i)
        const imageInfo: PdfImageInfo = images[i]
        offset = PdfImageWriter.writeObject(file, offsets, pageId, offset,
          PdfImageWriter.pageObject(imageInfo, imageId, contentId))
        offset = await PdfImageWriter.writeImageObject(file, offsets, imageId, alphaId, offset, imageInfo)
        offset = await PdfImageWriter.writeAlphaObject(file, offsets, alphaId, offset, imageInfo)
        offset = PdfImageWriter.writeObject(file, offsets, contentId, offset,
          PdfImageWriter.contentObject(imageInfo))
      }
      const xrefOffset: number = offset
      offset += PdfImageWriter.writeAscii(file, `xref\n0 ${objectCount + 1}\n`)
      offset += PdfImageWriter.writeAscii(file, '0000000000 65535 f \n')
      for (let i: number = 1; i <= objectCount; i++) {
        offset += PdfImageWriter.writeAscii(file, `${offsets[i].toString().padStart(10, '0')} 00000 n \n`)
      }
      offset += PdfImageWriter.writeAscii(file,
        `trailer\n<< /Size ${objectCount + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static pagesObject(count: number): string {
    let kids: string = ''
    for (let i: number = 0; i < count; i++) {
      kids += `${PdfImageWriter.pageObjectId(i)} 0 R `
    }
    return `<< /Type /Pages /Kids [ ${kids}] /Count ${count} >>\n`
  }

  private static pageObject(image: PdfImageInfo, imageId: number, contentId: number): string {
    return `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${image.width} ${image.height}] ` +
      `/Resources << /XObject << /Im0 ${imageId} 0 R >> >> /Contents ${contentId} 0 R >>\n`
  }

  private static contentObject(image: PdfImageInfo): string {
    const content: string = `q\n${image.width} 0 0 ${image.height} 0 0 cm\n/Im0 Do\nQ\n`
    return `<< /Length ${new util.TextEncoder().encodeInto(content).byteLength} >>\nstream\n` +
      content +
      'endstream\n'
  }

  private static writeObject(
    file: fileIo.File,
    offsets: number[],
    objectId: number,
    offset: number,
    body: string,
  ): number {
    offsets[objectId] = offset
    let next: number = offset
    next += PdfImageWriter.writeAscii(file, `${objectId} 0 obj\n`)
    next += PdfImageWriter.writeAscii(file, body)
    next += PdfImageWriter.writeAscii(file, 'endobj\n')
    return next
  }

  private static async writeImageObject(
    file: fileIo.File,
    offsets: number[],
    objectId: number,
    alphaObjectId: number,
    offset: number,
    imageInfo: PdfImageInfo,
  ): Promise<number> {
    offsets[objectId] = offset
    let next: number = offset
    next += PdfImageWriter.writeAscii(file, `${objectId} 0 obj\n`)
    next += PdfImageWriter.writeAscii(file, PdfImageWriter.imageHeader(imageInfo, alphaObjectId))
    if (imageInfo.useDecodedRgba) {
      next += await PdfImageWriter.writeDecodedRgb(file, imageInfo)
    } else if (imageInfo.kind === PdfImageWriter.KIND_PNG) {
      next += PdfImageWriter.writePngIdat(file, imageInfo)
    } else {
      next += PdfImageWriter.writeFileBytes(file, imageInfo.sourcePath)
    }
    next += PdfImageWriter.writeAscii(file, '\nendstream\nendobj\n')
    return next
  }

  private static async writeAlphaObject(
    file: fileIo.File,
    offsets: number[],
    objectId: number,
    offset: number,
    imageInfo: PdfImageInfo,
  ): Promise<number> {
    if (!imageInfo.useDecodedRgba) {
      return PdfImageWriter.writeObject(file, offsets, objectId, offset, 'null\n')
    }
    offsets[objectId] = offset
    let next: number = offset
    next += PdfImageWriter.writeAscii(file, `${objectId} 0 obj\n`)
    next += PdfImageWriter.writeAscii(file,
      `<< /Type /XObject /Subtype /Image /Width ${imageInfo.width} /Height ${imageInfo.height} ` +
        `/ColorSpace /DeviceGray /BitsPerComponent 8 /Length ${imageInfo.alphaStreamLength} >>\nstream\n`)
    next += await PdfImageWriter.writeDecodedAlpha(file, imageInfo)
    next += PdfImageWriter.writeAscii(file, '\nendstream\nendobj\n')
    return next
  }

  private static imageHeader(imageInfo: PdfImageInfo, alphaObjectId: number): string {
    if (imageInfo.useDecodedRgba) {
      return `<< /Type /XObject /Subtype /Image /Width ${imageInfo.width} /Height ${imageInfo.height} ` +
        `/ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask ${alphaObjectId} 0 R /Length ${imageInfo.streamLength} >>\nstream\n`
    }
    if (imageInfo.kind === PdfImageWriter.KIND_PNG) {
      return `<< /Type /XObject /Subtype /Image /Width ${imageInfo.width} /Height ${imageInfo.height} ` +
        `/ColorSpace ${imageInfo.colorSpace} /BitsPerComponent ${imageInfo.bits} /Filter /FlateDecode ` +
        `/DecodeParms << /Predictor 15 /Colors ${imageInfo.colors} /BitsPerComponent ${imageInfo.bits} /Columns ${imageInfo.width} >> ` +
        `/Length ${imageInfo.streamLength} >>\nstream\n`
    }
    return `<< /Type /XObject /Subtype /Image /Width ${imageInfo.width} /Height ${imageInfo.height} ` +
      `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${imageInfo.streamLength} >>\nstream\n`
  }

  private static imageInfo(path: string): PdfImageInfo {
    const header: Uint8Array = PdfImageWriter.readFileHeader(path, 16)
    if (PdfImageWriter.isPng(header)) {
      return PdfImageWriter.pngInfo(path)
    }
    if (PdfImageWriter.isJpeg(header)) {
      return PdfImageWriter.jpegInfo(path)
    }
    throw new Error('PDF export supports JPEG and PNG images')
  }

  private static pngInfo(path: string): PdfImageInfo {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const signature: Uint8Array = PdfImageWriter.readExact(file, 8)
      if (!PdfImageWriter.isPng(signature)) {
        throw new Error('invalid PNG image')
      }
      let position: number = 8
      const image: PdfImageInfo = new PdfImageInfo()
      image.sourcePath = path
      image.kind = PdfImageWriter.KIND_PNG
      while (true) {
        const lengthBytes: Uint8Array = PdfImageWriter.readExact(file, 4)
        position += 4
        const length: number = PdfImageWriter.readU32(lengthBytes, 0)
        const typeBytes: Uint8Array = PdfImageWriter.readExact(file, 4)
        position += 4
        const chunkType: string = PdfImageWriter.chunkType(typeBytes)
        if (chunkType === 'IHDR') {
          const ihdr: Uint8Array = PdfImageWriter.readExact(file, length)
          position += length
          image.width = PdfImageWriter.readU32(ihdr, 0)
          image.height = PdfImageWriter.readU32(ihdr, 4)
          image.bits = ihdr[8]
          const colorType: number = ihdr[9]
          PdfImageWriter.applyPngColor(image, colorType)
          PdfImageWriter.skipBytes(file, 4)
          position += 4
        } else if (chunkType === 'PLTE') {
          const palette: Uint8Array = PdfImageWriter.readExact(file, length)
          position += length
          PdfImageWriter.applyPngPalette(image, palette)
          PdfImageWriter.skipBytes(file, 4)
          position += 4
        } else if (chunkType === 'IDAT') {
          if (image.useDecodedRgba) {
            PdfImageWriter.skipBytes(file, length + 4)
            position += length + 4
            continue
          }
          const range: PngIdatRange = new PngIdatRange()
          range.offset = position
          range.length = length
          image.idatRanges.push(range)
          image.streamLength += length
          PdfImageWriter.skipBytes(file, length + 4)
          position += length + 4
        } else {
          PdfImageWriter.skipBytes(file, length + 4)
          position += length + 4
        }
        if (chunkType === 'IEND') {
          break
        }
      }
      if (image.width <= 0 || image.height <= 0 || image.streamLength <= 0) {
        throw new Error('invalid PNG image')
      }
      if (image.pngColorType === 3) {
        if (image.paletteColors <= 0) {
          throw new Error('indexed PNG palette unavailable')
        }
        image.colorSpace = `[/Indexed /DeviceRGB ${image.paletteColors - 1} <${image.paletteHex}>]`
      }
      return image
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static applyPngColor(image: PdfImageInfo, colorType: number): void {
    image.pngColorType = colorType
    if (colorType === 3) {
      if (image.bits !== 1 && image.bits !== 2 && image.bits !== 4 && image.bits !== 8) {
        throw new Error(`PDF export does not support indexed PNG bit depth ${image.bits}`)
      }
      image.colors = 1
      return
    }
    if (image.bits !== 8) {
      throw new Error('PDF export supports 8-bit PNG images')
    }
    if (colorType === 0) {
      image.colors = 1
      image.colorSpace = '/DeviceGray'
      return
    }
    if (colorType === 2) {
      image.colors = 3
      image.colorSpace = '/DeviceRGB'
      return
    }
    if (colorType === 6) {
      image.colors = 4
      image.colorSpace = '/DeviceRGB'
      image.streamLength = image.width * image.height * 3
      image.alphaStreamLength = image.width * image.height
      image.useDecodedRgba = true
      return
    }
    throw new Error(`PDF export does not support PNG color type ${colorType}`)
  }

  private static applyPngPalette(image: PdfImageInfo, palette: Uint8Array): void {
    if (palette.byteLength === 0 || palette.byteLength % 3 !== 0) {
      throw new Error('invalid PNG palette')
    }
    image.paletteColors = palette.byteLength / 3
    let hex: string = ''
    for (let i: number = 0; i < palette.byteLength; i++) {
      hex += palette[i].toString(16).padStart(2, '0')
    }
    image.paletteHex = hex
  }

  private static jpegInfo(path: string): PdfImageInfo {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const soi: Uint8Array = PdfImageWriter.readExact(file, 2)
      if (soi[0] !== 0xff || soi[1] !== 0xd8) {
        throw new Error('invalid JPEG image')
      }
      while (true) {
        let markerPrefix: number = PdfImageWriter.readByte(file)
        while (markerPrefix !== 0xff) {
          markerPrefix = PdfImageWriter.readByte(file)
        }
        let marker: number = PdfImageWriter.readByte(file)
        while (marker === 0xff) {
          marker = PdfImageWriter.readByte(file)
        }
        if (marker === 0xd9 || marker === 0xda) {
          break
        }
        if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
          continue
        }
        const lengthBytes: Uint8Array = PdfImageWriter.readExact(file, 2)
        const length: number = PdfImageWriter.readU16(lengthBytes, 0)
        if (length < 2) {
          throw new Error('invalid JPEG segment')
        }
        if (PdfImageWriter.isJpegSof(marker)) {
          const segment: Uint8Array = PdfImageWriter.readExact(file, length - 2)
          const image: PdfImageInfo = new PdfImageInfo()
          image.sourcePath = path
          image.kind = PdfImageWriter.KIND_JPEG
          image.bits = segment[0]
          image.height = PdfImageWriter.readU16(segment, 1)
          image.width = PdfImageWriter.readU16(segment, 3)
          image.streamLength = fileIo.statSync(path).size
          return image
        }
        PdfImageWriter.skipBytes(file, length - 2)
      }
      throw new Error('JPEG image size unavailable')
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static isJpegSof(marker: number): boolean {
    return marker === 0xc0 || marker === 0xc1 || marker === 0xc2 || marker === 0xc3 ||
      marker === 0xc5 || marker === 0xc6 || marker === 0xc7 || marker === 0xc9 ||
      marker === 0xca || marker === 0xcb || marker === 0xcd || marker === 0xce ||
      marker === 0xcf
  }

  private static writePngIdat(file: fileIo.File, image: PdfImageInfo): number {
    let source: fileIo.File | null = null
    try {
      source = fileIo.openSync(image.sourcePath, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(PdfImageWriter.CHUNK_SIZE)
      let written: number = 0
      for (let i: number = 0; i < image.idatRanges.length; i++) {
        const range: PngIdatRange = image.idatRanges[i]
        let remaining: number = range.length
        let position: number = range.offset
        while (remaining > 0) {
          const chunk: number = Math.min(PdfImageWriter.CHUNK_SIZE, remaining)
          const read: number = fileIo.readSync(source.fd, buffer, { offset: position, length: chunk })
          if (read <= 0) {
            throw new Error('PNG stream read failed')
          }
          fileIo.writeSync(file.fd, buffer, { length: read })
          position += read
          remaining -= read
          written += read
        }
      }
      return written
    } finally {
      if (source !== null) {
        fileIo.closeSync(source)
      }
    }
  }

  private static writeFileBytes(file: fileIo.File, path: string): number {
    let source: fileIo.File | null = null
    try {
      source = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(PdfImageWriter.CHUNK_SIZE)
      let written: number = 0
      while (true) {
        const read: number = fileIo.readSync(source.fd, buffer, { length: PdfImageWriter.CHUNK_SIZE })
        if (read <= 0) {
          break
        }
        fileIo.writeSync(file.fd, buffer, { length: read })
        written += read
      }
      return written
    } finally {
      if (source !== null) {
        fileIo.closeSync(source)
      }
    }
  }

  private static async writeDecodedRgb(file: fileIo.File, imageInfo: PdfImageInfo): Promise<number> {
    return await PdfImageWriter.writeDecodedRgbaChannel(file, imageInfo, false)
  }

  private static async writeDecodedAlpha(file: fileIo.File, imageInfo: PdfImageInfo): Promise<number> {
    return await PdfImageWriter.writeDecodedRgbaChannel(file, imageInfo, true)
  }

  private static async writeDecodedRgbaChannel(
    file: fileIo.File,
    imageInfo: PdfImageInfo,
    alphaOnly: boolean,
  ): Promise<number> {
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      source = image.createImageSource(imageInfo.sourcePath)
      const options: image.DecodingOptions = {
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      }
      pixelMap = await source.createPixelMap(options)
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      const width: number = Math.floor(info.size.width)
      const height: number = Math.floor(info.size.height)
      if (width !== imageInfo.width || height !== imageInfo.height) {
        throw new Error('decoded image size changed')
      }
      const inputBuffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
      await pixelMap.readPixelsToBuffer(inputBuffer)
      const input: Uint8Array = new Uint8Array(inputBuffer)
      const stride: number = Math.max(Math.floor(info.stride), width * 4)
      const bytesPerPixel: number = alphaOnly ? 1 : 3
      const rowsPerChunk: number = Math.max(1, Math.floor(PdfImageWriter.CHUNK_SIZE / (width * bytesPerPixel)))
      const output: Uint8Array = new Uint8Array(rowsPerChunk * width * bytesPerPixel)
      let written: number = 0
      let row: number = 0
      while (row < height) {
        const chunkRows: number = Math.min(rowsPerChunk, height - row)
        let outputOffset: number = 0
        for (let y: number = 0; y < chunkRows; y++) {
          const sourceRow: number = (row + y) * stride
          for (let x: number = 0; x < width; x++) {
            const sourceOffset: number = sourceRow + x * 4
            if (alphaOnly) {
              output[outputOffset] = input[sourceOffset + 3]
              outputOffset += 1
            } else {
              output[outputOffset] = input[sourceOffset]
              output[outputOffset + 1] = input[sourceOffset + 1]
              output[outputOffset + 2] = input[sourceOffset + 2]
              outputOffset += 3
            }
          }
        }
        fileIo.writeSync(file.fd, output.buffer, { length: outputOffset })
        written += outputOffset
        row += chunkRows
      }
      return written
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release()
      }
      if (source !== undefined) {
        await source.release()
      }
    }
  }

  private static readFileHeader(path: string, length: number): Uint8Array {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      return PdfImageWriter.readExact(file, length)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static readExact(file: fileIo.File, length: number): Uint8Array {
    const buffer: ArrayBuffer = new ArrayBuffer(length)
    const read: number = fileIo.readSync(file.fd, buffer, { length: length })
    if (read !== length) {
      throw new Error('file read failed')
    }
    return new Uint8Array(buffer)
  }

  private static readByte(file: fileIo.File): number {
    const data: Uint8Array = PdfImageWriter.readExact(file, 1)
    return data[0]
  }

  private static skipBytes(file: fileIo.File, length: number): void {
    const buffer: ArrayBuffer = new ArrayBuffer(PdfImageWriter.CHUNK_SIZE)
    let remaining: number = length
    while (remaining > 0) {
      const chunk: number = Math.min(PdfImageWriter.CHUNK_SIZE, remaining)
      const read: number = fileIo.readSync(file.fd, buffer, { length: chunk })
      if (read <= 0) {
        throw new Error('file skip failed')
      }
      remaining -= read
    }
  }

  private static writeAscii(file: fileIo.File, text: string): number {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(text)
    return PdfImageWriter.writeBytes(file, bytes)
  }

  private static writeBytes(file: fileIo.File, bytes: Uint8Array): number {
    const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    return fileIo.writeSync(file.fd, buffer)
  }

  private static pageObjectId(index: number): number {
    return 3 + index * 4
  }

  private static imageObjectId(index: number): number {
    return 4 + index * 4
  }

  private static alphaObjectId(index: number): number {
    return 5 + index * 4
  }

  private static contentObjectId(index: number): number {
    return 6 + index * 4
  }

  private static isPng(bytes: Uint8Array): boolean {
    return bytes.byteLength >= 8 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
      bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  }

  private static isJpeg(bytes: Uint8Array): boolean {
    return bytes.byteLength >= 2 && bytes[0] === 0xff && bytes[1] === 0xd8
  }

  private static chunkType(bytes: Uint8Array): string {
    return String.fromCharCode(bytes[0]) + String.fromCharCode(bytes[1]) +
      String.fromCharCode(bytes[2]) + String.fromCharCode(bytes[3])
  }

  private static readU16(bytes: Uint8Array, offset: number): number {
    return ((bytes[offset] << 8) | bytes[offset + 1]) >>> 0
  }

  private static readU32(bytes: Uint8Array, offset: number): number {
    return ((bytes[offset] * 0x1000000) + (bytes[offset + 1] << 16) +
      (bytes[offset + 2] << 8) + bytes[offset + 3]) >>> 0
  }
}

class ZipStoreWriter {
  static async write(filePath: string, entries: ZipStoreEntry[]): Promise<void> {
    const payload: string = JSON.stringify(entries)
    await taskpool.execute<[string, string], string>(writeZipStoreFileTask, filePath, payload)
  }
}
