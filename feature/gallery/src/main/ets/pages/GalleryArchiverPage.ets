import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhApiService,
  EhGalleryArchiverItem,
  EhGalleryArchiverQuote,
  GalleryArchiverParams,
  SecondaryListScaffold,
  PageErrorState,
  CardEmptyState,
  AppStrings,
  EhErrorText,
  immersiveTitleBar,
} from 'shared'

/**
 * Read-only archive quote/options page. Grounded in eros_fe ArchiverView, but intentionally does not
 * submit local/H@H archive downloads until the download executor lane is designed and accepted.
 */
@ComponentV2
export struct GalleryArchiverPage {
  @Local params: GalleryArchiverParams = new GalleryArchiverParams();
  @Local quote: EhGalleryArchiverQuote = new EhGalleryArchiverQuote();
  @Local loading: boolean = false;
  @Local error: string = '';
  private scroller: Scroller = new Scroller();

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
  private QuoteRow(item: EhGalleryArchiverItem) {
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
  }

  @Builder
  private QuoteList(title: ResourceStr, items: EhGalleryArchiverItem[]) {
    if (items.length > 0) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          this.SectionTitle(title)
          ForEach(items, (item: EhGalleryArchiverItem) => {
            this.QuoteRow(item)
          }, (item: EhGalleryArchiverItem) => `${item.dltype}:${item.resolution}`)
        }
        .width('100%')
      }
    }
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
          this.QuoteList($r('app.string.gallery_archiver_download'), this.quote.downloadItems)
          this.QuoteList($r('app.string.gallery_archiver_hath'), this.quote.hathItems)
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
