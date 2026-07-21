import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY,
  MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY,
} from './MangaTranslatorUiSidecarProtocol'

const ZIP_LOCAL_HEADER_SIGNATURE: number = 0x04034b50
const ZIP_CENTRAL_HEADER_SIGNATURE: number = 0x02014b50
const ZIP_END_SIGNATURE: number = 0x06054b50
const ZIP_END_MIN_BYTES: number = 22
const ZIP_MAX_COMMENT_BYTES: number = 0xffff
const MAX_EXPORT_ARCHIVE_BYTES: number = 6 * 1024 * 1024
const MAX_EXPORT_JSON_BYTES: number = 4 * 1024 * 1024
const MAX_EXPORT_TEXT_BYTES: number = 1024 * 1024
const MAX_COMPRESSION_RATIO: number = 100
const SIDECAR_ARCHIVE_CACHE_DIR: string = 'manga-translator-ui-archive'

class SidecarZipEntry {
  name: string = ''
  flags: number = 0
  method: number = 0
  compressedBytes: number = 0
  uncompressedBytes: number = 0
  localHeaderOffset: number = 0
}

export class MangaTranslatorUiExportFiles {
  translationJson: Uint8Array = new Uint8Array(0)
  originalText: Uint8Array = new Uint8Array(0)
}

/**
 * Reads the pinned two-file export archive only after validating its central and
 * local ZIP records. zlib never sees an unchecked filename or unbounded entry.
 */
export class MangaTranslatorUiSidecarArchive {
  static async extract(
    context: common.UIAbilityContext,
    archive: Uint8Array,
  ): Promise<MangaTranslatorUiExportFiles> {
    MangaTranslatorUiSidecarArchive.inspect(archive)
    const operationId: string = util.generateRandomUUID(true)
    const root: string = `${context.cacheDir}/${SIDECAR_ARCHIVE_CACHE_DIR}/${operationId}`
    const zipPath: string = `${root}/export.zip`
    const outputDir: string = `${root}/contents`
    MangaTranslatorUiSidecarArchive.ensureDir(outputDir)
    try {
      MangaTranslatorUiSidecarArchive.writeExact(zipPath, archive)
      const options: zlib.Options = {
        parallel: zlib.ParallelStrategy.PARALLEL_STRATEGY_SEQUENTIAL,
        pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH,
      }
      await zlib.decompressFile(zipPath, outputDir, options)
      const names: string[] = fileIo.listFileSync(outputDir).sort()
      if (names.length !== 2 ||
        names[0] !== MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY ||
        names[1] !== MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY) {
        throw new Error('Manga translator UI export archive contents changed after extraction')
      }
      const files: MangaTranslatorUiExportFiles = new MangaTranslatorUiExportFiles()
      files.translationJson = MangaTranslatorUiSidecarArchive.readBounded(
        `${outputDir}/${MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY}`,
        MAX_EXPORT_JSON_BYTES,
      )
      files.originalText = MangaTranslatorUiSidecarArchive.readBounded(
        `${outputDir}/${MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY}`,
        MAX_EXPORT_TEXT_BYTES,
      )
      return files
    } finally {
      MangaTranslatorUiSidecarArchive.removeFile(
        `${outputDir}/${MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY}`,
      )
      MangaTranslatorUiSidecarArchive.removeFile(
        `${outputDir}/${MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY}`,
      )
      MangaTranslatorUiSidecarArchive.removeFile(zipPath)
      MangaTranslatorUiSidecarArchive.removeDir(outputDir)
      MangaTranslatorUiSidecarArchive.removeDir(root)
    }
  }

  static inspect(archive: Uint8Array): void {
    if (archive.length < ZIP_END_MIN_BYTES || archive.length > MAX_EXPORT_ARCHIVE_BYTES) {
      throw new Error('Manga translator UI export archive size is invalid')
    }
    const endOffset: number = MangaTranslatorUiSidecarArchive.findEndRecord(archive)
    const diskNumber: number = MangaTranslatorUiSidecarArchive.u16(archive, endOffset + 4)
    const centralDisk: number = MangaTranslatorUiSidecarArchive.u16(archive, endOffset + 6)
    const entriesOnDisk: number = MangaTranslatorUiSidecarArchive.u16(archive, endOffset + 8)
    const totalEntries: number = MangaTranslatorUiSidecarArchive.u16(archive, endOffset + 10)
    const centralBytes: number = MangaTranslatorUiSidecarArchive.u32(archive, endOffset + 12)
    const centralOffset: number = MangaTranslatorUiSidecarArchive.u32(archive, endOffset + 16)
    const commentBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, endOffset + 20)
    if (diskNumber !== 0 || centralDisk !== 0 || entriesOnDisk !== 2 || totalEntries !== 2 ||
      commentBytes !== 0 || centralOffset + centralBytes !== endOffset) {
      throw new Error('Manga translator UI export archive layout is invalid')
    }

