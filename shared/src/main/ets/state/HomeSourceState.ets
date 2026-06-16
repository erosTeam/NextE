import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Gallery + Toplist tab selector state. `source` drives the Gallery tab's pinned source bar
 * (''=front page / 'popular' / 'watched' — NOT 'toplist'; toplist is its own bottom tab now,
 * matching eros_fe's IA where 排行 is a top-level CupertinoTabBar destination, NOT a gallery
 * source — tabhome_controller.dart:28). `toplistTl` drives the Toplist tab's pinned period bar.
 *
 * Both bars are pinned title-bar `bottomBuilder`s rendered OUTSIDE the page component tree, so this
 * shared @Trace holder is the only channel between a bar and its page's ViewModel (V2Next
 * FeedTabState/FeedPills pattern). eros_fe pins every list selector in a persistent header
 * (custom_tabbar_page.dart:63-77), never as a scrolling list item.
 */
@ObservedV2
export class HomeSourceState {
  // Gallery tab source: '' front page / 'popular' / 'watched' (login-only).
  @Trace source: string = ''
  // Toplist tab period: tl 11 all-time / 12 year / 13 month / 15 yesterday. Defaults to yesterday
  // (eros_fe's default ranking view — ehsetting_service.dart:144 / default_tabview_controller.dart:58).
  @Trace toplistTl: number = 15
}

const HOME_SOURCE_V2_KEY: string = 'v2:homeSource'

/** Returns the app-wide HomeSourceState singleton from AppStorageV2 (defaults to the front page). */
export function connectHomeSource(): HomeSourceState {
  return AppStorageV2.connect(HomeSourceState, HOME_SOURCE_V2_KEY, () => new HomeSourceState())!
}

/**
 * Per-frame interpolated tab index for a retained-tab selector bar's SLIDING indicator (V2Next
 * FeedVisualIndexState). Kept SEPARATE from the semantic selection key (HomeSourceState.source /
 * .toplistTl): the retained Swiper publishes this float continuously during a swipe (onGestureSwipe /
 * onAnimationStart / onAnimationEnd) so the bar indicator tracks the finger/page animation, while the
 * key only flips when the page settles. High-frequency, so it lives in its own holder to avoid churning
 * the selection observers. One instance per selector surface (different AppStorageV2 keys).
 */
@ObservedV2
export class TabVisualIndexState {
  @Trace value: number = 0
}

export function connectHomeSourceVisualIndex(): TabVisualIndexState {
  return AppStorageV2.connect(TabVisualIndexState, 'v2:homeSourceVisualIndex', () => new TabVisualIndexState())!
}

export function connectToplistVisualIndex(): TabVisualIndexState {
  return AppStorageV2.connect(TabVisualIndexState, 'v2:toplistVisualIndex', () => new TabVisualIndexState())!
}

/**
 * Height (vp) of a pinned selector bar (Gallery source / Toplist period / Favorites favcat). The single
 * source of truth: the HDS `bottomBuilder` height (Index), the page scaffold's top inset (topPadding),
 * AND the SubTabBar both read it, so the reserved space exactly matches the rendered bar — no canyon.
 * 38 matches V2Next's TAB_BAR_HEIGHT/FeedPills (a 44 bar over-reserved ~6vp above the actual pill row).
 */
export const SELECTOR_BAR_HEIGHT: number = 38
