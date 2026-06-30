import {
  ThemeConstants,
  SecondaryListScaffold,
  CardEmptyState,
  AppStrings,
  ArchiveImageService,
  CachedImageFileService,
  DownloadArchiverTask,
  DownloadArchiverParseSource,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
  EhGalleryImage,
  EhThumbnail,
  GalleryDetailParams,
  ReaderParams,
  DownloadQueueSettings,
  DownloadQueueState,
  DownloadQueueSignalState,
  DownloadSettings,
  DownloadViewType,
  DownloadViewState,
  DiagnosticLogger,
  GalleryReadProgressState,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectGalleryReadProgress,
  connectSiteMode,
  connectDownloadQueue,
  connectDownloadQueueSignal,
  connectDownloadView,
  connectNavStack,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Downloads (下载) bottom tab — plain tab content hosted under Index's shared HDS title bar (no
 * NavDestination wrapper). Mirrors eros_fe's first-level split: Gallery downloads and Archiver
 * downloads are separate retained queues. Gallery tasks show seed preparation and sandbox image
 * download progress here; completed Gallery tasks enter the normal Reader with local file:// images.
 */
@ComponentV2
export struct DownloadQueuePage {
  // Accepted for the Index tab-scroller handoff (this placeholder doesn't scroll, so it's unused).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local downloadView: DownloadViewState = connectDownloadView();
  @Local downloadQueue: DownloadQueueState = connectDownloadQueue();
  @Local downloadQueueSignal: DownloadQueueSignalState = connectDownloadQueueSignal();
  @Local readProgress: GalleryReadProgressState = connectGalleryReadProgress();
  @Local downloadQueueTick: number = 0;
  @Local openingArchiverTag: string = '';
  @Local refreshingGalleryKey: string = '';
  @Local actionMenuKey: string = '';
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  @Monitor('downloadQueueSignal.version')
  private onDownloadQueueChanged(): void {
    this.downloadQueueTick = this.downloadQueueTick + 1
  }

  private selectedEmptyText(): Resource {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? $r('app.string.download_archiver_empty')
      : $r('app.string.download_gallery_empty')
  }

  private selectedNextStep(): Resource {
    return this.downloadView.viewType === DownloadViewType.ARCHIVER
      ? $r('app.string.download_archiver_next_step')
      : $r('app.string.download_gallery_next_step')
  }

  private taskStatusText(status: string, downloadedFiles: number, pageCount: number): string {
    return this.statusText(this.effectiveGalleryStatus(status, downloadedFiles, pageCount))
  }

