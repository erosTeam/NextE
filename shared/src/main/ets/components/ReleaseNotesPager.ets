import { AppRelease } from '../model/AppRelease'
import { TabItem } from '../model/TabItem'
import { ThemeConstants } from '../theme/ThemeConstants'
import { MarkdownContent } from './MarkdownContent'

const RELEASE_NOTES_DIALOG_CONTENT_MAX_HEIGHT: string = '60%'
const RELEASE_NOTES_RIBBON_HEIGHT: number = 72
const RELEASE_NOTES_RIBBON_LABEL_HEIGHT: number = 40
const RELEASE_NOTES_RIBBON_TAB_GAP: number = ThemeConstants.SPACE_XS
const RELEASE_NOTES_RIBBON_LABEL_HORIZONTAL_PADDING: number = ThemeConstants.SPACE_LG
const RELEASE_NOTES_RIBBON_FOCUS_RAIL_Y: number = 40
const RELEASE_NOTES_RIBBON_FOCUS_RAIL_HEIGHT: number = 14
const RELEASE_NOTES_RIBBON_FOCUS_RAIL_WIDTH_RATIO: number = 0.52
const RELEASE_NOTES_RIBBON_LABEL_REGULAR_WEIGHT: number = 400
const RELEASE_NOTES_RIBBON_LABEL_BOLD_WEIGHT: number = 700
const RELEASE_NOTES_RIBBON_LABEL_MIN_OPACITY: number = 0.68

/**
 * Release-history-only version track. This keeps the dialog's natural-width labels, edge centring and
 * continuous rail in its own boundary; it intentionally does not alter the established application
 * SubTabBar used by other screens.
 */
@ComponentV2
struct ReleaseNotesVersionTrack {
  @Require @Param tabs: TabItem[]
  @Param visualIndex: number = 0
  @Param selectedIndex: number = 0
  @Require @Param focusRailImage: Resource
  @Event onSelect: (index: number) => void = (_index: number) => {}
  @Local tabWidths: number[] = []
  @Local tabLefts: number[] = []
  @Local viewportWidth: number = 0
  @Local scrollOffsetX: number = 0
  private scroller: Scroller = new Scroller()
  private containerGlobalLeft: number = 0
  private pendingCenterIndex: number = -1
  private pendingCenterSmooth: boolean = false

  aboutToAppear(): void {
    this.centerSelectedTab(false)
  }

  @Monitor('tabs')
  onTabsChange(): void {
    this.tabWidths = []
    this.tabLefts = []
    this.scrollOffsetX = 0
    this.pendingCenterIndex = this.centerIndex()
    this.pendingCenterSmooth = false
  }

  @Monitor('selectedIndex')
  onSelectedIndexChange(): void {
    this.centerSelectedTab(true)
  }

