import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { fileIo as fs } from '@kit.CoreFileKit'
import {
  ThemeConstants,
  EhGalleryImage,
  ReaderParams,
  ImageResolveService,
  EhHttpClient,
  DiagnosticLogger,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  connectReadMode,
  ReadModeState,
  ReadMode,
  ReadColumnMode,
  ReadModeSettings,
  GalleryReadProgressSettings,
  connectNavStack,
  connectSiteMode,
  ShareUtil,
} from 'shared'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'

/**
 * Image reader (basic-complete): horizontal paged Swiper of full images, each a
 * self-resolving ReaderImagePage that supports pinch / double-tap zoom + pan. Chrome
 * (page counter) toggles via the Swiper's own onClick — gestures on a Swiper child don't
 * reliably receive plain taps, so single-tap is handled at the Swiper level and only the
 * multi-finger / double-tap zoom lives on the image. While zoomed, the image reports up so
 * the Swiper disables swipe (pan moves the image instead of turning the page). The VM loads
 * further preview pages as you approach the end, so the whole gallery is readable.
 */
@ComponentV2
export struct ReaderPage {
  @Local vm: ReaderViewModel = new ReaderViewModel();
  @Local params: ReaderParams = new ReaderParams();
  // eros_fe opens the reader with chrome HIDDEN (view_state.dart:165 showBar=false); a center tap
  // fades it in. Top bar (back/page-count/settings) + bottom bar (page-count/mode/slider) are native
  // flat-scrim bars, not the old hand-rolled floating glass card.
  @Local showChrome: boolean = false;
  @Local imageZoomed: boolean = false;
  // While the user drags the page slider, show the target page (1-based) instead of the live one.
  @Local sliderPreview: number = -1;
  // 1-based slider position; follows the live page on swipe and drives jump-to-page on drag.
  @Local sliderValue: number = 1;
  @Local readMode: ReadModeState = connectReadMode();
  // Reader viewport size (captured on layout) — divides the canvas into eros_fe's 3×3 tap regions
  // (left/right thirds + center-column top/bottom fifths).
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  // Safe-area insets (gesture bar / status bar) published by EntryAbility — the page counter
  // sits above the bottom inset so it never hides behind the home indicator.
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.vm.images.length > 0) {
          if (this.readMode.mode === ReadMode.VERTICAL) {
            this.VerticalReader()
          } else if (this.doublePageEnabled()) {
            this.DoublePageReader()
          } else {
            this.HorizontalReader()
          }
        } else if (this.vm.error.length > 0) {
          // No preview pages loaded at all (first batch failed): white error + retry on the black
          // reader canvas, not the themed PageErrorState (which would be unreadable here).
          Column({ space: ThemeConstants.SPACE_MD }) {
            Text(this.vm.error)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
            Button($r('app.string.common_retry'))
              .type(ButtonType.Capsule)
              .onClick(() => {
                this.vm.loadMore()
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(ThemeConstants.SPACE_XL)
        } else {
          ReaderLoadingOverlay({ label: $r('app.string.reader_loading_resolving') })
        }

        // Jump-to-page spinner while a far slider jump loads the intermediate preview pages.
        if (this.vm.jumping) {
          ReaderLoadingOverlay({ label: $r('app.string.reader_loading_resolving') })
        }

        // Chrome bars are always mounted (when there's content) and faded via opacity so they animate;
        // an `if` can't fade. They only cover the top/bottom strips, so the center tap-toggle band and
        // the tap-zone thirds stay tap-through (V2Next ImagePreviewPage idiom: overlay only the controls).
        if (this.vm.images.length > 0) {
          this.ReaderTopBar()
          this.ReaderBottomBar()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .onAreaChange((_o: Area, n: Area) => {
        this.viewWidth = n.width as number
        this.viewHeight = n.height as number
      })
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as ReaderParams
      if (p !== undefined && p.gid.length > 0) {
        this.params = p
        this.sliderValue = p.index + 1
        const requestedIndex: number = p.index
        this.vm.init(
          p.gid,
          p.token,
          p.fileCount,
          p.index,
          p.seedImages,
          p.seedLoadedPages,
          p.seedPerPage,
          p.seedPreviewPages,
          p.seedImagePageUrl,
        )
          .then(() => {
            const targetIndex: number =
              this.vm.images.length > 0 ? Math.min(requestedIndex, this.vm.images.length - 1) : 0
            this.vm.currentIndex = targetIndex
            this.sliderValue = targetIndex + 1
            if (this.readMode.mode === ReadMode.VERTICAL) {
              setTimeout(() => {
                this.listScroller.scrollToIndex(targetIndex)
              }, 50)
            }
          })
      }
      // Keep the screen awake while reading (eros_fe couples fullscreen + wakelock); window-scoped,
      // restored on aboutToDisappear. The app is already edge-to-edge fullscreen (EntryAbility), so the
      // reader doesn't re-enter fullscreen — the black canvas + faded chrome is the immersive surface.
      this.setReaderKeepScreenOn(true)
    })
  }

  // Window keep-screen-on toggle (no global system-bar churn — status bar auto-contrasts white over the
  // black canvas). Best-effort: a failure must not break the reader.
  private setReaderKeepScreenOn(active: boolean): void {
    window
      .getLastWindow(this.hostContext())
      .then((win: window.Window) => {
        win.setWindowKeepScreenOn(active).catch((_e: Error) => {})
      })
      .catch((_e: Error) => {})
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private currentImage(): EhGalleryImage | null {
    if (this.vm.currentIndex < 0 || this.vm.currentIndex >= this.vm.images.length) {
      return null
    }
    return this.vm.images[this.vm.currentIndex]
  }

  // Share the current reader image URL from the reader top bar (eros_fe ViewTopBar share). Prefer the
  // original/fullimg URL when the image page has exposed it; otherwise share the resolved full image.
  // If the current page is not resolved yet, resolve it through the same /s/ pipeline the reader uses.
  private shareCurrentImage(): void {
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null) {
      this.shareGallery()
      return
    }
    const title: string = `${this.params.title} ${this.vm.currentIndex + 1}`.trim()
    const alreadyResolvedUrl: string =
      image.originImageUrl.length > 0 ? image.originImageUrl : image.imageUrl
    if (alreadyResolvedUrl.length > 0) {
      ShareUtil.shareUrl(this.hostContext(), alreadyResolvedUrl, title)
      return
    }
    ImageResolveService.getInstance()
      .resolve(image)
      .then((imageUrl: string) => {
        const url: string = image.originImageUrl.length > 0 ? image.originImageUrl : imageUrl
        ShareUtil.shareUrl(this.hostContext(), url, title)
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('reader', 'share_image_resolve_failed', err.message)
        this.shareGallery()
      })
  }

  // Share the gallery's public URL as a fallback when the current image cannot be resolved.
  private shareGallery(): void {
    ShareUtil.shareGallery(
      this.hostContext(),
      this.params.gid,
      this.params.token,
      connectSiteMode().isEx,
      this.params.title,
    )
  }

  // Keep the slider thumb on the live page when the user swipes (not while they drag the slider),
  // and persist the reading position (eros_fe saveLastIndex: memory now, disk on a 3s debounce).
  @Monitor('vm.currentIndex')
  onPageChanged(): void {
    if (this.sliderPreview < 0) {
      this.sliderValue = this.vm.currentIndex + 1
    }
    if (this.params.gid.length > 0) {
      GalleryReadProgressSettings.setIndex(
        this.hostContext(),
        this.params.gid,
        this.vm.currentIndex,
      )
    }
  }

  // Force-persist on close so the last page survives an unfired debounce (eros_fe saveToStore).
  aboutToDisappear(): void {
    if (this.params.gid.length > 0) {
      GalleryReadProgressSettings.flush(this.hostContext())
    }
    // Always restore (fires on NavDestination pop, incl. swipe-back) so the wakelock never leaks.
    this.setReaderKeepScreenOn(false)
  }

  // Tap-zone navigation — eros_fe's 3×3 region grid (lrRatio 1/3, tbRatio 1/5, view_page.dart):
  //   • left third → tapLeft, right third → tapRight (direction-aware: see tapLeft/tapRight);
  //   • center column: top fifth → prev page, bottom fifth → next page, middle → chrome toggle.
  // Works in all three modes (the center fifths are page-index relative, never RTL-inverted). While an
  // image is zoomed, a tap must NOT turn the page (eros_fe defers the tap to the zoomed image) — toggle
  // chrome only. `x`/`y` are the tap position within the full-canvas Swiper/List.
  private onReaderTap(x: number, y: number): void {
    if (this.imageZoomed || this.viewWidth <= 0) {
      this.toggleChrome()
      return
    }
    const lr: number = this.viewWidth / 3
    if (x < lr) {
      this.tapLeft()
    } else if (x > this.viewWidth - lr) {
      this.tapRight()
    } else if (this.viewHeight > 0 && y < this.viewHeight / 5) {
      this.toPrev()
    } else if (this.viewHeight > 0 && y > (this.viewHeight * 4) / 5) {
      this.toNext()
    } else {
      this.toggleChrome()
    }
  }

  private doublePageEnabled(): boolean {
    return this.readMode.mode !== ReadMode.VERTICAL && this.readMode.columnMode !== ReadColumnMode.SINGLE
  }

  private pageStep(): number {
    return this.doublePageEnabled() ? 2 : 1
  }

  // Left-third tap: LTR / vertical → previous page; RTL (manga) → next (eros_fe tapLeft inverts on RTL).
  private tapLeft(): void {
    if (this.readMode.mode === ReadMode.RTL) {
      this.toNext()
    } else {
      this.toPrev()
    }
  }

  // Right-third tap: LTR / vertical → next page; RTL (manga) → previous.
  private tapRight(): void {
    if (this.readMode.mode === ReadMode.RTL) {
      this.toPrev()
    } else {
      this.toNext()
    }
  }

  private toPrev(): void {
    this.turnTo(this.vm.currentIndex - this.pageStep())
  }

  private toNext(): void {
    this.turnTo(this.vm.currentIndex + this.pageStep())
  }

  // Go to a (page-index) target. Vertical scrolls the list by one image; horizontal moves the Swiper.
  // A loaded in-range step reuses the swipe path (no jump spinner); a missing preview slot, even when
  // padded into images[], loads via jumpToPage so placeholders are not rendered as image pages.
  private turnTo(target: number): void {
    if (target < 0) {
      return
    }
    if (target >= this.vm.images.length || !this.vm.hasPreviewAt(target)) {
      this.jumpToPage(target)
      return
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      this.vm.currentIndex = target
      this.listScroller.scrollToIndex(target)
    } else {
      this.vm.onPageChange(target)
    }
  }

  // Jump after loading every page up to the target. Horizontal: set currentIndex so the Swiper's
  // reactive `.index()` moves there (a fixed `.index` would reset on rebuild). Vertical: scroll the
  // List to the index (onScrollIndex then updates currentIndex).
  private jumpToPage(index: number): void {
    this.vm.jumpTo(index).then((target: number) => {
      if (this.readMode.mode === ReadMode.VERTICAL) {
        this.vm.currentIndex = target
        this.listScroller.scrollToIndex(target)
      } else {
        this.vm.currentIndex = target
      }
    })
  }

  @Builder
  HorizontalReader() {
    Swiper() {
      ForEach(
        this.vm.images,
        (img: EhGalleryImage) => {
          ReaderImagePage({
            image: img,
            onZoomChange: (zoomed: boolean) => {
              this.imageZoomed = zoomed
            },
          })
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .index(this.vm.currentIndex)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .loop(false)
    .cachedCount(2)
    .indicator(false)
    .disableSwipe(this.imageZoomed)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      this.vm.onPageChange(i)
    })
    .onClick((e: ClickEvent) => {
      this.onReaderTap(e.x, e.y)
    })
  }

  private spreadIndexForImage(index: number): number {
    if (!this.doublePageEnabled() || index <= 0) {
      return 0
    }
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      return Math.floor((index + 1) / 2)
    }
    return Math.floor(index / 2)
  }

  private spreadStartIndex(spreadIndex: number): number {
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
    }
    return spreadIndex * 2
  }

  private spreadCount(): number {
    const total: number = this.vm.totalPages()
    if (!this.doublePageEnabled() || total <= 1) {
      return total
    }
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      return Math.round(total / 2) + ((total + 1) % 2)
    }
    return Math.round(total / 2)
  }

  private spreadStarts(): number[] {
    const out: number[] = []
    const count: number = this.spreadCount()
    for (let i: number = 0; i < count; i++) {
      out.push(this.spreadStartIndex(i))
    }
    return out
  }

  private hasSpreadImage(index: number): boolean {
    return index >= 0 && index < this.vm.images.length && this.vm.hasPreviewAt(index)
  }

  @Builder
  SpreadImage(index: number) {
    if (this.hasSpreadImage(index)) {
      ReaderImagePage({
        image: this.vm.images[index],
        onZoomChange: (zoomed: boolean) => {
          this.imageZoomed = zoomed
        },
      })
        .layoutWeight(1)
    } else {
      Blank()
        .layoutWeight(1)
    }
  }

  @Builder
  DoublePageReader() {
    Swiper() {
      ForEach(
        this.spreadStarts(),
        (start: number) => {
          Row({ space: ThemeConstants.SPACE_XS }) {
            this.SpreadImage(start)
            if (start + 1 < this.vm.totalPages()) {
              this.SpreadImage(start + 1)
            } else {
              Blank()
                .layoutWeight(1)
            }
          }
          .width('100%')
          .height('100%')
        },
        (start: number) => `${start}`,
      )
    }
    .index(this.spreadIndexForImage(this.vm.currentIndex))
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .loop(false)
    .cachedCount(2)
    .indicator(false)
    .disableSwipe(this.imageZoomed)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      this.vm.onPageChange(this.spreadStartIndex(i))
    })
    .onClick((e: ClickEvent) => {
      this.onReaderTap(e.x, e.y)
    })
  }

  @Builder
  VerticalReader() {
    List({ initialIndex: this.vm.currentIndex, scroller: this.listScroller }) {
      ForEach(
        this.vm.images,
        (img: EhGalleryImage) => {
          ListItem() {
            ReaderVerticalImage({ image: img })
          }
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .width('100%')
    .height('100%')
    .cachedCount(2)
    .scrollBar(BarState.Off)
    .onScrollIndex((start: number, end: number) => {
      this.vm.onVerticalScroll(start, end)
    })
    .onClick((e: ClickEvent) => {
      this.onReaderTap(e.x, e.y)
    })
  }

  private modeLabel(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private cycleMode(): void {
    let next: string = ReadMode.LTR
    if (this.readMode.mode === ReadMode.LTR) {
      next = ReadMode.RTL
    } else if (this.readMode.mode === ReadMode.RTL) {
      next = ReadMode.VERTICAL
    } else {
      next = ReadMode.LTR
    }
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, next)
  }

  private columnModeLabel(): Resource {
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.common_off')
    }
    if (this.readMode.columnMode === ReadColumnMode.ODD_LEFT) {
      return $r('app.string.read_double_page_a')
    }
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      return $r('app.string.read_double_page_b')
    }
    return $r('app.string.common_off')
  }

  private cycleColumnMode(): void {
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return
    }
    let next: string = ReadColumnMode.ODD_LEFT
    if (this.readMode.columnMode === ReadColumnMode.ODD_LEFT) {
      next = ReadColumnMode.EVEN_LEFT
    } else if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      next = ReadColumnMode.SINGLE
    }
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setColumnMode(ctx, next)
  }

  // Page counter '5 / 120'; while dragging the slider it previews the target page (sliderPreview),
  // matching the live render once the drag commits. Shared by the top + bottom bars.
  private pageCountText(): string {
    const shown: number = this.sliderPreview >= 0 ? this.sliderPreview : this.vm.currentIndex + 1
    return `${shown} / ${this.vm.totalPages()}`
  }

  // Center-tap chrome toggle with a fade (eros_fe 300ms fastOutSlowIn; V2Next animateTo idiom). Hooks
  // the SAME onReaderTap center path — no new gesture.
  private toggleChrome(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
      this.showChrome = !this.showChrome
    })
  }

  // Reader settings entry (eros_fe top-bar ellipsis → readSetting, view_widget.dart:996-1015).
  private openReaderSettings(): void {
    connectNavStack().stack.pushPathByName('ReaderSettings', null)
  }

  // Top chrome bar — eros_fe ViewTopBar (view_widget.dart:913-1047): back + center page-counter +
  // settings. Flat dark scrim (V2Next ImagePreviewPage flat-overlay idiom; no API-26 material on the
  // API-23 device). Anchored to the top strip only via .position so the center toggle band + the
  // tap-zone thirds stay tap-through; faded out (opacity 0 + HitTestMode.None) when chrome is hidden.
  @Builder
  ReaderTopBar() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        connectNavStack().stack.pop()
      })
      Text(this.pageCountText())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(Color.White)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.shareCurrentImage()
      })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.openReaderSettings()
      })
    }
    .width('100%')
    .height(this.layout.topAvoidHeight + 56)
    .padding({
      top: this.layout.topAvoidHeight,
      left: ThemeConstants.SPACE_SM,
      right: ThemeConstants.SPACE_SM,
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#CC000000')
    .position({ x: 0, y: 0 })
    .opacity(this.showChrome ? 1 : 0)
    .hitTestBehavior(this.showChrome ? HitTestMode.Default : HitTestMode.None)
  }

  // Bottom chrome bar — eros_fe ViewBottomBar (view_widget.dart:1051-1095): page indicator + page
  // slider, with the reading-direction pill as the one quick control. Bottom-anchored by the root
  // Stack (Alignment.Bottom); flat scrim replaces the old floating BACKGROUND_THICK glass card. The
  // Slider wiring (drag-preview + jumpToPage) is ported verbatim.
  @Builder
  ReaderBottomBar() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Row() {
        Text(this.pageCountText())
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(Color.White)
        Blank()
        // Reading-direction toggle: L→R → R→L → Vertical → L→R (eros_fe ViewMode), persisted.
        Text(this.modeLabel())
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(Color.White)
          .borderRadius(ThemeConstants.RADIUS_ROUND)
          .border({ width: 1, color: Color.White })
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            top: 2,
            bottom: 2,
          })
          .onClick(() => {
            this.cycleMode()
          })
        Text(this.columnModeLabel())
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(this.readMode.mode === ReadMode.VERTICAL ? $r('sys.color.font_tertiary') : Color.White)
          .borderRadius(ThemeConstants.RADIUS_ROUND)
          .border({
            width: 1,
            color: this.readMode.mode === ReadMode.VERTICAL ? $r('sys.color.font_tertiary') : Color.White,
          })
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            top: 2,
            bottom: 2,
          })
          .onClick(() => {
            this.cycleColumnMode()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Slider({
        value: this.sliderValue,
        min: 1,
        max: this.vm.totalPages() > 1 ? this.vm.totalPages() : 1,
        step: 1,
      })
        .width('100%')
        .blockColor(Color.White)
        .selectedColor(ThemeConstants.BRAND_PRIMARY)
        .trackColor(ThemeConstants.OVERLAY_SCRIM)
        .onChange((value: number, mode: SliderChangeMode) => {
          const page: number = Math.round(value)
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.sliderPreview = page
            this.sliderValue = page
          } else {
            this.sliderPreview = -1
            this.sliderValue = page
            this.jumpToPage(page - 1)
          }
        })
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
      top: ThemeConstants.SPACE_SM,
      bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_SM,
    })
    .backgroundColor('#CC000000')
    .opacity(this.showChrome ? 1 : 0)
    .hitTestBehavior(this.showChrome ? HitTestMode.Default : HitTestMode.None)
  }
}

