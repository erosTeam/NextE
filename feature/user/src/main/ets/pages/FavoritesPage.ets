import {
  connectAuth,
  AuthState,
  FavSelectionState,
  connectFavSelection,
  connectFavcatVisualIndex,
  TabVisualIndexState,
  Favcat,
  RetainedSubtabHost,
  ActiveKeyState,
  SubtabSelectionSettings,
} from 'shared'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { FavcatPage } from '../components/FavcatPage'

// Global @Builder (no `this`) for RetainedSubtabHost's @BuilderParam. Renders one retained favcat page,
// handed the shared active-key signal.
@Builder
function favcatPageBuilder(key: string, active: ActiveKeyState, scroller: Scroller) {
  FavcatPage({ favcatKey: key, active: active, scroller: scroller })
}

/**
 * Favorites tab (M3) — retained per-FAVCAT sub-tabs on the shared RetainedSubtabHost framework (same as
 * Home/Toplist). Logged out → an actionable login prompt. Logged in → the host swipes between one retained
 * FavcatPage per favcat ('a' = all, '0'..'9'), each owning its OWN FavoritesViewModel + scroller, so
 * switching favcat away and back preserves that favcat's list AND scroll — no shared-list reload.
 *
 * FavSelectionState is the pure selection BUS: FavcatBar (pinned in the title bar) writes `selectedFavcat`;
 * the host swipes to it and publishes the visual index for the bar's sliding indicator. The GLOBAL order
 * menu writes `orderByPosted` (each FavcatPage reloads); the favcat counts (favList) are shared metadata
 * each page publishes. The order action arrives as an `openOrderMenu` command (HDS title-bar icons can't
 * anchor a Menu). FavoritesPage only adapts this surface to the framework — it owns no list mechanics.
 */
@ComponentV2
export struct FavoritesPage {
  @Local auth: AuthState = connectAuth();
  @Local favSel: FavSelectionState = connectFavSelection();
  @Local visual: TabVisualIndexState = connectFavcatVisualIndex();
  @Local orderMenuShown: boolean = false;
  // Index consumes the ACTIVE favcat's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Host keys: logged out sees only synthetic 'l' (local); logged in keeps 'a' + remote slots + 'l'.
  // Order matches FavcatBar's tabs.
  private favcatKeys(): string[] {
    if (!this.auth.isLogin) {
      return ['l']
    }
    const keys: string[] = ['a']
    this.favSel.favList.forEach((f: Favcat) => keys.push(f.favId))
    keys.push('l')
    return keys
  }

  private effectiveSelectedFavcat(): string {
    if (!this.auth.isLogin) {
      return 'l'
    }
    const selected: string = this.favSel.selectedFavcat.length > 0 ? this.favSel.selectedFavcat : 'a'
    return selected === 'l' || selected === 'a' || this.favSel.favList.find((f: Favcat) => f.favId === selected) !== undefined
      ? selected
      : 'a'
  }

  // The title-bar order icon publishes 'openOrderMenu' (it can't anchor a Menu itself).
  @Monitor('favSel.cmdSeq')
  onFavCommand(): void {
    if (this.favSel.cmdKind === 'openOrderMenu') {
      this.orderMenuShown = true
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      RetainedSubtabHost({
        keys: this.favcatKeys(),
        selectedKey: this.effectiveSelectedFavcat(),
        pageBuilder: favcatPageBuilder,
        onSelectKey: (key: string) => {
          SubtabSelectionSettings.setFavoritesFavcat(this.ctx(), key, this.auth.isLogin)
        },
        onVisualIndex: (value: number) => {
          this.visual.value = value
        },
        onScrollerReady: (scroller: Scroller) => {
          if (this.onScrollerReady) {
            this.onScrollerReady(scroller)
          }
        },
      })
      // Invisible anchor for the native order dropdown at the content's trailing edge (under the favcat
      // bar, near the title-bar order icon). bindMenu can't attach to the HDS title-bar icon, so the order
      // action opens this owned Menu via the command bus.
      Row()
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
        .bindMenu(this.orderMenuShown, this.OrderMenu, {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.orderMenuShown = false
          },
        })
    }
    .width('100%')
    .height('100%')
  }

  // Native GLOBAL order dropdown (eros_fe showFavOrder). Writes the shared order bus
  // (FavSelectionState.orderByPosted); each retained FavcatPage reloads with the new order. The active
  // order carries a checkmark (V2Next TopicDetailComponents.ets:192-227).
  @Builder
  OrderMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.fav_order_fav'),
        symbolEndIcon: this.favSel.orderByPosted
          ? undefined
          : new SymbolGlyphModifier($r('sys.symbol.checkmark')),
      })
        .onClick(() => {
          this.favSel.orderByPosted = false
          this.orderMenuShown = false
        })
      MenuItem({
        content: $r('app.string.fav_order_posted'),
        symbolEndIcon: this.favSel.orderByPosted
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          this.favSel.orderByPosted = true
          this.orderMenuShown = false
        })
    }
  }
}
