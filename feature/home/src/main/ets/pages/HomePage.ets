import {
  connectAuth,
  AuthState,
  connectHomeSource,
  HomeSourceState,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  RetainedSubtabHost,
  ActiveKeyState,
  SubtabSelectionSettings,
  connectListMode,
  ListModeState,
  ListMode,
  ListModeSettings,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { GallerySourcePage } from '../components/GallerySourcePage'

// Global @Builder (no `this`) so passing it to RetainedSubtabHost's @BuilderParam under @ComponentV2
// can't hit the instance-@Builder `this`-loss crash. Renders one retained gallery-source page per key,
// handed the SHARED active-key signal (so cached pages still get their first-activation load).
@Builder
function gallerySourcePageBuilder(
  key: string,
  active: ActiveKeyState,
  scroller: Scroller,
  onDidScroll: (offset: number, state: ScrollState) => void,
) {
  GallerySourcePage({ sourceKey: key, active: active, scroller: scroller, onDidScroll: onDidScroll })
}

/**
 * Gallery tab: retained per-SOURCE sub-tabs on the shared RetainedSubtabHost framework. The source
 * switcher (默认/热门/订阅, HomeSourceBar in the title bar) writes the HomeSourceState selection BUS; the
 * host swipes to the retained GallerySourcePage for that source (each owns its own VM + scroller) and
 * publishes the visual index for the bar's sliding indicator. HomePage only adapts this surface to the
 * framework: the visible source keys (login-gated), the selection bus read/write, and the scroller handoff.
 */
@ComponentV2
export struct HomePage {
  @Local auth: AuthState = connectAuth();
  @Local homeSource: HomeSourceState = connectHomeSource();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();
  @Local listMode: ListModeState = connectListMode();
  @Local layoutMenuShown: boolean = false;
  // Index consumes the ACTIVE source's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // 订阅 (watched) is login-only (eros_fe). The keyed host retains '' / 'popular' when 'watched' is added/
  // removed on login change. Must mirror HomeSourceBar's tab order so the visual index lines up.
  private visibleSources(): string[] {
    return this.auth.isLogin ? ['', 'popular', 'watched'] : ['', 'popular']
  }

  // If the user logs out while on 订阅, fall back to the front page (the host then drops the 'watched' key).
  @Monitor('auth.isLogin')
  onLoginChange(): void {
    if (!this.auth.isLogin && this.homeSource.source === 'watched') {
      SubtabSelectionSettings.setHomeSource(this.ctx(), '', false)
    }
  }

  // The title-bar layout icon publishes 'openLayoutMenu' (it can't anchor a Menu itself).
  @Monitor('homeSource.cmdSeq')
  onHomeCommand(): void {
    if (this.homeSource.cmdKind === 'openLayoutMenu') {
      this.layoutMenuShown = true
    }
  }

  private setViewMode(mode: string): void {
    ListModeSettings.setMode(this.ctx(), mode)
    this.layoutMenuShown = false
  }

  @Builder
  LayoutMenu() {
    Menu() {
      this.LayoutMenuItem($r('app.string.view_list'), ListMode.LIST)
      this.LayoutMenuItem($r('app.string.view_simple'), ListMode.SIMPLE_LIST)
      this.LayoutMenuItem($r('app.string.view_grid'), ListMode.GRID)
      this.LayoutMenuItem($r('app.string.view_waterfall'), ListMode.WATERFALL)
      this.LayoutMenuItem($r('app.string.view_cover_wall'), ListMode.COVER_WALL)
    }
  }

  @Builder
  LayoutMenuItem(label: ResourceStr, mode: string) {
    MenuItem({
      content: label,
      symbolEndIcon:
        this.listMode.mode === mode
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
    }).onClick(() => {
      this.setViewMode(mode)
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      RetainedSubtabHost({
        keys: this.visibleSources(),
        selectedKey: this.homeSource.source,
        pageBuilder: gallerySourcePageBuilder,
        onSelectKey: (key: string) => {
          SubtabSelectionSettings.setHomeSource(this.ctx(), key, this.auth.isLogin)
        },
        onVisualIndex: (value: number) => {
          this.visual.value = value
        },
        onScrollerReady: (scroller: Scroller) => {
          if (this.onScrollerReady) {
            this.onScrollerReady(scroller)
          }
        },
        onDidScroll: (offset: number, state: ScrollState) => {
          if (this.onDidScroll) {
            this.onDidScroll(offset, state)
          }
        },
      })
      // Invisible anchor for the native layout dropdown at the content's trailing edge, near the title-bar
      // layout icon. bindMenu can't attach to the HDS title-bar icon, so the icon opens this owned Menu
      // via the command bus (mirrors FavoritesPage's order menu).
      Row()
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
        .bindMenu(this.layoutMenuShown, this.LayoutMenu, {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.layoutMenuShown = false
          },
        })
    }
    .width('100%')
    .height('100%')
  }
}