  private numberFromLength(value: Length | undefined): number {
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'string') {
      const parsed: number = Number.parseFloat(value)
      return Number.isNaN(parsed) ? 0 : parsed
    }
    return 0
  }

  private tabWidth(index: number): number {
    return index >= 0 && index < this.tabWidths.length ? this.tabWidths[index] : 0
  }

  // The endpoint padding is derived from the actual endpoint labels. It is not a set of fixed-width cells:
  // it solely makes a real first/last version capable of resting at the viewport centre.
  private leadingPadding(): number {
    const first: number = this.tabWidth(0)
    return this.viewportWidth > 0 && first > 0 ? Math.max(0, this.viewportWidth / 2 - first / 2) : 0
  }

  private trailingPadding(): number {
    const last: number = this.tabWidth(this.tabs.length - 1)
    return this.viewportWidth > 0 && last > 0 ? Math.max(0, this.viewportWidth / 2 - last / 2) : 0
  }

  private leadingSpacerWidth(): number {
    return Math.max(0, this.leadingPadding() - RELEASE_NOTES_RIBBON_TAB_GAP)
  }

  private trailingSpacerWidth(): number {
    return Math.max(0, this.trailingPadding() - RELEASE_NOTES_RIBBON_TAB_GAP)
  }

  private tabLeft(index: number): number {
    if (index >= 0 && index < this.tabLefts.length && this.tabLefts[index] >= 0) {
      return this.tabLefts[index]
    }
    let left: number = this.leadingPadding()
    for (let itemIndex: number = 0; itemIndex < index; itemIndex++) {
      left += this.tabWidth(itemIndex) + RELEASE_NOTES_RIBBON_TAB_GAP
    }
    return left
  }

  private tabCenter(index: number): number {
    return this.tabLeft(index) + this.tabWidth(index) / 2
  }

  private visualSelectedIndex(): number {
    if (this.tabs.length <= 0) {
      return 0
    }
    return Math.max(0, Math.min(this.tabs.length - 1, Math.round(this.visualIndex)))
  }

  // A single fractional emphasis drives the drag-time visual state. It deliberately does not use
  // round(visualIndex): the page gesture publishes a float while the finger is down, and labels must
  // grow, shrink, and change variable font weight continuously through that interval.
  private labelEmphasis(index: number): number {
    const distance: number = Math.abs(this.visualIndex - index)
    return Math.max(0, 1 - Math.min(1, distance))
  }

  private labelScale(index: number): number {
    const compactScale: number = ThemeConstants.FONT_SIZE_BODY / ThemeConstants.FONT_SIZE_H2
    return compactScale + (1 - compactScale) * this.labelEmphasis(index)
  }

  private labelWeight(index: number): number {
    const range: number = RELEASE_NOTES_RIBBON_LABEL_BOLD_WEIGHT - RELEASE_NOTES_RIBBON_LABEL_REGULAR_WEIGHT
    return Math.round(RELEASE_NOTES_RIBBON_LABEL_REGULAR_WEIGHT + range * this.labelEmphasis(index))
  }

  private labelOpacity(index: number): number {
    return RELEASE_NOTES_RIBBON_LABEL_MIN_OPACITY +
      (1 - RELEASE_NOTES_RIBBON_LABEL_MIN_OPACITY) * this.labelEmphasis(index)
  }

  private centerIndex(): number {
    if (this.tabs.length <= 0) {
      return 0
    }
    const raw: number = this.selectedIndex >= 0 ? this.selectedIndex : this.visualSelectedIndex()
    return Math.max(0, Math.min(this.tabs.length - 1, raw))
  }

  private currentScrollOffsetX(): number {
    const offset: number = this.scroller.currentOffset().xOffset
    return offset > 0 && !Number.isNaN(offset) ? offset : 0
  }

  private updateScrollOffset(): void {
    const next: number = this.currentScrollOffsetX()
    if (this.scrollOffsetX !== next) {
      this.scrollOffsetX = next
    }
  }

  private centerSelectedTab(smooth: boolean): void {
    const target: number = this.centerIndex()
    if (this.viewportWidth <= 0) {
      this.pendingCenterIndex = target
      this.pendingCenterSmooth = smooth
      return
    }
    this.pendingCenterIndex = -1
    // List padding in ArkUI insets the viewport itself. Keep the viewport full-width and represent the
    // endpoint centring space as actual first/last list items; labels therefore remain neighbours while
    // native scrolling and virtualization stay identical to the shared SubTabBar path.
    this.scroller.scrollToIndex(target + 1, smooth, ScrollAlign.CENTER)
    if (!smooth) {
      this.updateScrollOffset()
    }
  }

  private setTabWidth(index: number, width: number): boolean {
    if (this.tabWidth(index) === width) {
      return false
    }
    const next: number[] = this.tabWidths.slice()
    while (next.length <= index) {
      next.push(0)
    }
    next[index] = width
    this.tabWidths = next
    return true
  }

  private updateTabLayout(index: number, area: Area): void {
    const width: number = this.numberFromLength(area.width)
    if (width <= 0) {
      return
    }
    const widthChanged: boolean = this.setTabWidth(index, width)
    const nextLefts: number[] = this.tabLefts.slice()
    while (nextLefts.length <= index) {
      nextLefts.push(-1)
    }
    const left: number = this.numberFromLength(area.globalPosition?.x) - this.containerGlobalLeft + this.currentScrollOffsetX()
    if (nextLefts[index] !== left) {
      nextLefts[index] = left
      this.tabLefts = nextLefts
    }
    if (this.pendingCenterIndex >= 0) {
      this.centerSelectedTab(this.pendingCenterSmooth)
    } else if (widthChanged && (index === 0 || index === this.tabs.length - 1)) {
      // Once a virtualized endpoint becomes measurable, its padding becomes exact; centre once more
      // without animation so the endpoint and the fixed rail share the same native List geometry.
      this.centerSelectedTab(false)
    }
  }

  private updateViewport(area: Area): void {
    const width: number = this.numberFromLength(area.width)
    if (width <= 0) {
      return
    }
    this.viewportWidth = width
    this.containerGlobalLeft = this.numberFromLength(area.globalPosition?.x)
    this.centerSelectedTab(false)
  }

  private railWidth(): number {
    return this.viewportWidth > 0 ? this.viewportWidth * RELEASE_NOTES_RIBBON_FOCUS_RAIL_WIDTH_RATIO : 0
  }

  private railLeft(): number {
    if (this.tabs.length <= 0) {
      return 0
    }
    const visual: number = Math.max(0, Math.min(this.tabs.length - 1, this.visualIndex))
    const from: number = Math.floor(visual)
    const to: number = Math.min(from + 1, this.tabs.length - 1)
    const fraction: number = visual - from
    const center: number = this.tabCenter(from) + (this.tabCenter(to) - this.tabCenter(from)) * fraction
    return center - this.scrollOffsetX - this.railWidth() / 2
  }

  @Builder
  private VersionLabel(tab: TabItem, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      // Reserve the bold footprint so changing emphasis never changes the measured tab geometry mid-drag.
      Text(tab.label)
        .fontSize(ThemeConstants.FONT_SIZE_H2)
        .fontWeight(FontWeight.Bold, { enableVariableFontWeight: true })
        .opacity(0)
        .maxLines(1)
      // Keep exactly one visible glyph layer. Its opacity, scale and variable font weight all derive
      // from the same fractional gesture progress, avoiding a midpoint colour snap or layer-composite
      // ambiguity while retaining automatic light/dark adaptation from the system primary token.
      Text(tab.label)
        .fontSize(ThemeConstants.FONT_SIZE_H2)
        .fontWeight(
          this.labelWeight(index),
          { enableVariableFontWeight: true },
        )
        .fontColor(ThemeConstants.TEXT_PRIMARY)
        .opacity(this.labelOpacity(index))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .scale({
          x: this.labelScale(index),
          y: this.labelScale(index),
        })
    }
    .padding({
      left: RELEASE_NOTES_RIBBON_LABEL_HORIZONTAL_PADDING,
      right: RELEASE_NOTES_RIBBON_LABEL_HORIZONTAL_PADDING,
    })
    .height(RELEASE_NOTES_RIBBON_LABEL_HEIGHT)
    .onClick(() => {
      this.onSelect(index)
    })
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.updateTabLayout(index, area)
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      List({ space: RELEASE_NOTES_RIBBON_TAB_GAP, scroller: this.scroller }) {
        ListItem() {
          Row()
            .width(this.leadingSpacerWidth())
            .height(RELEASE_NOTES_RIBBON_LABEL_HEIGHT)
        }
        ForEach(
          this.tabs,
          (tab: TabItem, index: number) => {
            ListItem() {
              this.VersionLabel(tab, index)
            }
          },
          (tab: TabItem, index: number) => `${index}_${tab.key}`,
        )
        ListItem() {
          Row()
            .width(this.trailingSpacerWidth())
            .height(RELEASE_NOTES_RIBBON_LABEL_HEIGHT)
        }
      }
      .listDirection(Axis.Horizontal)
      .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
        this.updateScrollOffset()
      })
      .onScrollIndex((_start: number, _end: number) => {
        this.updateScrollOffset()
      })
      .scrollBar(BarState.Off)
      .width('100%')
      .height(RELEASE_NOTES_RIBBON_LABEL_HEIGHT)
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.updateViewport(area)
      })
      if (this.railWidth() > 0) {
        Image(this.focusRailImage)
          .width(this.railWidth())
          .height(RELEASE_NOTES_RIBBON_FOCUS_RAIL_HEIGHT)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.High)
          .position({ x: this.railLeft(), y: RELEASE_NOTES_RIBBON_FOCUS_RAIL_Y })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(RELEASE_NOTES_RIBBON_HEIGHT)
  }
}

