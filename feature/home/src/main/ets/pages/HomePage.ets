import {
  connectAuth,
  AuthState,
  connectHomeSource,
  HomeSourceState,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  ThemeConstants,
} from 'shared'
import { GallerySourcePage } from '../components/GallerySourcePage'

/**
 * Gallery tab: retained per-SOURCE sub-tabs (V2Next HomePage/Swiper pattern). The source switcher
 * (默认/热门/订阅) is pinned in the HDS title bar (HomeSourceBar in entry) and writes the shared
 * HomeSourceState — a pure SELECTION BUS, not a datasource. This page renders one retained
 * GallerySourcePage per source inside a Swiper; each source owns its OWN GalleryListViewModel +
 * scroller, kept alive by the Swiper (cachedCount), so switching source away and back preserves that
 * source's list AND scroll offset instead of reloading one shared list.
 *
 * Index owns the title-bar scroll-up auto-hide; it binds to the ACTIVE source's scroller, which this
 * page reports up via onScrollerReady whenever the active source changes.
 */
@ComponentV2
export struct HomePage {
  @Local auth: AuthState = connectAuth();
  @Local homeSource: HomeSourceState = connectHomeSource();
  private swiperController: SwiperController = new SwiperController();
  // One stable scroller per source key (created lazily). Stable identity = retained scroll per source.
  private sourceScrollers: Map<string, Scroller> = new Map<string, Scroller>();
  // Per-frame interpolated index the source bar's sliding indicator reads (V2Next FeedVisualIndexState).
  private visual: TabVisualIndexState = connectHomeSourceVisualIndex();
  // Measured Swiper width, for interpolating the visual index from the mid-swipe offset.
  private swiperWidth: number = 0;
  // Index consumes the ACTIVE source's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;

  // 订阅 (watched) is login-only (eros_fe). Logged out → only 默认 + 热门; the keyed ForEach retains the
  // '' / 'popular' page instances when 'watched' is added/removed, so logging in/out never reloads them.
  private visibleSources(): string[] {
    return this.auth.isLogin ? ['', 'popular', 'watched'] : ['', 'popular']
  }

  private scrollerForSource(key: string): Scroller {
    const existing: Scroller | undefined = this.sourceScrollers.get(key)
    if (existing !== undefined) {
      return existing
    }
    const scroller: Scroller = new Scroller()
    this.sourceScrollers.set(key, scroller)
    return scroller
  }

  // Index of the selected source within the visible list (clamped to a valid page).
  private activeIndex(): number {
    const idx: number = this.visibleSources().indexOf(this.homeSource.source)
    return idx < 0 ? 0 : idx
  }

  private notifyActiveScroller(): void {
    if (this.onScrollerReady) {
      this.onScrollerReady(this.scrollerForSource(this.homeSource.source))
    }
  }

  // Interpolate the bar's visual index from the mid-swipe offset so the indicator tracks the finger.
  private visualFromOffset(index: number, extraInfo: SwiperAnimationEvent): number {
    if (this.swiperWidth <= 0) {
      return index
    }
    return index + -extraInfo.currentOffset / this.swiperWidth
  }

  aboutToAppear(): void {
    this.visual.value = this.activeIndex()
    this.notifyActiveScroller()
  }

  // Source switch from the pinned bar (默认/热门/订阅) → swipe the Swiper to that retained page (no
  // shared-list reload). Report the new active scroller up so the title auto-hide follows it.
  @Monitor('homeSource.source')
  onSourceChange(): void {
    const idx: number = this.activeIndex()
    this.swiperController.changeIndex(idx, true)
    this.notifyActiveScroller()
  }

  // 订阅 (watched) is login-only; if the user logs out while on it, fall back to the front page. The
  // visible-source list also drops 'watched' (keyed ForEach retains '' / 'popular').
  @Monitor('auth.isLogin')
  onLoginChange(): void {
    if (!this.auth.isLogin && this.homeSource.source === 'watched') {
      this.homeSource.source = ''
    }
  }

  build() {
    Swiper(this.swiperController) {
      ForEach(
        this.visibleSources(),
        (key: string) => {
          GallerySourcePage({
            sourceKey: key,
            isActive: key === this.homeSource.source,
            scroller: this.scrollerForSource(key),
          })
        },
        (key: string) => key,
      )
    }
    .index(this.activeIndex())
    // Retain ALL visible sources (only 2–3) so any away/back switch keeps that source's list + scroll.
    .cachedCount(this.visibleSources().length)
    .nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
    .indicator(false)
    .loop(false)
    // Publish the interpolated visual index so the source bar's indicator tracks the swipe (V2Next).
    .onGestureSwipe((index: number, extraInfo: SwiperAnimationEvent) => {
      this.visual.value = this.visualFromOffset(index, extraInfo)
    })
    .onAnimationStart((index: number, targetIndex: number, extraInfo: SwiperAnimationEvent) => {
      this.visual.value = this.visualFromOffset(index, extraInfo)
      this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
        this.visual.value = targetIndex
      })
    })
    .onAnimationEnd((index: number, _extraInfo: SwiperAnimationEvent) => {
      this.visual.value = index
    })
    .onChange((i: number) => {
      const sources: string[] = this.visibleSources()
      if (i < 0 || i >= sources.length) {
        return
      }
      this.visual.value = i
      const key: string = sources[i]
      if (key !== this.homeSource.source) {
        this.homeSource.source = key
      }
      this.notifyActiveScroller()
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.swiperWidth = newValue.width as number
    })
    .width('100%')
    .height('100%')
  }
}
