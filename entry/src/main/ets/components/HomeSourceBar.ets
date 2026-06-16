import {
  ThemeConstants,
  HomeSourceState,
  connectHomeSource,
  AuthState,
  connectAuth,
  SELECTOR_BAR_HEIGHT,
} from 'shared'

/**
 * Gallery-tab source switcher, PINNED in the HDS title bar via a `bottomBuilder` (V2Next FeedPills
 * pattern) — never a scrolling list item. eros_fe pins this selector in a persistent header
 * (custom_tabbar_page.dart:63-77). 默认 (front page) + 热门 (popular) always show; 订阅 (watched)
 * only when logged in. Toplist is its OWN bottom tab now (排行 left this bar), so this is a single
 * substantial row — no period sub-row, no wrap.
 */
@ComponentV2
export struct HomeSourceBar {
  @Local home: HomeSourceState = connectHomeSource();
  @Local auth: AuthState = connectAuth();

  build() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      this.Tab('', $r('app.string.home_source_default'))
      this.Tab('popular', $r('app.string.home_source_popular'))
      if (this.auth.isLogin) {
        this.Tab('watched', $r('app.string.home_source_watched'))
      }
    }
    .width('100%')
    .height(SELECTOR_BAR_HEIGHT)
    .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
    .alignItems(VerticalAlign.Center)
  }

  // V2Next FeedPills approach (IndexTitleBarComponents.ets:118-164): a text tab — brand color +
  // Medium weight when selected, secondary + Regular when not — over a short brand underline. No
  // capsule background (a pill with a translucent fill read as low-contrast; this is readable).
  @Builder
  Tab(value: string, label: ResourceStr) {
    Column({ space: 1 }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(
          this.home.source === value
            ? ThemeConstants.BRAND_PRIMARY
            : $r('sys.color.font_secondary'),
        )
        .fontWeight(this.home.source === value ? FontWeight.Medium : FontWeight.Regular)
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          top: ThemeConstants.SPACE_XS,
        })
        .maxLines(1)
      Row()
        .height(3)
        .width(18)
        .borderRadius(1.5)
        .backgroundColor(
          this.home.source === value ? ThemeConstants.BRAND_PRIMARY : Color.Transparent,
        )
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.home.source = value
    })
  }
}
@Builder
export function HomeSourceBarCCBuilder(_arg: Object) {
  HomeSourceBar()
}