/**
 * Reusable horizontal browser for a bounded release-history collection.
 *
 * Its release-only track is a separately reusable unit, so the log dialog can keep its natural-width
 * version labels and continuous rail without changing the established application sub-tab component.
 */
@ComponentV2
export struct ReleaseNotesPager {
  @Param releases: AppRelease[] = []
  @Param initialIndex: number = 0
  @Param emptyText: string = ''
  @Require @Param focusRailImage: Resource
  @Event onReleaseChanged: (index: number) => void = (_index: number) => {}
  @Event onLinkClick: (url: string) => void = (_url: string) => {}
  @Local activeIndex: number = 0
  @Local visualIndex: number = 0
  @Local displayTabs: TabItem[] = []
  private controller: SwiperController = new SwiperController()
  private swiperWidth: number = 0
  private appliedReleaseSignature: string = ''

  aboutToAppear(): void {
    this.syncReleaseInput(false)
  }

  @Monitor('releases')
  onReleasesChange(): void {
    this.syncReleaseInput(false)
  }

  @Monitor('initialIndex')
  onInitialIndexChange(): void {
    this.syncReleaseInput(true)
  }

  private clampedIndex(value: number): number {
    if (this.releases.length <= 0) {
      return 0
    }
    return Math.max(0, Math.min(this.releases.length - 1, value))
  }