  private statusText(status: string): string {
    if (status === DownloadGalleryTaskStatus.PREPARING) {
      return AppStrings.get('download_status_preparing')
    }
    if (status === DownloadGalleryTaskStatus.READY) {
      return AppStrings.get('download_status_ready')
    }
    if (status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return AppStrings.get('download_status_downloading')
    }
    if (status === DownloadGalleryTaskStatus.PAUSED) {
      return AppStrings.get('download_status_paused')
    }
    if (status === DownloadGalleryTaskStatus.PARTIAL) {
      return AppStrings.get('download_status_partial')
    }
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return AppStrings.get('download_status_complete')
    }
    if (status === DownloadGalleryTaskStatus.ERROR) {
      return AppStrings.get('download_status_error')
    }
    return AppStrings.get('download_status_queued')
  }

  private taskMetaText(task: DownloadGalleryTask): string {
    const parts: string[] = []
    if (task.pageCountText().length > 0) {
      parts.push(task.pageCountText())
    }
    if (task.category.length > 0) {
      parts.push(task.category)
    }
    return parts.join(' · ')
  }

  private taskProgressLabel(
    status: string,
    downloadedFiles: number,
    seededFiles: number,
    pageCount: number,
    prepareError: string,
  ): string {
    if (this.downloadQueue.revision < 0) {
      return ''
    }
    if (this.downloadQueueTick < 0) {
      return ''
    }
    const parts: string[] = []
    const total: number = Math.max(pageCount, downloadedFiles, seededFiles)
    const effectiveStatus: string = this.effectiveGalleryStatus(status, downloadedFiles, total)
    if (effectiveStatus === DownloadGalleryTaskStatus.COMPLETE) {
      return this.statusText(effectiveStatus)
    }
    const downloadProgress: string = this.progressText(downloadedFiles, total)
    const seedProgress: string = this.progressText(seededFiles, total)
    if (status === DownloadGalleryTaskStatus.ERROR) {
      if (downloadProgress.length > 0) {
        parts.push(this.statusText(effectiveStatus))
        parts.push(AppStrings.get('download_file_progress').replace('%s', downloadProgress))
        if (prepareError.length > 0) {
          parts.push(prepareError)
        }
        return parts.join(' · ')
      }
      if (seedProgress.length > 0) {
        parts.push(this.statusText(effectiveStatus))
        parts.push(AppStrings.get('download_seed_progress').replace('%s', seedProgress))
        if (prepareError.length > 0) {
          parts.push(prepareError)
        }
        return parts.join(' · ')
      }
      if (prepareError.length > 0) {
        return `${this.statusText(effectiveStatus)} · ${prepareError}`
      }
      return this.statusText(effectiveStatus)
    }
    if (downloadProgress.length > 0) {
      parts.push(this.statusText(effectiveStatus))
      parts.push(AppStrings.get('download_file_progress').replace('%s', downloadProgress))
      return parts.join(' · ')
    }
    if (seedProgress.length > 0) {
      if (effectiveStatus === DownloadGalleryTaskStatus.PREPARING || effectiveStatus === DownloadGalleryTaskStatus.READY) {
        parts.push(this.statusText(effectiveStatus))
      }
      parts.push(AppStrings.get('download_seed_progress').replace('%s', seedProgress))
      return parts.join(' · ')
    }
    return this.statusText(effectiveStatus)
  }

  private progressText(count: number, pageCount: number): string {
    if (count <= 0) {
      return ''
    }
    if (pageCount > 0) {
      return `${count}/${pageCount}`
    }
    return `${count}`
  }

  private activeDownloadRatio(activeBytesWritten: number, activeBytesTotal: number): number {
    if (activeBytesWritten <= 0 || activeBytesTotal <= 0) {
      return 0
    }
    return Math.max(0, Math.min(1, activeBytesWritten / activeBytesTotal))
  }

  private taskProgressRatio(
    status: string,
    downloadedFiles: number,
    seededFiles: number,
    pageCount: number,
    activeBytesWritten: number,
    activeBytesTotal: number,
  ): number {
    if (this.downloadQueue.revision < 0) {
      return 0
    }
    if (this.downloadQueueTick < 0) {
      return 0
    }
    const total: number = Math.max(pageCount, downloadedFiles, seededFiles)
    const effectiveStatus: string = this.effectiveGalleryStatus(status, downloadedFiles, total)
    if (effectiveStatus === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (total <= 0) {
      return 0
    }
    const active: number = this.activeDownloadRatio(activeBytesWritten, activeBytesTotal)
    if (downloadedFiles > 0 || active > 0) {
      return Math.max(0, Math.min(1, (downloadedFiles + active) / total))
    }
    if (seededFiles > 0) {
      return Math.max(0, Math.min(1, seededFiles / total))
    }
    return 0
  }

  private async removeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.removeGallery(this.ctx(), task.gid, task.token, task.preferOriginal)
  }

  private async removeArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.removeArchiver(this.ctx(), task.tag)
  }

  private async resumeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.downloadGalleryImages(this.ctx(), task.gid, task.token, task.preferOriginal)
  }

  private async pauseTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.pauseGalleryDownload(this.ctx(), task.gid, task.token, task.preferOriginal)
  }

  private taskKey(task: DownloadGalleryTask): string {
    return `${task.gid}:${task.token}:${task.preferOriginal ? 'original' : 'resample'}`
  }

  private safeForEachKeyPart(value: string): string {
    return value.replace(/[^A-Za-z0-9_]/g, '_')
  }

  private galleryRenderKey(task: DownloadGalleryTask): string {
    return `gallery_${this.safeForEachKeyPart(this.taskKey(task))}`
  }

  private archiverRenderKey(task: DownloadArchiverTask): string {
    return `archiver_${this.safeForEachKeyPart(task.tag)}`
  }

  private galleryActionKey(task: DownloadGalleryTask): string {
    return `gallery:${this.taskKey(task)}`
  }

  private archiverActionKey(task: DownloadArchiverTask): string {
    return `archiver:${task.tag}`
  }

  private currentGalleryTask(task: DownloadGalleryTask): DownloadGalleryTask {
    if (this.downloadQueue.revision < 0) {
      return task
    }
    if (this.downloadQueueTick < 0) {
      return task
    }
    const key: string = this.taskKey(task)
    for (let i: number = 0; i < this.downloadQueue.galleryTasks.length; i++) {
      const current: DownloadGalleryTask = this.downloadQueue.galleryTasks[i]
      if (this.taskKey(current) === key) {
        return current
      }
    }
    return task
  }

  private currentArchiverTask(task: DownloadArchiverTask): DownloadArchiverTask {
    if (this.downloadQueue.revision < 0) {
      return task
    }
    if (this.downloadQueueTick < 0) {
      return task
    }
    for (let i: number = 0; i < this.downloadQueue.archiverTasks.length; i++) {
      const current: DownloadArchiverTask = this.downloadQueue.archiverTasks[i]
      if (current.tag === task.tag) {
        return current
      }
    }
    return task
  }

  private closeActionMenu(): void {
    this.actionMenuKey = ''
  }

  private activeGalleryTask(): DownloadGalleryTask | undefined {
    if (!this.actionMenuKey.startsWith('gallery:')) {
      return undefined
    }
    const key: string = this.actionMenuKey.substring('gallery:'.length)
    for (let i: number = 0; i < this.downloadQueue.galleryTasks.length; i++) {
      const task: DownloadGalleryTask = this.downloadQueue.galleryTasks[i]
      if (this.taskKey(task) === key) {
        return task
      }
    }
    return undefined
  }

  private activeArchiverTask(): DownloadArchiverTask | undefined {
    if (!this.actionMenuKey.startsWith('archiver:')) {
      return undefined
    }
    const tag: string = this.actionMenuKey.substring('archiver:'.length)
    for (let i: number = 0; i < this.downloadQueue.archiverTasks.length; i++) {
      const task: DownloadArchiverTask = this.downloadQueue.archiverTasks[i]
      if (task.tag === tag) {
        return task
      }
    }
    return undefined
  }

  private activeGalleryCanRefresh(): boolean {
    const task: DownloadGalleryTask | undefined = this.activeGalleryTask()
    return task !== undefined && this.canRefreshTask(task)
  }

  private refreshActiveGalleryTask(): void {
    const task: DownloadGalleryTask | undefined = this.activeGalleryTask()
    this.closeActionMenu()
    if (task !== undefined) {
      this.refreshTask(task)
    }
  }

  private removeActiveGalleryTask(): void {
    const task: DownloadGalleryTask | undefined = this.activeGalleryTask()
    this.closeActionMenu()
    if (task !== undefined) {
      this.confirmDeleteGalleryTask(task)
    }
  }

  private removeActiveArchiverTask(): void {
    const task: DownloadArchiverTask | undefined = this.activeArchiverTask()
    this.closeActionMenu()
    if (task !== undefined) {
      this.confirmDeleteArchiverTask(task)
    }
  }

  private confirmDeleteGalleryTask(task: DownloadGalleryTask): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.download_delete_confirm_title'),
      message: $r('app.string.download_delete_confirm_message'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.download_delete_confirm_action'),
        fontColor: Color.Red,
        action: () => {
          this.removeTask(task)
        },
      },
    })
  }

  private confirmDeleteArchiverTask(task: DownloadArchiverTask): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.download_delete_confirm_title'),
      message: $r('app.string.download_delete_confirm_message'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.download_delete_confirm_action'),
        fontColor: Color.Red,
        action: () => {
          this.removeArchiverTask(task)
        },
      },
    })
  }

  private activeArchiverCanSwitchToBot(): boolean {
    const task: DownloadArchiverTask | undefined = this.activeArchiverTask()
    if (task === undefined || !DownloadSettings.archiveBotReady()) {
      return false
    }
    if (task.parseSource === DownloadArchiverParseSource.BOT ||
      task.status === DownloadGalleryTaskStatus.COMPLETE ||
      task.status === DownloadGalleryTaskStatus.DOWNLOADING) {
      return false
    }
    const resolution: string = task.resolution.toLowerCase()
    return task.dltype === 'org' || resolution.includes('original')
  }

  private switchActiveArchiverToBot(): void {
    const task: DownloadArchiverTask | undefined = this.activeArchiverTask()
    this.closeActionMenu()
    if (task !== undefined) {
      DownloadQueueSettings.switchArchiverToBot(this.ctx(), task.tag)
    }
  }

  private async refreshTask(task: DownloadGalleryTask): Promise<void> {
    if (this.refreshingGalleryKey.length > 0) {
      return
    }
    const key: string = this.taskKey(task)
    this.refreshingGalleryKey = key
    try {
      await DownloadQueueSettings.refreshGallerySeedsFromRemote(
        this.ctx(),
        task.gid,
        task.token,
        connectSiteMode().isEx,
        task.preferOriginal,
      )
    } catch (_error) {
      this.getUIContext()
        .getPromptAction()
        .openToast({ message: $r('app.string.common_refresh_failed') })
        .catch((_toastError: Error) => {})
    } finally {
      if (this.refreshingGalleryKey === key) {
        this.refreshingGalleryKey = ''
      }
    }
  }

  private async resumeArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.downloadArchiver(this.ctx(), task.tag)
  }

  private async pauseArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.pauseArchiverDownload(this.ctx(), task.tag)
  }

  private canResumeTask(task: DownloadGalleryTask): boolean {
    const status: string = this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount)
    return status === DownloadGalleryTaskStatus.QUEUED ||
      status === DownloadGalleryTaskStatus.ERROR ||
      status === DownloadGalleryTaskStatus.PAUSED ||
      status === DownloadGalleryTaskStatus.PARTIAL ||
      status === DownloadGalleryTaskStatus.READY
  }

  private galleryResumeActionIcon(task: DownloadGalleryTask): Resource {
    return $r('sys.symbol.play_fill')
  }

  private galleryResumeActionLabel(task: DownloadGalleryTask): Resource {
    const status: string = this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount)
    return status === DownloadGalleryTaskStatus.ERROR
      ? $r('app.string.common_retry')
      : $r('app.string.download_resume')
  }

  private canPauseTask(task: DownloadGalleryTask): boolean {
    return this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount) ===
      DownloadGalleryTaskStatus.DOWNLOADING
  }

  private canReadTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE && task.isDownloadComplete()
  }

  private openTaskIfComplete(task: DownloadGalleryTask): void {
    if (this.canReadTask(task)) {
      this.openDownloadedTask(task)
    }
  }

  private canRefreshTask(task: DownloadGalleryTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE &&
      task.isDownloadComplete() &&
      task.gid.length > 0 &&
      task.token.length > 0
  }

  private canResumeArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.ERROR ||
      task.status === DownloadGalleryTaskStatus.PREPARING ||
      task.status === DownloadGalleryTaskStatus.PAUSED ||
      task.status === DownloadGalleryTaskStatus.QUEUED
  }

  private archiverResumeActionIcon(task: DownloadArchiverTask): Resource {
    return $r('sys.symbol.play_fill')
  }

  private archiverResumeActionLabel(task: DownloadArchiverTask): Resource {
    return task.status === DownloadGalleryTaskStatus.ERROR
      ? $r('app.string.common_retry')
      : $r('app.string.download_resume')
  }

  private canPauseArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.DOWNLOADING
  }

  private canReadArchiverTask(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.COMPLETE && task.filePath.length > 0 && task.bytesWritten > 0
  }

  private openArchiverTaskIfComplete(task: DownloadArchiverTask): void {
    if (this.canReadArchiverTask(task)) {
      this.openArchiverTask(task)
    }
  }

  private archiverProgressRatio(task: DownloadArchiverTask): number {
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (task.bytesTotal > 0) {
      return Math.max(0, Math.min(1, task.bytesWritten / task.bytesTotal))
    }
    return Math.max(0, Math.min(1, task.progress / 100))
  }

  private archiverProgressLabel(task: DownloadArchiverTask): string {
    if (task.status === DownloadGalleryTaskStatus.COMPLETE) {
      return this.statusText(task.status)
    }
    if (task.status === DownloadGalleryTaskStatus.ERROR) {
      if (task.error.length > 0) {
        return `${this.statusText(task.status)} · ${task.error}`
      }
      return this.statusText(task.status)
    }
    const progress: string = task.progressText()
    if (progress.length > 0) {
      return `${this.statusText(task.status)} · ${progress}`
    }
    return this.statusText(task.status)
  }

  private shouldShowGalleryProgress(
    status: string,
    downloadedFiles: number,
    seededFiles: number,
    pageCount: number,
    activeBytesWritten: number,
    activeBytesTotal: number,
  ): boolean {
    const total: number = Math.max(pageCount, downloadedFiles, seededFiles)
    const effectiveStatus: string = this.effectiveGalleryStatus(status, downloadedFiles, total)
    if (effectiveStatus === DownloadGalleryTaskStatus.COMPLETE || effectiveStatus === DownloadGalleryTaskStatus.ERROR) {
      return false
    }
    return downloadedFiles > 0 ||
      seededFiles > 0 ||
      this.activeDownloadRatio(activeBytesWritten, activeBytesTotal) > 0 ||
      effectiveStatus === DownloadGalleryTaskStatus.PREPARING ||
      effectiveStatus === DownloadGalleryTaskStatus.READY ||
      effectiveStatus === DownloadGalleryTaskStatus.DOWNLOADING ||
      effectiveStatus === DownloadGalleryTaskStatus.PAUSED ||
      effectiveStatus === DownloadGalleryTaskStatus.PARTIAL
  }

  private effectiveGalleryStatus(status: string, downloadedFiles: number, pageCount: number): string {
    if (status === DownloadGalleryTaskStatus.COMPLETE && pageCount > 0 && downloadedFiles < pageCount) {
      return DownloadGalleryTaskStatus.PARTIAL
    }
    return status
  }

  private shouldShowArchiverProgress(task: DownloadArchiverTask): boolean {
    return task.status === DownloadGalleryTaskStatus.DOWNLOADING ||
      task.status === DownloadGalleryTaskStatus.PAUSED ||
      task.status === DownloadGalleryTaskStatus.PARTIAL
  }

  private openGalleryTaskSource(task: DownloadGalleryTask): void {
    if (task.gid.length === 0 || task.token.length === 0) {
      return
    }
    DiagnosticLogger.info(
      'download',
      'gallery_open_source_from_download',
      `gid=${task.gid} tokenHash=${DiagnosticLogger.ownerHash(task.token)} status=${task.status}`,
    )
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(
        task.gid,
        task.token,
        task.thumbUrl,
        task.displayTitle(),
        task.pageCount > 0 ? `${task.pageCount}` : '',
      ),
    )
  }

  private openArchiverTaskSource(task: DownloadArchiverTask): void {
    if (task.gid.length === 0 || task.token.length === 0) {
      return
    }
    DiagnosticLogger.info(
      'download',
      'archiver_open_source_from_download',
      `gid=${task.gid} tokenHash=${DiagnosticLogger.ownerHash(task.token)} tagHash=${DiagnosticLogger.ownerHash(task.tag)} status=${task.status}`,
    )
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(task.gid, task.token, task.thumbUrl, task.displayTitle()),
    )
  }

  private openDownloadedTask(task: DownloadGalleryTask): void {
    const images: EhGalleryImage[] = this.downloadedSeedImages(task)
    if (images.length === 0) {
      return
    }
    const index: number = Math.max(0, Math.min(images.length - 1, this.readProgress.getIndex(task.gid)))
    DiagnosticLogger.info(
      'download',
      'gallery_open_local_reader',
      `gid=${task.gid} images=${images.length} index=${index} firstUriHash=${DiagnosticLogger.ownerHash(images[0].imageUrl)}`,
    )
    this.stack.pushPathByName(
      'Reader',
      new ReaderParams(task.gid, task.token, index, images.length, task.displayTitle(), images, 1, images.length),
    )
  }

  private downloadedSeedImages(task: DownloadGalleryTask): EhGalleryImage[] {
    const images: EhGalleryImage[] = []
    for (let i: number = 0; i < task.imageSeeds.length; i++) {
      const seed: DownloadImageSeed = task.imageSeeds[i]
      if (seed.filePath.length === 0 || seed.bytesWritten <= 0) {
        continue
      }
      const image: EhGalleryImage = new EhGalleryImage(seed.page)
      image.imgkey = seed.imgkey
      image.sUrl = seed.imagePageUrl
      image.thumbUrl = seed.thumbUrl
      image.imageUrl = CachedImageFileService.displayUri(seed.filePath)
      image.originImageUrl = seed.originImageUrl
      image.showKey = seed.showKey
      image.reloadKey = seed.reloadKey
      images.push(image)
    }
    return images
  }

  private async openArchiverTask(task: DownloadArchiverTask): Promise<void> {
    if (this.openingArchiverTag.length > 0) {
      return
    }
    this.openingArchiverTag = task.tag
    try {
      const images: EhGalleryImage[] = await ArchiveImageService.imagesForTask(this.ctx(), task)
      const index: number = Math.max(0, Math.min(images.length - 1, this.readProgress.getIndex(task.gid)))
      DiagnosticLogger.info(
        'download',
        'archiver_open_local_reader',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(task.tag)} images=${images.length} index=${index} firstUriHash=${images.length > 0 ? DiagnosticLogger.ownerHash(images[0].imageUrl) : ''}`,
      )
      this.stack.pushPathByName(
        'Reader',
        new ReaderParams(task.gid, '', index, images.length, task.displayTitle(), images, 1, images.length),
      )
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: (error as Error).message })
    } finally {
      this.openingArchiverTag = ''
    }
  }

  @Builder
  private EmptyQueueSection() {
    Column() {
      CardEmptyState({ message: this.selectedEmptyText(), expand: false })
      Text(this.selectedNextStep())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          bottom: ThemeConstants.SPACE_LG,
        })
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private GalleryTaskSection() {
    ForEach(
      this.downloadQueue.galleryTasks,
      (task: DownloadGalleryTask) => {
        ListItem() {
          this.DownloadGalleryTaskCard(this.currentGalleryTask(task))
        }
        .clip(false)
      },
      (task: DownloadGalleryTask) => this.galleryRenderKey(task),
    )
  }

  @Builder
  private ArchiverTaskSection() {
    ForEach(
      this.downloadQueue.archiverTasks,
      (task: DownloadArchiverTask) => {
        ListItem() {
          this.DownloadArchiverTaskCard(this.currentArchiverTask(task))
        }
        .clip(false)
      },
      (task: DownloadArchiverTask) => this.archiverRenderKey(task),
    )
  }

  @Builder
  private DownloadGalleryTaskCard(task: DownloadGalleryTask) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.GalleryTaskCover(task)
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(task.displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: ThemeConstants.SPACE_XS }) {
          Column({ space: ThemeConstants.SPACE_XS }) {
            if (this.taskMetaText(task).length > 0 || task.preferOriginal) {
              Row({ space: ThemeConstants.SPACE_XS }) {
                Text(this.taskMetaText(task))
                  .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (task.preferOriginal) {
                  this.GalleryOriginalBadge()
                }
              }
              .alignItems(VerticalAlign.Center)
              .width('100%')
            }
            if (this.shouldShowGalleryProgress(
              task.status,
              task.downloadedFiles,
              task.seededFiles,
              task.pageCount,
              task.activeBytesWritten,
              task.activeBytesTotal,
            )) {
              this.GalleryTaskProgressBar(task)
            }
            this.GalleryTaskStatusText(task)
          }
          .layoutWeight(1)
          .height('100%')
          this.GalleryTaskInlineActionColumn(task)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .height(0)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openTaskIfComplete(task)
      })
    }
    .width('100%')
    .padding({ left: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING,
      top: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING })
    .borderRadius(ThemeConstants.DOWNLOAD_TASK_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private GalleryOriginalBadge() {
    Text(AppStrings.get('download_use_original_image'))
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .padding({
        left: ThemeConstants.SPACE_XS,
        right: ThemeConstants.SPACE_XS,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .borderRadius(ThemeConstants.LIST_TAG_RADIUS)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
  }

  @Builder
  private DownloadArchiverTaskCard(task: DownloadArchiverTask) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.ArchiverTaskCover(task)
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(task.displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: ThemeConstants.SPACE_XS }) {
          Column({ space: ThemeConstants.SPACE_XS }) {
            if (task.resolution.length > 0 || task.dltype.length > 0) {
              Text(task.resolution.length > 0 ? task.resolution : task.dltype)
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            if (this.shouldShowArchiverProgress(task)) {
              this.ArchiverProgressBar(task)
            }
            this.ArchiverTaskStatusText(task)
          }
          .layoutWeight(1)
          .height('100%')
          this.ArchiverTaskInlineActionColumn(task)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .height(0)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openArchiverTaskIfComplete(task)
      })
    }
    .width('100%')
    .padding({ left: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING,
      top: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING })
    .borderRadius(ThemeConstants.DOWNLOAD_TASK_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private GalleryTaskCover(task: DownloadGalleryTask) {
    EhThumbnail({
      url: task.thumbUrl,
      thumbWidth: ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH,
      thumbHeight: ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT,
      radius: ThemeConstants.DOWNLOAD_TASK_COVER_RADIUS,
    })
      .onClick(() => {
        this.openGalleryTaskSource(task)
      })
  }

  @Builder
  private ArchiverTaskCover(task: DownloadArchiverTask) {
    if (task.thumbUrl.length > 0) {
      EhThumbnail({
        url: task.thumbUrl,
        thumbWidth: ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH,
        thumbHeight: ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT,
        radius: ThemeConstants.DOWNLOAD_TASK_COVER_RADIUS,
      })
        .onClick(() => {
          this.openArchiverTaskSource(task)
        })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
          .fontSize(ThemeConstants.FONT_SIZE_H1)
          .fontColor([ThemeConstants.BRAND_PRIMARY])
      }
      .width(ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(ThemeConstants.DOWNLOAD_TASK_COVER_RADIUS)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .onClick(() => {
        this.openArchiverTaskSource(task)
      })
    }
  }

  @Builder
  private GalleryTaskStatusText(task: DownloadGalleryTask) {
    // Dynamic queue fields must be read inside the builder; scalar builder params can keep their
    // initial value under stable ListItem reuse.
    Text(this.taskProgressLabel(
      task.status,
      task.downloadedFiles,
      task.seededFiles,
      task.pageCount,
      task.prepareError,
    ))
      .fontSize(ThemeConstants.FONT_SIZE_META)
      .fontColor(this.effectiveGalleryStatus(
        task.status,
        task.downloadedFiles,
        Math.max(task.pageCount, task.downloadedFiles, task.seededFiles),
      ) === DownloadGalleryTaskStatus.ERROR ? Color.Red : $r('sys.color.font_primary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  private ArchiverTaskStatusText(task: DownloadArchiverTask) {
    Text(this.archiverProgressLabel(task))
      .fontSize(ThemeConstants.FONT_SIZE_META)
      .fontColor(task.status === DownloadGalleryTaskStatus.ERROR ? Color.Red : $r('sys.color.font_primary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  private GalleryTaskProgressBar(task: DownloadGalleryTask) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.taskProgressRatio(
          task.status,
          task.downloadedFiles,
          task.seededFiles,
          task.pageCount,
          task.activeBytesWritten,
          task.activeBytesTotal,
        ) * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(task.status === DownloadGalleryTaskStatus.ERROR
          ? Color.Red
          : ThemeConstants.BRAND_PRIMARY)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
    .borderRadius(ThemeConstants.RADIUS_SM)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .clip(true)
  }

  @Builder
  private ArchiverProgressBar(task: DownloadArchiverTask) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.archiverProgressRatio(task) * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(task.status === DownloadGalleryTaskStatus.ERROR
          ? Color.Red
          : ThemeConstants.BRAND_PRIMARY)
    }
    .width('100%')
    .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
    .borderRadius(ThemeConstants.RADIUS_SM)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .clip(true)
  }

  @Builder
  private GalleryTaskInlineActionColumn(task: DownloadGalleryTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.GalleryPrimaryAction(task)
      this.GalleryTaskMoreButton(task)
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ArchiverTaskInlineActionColumn(task: DownloadArchiverTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.ArchiverPrimaryAction(task)
      this.ArchiverTaskMoreButton(task)
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private GalleryPrimaryAction(task: DownloadGalleryTask) {
    if (this.refreshingGalleryKey === this.taskKey(task)) {
      this.LoadingTaskIconButton($r('app.string.common_refresh'))
    } else if (this.canPauseTask(task)) {
      this.PauseTaskButton(task)
    } else if (this.canResumeTask(task)) {
      this.ResumeTaskButton(task)
    }
  }

  @Builder
  private ArchiverPrimaryAction(task: DownloadArchiverTask) {
    if (this.openingArchiverTag === task.tag) {
      this.ArchiverOpeningButton(task)
    } else if (this.canPauseArchiverTask(task)) {
      this.PauseArchiverTaskButton(task)
    } else if (this.canResumeArchiverTask(task)) {
      this.ResumeArchiverTaskButton(task)
    }
  }

  @Builder
  private GalleryTaskMoreButton(task: DownloadGalleryTask) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.common_more_actions'))
      .onClick(() => {
        this.actionMenuKey = this.galleryActionKey(task)
      })
      .bindMenu(this.actionMenuKey === this.galleryActionKey(task), this.TaskActionMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          if (this.actionMenuKey === this.galleryActionKey(task)) {
            this.closeActionMenu()
          }
        },
      })
  }

  @Builder
  private ArchiverTaskMoreButton(task: DownloadArchiverTask) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.common_more_actions'))
      .onClick(() => {
        this.actionMenuKey = this.archiverActionKey(task)
      })
      .bindMenu(this.actionMenuKey === this.archiverActionKey(task), this.TaskActionMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          if (this.actionMenuKey === this.archiverActionKey(task)) {
            this.closeActionMenu()
          }
        },
      })
  }

  @Builder
  private TaskActionMenu() {
    Menu() {
      if (this.actionMenuKey.startsWith('gallery:')) {
        if (this.activeGalleryCanRefresh()) {
          MenuItem({ content: $r('app.string.common_refresh') })
            .onClick(() => {
              this.refreshActiveGalleryTask()
            })
        }
        MenuItem({ content: $r('app.string.download_delete_task') })
          .onClick(() => {
            this.removeActiveGalleryTask()
          })
      } else if (this.actionMenuKey.startsWith('archiver:')) {
        if (this.activeArchiverCanSwitchToBot()) {
          MenuItem({ content: $r('app.string.download_archiver_use_bot') })
            .onClick(() => {
              this.switchActiveArchiverToBot()
            })
        }
        MenuItem({ content: $r('app.string.download_delete_task') })
          .onClick(() => {
            this.removeActiveArchiverTask()
          })
      }
    }
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private TaskIconButton(icon: Resource, label: Resource, tint: ResourceColor, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([tint])
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private ResumeTaskButton(task: DownloadGalleryTask) {
    this.TaskIconButton(this.galleryResumeActionIcon(task), this.galleryResumeActionLabel(task),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.resumeTask(task)
      })
  }

  @Builder
  private PauseTaskButton(task: DownloadGalleryTask) {
    this.TaskIconButton($r('sys.symbol.pause'), $r('app.string.common_pause'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.pauseTask(task)
      })
  }

  @Builder
  private ResumeArchiverTaskButton(task: DownloadArchiverTask) {
    this.TaskIconButton(this.archiverResumeActionIcon(task), this.archiverResumeActionLabel(task),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.resumeArchiverTask(task)
      })
  }

  @Builder
  private PauseArchiverTaskButton(task: DownloadArchiverTask) {
    this.TaskIconButton($r('sys.symbol.pause'), $r('app.string.common_pause'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.pauseArchiverTask(task)
      })
  }

  @Builder
  private ArchiverOpeningButton(_task: DownloadArchiverTask) {
    this.LoadingTaskIconButton($r('app.string.reader_loading_resolving'))
  }

  @Builder
  private LoadingTaskIconButton(label: Resource) {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      LoadingProgress()
        .width(ThemeConstants.FONT_SIZE_TITLE)
        .height(ThemeConstants.FONT_SIZE_TITLE)
        .color(ThemeConstants.BRAND_PRIMARY)
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(false)
    .accessibilityText(label)
  }

  build() {
    Column() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
        onDidScroll: (offset: number, state: ScrollState) => {
          if (this.onDidScroll) {
            this.onDidScroll(offset, state)
          }
        },
      }) {
        ListItem() {
          Column() {
            Blank()
          }
          .height(DOWNLOAD_SELECTOR_BAR_HEIGHT)
        }
        if (this.downloadView.viewType === DownloadViewType.GALLERY && this.downloadQueue.galleryTasks.length > 0) {
          this.GalleryTaskSection()
        } else if (this.downloadView.viewType === DownloadViewType.ARCHIVER && this.downloadQueue.archiverTasks.length > 0) {
          this.ArchiverTaskSection()
        } else {
          ListItem() {
            this.EmptyQueueSection()
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