const MAX_SCALE: number = 4
const DOUBLE_TAP_SCALE: number = 2.5
const IMAGE_AUTO_RETRY_LIMIT: number = 3
const READER_IMAGE_CACHE_DIR: string = 'reader-images'

/**
 * One reader page. Resolves its full image on appear, then renders it with pinch /
 * double-tap zoom and (when zoomed) pan. Reports zoom state up so the parent gates Swiper
 * swipe. Gestures are bound unconditionally (a conditional `.gesture()` is silently
 * dropped by ArkUI); the pan callback no-ops at 1x so it doesn't fight the page swipe.
 */
@ComponentV2
struct ReaderImagePage {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local imageProgress: number = -1;
  @Local failed: boolean = false;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;

  private baseZoom: number = 1;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private compW: number = 0;
  private compH: number = 0;
  private lastZoomed: boolean = false;
  private autoRetryCount: number = 0;
  private loadSerial: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) — re-resolves via /s/?nl= for a
  // different host, bypassing the cached URL.
  private async resolve(changeSource: boolean = false): Promise<void> {
    const serial: number = this.nextLoadSerial()
    try {
      const remoteUrl: string = !changeSource && this.image.imageUrl.length > 0
        ? this.image.imageUrl
        : await ImageResolveService.getInstance().resolve(this.image, changeSource)
      if (serial !== this.loadSerial) {
        return
      }
      await this.downloadImage(remoteUrl, serial)
      this.failed = false
    } catch (err) {
      DiagnosticLogger.warn('reader', 'resolve_failed', (err as Error).message)
      this.retrySourceAutomatically()
    }
  }

  // Retry on failure: re-source (换源) — clear the dead URL and re-resolve from a different host.
  private retrySource(): void {
    this.autoRetryCount = 0
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgress = -1
    this.failed = false
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgress = -1
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  private nextLoadSerial(): number {
    this.loadSerial++
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgress = -1
    this.failed = false
    return this.loadSerial
  }

  private async downloadImage(remoteUrl: string, serial: number): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const dir: string = `${context.cacheDir}/${READER_IMAGE_CACHE_DIR}`
    ReaderImageCache.ensureDir(dir)
    const filePath: string = `${dir}/${ReaderImageCache.fileName(this.image, remoteUrl)}`
    this.imageProgress = 0
    await EhHttpClient.getInstance().downloadBinaryToFileInStream(
      remoteUrl,
      filePath,
      (loaded: number, total: number) => {
        if (serial !== this.loadSerial) {
          return
        }
        if (total > 0) {
          this.imageProgress = Math.max(0, Math.min(1, loaded / total))
        } else if (loaded > 0) {
          this.imageProgress = 0.08
        }
      },
    )
    if (serial !== this.loadSerial) {
      return
    }
    this.imageProgress = 1
    this.imageLoaded = false
    this.imageUrl = `file://${filePath}`
  }

  private clampOffset(): void {
    const maxX: number = Math.max(0, (this.compW * (this.zoomScale - 1)) / 2)
    const maxY: number = Math.max(0, (this.compH * (this.zoomScale - 1)) / 2)
    this.offsetX = Math.min(maxX, Math.max(-maxX, this.offsetX))
    this.offsetY = Math.min(maxY, Math.max(-maxY, this.offsetY))
    this.baseOffsetX = this.offsetX
    this.baseOffsetY = this.offsetY
  }

  private resetZoom(): void {
    this.zoomScale = 1
    this.baseZoom = 1
    this.offsetX = 0
    this.offsetY = 0
    this.baseOffsetX = 0
    this.baseOffsetY = 0
  }

  private notifyZoom(): void {
    const zoomed: boolean = this.zoomScale > 1.01
    if (zoomed !== this.lastZoomed) {
      this.lastZoomed = zoomed
      this.onZoomChange(zoomed)
    }
  }

  private onDoubleTap(): void {
    if (this.zoomScale > 1.01) {
      this.resetZoom()
    } else {
      this.zoomScale = DOUBLE_TAP_SCALE
      this.baseZoom = DOUBLE_TAP_SCALE
    }
    this.notifyZoom()
  }

  build() {
    Stack() {
      // `failed` first: a resolve error OR an Image fetch error (dead one-shot token / 509) shows the
      // re-source retry even if a (broken) URL is set.
      if (this.failed) {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Text($r('app.string.image_load_failed'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(Color.White)
          Button($r('app.string.common_retry'))
            .onClick(() => {
              this.retrySource()
            })
        }
      } else if (this.imageUrl.length > 0) {
        Image(this.imageUrl)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .draggable(false)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.offsetX, y: this.offsetY })
          .onComplete((_e) => {
            this.autoRetryCount = 0
            this.imageLoaded = true
          })
          .onError(() => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          })
        if (!this.imageLoaded) {
          ReaderLoadingOverlay({ label: $r('app.string.reader_loading_image'), progress: this.imageProgress })
        }
      } else {
        ReaderLoadingOverlay({ label: $r('app.string.reader_loading_resolving') })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area) => {
      this.compW = n.width as number
      this.compH = n.height as number
    })
    // Pinch + double-tap zoom + VERTICAL-only pan. The pan is direction-restricted so it
    // never captures horizontal drags — those pass through to the ancestor Swiper for the
    // page turn. When zoomed, vertical drag pans the (tall) image top-to-bottom, which is
    // the common reading need; double-tap resets. (A conditional `.gesture(cond ? a : b)`
    // is silently dropped by ArkUI — the gesture set must be unconditional.)
    .gesture(
      GestureGroup(
        GestureMode.Parallel,
        PinchGesture()
          .onActionUpdate((e: GestureEvent) => {
            this.zoomScale = Math.min(MAX_SCALE, Math.max(1, this.baseZoom * e.scale))
            this.notifyZoom()
          })
          .onActionEnd(() => {
            this.baseZoom = this.zoomScale
            if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          }),
        TapGesture({ count: 2 }).onAction(() => {
          this.onDoubleTap()
        }),
        PanGesture({ direction: PanDirection.Vertical })
          .onActionUpdate((e: GestureEvent) => {
            if (this.zoomScale > 1.01) {
              this.offsetY = this.baseOffsetY + e.offsetY
              this.clampOffset()
            }
          })
          .onActionEnd(() => {
            this.baseOffsetY = this.offsetY
          }),
      ),
    )
  }
}

