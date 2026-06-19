import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  GalleryRemoteFavoriteParams,
  GalleryWebParams,
  Favcat,
  connectNavStack,
  connectFavSelection,
  FavSelectionState,
  EhConstants,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  AppStrings,
  immersiveTitleBar,
} from 'shared'

/**
 * Non-destructive remote EH favorite entry. eros_fe's GalleryFavController/FavController eventually
 * POSTs the EH favorite popup endpoint; NextE intentionally stops before that protected write flow.
 */
@ComponentV2
export struct GalleryRemoteFavoritePage {
  @Local params: GalleryRemoteFavoriteParams = new GalleryRemoteFavoriteParams();
  @Local favSelection: FavSelectionState = connectFavSelection();
  private scroller: Scroller = new Scroller();

  private isRemoteFavorited(): boolean {
    return this.params.favcat.length > 0
  }

  private titleText(): string {
    return this.params.title.length > 0 ? this.params.title : AppStrings.get('detail_remote_favorite')
  }

  private currentFavTitle(): string {
    if (this.params.favTitle.length > 0) {
      return this.params.favTitle
    }
    if (this.params.favcat.length > 0) {
      return `Favorites ${this.params.favcat}`
    }
    return AppStrings.get('detail_remote_favorite_none')
  }

  private remoteFavoriteActionMessage(actionLabel: ResourceStr): ResourceStr {
    if (typeof actionLabel === 'string') {
      return `${actionLabel}\n${AppStrings.get('detail_remote_favorite_protected_desc')}`
    }
    return $r('app.string.detail_remote_favorite_protected_desc')
  }

  private confirmRemoteWrite(actionLabel: ResourceStr): void {
    this.getUIContext().showAlertDialog({
      message: this.remoteFavoriteActionMessage(actionLabel),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.detail_open_internal_web'),
        action: () => {
          this.openInternalWeb()
        },
      },
    })
  }

  private galleryUrl(): string {
    return `${EhConstants.baseUrl(this.params.isEx)}/g/${this.params.gid}/${this.params.token}/`
  }

  private openInternalWeb(): void {
    connectNavStack().stack.pushPathByName(
      'GalleryWeb',
      new GalleryWebParams(this.galleryUrl(), this.titleText()),
    )
  }

  @Builder
  private FavcatSwatch(favcat: string) {
    SymbolGlyph($r('sys.symbol.heart_fill'))
      .fontSize(ThemeConstants.FONT_SIZE_TITLE)
      .fontColor([EhConstants.favCatColor(favcat)])
  }

  @Builder
  private Summary() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.detail_remote_favorite_current'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
        Row({ space: ThemeConstants.SPACE_SM }) {
          if (this.isRemoteFavorited()) {
            this.FavcatSwatch(this.params.favcat)
          } else {
            SymbolGlyph($r('sys.symbol.heart'))
              .fontSize(ThemeConstants.FONT_SIZE_TITLE)
              .fontColor([$r('sys.color.font_secondary')])
          }
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text(this.currentFavTitle())
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.params.favNote.length > 0) {
              Text(this.params.favNote)
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text($r('app.string.detail_remote_favorite_readonly_desc'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      .width('100%')
      .padding(ThemeConstants.SPACE_MD)
    }
  }

  @Builder
  private FavoriteRows() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      if (this.isRemoteFavorited()) {
        ConciseListRow({
          title: $r('app.string.detail_remote_favorite_remove'),
          subtitle: this.currentFavTitle(),
          destructive: true,
          leadingIcon: $r('sys.symbol.heart'),
          action: () => {
            this.confirmRemoteWrite($r('app.string.detail_remote_favorite_remove'))
          },
        })
      }
      ForEach(
        this.favSelection.favList,
        (fav: Favcat) => {
          ConciseListRow({
            title: fav.favTitle,
            subtitle: $r('app.string.detail_remote_favorite_slot', fav.favId),
            trailingText: fav.totNum > 0 ? `${fav.totNum}` : '',
            showChevron: true,
            action: () => {
              this.confirmRemoteWrite(fav.favTitle)
            },
            prefixBuilderParam: () => {
              this.FavcatSwatch(fav.favId)
            },
          })
        },
        (fav: Favcat) => {
          return fav.favId
        },
      )
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        ListItem() {
          this.Summary()
        }
        ListItem() {
          this.FavoriteRows()
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('detail_remote_favorite')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryRemoteFavoriteParams
      if (p !== undefined) {
        this.params = p
      }
    })
  }
}
