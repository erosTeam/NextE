import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { ThemeConstants } from '../theme/ThemeConstants'
import { PullRefresh, PullRefreshController } from './PullRefresh'
import {
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  LayoutSafeAreaBridge,
} from '../state/LayoutSafeAreaState'
import { connectListMode, ListModeState } from '../state/ListModeState'
import { ListModeSettings } from '../settings/ListModeSettings'
import { galleryWaterfallColumnCount, clampColumnWidth } from '../utils/GalleryColumns'
import { LoadingFooter } from './LoadingFooter'
import { isUserScrollSource } from '../utils/ScrollUserInput'

const WATER_FLOW_CACHE_ROWS: number = 2
const WATER_FLOW_MAX_CACHE_ITEMS: number = 16

/**
 * WaterFlow sibling of PullRefreshGridScaffold for gallery cards: same refresh, paging, safe-area,
 * and responsive column model, but native masonry placement for variable-height cover-first cards.
 * The top reserve is real scroll content so HDS title-bar auto-hide sees the first scroll gesture;
 * the bottom reserve uses WaterFlow's native footer instead of a non-content end offset.
 */
@ComponentV2
export struct PullRefreshWaterFlowScaffold {
  @BuilderParam content: () => void;
  layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Param scroller: Scroller = new Scroller();
  @Param minColumnWidth: number = 0;
  // When set to a ListMode.GRID/WATERFALL/COVER_WALL key, two-finger pinch adjusts that mode's stored
  // column width (and the scaffold renders that override). Empty = pinch disabled (e.g. thumbnails grid).
  @Param pinchModeKey: string = '';
  listMode: ListModeState = connectListMode();
  // Pinch = ONE proportional notch per gesture (commit once). Stores the raw scaled width — never snapped
  // to a column boundary, so it adapts across screen sizes. pinchStartCols only gates the toast.
  private pinchStartW: number = 0;
  private pinchStartCols: number = 0;
  private pinchCommitted: boolean = false;
  @Local measuredWidth: number = 0;
  @Param gap: number = ThemeConstants.SPACE_SM;
  @Param horizontalPadding: number = ThemeConstants.SPACE_MD;
  @Param bottomPadding: number = ThemeConstants.SPACE_XL;
  @Param topPadding: number = 0;
  @Param itemCount: number = 0;
  @Param nearEndThreshold: number = 0;
  @Param showFooter: boolean = false;
  @Param footerIsLoading: boolean = false;
  @Param footerHasMore: boolean = true;
  @Param footerIsError: boolean = false;
  // Defaults to ArkUI's API 18+ vertical behavior. Wide gallery detail passes an explicit owner gate.
  @Param backToTop: boolean = true;
  @Param controller: PullRefreshController = new PullRefreshController();
  @Local scrollEnabled: boolean = true;
  @Event onRefresh?: () => Promise<void>;
  @Event onBottomRefresh?: () => Promise<void>;
  @Event canStartBottomRefresh?: () => boolean;
  @Event onReachEnd?: () => void;
  @Event onNearEnd?: () => void;
  @Event onFooterRetry?: () => void;
  @Event onScrollIndex?: (start: number, end: number) => void;
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Event onUserScroll?: () => void;

