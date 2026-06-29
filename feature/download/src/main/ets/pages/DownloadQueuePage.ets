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
  DownloadSettings,
  DownloadViewType,
  DownloadViewState,
  DiagnosticLogger,
  GalleryReadProgressState,
  DOWNLOAD_SELECTOR_BAR_HEIGHT,
  connectGalleryReadProgress,
  connectSiteMode,
  connectDownloadQueue,
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
  @Local readProgress: GalleryReadProgressState = connectGalleryReadProgress();
  @Local downloadQueueTick: number = 0;
  @Local openingArchiverTag: string = '';
  @Local refreshingGalleryKey: string = '';
  @Local actionMenuKey: string = '';
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  @Monitor('downloadQueue.revision')
  private onDownloadQueueChanged(): void {
    this.downloadQueueTick = this.downloadQueueTick + 1
    const debugTask: DownloadGalleryTask | undefined = this.queueDebugTask()
    const debugArchiverTask: DownloadArchiverTask | undefined = this.queueDebugArchiverTask()
    let message: string = debugTask === undefined
      ? `revision=${this.downloadQueue.revision} signal=${this.downloadQueueTick} gallery=0`
      : `revision=${this.downloadQueue.revision} signal=${this.downloadQueueTick} gid=${debugTask.gid} status=${debugTask.status} downloaded=${debugTask.downloadedCount()} seeded=${debugTask.seededCount()}`
    message = debugArchiverTask === undefined
      ? `${message} archiver=${this.downloadQueue.archiverTasks.length}`
      : `${message} archiverTagHash=${DiagnosticLogger.ownerHash(debugArchiverTask.tag)} archiverStatus=${debugArchiverTask.status} archiverBytes=${debugArchiverTask.bytesWritten}/${debugArchiverTask.bytesTotal} archiverProgress=${debugArchiverTask.progress}`
    DiagnosticLogger.info(
      'download',
      'queue_page_revision',
      message,
    )
  }

  private queueDebugTask(): DownloadGalleryTask | undefined {
    for (let i: number = 0; i < this.downloadQueue.galleryTasks.length; i++) {
      const task: DownloadGalleryTask = this.downloadQueue.galleryTasks[i]
      if (task.status !== DownloadGalleryTaskStatus.COMPLETE) {
        return task
      }
    }
    return this.downloadQueue.galleryTasks.length > 0 ? this.downloadQueue.galleryTasks[0] : undefined
  }

  private queueDebugArchiverTask(): DownloadArchiverTask | undefined {
    for (let i: number = 0; i < this.downloadQueue.archiverTasks.length; i++) {
      const task: DownloadArchiverTask = this.downloadQueue.archiverTasks[i]
      if (task.status !== DownloadGalleryTaskStatus.COMPLETE) {
        return task
      }
    }
    return undefined
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

  private taskStatusText(task: DownloadGalleryTask): string {
    return this.statusText(this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount))
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
    if (task.uploader.length > 0) {
      parts.push(task.uploader)
    }
    return parts.join(' · ')
  }

  private taskProgressLabel(task: DownloadGalleryTask): string {
    if (this.downloadQueue.revision < 0) {
      return ''
    }
    if (this.downloadQueueTick < 0) {
      return ''
    }
    const parts: string[] = []
    const status: string = this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount)
    if (status === DownloadGalleryTaskStatus.ERROR) {
      if (task.downloadProgressText().length > 0) {
        parts.push(this.taskStatusText(task))
        parts.push(AppStrings.get('download_file_progress').replace('%s', task.downloadProgressText()))
        if (task.prepareError.length > 0) {
          parts.push(task.prepareError)
        }
        return parts.join(' · ')
      }
      if (task.seedProgressText().length > 0) {
        parts.push(this.taskStatusText(task))
        parts.push(AppStrings.get('download_seed_progress').replace('%s', task.seedProgressText()))
        if (task.prepareError.length > 0) {
          parts.push(task.prepareError)
        }
        return parts.join(' · ')
      }
      if (task.prepareError.length > 0) {
        return `${this.taskStatusText(task)} · ${task.prepareError}`
      }
      return this.taskStatusText(task)
    }
    if (task.downloadProgressText().length > 0) {
      parts.push(this.taskStatusText(task))
      parts.push(AppStrings.get('download_file_progress').replace('%s', task.downloadProgressText()))
      return parts.join(' · ')
    }
    if (task.seedProgressText().length > 0) {
      if (status === DownloadGalleryTaskStatus.PREPARING || status === DownloadGalleryTaskStatus.READY) {
        parts.push(this.taskStatusText(task))
      }
      parts.push(AppStrings.get('download_seed_progress').replace('%s', task.seedProgressText()))
      return parts.join(' · ')
    }
    return this.taskStatusText(task)
  }

  private taskProgressRatio(task: DownloadGalleryTask): number {
    if (this.downloadQueue.revision < 0) {
      return 0
    }
    if (this.downloadQueueTick < 0) {
      return 0
    }
    const status: string = this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount)
    if (status === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (task.pageCount <= 0) {
      return 0
    }
    const active: number = task.activeDownloadRatio()
    if (task.downloadedCount() > 0 || active > 0) {
      return Math.max(0, Math.min(1, (task.downloadedCount() + active) / task.pageCount))
    }
    if (task.seededCount() > 0) {
      return Math.max(0, Math.min(1, task.seededCount() / task.pageCount))
    }
    return 0
  }

  private async removeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.removeGallery(this.ctx(), task.gid, task.token)
  }

  private async removeArchiverTask(task: DownloadArchiverTask): Promise<void> {
    await DownloadQueueSettings.removeArchiver(this.ctx(), task.tag)
  }

  private async resumeTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.downloadGalleryImages(this.ctx(), task.gid, task.token)
  }

  private async pauseTask(task: DownloadGalleryTask): Promise<void> {
    await DownloadQueueSettings.pauseGalleryDownload(this.ctx(), task.gid, task.token)
  }

  private taskKey(task: DownloadGalleryTask): string {
    return `${task.gid}:${task.token}`
  }

  private safeForEachKeyPart(value: string): string {
    return value.replace(/[^A-Za-z0-9_]/g, '_')
  }

  private galleryRenderKey(task: DownloadGalleryTask): string {
    return `gallery_${this.safeForEachKeyPart(task.gid)}_${this.safeForEachKeyPart(task.token)}`
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
      this.removeTask(task)
    }
  }

  private removeActiveArchiverTask(): void {
    const task: DownloadArchiverTask | undefined = this.activeArchiverTask()
    this.closeActionMenu()
    if (task !== undefined) {
      this.removeArchiverTask(task)
    }
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

  private shouldShowGalleryProgress(task: DownloadGalleryTask): boolean {
    const status: string = this.effectiveGalleryStatus(task.status, task.downloadedCount(), task.pageCount)
    if (status === DownloadGalleryTaskStatus.COMPLETE || status === DownloadGalleryTaskStatus.ERROR) {
      return false
    }
    return task.downloadedCount() > 0 ||
      task.seededCount() > 0 ||
      status === DownloadGalleryTaskStatus.PREPARING ||
      status === DownloadGalleryTaskStatus.READY ||
      status === DownloadGalleryTaskStatus.DOWNLOADING ||
      status === DownloadGalleryTaskStatus.PAUSED ||
      status === DownloadGalleryTaskStatus.PARTIAL
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
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(task.gid, task.token, '', task.displayTitle()),
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
          DownloadGalleryTaskCardView({
            task: this.currentGalleryTask(task),
            downloadQueueRevision: this.downloadQueueTick,
            visibleStatus: this.currentGalleryTask(task).status,
            visiblePageCount: this.currentGalleryTask(task).pageCount,
            visibleExpectedFiles: this.currentGalleryTask(task).expectedFileCount(),
            visibleDownloadedFiles: this.currentGalleryTask(task).downloadedCount(),
            visibleSeededFiles: this.currentGalleryTask(task).seededCount(),
            visibleActiveRatio: this.currentGalleryTask(task).activeDownloadRatio(),
            visiblePrepareError: this.currentGalleryTask(task).prepareError,
            actionMenuKey: this.actionMenuKey,
            refreshingGalleryKey: this.refreshingGalleryKey,
            onOpenSource: (selected: DownloadGalleryTask) => {
              this.openGalleryTaskSource(selected)
            },
            onOpenTask: (selected: DownloadGalleryTask) => {
              this.openTaskIfComplete(selected)
            },
            onResume: (selected: DownloadGalleryTask) => {
              this.resumeTask(selected)
            },
            onPause: (selected: DownloadGalleryTask) => {
              this.pauseTask(selected)
            },
            onRefresh: (selected: DownloadGalleryTask) => {
              this.refreshTask(selected)
            },
            onRemove: (selected: DownloadGalleryTask) => {
              this.removeTask(selected)
            },
            onOpenMenu: (key: string) => {
              this.actionMenuKey = key
            },
            onCloseMenu: () => {
              this.closeActionMenu()
            },
          })
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
          DownloadArchiverTaskCardView({
            task: this.currentArchiverTask(task),
            downloadQueueRevision: this.downloadQueueTick,
            visibleStatus: this.currentArchiverTask(task).status,
            visibleBytesWritten: this.currentArchiverTask(task).bytesWritten,
            visibleBytesTotal: this.currentArchiverTask(task).bytesTotal,
            visibleProgress: this.currentArchiverTask(task).progress,
            visibleError: this.currentArchiverTask(task).error,
            actionMenuKey: this.actionMenuKey,
            openingArchiverTag: this.openingArchiverTag,
            onOpenSource: (selected: DownloadArchiverTask) => {
              this.openArchiverTaskSource(selected)
            },
            onOpenTask: (selected: DownloadArchiverTask) => {
              this.openArchiverTaskIfComplete(selected)
            },
            onResume: (selected: DownloadArchiverTask) => {
              this.resumeArchiverTask(selected)
            },
            onPause: (selected: DownloadArchiverTask) => {
              this.pauseArchiverTask(selected)
            },
            onSwitchToBot: (selected: DownloadArchiverTask) => {
              DownloadQueueSettings.switchArchiverToBot(this.ctx(), selected.tag)
            },
            onRemove: (selected: DownloadArchiverTask) => {
              this.removeArchiverTask(selected)
            },
            onOpenMenu: (key: string) => {
              this.actionMenuKey = key
            },
            onCloseMenu: () => {
              this.closeActionMenu()
            },
          })
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
        if (this.taskMetaText(task).length > 0) {
          Text(this.taskMetaText(task))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.shouldShowGalleryProgress(task)) {
          this.TaskProgressBar(task)
        }
        this.TaskStatusText(this.taskProgressLabel(task), task.status === DownloadGalleryTaskStatus.ERROR)
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openTaskIfComplete(task)
      })
      this.GalleryTaskActionColumn(task)
    }
    .width('100%')
    .padding({ left: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING,
      top: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING })
    .borderRadius(ThemeConstants.DOWNLOAD_TASK_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Top)
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
        this.TaskStatusText(this.archiverProgressLabel(task), task.status === DownloadGalleryTaskStatus.ERROR)
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openArchiverTaskIfComplete(task)
      })
      this.ArchiverTaskActionColumn(task)
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
  private TaskStatusText(text: string, isError: boolean) {
    Text(text)
      .fontSize(ThemeConstants.FONT_SIZE_META)
      .fontColor(isError ? Color.Red : $r('sys.color.font_primary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  private TaskProgressBar(task: DownloadGalleryTask) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.taskProgressRatio(task) * 100))}%`)
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
  private GalleryTaskActionColumn(task: DownloadGalleryTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.GalleryPrimaryAction(task)
      this.GalleryTaskMoreButton(task)
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ArchiverTaskActionColumn(task: DownloadArchiverTask) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.ArchiverPrimaryAction(task)
      this.ArchiverTaskMoreButton(task)
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
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
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
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
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
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
        MenuItem({ content: $r('app.string.common_remove') })
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
        MenuItem({ content: $r('app.string.common_remove') })
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private ResumeTaskButton(task: DownloadGalleryTask) {
    this.TaskIconButton($r('sys.symbol.arrow_clockwise'), $r('app.string.common_retry'),
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
    this.TaskIconButton($r('sys.symbol.arrow_clockwise'), $r('app.string.common_retry'),
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
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

@ComponentV2
struct DownloadGalleryTaskCardView {
  @Param task: DownloadGalleryTask = new DownloadGalleryTask()
  @Param downloadQueueRevision: number = 0
  @Param visibleStatus: string = DownloadGalleryTaskStatus.QUEUED
  @Param visiblePageCount: number = 0
  @Param visibleExpectedFiles: number = 0
  @Param visibleDownloadedFiles: number = 0
  @Param visibleSeededFiles: number = 0
  @Param visibleActiveRatio: number = 0
  @Param visiblePrepareError: string = ''
  @Param actionMenuKey: string = ''
  @Param refreshingGalleryKey: string = ''
  @Event onOpenSource?: (task: DownloadGalleryTask) => void;
  @Event onOpenTask?: (task: DownloadGalleryTask) => void;
  @Event onResume?: (task: DownloadGalleryTask) => void;
  @Event onPause?: (task: DownloadGalleryTask) => void;
  @Event onRefresh?: (task: DownloadGalleryTask) => void;
  @Event onRemove?: (task: DownloadGalleryTask) => void;
  @Event onOpenMenu?: (key: string) => void;
  @Event onCloseMenu?: () => void;

  private taskKey(): string {
    if (this.downloadQueueRevision < 0) {
      return ''
    }
    return `${this.task.gid}:${this.task.token}`
  }

  private currentTask(): DownloadGalleryTask {
    return this.task
  }

  private galleryActionKey(): string {
    return `gallery:${this.taskKey()}`
  }

  private actionTask(): DownloadGalleryTask {
    return this.currentTask()
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

  private taskStatusText(status: string): string {
    return this.statusText(status)
  }

  private displayTitle(): string {
    return this.currentTask().displayTitle()
  }

  private taskMetaText(): string {
    const task: DownloadGalleryTask = this.currentTask()
    const parts: string[] = []
    if (this.visibleExpectedFiles > 0) {
      parts.push(`${this.visibleExpectedFiles}P`)
    } else if (this.visiblePageCount > 0) {
      parts.push(`${this.visiblePageCount}P`)
    }
    if (task.category.length > 0) {
      parts.push(task.category)
    }
    if (task.uploader.length > 0) {
      parts.push(task.uploader)
    }
    return parts.join(' · ')
  }

  private downloadedFiles(): number {
    return this.visibleDownloadedFiles
  }

  private seededFiles(): number {
    return this.visibleSeededFiles
  }

  private taskProgressLabel(
    status: string,
    downloadedFiles: number,
    seededFiles: number,
    pageCount: number,
    prepareError: string,
  ): string {
    const total: number = this.expectedFileCount(pageCount, downloadedFiles, seededFiles)
    const effectiveStatus: string = this.effectiveGalleryStatus(status, downloadedFiles, total)
    const parts: string[] = []
    const downloadProgress: string = this.progressText(downloadedFiles, total)
    const seedProgress: string = this.progressText(seededFiles, total)
    if (effectiveStatus === DownloadGalleryTaskStatus.ERROR) {
      if (downloadProgress.length > 0) {
        parts.push(this.taskStatusText(effectiveStatus))
        parts.push(AppStrings.get('download_file_progress').replace('%s', downloadProgress))
        if (prepareError.length > 0) {
          parts.push(prepareError)
        }
        return parts.join(' · ')
      }
      if (seedProgress.length > 0) {
        parts.push(this.taskStatusText(effectiveStatus))
        parts.push(AppStrings.get('download_seed_progress').replace('%s', seedProgress))
        if (prepareError.length > 0) {
          parts.push(prepareError)
        }
        return parts.join(' · ')
      }
      if (prepareError.length > 0) {
        return `${this.taskStatusText(effectiveStatus)} · ${prepareError}`
      }
      return this.taskStatusText(effectiveStatus)
    }
    if (downloadProgress.length > 0) {
      parts.push(this.taskStatusText(effectiveStatus))
      parts.push(AppStrings.get('download_file_progress').replace('%s', downloadProgress))
      return parts.join(' · ')
    }
    if (seedProgress.length > 0) {
      if (effectiveStatus === DownloadGalleryTaskStatus.PREPARING || effectiveStatus === DownloadGalleryTaskStatus.READY) {
        parts.push(this.taskStatusText(effectiveStatus))
      }
      parts.push(AppStrings.get('download_seed_progress').replace('%s', seedProgress))
      return parts.join(' · ')
    }
    return this.taskStatusText(effectiveStatus)
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

  private taskProgressRatio(status: string, downloadedFiles: number, seededFiles: number, pageCount: number): number {
    const total: number = this.expectedFileCount(pageCount, downloadedFiles, seededFiles)
    const effectiveStatus: string = this.effectiveGalleryStatus(status, downloadedFiles, total)
    if (effectiveStatus === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (total <= 0) {
      return 0
    }
    const active: number = this.visibleActiveRatio
    if (downloadedFiles > 0 || active > 0) {
      return Math.max(0, Math.min(1, (downloadedFiles + active) / total))
    }
    if (seededFiles > 0) {
      return Math.max(0, Math.min(1, seededFiles / total))
    }
    return 0
  }

  private canResumeTask(status: string): boolean {
    const effectiveStatus: string = this.effectiveGalleryStatus(
      status,
      this.downloadedFiles(),
      this.expectedFileCount(this.visiblePageCount, this.downloadedFiles(), this.seededFiles()),
    )
    return effectiveStatus === DownloadGalleryTaskStatus.QUEUED ||
      effectiveStatus === DownloadGalleryTaskStatus.ERROR ||
      effectiveStatus === DownloadGalleryTaskStatus.PAUSED ||
      effectiveStatus === DownloadGalleryTaskStatus.PARTIAL ||
      effectiveStatus === DownloadGalleryTaskStatus.READY
  }

  private canPauseTask(status: string): boolean {
    return this.effectiveGalleryStatus(
      status,
      this.downloadedFiles(),
      this.expectedFileCount(this.visiblePageCount, this.downloadedFiles(), this.seededFiles()),
    ) ===
      DownloadGalleryTaskStatus.DOWNLOADING
  }

  private canRefreshTask(): boolean {
    const task: DownloadGalleryTask = this.currentTask()
    return this.effectiveGalleryStatus(
      this.visibleStatus,
      this.downloadedFiles(),
      this.expectedFileCount(this.visiblePageCount, this.downloadedFiles(), this.seededFiles()),
    ) ===
      DownloadGalleryTaskStatus.COMPLETE &&
      task.gid.length > 0 &&
      task.token.length > 0
  }

  private shouldShowGalleryProgress(status: string, downloadedFiles: number, seededFiles: number): boolean {
    const effectiveStatus: string = this.effectiveGalleryStatus(
      status,
      downloadedFiles,
      this.expectedFileCount(this.visiblePageCount, downloadedFiles, seededFiles),
    )
    if (effectiveStatus === DownloadGalleryTaskStatus.COMPLETE || effectiveStatus === DownloadGalleryTaskStatus.ERROR) {
      return false
    }
    return downloadedFiles > 0 ||
      this.visibleActiveRatio > 0 ||
      seededFiles > 0 ||
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

  private expectedFileCount(pageCount: number, downloadedFiles: number, seededFiles: number): number {
    return Math.max(this.visibleExpectedFiles, pageCount, downloadedFiles, seededFiles)
  }

  private openSource(): void {
    if (this.onOpenSource !== undefined) {
      this.onOpenSource(this.actionTask())
    }
  }

  private openTask(): void {
    if (this.onOpenTask !== undefined) {
      this.onOpenTask(this.actionTask())
    }
  }

  private resumeTask(): void {
    if (this.onResume !== undefined) {
      this.onResume(this.actionTask())
    }
  }

  private pauseTask(): void {
    if (this.onPause !== undefined) {
      this.onPause(this.actionTask())
    }
  }

  private refreshTask(): void {
    if (this.onRefresh !== undefined) {
      this.onRefresh(this.actionTask())
    }
  }

  private removeTask(): void {
    if (this.onRemove !== undefined) {
      this.onRemove(this.actionTask())
    }
  }

  private openMenu(): void {
    if (this.onOpenMenu !== undefined) {
      this.onOpenMenu(this.galleryActionKey())
    }
  }

  private closeMenu(): void {
    if (this.onCloseMenu !== undefined) {
      this.onCloseMenu()
    }
  }

  @Builder
  private GalleryTaskCover() {
    EhThumbnail({
      url: this.currentTask().thumbUrl,
      thumbWidth: ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH,
      thumbHeight: ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT,
      radius: ThemeConstants.DOWNLOAD_TASK_COVER_RADIUS,
    })
      .onClick(() => {
        this.openSource()
      })
  }

  @Builder
  private TaskStatusText(text: string, isError: boolean) {
    Text(text)
      .fontSize(ThemeConstants.FONT_SIZE_META)
      .fontColor(isError ? Color.Red : $r('sys.color.font_primary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  private TaskProgressBar(status: string, downloadedFiles: number, seededFiles: number, pageCount: number) {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.taskProgressRatio(status, downloadedFiles, seededFiles, pageCount) * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(status === DownloadGalleryTaskStatus.ERROR
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
  private GalleryTaskActionColumn(status: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.GalleryPrimaryAction(this.effectiveGalleryStatus(
        status,
        this.downloadedFiles(),
        this.expectedFileCount(this.visiblePageCount, this.downloadedFiles(), this.seededFiles()),
      ))
      this.GalleryTaskMoreButton()
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private GalleryPrimaryAction(status: string) {
    if (this.refreshingGalleryKey === this.taskKey()) {
      this.LoadingTaskIconButton($r('app.string.common_refresh'))
    } else if (this.canPauseTask(status)) {
      this.PauseTaskButton()
    } else if (this.canResumeTask(status)) {
      this.ResumeTaskButton()
    }
  }

  @Builder
  private GalleryTaskMoreButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.common_more_actions'))
      .onClick(() => {
        this.openMenu()
      })
      .bindMenu(this.actionMenuKey === this.galleryActionKey(), this.TaskActionMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          if (this.actionMenuKey === this.galleryActionKey()) {
            this.closeMenu()
          }
        },
      })
  }

  @Builder
  private TaskActionMenu() {
    Menu() {
      if (this.canRefreshTask()) {
        MenuItem({ content: $r('app.string.common_refresh') })
          .onClick(() => {
            this.refreshTask()
          })
      }
      MenuItem({ content: $r('app.string.common_remove') })
        .onClick(() => {
          this.removeTask()
        })
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private ResumeTaskButton() {
    this.TaskIconButton($r('sys.symbol.arrow_clockwise'), $r('app.string.common_retry'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.resumeTask()
      })
  }

  @Builder
  private PauseTaskButton() {
    this.TaskIconButton($r('sys.symbol.pause'), $r('app.string.common_pause'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.pauseTask()
      })
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(false)
    .accessibilityText(label)
  }

  build() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.GalleryTaskCover()
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.taskMetaText().length > 0) {
          Text(this.taskMetaText())
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.shouldShowGalleryProgress(this.visibleStatus, this.downloadedFiles(), this.seededFiles())) {
          this.TaskProgressBar(
            this.visibleStatus,
            this.downloadedFiles(),
            this.seededFiles(),
            this.visiblePageCount,
          )
        }
        this.TaskStatusText(
          this.taskProgressLabel(
            this.visibleStatus,
            this.downloadedFiles(),
            this.seededFiles(),
            this.visiblePageCount,
            this.visiblePrepareError,
          ),
          this.effectiveGalleryStatus(
            this.visibleStatus,
            this.downloadedFiles(),
            this.expectedFileCount(this.visiblePageCount, this.downloadedFiles(), this.seededFiles()),
          ) ===
            DownloadGalleryTaskStatus.ERROR,
        )
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openTask()
      })
      this.GalleryTaskActionColumn(this.visibleStatus)
    }
    .width('100%')
    .padding({ left: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING,
      top: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING })
    .borderRadius(ThemeConstants.DOWNLOAD_TASK_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Top)
  }
}

@ComponentV2
struct DownloadArchiverTaskCardView {
  @Param task: DownloadArchiverTask = new DownloadArchiverTask()
  @Param downloadQueueRevision: number = 0
  @Param visibleStatus: string = DownloadGalleryTaskStatus.QUEUED
  @Param visibleBytesWritten: number = 0
  @Param visibleBytesTotal: number = 0
  @Param visibleProgress: number = 0
  @Param visibleError: string = ''
  @Param actionMenuKey: string = ''
  @Param openingArchiverTag: string = ''
  @Event onOpenSource?: (task: DownloadArchiverTask) => void;
  @Event onOpenTask?: (task: DownloadArchiverTask) => void;
  @Event onResume?: (task: DownloadArchiverTask) => void;
  @Event onPause?: (task: DownloadArchiverTask) => void;
  @Event onSwitchToBot?: (task: DownloadArchiverTask) => void;
  @Event onRemove?: (task: DownloadArchiverTask) => void;
  @Event onOpenMenu?: (key: string) => void;
  @Event onCloseMenu?: () => void;

  private archiverActionKey(): string {
    if (this.downloadQueueRevision < 0) {
      return ''
    }
    return `archiver:${this.task.tag}`
  }

  private currentTask(): DownloadArchiverTask {
    return this.task
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

  private canResumeArchiverTask(): boolean {
    return this.visibleStatus === DownloadGalleryTaskStatus.ERROR ||
      this.visibleStatus === DownloadGalleryTaskStatus.PREPARING ||
      this.visibleStatus === DownloadGalleryTaskStatus.PAUSED ||
      this.visibleStatus === DownloadGalleryTaskStatus.QUEUED
  }

  private canPauseArchiverTask(): boolean {
    return this.visibleStatus === DownloadGalleryTaskStatus.DOWNLOADING
  }

  private canSwitchToBot(): boolean {
    const task: DownloadArchiverTask = this.currentTask()
    if (!DownloadSettings.archiveBotReady() ||
      task.parseSource === DownloadArchiverParseSource.BOT ||
      this.visibleStatus === DownloadGalleryTaskStatus.COMPLETE ||
      this.visibleStatus === DownloadGalleryTaskStatus.DOWNLOADING) {
      return false
    }
    const resolution: string = task.resolution.toLowerCase()
    return task.dltype === 'org' || resolution.includes('original')
  }

  private canReadArchiverTask(): boolean {
    const task: DownloadArchiverTask = this.currentTask()
    return this.visibleStatus === DownloadGalleryTaskStatus.COMPLETE &&
      task.filePath.length > 0 &&
      this.visibleBytesWritten > 0
  }

  private shouldShowArchiverProgress(): boolean {
    return this.visibleStatus === DownloadGalleryTaskStatus.DOWNLOADING ||
      this.visibleStatus === DownloadGalleryTaskStatus.PAUSED ||
      this.visibleStatus === DownloadGalleryTaskStatus.PARTIAL
  }

  private archiverProgressRatio(): number {
    if (this.visibleStatus === DownloadGalleryTaskStatus.COMPLETE) {
      return 1
    }
    if (this.visibleBytesTotal > 0) {
      return Math.max(0, Math.min(1, this.visibleBytesWritten / this.visibleBytesTotal))
    }
    return Math.max(0, Math.min(1, this.visibleProgress / 100))
  }

  private archiverProgressText(): string {
    if (this.visibleBytesWritten <= 0) {
      return ''
    }
    if (this.visibleBytesTotal > 0) {
      return `${this.visibleProgress}%`
    }
    return `${this.visibleBytesWritten} B`
  }

  private archiverProgressLabel(): string {
    if (this.visibleStatus === DownloadGalleryTaskStatus.COMPLETE) {
      return this.statusText(this.visibleStatus)
    }
    if (this.visibleStatus === DownloadGalleryTaskStatus.ERROR) {
      if (this.visibleError.length > 0) {
        return `${this.statusText(this.visibleStatus)} · ${this.visibleError}`
      }
      return this.statusText(this.visibleStatus)
    }
    const progress: string = this.archiverProgressText()
    if (progress.length > 0) {
      return `${this.statusText(this.visibleStatus)} · ${progress}`
    }
    return this.statusText(this.visibleStatus)
  }

  private openSource(): void {
    if (this.onOpenSource !== undefined) {
      this.onOpenSource(this.currentTask())
    }
  }

  private openTask(): void {
    if (this.canReadArchiverTask() && this.onOpenTask !== undefined) {
      this.onOpenTask(this.currentTask())
    }
  }

  private resumeTask(): void {
    if (this.onResume !== undefined) {
      this.onResume(this.currentTask())
    }
  }

  private pauseTask(): void {
    if (this.onPause !== undefined) {
      this.onPause(this.currentTask())
    }
  }

  private switchToBot(): void {
    if (this.onSwitchToBot !== undefined) {
      this.onSwitchToBot(this.currentTask())
    }
  }

  private removeTask(): void {
    if (this.onRemove !== undefined) {
      this.onRemove(this.currentTask())
    }
  }

  private openMenu(): void {
    if (this.onOpenMenu !== undefined) {
      this.onOpenMenu(this.archiverActionKey())
    }
  }

  private closeMenu(): void {
    if (this.onCloseMenu !== undefined) {
      this.onCloseMenu()
    }
  }

  @Builder
  private ArchiverTaskCover() {
    if (this.currentTask().thumbUrl.length > 0) {
      EhThumbnail({
        url: this.currentTask().thumbUrl,
        thumbWidth: ThemeConstants.DOWNLOAD_TASK_COVER_WIDTH,
        thumbHeight: ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT,
        radius: ThemeConstants.DOWNLOAD_TASK_COVER_RADIUS,
      })
        .onClick(() => {
          this.openSource()
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
        this.openSource()
      })
    }
  }

  @Builder
  private TaskStatusText(text: string, isError: boolean) {
    Text(text)
      .fontSize(ThemeConstants.FONT_SIZE_META)
      .fontColor(isError ? Color.Red : $r('sys.color.font_primary'))
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
  }

  @Builder
  private ArchiverProgressBar() {
    Row() {
      Blank()
        .width(`${Math.max(4, Math.round(this.archiverProgressRatio() * 100))}%`)
        .height(ThemeConstants.DOWNLOAD_TASK_PROGRESS_HEIGHT)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .backgroundColor(this.visibleStatus === DownloadGalleryTaskStatus.ERROR
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
  private ArchiverTaskActionColumn() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.ArchiverPrimaryAction()
      this.ArchiverTaskMoreButton()
    }
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ArchiverPrimaryAction() {
    if (this.openingArchiverTag === this.task.tag) {
      this.ArchiverOpeningButton()
    } else if (this.canPauseArchiverTask()) {
      this.PauseArchiverTaskButton()
    } else if (this.canResumeArchiverTask()) {
      this.ResumeArchiverTaskButton()
    }
  }

  @Builder
  private ArchiverTaskMoreButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.common_more_actions'))
      .onClick(() => {
        this.openMenu()
      })
      .bindMenu(this.actionMenuKey === this.archiverActionKey(), this.TaskActionMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          if (this.actionMenuKey === this.archiverActionKey()) {
            this.closeMenu()
          }
        },
      })
  }

  @Builder
  private TaskActionMenu() {
    Menu() {
      if (this.canSwitchToBot()) {
        MenuItem({ content: $r('app.string.download_archiver_use_bot') })
          .onClick(() => {
            this.switchToBot()
          })
      }
      MenuItem({ content: $r('app.string.common_remove') })
        .onClick(() => {
          this.removeTask()
        })
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private ResumeArchiverTaskButton() {
    this.TaskIconButton($r('sys.symbol.arrow_clockwise'), $r('app.string.common_retry'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.resumeTask()
      })
  }

  @Builder
  private PauseArchiverTaskButton() {
    this.TaskIconButton($r('sys.symbol.pause'), $r('app.string.common_pause'),
      ThemeConstants.BRAND_PRIMARY, true, () => {
        this.pauseTask()
      })
  }

  @Builder
  private ArchiverOpeningButton() {
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
    .width(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .height(ThemeConstants.DOWNLOAD_TASK_ACTION_SIZE)
    .backgroundColor(Color.Transparent)
    .enabled(false)
    .accessibilityText(label)
  }

  build() {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.ArchiverTaskCover()
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.currentTask().displayTitle())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.currentTask().resolution.length > 0 || this.currentTask().dltype.length > 0) {
          Text(this.currentTask().resolution.length > 0 ? this.currentTask().resolution : this.currentTask().dltype)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.shouldShowArchiverProgress()) {
          this.ArchiverProgressBar()
        }
        this.TaskStatusText(this.archiverProgressLabel(), this.visibleStatus === DownloadGalleryTaskStatus.ERROR)
      }
      .layoutWeight(1)
      .height(ThemeConstants.DOWNLOAD_TASK_COVER_HEIGHT)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        this.openTask()
      })
      this.ArchiverTaskActionColumn()
    }
    .width('100%')
    .padding({ left: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, right: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING,
      top: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING, bottom: ThemeConstants.DOWNLOAD_TASK_CARD_PADDING })
    .borderRadius(ThemeConstants.DOWNLOAD_TASK_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Top)
  }
}