  // GitHub's cache is newest-first. Keep the visible sequence oldest-first: moving right from the
  // current release reaches an older release, and source-index translation stays at this boundary only.
  private displayIndexForSourceIndex(sourceIndex: number): number {
    return this.clampedIndex(this.releases.length - 1 - sourceIndex)
  }

  private sourceIndexForDisplayIndex(displayIndex: number): number {
    return this.clampedIndex(this.releases.length - 1 - displayIndex)
  }

  private releaseAtDisplayIndex(displayIndex: number): AppRelease {
    return this.releases[this.sourceIndexForDisplayIndex(displayIndex)]
  }

  private clampedVisualIndex(value: number): number {
    if (this.releases.length <= 0 || !Number.isFinite(value)) {
      return 0
    }
    return Math.max(0, Math.min(this.releases.length - 1, value))
  }

  private releaseSignature(): string {
    let signature: string = `${this.releases.length}`
    for (let i: number = 0; i < this.releases.length; i++) {
      signature += `:${this.releases[i].tagName}`
    }
    return signature
  }

  private makeDisplayTabs(): TabItem[] {
    const tabs: TabItem[] = []
    for (let index: number = 0; index < this.releases.length; index++) {
      const release: AppRelease = this.releaseAtDisplayIndex(index)
      tabs.push(new TabItem(release.tagName, release.tagName))
    }
    return tabs
  }

