import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  DownloadArchiverTask,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
} from '../model/DownloadGalleryTask'
import { EhGalleryImage } from '../model/EhGalleryImage'
import { ReaderParams } from '../model/RouteParams'
import {
  ReaderSourceDescriptor,
  ReaderSourceKind,
  ReaderSourceVariant,
} from '../model/ReaderSource'
import { connectDownloadQueue } from '../state/DownloadQueueState'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ImagePipelineService } from './ImagePipelineService'
import { ArchiveImageService } from './ArchiveImageService'

/**
 * Converts completed download assets into an explicit Reader session.
 *
 * Entry pages should not rebuild local EhGalleryImage seeds themselves. Keeping selection and validation
 * here gives every Reader entry the same complete-set, local-first policy while preserving an exact task
 * when the user enters from the Downloads page.
 */
export class ReaderLocalSourceService {
  static galleryTaskParams(task: DownloadGalleryTask, index: number): ReaderParams | null {
    if (!ReaderLocalSourceService.isCompleteGalleryTask(task)) {
      return null
    }
    const sourceKey: string = ReaderLocalSourceService.gallerySourceKey(task)
    const images: EhGalleryImage[] = ReaderLocalSourceService.galleryImages(task, sourceKey)
    if (images.length === 0) {
      return null
    }
    const source: ReaderSourceDescriptor = new ReaderSourceDescriptor(
      ReaderSourceKind.GALLERY_DOWNLOAD,
      task.preferOriginal ? ReaderSourceVariant.ORIGINAL : ReaderSourceVariant.RESAMPLED,
      sourceKey,
      '',
    )
    return ReaderLocalSourceService.localParams(
      task.gid,
      task.token,
      index,
      task.displayTitle(),
      images,
      source,
    )
  }

  static async archiveTaskParams(
    context: common.UIAbilityContext,
    task: DownloadArchiverTask,
    index: number,
  ): Promise<ReaderParams | null> {
    if (!ReaderLocalSourceService.isCompleteArchiveTask(task)) {
      return null
    }
    const images: EhGalleryImage[] = await ArchiveImageService.imagesForTask(context, task)
    if (images.length === 0) {
      return null
    }
    const source: ReaderSourceDescriptor = new ReaderSourceDescriptor(
      ReaderSourceKind.ARCHIVE,
      ReaderLocalSourceService.isOriginalArchive(task)
        ? ReaderSourceVariant.ORIGINAL
        : ReaderSourceVariant.RESAMPLED,
      ReaderLocalSourceService.archiveSourceKey(task),
      task.resolution,
    )
    return ReaderLocalSourceService.localParams(
      task.gid,
      task.token,
      index,
      task.displayTitle(),
      images,
      source,
    )
  }

  /** Returns the original params when no complete, readable local source exists. */
  static async preferLocal(
    context: common.UIAbilityContext,
    params: ReaderParams,
  ): Promise<ReaderParams> {
    if (params.source.isLocal()) {
      return params
    }
    const galleryTasks: DownloadGalleryTask[] = connectDownloadQueue().galleryTasks
      .filter((task: DownloadGalleryTask) => task.gid === params.gid)
      .sort((left: DownloadGalleryTask, right: DownloadGalleryTask) => {
        const leftExact: number = params.token.length > 0 && left.token === params.token ? 1 : 0
        const rightExact: number = params.token.length > 0 && right.token === params.token ? 1 : 0
        if (leftExact !== rightExact) {
          return rightExact - leftExact
        }
        if (left.preferOriginal !== right.preferOriginal) {
          return left.preferOriginal ? 1 : -1
        }
        return right.queuedAt - left.queuedAt
      })
    for (let i: number = 0; i < galleryTasks.length; i++) {
      const prepared: ReaderParams | null = ReaderLocalSourceService.galleryTaskParams(
        galleryTasks[i],
        params.index,
      )
      if (prepared !== null) {
        prepared.initialChromeVisible = params.initialChromeVisible
        ReaderLocalSourceService.logSelection(prepared)
        return prepared
      }
    }

    const archiveTasks: DownloadArchiverTask[] = connectDownloadQueue().archiverTasks
      .filter((task: DownloadArchiverTask) => task.gid === params.gid)
      .sort((left: DownloadArchiverTask, right: DownloadArchiverTask) => {
        const leftOriginal: boolean = ReaderLocalSourceService.isOriginalArchive(left)
        const rightOriginal: boolean = ReaderLocalSourceService.isOriginalArchive(right)
        if (leftOriginal !== rightOriginal) {
          return leftOriginal ? 1 : -1
        }
        const leftAt: number = left.downloadedAt > 0 ? left.downloadedAt : left.queuedAt
        const rightAt: number = right.downloadedAt > 0 ? right.downloadedAt : right.queuedAt
        return rightAt - leftAt
      })
    for (let i: number = 0; i < archiveTasks.length; i++) {
      try {
        const prepared: ReaderParams | null = await ReaderLocalSourceService.archiveTaskParams(
          context,
          archiveTasks[i],
          params.index,
        )
        if (prepared !== null) {
          prepared.initialChromeVisible = params.initialChromeVisible
          ReaderLocalSourceService.logSelection(prepared)
          return prepared
        }
      } catch (error) {
        DiagnosticLogger.warn(
          'reader',
          'local_archive_prepare_failed',
          `gid=${params.gid} tagHash=${DiagnosticLogger.ownerHash(archiveTasks[i].tag)} error=${(error as Error).message}`,
        )
      }
    }
    DiagnosticLogger.info('reader', 'reader_source_selected', `gid=${params.gid} kind=online`)
    return params
  }

