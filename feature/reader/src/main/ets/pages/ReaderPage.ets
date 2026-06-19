import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { promptAction, window } from '@kit.ArkUI'
import { KeyCode } from '@kit.InputKit'
import inputConsumer from '@ohos.multimodalInput.inputConsumer'
import { Action, KeyEvent as InputConsumerKeyEvent } from '@ohos.multimodalInput.keyEvent'
import {
  ThemeConstants,
  EhGalleryImage,
  EhSpriteThumbnail,
  ReaderParams,
  ImageResolveService,
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
  ImageSaveUtil,
} from 'shared'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'

const READER_KEY_SURFACE_ID: string = 'reader_key_surface'

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
  @Local doubleTapSeq: number = 0;
  @Local doubleTapX: number = 0;
  @Local doubleTapY: number = 0;
  // While the user drags the page slider, show the target page (1-based) instead of the live one.
  @Local sliderPreview: number = -1;
  // 1-based slider position; follows the live page on swipe and drives jump-to-page on drag.
  @Local sliderValue: number = 1;
  @Local readMode: ReadModeState = connectReadMode();
  @Local autoReadActive: boolean = false;
  @Local showThumbStrip: boolean = false;
  // Reader viewport size (captured on layout) — divides the canvas into eros_fe's 3×3 tap regions
  // (left/right thirds + center-column top/bottom fifths).
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  private listScroller: Scroller = new Scroller();
  // Safe-area insets (gesture bar / status bar) published by EntryAbility — the page counter
  // sits above the bottom inset so it never hides behind the home indicator.
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private autoReadTimer: number = -1;
  private autoReadWaitingIndex: number = -1;
  private loadedPages: number[] = [];
  private volumeDownConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;
  private volumeUpConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;

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
          ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
        }

        // Jump-to-page spinner while a far slider jump loads the intermediate preview pages.
        if (this.vm.jumping) {
          ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
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
      .id(READER_KEY_SURFACE_ID)
      .focusable(true)
      .defaultFocus(true)
      .backgroundColor(Color.Black)
      .onAreaChange((_o: Area, n: Area) => {
        this.viewWidth = n.width as number
        this.viewHeight = n.height as number
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return this.handleKeyEvent(event)
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
            const loadedTarget: number =
              this.vm.images.length > 0 ? Math.min(requestedIndex, this.vm.images.length - 1) : 0
            const targetIndex: number = this.normalizedReaderIndex(loadedTarget)
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
      this.requestReaderKeyFocus()
      this.registerVolumeKeyConsumer()
    })
  }

  private requestReaderKeyFocus(): void {
    this.requestReaderKeyFocusAfter(0)
    this.requestReaderKeyFocusAfter(120)
    this.requestReaderKeyFocusAfter(360)
  }

  private requestReaderKeyFocusAfter(delayMs: number): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(READER_KEY_SURFACE_ID)
      } catch (err) {
        const message: string = err instanceof Error ? err.message : `${err}`
        DiagnosticLogger.warn('reader', 'key_focus_request_failed', message)
      }
    }, delayMs)
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (!this.readMode.volumeKeyTurn) {
      return false
    }
    if (
      event.keyCode !== KeyCode.KEYCODE_VOLUME_UP &&
      event.keyCode !== KeyCode.KEYCODE_VOLUME_DOWN
    ) {
      return false
    }
    if (event.type !== KeyType.Down) {
      return true
    }
    return this.turnByVolumeKeyCode(event.keyCode)
  }

  private turnByVolumeKeyCode(keyCode: number): boolean {
    if (!this.readMode.volumeKeyTurn) {
      return false
    }
    if (
      keyCode !== KeyCode.KEYCODE_VOLUME_UP &&
      keyCode !== KeyCode.KEYCODE_VOLUME_DOWN
    ) {
      return false
    }
    if (this.imageZoomed || this.vm.jumping || this.vm.images.length === 0) {
      return true
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      this.toNext()
    } else {
      this.toPrev()
    }
    return true
  }

  private registerVolumeKeyConsumer(): void {
    if (!this.readMode.volumeKeyTurn || this.volumeDownConsumer !== null || this.volumeUpConsumer !== null) {
      return
    }
    const downCallback: (event: InputConsumerKeyEvent) => void = (event: InputConsumerKeyEvent): void => {
      if (event.action === Action.DOWN) {
        this.turnByVolumeKeyCode(KeyCode.KEYCODE_VOLUME_DOWN)
      }
    }
    const upCallback: (event: InputConsumerKeyEvent) => void = (event: InputConsumerKeyEvent): void => {
      if (event.action === Action.DOWN) {
        this.turnByVolumeKeyCode(KeyCode.KEYCODE_VOLUME_UP)
      }
    }
    this.volumeDownConsumer = downCallback
    this.volumeUpConsumer = upCallback
    try {
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: Action.DOWN,
        isRepeat: false,
      }, downCallback)
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: Action.DOWN,
        isRepeat: false,
      }, upCallback)
    } catch (err) {
      const message: string = err instanceof Error ? err.message : `${err}`
      DiagnosticLogger.warn('reader', 'volume_key_consumer_register_failed', message)
      this.unregisterVolumeKeyConsumer()
    }
  }

  private unregisterVolumeKeyConsumer(): void {
    try {
      if (this.volumeDownConsumer !== null) {
        inputConsumer.off('keyPressed', this.volumeDownConsumer)
      }
      if (this.volumeUpConsumer !== null) {
        inputConsumer.off('keyPressed', this.volumeUpConsumer)
      }
    } catch (err) {
      const message: string = err instanceof Error ? err.message : `${err}`
      DiagnosticLogger.warn('reader', 'volume_key_consumer_unregister_failed', message)
    }
    this.volumeDownConsumer = null
    this.volumeUpConsumer = null
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

  private saveCurrentImage(): void {
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_no_image') })
      return
    }
    const title: string = `${this.params.gid}-${this.vm.currentIndex + 1}`.trim()
    const alreadyResolvedUrl: string =
      image.originImageUrl.length > 0 ? image.originImageUrl : image.imageUrl
    if (alreadyResolvedUrl.length > 0) {
      this.saveImageUrl(alreadyResolvedUrl, title)
      return
    }
    ImageResolveService.getInstance()
      .resolve(image)
      .then((imageUrl: string) => {
        const url: string = image.originImageUrl.length > 0 ? image.originImageUrl : imageUrl
        this.saveImageUrl(url, title)
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('reader', 'save_image_resolve_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_failed') })
      })
  }

  private saveImageUrl(url: string, title: string): void {
    ImageSaveUtil.saveNetworkImageToGallery(this.hostContext(), url, title)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_success') })
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('reader', 'save_image_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_failed') })
      })
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
    this.stopAutoRead()
    this.unregisterVolumeKeyConsumer()
    // Always restore (fires on NavDestination pop, incl. swipe-back) so the wakelock never leaks.
    this.setReaderKeepScreenOn(false)
  }

  private autoReadIntervalMs(): number {
    const seconds: number = this.readMode.autoPageSeconds > 0 ? this.readMode.autoPageSeconds : 3
    return seconds * 1000
  }

  private isPageImageLoaded(index: number): boolean {
    const page: number = index + 1
    for (let i: number = 0; i < this.loadedPages.length; i++) {
      if (this.loadedPages[i] === page) {
        return true
      }
    }
    return false
  }

  private isPageReadyForAutoRead(index: number): boolean {
    if (this.isPageImageLoaded(index)) {
      return true
    }
    return index >= 0 && index < this.vm.images.length && this.vm.images[index].imageUrl.length > 0
  }

  private markPageImageLoaded(page: number): void {
    if (page <= 0) {
      return
    }
    for (let i: number = 0; i < this.loadedPages.length; i++) {
      if (this.loadedPages[i] === page) {
        this.maybeResumeAutoRead(page - 1)
        return
      }
    }
    this.loadedPages.push(page)
    this.maybeResumeAutoRead(page - 1)
  }

  private nextAutoReadIndex(): number {
    if (this.doublePageEnabled()) {
      const currentSpread: number = this.spreadIndexForImage(this.vm.currentIndex)
      const targetSpread: number = currentSpread + 1
      if (targetSpread >= this.spreadCount()) {
        return -1
      }
      return this.spreadStartIndex(targetSpread)
    }
    return this.vm.currentIndex + 1
  }

  private toggleAutoRead(): void {
    if (this.autoReadActive) {
      this.stopAutoRead()
      return
    }
    this.autoReadActive = true
    this.autoReadWaitingIndex = -1
    this.startAutoReadTimer()
  }

  private startAutoReadTimer(): void {
    if (!this.autoReadActive) {
      return
    }
    this.clearAutoReadTimer()
    this.autoReadTimer = setInterval(() => {
      this.advanceAutoRead()
    }, this.autoReadIntervalMs())
  }

  private clearAutoReadTimer(): void {
    if (this.autoReadTimer >= 0) {
      clearInterval(this.autoReadTimer)
      this.autoReadTimer = -1
    }
  }

  private stopAutoRead(): void {
    this.clearAutoReadTimer()
    this.autoReadActive = false
    this.autoReadWaitingIndex = -1
  }

  private waitForAutoReadPage(index: number): void {
    this.autoReadWaitingIndex = index
    this.clearAutoReadTimer()
    this.vm.warmForAutoRead(index)
  }

  private maybeResumeAutoRead(index: number): void {
    if (!this.autoReadActive || this.autoReadTimer >= 0 || this.autoReadWaitingIndex < 0) {
      return
    }
    if (index === this.autoReadWaitingIndex || this.isPageReadyForAutoRead(this.autoReadWaitingIndex)) {
      this.autoReadWaitingIndex = -1
      this.startAutoReadTimer()
    }
  }

  private advanceAutoRead(): void {
    if (!this.autoReadActive || this.vm.jumping || this.imageZoomed) {
      return
    }
    const target: number = this.nextAutoReadIndex()
    if (target < 0 || target >= this.vm.totalPages()) {
      this.stopAutoRead()
      return
    }
    if (!this.vm.hasPreviewAt(target) || !this.isPageReadyForAutoRead(target)) {
      this.waitForAutoReadPage(target)
      return
    }
    this.turnTo(target)
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

  private onReaderDoubleTap(x: number, y: number): void {
    this.doubleTapX = x
    this.doubleTapY = y
    this.doubleTapSeq = this.doubleTapSeq + 1
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

  private turnSpread(delta: number): void {
    const currentSpread: number = this.spreadIndexForImage(this.vm.currentIndex)
    const targetSpread: number = currentSpread + delta
    if (targetSpread < 0 || targetSpread >= this.spreadCount()) {
      return
    }
    this.turnTo(this.spreadStartIndex(targetSpread))
  }

  private toPrev(): void {
    if (this.doublePageEnabled()) {
      this.turnSpread(-1)
      return
    }
    this.turnTo(this.vm.currentIndex - this.pageStep())
  }

  private toNext(): void {
    if (this.doublePageEnabled()) {
      this.turnSpread(1)
      return
    }
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
        this.vm.currentIndex = this.normalizedReaderIndex(target)
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
            activeIndex: this.vm.currentIndex,
            doubleTapSeq: this.doubleTapSeq,
            doubleTapX: this.doubleTapX,
            doubleTapY: this.doubleTapY,
            onZoomChange: (zoomed: boolean) => {
              this.imageZoomed = zoomed
            },
            onImageLoaded: (page: number) => {
              this.markPageImageLoaded(page)
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
    .parallelGesture(
      TapGesture({ count: 2 }).onAction((e?: GestureEvent) => {
        const loc = e ? e.tapLocation : undefined
        const tapX: number = loc ? (loc.x as number) : this.viewWidth / 2
        const tapY: number = loc ? (loc.y as number) : this.viewHeight / 2
        this.onReaderDoubleTap(tapX, tapY)
      }),
    )
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

  private spreadIndexForMode(columnMode: string, index: number): number {
    if (columnMode === ReadColumnMode.SINGLE || index <= 0) {
      return index
    }
    if (columnMode === ReadColumnMode.EVEN_LEFT) {
      return Math.floor((index + 1) / 2)
    }
    return Math.floor(index / 2)
  }

  private spreadStartForMode(columnMode: string, spreadIndex: number): number {
    if (columnMode === ReadColumnMode.SINGLE) {
      return spreadIndex
    }
    if (columnMode === ReadColumnMode.EVEN_LEFT) {
      return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
    }
    return spreadIndex * 2
  }

  private normalizedIndexForColumnMode(columnMode: string): number {
    const spreadIndex: number = this.spreadIndexForMode(columnMode, this.vm.currentIndex)
    return this.spreadStartForMode(columnMode, spreadIndex)
  }

  private normalizedReaderIndex(index: number): number {
    if (!this.doublePageEnabled()) {
      return index
    }
    return this.spreadStartIndex(this.spreadIndexForImage(index))
  }

  private sliderTargetIndex(page: number): number {
    const index: number = page - 1
    if (!this.doublePageEnabled()) {
      return index
    }
    return this.spreadStartIndex(this.spreadIndexForImage(index))
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

  private spreadSecondIndex(start: number): number {
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT && start <= 0) {
      return -1
    }
    return start + 1
  }

  private spreadSecondVisible(start: number): boolean {
    const second: number = this.spreadSecondIndex(start)
    return second >= 0 && second < this.vm.totalPages()
  }

  private spreadRowReversed(): boolean {
    return this.readMode.mode === ReadMode.RTL
  }

  @Builder
  SpreadImage(index: number) {
    if (this.hasSpreadImage(index)) {
      ReaderImagePage({
        image: this.vm.images[index],
        activeIndex: this.vm.currentIndex,
        doubleTapSeq: this.doubleTapSeq,
        doubleTapX: this.doubleTapX,
        doubleTapY: this.doubleTapY,
        onZoomChange: (zoomed: boolean) => {
          this.imageZoomed = zoomed
        },
        onImageLoaded: (page: number) => {
          this.markPageImageLoaded(page)
        },
      })
        .layoutWeight(1)
    } else {
      Blank()
        .layoutWeight(1)
    }
  }

  @Builder
  SpreadSecondSlot(start: number) {
    if (this.spreadSecondVisible(start)) {
      this.SpreadImage(this.spreadSecondIndex(start))
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
            if (this.spreadRowReversed()) {
              this.SpreadSecondSlot(start)
              this.SpreadImage(start)
            } else {
              this.SpreadImage(start)
              this.SpreadSecondSlot(start)
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
    .parallelGesture(
      TapGesture({ count: 2 }).onAction((e?: GestureEvent) => {
        const loc = e ? e.tapLocation : undefined
        const tapX: number = loc ? (loc.x as number) : this.viewWidth / 2
        const tapY: number = loc ? (loc.y as number) : this.viewHeight / 2
        this.onReaderDoubleTap(tapX, tapY)
      }),
    )
  }

  @Builder
  VerticalReader() {
    List({ initialIndex: this.vm.currentIndex, scroller: this.listScroller }) {
      ForEach(
        this.vm.images,
        (img: EhGalleryImage) => {
          ListItem() {
            ReaderVerticalImage({
              image: img,
              onImageLoaded: (page: number) => {
                this.markPageImageLoaded(page)
              },
            })
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
    const targetIndex: number = this.normalizedIndexForColumnMode(next)
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setColumnMode(ctx, next)
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return
    }
    this.vm.currentIndex = targetIndex
    this.sliderValue = targetIndex + 1
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

  private hasRenderableThumb(img: EhGalleryImage): boolean {
    return img.sUrl.length > 0 && img.thumbUrl.length > 0
  }

  private thumbKey(img: EhGalleryImage): string {
    return `${img.page}-${img.sUrl}`
  }

  private jumpToThumb(index: number): void {
    this.showChrome = false
    this.jumpToPage(index)
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
        Row() {
          SaveButton({
            icon: SaveIconStyle.LINES,
            buttonType: ButtonType.Circle,
          })
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.saveCurrentImage()
              } else {
                promptAction.showToast({ message: $r('app.string.reader_save_failed') })
              }
            })
            .width(40)
            .height(40)
        }
        .margin({ right: ThemeConstants.SPACE_SM })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(20)
            .fontColor([this.autoReadActive ? ThemeConstants.BRAND_PRIMARY : Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.toggleAutoRead()
        })
        .margin({ right: ThemeConstants.SPACE_SM })
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(20)
            .fontColor([this.showThumbStrip ? ThemeConstants.BRAND_PRIMARY : Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showThumbStrip = !this.showThumbStrip
        })
        .margin({ right: ThemeConstants.SPACE_SM })
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
            this.jumpToPage(this.sliderTargetIndex(page))
          }
        })
      if (this.showThumbStrip) {
        this.ReaderThumbStrip()
      }
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

  @Builder
  ReaderThumbStrip() {
    List({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.vm.images,
        (img: EhGalleryImage) => {
          if (this.hasRenderableThumb(img)) {
            ListItem() {
              Column({ space: ThemeConstants.SPACE_XS }) {
                Stack({ alignContent: Alignment.Center }) {
                  EhSpriteThumbnail({
                    url: img.thumbUrl,
                    thumbWidth: img.thumbWidth,
                    thumbHeight: img.thumbHeight,
                    offsetX: img.thumbOffsetX,
                    spriteWidth: img.spriteWidth,
                    spriteHeight: img.spriteHeight,
                    displayHeight: 58,
                    fitHeight: true,
                    radius: ThemeConstants.RADIUS_SM,
                  })
                  if (img.page - 1 === this.vm.currentIndex) {
                    Row()
                      .width('100%')
                      .height('100%')
                      .border({
                        width: 2,
                        color: ThemeConstants.BRAND_PRIMARY,
                      })
                      .borderRadius(ThemeConstants.RADIUS_SM)
                  }
                }
                .height(58)
                .constraintSize({ minWidth: 42, maxWidth: 72 })
                .clip(true)
                Text(`${img.page}`)
                  .fontSize(ThemeConstants.FONT_SIZE_TINY)
                  .fontColor(img.page - 1 === this.vm.currentIndex ? ThemeConstants.BRAND_PRIMARY : Color.White)
                  .maxLines(1)
              }
              .width(76)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.jumpToThumb(img.page - 1)
              })
            }
          }
        },
        (img: EhGalleryImage) => this.thumbKey(img),
      )
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .height(82)
    .width('100%')
  }
}

const MAX_SCALE: number = 4
const DOUBLE_TAP_SCALE: number = 2.5
const IMAGE_AUTO_RETRY_LIMIT: number = 3

enum ReaderImageFailureKind {
  Generic = 'generic',
  Quota = 'quota',
  RateLimited = 'rateLimited',
}

function readerFailureKindFromError(err: Error): ReaderImageFailureKind {
  const message: string = err.message.toLowerCase()
  if (message.indexOf('image509') >= 0 || message.indexOf('509') >= 0 || message.indexOf('quota') >= 0) {
    return ReaderImageFailureKind.Quota
  }
  if (message.indexOf('429') >= 0 || message.indexOf('rate') >= 0 || message.indexOf('throttle') >= 0) {
    return ReaderImageFailureKind.RateLimited
  }
  return ReaderImageFailureKind.Generic
}

// Structural subset of Image.onComplete. Intrinsic bitmap size is converted to vp so
// contain-fit pan bounds stay in the same coordinate space as gestures.
interface ReaderImageLoadEvent {
  loadingStatus: number
  width?: number
  height?: number
  componentWidth?: number
  componentHeight?: number
}

/**
 * One reader page. Resolves its full image on appear, then renders it with pinch /
 * double-tap zoom and (when zoomed) pan. Reports zoom state up so the parent gates Swiper
 * swipe. Pinch/double-tap stay on the image gesture group; zoomed pan is a parallel
 * one-finger gesture so fit-state horizontal drags can still reach the ancestor Swiper.
 */
@ComponentV2
struct ReaderImagePage {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Param activeIndex: number = 0;
  @Param doubleTapSeq: number = 0;
  @Param doubleTapX: number = 0;
  @Param doubleTapY: number = 0;
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local intrinsicW: number = 0;
  @Local intrinsicH: number = 0;

  private baseZoom: number = 1;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private pinchStartScale: number = 1;
  private pinchStartOffX: number = 0;
  private pinchStartOffY: number = 0;
  private pinchCenterStartX: number = 0;
  private pinchCenterStartY: number = 0;
  private panStartOffX: number = 0;
  private panStartOffY: number = 0;
  private isPinching: boolean = false;
  private compW: number = 0;
  private compH: number = 0;
  private lastZoomed: boolean = false;
  private autoRetryCount: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  @Monitor('doubleTapSeq')
  onDoubleTapCommand(): void {
    if (this.image.page !== this.activeIndex + 1) {
      return
    }
    this.onDoubleTap(this.doubleTapX, this.doubleTapY)
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) — re-resolves via /s/?nl= for a
  // different host, bypassing the cached URL.
  private async resolve(changeSource: boolean = false): Promise<void> {
    if (!changeSource && this.image.imageUrl.length > 0) {
      this.imageLoaded = false
      this.imageUrl = this.image.imageUrl
      return
    }
    try {
      this.imageLoaded = false
      this.imageUrl = await ImageResolveService.getInstance().resolve(this.image, changeSource)
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  // Retry on failure: re-source (换源) — clear the dead URL and re-resolve from a different host.
  private retrySource(): void {
    this.autoRetryCount = 0
    this.imageUrl = ''
    this.imageLoaded = false
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.imageUrl = ''
      this.imageLoaded = false
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  private clampScale(value: number): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value < 1) {
      return 1
    }
    if (value > MAX_SCALE) {
      return MAX_SCALE
    }
    return value
  }

  private fitScale(): number {
    if (this.compW <= 0 || this.compH <= 0 || this.intrinsicW <= 0 || this.intrinsicH <= 0) {
      return 1
    }
    const scaleW: number = this.compW / this.intrinsicW
    const scaleH: number = this.compH / this.intrinsicH
    const fit: number = Math.min(scaleW, scaleH)
    return fit > 0 ? fit : 1
  }

  private displayW(): number {
    if (this.intrinsicW <= 0) {
      return this.compW
    }
    return this.intrinsicW * this.fitScale()
  }

  private displayH(): number {
    if (this.intrinsicH <= 0) {
      return this.compH
    }
    return this.intrinsicH * this.fitScale()
  }

  private maxOffset(viewport: number, displaySize: number, scale: number): number {
    const overflow: number = displaySize * scale - viewport
    return overflow > 0 ? overflow / 2 : 0
  }

  private clampOffsetX(value: number, scale: number): number {
    const maxX: number = this.maxOffset(this.compW, this.displayW(), scale)
    if (value > maxX) {
      return maxX
    }
    if (value < -maxX) {
      return -maxX
    }
    return value
  }

  private clampOffsetY(value: number, scale: number): number {
    const maxY: number = this.maxOffset(this.compH, this.displayH(), scale)
    if (value > maxY) {
      return maxY
    }
    if (value < -maxY) {
      return -maxY
    }
    return value
  }

  private panDistance(): number {
    if (this.zoomScale > 1.01) {
      return 1
    }
    const longSide: number = Math.max(this.compW, this.compH)
    return longSide > 0 ? longSide * 2 : 10000
  }

  private clampOffset(): void {
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
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

  private onDoubleTap(tapX: number, tapY: number): void {
    if (this.zoomScale > 1.01) {
      this.resetZoom()
    } else {
      const target: number = DOUBLE_TAP_SCALE
      const nextX: number = (1 - target) * (tapX - this.compW / 2)
      const nextY: number = (1 - target) * (tapY - this.compH / 2)
      this.zoomScale = target
      this.baseZoom = target
      this.offsetX = this.clampOffsetX(nextX, target)
      this.offsetY = this.clampOffsetY(nextY, target)
      this.baseOffsetX = this.offsetX
      this.baseOffsetY = this.offsetY
    }
    this.notifyZoom()
  }

  build() {
    Stack() {
      // `failed` first: a resolve error OR an Image fetch error (dead one-shot token / 509) shows the
      // re-source retry even if a (broken) URL is set.
      if (this.failed) {
        ReaderFailureOverlay({
          page: this.image.page,
          kind: this.failureKind,
          onRetry: () => {
            this.retrySource()
          },
        })
      } else if (this.imageUrl.length > 0) {
        Image(this.imageUrl)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .draggable(false)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.offsetX, y: this.offsetY })
          .renderGroup(true)
          .onComplete((event?: ReaderImageLoadEvent) => {
            if (event && event.width && event.height) {
              this.intrinsicW = this.getUIContext().px2vp(event.width)
              this.intrinsicH = this.getUIContext().px2vp(event.height)
            } else if (event && event.componentWidth && event.componentHeight) {
              this.intrinsicW = event.componentWidth
              this.intrinsicH = event.componentHeight
            }
            this.autoRetryCount = 0
            this.imageLoaded = true
            this.onImageLoaded(this.image.page)
            this.clampOffset()
          })
          .onError(() => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          })
        if (!this.imageLoaded) {
          ReaderLoadingStage({ label: $r('app.string.reader_loading_image') })
            .hitTestBehavior(HitTestMode.None)
        }
      } else {
        ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area) => {
      this.compW = n.width as number
      this.compH = n.height as number
      this.clampOffset()
    })
    // Pinch zoom. Parent Reader captures double-tap on the Swiper and commands the active
    // image page, because child double-tap recognizers are unreliable inside Swiper.
    // Pan is bound as a parallel gesture below so normal page
    // swipes can still reach the Swiper at fit scale.
    .gesture(
      GestureGroup(
        GestureMode.Parallel,
        PinchGesture({ fingers: 2 })
          .onActionStart((e?: GestureEvent) => {
            if (!e) {
              return
            }
            this.isPinching = true
            this.pinchStartScale = this.zoomScale
            this.pinchStartOffX = this.offsetX
            this.pinchStartOffY = this.offsetY
            this.pinchCenterStartX = e.pinchCenterX as number
            this.pinchCenterStartY = e.pinchCenterY as number
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e) {
              return
            }
            const nextScale: number = this.clampScale(this.pinchStartScale * (e.scale as number))
            const k: number = nextScale / this.pinchStartScale
            const dx: number = (e.pinchCenterX as number) - this.pinchCenterStartX
            const dy: number = (e.pinchCenterY as number) - this.pinchCenterStartY
            const nextX: number =
              (this.pinchCenterStartX - this.compW / 2) * (1 - k) + k * this.pinchStartOffX + dx
            const nextY: number =
              (this.pinchCenterStartY - this.compH / 2) * (1 - k) + k * this.pinchStartOffY + dy
            this.zoomScale = nextScale
            this.offsetX = this.clampOffsetX(nextX, nextScale)
            this.offsetY = this.clampOffsetY(nextY, nextScale)
            this.notifyZoom()
          })
          .onActionEnd(() => {
            this.isPinching = false
            this.baseZoom = this.zoomScale
            if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          })
          .onActionCancel(() => {
            this.isPinching = false
            this.baseZoom = this.zoomScale
            this.clampOffset()
          }),
      ),
    )
    .parallelGesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: this.panDistance() })
        .onActionStart(() => {
          this.panStartOffX = this.offsetX
          this.panStartOffY = this.offsetY
        })
        .onActionUpdate((e?: GestureEvent) => {
          if (!e || this.isPinching || this.zoomScale <= 1.01) {
            return
          }
          this.offsetX = this.clampOffsetX(this.panStartOffX + (e.offsetX as number), this.zoomScale)
          this.offsetY = this.clampOffsetY(this.panStartOffY + (e.offsetY as number), this.zoomScale)
        })
        .onActionEnd(() => {
          this.baseOffsetX = this.offsetX
          this.baseOffsetY = this.offsetY
        }),
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
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local ratio: number = DEFAULT_VERTICAL_RATIO;
  private autoRetryCount: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) via /s/?nl=, bypassing the cache.
  private async resolve(changeSource: boolean = false): Promise<void> {
    if (!changeSource && this.image.imageUrl.length > 0) {
      this.imageLoaded = false
      this.imageUrl = this.image.imageUrl
      return
    }
    try {
      this.imageLoaded = false
      this.imageUrl = await ImageResolveService.getInstance().resolve(this.image, changeSource)
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    this.imageUrl = ''
    this.imageLoaded = false
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.imageUrl = ''
      this.imageLoaded = false
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  build() {
    Stack() {
      // `failed` first so an Image fetch error (dead token / 509) shows the re-source retry.
      if (this.failed) {
        ReaderFailureOverlay({
          page: this.image.page,
          kind: this.failureKind,
          compact: true,
          onRetry: () => {
            this.retrySource()
          },
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
            this.onImageLoaded(this.image.page)
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
          ReaderLoadingStage({
            label: $r('app.string.reader_loading_image'),
            compact: true,
          })
            .hitTestBehavior(HitTestMode.None)
        }
      } else {
        ReaderLoadingStage({
          label: $r('app.string.reader_loading_resolving'),
          compact: true,
        })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 220 })
  }
}

@ComponentV2
struct ReaderLoadingStage {
  @Param label: ResourceStr = '';
  @Param compact: boolean = false;

  private spinnerSize(): number {
    return this.compact ? ThemeConstants.LOADING_SIZE : ThemeConstants.LOADING_SIZE_LARGE
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      LoadingProgress()
        .width(this.spinnerSize())
        .height(this.spinnerSize())
        .color(Color.White)
      Text(this.label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeConstants.SPACE_XL)
  }
}

@ComponentV2
struct ReaderFailureOverlay {
  @Param page: number = 0;
  @Param kind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Param compact: boolean = false;
  @Param onRetry: () => void = () => {};

  private iconSize(): number {
    return this.compact ? 28 : 36
  }

  private contentWidth(): number {
    return this.compact ? 196 : 280
  }

  private failureTitle(): ResourceStr {
    if (this.kind === ReaderImageFailureKind.Quota) {
      return $r('app.string.reader_error_quota')
    }
    if (this.kind === ReaderImageFailureKind.RateLimited) {
      return $r('app.string.reader_error_rate_limited')
    }
    return $r('app.string.image_load_failed')
  }

  private failureHint(): ResourceStr {
    if (this.kind === ReaderImageFailureKind.Quota) {
      return $r('app.string.reader_error_quota_hint')
    }
    if (this.kind === ReaderImageFailureKind.RateLimited) {
      return $r('app.string.reader_error_rate_limited_hint')
    }
    return $r('app.string.reader_retry_source_hint')
  }

  build() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(this.iconSize())
        .fontColor([Color.White])
      Text(this.failureTitle())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text(this.failureHint())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor('#AAFFFFFF')
        .textAlign(TextAlign.Center)
        .maxLines(2)
      if (this.page > 0) {
        Text(`P${this.page}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor('#88FFFFFF')
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
      Button($r('app.string.reader_retry_source'))
        .type(ButtonType.Capsule)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(Color.White)
        .backgroundColor('#26FFFFFF')
        .onClick(() => {
          this.onRetry()
        })
    }
    .width(this.contentWidth())
    .padding(ThemeConstants.SPACE_LG)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.Default)
  }
}
