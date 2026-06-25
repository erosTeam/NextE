import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { KeyCode } from '@kit.InputKit'
import inputConsumer from '@ohos.multimodalInput.inputConsumer'
import { Action, KeyEvent as InputConsumerKeyEvent } from '@ohos.multimodalInput.keyEvent'
import {
  ThemeConstants,
  BasicDataSource,
  EhGalleryImage,
  EhSpriteThumbnail,
  ReaderParams,
  ImageResolveService,
  CachedImageFileService,
  DiagnosticLogger,
  connectThemeDisplay,
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
  CachedImageProgress,
  CachedImageFileResult,
} from 'shared'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'

const READER_KEY_SURFACE_ID: string = 'reader_key_surface'
const READER_CHROME_ACTION_SIZE: number = 44
const READER_CHROME_ICON_SIZE: number = 22
const READER_CHROME_TRACK_BG: ResourceColor = '#33FFFFFF'
const READER_THUMB_STRIP_HEIGHT: number = 84
const READER_BOTTOM_TOOLBAR_HEIGHT: number = 112
const READER_PROGRESS_NUMBER_MIN_W: number = 30
const READER_PROGRESS_SLIDER_GAP: number = 4
const READER_IMAGE_WARM_AHEAD: number = 2
const READER_ZOOM_ANIM_DURATION: number = 180
class ReaderSpreadResolver {
  static isDoublePage(mode: string, columnMode: string): boolean {
    return mode !== ReadMode.VERTICAL && columnMode !== ReadColumnMode.SINGLE
  }

  static spreadIndexForImage(columnMode: string, index: number): number {
    if (index <= 0) {
      return 0
    }
    if (columnMode === ReadColumnMode.EVEN_LEFT) {
      return Math.floor((index + 1) / 2)
    }
    return Math.floor(index / 2)
  }

  static spreadStartIndex(columnMode: string, spreadIndex: number): number {
    if (columnMode === ReadColumnMode.EVEN_LEFT) {
      return spreadIndex <= 0 ? 0 : spreadIndex * 2 - 1
    }
    return spreadIndex * 2
  }

  static spreadIndexForMode(columnMode: string, index: number): number {
    if (columnMode === ReadColumnMode.SINGLE || index <= 0) {
      return index
    }
    return ReaderSpreadResolver.spreadIndexForImage(columnMode, index)
  }

  static spreadStartForMode(columnMode: string, spreadIndex: number): number {
    if (columnMode === ReadColumnMode.SINGLE) {
      return spreadIndex
    }
    return ReaderSpreadResolver.spreadStartIndex(columnMode, spreadIndex)
  }

  static normalizedIndexForColumnMode(columnMode: string, currentIndex: number): number {
    const spreadIndex: number = ReaderSpreadResolver.spreadIndexForMode(columnMode, currentIndex)
    return ReaderSpreadResolver.spreadStartForMode(columnMode, spreadIndex)
  }

  static normalizedReaderIndex(enabled: boolean, columnMode: string, index: number): number {
    if (!enabled) {
      return index
    }
    return ReaderSpreadResolver.spreadStartIndex(
      columnMode,
      ReaderSpreadResolver.spreadIndexForImage(columnMode, index)
    )
  }

  static sliderTargetIndex(enabled: boolean, columnMode: string, page: number): number {
    const index: number = page - 1
    return ReaderSpreadResolver.normalizedReaderIndex(enabled, columnMode, index)
  }

  static spreadCount(enabled: boolean, columnMode: string, total: number): number {
    if (!enabled || total <= 1) {
      return total
    }
    if (columnMode === ReadColumnMode.EVEN_LEFT) {
      return Math.round(total / 2) + ((total + 1) % 2)
    }
    return Math.round(total / 2)
  }

  static spreadStarts(enabled: boolean, columnMode: string, total: number): number[] {
    const out: number[] = []
    const count: number = ReaderSpreadResolver.spreadCount(enabled, columnMode, total)
    for (let i: number = 0; i < count; i++) {
      out.push(ReaderSpreadResolver.spreadStartIndex(columnMode, i))
    }
    return out
  }

  static spreadSecondIndex(columnMode: string, start: number): number {
    if (columnMode === ReadColumnMode.EVEN_LEFT && start <= 0) {
      return -1
    }
    return start + 1
  }

  static spreadSecondVisible(columnMode: string, start: number, total: number): boolean {
    const second: number = ReaderSpreadResolver.spreadSecondIndex(columnMode, start)
    return second >= 0 && second < total
  }
}

