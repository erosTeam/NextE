import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  ThemeConstants,
  DownloadArchiverTask,
  DownloadArchiverParseSource,
  DownloadQueueSettings,
  DownloadSettings,
  DownloadSettingsState,
  EhApiService,
  EhGalleryArchiverItem,
  EhGalleryArchiverQuote,
  EhGalleryArchiverSubmitResult,
  GalleryArchiverParams,
  SecondaryListScaffold,
  PageErrorState,
  CardEmptyState,
  AppModalScaffold,
  AppStrings,
  EhErrorText,
  immersiveTitleBar,
  DiagnosticLogger,
  connectDownloadSettings,
} from 'shared'

/**
 * Archive quote/options page. Grounded in eros_fe ArchiverView: local archive options POST
 * `dltype/dlcheck` and return a generated download URL; H@H options POST `hathdl_xres` and return an
 * EH status message. Every submit remains protected behind a native confirmation because it can spend
 * account GP/Credits.
 */
@ComponentV2
export struct GalleryArchiverContent {
  @Param params: GalleryArchiverParams = new GalleryArchiverParams();
  @Param modal: boolean = false;
  @Event closeAction?: () => void;
  @Local quote: EhGalleryArchiverQuote = new EhGalleryArchiverQuote();
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local submittingKey: string = '';
  @Local loadedKey: string = '';
  @Local downloadSettings: DownloadSettingsState = connectDownloadSettings();
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.loadIfNeeded()
  }

  private paramsKey(): string {
    return `${this.params.gid}|${this.params.token}|${this.params.archiverLink}|${this.params.isEx ? '1' : '0'}`
  }

  private async loadIfNeeded(): Promise<void> {
    const key: string = this.paramsKey()
    if (key === this.loadedKey || this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.loadedKey = key
    await this.load()
  }

  private async load(): Promise<void> {
    if (this.params.gid.length === 0 || this.params.token.length === 0) {
      this.loading = false
      return
    }
    this.loading = true
    this.error = ''
    DiagnosticLogger.info(
      'gallery',
      'archiver_load_start',
      `gid=${this.params.gid} tokenHash=${DiagnosticLogger.ownerHash(this.params.token)} isEx=${this.params.isEx}`,
    )
    try {
      this.quote = await EhApiService.getInstance().getGalleryArchiver(
        this.params.gid,
        this.params.token,
        this.params.archiverLink,
        this.params.isEx,
      )
      DiagnosticLogger.info(
        'gallery',
        'archiver_load_done',
        `gid=${this.params.gid} downloadItems=${this.quote.downloadItems.length} hathItems=${this.quote.hathItems.length}`,
      )
    } catch (e) {
      this.error = EhErrorText.forUser(e)
      DiagnosticLogger.warn(
        'gallery',
        'archiver_load_failed',
        `gid=${this.params.gid} error=${(e as Error).message}`,
      )
    }
    this.loading = false
  }

  @Builder
  private BalanceBadge(label: string, value: string) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeConstants.TEXT_ON_BRAND)
        .backgroundColor($r('sys.color.font_secondary'))
        .borderRadius(ThemeConstants.RADIUS_ROUND)
        .width(ThemeConstants.ARCHIVER_BALANCE_BADGE_SIZE)
        .height(ThemeConstants.ARCHIVER_BALANCE_BADGE_SIZE)
        .textAlign(TextAlign.Center)
      Text(value)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private BalanceRow() {
    if (this.quote.gp.length > 0 || this.quote.credits.length > 0) {
      ListItem() {
        Row({ space: ThemeConstants.SPACE_LG }) {
          if (this.quote.gp.length > 0) {
            this.BalanceBadge('G', this.quote.gp)
          }
          if (this.quote.credits.length > 0) {
            this.BalanceBadge('C', this.quote.credits)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          top: ThemeConstants.SPACE_SM,
          bottom: ThemeConstants.SPACE_SM,
        })
      }
    }
  }

  @Builder
  private SectionTitle(label: ResourceStr) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
  }

  @Builder
  private QuoteRow(item: EhGalleryArchiverItem, isHath: boolean) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(item.resolution)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Row({ space: ThemeConstants.SPACE_XS }) {
        Text(this.quoteMeta(item))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
        if (this.isSubmittingItem(item, isHath)) {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE_SMALL)
            .height(ThemeConstants.LOADING_SIZE_SMALL)
            .color(ThemeConstants.BRAND_PRIMARY)
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .borderRadius(ThemeConstants.RADIUS_MD)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.confirmArchiveSubmit(item, isHath)
    })
  }

  @Builder
  private QuoteList(title: ResourceStr, items: EhGalleryArchiverItem[], isHath: boolean) {
    if (items.length > 0) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          this.SectionTitle(title)
          Grid() {
            ForEach(items, (item: EhGalleryArchiverItem) => {
              GridItem() {
                this.QuoteRow(item, isHath)
              }
            }, (item: EhGalleryArchiverItem, index: number) =>
              `quote_${index}_${item.dltype}_${item.resolution}`.replace(/[^A-Za-z0-9_]/g, '_'))
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(ThemeConstants.SPACE_SM)
          .rowsGap(ThemeConstants.SPACE_SM)
          .width('100%')
          .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
        }
        .width('100%')
      }
    }
  }

  @Builder
  private BotQuoteList() {
    if (DownloadSettings.archiveBotReady(this.downloadSettings)) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          this.SectionTitle($r('app.string.gallery_archiver_bot'))
          Grid() {
            GridItem() {
              this.BotQuoteRow(this.botArchiveItem())
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(ThemeConstants.SPACE_SM)
          .rowsGap(ThemeConstants.SPACE_SM)
          .width('100%')
          .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
        }
        .width('100%')
      }
    }
  }

  @Builder
  private BotQuoteRow(item: EhGalleryArchiverItem) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text($r('app.string.gallery_archiver_bot_original'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      Row({ space: ThemeConstants.SPACE_XS }) {
        Text(this.botMeta(item))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .borderRadius(ThemeConstants.RADIUS_MD)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.enqueueBotArchiveDownload(item)
    })
  }

  private confirmArchiveSubmit(item: EhGalleryArchiverItem, isHath: boolean): void {
    if (this.submittingKey.length > 0) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: isHath ? $r('app.string.gallery_archiver_hath_confirm') : $r('app.string.gallery_archiver_download_confirm'),
      message: this.confirmMessage(item),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.submitArchive(item, isHath)
        },
      },
    })
  }

  private async submitArchive(item: EhGalleryArchiverItem, isHath: boolean): Promise<void> {
    const key: string = this.submitKey(item, isHath)
    if (this.submittingKey.length > 0) {
      return
    }
    this.submittingKey = key
    DiagnosticLogger.info(
      'gallery',
      'archiver_submit_start',
      `gid=${this.params.gid} type=${isHath ? 'hath' : 'local'} dltype=${item.dltype}`,
    )
    try {
      const result: EhGalleryArchiverSubmitResult = isHath
        ? await EhApiService.getInstance().submitGalleryArchiverHath(
          this.params.gid,
          this.params.token,
          this.params.archiverLink,
          item.dltype,
          this.params.isEx,
        )
        : await EhApiService.getInstance().submitGalleryArchiverLocal(
          this.params.gid,
          this.params.token,
          this.params.archiverLink,
          item.dltype,
          this.localDlcheck(item),
          this.params.isEx,
      )
      if (!isHath && result.localDownloadUrl.length > 0) {
        await this.enqueueLocalArchiveDownload(item, result.localDownloadUrl)
      } else if (result.message.length > 0) {
        this.showArchiverToast(result.message)
      } else {
        this.showArchiverToast($r('app.string.gallery_archiver_submitted'))
      }
      DiagnosticLogger.info(
        'gallery',
        'archiver_submit_done',
        `gid=${this.params.gid} type=${isHath ? 'hath' : 'local'} hasDownload=${result.localDownloadUrl.length > 0}`,
      )
    } catch (e) {
      this.showArchiverToast(EhErrorText.forUser(e))
      DiagnosticLogger.warn(
        'gallery',
        'archiver_submit_failed',
        `gid=${this.params.gid} type=${isHath ? 'hath' : 'local'} dltype=${item.dltype} error=${(e as Error).message}`,
      )
    }
    this.submittingKey = ''
  }

  private async enqueueLocalArchiveDownload(item: EhGalleryArchiverItem, url: string): Promise<void> {
    const task: DownloadArchiverTask = new DownloadArchiverTask()
    task.gid = this.params.gid
    task.token = this.params.token
    task.dltype = item.dltype
    task.tag = `${task.gid}:${task.dltype}`
    task.title = this.params.title
    task.thumbUrl = this.params.thumbUrl
    task.resolution = item.resolution
    task.url = url
    const shouldDownload: boolean = await DownloadQueueSettings.enqueueArchiver(this.ctx(), task)
    if (!shouldDownload) {
      this.showArchiverToast($r('app.string.download_archiver_already_queued'))
      return
    }
    this.showArchiverToast($r('app.string.gallery_archiver_download_started'))
    DownloadQueueSettings.downloadArchiver(this.ctx(), task.tag).catch((error: Error) => {
      DiagnosticLogger.warn(
        'download',
        'archiver_background_start_failed',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(task.tag)} error=${error.message}`,
      )
    })
  }

  private async enqueueBotArchiveDownload(item: EhGalleryArchiverItem): Promise<void> {
    if (!DownloadSettings.archiveBotReady(this.downloadSettings)) {
      this.showArchiverToast($r('app.string.gallery_archiver_bot_not_ready'))
      return
    }
    const task: DownloadArchiverTask = new DownloadArchiverTask()
    task.gid = this.params.gid
    task.token = this.params.token
    task.dltype = 'org'
    task.tag = `${task.gid}:org`
    task.title = this.params.title
    task.thumbUrl = this.params.thumbUrl
    task.resolution = item.resolution.length > 0 ? item.resolution : AppStrings.get('gallery_archiver_bot_original')
    task.parseSource = DownloadArchiverParseSource.BOT
    task.url = ''
    const shouldDownload: boolean = await DownloadQueueSettings.enqueueArchiver(this.ctx(), task)
    if (!shouldDownload) {
      this.showArchiverToast($r('app.string.download_archiver_already_queued'))
      return
    }
    DiagnosticLogger.info(
      'gallery',
      'archiver_bot_enqueue',
      `gid=${this.params.gid} tagHash=${DiagnosticLogger.ownerHash(task.tag)}`,
    )
    this.showArchiverToast($r('app.string.gallery_archiver_download_started'))
    DownloadQueueSettings.downloadArchiver(this.ctx(), task.tag).catch((error: Error) => {
      DiagnosticLogger.warn(
        'download',
        'archiver_background_start_failed',
        `gid=${task.gid} tagHash=${DiagnosticLogger.ownerHash(task.tag)} error=${error.message}`,
      )
    })
  }

  private showArchiverToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
      // The submit/open path already completed or failed; toast failure should not change state.
    })
  }

  private confirmMessage(item: EhGalleryArchiverItem): string {
    const parts: string[] = []
    if (item.resolution.length > 0) {
      parts.push(item.resolution)
    }
    if (item.sizeText.length > 0 || item.priceText.length > 0) {
      parts.push(`${item.sizeText} · ${item.priceText}`.trim())
    }
    parts.push(AppStrings.get('gallery_archiver_submit_notice'))
    return parts.join('\n')
  }

  private quoteMeta(item: EhGalleryArchiverItem): string {
    if (item.sizeText.length > 0 && item.priceText.length > 0) {
      return `${item.sizeText} · ${item.priceText}`
    }
    return item.sizeText.length > 0 ? item.sizeText : item.priceText
  }

  private botMeta(item: EhGalleryArchiverItem): string {
    if (item.sizeText.length > 0) {
      return `${item.sizeText} · ${AppStrings.get('gallery_archiver_bot_free')}`
    }
    return AppStrings.get('gallery_archiver_bot_free')
  }

  private botArchiveItem(): EhGalleryArchiverItem {
    const item: EhGalleryArchiverItem = new EhGalleryArchiverItem()
    for (let i: number = 0; i < this.quote.downloadItems.length; i++) {
      if (this.quote.downloadItems[i].dltype === 'org') {
        item.resolution = this.quote.downloadItems[i].resolution
        item.sizeText = this.quote.downloadItems[i].sizeText
        return item
      }
    }
    item.resolution = AppStrings.get('gallery_archiver_bot_original')
    return item
  }

  private localDlcheck(item: EhGalleryArchiverItem): string {
    if (item.dlcheck.length > 0) {
      return item.dlcheck
    }
    return item.dltype === 'org' ? 'Download Original Archive' : 'Download Resample Archive'
  }

  private isSubmittingItem(item: EhGalleryArchiverItem, isHath: boolean): boolean {
    return this.submittingKey === this.submitKey(item, isHath)
  }

  private submitKey(item: EhGalleryArchiverItem, isHath: boolean): string {
    return `${isHath ? 'h' : 'l'}:${item.dltype}`
  }

  @Builder
  private Content() {
    if (this.loading) {
      ListItem() {
        Row() {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
            .color(ThemeConstants.BRAND_PRIMARY)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(ThemeConstants.SPACE_MD)
      }
    } else if (this.error.length > 0) {
      ListItem() {
        PageErrorState({
          message: this.error,
          expand: false,
          retryAction: () => {
            this.load()
          },
        })
      }
    } else if (this.quote.downloadItems.length === 0 && this.quote.hathItems.length === 0) {
      ListItem() {
        CardEmptyState({ message: $r('app.string.gallery_archiver_empty') })
      }
    } else {
      this.BalanceRow()
      this.QuoteList($r('app.string.gallery_archiver_download'), this.quote.downloadItems, false)
      this.QuoteList($r('app.string.gallery_archiver_hath'), this.quote.hathItems, true)
      this.BotQuoteList()
    }
  }

  build() {
    if (this.modal) {
      AppModalScaffold({
        title: $r('app.string.gallery_archiver'),
        showConfirmAction: false,
        closeAction: () => {
          if (this.closeAction) {
            this.closeAction()
          }
        },
      }) {
        this.Content()
      }
    } else {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        this.Content()
      }
    }
  }
}

@ComponentV2
export struct GalleryArchiverPage {
  @Local params: GalleryArchiverParams = new GalleryArchiverParams();

  build() {
    HdsNavDestination() {
      if (this.params.gid.length > 0) {
        GalleryArchiverContent({ params: this.params })
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('gallery_archiver')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryArchiverParams
      if (p !== undefined) {
        this.params = p
      }
    })
  }
}
