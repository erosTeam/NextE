import { common } from '@kit.AbilityKit'
import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { DownloadArchiverTask } from '../model/DownloadGalleryTask'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImagePipelineService } from './ImagePipelineService'

const ARCHIVE_IMAGE_CACHE_DIR: string = 'download-archiver-read'
const ARCHIVE_COMPLETE_MARKER_PREFIX: string = 'complete:'

/** Extracts a completed local archive into Reader-ready file:// images. */
export class ArchiveImageService {
  private static extracting: Map<string, Promise<string[]>> = new Map<string, Promise<string[]>>()

  static async imagesForTask(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<EhGalleryImage[]> {
    const paths: string[] = await ArchiveImageService.imagePathsForTask(context, task)
    const images: EhGalleryImage[] = []
    for (let i: number = 0; i < paths.length; i++) {
      const page: number = i + 1
      const image: EhGalleryImage = new EhGalleryImage(page)
      image.sUrl = `archive://${task.tag}/${page}`
      image.imageUrl = ImagePipelineService.displayUri(paths[i])
      images.push(image)
    }
    DiagnosticLogger.info('download', 'archive_reader_images', `tag=${task.tag} images=${images.length}`)
    return images
  }

  static async imagePathsForTask(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<string[]> {
    if (task.filePath.length === 0 || !fileIo.accessSync(task.filePath)) {
      throw new Error('archive file missing')
    }
    const outDir: string = ArchiveImageService.extractDir(context, task)
    const pending: Promise<string[]> | undefined = ArchiveImageService.extracting.get(outDir)
    if (pending !== undefined) {
      return pending
    }
    const extracting: Promise<string[]> = ArchiveImageService.completeImagePaths(task, outDir)
    ArchiveImageService.extracting.set(outDir, extracting)
    try {
      return await extracting
    } finally {
      ArchiveImageService.extracting.delete(outDir)
    }
  }

  private static async completeImagePaths(task: DownloadArchiverTask, outDir: string): Promise<string[]> {
    const markerPath: string = `${outDir}.complete`
    let paths: string[] = ArchiveImageService.listImageFiles(outDir)
    // A process can stop midway through decompression. Only a separately written completion
    // marker with the same image count permits reuse; legacy caches have no such receipt.
    if (!ArchiveImageService.isCompleteCache(markerPath, paths.length)) {
      ArchiveImageService.deletePath(markerPath)
      ArchiveImageService.deletePath(outDir)
      if (fileIo.accessSync(markerPath) || fileIo.accessSync(outDir)) {
        throw new Error('incomplete archive cache could not be removed')
      }
      ArchiveImageService.ensureDir(outDir)
      try {
        const startedAt: number = Date.now()
        const options: zlib.Options = {
          parallel: zlib.ParallelStrategy.PARALLEL_STRATEGY_PARALLEL_DECOMPRESSION,
          pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH,
        }
        DiagnosticLogger.info('download', 'archive_extract_start', `tag=${task.tag}`)
        await zlib.decompressFile(task.filePath, outDir, options)
        paths = ArchiveImageService.listImageFiles(outDir)
        if (paths.length === 0) {
          throw new Error('archive has no readable images')
        }
        ArchiveImageService.writeCompleteMarker(markerPath, paths.length)
        DiagnosticLogger.info('download', 'archive_extract_done', `tag=${task.tag} elapsedMs=${Date.now() - startedAt}`)
      } catch (error) {
        ArchiveImageService.deletePath(markerPath)
        ArchiveImageService.deletePath(outDir)
        throw error as Error
      }
    }
    paths.sort((a: string, b: string) => ArchiveImageService.naturalPathCompare(a, b))
    return paths
  }

  private static isCompleteCache(markerPath: string, count: number): boolean {
    if (count <= 0) return false
    try {
      return fileIo.readTextSync(markerPath) === `${ARCHIVE_COMPLETE_MARKER_PREFIX}${count}`
    } catch (_error) {
      return false
    }
  }

  private static writeCompleteMarker(path: string, count: number): void {
    const text: string = `${ARCHIVE_COMPLETE_MARKER_PREFIX}${count}`
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      if (fileIo.writeSync(file.fd, text) !== text.length) {
        throw new Error('archive completion marker write incomplete')
      }
    } finally {
      fileIo.closeSync(file)
    }
  }

  private static extractDir(context: common.UIAbilityContext, task: DownloadArchiverTask): string {
    const stamp: string = task.downloadedAt > 0 ? `${task.downloadedAt}` : `${task.bytesWritten}`
    // Do not mutate a legacy extraction that may still be displayed by another reader session.
    return `${context.cacheDir}/${ARCHIVE_IMAGE_CACHE_DIR}/${ArchiveImageService.safePathPart(task.tag)}-${stamp}-verified-v1`
  }

  private static listImageFiles(dir: string): string[] {
    const out: string[] = []
    if (!fileIo.accessSync(dir)) {
      return out
    }
    const names: string[] = fileIo.listFileSync(dir)
    for (let i: number = 0; i < names.length; i++) {
      const path: string = `${dir}/${names[i]}`
      const stat: fileIo.Stat = fileIo.statSync(path)
      if (stat.isDirectory()) {
        const nested: string[] = ArchiveImageService.listImageFiles(path)
        for (let j: number = 0; j < nested.length; j++) {
          out.push(nested[j])
        }
      } else if (stat.isFile() && ArchiveImageService.isImagePath(path)) {
        out.push(path)
      }
    }
    return out
  }

  private static isImagePath(path: string): boolean {
    const lower: string = path.toLowerCase()
    return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heif')
  }

  private static naturalPathCompare(left: string, right: string): number {
    const a: string = left.toLowerCase()
    const b: string = right.toLowerCase()
    let ai: number = 0
    let bi: number = 0
    while (ai < a.length && bi < b.length) {
      const ac: number = a.charCodeAt(ai)
      const bc: number = b.charCodeAt(bi)
      if (ArchiveImageService.isDigit(ac) && ArchiveImageService.isDigit(bc)) {
        const aStart: number = ai
        const bStart: number = bi
        while (ai < a.length && ArchiveImageService.isDigit(a.charCodeAt(ai))) {
          ai++
        }
        while (bi < b.length && ArchiveImageService.isDigit(b.charCodeAt(bi))) {
          bi++
        }
        const aNum: number = Number.parseInt(a.substring(aStart, ai), 10)
        const bNum: number = Number.parseInt(b.substring(bStart, bi), 10)
        if (aNum !== bNum) {
          return aNum - bNum
        }
        const lenDiff: number = (ai - aStart) - (bi - bStart)
        if (lenDiff !== 0) {
          return lenDiff
        }
        continue
      }
      if (ac !== bc) {
        return ac - bc
      }
      ai++
      bi++
    }
    return a.length - b.length
  }

  private static isDigit(code: number): boolean {
    return code >= 48 && code <= 57
  }

  private static safePathPart(value: string): string {
    return value.replace(/[/:*"<>|,?\\]/g, '_')
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

  private static deletePath(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        return
      }
      const stat: fileIo.Stat = fileIo.statSync(path)
      if (stat.isDirectory()) {
        fileIo.rmdirSync(path)
      } else {
        fileIo.unlinkSync(path)
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'archive_extract_delete_failed', (error as Error).message)
    }
  }
}
