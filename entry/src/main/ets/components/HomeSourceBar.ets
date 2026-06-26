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
  CustomProfilesSettings,
  connectNavStack,
  ThemeConstants,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Gallery-tab source switcher, PINNED in the HDS title bar via a `bottomBuilder` (V2Next FeedPills
 * pattern) — never a scrolling list item. 默认 (front page) + 热门 (popular) always show; 订阅 (watched)
 * only when logged in (its tab list must match HomePage.visibleSources()).
 *
 * The indicator is the shared SubTabBar's sliding underline, driven by the per-frame visual index that
 * HomePage's retained Swiper publishes — so the bar tracks the finger/page swipe instead of jumping on
 * settle. A tap publishes the source key (the bus); HomePage swipes the Swiper, which drives the indicator.
 */
@ComponentV2
export struct HomeSourceBar {
  @Local profiles: CustomProfilesState = connectCustomProfiles();
  @Local auth: AuthState = connectAuth();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

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

  build() {
    Row() {
      SubTabBar({
        tabs: this.tabs(),
        visualIndex: this.visual.value,
        selectedIndex: this.selectedIndex(),
        scrollable: true,
        onSelect: (index: number) => {
          const items: TabItem[] = this.tabs()
          if (index >= 0 && index < items.length) {
            CustomProfilesSettings.setSelected(this.ctx(), items[index].key)
          }
        },
      })
        .layoutWeight(1)
      // Pinned trailing affordance to manage tabs (outside the scroll so it never scrolls away).
      // Top-aligned (alignSelf) so the chip sits on the same line as the top-aligned tab labels — only
      // the chip moves; the SubTabBar position is untouched.
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.list_square'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .width(28)
      .height(28)
      .margin({ left: ThemeConstants.SPACE_XS, right: ThemeConstants.SPACE_SM })
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .alignSelf(ItemAlign.Start)
      // Fine nudge so the chip's center matches the top-aligned tab labels' baseline exactly.
      .offset({ y: -2 })
      .onClick(() => {
        connectNavStack().stack.pushPathByName('TabManager', null)
      })
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