const DEFAULT_VERTICAL_RATIO: number = 0.7

/**
 * One page in the vertical (continuous) reader: a full-width image whose height follows the
 * loaded image's aspect ratio (captured in onComplete). No per-image zoom — vertical scroll is
 * the navigation; a min-height keeps the placeholder tappable while resolving.
 */
@ComponentV2
struct ReaderVerticalImage {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local imageProgress: number = -1;
  @Local failed: boolean = false;
  @Local ratio: number = DEFAULT_VERTICAL_RATIO;
  private autoRetryCount: number = 0;
  private loadSerial: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) via /s/?nl=, bypassing the cache.
  private async resolve(changeSource: boolean = false): Promise<void> {
    const serial: number = this.nextLoadSerial()
    try {
      const remoteUrl: string = !changeSource && this.image.imageUrl.length > 0
        ? this.image.imageUrl
        : await ImageResolveService.getInstance().resolve(this.image, changeSource)
      if (serial !== this.loadSerial) {
        return
      }
      await this.downloadImage(remoteUrl, serial)
      this.failed = false
    } catch (err) {
      DiagnosticLogger.warn('reader', 'resolve_failed', (err as Error).message)
      this.retrySourceAutomatically()
    }
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgress = -1
    this.failed = false
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgress = -1
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  private nextLoadSerial(): number {
    this.loadSerial++
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgress = -1
    this.failed = false
    return this.loadSerial
  }

  private async downloadImage(remoteUrl: string, serial: number): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const dir: string = `${context.cacheDir}/${READER_IMAGE_CACHE_DIR}`
    ReaderImageCache.ensureDir(dir)
    const filePath: string = `${dir}/${ReaderImageCache.fileName(this.image, remoteUrl)}`
    this.imageProgress = 0
    await EhHttpClient.getInstance().downloadBinaryToFileInStream(
      remoteUrl,
      filePath,
      (loaded: number, total: number) => {
        if (serial !== this.loadSerial) {
          return
        }
        if (total > 0) {
          this.imageProgress = Math.max(0, Math.min(1, loaded / total))
        } else if (loaded > 0) {
          this.imageProgress = 0.08
        }
      },
    )
    if (serial !== this.loadSerial) {
      return
    }
    this.imageProgress = 1
    this.imageLoaded = false
    this.imageUrl = `file://${filePath}`
  }

  build() {
    Stack() {
      // `failed` first so an Image fetch error (dead token / 509) shows the re-source retry.
      if (this.failed) {
        Button($r('app.string.common_retry')).onClick(() => {
          this.retrySource()
        })
      } else if (this.imageUrl.length > 0) {
        Image(this.imageUrl)
          .width('100%')
          .aspectRatio(this.ratio)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .onComplete((e) => {
            this.autoRetryCount = 0
            this.imageLoaded = true
            if (e !== undefined && e.width > 0 && e.height > 0) {
              this.ratio = e.width / e.height
            }
          })
          .onError(() => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          })
        if (!this.imageLoaded) {
          ReaderLoadingOverlay({ label: $r('app.string.reader_loading_image'), progress: this.imageProgress })
        }
      } else {
        ReaderLoadingOverlay({ label: $r('app.string.reader_loading_resolving'), compact: true })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 220 })
  }
}