  private syncReleaseInput(smooth: boolean): void {
    const signature: string = this.releaseSignature()
    const target: number = this.displayIndexForSourceIndex(this.initialIndex)
    const releasesChanged: boolean = signature !== this.appliedReleaseSignature
    const indexChanged: boolean = target !== this.activeIndex
    if (!releasesChanged && !indexChanged) {
      return
    }
    if (releasesChanged) {
      this.displayTabs = this.makeDisplayTabs()
    }
    this.appliedReleaseSignature = signature
    this.activeIndex = target
    this.visualIndex = target
    if (indexChanged && this.releases.length > 0) {
      this.controller.changeIndex(target, smooth)
    }
  }

  @Builder
  private ReleaseRibbon() {
    ReleaseNotesVersionTrack({
      tabs: this.displayTabs,
      visualIndex: this.visualIndex,
      selectedIndex: this.activeIndex,
      focusRailImage: this.focusRailImage,
      onSelect: (index: number) => {
        if (index >= 0 && index < this.releases.length) {
          this.controller.changeIndex(index, true)
        }
      },
    })
      .width('100%')
  }

  // RetainedSubtabHost's visual-index rule is reused here verbatim: this float is the only gesture-time
  // coordinate shared by the page Swiper and this release-track rail.
  private visualIndexFromOffset(index: number, extraInfo: SwiperAnimationEvent): number {
    if (this.swiperWidth <= 0) {
      return this.clampedVisualIndex(index)
    }
    return this.clampedVisualIndex(index + -extraInfo.currentOffset / this.swiperWidth)
  }

  @Builder
  private ReleasePage(release: AppRelease) {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {
          MarkdownContent({
            markdown: release.body.length > 0 ? release.body : this.emptyText,
            onLinkClick: (url: string) => {
              this.onLinkClick(url)
            },
          })
            .width('100%')
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .nestedScroll({
        scrollForward: NestedScrollMode.PARALLEL,
        scrollBackward: NestedScrollMode.PARALLEL,
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    if (this.releases.length === 0) {
      Text(this.emptyText)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
    } else {
      Column({ space: ThemeConstants.SPACE_SM }) {
        this.ReleaseRibbon()
        Swiper(this.controller) {
          ForEach(
            this.releases,
            (_release: AppRelease, index: number) => {
              this.ReleasePage(this.releaseAtDisplayIndex(index))
            },
            (_release: AppRelease, index: number) => this.releaseAtDisplayIndex(index).tagName,
          )
        }
        .index(this.activeIndex)
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .indicator(false)
        .loop(false)
        .cachedCount(1)
        .nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
        .duration(ThemeConstants.ANIM_DURATION)
        .curve(Curve.EaseOut)
        .onGestureSwipe((index: number, extraInfo: SwiperAnimationEvent) => {
          this.visualIndex = this.visualIndexFromOffset(index, extraInfo)
        })
        .onAnimationStart((index: number, targetIndex: number, extraInfo: SwiperAnimationEvent) => {
          this.visualIndex = this.visualIndexFromOffset(index, extraInfo)
          this.getUIContext().animateTo({ duration: ThemeConstants.ANIM_DURATION, curve: Curve.EaseOut }, () => {
            this.visualIndex = this.clampedVisualIndex(targetIndex)
          })
        })
        // `.index(this.activeIndex)` establishes the opening page. Do not use onChange to "correct" a
        // presumed startup event: when none is emitted, that callback would instead consume the first
        // real transition and reapply this stale activeIndex over the requested release page.
        .onAnimationEnd((index: number, _extraInfo: SwiperAnimationEvent) => {
          this.activeIndex = this.clampedIndex(index)
          this.visualIndex = this.activeIndex
          this.onReleaseChanged(this.sourceIndexForDisplayIndex(this.activeIndex))
        })
        .onAreaChange((_oldArea: Area, area: Area) => {
          const width: number = area.width as number
          if (width > 0) {
            this.swiperWidth = width
          }
        })
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxHeight: RELEASE_NOTES_DIALOG_CONTENT_MAX_HEIGHT })
    }
  }
}
