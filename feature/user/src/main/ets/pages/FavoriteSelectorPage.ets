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
} from 'shared'

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
    if (favId === 'a') {
      return ThemeConstants.FAV_HEART_DEFAULT
    }
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
      return AppStrings.get('common_yes')
    }
    return fc.totNum >= 0 ? `${fc.totNum}` : ''
  }

  private selectFavcat(favId: string): void {
    this.fav.selectedFavcat = favId.length > 0 ? favId : 'a'
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
              trailingText: this.trailingFor(fc),
              showChevron: false,
              leadingIcon: $r('sys.symbol.heart_fill'),
              primaryColor: this.isSelected(fc) ? ThemeConstants.BRAND_PRIMARY : undefined,
              secondaryColor: this.colorFor(fc.favId),
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
