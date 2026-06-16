import {
  connectHomeSource,
  HomeSourceState,
  connectToplistVisualIndex,
  TabVisualIndexState,
  ThemeConstants,
} from 'shared'
import { ToplistPeriodPage } from '../components/ToplistPeriodPage'

// Toplist periods in the bar's order (ToplistPeriodBar): 全部(11) · 年榜(12) · 月榜(13) · 昨日(15).
const TOPLIST_PERIODS: number[] = [11, 12, 13, 15]

/**
 * Toplist (排行) tab — retained per-PERIOD sub-tabs (V2Next Swiper pattern; mirrors HomePage). The period
 * selector (全部/年榜/月榜/昨日) is pinned in the HDS title bar (ToplistPeriodBar in entry) and writes the
 * shared HomeSourceState.toplistTl — a pure SELECTION BUS, not a datasource. NextE presents the period as
 * a subtab, so each period is a retained ToplistPeriodPage owning its OWN GalleryListViewModel + scroller,
 * kept alive by the Swiper (cachedCount), so switching period away and back preserves that period's list
 * AND scroll instead of reloading one shared list.
 *
 * Toplist always hits the e-hentai host (toplist.php 404s on exhentai), so it does not react to 表/里.
 */
@ComponentV2
export struct ToplistPage {
  @Local homeSource: HomeSourceState = connectHomeSource();
  private swiperController: SwiperController = new SwiperController();
  // One stable scroller per period (created lazily) → retained scroll per period.
  private periodScrollers: Map<number, Scroller> = new Map<number, Scroller>();
  // Per-frame interpolated index the period bar's sliding indicator reads (V2Next FeedVisualIndexState).
  private visual: TabVisualIndexState = connectToplistVisualIndex();
  private swiperWidth: number = 0;
  // Index consumes the ACTIVE period's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;

  private scrollerForPeriod(tl: number): Scroller {
    const existing: Scroller | undefined = this.periodScrollers.get(tl)
    if (existing !== undefined) {
      return existing
    }
    const scroller: Scroller = new Scroller()
    this.periodScrollers.set(tl, scroller)
    return scroller
  }

  private activeIndex(): number {
    const idx: number = TOPLIST_PERIODS.indexOf(this.homeSource.toplistTl)
    return idx < 0 ? 0 : idx
  }

  private notifyActiveScroller(): void {
    if (this.onScrollerReady) {
      this.onScrollerReady(this.scrollerForPeriod(this.homeSource.toplistTl))
    }
  }

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

  // Period switch from the pinned bar (tl 11/12/13/15) → swipe to that retained page (no shared-list
  // reload). Report the new active scroller up so the title auto-hide follows it.
  @Monitor('homeSource.toplistTl')
  onPeriodChange(): void {
    this.swiperController.changeIndex(this.activeIndex(), true)
    this.notifyActiveScroller()
  }

  build() {
    Swiper(this.swiperController) {
      ForEach(
        TOPLIST_PERIODS,
        (tl: number) => {
          ToplistPeriodPage({
            periodTl: tl,
            isActive: tl === this.homeSource.toplistTl,
            scroller: this.scrollerForPeriod(tl),
          })
        },
        (tl: number) => `${tl}`,
      )
    }
    .index(this.activeIndex())
    // Retain ALL periods (only 4) so any away/back switch keeps that period's list + scroll.
    .cachedCount(TOPLIST_PERIODS.length)
    .nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
    .indicator(false)
    .loop(false)
    // Publish the interpolated visual index so the period bar's indicator tracks the swipe (V2Next).
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
      if (i < 0 || i >= TOPLIST_PERIODS.length) {
        return
      }
      this.visual.value = i
      const tl: number = TOPLIST_PERIODS[i]
      if (tl !== this.homeSource.toplistTl) {
        this.homeSource.toplistTl = tl
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