  private static localParams(
    gid: string,
    token: string,
    index: number,
    title: string,
    images: EhGalleryImage[],
    source: ReaderSourceDescriptor,
  ): ReaderParams {
    const clampedIndex: number = Math.max(0, Math.min(images.length - 1, index))
    return new ReaderParams(
      gid,
      token,
      clampedIndex,
      images.length,
      title,
      images,
      0,
      0,
      [],
      '',
      false,
      source,
    )
  }

  private static galleryImages(task: DownloadGalleryTask, sourceKey: string): EhGalleryImage[] {
    const seeds: DownloadImageSeed[] = task.imageSeeds.map((seed: DownloadImageSeed) => seed.copy())
    seeds.sort((left: DownloadImageSeed, right: DownloadImageSeed) => left.page - right.page)
    const expected: number = task.expectedFileCount()
    if (expected <= 0 || seeds.length !== expected) {
      return []
    }
    const images: EhGalleryImage[] = []
    for (let i: number = 0; i < seeds.length; i++) {
      const seed: DownloadImageSeed = seeds[i]
      if (seed.page !== i + 1 || ReaderLocalSourceService.fileSize(seed.filePath) <= 0) {
        return []
      }
      const image: EhGalleryImage = new EhGalleryImage(seed.page)
      image.imgkey = seed.imgkey
      image.sUrl = seed.imagePageUrl.length > 0
        ? seed.imagePageUrl
        : `download://${sourceKey}/${seed.page}`
      image.thumbUrl = seed.thumbUrl
      image.imageUrl = ImagePipelineService.displayUri(seed.filePath)
      image.originImageUrl = seed.originImageUrl
      image.showKey = seed.showKey
      image.reloadKey = seed.reloadKey
      images.push(image)
    }
    return images
  }

  private static isCompleteGalleryTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE && task.isDownloadComplete()
  }

  private static isCompleteArchiveTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE &&
      task.bytesWritten > 0 &&
      ReaderLocalSourceService.fileSize(task.filePath) > 0
  }

  private static isOriginalArchive(task: DownloadArchiverTask): boolean {
    return task.dltype === 'org' || task.resolution.toLowerCase().includes('original')
  }

  private static gallerySourceKey(task: DownloadGalleryTask): string {
    const quality: string = task.preferOriginal ? 'original' : 'resampled'
    return `download:${task.gid}:${quality}:${task.queuedAt}`
  }

  private static archiveSourceKey(task: DownloadArchiverTask): string {
    const stamp: number = task.downloadedAt > 0 ? task.downloadedAt : task.bytesWritten
    return `archive:${task.tag}:${stamp}`
  }

  private static fileSize(path: string): number {
    if (path.length === 0) {
      return 0
    }
    try {
      if (!fileIo.accessSync(path)) {
        return 0
      }
      return fileIo.statSync(path).size
    } catch (_error) {
      return 0
    }
  }

  private static logSelection(params: ReaderParams): void {
    DiagnosticLogger.info(
      'reader',
      'reader_source_selected',
      `gid=${params.gid} kind=${params.source.kind} variant=${params.source.variant} pages=${params.fileCount} sourceHash=${DiagnosticLogger.ownerHash(params.source.sourceKey)}`,
    )
  }
}
