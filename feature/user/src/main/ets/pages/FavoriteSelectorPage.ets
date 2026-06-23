import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  EhConstants,
  FavSelectionState,
  Favcat,
  GroupedListSection,
  AuthState,
  LocalFavState,
  SecondaryListScaffold,
  ThemeConstants,
  connectAuth,
  connectFavSelection,
  connectLocalFav,
  connectNavStack,
  immersiveTitleBar,
  SubtabSelectionSettings,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Full-screen favcat selector. eros_fe exposes this from the Favorites favcat bar's bars button; NextE
 * keeps the horizontal pinned chips for quick switching and adds this native settings-list overview for
 * long favcat names/counts. It only changes the selected favcat; favorite writes/renames are separate
 * lanes.
 */
@ComponentV2
export struct FavoriteSelectorPage {
  @Local fav: FavSelectionState = connectFavSelection();
  @Local auth: AuthState = connectAuth();
  @Local localFav: LocalFavState = connectLocalFav();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private rows(): Favcat[] {
    const local: Favcat = new Favcat('l', AppStrings.get('favorites_local'), this.localFav.count())
    if (!this.auth.isLogin) {
      return [local]
    }
    const items: Favcat[] = [new Favcat('a', AppStrings.get('favorites_all'), this.fav.remoteTotalCount())]
    this.fav.favList.forEach((fc: Favcat) => items.push(fc))
    items.push(local)
    return items
  }

  private colorFor(favId: string): ResourceColor {
    const c: string = EhConstants.favCatColor(favId)
    return c.length > 0 ? c : ThemeConstants.FAV_HEART_DEFAULT
  }

  private isSelected(fc: Favcat): boolean {
    if (!this.auth.isLogin) {
      return fc.favId === 'l'
    }
    return this.fav.selectedFavcat === fc.favId
  }

  private trailingFor(fc: Favcat): string {
    if (this.isSelected(fc)) {
      return AppStrings.get('detail_remote_favorite_current_badge')
    }
    return fc.totNum >= 0 ? `${fc.totNum}` : ''
  }

  @Builder
  private FavcatPrefix(favId: string) {
    SymbolGlyph($r('sys.symbol.heart_fill'))
      .fontSize(24)
      .fontColor([this.colorFor(favId)])
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
  }

  @Builder
  private FavcatSuffix(fc: Favcat) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      if (this.isSelected(fc)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      Text(this.trailingFor(fc))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ right: ThemeConstants.SPACE_MD })
  }

  private async selectFavcat(favId: string): Promise<void> {
    await SubtabSelectionSettings.setFavoritesFavcat(
      this.ctx(),
      favId.length > 0 ? favId : 'a',
      this.auth.isLogin,
    )
    this.stack.pop()
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private FavcatRows() {
    ListItem() {
      GroupedListSection() {
        ForEach(
          this.rows(),
          (fc: Favcat, index: number) => {
            ConciseListRow({
              title: fc.favTitle,
              trailingText: '',
              showChevron: false,
              prefixBuilderParam: () => {
                this.FavcatPrefix(fc.favId)
              },
              suffixBuilderParam: () => {
                this.FavcatSuffix(fc)
              },
              action: () => {
                this.selectFavcat(fc.favId)
              },
            })
            if (index < this.rows().length - 1) {
              this.rowDivider()
            }
          },
          (fc: Favcat) => `${fc.favId}:${fc.favTitle}:${fc.totNum}`,
        )
      }
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        this.FavcatRows()
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('favorites_selector_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
