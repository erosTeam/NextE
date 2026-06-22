import { HdsNavDestination } from '@kit.UIDesignKit'
import { common, Want } from '@kit.AbilityKit'
import {
  ThemeConstants,
  EhApiService,
  EhGalleryArchiverItem,
  EhGalleryArchiverQuote,
  EhGalleryArchiverSubmitResult,
  GalleryArchiverParams,
  SecondaryListScaffold,
  PageErrorState,
  CardEmptyState,
  AppStrings,
  EhErrorText,
  immersiveTitleBar,
} from 'shared'

/**
 * Archive quote/options page. Grounded in eros_fe ArchiverView: local archive options POST
 * `dltype/dlcheck` and return a generated download URL; H@H options POST `hathdl_xres` and return an
 * EH status message. Every submit remains protected behind a native confirmation because it can spend
 * account GP/Credits.
 */
@ComponentV2
export struct GalleryArchiverPage {
  @Local params: GalleryArchiverParams = new GalleryArchiverParams();
  @Local quote: EhGalleryArchiverQuote = new EhGalleryArchiverQuote();
  @Local loading: boolean = false;
  @Local error: string = '';
  @Local submittingKey: string = '';
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private async load(): Promise<void> {
    if (this.params.gid.length === 0 || this.params.token.length === 0 || this.params.archiverLink.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      this.quote = await EhApiService.getInstance().getGalleryArchiver(
        this.params.gid,
        this.params.token,
        this.params.archiverLink,
        this.params.isEx,
      )
    } catch (e) {
      this.error = EhErrorText.forUser(e)
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
    Row({ space: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(item.resolution)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${item.sizeText}    ${item.priceText}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      if (this.isSubmittingItem(item, isHath)) {
        LoadingProgress()
          .width(ThemeConstants.LOADING_SIZE_SMALL)
          .height(ThemeConstants.LOADING_SIZE_SMALL)
          .color(ThemeConstants.BRAND_PRIMARY)
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([$r('sys.color.font_secondary')])
      }
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
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
          ForEach(items, (item: EhGalleryArchiverItem) => {
            this.QuoteRow(item, isHath)
          }, (item: EhGalleryArchiverItem) => `${item.dltype}:${item.resolution}`)
        }
        .width('100%')
      }
    }
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
        this.openLocalArchiveDownload(result.localDownloadUrl)
      } else if (result.message.length > 0) {
        this.showArchiverToast(result.message)
      } else {
        this.showArchiverToast($r('app.string.gallery_archiver_submitted'))
      }
    } catch (e) {
      this.showArchiverToast(EhErrorText.forUser(e))
    }
    this.submittingKey = ''
  }

  private openLocalArchiveDownload(url: string): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: url }
    this.ctx().startAbility(want).then(() => {
      this.showArchiverToast($r('app.string.gallery_archiver_download_started'))
    }).catch((_error: Error) => {
      this.showArchiverToast(url)
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

  private localDlcheck(item: EhGalleryArchiverItem): string {
    return item.dltype === 'org' ? 'Original Archive' : 'Resample Archive'
  }

  private isSubmittingItem(item: EhGalleryArchiverItem, isHath: boolean): boolean {
    return this.submittingKey === this.submitKey(item, isHath)
  }

  private submitKey(item: EhGalleryArchiverItem, isHath: boolean): string {
    return `${isHath ? 'h' : 'l'}:${item.dltype}`
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
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
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('gallery_archiver')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryArchiverParams
      if (p !== undefined) {
        this.params = p
        this.load()
      }
    })
  }
}
