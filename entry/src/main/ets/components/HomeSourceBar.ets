import {
  AuthState,
  connectAuth,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  SubTabBar,
  TabItem,
  CustomProfilesState,
  connectCustomProfiles,
  CustomProfile,
  connectNavStack,
  ThemeConstants,
  SafeModeState,
  connectSafeMode,
  ThemeDisplayState,
  connectThemeDisplay,
  SubtabTransitionBridge,
  SUBTAB_TRANSITION_SCOPE_HOME,
} from 'shared'

/**
 * Gallery-tab source switcher, PINNED in the HDS title bar via a `bottomBuilder` (V2Next FeedPills
 * pattern) — never a scrolling list item. 默认 (front page) + 热门 (popular) always show; 订阅 (watched)
 * only when logged in (its tab list must match HomePage.visibleSources()).
 *
 * The selected glass capsule is driven by the per-frame visual index that HomePage's retained Swiper
 * publishes — so the highlight tracks the finger/page swipe instead of jumping on settle. A tap requests the
 * host's native transition; the selected profile is published after it settles.
 */
@ComponentV2
export struct HomeSourceBar {
  @Local profiles: CustomProfilesState = connectCustomProfiles();
  @Local auth: AuthState = connectAuth();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();

  // Must mirror HomePage.visibleSources() order so the visual index lines up with the right tab:
  // non-hidden profiles, login-gated (watched/favorite need an account). The TabItem label is the
  // profile name (a plain string), so a rename produces a new label → SubTabBar redraws.
  private tabs(): TabItem[] {
    const items: TabItem[] = []
    this.profiles.profiles.forEach((p: CustomProfile) => {
      if (!p.hidden && !(p.requiresLogin() && !this.auth.isLogin)) {
        items.push(new TabItem(p.uuid, p.name))
      }
    })
    return items
  }

  private selectedIndex(): number {
    const items: TabItem[] = this.tabs()
    const index: number = items.findIndex((item: TabItem) => item.key === this.profiles.selectedUuid)
    return index < 0 ? 0 : index
  }

  private themeTracked(color: ResourceColor): ResourceColor {
    return this.themeDisplay.effectiveDark ? color : color
  }

  build() {
    Row() {
      SubTabBar({
        tabs: this.tabs(),
        visualIndex: this.visual.value,
        selectedIndex: this.selectedIndex(),
        onSelect: (index: number) => {
          const items: TabItem[] = this.tabs()
          if (index >= 0 && index < items.length && items[index].key !== this.profiles.selectedUuid) {
            SubtabTransitionBridge.request(SUBTAB_TRANSITION_SCOPE_HOME, items[index].key)
          }
        },
      })
        .layoutWeight(1)
      // Pinned trailing affordance to manage tabs (outside the scroll so it never scrolls away).
      // The capsules centre themselves on the bar's cross axis, so the chip simply inherits this Row's
      // VerticalAlign.Center — no alignSelf/offset nudge (that existed only for the old top-aligned labels).
      // No left margin: the bar's own contentEndOffset already leaves SPACE_MD of clear space in front of the
      // chip (a touch wider than the 8vp between capsules — the separation a different-kind control wants).
      // The right margin mirrors the bar's inset so both screen edges breathe equally.
      if (!this.safeMode.restricted()) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.list_square'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontColor([this.themeTracked($r('sys.color.font_secondary'))])
        }
        .width(28)
        .height(28)
        .margin({ right: ThemeConstants.SPACE_MD })
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          connectNavStack().stack.pushPathByName('TabManager', null)
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }
}
@Builder
export function HomeSourceBarCCBuilder(_arg: Object) {
  HomeSourceBar()
}