    const entries: SidecarZipEntry[] = []
    let offset: number = centralOffset
    for (let index: number = 0; index < totalEntries; index++) {
      const entry: SidecarZipEntry = MangaTranslatorUiSidecarArchive.centralEntry(archive, offset)
      entries.push(entry)
      const nameBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 28)
      const extraBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 30)
      const entryCommentBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 32)
      offset += 46 + nameBytes + extraBytes + entryCommentBytes
    }
    if (offset !== endOffset) {
      throw new Error('Manga translator UI export central directory is invalid')
    }
    entries.sort((left: SidecarZipEntry, right: SidecarZipEntry): number =>
      left.name.localeCompare(right.name))
    if (entries[0].name !== MANGA_TRANSLATOR_UI_EXPORT_TEXT_ENTRY ||
      entries[1].name !== MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY) {
      throw new Error('Manga translator UI export archive entries are invalid')
    }
    for (let index: number = 0; index < entries.length; index++) {
      MangaTranslatorUiSidecarArchive.validateLocalEntry(archive, entries[index], centralOffset)
    }
  }

  private static centralEntry(archive: Uint8Array, offset: number): SidecarZipEntry {
    MangaTranslatorUiSidecarArchive.requireRange(archive, offset, 46)
    if (MangaTranslatorUiSidecarArchive.u32(archive, offset) !== ZIP_CENTRAL_HEADER_SIGNATURE) {
      throw new Error('Manga translator UI export central header is invalid')
    }
    const entry: SidecarZipEntry = new SidecarZipEntry()
    entry.flags = MangaTranslatorUiSidecarArchive.u16(archive, offset + 8)
    entry.method = MangaTranslatorUiSidecarArchive.u16(archive, offset + 10)
    entry.compressedBytes = MangaTranslatorUiSidecarArchive.u32(archive, offset + 20)
    entry.uncompressedBytes = MangaTranslatorUiSidecarArchive.u32(archive, offset + 24)
    const nameBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 28)
    const extraBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 30)
    const commentBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 32)
    const diskStart: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 34)
    entry.localHeaderOffset = MangaTranslatorUiSidecarArchive.u32(archive, offset + 42)
    MangaTranslatorUiSidecarArchive.requireRange(
      archive,
      offset + 46,
      nameBytes + extraBytes + commentBytes,
    )
    entry.name = MangaTranslatorUiSidecarArchive.ascii(archive, offset + 46, nameBytes)
    const maxBytes: number = entry.name === MANGA_TRANSLATOR_UI_EXPORT_JSON_ENTRY ?
      MAX_EXPORT_JSON_BYTES : MAX_EXPORT_TEXT_BYTES
    if ((entry.flags & ~0x0800) !== 0 || (entry.method !== 0 && entry.method !== 8) ||
      nameBytes <= 0 || extraBytes !== 0 || commentBytes !== 0 || diskStart !== 0 ||
      entry.uncompressedBytes > maxBytes || entry.compressedBytes > MAX_EXPORT_ARCHIVE_BYTES ||
      (entry.uncompressedBytes > 0 && entry.compressedBytes === 0) ||
      (entry.uncompressedBytes > 65536 &&
        entry.uncompressedBytes > entry.compressedBytes * MAX_COMPRESSION_RATIO)) {
      throw new Error('Manga translator UI export ZIP entry is unsafe')
    }
    return entry
  }

  private static validateLocalEntry(
    archive: Uint8Array,
    entry: SidecarZipEntry,
    centralOffset: number,
  ): void {
    const offset: number = entry.localHeaderOffset
    MangaTranslatorUiSidecarArchive.requireRange(archive, offset, 30)
    if (MangaTranslatorUiSidecarArchive.u32(archive, offset) !== ZIP_LOCAL_HEADER_SIGNATURE ||
      MangaTranslatorUiSidecarArchive.u16(archive, offset + 6) !== entry.flags ||
      MangaTranslatorUiSidecarArchive.u16(archive, offset + 8) !== entry.method ||
      MangaTranslatorUiSidecarArchive.u32(archive, offset + 18) !== entry.compressedBytes ||
      MangaTranslatorUiSidecarArchive.u32(archive, offset + 22) !== entry.uncompressedBytes) {
      throw new Error('Manga translator UI export local header is invalid')
    }
    const nameBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 26)
    const extraBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 28)
    MangaTranslatorUiSidecarArchive.requireRange(archive, offset + 30, nameBytes + extraBytes)
    const localName: string = MangaTranslatorUiSidecarArchive.ascii(archive, offset + 30, nameBytes)
    const dataEnd: number = offset + 30 + nameBytes + extraBytes + entry.compressedBytes
    if (localName !== entry.name || extraBytes !== 0 || dataEnd > centralOffset) {
      throw new Error('Manga translator UI export local entry is invalid')
    }
  }

  private static findEndRecord(archive: Uint8Array): number {
    const start: number = Math.max(0, archive.length - ZIP_END_MIN_BYTES - ZIP_MAX_COMMENT_BYTES)
    for (let offset: number = archive.length - ZIP_END_MIN_BYTES; offset >= start; offset--) {
      if (MangaTranslatorUiSidecarArchive.u32(archive, offset) === ZIP_END_SIGNATURE) {
        const commentBytes: number = MangaTranslatorUiSidecarArchive.u16(archive, offset + 20)
        if (offset + ZIP_END_MIN_BYTES + commentBytes === archive.length) {
          return offset
        }
      }
    }
    throw new Error('Manga translator UI export end record is missing')
  }

  private static u16(value: Uint8Array, offset: number): number {
    MangaTranslatorUiSidecarArchive.requireRange(value, offset, 2)
    return value[offset] | (value[offset + 1] << 8)
  }

  private static u32(value: Uint8Array, offset: number): number {
    MangaTranslatorUiSidecarArchive.requireRange(value, offset, 4)
    return (value[offset] |
      (value[offset + 1] << 8) |
      (value[offset + 2] << 16) |
      (value[offset + 3] << 24)) >>> 0
  }

  private static requireRange(value: Uint8Array, offset: number, length: number): void {
    if (!Number.isFinite(offset) || !Number.isFinite(length) || offset < 0 || length < 0 ||
      offset + length > value.length) {
      throw new Error('Manga translator UI export archive is truncated')
    }
  }

  private static ascii(value: Uint8Array, offset: number, length: number): string {
    MangaTranslatorUiSidecarArchive.requireRange(value, offset, length)
    let output: string = ''
    for (let index: number = 0; index < length; index++) {
      const code: number = value[offset + index]
      if (code < 0x20 || code > 0x7e) {
        throw new Error('Manga translator UI export filename is invalid')
      }
      output += String.fromCharCode(code)
    }
    return output
  }

  private static readBounded(path: string, maxBytes: number): Uint8Array {
    const stat: fileIo.Stat = fileIo.statSync(path)
    const length: number = Math.floor(stat.size)
    if (!stat.isFile() || length < 0 || length > maxBytes) {
      throw new Error('Manga translator UI extracted file size is invalid')
    }
    const output: Uint8Array = new Uint8Array(length)
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      while (offset < length) {
        const chunk: ArrayBuffer = new ArrayBuffer(length - offset)
        const read: number = fileIo.readSync(file.fd, chunk, { length: chunk.byteLength })
        if (read <= 0) {
          throw new Error('Manga translator UI extracted file is truncated')
        }
        output.set(new Uint8Array(chunk, 0, read), offset)
        offset += read
      }
      return output
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static writeExact(path: string, bytes: Uint8Array): void {
    let file: fileIo.File | null = null
    let offset: number = 0
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      while (offset < bytes.length) {
        const remaining: ArrayBuffer = bytes.buffer.slice(
          bytes.byteOffset + offset,
          bytes.byteOffset + bytes.byteLength,
        )
        const written: number = fileIo.writeSync(
          file.fd,
          remaining,
          { length: remaining.byteLength },
        )
        if (written <= 0) {
          throw new Error('Manga translator UI archive write failed')
        }
        offset += written
      }
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private static ensureDir(path: string): void {
    try {
      fileIo.mkdirSync(path, true)
    } catch (error) {
      if (!fileIo.accessSync(path)) {
        throw error as Error
      }
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private static removeDir(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.rmdirSync(path)
      }
    } catch (_error) {}
  }
}