@ComponentV2
struct ReaderLoadingOverlay {
  @Param label: Resource = $r('app.string.reader_loading_resolving');
  @Param compact: boolean = false;
  @Param progress: number = -1;

  build() {
    Column() {
      ReaderLoadingLine({ label: this.label, compact: this.compact, progress: this.progress })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
struct ReaderLoadingLine {
  @Param label: Resource = $r('app.string.reader_loading_resolving');
  @Param compact: boolean = false;
  @Param progress: number = -1;

  private lineWidth(): number {
    return this.compact ? 148 : 220
  }

  private activeWidth(): number {
    if (this.progress >= 0) {
      const width: number = this.lineWidth() * Math.max(0.04, Math.min(1, this.progress))
      return Math.max(8, width)
    }
    return this.compact ? 72 : 108
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Row() {
        Blank()
          .width(this.activeWidth())
          .height(4)
          .borderRadius(2)
          .backgroundColor(Color.White)
      }
      .width(this.lineWidth())
      .height(4)
      .borderRadius(2)
      .backgroundColor('#55FFFFFF')
      .clip(true)
      Text(this.label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .maxLines(1)
      if (this.progress >= 0) {
        Text(`${Math.round(Math.max(0, Math.min(1, this.progress)) * 100)}%`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeConstants.SPACE_MD)
  }
}

class ReaderImageCache {
  static ensureDir(dir: string): void {
    try {
      fs.mkdirSync(dir, true)
    } catch (err) {
      DiagnosticLogger.warn('reader', 'cache_mkdir_failed', (err as Error).message)
    }
  }

  static fileName(image: EhGalleryImage, url: string): string {
    const ext: string = ReaderImageCache.extension(url)
    const seed: string = `${image.page}_${image.imgkey}_${image.reloadKey}`
    return `${ReaderImageCache.safePart(seed)}${ext}`
  }

  private static extension(url: string): string {
    const lower: string = url.toLowerCase()
    const q: number = lower.indexOf('?')
    const clean: string = q >= 0 ? lower.substring(0, q) : lower
    if (clean.endsWith('.png')) {
      return '.png'
    }
    if (clean.endsWith('.webp')) {
      return '.webp'
    }
    if (clean.endsWith('.gif')) {
      return '.gif'
    }
    return '.jpg'
  }

  private static safePart(value: string): string {
    return value.replace(/[^a-zA-Z0-9._-]/g, '_')
  }
}