/**
 * Image reader (basic-complete): pager owns page turns, image/spread surfaces own zoom gestures,
 * and a transparent tap overlay owns chrome/tap-zone routing. Keeping tap/chrome arbitration out
 * of Swiper prevents the pager from becoming a mixed single-tap/double-tap/zoom surface.
 * While zoomed, the image reports up so the Swiper disables swipe (pan moves the image instead of
 * turning the page). The VM loads further preview pages as you approach the end, so the whole
 * gallery is readable.
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
  @Local doubleTapTargetPage: number = 0;
  // While the user drags the page slider, show the target page (1-based) instead of the live one.
  @Local sliderPreview: number = -1;
  // 1-based slider position; follows the live page on swipe and drives jump-to-page on drag.
  @Local sliderValue: number = 1;
  // Swiper index is a component concern: image index in single-page mode, spread index in double-page.
  @Local readerPagerIndex: number = 0;
  // The reader surface must not mount while init is still loading page 0 to discover perPage.
  // Resume-to-later-page otherwise mounts Swiper at index 0, then chrome moves to the target while
  // the rendered page can stay on the reused first page surface.
  @Local readerReady: boolean = false;
  @Local readMode: ReadModeState = connectReadMode();
  @Local autoReadActive: boolean = false;
  @Local showThumbStrip: boolean = false;
  // Reader viewport size (captured on layout) — divides the canvas into eros_fe's 3×3 tap regions
  // (left/right thirds + center-column top/bottom fifths).
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  @Local loadedPageSignal: number = 0;
  @Local originalImagePages: string = '';
  @Local originalImageResolving: boolean = false;
  @Local savingCurrentImage: boolean = false;
  private listScroller: Scroller = new Scroller();
  private thumbScroller: Scroller = new Scroller();
  private horizontalSwiperController: SwiperController = new SwiperController();
  private doublePageSwiperController: SwiperController = new SwiperController();
  // Safe-area insets (gesture bar / status bar) published by EntryAbility — the page counter
  // sits above the bottom inset so it never hides behind the home indicator.
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private autoReadTimer: number = -1;
  private autoReadWaitingIndex: number = -1;
  private loadedPages: number[] = [];
  private spreadDataSource: BasicDataSource<number> = new BasicDataSource<number>();
  private spreadDataSourceKey: string = '';
  private volumeDownConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;
  private volumeUpConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.readerContentReady()) {
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
              .fontColor(ThemeConstants.TEXT_ON_BRAND)
              .backgroundColor(ThemeConstants.BRAND_PRIMARY)
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

        // Only show far-jump resolving UI when there is no readable image surface yet.
        if (this.vm.jumping && !this.readerContentReady()) {
          ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
        }

        if (this.readerContentReady()) {
          this.ReaderImageWarmers()
          this.ReaderTapOverlay()
        }

        // Hidden chrome must leave the reader canvas entirely; opacity-only controls can still steal
        // drags from the pager on some devices.
        if (this.readerContentReady() && this.showChrome) {
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
        this.readerReady = false
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
            const total: number = this.vm.totalPages()
            const loadedTarget: number = total > 0 ? Math.min(requestedIndex, total - 1) : 0
            const targetIndex: number = this.normalizedReaderIndex(loadedTarget)
            this.vm.currentIndex = targetIndex
            this.sliderValue = targetIndex + 1
            this.readerPagerIndex = this.readerPagerIndexFor(targetIndex)
            this.readerReady = true
            if (this.readMode.mode === ReadMode.VERTICAL) {
              setTimeout(() => {
                this.listScroller.scrollToIndex(targetIndex)
              }, 50)
            } else {
              this.syncReaderPagerToIndex(targetIndex, false)
            }
          })
      }
      // Keep the screen awake while reading (eros_fe couples fullscreen + wakelock); window-scoped,
      // restored on aboutToDisappear. The app is already edge-to-edge fullscreen (EntryAbility), so the
      // reader doesn't re-enter fullscreen — the black canvas + faded chrome is the immersive surface.
      this.setReaderKeepScreenOn(true)
      this.setReaderStatusIconsHidden(true)
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
    if (this.imageZoomed || this.vm.jumping || this.vm.totalPages() === 0) {
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

  private setReaderStatusIconsHidden(hidden: boolean): void {
    const restoreColor: string = connectThemeDisplay().effectiveDark ? '#FFFFFFFF' : '#FF000000'
    const contentColor: string = hidden ? '#00000000' : restoreColor
    window
      .getLastWindow(this.hostContext())
      .then((win: window.Window) => {
        win.setWindowSystemBarProperties({ statusBarContentColor: contentColor }).catch((_e: Error) => {})
      })
      .catch((_e: Error) => {})
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private currentImage(): EhGalleryImage | null {
    if (!this.vm.hasPreviewAt(this.vm.currentIndex)) {
      return null
    }
    return this.vm.imageAt(this.vm.currentIndex)
  }

  private readerContentReady(): boolean {
    return this.readerReady && this.vm.totalPages() > 0
  }

  private warmImageIndexes(): number[] {
    const indexes: number[] = []
    if (!this.readerContentReady() || this.viewWidth <= 0 || this.viewHeight <= 0) {
      return indexes
    }
    const to: number = Math.min(this.vm.currentIndex + READER_IMAGE_WARM_AHEAD, this.vm.totalPages() - 1)
    for (let i: number = this.vm.currentIndex + 1; i <= to; i++) {
      if (this.vm.imageAt(i).imageUrl.length > 0) {
        indexes.push(i)
      }
    }
    return indexes
  }

  private warmerTranslateX(): number {
    return this.viewWidth + ThemeConstants.SPACE_XL
  }

  @Builder
  ReaderImageWarmers() {
    Stack() {
      ForEach(
        this.warmImageIndexes(),
        (index: number) => {
          Image(this.vm.imageAt(index).imageUrl)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)
            .width('100%')
            .height('100%')
            // Lay out the warmer at reader-canvas size, then move it off-screen. A 1vp warmer only
            // proves the URL fetch path; this makes the hidden Image enter the same display-size
            // pipeline before Swiper exposes the page.
            .translate({ x: this.warmerTranslateX(), y: 0 })
            .draggable(false)
            .onComplete(() => {
              this.markPageImageLoaded(index + 1)
              DiagnosticLogger.info('reader', 'warm_image_complete', `page ${index + 1}`)
            })
            .onError(() => {
              DiagnosticLogger.warn('reader', 'warm_image_failed', `page ${index + 1}`)
            })
        },
        (index: number) => `${index}-${this.vm.imageAt(index).imageUrl}`,
      )
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.None)
  }

  private originalToken(page: number): string {
    return `|${page}|`
  }

  private originalModeForPage(page: number): boolean {
    return page > 0 && this.originalImagePages.indexOf(this.originalToken(page)) >= 0
  }

  private originalModeKeyForPage(page: number): string {
    return this.originalModeForPage(page) ? 'orig' : 'fit'
  }

  private setOriginalModeForPage(page: number, enabled: boolean): void {
    const token: string = this.originalToken(page)
    const has: boolean = this.originalImagePages.indexOf(token) >= 0
    if (enabled && !has) {
      this.originalImagePages = `${this.originalImagePages}${token}`
    } else if (!enabled && has) {
      this.originalImagePages = this.originalImagePages.replace(token, '')
    }
  }

  private currentDisplayUrl(image: EhGalleryImage): string {
    if (this.originalModeForPage(image.page) && image.originImageUrl.length > 0) {
      return image.originImageUrl
    }
    return image.imageUrl
  }

  private resolveCurrentDisplayUrl(image: EhGalleryImage): Promise<string> {
    if (this.originalModeForPage(image.page)) {
      return ImageResolveService.getInstance().resolveOriginal(image)
    }
    return ImageResolveService.getInstance().resolve(image)
  }

  private toggleOriginalImage(): void {
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null || this.originalImageResolving) {
      return
    }
    if (this.originalModeForPage(image.page)) {
      this.setOriginalModeForPage(image.page, false)
      DiagnosticLogger.info('reader', 'original_mode_off', `page ${image.page}`)
      return
    }
    this.originalImageResolving = true
    ImageResolveService.getInstance()
      .resolveOriginal(image)
      .then((url: string) => {
        this.setOriginalModeForPage(image.page, true)
        DiagnosticLogger.info('reader', 'original_mode_on', `page ${image.page} fullimg ${url.indexOf('/fullimg') >= 0}`)
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('reader', 'original_resolve_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_original_unavailable') })
      })
      .finally(() => {
        this.originalImageResolving = false
      })
  }

  private originalButtonColor(): ResourceColor {
    const image: EhGalleryImage | null = this.currentImage()
    if (image !== null && this.originalModeForPage(image.page)) {
      return ThemeConstants.BRAND_PRIMARY
    }
    return Color.White
  }

  // Share the current reader image URL from the reader top bar (eros_fe ViewTopBar share). It uses the
  // currently displayed source: resampled by default, original only after the user explicitly enables it.
  // If the current page is not resolved yet, resolve it through the same /s/ pipeline the reader uses.
  private shareCurrentImage(): void {
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null) {
      this.shareGallery()
      return
    }
    const title: string = `${this.params.title} ${this.vm.currentIndex + 1}`.trim()
    const alreadyResolvedUrl: string = this.currentDisplayUrl(image)
    if (alreadyResolvedUrl.length > 0) {
      ShareUtil.shareUrl(this.hostContext(), alreadyResolvedUrl, title)
      return
    }
    this.resolveCurrentDisplayUrl(image)
      .then((imageUrl: string) => {
        ShareUtil.shareUrl(this.hostContext(), imageUrl, title)
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
    if (this.savingCurrentImage) {
      return
    }
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_no_image') })
      return
    }
    this.savingCurrentImage = true
    const title: string = `${this.params.gid}-${this.vm.currentIndex + 1}`.trim()
    const alreadyResolvedUrl: string = this.currentDisplayUrl(image)
    if (alreadyResolvedUrl.length > 0) {
      this.saveImageUrl(alreadyResolvedUrl, title).finally(() => {
        this.savingCurrentImage = false
      })
      return
    }
    this.resolveCurrentDisplayUrl(image)
      .then((imageUrl: string) => {
        return this.saveImageUrl(imageUrl, title)
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('reader', 'save_image_resolve_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_failed') })
      })
      .finally(() => {
        this.savingCurrentImage = false
      })
  }

  private saveImageUrl(url: string, title: string): Promise<void> {
    return ImageSaveUtil.saveNetworkImageToGallery(this.hostContext(), url, title)
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
    this.readerPagerIndex = this.readerPagerIndexFor(this.vm.currentIndex)
    this.scrollThumbStripTo(this.vm.currentIndex, true)
    if (this.params.gid.length > 0) {
      GalleryReadProgressSettings.setIndex(
        this.hostContext(),
        this.params.gid,
        this.vm.currentIndex,
      )
    }
  }

  @Monitor('readMode.volumeKeyTurn')
  onVolumeKeyTurnChanged(): void {
    if (this.readMode.volumeKeyTurn) {
      this.requestReaderKeyFocus()
      this.registerVolumeKeyConsumer()
    } else {
      this.unregisterVolumeKeyConsumer()
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
    this.setReaderStatusIconsHidden(false)
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
    return index >= 0 && index < this.vm.totalPages() && this.vm.imageAt(index).imageUrl.length > 0
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
    this.loadedPageSignal++
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

  private clearZoomGate(): void {
    this.imageZoomed = false
  }

  private doubleTapTargetForPoint(x: number): number {
    if (!this.doublePageEnabled()) {
      return this.vm.currentIndex + 1
    }
    const spreadStart: number = this.spreadStartIndex(this.spreadIndexForImage(this.vm.currentIndex))
    const second: number = this.spreadSecondIndex(spreadStart)
    const leftVisualTarget: number = this.spreadRowReversed() ? second : spreadStart
    const rightVisualTarget: number = this.spreadRowReversed() ? spreadStart : second
    const tapLeftSide: boolean = x < this.viewWidth / 2
    const target: number = tapLeftSide ? leftVisualTarget : rightVisualTarget
    if (!this.hasSpreadImage(target)) {
      return spreadStart + 1
    }
    return target + 1
  }

  private onReaderDoubleTap(x: number, y: number): void {
    this.doubleTapX = x
    this.doubleTapY = y
    this.doubleTapTargetPage = this.doubleTapTargetForPoint(x)
    this.doubleTapSeq = this.doubleTapSeq + 1
  }

  private doublePageEnabled(): boolean {
    return ReaderSpreadResolver.isDoublePage(this.readMode.mode, this.readMode.columnMode)
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
    this.clearZoomGate()
    if (target >= this.vm.totalPages() || !this.vm.hasPreviewAt(target)) {
      this.jumpToPage(target)
      return
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      this.vm.currentIndex = target
      this.listScroller.scrollToIndex(target)
    } else {
      const targetIndex: number = this.normalizedReaderIndex(target)
      this.readerPagerIndex = this.readerPagerIndexFor(targetIndex)
      this.vm.onPageChange(targetIndex)
      this.syncReaderPagerToIndex(targetIndex, false)
    }
  }

  // Jump after loading every page up to the target. Horizontal: set currentIndex so the Swiper's
  // reactive `.index()` moves there (a fixed `.index` would reset on rebuild). Vertical: scroll the
  // List to the index (onScrollIndex then updates currentIndex).
  private jumpToPage(index: number): void {
    this.clearZoomGate()
    this.vm.jumpTo(index).then((target: number) => {
      if (this.readMode.mode === ReadMode.VERTICAL) {
        this.vm.currentIndex = target
        this.listScroller.scrollToIndex(target)
      } else {
        const targetIndex: number = this.normalizedReaderIndex(target)
        this.readerPagerIndex = this.readerPagerIndexFor(targetIndex)
        this.vm.currentIndex = targetIndex
        this.syncReaderPagerToIndex(targetIndex, false)
      }
    })
  }

  private syncReaderPagerToIndex(index: number, animated: boolean): void {
    if (this.readMode.mode === ReadMode.VERTICAL) {
      setTimeout(() => {
        this.listScroller.scrollToIndex(index)
      }, 0)
      return
    }
    const targetPagerIndex: number = this.readerPagerIndexFor(index)
    this.readerPagerIndex = targetPagerIndex
    setTimeout(() => {
      try {
        if (this.doublePageEnabled()) {
          this.doublePageSwiperController.changeIndex(targetPagerIndex, animated)
        } else {
          this.horizontalSwiperController.changeIndex(targetPagerIndex, animated)
        }
      } catch (err) {
        const message: string = err instanceof Error ? err.message : `${err}`
        DiagnosticLogger.warn('reader', 'pager_sync_failed', message)
      }
    }, 0)
  }

  @Builder
  HorizontalReader() {
    Swiper(this.horizontalSwiperController) {
      LazyForEach(
        this.vm.pageIndexSource,
        (index: number) => {
          if (this.vm.hasPreviewAt(index)) {
            ReaderImagePage({
              image: this.vm.imageAt(index),
              imageKey: `${this.readerImageKey(this.vm.imageAt(index))}-${this.originalModeKeyForPage(this.vm.imageAt(index).page)}`,
              preferOriginal: this.originalModeForPage(this.vm.imageAt(index).page),
              initiallyLoaded: this.isPageImageLoaded(index),
              loadedSignal: this.loadedPageSignal,
              activeIndex: this.vm.currentIndex,
              doubleTapSeq: this.doubleTapSeq,
              doubleTapX: this.doubleTapX,
              doubleTapY: this.doubleTapY,
              doubleTapTargetPage: this.doubleTapTargetPage,
              onZoomChange: (zoomed: boolean) => {
                this.imageZoomed = zoomed
              },
              onImageLoaded: (page: number) => {
                this.markPageImageLoaded(page)
              },
            })
          } else {
            this.ReaderPendingPage(index)
          }
        },
        (index: number) => `${index}-${this.readerImageIdentityKey(this.vm.imageAt(index))}`,
      )
    }
    .index(this.readerPagerIndex)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .loop(false)
    .cachedCount(2)
    .indicator(false)
    .disableSwipe(this.imageZoomed)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      this.clearZoomGate()
      this.readerPagerIndex = i
      DiagnosticLogger.info('reader', 'horizontal_swipe_change', `index ${i} hasPreview ${this.vm.hasPreviewAt(i)}`)
      this.vm.onPageChange(i)
    })
  }

  private spreadIndexForImage(index: number): number {
    return ReaderSpreadResolver.spreadIndexForImage(this.readMode.columnMode, index)
  }

  private spreadStartIndex(spreadIndex: number): number {
    return ReaderSpreadResolver.spreadStartIndex(this.readMode.columnMode, spreadIndex)
  }

  private spreadIndexForMode(columnMode: string, index: number): number {
    return ReaderSpreadResolver.spreadIndexForMode(columnMode, index)
  }

  private spreadStartForMode(columnMode: string, spreadIndex: number): number {
    return ReaderSpreadResolver.spreadStartForMode(columnMode, spreadIndex)
  }

  private normalizedIndexForColumnMode(columnMode: string): number {
    return ReaderSpreadResolver.normalizedIndexForColumnMode(columnMode, this.vm.currentIndex)
  }

  private normalizedReaderIndex(index: number): number {
    return ReaderSpreadResolver.normalizedReaderIndex(
      this.doublePageEnabled(),
      this.readMode.columnMode,
      index
    )
  }

  private readerPagerIndexFor(index: number): number {
    return this.doublePageEnabled() ? this.spreadIndexForImage(index) : index
  }

  private readerPageIndexes(): number[] {
    const total: number = this.vm.totalPages()
    const out: number[] = []
    for (let i: number = 0; i < total; i++) {
      out.push(i)
    }
    return out
  }

  private readerImageKey(img: EhGalleryImage): string {
    return `${img.page}-${img.sUrl}-${img.imageUrl}`
  }

  private readerImageIdentityKey(img: EhGalleryImage): string {
    return `${img.page}-${img.sUrl}`
  }

  private sliderTargetIndex(page: number): number {
    return ReaderSpreadResolver.sliderTargetIndex(this.doublePageEnabled(), this.readMode.columnMode, page)
  }

  private spreadCount(): number {
    return ReaderSpreadResolver.spreadCount(
      this.doublePageEnabled(),
      this.readMode.columnMode,
      this.vm.totalPages()
    )
  }

  private spreadStarts(): number[] {
    return ReaderSpreadResolver.spreadStarts(
      this.doublePageEnabled(),
      this.readMode.columnMode,
      this.vm.totalPages()
    )
  }

  private spreadStartSource(): BasicDataSource<number> {
    const key: string = `${this.doublePageEnabled()}-${this.readMode.columnMode}-${this.vm.totalPages()}`
    if (key !== this.spreadDataSourceKey) {
      this.spreadDataSourceKey = key
      this.spreadDataSource.setData(this.spreadStarts())
    }
    return this.spreadDataSource
  }

  private hasSpreadImage(index: number): boolean {
    return index >= 0 && index < this.vm.totalPages() && this.vm.hasPreviewAt(index)
  }

  private spreadNeedsPreview(start: number): boolean {
    if (!this.hasSpreadImage(start)) {
      return true
    }
    const second: number = this.spreadSecondIndex(start)
    return this.spreadSecondVisible(start) && !this.hasSpreadImage(second)
  }

  private missingSpreadPreviewIndex(start: number): number {
    if (!this.hasSpreadImage(start)) {
      return start
    }
    const second: number = this.spreadSecondIndex(start)
    if (this.spreadSecondVisible(start) && !this.hasSpreadImage(second)) {
      return second
    }
    return start
  }

  private spreadSecondIndex(start: number): number {
    return ReaderSpreadResolver.spreadSecondIndex(this.readMode.columnMode, start)
  }

  private spreadSecondVisible(start: number): boolean {
    return ReaderSpreadResolver.spreadSecondVisible(this.readMode.columnMode, start, this.vm.totalPages())
  }

  private spreadRowReversed(): boolean {
    return this.readMode.mode === ReadMode.RTL
  }

  @Builder
  DoublePageReader() {
    Swiper(this.doublePageSwiperController) {
      LazyForEach(
        this.spreadStartSource(),
        (start: number) => {
          if (this.spreadNeedsPreview(start)) {
            this.ReaderPendingPage(this.missingSpreadPreviewIndex(start))
          } else {
            ReaderSpreadSurface({
              first: this.vm.imageAt(start),
              second: this.hasSpreadImage(this.spreadSecondIndex(start)) ? this.vm.imageAt(this.spreadSecondIndex(start)) : new EhGalleryImage(),
              hasFirst: true,
              hasSecond: this.spreadSecondVisible(start) && this.hasSpreadImage(this.spreadSecondIndex(start)),
              firstPreferOriginal: this.originalModeForPage(this.vm.imageAt(start).page),
              secondPreferOriginal: this.hasSpreadImage(this.spreadSecondIndex(start))
                ? this.originalModeForPage(this.vm.imageAt(this.spreadSecondIndex(start)).page)
                : false,
              firstInitiallyLoaded: this.isPageImageLoaded(start),
              secondInitiallyLoaded: this.isPageImageLoaded(this.spreadSecondIndex(start)),
              loadedSignal: this.loadedPageSignal,
              rowReversed: this.spreadRowReversed(),
              activeIndex: this.vm.currentIndex,
              doubleTapSeq: this.doubleTapSeq,
              doubleTapX: this.doubleTapX,
              doubleTapY: this.doubleTapY,
              doubleTapTargetPage: this.doubleTapTargetPage,
              onZoomChange: (zoomed: boolean) => {
                this.imageZoomed = zoomed
              },
              onImageLoaded: (page: number) => {
                this.markPageImageLoaded(page)
              },
            })
          }
        },
        (start: number) => {
          const first: string = this.hasSpreadImage(start) ? this.vm.imageAt(start).sUrl : ''
          const secondIndex: number = this.spreadSecondIndex(start)
          const second: string = this.hasSpreadImage(secondIndex) ? this.vm.imageAt(secondIndex).sUrl : ''
          return `${start}-${first}-${second}`
        },
      )
    }
    .index(this.readerPagerIndex)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .loop(false)
    .cachedCount(2)
    .indicator(false)
    .disableSwipe(this.imageZoomed)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      this.clearZoomGate()
      this.readerPagerIndex = i
      const target: number = this.spreadStartIndex(i)
      DiagnosticLogger.info('reader', 'double_swipe_change', `spread ${i} index ${target} hasPreview ${this.vm.hasPreviewAt(target)}`)
      this.vm.onPageChange(target)
    })
  }

  @Builder
  ReaderPendingPage(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.vm.previewFailedIndex === index) {
        ReaderFailureOverlay({
          page: index + 1,
          onRetry: () => {
            this.vm.warmPreviewForIndex(index, 'pending-retry')
          },
        })
      } else {
        ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ReaderTapOverlay() {
    Blank()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction((e?: GestureEvent) => {
            const loc = e ? e.tapLocation : undefined
            const tapX: number = loc ? (loc.x as number) : this.viewWidth / 2
            const tapY: number = loc ? (loc.y as number) : this.viewHeight / 2
            this.onReaderDoubleTap(tapX, tapY)
          }),
          TapGesture({ count: 1 }).onAction((e?: GestureEvent) => {
            const loc = e ? e.tapLocation : undefined
            const tapX: number = loc ? (loc.x as number) : this.viewWidth / 2
            const tapY: number = loc ? (loc.y as number) : this.viewHeight / 2
            this.onReaderTap(tapX, tapY)
          }),
        ),
      )
  }

  @Builder
  VerticalReader() {
    List({ initialIndex: this.vm.currentIndex, scroller: this.listScroller }) {
      LazyForEach(
        this.vm.pageIndexSource,
        (index: number) => {
          ListItem() {
            if (this.vm.hasPreviewAt(index)) {
              ReaderVerticalImage({
                image: this.vm.imageAt(index),
                imageKey: `${this.readerImageKey(this.vm.imageAt(index))}-${this.originalModeKeyForPage(this.vm.imageAt(index).page)}`,
                preferOriginal: this.originalModeForPage(this.vm.imageAt(index).page),
                initiallyLoaded: this.isPageImageLoaded(index),
                loadedSignal: this.loadedPageSignal,
                onImageLoaded: (page: number) => {
                  this.markPageImageLoaded(page)
                },
              })
            } else {
              this.ReaderPendingPage(index)
            }
          }
        },
        (index: number) => `${index}-${this.readerImageIdentityKey(this.vm.imageAt(index))}`,
      )
    }
    .width('100%')
    .height('100%')
    .cachedCount(2)
    .scrollBar(BarState.Off)
    .onScrollIndex((start: number, end: number) => {
      this.vm.onVerticalScroll(start, end)
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

  private modeIcon(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('sys.symbol.arrow_left')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('sys.symbol.arrow_down')
    }
    return $r('sys.symbol.arrow_right')
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

  private columnModeIconColor(): ResourceColor {
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('sys.color.font_tertiary')
    }
    if (this.readMode.columnMode === ReadColumnMode.SINGLE) {
      return Color.White
    }
    return ThemeConstants.BRAND_PRIMARY
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
    this.clearZoomGate()
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
    return `${img.page}-${img.sUrl}-${img.thumbUrl}`
  }

  private jumpToThumb(index: number): void {
    this.jumpToPage(index)
    this.scrollThumbStripTo(index, true)
  }

  private toggleThumbStrip(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, () => {
      this.showThumbStrip = !this.showThumbStrip
    })
    if (!this.showThumbStrip) {
      setTimeout(() => {
        this.scrollThumbStripTo(this.vm.currentIndex, false)
      }, 0)
    }
  }

  private scrollThumbStripTo(index: number, animated: boolean): void {
    if (!this.showThumbStrip || index < 0 || index >= this.vm.totalPages()) {
      return
    }
    this.thumbScroller.scrollToIndex(index, animated)
  }

  private thumbPageIndexes(): number[] {
    const total: number = this.vm.totalPages()
    const out: number[] = []
    for (let i: number = 0; i < total; i++) {
      out.push(i)
    }
    return out
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
          .fontSize(READER_CHROME_ICON_SIZE)
          .fontColor([Color.White])
      }
      .width(READER_CHROME_ACTION_SIZE)
      .height(READER_CHROME_ACTION_SIZE)
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
          .fontSize(READER_CHROME_ICON_SIZE)
          .fontColor([Color.White])
      }
      .width(READER_CHROME_ACTION_SIZE)
      .height(READER_CHROME_ACTION_SIZE)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.shareCurrentImage()
      })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(READER_CHROME_ICON_SIZE)
          .fontColor([Color.White])
      }
      .width(READER_CHROME_ACTION_SIZE)
      .height(READER_CHROME_ACTION_SIZE)
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
    .hitTestBehavior(HitTestMode.Default)
  }

  // Bottom chrome bar: progress first, then one coherent toolbar family. FE keeps save / double /
  // auto / thumbs as equal-width controller buttons; NextE keeps the same action hierarchy with
  // neutral toolbar icons instead of a primary action button.
  @Builder
  ReaderBottomBar() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.showThumbStrip) {
          this.ReaderThumbStrip()
        }
      }
      .width('100%')
      .height(READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2)
      .padding({
        left: ThemeConstants.SPACE_LG,
        right: ThemeConstants.SPACE_LG,
        top: ThemeConstants.SPACE_SM,
        bottom: ThemeConstants.SPACE_SM,
      })
      .margin({
        bottom: this.layout.bottomAvoidHeight + READER_BOTTOM_TOOLBAR_HEIGHT,
      })
      .backgroundColor('#CC000000')
      .visibility(this.showThumbStrip ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(this.showThumbStrip ? HitTestMode.Default : HitTestMode.None)

      Column({ space: ThemeConstants.SPACE_XS }) {
        Row({ space: READER_PROGRESS_SLIDER_GAP }) {
          Text(`${this.sliderPreview >= 0 ? this.sliderPreview : this.sliderValue}`)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(Color.White)
            .constraintSize({ minWidth: READER_PROGRESS_NUMBER_MIN_W })
            .textAlign(TextAlign.Start)
            .maxLines(1)
          Slider({
            value: this.sliderValue,
            min: 1,
            max: this.vm.totalPages() > 1 ? this.vm.totalPages() : 1,
            step: 1,
            style: SliderStyle.InSet,
          })
            .layoutWeight(1)
            .trackColor(READER_CHROME_TRACK_BG)
            .selectedColor(ThemeConstants.BRAND_PRIMARY)
            .onChange((value: number, mode: SliderChangeMode) => {
              const page: number = Math.round(value)
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.sliderPreview = page
                this.sliderValue = page
                this.scrollThumbStripTo(this.sliderTargetIndex(page), true)
              } else {
                this.sliderPreview = -1
                this.sliderValue = page
                const targetIndex: number = this.sliderTargetIndex(page)
                this.jumpToPage(targetIndex)
                this.scrollThumbStripTo(targetIndex, true)
              }
            })
          Text(`${this.vm.totalPages()}`)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(Color.White)
            .constraintSize({ minWidth: READER_PROGRESS_NUMBER_MIN_W })
            .textAlign(TextAlign.End)
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Button({ type: ButtonType.Circle }) {
            if (this.savingCurrentImage) {
              LoadingProgress()
                .width(READER_CHROME_ICON_SIZE)
                .height(READER_CHROME_ICON_SIZE)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
                .fontSize(READER_CHROME_ICON_SIZE)
                .fontColor([Color.White])
            }
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.saveCurrentImage()
          })
          Button({ type: ButtonType.Circle }) {
            if (this.originalImageResolving) {
              LoadingProgress()
                .width(READER_CHROME_ICON_SIZE)
                .height(READER_CHROME_ICON_SIZE)
                .color(ThemeConstants.BRAND_PRIMARY)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_outward_and_rectangle'))
                .fontSize(READER_CHROME_ICON_SIZE)
                .fontColor([this.originalButtonColor()])
            }
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleOriginalImage()
          })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([this.autoReadActive ? ThemeConstants.BRAND_PRIMARY : Color.White])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleAutoRead()
          })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([this.showThumbStrip ? ThemeConstants.BRAND_PRIMARY : Color.White])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleThumbStrip()
          })
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.modeIcon())
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([Color.White])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.cycleMode()
          })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.rectangle_grid_1x2'))
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([this.columnModeIconColor()])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(
            Color.Transparent
          )
          .enabled(this.readMode.mode !== ReadMode.VERTICAL)
          .onClick(() => {
            this.cycleColumnMode()
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(this.layout.bottomAvoidHeight + READER_BOTTOM_TOOLBAR_HEIGHT)
      .padding({
        left: ThemeConstants.SPACE_LG,
        right: ThemeConstants.SPACE_LG,
        top: ThemeConstants.SPACE_SM,
        bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_SM,
      })
      .backgroundColor('#CC000000')
    }
    .width('100%')
    .height(this.layout.bottomAvoidHeight + READER_BOTTOM_TOOLBAR_HEIGHT +
      READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  ReaderThumbStrip() {
    List({ initialIndex: this.vm.currentIndex, scroller: this.thumbScroller, space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.thumbPageIndexes(),
        (index: number) => {
          ListItem() {
            this.ReaderThumbItem(index)
          }
        },
        (index: number) => `${index}-${this.thumbKey(this.vm.imageAt(index))}`,
      )
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .height(READER_THUMB_STRIP_HEIGHT)
    .width('100%')
  }

  @Builder
  ReaderThumbItem(index: number) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      this.ReaderThumbImage(index, this.vm.imageAt(index))
      Text(`${index + 1}`)
        .fontSize(ThemeConstants.FONT_SIZE_META)
        .fontColor(index === this.vm.currentIndex ? ThemeConstants.BRAND_PRIMARY : Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .height(18)
        .textAlign(TextAlign.Center)
    }
    .width(76)
    .height(READER_THUMB_STRIP_HEIGHT)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.jumpToThumb(index)
    })
  }

  @Builder
  ReaderThumbImage(index: number, image: EhGalleryImage) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.hasRenderableThumb(image)) {
        EhSpriteThumbnail({
          url: image.thumbUrl,
          thumbWidth: image.thumbWidth,
          thumbHeight: image.thumbHeight,
          offsetX: image.thumbOffsetX,
          spriteWidth: image.spriteWidth,
          spriteHeight: image.spriteHeight,
          displayHeight: 58,
          fitHeight: true,
          radius: ThemeConstants.RADIUS_SM,
        })
      } else {
        Stack() {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(Color.White)
        }
        .width(44)
        .height(58)
        .backgroundColor('#26FFFFFF')
        .borderRadius(ThemeConstants.RADIUS_SM)
        .onAppear(() => {
          DiagnosticLogger.info(
            'reader',
            'thumb_placeholder_appear',
            `index ${index} page ${image.page} sUrl ${image.sUrl.length} thumb ${image.thumbUrl.length}`,
          )
          this.vm.warmPreviewForIndex(index, 'thumb-strip')
        })
      }
    }
    .height(58)
    .constraintSize({ minWidth: 42, maxWidth: 72 })
    .border({
      width: index === this.vm.currentIndex ? 2 : 0,
      color: index === this.vm.currentIndex ? ThemeConstants.BRAND_PRIMARY : Color.Transparent,
    })
    .borderRadius(ThemeConstants.RADIUS_SM)
    .clip(true)
  }
}

const MAX_SCALE: number = 4
const DOUBLE_TAP_SCALE: number = 2.5
const IMAGE_AUTO_RETRY_LIMIT: number = 3

class ReaderZoomCoordinator {
  static isZoomed(scale: number): boolean {
    return scale > 1.01
  }

  static clampScale(value: number): number {
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

  static fitScale(
    viewportW: number,
    viewportH: number,
    intrinsicW: number,
    intrinsicH: number
  ): number {
    if (viewportW <= 0 || viewportH <= 0 || intrinsicW <= 0 || intrinsicH <= 0) {
      return 1
    }
    const scaleW: number = viewportW / intrinsicW
    const scaleH: number = viewportH / intrinsicH
    const fit: number = Math.min(scaleW, scaleH)
    return fit > 0 ? fit : 1
  }

  static displaySize(viewport: number, intrinsic: number, fitScale: number): number {
    if (intrinsic <= 0 || fitScale <= 0) {
      return viewport
    }
    return intrinsic * fitScale
  }

  static maxOffset(viewport: number, displaySize: number, scale: number): number {
    const overflow: number = displaySize * scale - viewport
    return overflow > 0 ? overflow / 2 : 0
  }

  static clampOffset(value: number, viewport: number, displaySize: number, scale: number): number {
    const max: number = ReaderZoomCoordinator.maxOffset(viewport, displaySize, scale)
    if (value > max) {
      return max
    }
    if (value < -max) {
      return -max
    }
    return value
  }

  static panDistance(scale: number, viewportW: number, viewportH: number): number {
    if (ReaderZoomCoordinator.isZoomed(scale)) {
      return 1
    }
    const longSide: number = Math.max(viewportW, viewportH)
    return longSide > 0 ? longSide * 2 : 10000
  }

  static doubleTapTarget(currentScale: number): number {
    return ReaderZoomCoordinator.isZoomed(currentScale) ? 1 : DOUBLE_TAP_SCALE
  }

  static doubleTapOffset(tap: number, viewport: number, targetScale: number): number {
    return (1 - targetScale) * (tap - viewport / 2)
  }

  static pinchOffset(
    pinchCenterStart: number,
    viewport: number,
    scaleRatio: number,
    startOffset: number,
    centerDrift: number
  ): number {
    return (pinchCenterStart - viewport / 2) * (1 - scaleRatio) + scaleRatio * startOffset + centerDrift
  }
}

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

@ComponentV2
struct ReaderSpreadSurface {
  @Param first: EhGalleryImage = new EhGalleryImage();
  @Param second: EhGalleryImage = new EhGalleryImage();
  @Param hasFirst: boolean = false;
  @Param hasSecond: boolean = false;
  @Param firstPreferOriginal: boolean = false;
  @Param secondPreferOriginal: boolean = false;
  @Param firstInitiallyLoaded: boolean = false;
  @Param secondInitiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param rowReversed: boolean = false;
  @Param activeIndex: number = 0;
  @Param doubleTapSeq: number = 0;
  @Param doubleTapX: number = 0;
  @Param doubleTapY: number = 0;
  @Param doubleTapTargetPage: number = 0;
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};

  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local zoomAnimating: boolean = false;
  @Local firstIntrinsicW: number = 0;
  @Local firstIntrinsicH: number = 0;
  @Local secondIntrinsicW: number = 0;
  @Local secondIntrinsicH: number = 0;

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
  private zoomAnimatingTimerId: number = 0;

  private includesPage(page: number): boolean {
    if (this.hasFirst && this.first.page === page) {
      return true
    }
    return this.hasSecond && this.second.page === page
  }

  @Monitor('doubleTapSeq')
  onDoubleTapCommand(): void {
    const targetPage: number = this.doubleTapTargetPage > 0 ? this.doubleTapTargetPage : this.activeIndex + 1
    if (!this.includesPage(targetPage)) {
      return
    }
    this.onDoubleTap(this.doubleTapX, this.doubleTapY)
  }

  @Monitor('activeIndex')
  onActiveIndexChanged(): void {
    if (!this.includesPage(this.activeIndex + 1)) {
      this.resetZoom()
      this.notifyZoom()
    }
  }

  private clampScale(value: number): number {
    return ReaderZoomCoordinator.clampScale(value)
  }

  private paneCount(): number {
    return this.hasSecond ? 2 : 1
  }

  private paneWidth(): number {
    const count: number = this.paneCount()
    if (count <= 1) {
      return this.compW
    }
    const contentWidth: number = this.compW - ThemeConstants.SPACE_XS
    return contentWidth > 0 ? contentWidth / count : this.compW / count
  }

  private imageDisplayW(intrinsicW: number, intrinsicH: number): number {
    const fit: number = ReaderZoomCoordinator.fitScale(this.paneWidth(), this.compH, intrinsicW, intrinsicH)
    return ReaderZoomCoordinator.displaySize(this.paneWidth(), intrinsicW, fit)
  }

  private imageDisplayH(intrinsicW: number, intrinsicH: number): number {
    const fit: number = ReaderZoomCoordinator.fitScale(this.paneWidth(), this.compH, intrinsicW, intrinsicH)
    return ReaderZoomCoordinator.displaySize(this.compH, intrinsicH, fit)
  }

  private displayW(): number {
    const firstW: number = this.hasFirst ? this.imageDisplayW(this.firstIntrinsicW, this.firstIntrinsicH) : 0
    const secondW: number = this.hasSecond ? this.imageDisplayW(this.secondIntrinsicW, this.secondIntrinsicH) : 0
    const gap: number = this.hasFirst && this.hasSecond ? ThemeConstants.SPACE_XS : 0
    const total: number = firstW + secondW + gap
    return total > 0 ? total : this.compW
  }

  private displayH(): number {
    const firstH: number = this.hasFirst ? this.imageDisplayH(this.firstIntrinsicW, this.firstIntrinsicH) : 0
    const secondH: number = this.hasSecond ? this.imageDisplayH(this.secondIntrinsicW, this.secondIntrinsicH) : 0
    const total: number = Math.max(firstH, secondH)
    return total > 0 ? total : this.compH
  }

  private clampOffsetX(value: number, scale: number): number {
    return ReaderZoomCoordinator.clampOffset(value, this.compW, this.displayW(), scale)
  }

  private clampOffsetY(value: number, scale: number): number {
    return ReaderZoomCoordinator.clampOffset(value, this.compH, this.displayH(), scale)
  }

  private panDistance(): number {
    return ReaderZoomCoordinator.panDistance(this.zoomScale, this.compW, this.compH)
  }

  private clampOffset(): void {
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
  }

  private resetZoom(): void {
    this.zoomScale = 1
    this.offsetX = 0
    this.offsetY = 0
  }

  private beginZoomAnimation(): void {
    if (this.zoomAnimatingTimerId > 0) {
      clearTimeout(this.zoomAnimatingTimerId)
      this.zoomAnimatingTimerId = 0
    }
    this.zoomAnimating = true
    this.zoomAnimatingTimerId = setTimeout((): void => {
      this.zoomAnimating = false
      this.zoomAnimatingTimerId = 0
    }, READER_ZOOM_ANIM_DURATION + ThemeConstants.ANIM_DONE_DELAY_MS)
  }

  private notifyZoom(): void {
    const zoomed: boolean = ReaderZoomCoordinator.isZoomed(this.zoomScale)
    if (zoomed !== this.lastZoomed) {
      this.lastZoomed = zoomed
      this.onZoomChange(zoomed)
    }
  }

  private onDoubleTap(tapX: number, tapY: number): void {
    this.beginZoomAnimation()
    if (ReaderZoomCoordinator.doubleTapTarget(this.zoomScale) === 1) {
      this.resetZoom()
      this.notifyZoom()
      return
    }
    const target: number = DOUBLE_TAP_SCALE
    const nextX: number = ReaderZoomCoordinator.doubleTapOffset(tapX, this.compW, target)
    const nextY: number = ReaderZoomCoordinator.doubleTapOffset(tapY, this.compH, target)
    this.zoomScale = target
    this.offsetX = this.clampOffsetX(nextX, target)
    this.offsetY = this.clampOffsetY(nextY, target)
    this.notifyZoom()
  }

  private recordImageMetrics(page: number, width: number, height: number): void {
    const w: number = this.getUIContext().px2vp(width)
    const h: number = this.getUIContext().px2vp(height)
    if (this.hasFirst && this.first.page === page) {
      this.firstIntrinsicW = w
      this.firstIntrinsicH = h
    } else if (this.hasSecond && this.second.page === page) {
      this.secondIntrinsicW = w
      this.secondIntrinsicH = h
    }
    this.clampOffset()
  }

  @Builder
  SpreadImageLayer(image: EhGalleryImage, hasImage: boolean, preferOriginal: boolean, initiallyLoaded: boolean) {
    if (hasImage) {
      ReaderSpreadImageLayer({
        image: image,
        imageKey: `${image.page}-${image.sUrl}-${image.imageUrl}-${preferOriginal ? 'orig' : 'fit'}`,
        preferOriginal: preferOriginal,
        initiallyLoaded: initiallyLoaded,
        loadedSignal: this.loadedSignal,
        onImageLoaded: (page: number) => {
          this.onImageLoaded(page)
        },
        onImageMetrics: (page: number, width: number, height: number) => {
          this.recordImageMetrics(page, width, height)
        },
      })
        .layoutWeight(1)
    } else {
      Blank()
        .layoutWeight(1)
    }
  }

  build() {
    Stack() {
      Row({ space: ThemeConstants.SPACE_XS }) {
        if (this.rowReversed) {
          this.SpreadImageLayer(this.second, this.hasSecond, this.secondPreferOriginal, this.secondInitiallyLoaded)
          this.SpreadImageLayer(this.first, this.hasFirst, this.firstPreferOriginal, this.firstInitiallyLoaded)
        } else {
          this.SpreadImageLayer(this.first, this.hasFirst, this.firstPreferOriginal, this.firstInitiallyLoaded)
          this.SpreadImageLayer(this.second, this.hasSecond, this.secondPreferOriginal, this.secondInitiallyLoaded)
        }
      }
      .width('100%')
      .height('100%')
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.offsetX, y: this.offsetY })
      .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_o: Area, n: Area) => {
      this.compW = n.width as number
      this.compH = n.height as number
      this.clampOffset()
    })
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
            const nextX: number = ReaderZoomCoordinator.pinchOffset(
              this.pinchCenterStartX,
              this.compW,
              k,
              this.pinchStartOffX,
              dx
            )
            const nextY: number = ReaderZoomCoordinator.pinchOffset(
              this.pinchCenterStartY,
              this.compH,
              k,
              this.pinchStartOffY,
              dy
            )
            this.zoomScale = nextScale
            this.offsetX = this.clampOffsetX(nextX, nextScale)
            this.offsetY = this.clampOffsetY(nextY, nextScale)
            this.notifyZoom()
          })
          .onActionEnd(() => {
            this.isPinching = false
            if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          })
          .onActionCancel(() => {
            this.isPinching = false
            this.clampOffset()
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: this.panDistance() })
          .onActionStart(() => {
            this.panStartOffX = this.offsetX
            this.panStartOffY = this.offsetY
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e || this.isPinching || !ReaderZoomCoordinator.isZoomed(this.zoomScale)) {
              return
            }
            this.offsetX = this.clampOffsetX(this.panStartOffX + (e.offsetX as number), this.zoomScale)
            this.offsetY = this.clampOffsetY(this.panStartOffY + (e.offsetY as number), this.zoomScale)
          }),
      ),
    )
  }
}

@ComponentV2
struct ReaderSpreadImageLayer {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Param imageKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageMetrics: (page: number, width: number, height: number) => void =
    (_page: number, _width: number, _height: number) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  private autoRetryCount: number = 0;
  private loadSeq: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  @Monitor('imageKey')
  onImageKeyChanged(): void {
    this.resetImageState()
    this.resolve()
  }

  @Monitor('preferOriginal')
  onPreferOriginalChanged(): void {
    this.resetImageState()
    this.resolve()
  }

  @Monitor('loadedSignal')
  onLoadedSignalChanged(): void {
    if (this.initiallyLoaded && this.imageUrl.length > 0) {
      this.imageLoaded = true
    }
  }

  private resetImageState(): void {
    this.autoRetryCount = 0
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
  }

  private async resolve(changeSource: boolean = false): Promise<void> {
    if (!changeSource && this.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(this.image)
        DiagnosticLogger.info('reader', 'display_original', `page ${this.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(original)
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'spread_original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && this.image.imageUrl.length > 0) {
      await this.loadResolvedImage(this.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(this.image, changeSource)
      await this.loadResolvedImage(resolved)
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'spread_resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(resolved: string): Promise<void> {
    const seq: number = ++this.loadSeq
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheKey: string = this.cacheKey(resolved)
    const cached: CachedImageFileResult | null = CachedImageFileService.cached(context, resolved, cacheKey)
    if (cached !== null) {
      this.sourceImageUrl = resolved
      this.imageUrl = cached.displayUri
      this.imageLoaded = true
      this.imageProgressLoaded = cached.bytes
      this.imageProgressTotal = cached.bytes
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
      DiagnosticLogger.info('image-cache', 'reader_display_hit', `page ${this.image.page} ${cached.bytes} bytes`)
      return
    }
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result = await CachedImageFileService.load(
      context,
      resolved,
      cacheKey,
      (progress: CachedImageProgress) => {
        if (seq !== this.loadSeq) {
          return
        }
        this.imageProgressLoaded = progress.loaded
        this.imageProgressTotal = progress.total
      },
    )
    if (seq !== this.loadSeq) {
      return
    }
    this.imageUrl = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
  }

  private cacheKey(resolved: string): string {
    return `${this.image.page}-${this.imageKey}-${resolved}`
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    if (this.sourceImageUrl.length > 0) {
      CachedImageFileService.remove(
        this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.sourceImageUrl,
        this.cacheKey(this.sourceImageUrl),
      )
    }
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.loadSeq++
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  build() {
    Stack() {
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
          .interpolation(ImageInterpolation.High)
          .width('100%')
          .height('100%')
          .draggable(false)
          .onComplete((_event?: ReaderImageLoadEvent) => {
            this.autoRetryCount = 0
            this.imageLoaded = true
            this.onImageLoaded(this.image.page)
            if (_event && _event.width && _event.height) {
              this.onImageMetrics(this.image.page, _event.width, _event.height)
            } else if (_event && _event.componentWidth && _event.componentHeight) {
              this.onImageMetrics(this.image.page, _event.componentWidth, _event.componentHeight)
            }
          })
          .onError(() => {
            DiagnosticLogger.warn('reader', 'spread_image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          })
      } else if (this.sourceImageUrl.length > 0) {
        ReaderLoadingStage({
          label: $r('app.string.reader_loading_image'),
          loaded: this.imageProgressLoaded,
          total: this.imageProgressTotal,
        })
      } else {
        ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
      }
    }
    .width('100%')
    .height('100%')
  }
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
  @Param imageKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param activeIndex: number = 0;
  @Param doubleTapSeq: number = 0;
  @Param doubleTapX: number = 0;
  @Param doubleTapY: number = 0;
  @Param doubleTapTargetPage: number = 0;
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local zoomAnimating: boolean = false;
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
  private loadSeq: number = 0;
  private zoomAnimatingTimerId: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  @Monitor('imageKey')
  onImageKeyChanged(): void {
    this.resetSourceState()
    this.resetZoom()
    this.notifyZoom()
    this.resolve()
  }

  @Monitor('preferOriginal')
  onPreferOriginalChanged(): void {
    this.resetSourceState()
    this.resolve()
  }

  @Monitor('loadedSignal')
  onLoadedSignalChanged(): void {
    if (this.initiallyLoaded && this.imageUrl.length > 0) {
      this.imageLoaded = true
    }
  }

  @Monitor('doubleTapSeq')
  onDoubleTapCommand(): void {
    const targetPage: number = this.doubleTapTargetPage > 0 ? this.doubleTapTargetPage : this.activeIndex + 1
    if (this.image.page !== targetPage) {
      return
    }
    this.onDoubleTap(this.doubleTapX, this.doubleTapY)
  }

  @Monitor('activeIndex')
  onActiveIndexChanged(): void {
    if (this.image.page !== this.activeIndex + 1) {
      this.resetZoom()
      this.notifyZoom()
    }
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) — re-resolves via /s/?nl= for a
  // different host, bypassing the cached URL.
  private async resolve(changeSource: boolean = false): Promise<void> {
    if (!changeSource && this.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(this.image)
        DiagnosticLogger.info('reader', 'display_original', `page ${this.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(original)
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && this.image.imageUrl.length > 0) {
      await this.loadResolvedImage(this.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(this.image, changeSource)
      await this.loadResolvedImage(resolved)
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(resolved: string): Promise<void> {
    const seq: number = ++this.loadSeq
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheKey: string = this.cacheKey(resolved)
    const cached: CachedImageFileResult | null = CachedImageFileService.cached(context, resolved, cacheKey)
    if (cached !== null) {
      this.sourceImageUrl = resolved
      this.imageUrl = cached.displayUri
      this.imageLoaded = true
      this.imageProgressLoaded = cached.bytes
      this.imageProgressTotal = cached.bytes
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
      DiagnosticLogger.info('image-cache', 'reader_display_hit', `page ${this.image.page} ${cached.bytes} bytes`)
      return
    }
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result = await CachedImageFileService.load(
      context,
      resolved,
      cacheKey,
      (progress: CachedImageProgress) => {
        if (seq !== this.loadSeq) {
          return
        }
        this.imageProgressLoaded = progress.loaded
        this.imageProgressTotal = progress.total
      },
    )
    if (seq !== this.loadSeq) {
      return
    }
    this.imageUrl = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
  }

  private cacheKey(resolved: string): string {
    return `${this.image.page}-${this.imageKey}-${resolved}`
  }

  private resetSourceState(): void {
    this.autoRetryCount = 0
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.intrinsicW = 0
    this.intrinsicH = 0
  }

  // Retry on failure: re-source (换源) — clear the dead URL and re-resolve from a different host.
  private retrySource(): void {
    this.autoRetryCount = 0
    if (this.sourceImageUrl.length > 0) {
      CachedImageFileService.remove(
        this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.sourceImageUrl,
        this.cacheKey(this.sourceImageUrl),
      )
    }
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.loadSeq++
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
      this.failed = false
      this.resolve(true)
      return
    }
    this.failed = true
  }

  private clampScale(value: number): number {
    return ReaderZoomCoordinator.clampScale(value)
  }

  private fitScale(): number {
    return ReaderZoomCoordinator.fitScale(this.compW, this.compH, this.intrinsicW, this.intrinsicH)
  }

  private displayW(): number {
    return ReaderZoomCoordinator.displaySize(this.compW, this.intrinsicW, this.fitScale())
  }

  private displayH(): number {
    return ReaderZoomCoordinator.displaySize(this.compH, this.intrinsicH, this.fitScale())
  }

  private maxOffset(viewport: number, displaySize: number, scale: number): number {
    return ReaderZoomCoordinator.maxOffset(viewport, displaySize, scale)
  }

  private clampOffsetX(value: number, scale: number): number {
    return ReaderZoomCoordinator.clampOffset(value, this.compW, this.displayW(), scale)
  }

  private clampOffsetY(value: number, scale: number): number {
    return ReaderZoomCoordinator.clampOffset(value, this.compH, this.displayH(), scale)
  }

  private panDistance(): number {
    return ReaderZoomCoordinator.panDistance(this.zoomScale, this.compW, this.compH)
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

  private beginZoomAnimation(): void {
    if (this.zoomAnimatingTimerId > 0) {
      clearTimeout(this.zoomAnimatingTimerId)
      this.zoomAnimatingTimerId = 0
    }
    this.zoomAnimating = true
    this.zoomAnimatingTimerId = setTimeout((): void => {
      this.zoomAnimating = false
      this.zoomAnimatingTimerId = 0
    }, READER_ZOOM_ANIM_DURATION + ThemeConstants.ANIM_DONE_DELAY_MS)
  }

  private notifyZoom(): void {
    const zoomed: boolean = ReaderZoomCoordinator.isZoomed(this.zoomScale)
    if (zoomed !== this.lastZoomed) {
      this.lastZoomed = zoomed
      this.onZoomChange(zoomed)
    }
  }

  private onDoubleTap(tapX: number, tapY: number): void {
    this.beginZoomAnimation()
    if (ReaderZoomCoordinator.doubleTapTarget(this.zoomScale) === 1) {
      this.resetZoom()
      this.notifyZoom()
    } else {
      const target: number = DOUBLE_TAP_SCALE
      const nextX: number = ReaderZoomCoordinator.doubleTapOffset(tapX, this.compW, target)
      const nextY: number = ReaderZoomCoordinator.doubleTapOffset(tapY, this.compH, target)
      this.zoomScale = target
      this.baseZoom = target
      this.offsetX = this.clampOffsetX(nextX, target)
      this.offsetY = this.clampOffsetY(nextY, target)
      this.baseOffsetX = this.offsetX
      this.baseOffsetY = this.offsetY
      this.notifyZoom()
    }
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
          .interpolation(ImageInterpolation.High)
          .width('100%')
          .height('100%')
          .draggable(false)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.offsetX, y: this.offsetY })
          .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
          .onComplete((event?: ReaderImageLoadEvent) => {
            if (event && event.width && event.height) {
              this.intrinsicW = this.getUIContext().px2vp(event.width)
              this.intrinsicH = this.getUIContext().px2vp(event.height)
              DiagnosticLogger.info(
                'reader',
                'image_decoded',
                `page=${this.image.page} width=${event.width} height=${event.height} urlHash=${DiagnosticLogger.ownerHash(this.imageUrl)}`,
              )
            } else if (event && event.componentWidth && event.componentHeight) {
              this.intrinsicW = event.componentWidth
              this.intrinsicH = event.componentHeight
              DiagnosticLogger.info(
                'reader',
                'image_decoded_component',
                `page=${this.image.page} width=${event.componentWidth} height=${event.componentHeight} urlHash=${DiagnosticLogger.ownerHash(this.imageUrl)}`,
              )
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
      } else if (this.sourceImageUrl.length > 0) {
        ReaderLoadingStage({
          label: $r('app.string.reader_loading_image'),
          loaded: this.imageProgressLoaded,
          total: this.imageProgressTotal,
        })
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
    // The image surface owns pinch and double-tap zoom. Zoomed pan is a parallel one-finger
    // gesture so fit-state horizontal drags can still reach the ancestor Swiper.
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
            const nextX: number = ReaderZoomCoordinator.pinchOffset(
              this.pinchCenterStartX,
              this.compW,
              k,
              this.pinchStartOffX,
              dx
            )
            const nextY: number = ReaderZoomCoordinator.pinchOffset(
              this.pinchCenterStartY,
              this.compH,
              k,
              this.pinchStartOffY,
              dy
            )
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
          if (!e || this.isPinching || !ReaderZoomCoordinator.isZoomed(this.zoomScale)) {
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
  @Param imageKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local ratio: number = DEFAULT_VERTICAL_RATIO;
  private autoRetryCount: number = 0;
  private loadSeq: number = 0;

  aboutToAppear(): void {
    this.resolve()
  }

  @Monitor('imageKey')
  onImageKeyChanged(): void {
    this.resetSourceState()
    this.resolve()
  }

  @Monitor('preferOriginal')
  onPreferOriginalChanged(): void {
    this.resetSourceState()
    this.resolve()
  }

  @Monitor('loadedSignal')
  onLoadedSignalChanged(): void {
    if (this.initiallyLoaded && this.imageUrl.length > 0) {
      this.imageLoaded = true
    }
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) via /s/?nl=, bypassing the cache.
  private async resolve(changeSource: boolean = false): Promise<void> {
    if (!changeSource && this.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(this.image)
        DiagnosticLogger.info('reader', 'display_original', `page ${this.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(original)
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'vertical_original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && this.image.imageUrl.length > 0) {
      await this.loadResolvedImage(this.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(this.image, changeSource)
      await this.loadResolvedImage(resolved)
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(resolved: string): Promise<void> {
    const seq: number = ++this.loadSeq
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const cacheKey: string = this.cacheKey(resolved)
    const cached: CachedImageFileResult | null = CachedImageFileService.cached(context, resolved, cacheKey)
    if (cached !== null) {
      this.sourceImageUrl = resolved
      this.imageUrl = cached.displayUri
      this.imageLoaded = true
      this.imageProgressLoaded = cached.bytes
      this.imageProgressTotal = cached.bytes
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
      DiagnosticLogger.info('image-cache', 'reader_display_hit', `page ${this.image.page} ${cached.bytes} bytes`)
      return
    }
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result = await CachedImageFileService.load(
      context,
      resolved,
      cacheKey,
      (progress: CachedImageProgress) => {
        if (seq !== this.loadSeq) {
          return
        }
        this.imageProgressLoaded = progress.loaded
        this.imageProgressTotal = progress.total
      },
    )
    if (seq !== this.loadSeq) {
      return
    }
    this.imageUrl = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
  }

  private cacheKey(resolved: string): string {
    return `${this.image.page}-${this.imageKey}-${resolved}`
  }

  private resetSourceState(): void {
    this.autoRetryCount = 0
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.ratio = DEFAULT_VERTICAL_RATIO
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    if (this.sourceImageUrl.length > 0) {
      CachedImageFileService.remove(
        this.getUIContext().getHostContext() as common.UIAbilityContext,
        this.sourceImageUrl,
        this.cacheKey(this.sourceImageUrl),
      )
    }
    this.loadSeq++
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(true)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      this.autoRetryCount++
      this.loadSeq++
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
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
          .interpolation(ImageInterpolation.High)
          .draggable(false)
          .onComplete((e) => {
            this.autoRetryCount = 0
            this.imageLoaded = true
            this.onImageLoaded(this.image.page)
            if (e !== undefined && e.width > 0 && e.height > 0) {
              this.ratio = e.width / e.height
              DiagnosticLogger.info(
                'reader',
                'image_decoded',
                `page=${this.image.page} width=${e.width} height=${e.height} urlHash=${DiagnosticLogger.ownerHash(this.imageUrl)}`,
              )
            }
          })
          .onError(() => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          })
      } else if (this.sourceImageUrl.length > 0) {
        ReaderLoadingStage({
          label: $r('app.string.reader_loading_image'),
          compact: true,
          loaded: this.imageProgressLoaded,
          total: this.imageProgressTotal,
        })
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
  @Param loaded: number = 0;
  @Param total: number = 0;

  private barWidth(): number {
    return this.compact ? 120 : 180
  }

  private hasProgress(): boolean {
    return this.total > 0
  }

  private progressRatio(): number {
    if (!this.hasProgress()) {
      return 0.32
    }
    const ratio: number = this.loaded / this.total
    if (ratio < 0) {
      return 0
    }
    if (ratio > 1) {
      return 1
    }
    return ratio
  }

  private progressPercent(): string {
    return `${Math.round(this.progressRatio() * 100)}%`
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      if (this.hasProgress()) {
        Row() {
          Blank()
            .width(this.barWidth() * this.progressRatio())
            .height(4)
            .backgroundColor(Color.White)
            .borderRadius(2)
          Blank()
            .layoutWeight(1)
            .height(4)
        }
        .width(this.barWidth())
        .height(4)
        .backgroundColor('#33FFFFFF')
        .borderRadius(2)
      } else {
        LoadingProgress()
          .width(this.compact ? 24 : 28)
          .height(this.compact ? 24 : 28)
          .color(Color.White)
      }
      Text(this.label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
      if (this.hasProgress()) {
        Text(this.progressPercent())
          .fontSize(ThemeConstants.FONT_SIZE_META)
          .fontColor('#CCFFFFFF')
          .textAlign(TextAlign.Center)
      }
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
