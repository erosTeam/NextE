import {
  connectAuth,
  AuthState,
  connectHomeSource,
  HomeSourceState,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  RetainedSubtabHost,
  ActiveKeyState,
  connectCustomProfiles,
  CustomProfilesState,
  CustomProfile,
  CustomProfilesSettings,
  PROFILE_DISPLAY_GLOBAL,
  ListMode,
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
  @Local profiles: CustomProfilesState = connectCustomProfiles();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();
  @Local layoutMenuShown: boolean = false;
  // Index consumes the ACTIVE source's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Ordered uuids of the visible (non-hidden, login-gated) profiles — the Swiper keys. Must mirror
  // HomeSourceBar.tabs() exactly so the visual index lines up. watched/favorite profiles drop when
  // logged out (CustomProfile.requiresLogin()).
  private visibleSources(): string[] {
    const keys: string[] = []
    this.profiles.profiles.forEach((p: CustomProfile) => {
      if (!p.hidden && !(p.requiresLogin() && !this.auth.isLogin)) {
        keys.push(p.uuid)
      }
    })
    return keys
  }

  // Selected profile uuid clamped to a currently-visible key (so a hidden/removed/login-gated selection
  // can't strand the host on a missing key).
  private selectedKey(): string {
    const keys: string[] = this.visibleSources()
    const sel: string = this.profiles.selectedUuid
    if (keys.indexOf(sel) >= 0) {
      return sel
    }
    return keys.length > 0 ? keys[0] : ''
  }

  // If the user logs out while a login-only (watched/favorite) profile is selected, fall back to the
  // first visible profile (the host then drops the login-gated keys).
  @Monitor('auth.isLogin')
  onLoginChange(): void {
    if (this.auth.isLogin) {
      return
    }
    const sel: CustomProfile | null = this.profiles.findByUuid(this.profiles.selectedUuid)
    if (sel !== null && sel.requiresLogin()) {
      const keys: string[] = this.visibleSources()
      if (keys.length > 0) {
        CustomProfilesSettings.setSelected(this.ctx(), keys[0])
      }
    }
  }

  // The title-bar layout icon publishes 'openLayoutMenu' (it can't anchor a Menu itself).
  @Monitor('homeSource.cmdSeq')
  onHomeCommand(): void {
    if (this.homeSource.cmdKind === 'openLayoutMenu') {
      this.layoutMenuShown = true
    }
  }

  // The layout menu now pins the display mode to the ACTIVE tab (eros_fe per-tab renderer), via the
  // light setDisplayMode (no refetch). 跟随全局 ('global') reverts the tab to the shared default.
  private setViewMode(mode: string): void {
    CustomProfilesSettings.setDisplayMode(this.ctx(), this.selectedKey(), mode)
    this.layoutMenuShown = false
  }

  private activeDisplayMode(): string {
    const p: CustomProfile | null = connectCustomProfiles().findByUuid(this.selectedKey())
    return p !== null ? p.displayMode : PROFILE_DISPLAY_GLOBAL
  }

  @Builder
  LayoutMenu() {
    Menu() {
      this.LayoutMenuItem($r('app.string.view_follow_global'), PROFILE_DISPLAY_GLOBAL)
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
        this.activeDisplayMode() === mode
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
        selectedKey: this.selectedKey(),
        pageBuilder: gallerySourcePageBuilder,
        onSelectKey: (key: string) => {
          CustomProfilesSettings.setSelected(this.ctx(), key)
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
