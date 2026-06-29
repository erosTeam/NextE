import { common } from '@kit.AbilityKit'
import { zlib } from '@kit.BasicServicesKit'
import { fileIo } from '@kit.CoreFileKit'
import { DownloadArchiverTask } from '../model/DownloadGalleryTask'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { CachedImageFileService } from './CachedImageFileService'

const ARCHIVE_IMAGE_CACHE_DIR: string = 'download-archiver-read'

/** Extracts a completed local archive into Reader-ready file:// images. */
export class ArchiveImageService {
  static async imagesForTask(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
  ): Promise<EhGalleryImage[]> {
    if (task.filePath.length === 0 || !fileIo.accessSync(task.filePath)) {
      throw new Error('archive file missing')
    }
    const outDir: string = ArchiveImageService.extractDir(context, task)
    ArchiveImageService.ensureDir(outDir)

    let paths: string[] = ArchiveImageService.listImageFiles(outDir)
    if (paths.length === 0) {
      try {
        const startedAt: number = Date.now()
        const options: zlib.Options = {
          parallel: zlib.ParallelStrategy.PARALLEL_STRATEGY_PARALLEL_DECOMPRESSION,
          pathSeparatorStrategy: zlib.PathSeparatorStrategy.PATH_SEPARATOR_STRATEGY_REPLACE_BACKSLASH,
        }
        DiagnosticLogger.info('download', 'archive_extract_start', `tag=${task.tag}`)
        await zlib.decompressFile(task.filePath, outDir, options)
        DiagnosticLogger.info('download', 'archive_extract_done', `tag=${task.tag} elapsedMs=${Date.now() - startedAt}`)
      } catch (error) {
        ArchiveImageService.deletePath(outDir)
        throw error as Error
      }
      paths = ArchiveImageService.listImageFiles(outDir)
    }
    if (paths.length === 0) {
      ArchiveImageService.deletePath(outDir)
      throw new Error('archive has no readable images')
    }
    paths.sort((a: string, b: string) => ArchiveImageService.naturalPathCompare(a, b))

    const images: EhGalleryImage[] = []
    for (let i: number = 0; i < paths.length; i++) {
      const page: number = i + 1
      const image: EhGalleryImage = new EhGalleryImage(page)
      image.sUrl = `archive://${task.tag}/${page}`
      image.imageUrl = CachedImageFileService.displayUri(paths[i])
      images.push(image)
    }
    DiagnosticLogger.info('download', 'archive_reader_images', `tag=${task.tag} images=${images.length}`)
    return images
  }

  private static extractDir(context: common.UIAbilityContext, task: DownloadArchiverTask): string {
    const stamp: string = task.downloadedAt > 0 ? `${task.downloadedAt}` : `${task.bytesWritten}`
    return `${context.cacheDir}/${ARCHIVE_IMAGE_CACHE_DIR}/${ArchiveImageService.safePathPart(task.tag)}-${stamp}`
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