  build() {
    PullRefresh({
      scroller: this.scroller,
      controller: this.controller,
      indicatorTop:
        this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT / 2 + this.topPadding,
      bottomIndicatorBottom: this.layout.bottomAvoidHeight + this.bottomPadding,
      onRefresh: async () => {
        if (this.onRefresh) {
          await this.onRefresh()
        }
      },
      onBottomRefresh: async () => {
        if (this.onBottomRefresh) {
          await this.onBottomRefresh()
        }
      },
      canStartBottomRefresh: () => {
        if (this.canStartBottomRefresh) {
          return this.canStartBottomRefresh()
        }
        return false
      },
      onScrollEnableChange: (enabled: boolean) => {
        this.scrollEnabled = enabled
      },
    }) {
      WaterFlow({
        scroller: this.scroller,
        sections: this.waterFlowSections(),
        layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW,
      }) {
        this.TopSpacer()
        this.content()
        this.BottomSpacer()
      }
      .columnsGap(this.gap)
      .rowsGap(this.gap)
      // Keep roughly two upcoming rows ready without forcing ArkUI's maximum cache on narrow screens.
      // Component reuse and cover prefetching remain independent layers of the browsing pipeline.
      .cachedCount(this.cachedItemCount(), false)
      .enableScrollInteraction(this.scrollEnabled)
      .backToTop(this.backToTop)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
      })
      // PullRefresh owns the edge drag offset; native spring would add a second movement layer.
      .edgeEffect(EdgeEffect.None)
      .clip(false)
      // Two-finger pinch continuously scales the column width (fingers:2 leaves single-finger scroll
      // untouched). Spread → bigger cards; pinch → smaller. The exact width is stored on release.
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.pinchStartW = this.effectiveMinWidth()
            this.pinchStartCols = this.currentColumns()
            this.pinchCommitted = false
          })
          .onActionUpdate((event: GestureEvent) => {
            this.applyPinch(event.scale)
          })
          .onActionEnd(() => {
            if (this.pinchModeKey.length > 0) {
              ListModeSettings.setColumnWidth(
                this.ctx(),
                this.pinchModeKey,
                this.effectiveMinWidth(),
              )
            }
            this.pinchCommitted = false
          }),
      )
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const w: number = this.parseAreaWidth(newValue)
        this.measuredWidth = w
        // Warm the shared cache so the next remount can pick the correct column count on its first frame.
        if (w > 0) {
          LayoutSafeAreaBridge.publishGalleryContentWidth(w)
        }
      })
      .onReachEnd(() => {
        if (this.onReachEnd) {
          this.onReachEnd()
        }
      })
      .onDidScroll((_scrollOffset: number, scrollState: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, scrollState)
        }
      })
      .onWillScroll((_scrollOffset: number, _scrollState: ScrollState, source: ScrollSource) => {
        if (this.onUserScroll && isUserScrollSource(source)) {
          this.onUserScroll()
        }
      })
      .onScrollIndex((start: number, end: number) => {
        const adjustedStart: number = this.galleryIndex(start)
        const adjustedEnd: number = this.galleryIndex(end)
        if (this.onScrollIndex) {
          this.onScrollIndex(adjustedStart, adjustedEnd)
        }
        if (this.onDidScroll) {
          this.onDidScroll(this.scroller.currentOffset().yOffset, ScrollState.Scroll)
        }
        this.maybeLoadNearEnd(adjustedEnd)
      })
    }
  }

  private waterFlowSections(): WaterFlowSections {
    const sections: WaterFlowSections = new WaterFlowSections()
    const opts: SectionOptions[] = []
    opts.push({
      itemsCount: 1,
      crossCount: 1,
      rowsGap: 0,
      columnsGap: 0,
    })
    // Avoid a zero-item content section; the empty state only needs the top and bottom spacers.
    if (this.itemCount > 0) {
      opts.push({
        itemsCount: this.itemCount,
        crossCount: this.contentColumnCount(),
        rowsGap: this.gap,
        columnsGap: this.gap,
      })
    }
    opts.push({
      itemsCount: 1,
      crossCount: 1,
      rowsGap: 0,
      columnsGap: 0,
    })
    sections.splice(0, 0, opts)
    return sections
  }

  private contentColumnCount(): number {
    return galleryWaterfallColumnCount(
      this.effectiveMeasuredWidth(),
      this.effectiveMinWidth(),
      this.gap,
      this.horizontalPadding,
    )
  }

  private cachedItemCount(): number {
    return Math.min(
      WATER_FLOW_MAX_CACHE_ITEMS,
      Math.max(1, this.contentColumnCount() * WATER_FLOW_CACHE_ROWS),
    )
  }

  // Width to derive the column count from on the FIRST frame, before onAreaChange has measured this
  // component. Prefer the real measurement; before that the shared cached gallery width (precise, kept
  // fresh / invalidated on fold by EntryAbility); last resort the live screen width — anything but the
  // fixed 2-column default the pure helper falls back to when handed 0.
  private effectiveMeasuredWidth(): number {
    if (this.measuredWidth > 0) {
      return this.measuredWidth
    }
    if (this.layout.galleryContentWidth > 0) {
      return this.layout.galleryContentWidth
    }
    return this.screenWidthFallback()
  }

  private screenWidthFallback(): number {
    try {
      return this.getUIContext().px2vp(display.getDefaultDisplaySync().width)
    } catch (_error) {
      return 0
    }
  }

  // Pinch/slider override (when pinchModeKey set) wins over the base minColumnWidth param.
  private effectiveMinWidth(): number {
    if (this.pinchModeKey.length > 0) {
      const override: number = this.listMode.overrideWidthFor(this.pinchModeKey)
      if (override > 0) {
        return override
      }
    }
    return this.minColumnWidth > 0 ? this.minColumnWidth : ThemeConstants.GALLERY_WATERFALL_MIN_W
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private currentColumns(): number {
    return galleryWaterfallColumnCount(
      this.measuredWidth,
      this.effectiveMinWidth(),
      this.gap,
      this.horizontalPadding,
    )
  }

  // Pinch IS the slider for minColumnWidth: width tracks the gesture continuously. The only constraint is
  // that one gesture may cross at most one column boundary — the instant the column count changes we lock
  // (pinchCommitted) so a single pinch can't skip from 3 to 5. The stored width is the organic value where
  // the gesture landed, never a snapped/computed boundary. Column count is read only to lock + toast.
  private applyPinch(scale: number): void {
    if (this.pinchModeKey.length === 0 || this.pinchCommitted || this.measuredWidth <= 0) {
      return
    }
    const next: number = clampColumnWidth(this.pinchStartW * scale)
    this.listMode.setWidthFor(this.pinchModeKey, next)
    const cols: number = galleryWaterfallColumnCount(
      this.measuredWidth,
      next,
      this.gap,
      this.horizontalPadding,
    )
    if (cols !== this.pinchStartCols) {
      this.pinchCommitted = true
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message:
            cols > this.pinchStartCols
              ? $r('app.string.column_density_more')
              : $r('app.string.column_density_fewer'),
          duration: 800,
        })
    }
  }

  @Builder
  private TopSpacer() {
    FlowItem() {
      Column() {
        Blank().height(this.topSpacerHeight())
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private BottomSpacer() {
    FlowItem() {
      Column() {
        if (this.showFooter) {
          LoadingFooter({
            isLoading: this.footerIsLoading,
            hasMore: this.footerHasMore,
            isError: this.footerIsError,
            onRetry: () => {
              if (this.onFooterRetry) {
                this.onFooterRetry()
              }
            },
          })
        }
        Blank().height(this.bottomSpacerHeight())
      }.width('100%')
    }.width('100%')
    .onAppear(() => {
      this.maybeLoadOnTailAppear()
    })
  }

  private parseAreaWidth(value: Area): number {
    const parsed: number = Number.parseFloat(`${value.width}`)
    return parsed > 0 ? parsed : 0
  }

  private topSpacerHeight(): number {
    return this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + this.topPadding
  }

  private bottomSpacerHeight(): number {
    return this.layout.bottomAvoidHeight + this.bottomPadding
  }

  private galleryIndex(rawIndex: number): number {
    const index: number = rawIndex - 1
    if (index < 0) {
      return 0
    }
    if (this.itemCount > 0 && index >= this.itemCount) {
      return this.itemCount - 1
    }
    return index
  }

  private maybeLoadNearEnd(end: number): void {
    if (this.itemCount <= 0 || this.nearEndThreshold <= 0) {
      return
    }
    if (end < this.itemCount - 1 - this.nearEndThreshold) {
      return
    }
    if (this.canStartBottomRefresh && !this.canStartBottomRefresh()) {
      return
    }
    if (this.onNearEnd) {
      this.onNearEnd()
      return
    }
    if (this.onReachEnd) {
      this.onReachEnd()
    }
  }

  private maybeLoadOnTailAppear(): void {
    if (this.itemCount <= 0) {
      return
    }
    if (this.canStartBottomRefresh && !this.canStartBottomRefresh()) {
      return
    }
    if (this.onNearEnd) {
      this.onNearEnd()
      return
    }
    if (this.onReachEnd) {
      this.onReachEnd()
    }
  }
}
