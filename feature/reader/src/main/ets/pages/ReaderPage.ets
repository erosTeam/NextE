import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SymbolGlyphModifier, window } from '@kit.ArkUI'
import { KeyCode } from '@kit.InputKit'
import { fileIo } from '@kit.CoreFileKit'
import inputConsumer from '@ohos.multimodalInput.inputConsumer'
import { Action, KeyEvent as InputConsumerKeyEvent } from '@ohos.multimodalInput.keyEvent'
import {
  ThemeConstants,
  AppStrings,
  BasicDataSource,
  EhGalleryImage,
  EhImageKnifeImage,
  EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FIT,
  EH_IMAGE_PRIORITY_LOW,
  EhSpriteThumbnail,
  ReaderParams,
  ImageResolveService,
  ImagePipelineService,
  DiagnosticLogger,
  connectThemeDisplay,
  ThemeDisplayState,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  connectReadMode,
  ReadModeState,
  ReadMode,
  ReaderBackgroundMode,
  ReaderImageScalingQuality,
  ReadColumnMode,
  ReadSpreadLayout,
  ReaderTapZoneAction,
  ReaderTapZoneRegion,
  ReaderTapZoneResolver,
  ReadModeSettings,
  GalleryReadProgressSettings,
  connectGalleryReadProgress,
  connectReaderOverlayNavigation,
  connectSiteMode,
  ShareUtil,
  ImageSaveUtil,
  CachedImageProgress,
  CachedImageFileResult,
  ReaderSuperResolutionResult,
  ReaderSuperResolutionService,
  ReaderSuperResolutionTaskState,
  ReaderSuperResolutionModel,
  ImageBlockDecision,
  ImageBlockRuntimeService,
  ImageBlockSettingsState,
  connectImageBlockSettings,
  ReaderLocalSourceService,
  ReaderSourceKind,
  ReaderSourceVariant,
  appSheetOptions,
} from 'shared'
import { ReaderViewModel } from '../viewmodel/ReaderViewModel'
import { ReaderImageLoadPresentation } from '../model/ReaderImageLoadPresentation'
import { ReaderImageLoadPriority } from '../model/ReaderImageLoadPriority'
import { ReaderImageSourceRequest, ReaderImageSourceRequestGate } from '../model/ReaderImageSourceRequestGate'
import { ReaderSessionRequest } from '../model/ReaderSessionRequestGate'
import { ReaderThumbnailGeometry, ReaderThumbnailSize } from '../model/ReaderThumbnailGeometry'

const READER_KEY_SURFACE_ID: string = 'reader_key_surface'
const READER_CHROME_ACTION_SIZE: number = 44
const READER_CHROME_ICON_SIZE: number = 22
const READER_CHROME_TRACK_BG: ResourceColor = '#33FFFFFF'
const READER_THUMB_STRIP_HEIGHT: number = 140
const READER_BOTTOM_TOOLBAR_HEIGHT: number = 112
const READER_PROGRESS_NUMBER_MIN_W: number = 30
const READER_PROGRESS_SLIDER_GAP: number = 4
const READER_PROGRESS_ANIM_DURATION: number = 160
const READER_ZOOM_ANIM_DURATION: number = 180
const READER_LOADING_PROGRESS_ANIM_DURATION: number = 220
const READER_LOADING_COMPLETION_HOLD_MS: number = 160
const READER_LOADING_INDETERMINATE_ANIM_DURATION: number = 900
const READER_LOADING_BAR_HEIGHT: number = 4
const READER_LOADING_BAR_WIDTH_PERCENT: string = '80%'
const READER_LOADING_BAR_MAX_WIDTH: number = 180
const READER_LOADING_SLIDER_WIDTH_RATIO: number = 0.3
const READER_LOADING_BAR_RADIUS: number = 2
const READER_LOADING_BAR_BG: ResourceColor = '#33FFFFFF'
const READER_LOADING_BAR_LIGHT_BG: ResourceColor = '#33000000'
const READER_LOADING_BAR_FG: ResourceColor = Color.White
const READER_VERTICAL_TAP_MAX_DISTANCE: number = 8
const READER_VERTICAL_SINGLE_TAP_DELAY_MS: number = 240
const READER_TOUCH_TAP_SUPPRESS_MS: number = 350
const READER_TAP_ZONE_SCROLL_RATIO: number = 0.75
const READER_STATUS_BAR_LIGHT_CONTENT: string = '#FFFFFFFF'
const READER_ENTRY_STATUS_BAR_HIDE_DELAY_MS: number = 500
const READER_EXIT_STATUS_BAR_LEAD_MS: number = 20
const READER_DEFAULT_PRELOAD_PAGES: number = 2
const READER_MAX_PRELOAD_PAGES: number = 5
const READER_STATUS_BAR_DARK_CONTENT: string = '#FF000000'
const READER_FAILURE_HINT_DARK: ResourceColor = '#AAFFFFFF'
const READER_FAILURE_HINT_LIGHT: ResourceColor = '#AA000000'
const READER_FAILURE_PAGE_DARK: ResourceColor = '#88FFFFFF'
const READER_FAILURE_PAGE_LIGHT: ResourceColor = '#88000000'

function readerBackgroundIsDark(mode: string, effectiveDark: boolean): boolean {
  if (mode === ReaderBackgroundMode.WHITE) {
    return false
  }
  if (mode === ReaderBackgroundMode.AUTO) {
    return effectiveDark
  }
  return true
}

function readerBackgroundColor(mode: string, effectiveDark: boolean): ResourceColor {
  if (mode === ReaderBackgroundMode.GRAY) {
    return ThemeConstants.READER_BACKGROUND_GRAY
  }
  if (mode === ReaderBackgroundMode.WHITE) {
    return ThemeConstants.READER_BACKGROUND_WHITE
  }
  if (mode === ReaderBackgroundMode.AUTO) {
    return effectiveDark
      ? ThemeConstants.READER_BACKGROUND_BLACK
      : ThemeConstants.READER_BACKGROUND_WHITE
  }
  return ThemeConstants.READER_BACKGROUND_BLACK
}

function readerForegroundColor(mode: string, effectiveDark: boolean): ResourceColor {
  return readerBackgroundIsDark(mode, effectiveDark)
    ? ThemeConstants.READER_FOREGROUND_LIGHT
    : ThemeConstants.READER_FOREGROUND_DARK
}

function readerSecondaryForegroundColor(mode: string, effectiveDark: boolean): ResourceColor {
  return readerBackgroundIsDark(mode, effectiveDark)
    ? ThemeConstants.READER_FOREGROUND_LIGHT_SECONDARY
    : ThemeConstants.READER_FOREGROUND_DARK_SECONDARY
}

function readerImageInterpolation(quality: string): ImageInterpolation {
  if (quality === ReaderImageScalingQuality.LOW) {
    return ImageInterpolation.Low
  }
  if (quality === ReaderImageScalingQuality.HIGH) {
    return ImageInterpolation.High
  }
  return ImageInterpolation.Medium
}

function readerDelay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve()
    }, Math.max(0, Math.round(ms)))
  })
}

class ReaderSpreadResolver {
  static isDoublePage(mode: string, enabled: boolean): boolean {
    return (mode === ReadMode.LTR || mode === ReadMode.RTL) && enabled
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

  static sliderTargetIndex(page: number): number {
    return page - 1
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
  @BuilderParam settingsSheetContent: (dismiss: () => void) => void;
  @Local settingsSheetShown: boolean = false;
  @Local vm: ReaderViewModel = new ReaderViewModel();
  @Local params: ReaderParams = new ReaderParams();
  // eros_fe opens the reader with chrome HIDDEN (view_state.dart:165 showBar=false); a center tap
  // fades it in. Top bar (back/page-count/settings) + bottom bar (page-count/mode/slider) are native
  // flat-scrim bars, not the old hand-rolled floating glass card.
  @Local showChrome: boolean = false;
  @Local imageZoomed: boolean = false;
  @Local verticalZoomedPage: number = -1;
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
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Local autoReadActive: boolean = false;
  @Local showThumbStrip: boolean = false;
  @Local tapZonePreviewVisible: boolean = false;
  // Reader viewport size used by normalized tap-zone hit testing and continuous-mode page steps.
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  @Local loadedPageSignal: number = 0;
  @Local originalImagePages: string = '';
  @Local originalAvailablePages: string = '';
  @Local originalImageResolving: boolean = false;
  @Local savingCurrentImage: boolean = false;
  @Local saveSpreadMenuShown: boolean = false;
  @Local originalSpreadMenuShown: boolean = false;
  @Local imageBlockRuleSaving: boolean = false;
  @Local imageBlockWhitelistSaving: boolean = false;
  @Local currentImageBlockFilePath: string = '';
  @Local currentImageBlocked: boolean = false;
  @Local imageBlockRuleVersion: number = 0;
  @Local imageBlockActionMenuShown: boolean = false;
  @Local readModeMenuShown: boolean = false;
  @Local readerTopMoreMenuShown: boolean = false;
  @Local sourceReloadPage: number = 0;
  @Local sourceReloadRequestId: number = 0;
  // List.onScrollIndex reports the first and last screen-visible rows; its cached rows must not
  // compete with the image the reader is actually showing.
  @Local verticalVisibleStart: number = 0;
  @Local verticalVisibleEnd: number = 0;
  @Local imageMetricPages: number[] = [];
  @Local imageMetricWidths: number[] = [];
  @Local imageMetricHeights: number[] = [];
  @Local imageEnhancementPages: number[] = [];
  @Local imageEnhancementModels: string[] = [];
  @Local imageEnhancementApplied: boolean[] = [];
  @Local imageEnhancementReasons: string[] = [];
  @Local imageFilePages: number[] = [];
  @Local imageFileBytes: number[] = [];
  @Local imageFileFormats: string[] = [];
  @Local imageBlockSettings: ImageBlockSettingsState = connectImageBlockSettings();
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
  private imageBlockFilePages: number[] = [];
  private imageBlockFilePaths: string[] = [];
  private imageBlockStatePages: number[] = [];
  private imageBlockStateValues: boolean[] = [];
  private spreadDataSource: BasicDataSource<number> = new BasicDataSource<number>();
  private spreadDataSourceKey: string = '';
  private volumeDownConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;
  private volumeUpConsumer: ((event: InputConsumerKeyEvent) => void) | null = null;
  private readerClosing: boolean = false;
  private readerStatusBarHideTimerId: number = -1;
  private readerRouteEpoch: number = 0;
  private sliderSyncToken: number = 0;
  private readerTapStartX: number = 0;
  private readerTapStartY: number = 0;
  private readerTapSuppressUntilMs: number = 0;
  private readerRouteVisible: boolean = false;

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.readerContentReady()) {
          if (this.isContinuousVerticalMode()) {
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
              .fontColor(this.readerForegroundColor())
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
          if (!this.isLocalReaderSource()) {
            this.ReaderCacheWarmers()
          }
          if (!this.currentImageBlocked && !this.isContinuousVerticalMode()) {
            this.ReaderTapOverlay()
          }
          if (this.originalImageResolving) {
            ReaderLoadingStage({ label: $r('app.string.reader_loading_resolving') })
          }
        }

        if (this.readerContentReady() && this.tapZonePreviewVisible) {
          this.ReaderTapZonePreview()
        }

        if (this.readerContentReady() && !this.showChrome &&
          (this.readMode.showPageNumber || this.superResolutionIndicatorVisible())) {
          this.ReaderPersistentPageStatus()
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
      .backgroundColor(this.readerBackgroundColor())
      .onAreaChange((_o: Area, n: Area) => {
        this.viewWidth = n.width as number
        this.viewHeight = n.height as number
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return this.handleKeyEvent(event)
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.readerBackgroundColor())
    .onBackPressed(() => {
      this.closeReader()
      return true
    })
    .onShown(() => {
      this.readerRouteVisible = true
      this.scheduleEntryStatusBarVisibility()
      this.setReaderKeepScreenOn(this.readMode.keepScreenOn)
    })
    .onWillDisappear(() => {
      this.readerRouteVisible = false
      this.clearPendingEntryStatusBarHide()
      this.setReaderKeepScreenOn(false)
      // Normal Reader close owns its status-bar request in closeReader() before popping. Keep
      // this only for an external unmount that bypasses the Reader close path.
      if (!this.readerClosing) {
        this.restoreAppStatusBar()
      }
    })
    .onWillHide(() => {
      this.readerRouteVisible = false
      this.clearPendingEntryStatusBarHide()
      this.setReaderKeepScreenOn(false)
      // ReaderSettings hides Reader without unmounting it. A real Reader close is handled by
      // onWillDisappear, which the framework invokes before the exit transition begins.
      if (!this.readerClosing) {
        this.restoreAppStatusBar()
      }
    })
    .onDisAppear(() => {
      this.readerRouteVisible = false
      this.clearPendingEntryStatusBarHide()
      connectReaderOverlayNavigation().finishClose()
    })
    .onReady((context: NavDestinationContext) => {
      const routeEpoch: number = this.readerRouteEpoch + 1
      this.readerRouteEpoch = routeEpoch
      this.sliderSyncToken++
      const p = context.pathInfo.param as ReaderParams
      if (p !== undefined && p.gid.length > 0) {
        this.clearPendingEntryStatusBarHide()
        this.readerClosing = false
        this.readerReady = false
        this.stopAutoRead()
        this.resetReaderGalleryState()
        this.params = p
        this.showChrome = p.initialChromeVisible
        this.readMode.columnMode = connectGalleryReadProgress().getColumnMode(p.gid)
        this.sliderValue = p.index + 1
        const isEx: boolean = connectSiteMode().isEx
        ReaderLocalSourceService.preferLocal(this.hostContext(), p)
          .then((prepared: ReaderParams) => {
            if (!this.isReaderRouteIdentityCurrent(routeEpoch, p.gid, p.token, isEx)) {
              return
            }
            this.startReaderSession(prepared, routeEpoch, isEx)
          })
          .catch((error: Error) => {
            if (!this.isReaderRouteIdentityCurrent(routeEpoch, p.gid, p.token, isEx)) {
              return
            }
            DiagnosticLogger.warn('reader', 'local_source_prepare_failed', error.message)
            this.startReaderSession(p, routeEpoch, isEx)
          })
      }
      this.setReaderKeepScreenOn(this.readMode.keepScreenOn)
      this.requestReaderKeyFocus()
      this.registerVolumeKeyConsumer()
    })
  }

  private startReaderSession(p: ReaderParams, routeEpoch: number, isEx: boolean): void {
    this.params = p
    this.showChrome = p.initialChromeVisible
    this.sliderValue = p.index + 1
    const requestedIndex: number = p.index
    this.vm.init(
      p.gid,
      p.token,
      isEx,
      p.fileCount,
      p.index,
      p.seedImages,
      p.seedLoadedPages,
      p.seedPerPage,
      p.seedPreviewPages,
      p.seedImagePageUrl,
      p.source.kind,
      p.source.sourceKey,
    )
      .then((request: ReaderSessionRequest | null) => {
        if (!this.isReaderRouteCurrent(routeEpoch, request, p.gid, p.token, isEx)) {
          return
        }
        const total: number = this.vm.totalPages()
        const targetIndex: number = total > 0 ? Math.min(requestedIndex, total - 1) : 0
        this.vm.currentIndex = targetIndex
        this.sliderValue = targetIndex + 1
        this.readerPagerIndex = this.readerPagerIndexFor(targetIndex)
        this.verticalVisibleStart = targetIndex
        this.verticalVisibleEnd = targetIndex
        this.readerReady = true
        if (this.isContinuousVerticalMode()) {
          setTimeout(() => {
            if (!this.isReaderRouteCurrent(routeEpoch, request, p.gid, p.token, isEx)) {
              return
            }
            this.listScroller.scrollToIndex(targetIndex)
          }, 50)
        } else {
          this.syncReaderPagerToIndex(targetIndex, false, routeEpoch)
        }
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

  // Window keep-screen-on toggle. Best-effort: a failure must not break the reader.
  private setReaderKeepScreenOn(active: boolean): void {
    window
      .getLastWindow(this.hostContext())
      .then((win: window.Window) => {
        win.setWindowKeepScreenOn(active).catch((_e: Error) => {})
      })
      .catch((_e: Error) => {})
  }

  private readerBackgroundColor(): ResourceColor {
    return readerBackgroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private readerForegroundColor(): ResourceColor {
    return readerForegroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private readerBackgroundIsDark(): boolean {
    return readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private appStatusBarContentColor(): string {
    return this.themeDisplay.effectiveDark ? READER_STATUS_BAR_LIGHT_CONTENT : READER_STATUS_BAR_DARK_CONTENT
  }

  private applyStatusBarVisible(visible: boolean, contentColor: string, lightIcon: boolean): Promise<void> {
    return window
      .getLastWindow(this.hostContext())
      .then((win: window.Window) => {
        if (visible) {
          return win.setWindowSystemBarProperties({
            statusBarContentColor: contentColor,
            isStatusBarLightIcon: lightIcon,
          })
            .catch((_e: Error) => {})
            .then(() => {
              return win.setSpecificSystemBarEnabled('status', true, false)
            })
        }
        return win.setSpecificSystemBarEnabled('status', false, false)
      })
      .catch((_e: Error) => {})
  }

  private readerStatusBarContentColor(chromeVisible: boolean): string {
    if (chromeVisible || this.readerBackgroundIsDark()) {
      return READER_STATUS_BAR_LIGHT_CONTENT
    }
    return READER_STATUS_BAR_DARK_CONTENT
  }

  private setReaderStatusBarForChrome(chromeVisible: boolean): void {
    const visible: boolean = !this.readMode.fullscreen || chromeVisible
    const lightIcon: boolean = chromeVisible || this.readerBackgroundIsDark()
    this.applyStatusBarVisible(visible, this.readerStatusBarContentColor(chromeVisible), lightIcon)
  }

  private restoreAppStatusBar(): void {
    this.applyStatusBarVisible(
      true,
      this.appStatusBarContentColor(),
      this.themeDisplay.effectiveDark,
    )
  }

  private syncReaderStatusBarWithChrome(): void {
    this.setReaderStatusBarForChrome(this.showChrome)
  }

  private scheduleEntryStatusBarVisibility(): void {
    this.clearPendingEntryStatusBarHide()
    if (!this.readMode.fullscreen || this.showChrome) {
      this.syncReaderStatusBarWithChrome()
      return
    }
    const routeEpoch: number = this.readerRouteEpoch
    this.readerStatusBarHideTimerId = setTimeout((): void => {
      this.readerStatusBarHideTimerId = -1
      if (this.readerClosing || routeEpoch !== this.readerRouteEpoch || this.showChrome ||
        !this.readMode.fullscreen) {
        return
      }
      this.setReaderStatusBarForChrome(false)
    }, READER_ENTRY_STATUS_BAR_HIDE_DELAY_MS)
  }

  private clearPendingEntryStatusBarHide(): void {
    if (this.readerStatusBarHideTimerId < 0) {
      return
    }
    clearTimeout(this.readerStatusBarHideTimerId)
    this.readerStatusBarHideTimerId = -1
  }

  private closeReader(): void {
    if (this.readerClosing) {
      return
    }
    this.readerRouteEpoch++
    this.sliderSyncToken++
    this.readerClosing = true
    this.clearPendingEntryStatusBarHide()
    this.applyStatusBarVisible(
      true,
      this.appStatusBarContentColor(),
      this.themeDisplay.effectiveDark,
    )
      .then(() => {
        return readerDelay(READER_EXIT_STATUS_BAR_LEAD_MS)
      })
      .then(() => {
        connectReaderOverlayNavigation().close()
      })
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private isReaderRouteCurrent(
    routeEpoch: number,
    request: ReaderSessionRequest | null,
    gid: string,
    token: string,
    isEx: boolean,
  ): boolean {
    return routeEpoch === this.readerRouteEpoch &&
      !this.readerClosing &&
      this.params.gid === gid &&
      this.params.token === token &&
      connectSiteMode().isEx === isEx &&
      this.vm.isSessionCurrent(request)
  }

  private isReaderRouteIdentityCurrent(
    routeEpoch: number,
    gid: string,
    token: string,
    isEx: boolean,
  ): boolean {
    return routeEpoch === this.readerRouteEpoch &&
      !this.readerClosing &&
      this.params.gid === gid &&
      this.params.token === token &&
      connectSiteMode().isEx === isEx
  }

  /** Clears page-number keyed state before a retained ReaderPage starts another gallery. */
  private resetReaderGalleryState(): void {
    this.loadedPages = []
    this.loadedPageSignal++
    this.originalImagePages = ''
    this.originalAvailablePages = ''
    this.originalImageResolving = false
    this.imageMetricPages = []
    this.imageMetricWidths = []
    this.imageMetricHeights = []
    this.imageEnhancementPages = []
    this.imageEnhancementModels = []
    this.imageEnhancementApplied = []
    this.imageEnhancementReasons = []
    this.imageFilePages = []
    this.imageFileBytes = []
    this.imageFileFormats = []
    this.imageBlockFilePages = []
    this.imageBlockFilePaths = []
    this.imageBlockStatePages = []
    this.imageBlockStateValues = []
    this.currentImageBlockFilePath = ''
    this.currentImageBlocked = false
    this.sourceReloadPage = 0
    this.sourceReloadRequestId++
    this.imageZoomed = false
    this.verticalZoomedPage = -1
    this.verticalVisibleStart = 0
    this.verticalVisibleEnd = 0
    this.sliderPreview = -1
    this.readerPagerIndex = 0
  }

  private currentImage(): EhGalleryImage | null {
    if (!this.vm.hasPreviewAt(this.vm.currentIndex)) {
      return null
    }
    return this.vm.imageAt(this.vm.currentIndex)
  }

  private rememberImageMetrics(page: number, width: number, height: number): void {
    if (page <= 0 || width <= 0 || height <= 0) {
      return
    }
    for (let i: number = 0; i < this.imageMetricPages.length; i++) {
      if (this.imageMetricPages[i] === page) {
        this.imageMetricWidths[i] = Math.round(width)
        this.imageMetricHeights[i] = Math.round(height)
        return
      }
    }
    this.imageMetricPages.push(page)
    this.imageMetricWidths.push(Math.round(width))
    this.imageMetricHeights.push(Math.round(height))
  }

  private imageMetricsText(page: number): string {
    for (let i: number = 0; i < this.imageMetricPages.length; i++) {
      if (this.imageMetricPages[i] === page) {
        return AppStrings.get('reader_image_info_dimensions')
          .replace('%d', `${this.imageMetricWidths[i]}`)
          .replace('%d', `${this.imageMetricHeights[i]}`)
      }
    }
    return ''
  }

  private rememberImageEnhancement(
    page: number,
    model: string,
    applied: boolean,
    reason: string,
  ): void {
    if (page <= 0) {
      return
    }
    for (let i: number = 0; i < this.imageEnhancementPages.length; i++) {
      if (this.imageEnhancementPages[i] === page) {
        this.imageEnhancementModels[i] = model
        this.imageEnhancementApplied[i] = applied
        this.imageEnhancementReasons[i] = reason
        return
      }
    }
    this.imageEnhancementPages.push(page)
    this.imageEnhancementModels.push(model)
    this.imageEnhancementApplied.push(applied)
    this.imageEnhancementReasons.push(reason)
  }

  private clearImageEnhancement(page: number): void {
    for (let i: number = 0; i < this.imageEnhancementPages.length; i++) {
      if (this.imageEnhancementPages[i] === page) {
        this.imageEnhancementPages.splice(i, 1)
        this.imageEnhancementModels.splice(i, 1)
        this.imageEnhancementApplied.splice(i, 1)
        this.imageEnhancementReasons.splice(i, 1)
        return
      }
    }
  }

  private imageEnhancementModelLabel(model: string): string {
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS) {
      return AppStrings.get('settings_reader_super_resolution_realesrgan_x2plus')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_PHOTO_NOISE0_2X) {
      return AppStrings.get('settings_reader_super_resolution_waifu2x_photo_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_ANIMEVIDEO_V3_X2) {
      return AppStrings.get('settings_reader_super_resolution_realesrgan_animevideov3_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X) {
      return AppStrings.get('settings_reader_super_resolution_waifu2x_art_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X) {
      return AppStrings.get('settings_reader_super_resolution_waifu2x_cunet_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE) {
      return AppStrings.get('settings_reader_super_resolution_realcugan_se_2x_conservative')
    }
    return AppStrings.get('settings_reader_super_resolution_model_not_selected')
  }

  private imageEnhancementBackendLabel(reason: string): string {
    if (reason.endsWith(':vulkan')) {
      return AppStrings.get('settings_reader_super_resolution_backend_vulkan')
    }
    if (reason.endsWith(':cpu')) {
      return AppStrings.get('settings_reader_super_resolution_backend_cpu')
    }
    return ''
  }

  private imageEnhancementText(page: number): string {
    if (!this.readMode.superResolutionEnabled) {
      return AppStrings.get('reader_image_info_enhancement').replace(
        '%s',
        AppStrings.get('settings_reader_super_resolution_off'),
      )
    }
    const currentModel: string = this.readMode.superResolutionModel
    const modelLabel: string = this.imageEnhancementModelLabel(currentModel)
    if (currentModel === ReaderSuperResolutionModel.NONE) {
      return AppStrings.get('reader_image_info_enhancement').replace('%s', modelLabel)
    }
    let applied: boolean = false
    let reason: string = 'queued'
    for (let i: number = 0; i < this.imageEnhancementPages.length; i++) {
      if (this.imageEnhancementPages[i] === page && this.imageEnhancementModels[i] === currentModel) {
        applied = this.imageEnhancementApplied[i]
        reason = this.imageEnhancementReasons[i]
        break
      }
    }
    let detail: string = ''
    if (applied) {
      const backendLabel: string = this.imageEnhancementBackendLabel(reason)
      const appliedLabel: string = backendLabel.length > 0
        ? `${modelLabel} · ${backendLabel}`
        : modelLabel
      detail = AppStrings.get('reader_image_info_enhancement_applied').replace('%s', appliedLabel)
    } else if (reason === 'processing') {
      detail = AppStrings.get('reader_image_info_enhancement_processing').replace('%s', modelLabel)
    } else if (reason === 'queued') {
      detail = AppStrings.get('reader_image_info_enhancement_queued').replace('%s', modelLabel)
    } else {
      detail = AppStrings.get('reader_image_info_enhancement_not_applied').replace('%s', modelLabel)
    }
    return AppStrings.get('reader_image_info_enhancement').replace('%s', detail)
  }

  private rememberImageFile(page: number, filePath: string, bytes: number): void {
    const previousFilePath: string = this.imageBlockFileForPage(page)
    if (previousFilePath.length > 0 && previousFilePath !== filePath) {
      this.clearImageEnhancement(page)
    }
    this.rememberImageBlockFile(page, filePath)
    if (page <= 0 || filePath.length === 0 || bytes < 0) {
      return
    }
    const format: string = readerImageFormatFromFile(filePath)
    for (let i: number = 0; i < this.imageFilePages.length; i++) {
      if (this.imageFilePages[i] === page) {
        this.imageFileBytes[i] = bytes
        this.imageFileFormats[i] = format
        return
      }
    }
    this.imageFilePages.push(page)
    this.imageFileBytes.push(bytes)
    this.imageFileFormats.push(format)
  }

  private imageFileBytesForPage(page: number): number {
    for (let i: number = 0; i < this.imageFilePages.length; i++) {
      if (this.imageFilePages[i] === page) {
        return this.imageFileBytes[i]
      }
    }
    return 0
  }

  private imageFileFormatForPage(page: number): string {
    for (let i: number = 0; i < this.imageFilePages.length; i++) {
      if (this.imageFilePages[i] === page) {
        return this.imageFileFormats[i]
      }
    }
    return AppStrings.get('reader_image_info_unknown')
  }

  private formatImageBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  private imageFileSizeText(page: number): string {
    const bytes: number = this.imageFileBytesForPage(page)
    return bytes > 0 ? this.formatImageBytes(bytes) : AppStrings.get('reader_image_info_unknown')
  }

  private imageHost(url: string): string {
    const scheme: number = url.indexOf('://')
    if (scheme < 0) {
      return ''
    }
    const start: number = scheme + 3
    const slash: number = url.indexOf('/', start)
    const host: string = slash >= 0 ? url.substring(start, slash) : url.substring(start)
    const port: number = host.indexOf(':')
    return port >= 0 ? host.substring(0, port) : host
  }

  private isLocalReaderSource(): boolean {
    return this.params.source.isLocal()
  }

  private displayedVariantText(page: number): string {
    if (this.isLocalReaderSource()) {
      if (this.params.source.variant === ReaderSourceVariant.ORIGINAL) {
        return AppStrings.get('reader_image_info_original')
      }
      if (this.params.source.variant === ReaderSourceVariant.RESAMPLED) {
        return AppStrings.get('reader_image_info_resampled')
      }
      return AppStrings.get('reader_image_info_unknown')
    }
    return this.originalModeForPage(page)
      ? AppStrings.get('reader_image_info_original')
      : AppStrings.get('reader_image_info_resampled')
  }

  private readerSourceText(): string {
    if (this.params.source.kind === ReaderSourceKind.GALLERY_DOWNLOAD) {
      return AppStrings.get('reader_image_info_local_download')
    }
    if (this.params.source.kind === ReaderSourceKind.ARCHIVE) {
      const base: string = AppStrings.get('reader_image_info_local_archive')
      return this.params.source.resolution.length > 0
        ? `${base} · ${this.params.source.resolution}`
        : base
    }
    return ''
  }

  private requestSourceReload(index: number): void {
    if (!this.vm.hasPreviewAt(index)) {
      return
    }
    const image: EhGalleryImage = this.vm.imageAt(index)
    this.sourceReloadPage = image.page
    this.sourceReloadRequestId++
    DiagnosticLogger.info('reader', 'source_reload_requested', `page ${image.page}`)
  }

  private showImageInfo(index: number): void {
    if (!this.vm.hasPreviewAt(index)) {
      return
    }
    const image: EhGalleryImage = this.vm.imageAt(index)
    const lines: string[] = [
      AppStrings.get('reader_image_info_format').replace('%s', this.imageFileFormatForPage(image.page)),
      AppStrings.get('reader_image_info_size').replace('%s', this.imageFileSizeText(image.page)),
      AppStrings.get('reader_image_info_current').replace('%s', this.displayedVariantText(image.page)),
    ]
    if (!this.isLocalReaderSource()) {
      lines.push(this.originalAvailableForIndex(index)
        ? AppStrings.get('reader_image_info_original_available')
        : AppStrings.get('reader_image_info_original_unavailable'))
    }
    const dimensions: string = this.imageMetricsText(image.page)
    if (dimensions.length > 0) {
      lines.push(dimensions)
    }
    lines.push(this.imageEnhancementText(image.page))
    const sourceText: string = this.readerSourceText()
    const displaySource: string = sourceText.length > 0
      ? sourceText
      : this.imageHost(this.currentDisplayUrl(image))
    if (displaySource.length > 0) {
      lines.push(AppStrings.get('reader_image_info_source').replace('%s', displaySource))
    }
    this.getUIContext().showAlertDialog({
      title: AppStrings.get('reader_image_info_title').replace('%d', `${image.page}`),
      message: lines.join('\n'),
      primaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {},
      },
    })
  }

  private spreadVisualLeftIndex(): number {
    if (!this.doublePageEnabled()) {
      return this.vm.currentIndex
    }
    const start: number = this.currentDoublePageStart()
    const second: number = this.spreadSecondIndex(start)
    if (this.spreadRowReversed() && this.hasSpreadImage(second)) {
      return second
    }
    return start
  }

  private spreadVisualRightIndex(): number {
    if (!this.doublePageEnabled()) {
      return -1
    }
    const start: number = this.currentDoublePageStart()
    const second: number = this.spreadSecondIndex(start)
    if (!this.spreadSecondVisible(start) || !this.hasSpreadImage(second)) {
      return -1
    }
    return this.spreadRowReversed() ? start : second
  }

  private spreadVisualIndexes(): number[] {
    const out: number[] = []
    const left: number = this.spreadVisualLeftIndex()
    if (this.hasSpreadImage(left)) {
      out.push(left)
    }
    const right: number = this.spreadVisualRightIndex()
    if (this.hasSpreadImage(right)) {
      out.push(right)
    }
    return out
  }

  private hasTwoSpreadActions(): boolean {
    return this.doublePageEnabled() && this.spreadVisualIndexes().length > 1
  }

  private readerContentReady(): boolean {
    return this.readerReady && this.vm.totalPages() > 0
  }

  private readerPreloadPages(): number {
    const value: number = this.readMode.preloadPages
    if (!Number.isFinite(value)) {
      return READER_DEFAULT_PRELOAD_PAGES
    }
    if (value < 0) {
      return 0
    }
    if (value > READER_MAX_PRELOAD_PAGES) {
      return READER_MAX_PRELOAD_PAGES
    }
    return Math.round(value)
  }

  private isContinuousVerticalMode(): boolean {
    return this.readMode.mode === ReadMode.VERTICAL
  }

  private isPagedVerticalMode(): boolean {
    return this.readMode.mode === ReadMode.TOP_TO_BOTTOM
  }

  private isHorizontalPagedMode(): boolean {
    return this.readMode.mode === ReadMode.LTR || this.readMode.mode === ReadMode.RTL
  }

  private cacheWarmImageIndexes(): number[] {
    const indexes: number[] = []
    const preloadPages: number = this.readerPreloadPages()
    if (!this.readerContentReady() || preloadPages <= 0 || this.viewWidth <= 0 || this.viewHeight <= 0) {
      return indexes
    }
    const to: number = Math.min(this.vm.currentIndex + preloadPages, this.vm.totalPages() - 1)
    for (let i: number = this.vm.currentIndex + 1; i <= to; i++) {
      if (this.vm.hasPreviewAt(i)) {
        indexes.push(i)
      }
    }
    return indexes
  }

  private warmerTranslateX(): number {
    return this.viewWidth + ThemeConstants.SPACE_XL
  }

  @Builder
  ReaderCacheWarmers() {
    Stack() {
      ForEach(
        this.cacheWarmImageIndexes(),
        (index: number) => {
          ReaderCacheWarmImage({
            page: this.vm.imageAt(index).page,
            sourceUrl: this.currentDisplayUrl(this.vm.imageAt(index)),
            imageKey: `${this.readerImageKey(this.vm.imageAt(index))}-${this.originalModeKeyForPage(this.vm.imageAt(index).page)}-${this.imageBlockRuleVersion}`,
            fileCacheKey: this.readerFileCacheKey(
              this.vm.imageAt(index),
              this.originalModeForPage(this.vm.imageAt(index).page),
            ),
            onImageLoaded: (page: number) => {
              this.markPageImageLoaded(page)
            },
            onImageFileReady: (page: number, filePath: string, bytes: number) => {
              this.rememberImageFile(page, filePath, bytes)
            },
            translateX: this.warmerTranslateX(),
          })
        },
        (index: number) => `cache_warm_${index}_${this.safeForEachKeyHash(this.currentDisplayUrl(this.vm.imageAt(index)))}`,
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
      this.refreshSpreadStartSource(true)
    } else if (!enabled && has) {
      this.originalImagePages = this.originalImagePages.replace(token, '')
      this.refreshSpreadStartSource(true)
    }
  }

  private currentDisplayUrl(image: EhGalleryImage): string {
    if (this.isLocalReaderSource()) {
      return image.imageUrl
    }
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

  private originalModeForIndex(index: number): boolean {
    if (!this.vm.hasPreviewAt(index)) {
      return false
    }
    return this.originalModeForPage(this.vm.imageAt(index).page)
  }

  private setOriginalAvailableForPage(page: number, available: boolean): void {
    const token: string = this.originalToken(page)
    const has: boolean = this.originalAvailablePages.indexOf(token) >= 0
    if (available && !has) {
      this.originalAvailablePages = `${this.originalAvailablePages}${token}`
    } else if (!available && has) {
      this.originalAvailablePages = this.originalAvailablePages.replace(token, '')
    }
  }

  private syncOriginalAvailabilityForPage(page: number): void {
    const index: number = page - 1
    if (!this.vm.hasPreviewAt(index)) {
      return
    }
    const image: EhGalleryImage = this.vm.imageAt(index)
    if (image.page !== page) {
      return
    }
    this.setOriginalAvailableForPage(page, image.originImageUrl.length > 0)
  }

  private originalAvailableForIndex(index: number): boolean {
    if (this.isLocalReaderSource()) {
      return false
    }
    if (!this.vm.hasPreviewAt(index)) {
      return false
    }
    const image: EhGalleryImage = this.vm.imageAt(index)
    return image.originImageUrl.length > 0 ||
      this.originalAvailablePages.indexOf(this.originalToken(image.page)) >= 0
  }

  private anyOriginalAvailableForIndexes(indexes: number[]): boolean {
    for (let i: number = 0; i < indexes.length; i++) {
      if (this.originalAvailableForIndex(indexes[i])) {
        return true
      }
    }
    return false
  }

  private allOriginalAvailableForIndexes(indexes: number[]): boolean {
    if (indexes.length === 0) {
      return false
    }
    for (let i: number = 0; i < indexes.length; i++) {
      if (!this.originalAvailableForIndex(indexes[i])) {
        return false
      }
    }
    return true
  }

  private anyOriginalModeForIndexes(indexes: number[]): boolean {
    for (let i: number = 0; i < indexes.length; i++) {
      if (this.originalModeForIndex(indexes[i])) {
        return true
      }
    }
    return false
  }

  private allOriginalModeForIndexes(indexes: number[]): boolean {
    if (indexes.length === 0) {
      return false
    }
    for (let i: number = 0; i < indexes.length; i++) {
      if (!this.originalModeForIndex(indexes[i])) {
        return false
      }
    }
    return true
  }

  private hasCachedOriginal(image: EhGalleryImage): boolean {
    return ImagePipelineService.cachedReaderFile(
      this.hostContext(),
      this.readerFileCacheKey(image, true),
    ) !== null
  }

  private async enableOriginalImages(indexes: number[]): Promise<void> {
    for (let i: number = 0; i < indexes.length; i++) {
      const index: number = indexes[i]
      if (!this.vm.hasPreviewAt(index)) {
        continue
      }
      const image: EhGalleryImage = this.vm.imageAt(index)
      if (this.originalModeForPage(image.page)) {
        continue
      }
      if (this.hasCachedOriginal(image)) {
        this.setOriginalModeForPage(image.page, true)
        DiagnosticLogger.info('reader', 'original_mode_cache_hit', `page ${image.page}`)
        continue
      }
      try {
        const url: string = await ImageResolveService.getInstance().resolveOriginal(image)
        this.setOriginalModeForPage(image.page, true)
        DiagnosticLogger.info('reader', 'original_mode_on', `page ${image.page} fullimg ${url.indexOf('/fullimg') >= 0}`)
      } catch (err) {
        const e: Error = err as Error
        DiagnosticLogger.warn('reader', 'original_resolve_failed', e.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_original_unavailable') })
      }
    }
  }

  private missingOriginalPagesMessage(pages: number[]): string {
    if (pages.length === 0) {
      return AppStrings.get('reader_original_unavailable')
    }
    const pageText: string = pages.map((page: number) => `${page}`).join(', ')
    return AppStrings.get('reader_spread_original_pages_unavailable').replace('%s', pageText)
  }

  private async enableOriginalImagesWithPageFeedback(indexes: number[]): Promise<void> {
    const missingPages: number[] = []
    for (let i: number = 0; i < indexes.length; i++) {
      const index: number = indexes[i]
      if (!this.vm.hasPreviewAt(index)) {
        continue
      }
      const image: EhGalleryImage = this.vm.imageAt(index)
      if (this.originalModeForPage(image.page)) {
        continue
      }
      if (this.hasCachedOriginal(image)) {
        this.setOriginalModeForPage(image.page, true)
        DiagnosticLogger.info('reader', 'original_mode_cache_hit', `page ${image.page}`)
        continue
      }
      try {
        const url: string = await ImageResolveService.getInstance().resolveOriginal(image)
        this.setOriginalModeForPage(image.page, true)
        DiagnosticLogger.info('reader', 'original_mode_on', `page ${image.page} fullimg ${url.indexOf('/fullimg') >= 0}`)
      } catch (err) {
        const e: Error = err as Error
        DiagnosticLogger.warn('reader', 'spread_original_resolve_failed', e.message)
        missingPages.push(image.page)
      }
    }
    if (missingPages.length > 0) {
      this.getUIContext().getPromptAction().showToast({
        message: this.missingOriginalPagesMessage(missingPages),
      })
    }
  }

  private toggleOriginalImagesAtIndexes(indexes: number[]): void {
    if (indexes.length === 0 || this.originalImageResolving) {
      return
    }
    if (this.allOriginalModeForIndexes(indexes)) {
      for (let i: number = 0; i < indexes.length; i++) {
        if (this.vm.hasPreviewAt(indexes[i])) {
          const image: EhGalleryImage = this.vm.imageAt(indexes[i])
          this.setOriginalModeForPage(image.page, false)
          DiagnosticLogger.info('reader', 'original_mode_off', `page ${image.page}`)
        }
      }
      return
    }
    this.originalImageResolving = true
    const task: Promise<void> = indexes.length > 1
      ? this.enableOriginalImagesWithPageFeedback(indexes)
      : this.enableOriginalImages(indexes)
    task
      .finally(() => {
        this.originalImageResolving = false
      })
  }

  private toggleOriginalImage(): void {
    this.toggleOriginalImagesAtIndexes([this.vm.currentIndex])
  }

  private openOriginalAction(): void {
    if (this.originalImageResolving || !this.originalActionEnabled()) {
      return
    }
    if (this.hasTwoSpreadActions()) {
      this.saveSpreadMenuShown = false
      this.originalSpreadMenuShown = true
      return
    }
    this.toggleOriginalImage()
  }

  private originalActionEnabled(): boolean {
    if (this.isLocalReaderSource()) {
      return false
    }
    const indexes: number[] = this.hasTwoSpreadActions()
      ? this.spreadVisualIndexes()
      : [this.vm.currentIndex]
    return this.anyOriginalModeForIndexes(indexes) || this.anyOriginalAvailableForIndexes(indexes)
  }

  private originalSpreadBothActionEnabled(): boolean {
    const indexes: number[] = this.spreadVisualIndexes()
    return this.allOriginalModeForIndexes(indexes) || this.allOriginalAvailableForIndexes(indexes)
  }

  private originalButtonColor(): ResourceColor {
    if (this.hasTwoSpreadActions() && this.anyOriginalModeForIndexes(this.spreadVisualIndexes())) {
      return ThemeConstants.BRAND_PRIMARY
    }
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

  private async saveImagesSequential(indexes: number[]): Promise<void> {
    for (let i: number = 0; i < indexes.length; i++) {
      const index: number = indexes[i]
      if (!this.vm.hasPreviewAt(index)) {
        continue
      }
      const image: EhGalleryImage = this.vm.imageAt(index)
      const title: string = `${this.params.gid}-${index + 1}`.trim()
      const alreadyResolvedUrl: string = this.currentDisplayUrl(image)
      try {
        if (alreadyResolvedUrl.length > 0) {
          await this.saveImageUrl(alreadyResolvedUrl, title)
        } else {
          const imageUrl: string = await this.resolveCurrentDisplayUrl(image)
          await this.saveImageUrl(imageUrl, title)
        }
      } catch (err) {
        const e: Error = err as Error
        DiagnosticLogger.warn('reader', 'save_image_resolve_failed', e.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_failed') })
      }
    }
  }

  private saveImagesAtIndexes(indexes: number[]): void {
    if (this.savingCurrentImage) {
      return
    }
    if (indexes.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_no_image') })
      return
    }
    const valid: number[] = []
    for (let i: number = 0; i < indexes.length; i++) {
      if (this.vm.hasPreviewAt(indexes[i])) {
        valid.push(indexes[i])
      }
    }
    if (valid.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_save_no_image') })
      return
    }
    this.savingCurrentImage = true
    this.saveImagesSequential(valid)
      .finally(() => {
        this.savingCurrentImage = false
      })
  }

  private saveCurrentImage(): void {
    this.saveImagesAtIndexes([this.vm.currentIndex])
  }

  private openSaveAction(): void {
    if (this.savingCurrentImage) {
      return
    }
    if (this.hasTwoSpreadActions()) {
      this.originalSpreadMenuShown = false
      this.saveSpreadMenuShown = true
      return
    }
    this.saveCurrentImage()
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

  private imageBlockFileForPage(page: number): string {
    for (let i: number = 0; i < this.imageBlockFilePages.length; i++) {
      if (this.imageBlockFilePages[i] === page) {
        return this.imageBlockFilePaths[i]
      }
    }
    return ''
  }

  private imageBlockStateForPage(page: number): boolean {
    for (let i: number = 0; i < this.imageBlockStatePages.length; i++) {
      if (this.imageBlockStatePages[i] === page) {
        return this.imageBlockStateValues[i]
      }
    }
    return false
  }

  private rememberImageBlockFile(page: number, filePath: string): void {
    if (page <= 0 || filePath.length === 0) {
      return
    }
    for (let i: number = 0; i < this.imageBlockFilePages.length; i++) {
      if (this.imageBlockFilePages[i] === page) {
        this.imageBlockFilePaths[i] = filePath
        this.syncCurrentImageBlockFile()
        return
      }
    }
    this.imageBlockFilePages.push(page)
    this.imageBlockFilePaths.push(filePath)
    this.syncCurrentImageBlockFile()
  }

  private syncCurrentImageBlockFile(): void {
    const page: number = this.vm.currentIndex + 1
    this.currentImageBlockFilePath = this.imageBlockFileForPage(page)
    this.currentImageBlocked = this.imageBlockStateForPage(page)
  }

  private rememberImageBlockState(page: number, blocked: boolean): void {
    if (page <= 0) {
      return
    }
    for (let i: number = 0; i < this.imageBlockStatePages.length; i++) {
      if (this.imageBlockStatePages[i] === page) {
        this.imageBlockStateValues[i] = blocked
        this.syncCurrentImageBlockFile()
        return
      }
    }
    this.imageBlockStatePages.push(page)
    this.imageBlockStateValues.push(blocked)
    this.syncCurrentImageBlockFile()
  }

  private markCurrentImageAsBlocked(): void {
    if (this.imageBlockRuleSaving) {
      return
    }
    const image: EhGalleryImage | null = this.currentImage()
    if (image === null) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_mark_waiting') })
      return
    }
    const filePath: string = this.currentImageBlockFilePath.length > 0
      ? this.currentImageBlockFilePath
      : this.imageBlockFileForPage(image.page)
    if (filePath.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_mark_waiting') })
      return
    }
    this.imageBlockRuleSaving = true
    ImageBlockRuntimeService.addLocalRuleForFile(
      this.hostContext(),
      filePath,
      'scanlator-ad',
      8,
      this.currentGallerySourceUrl(),
      image.page,
    )
      .then(() => {
        this.imageBlockRuleVersion++
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_mark_added') })
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('image-block', 'reader_local_rule_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_mark_failed') })
      })
      .finally(() => {
        this.imageBlockRuleSaving = false
      })
  }

  private canShowReaderImageBlockAction(): boolean {
    return this.imageBlockSettings.enabled && !this.currentImageBlocked
  }

  private confirmMarkCurrentImageAsBlocked(): void {
    if (!this.canShowReaderImageBlockAction() || this.imageBlockRuleSaving) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.reader_image_block_mark'),
      message: $r('app.string.reader_image_block_mark_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.reader_image_block_mark'),
        action: () => {
          this.markCurrentImageAsBlocked()
        },
      },
    })
  }

  private allowImageBlockForPage(page: number): void {
    if (this.imageBlockWhitelistSaving) {
      return
    }
    const filePath: string = this.imageBlockFileForPage(page)
    if (filePath.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_mark_waiting') })
      return
    }
    this.imageBlockWhitelistSaving = true
    ImageBlockRuntimeService.addWhitelistForFile(this.hostContext(), filePath)
      .then(() => {
        this.imageBlockRuleVersion++
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_allowed') })
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('image-block', 'reader_whitelist_failed', err.message)
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.reader_image_block_allow_failed') })
      })
      .finally(() => {
        this.imageBlockWhitelistSaving = false
      })
  }

  private currentGallerySourceUrl(): string {
    if (this.params.gid.length === 0 || this.params.token.length === 0) {
      return ''
    }
    return `https://e-hentai.org/g/${this.params.gid}/${this.params.token}/`
  }

  // Keep the slider thumb on the live page when the user swipes (not while they drag the slider),
  // and persist the reading position (eros_fe saveLastIndex: memory now, disk on a 3s debounce).
  @Monitor('vm.currentIndex')
  onPageChanged(): void {
    if (this.sliderPreview < 0) {
      const target: number = this.vm.currentIndex + 1
      const token: number = ++this.sliderSyncToken
      if (this.sliderValue !== target) {
        // A Monitor runs after its observed state has already invalidated the Reader subtree. Start
        // the Slider transaction in the next task so ArkUI can animate from the retained thumb value.
        setTimeout(() => {
          if (token !== this.sliderSyncToken || this.sliderPreview >= 0 || this.readerClosing) {
            return
          }
          this.getUIContext().animateTo({ duration: READER_PROGRESS_ANIM_DURATION, curve: Curve.EaseOut }, () => {
            this.sliderValue = target
          })
        }, 0)
      }
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
    this.syncCurrentImageBlockFile()
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

  @Monitor('readMode.keepScreenOn')
  onKeepScreenOnChanged(): void {
    if (this.readerRouteVisible) {
      this.setReaderKeepScreenOn(this.readMode.keepScreenOn)
    }
  }

  @Monitor('readMode.fullscreen', 'readMode.backgroundMode', 'themeDisplay.effectiveDark')
  onReaderPresentationSettingsChanged(): void {
    if (this.readerRouteVisible) {
      this.clearPendingEntryStatusBarHide()
      this.syncReaderStatusBarWithChrome()
    }
  }

  @Monitor('readMode.mode')
  onReadModeChanged(): void {
    this.clearZoomGate()
    if (this.isContinuousVerticalMode()) {
      this.verticalVisibleStart = this.vm.currentIndex
      this.verticalVisibleEnd = this.vm.currentIndex
    }
    if (this.readerContentReady()) {
      this.syncReaderPagerToIndex(this.vm.currentIndex, false)
    }
    if (this.showThumbStrip) {
      setTimeout(() => {
        this.scrollThumbStripTo(this.vm.currentIndex, false)
      }, 0)
    }
  }

  @Monitor('readMode.tapZoneLayout', 'readMode.tapZoneInvert')
  onTapZoneSettingsChanged(): void {
    if (this.readerContentReady()) {
      this.tapZonePreviewVisible = true
    }
  }

  // Force-persist on close so the last page survives an unfired debounce (eros_fe saveToStore).
  aboutToDisappear(): void {
    if (this.params.gid.length > 0) {
      GalleryReadProgressSettings.flush(this.hostContext())
    }
    this.stopAutoRead()
    this.unregisterVolumeKeyConsumer()
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
    return index >= 0 && index < this.vm.totalPages() && this.vm.imageAt(index).imageUrl.length > 0
  }

  private markPageImageLoaded(page: number): void {
    if (page <= 0) {
      return
    }
    this.syncOriginalAvailabilityForPage(page)
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

  private onReaderTap(x: number, y: number): void {
    if (this.tapZonePreviewVisible) {
      this.tapZonePreviewVisible = false
      return
    }
    if (this.consumeReaderTapSuppressed()) {
      return
    }
    const action: string = ReaderTapZoneResolver.resolve(
      this.readMode.tapZoneLayout,
      this.readMode.tapZoneInvert,
      x,
      y,
      this.viewWidth,
      this.viewHeight,
    )
    this.performTapZoneAction(action)
  }

  private performTapZoneAction(action: string): void {
    if (this.isContinuousVerticalMode()) {
      if (action === ReaderTapZoneAction.PREVIOUS || action === ReaderTapZoneAction.LEFT) {
        this.listScroller.scrollBy(0, -this.viewHeight * READER_TAP_ZONE_SCROLL_RATIO)
      } else if (action === ReaderTapZoneAction.NEXT || action === ReaderTapZoneAction.RIGHT) {
        this.listScroller.scrollBy(0, this.viewHeight * READER_TAP_ZONE_SCROLL_RATIO)
      } else {
        this.toggleChrome()
      }
      return
    }
    if (action === ReaderTapZoneAction.PREVIOUS) {
      this.toPrev()
    } else if (action === ReaderTapZoneAction.NEXT) {
      this.toNext()
    } else if (action === ReaderTapZoneAction.LEFT) {
      this.tapLeft()
    } else if (action === ReaderTapZoneAction.RIGHT) {
      this.tapRight()
    } else {
      this.toggleChrome()
    }
  }

  private firstTouch(event: TouchEvent): TouchObject | null {
    if (event.touches.length > 0) {
      return event.touches[0]
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    return null
  }

  private movedBeyondTap(startX: number, startY: number, x: number, y: number): boolean {
    const dx: number = x - startX
    const dy: number = y - startY
    return (dx * dx + dy * dy) > (READER_VERTICAL_TAP_MAX_DISTANCE * READER_VERTICAL_TAP_MAX_DISTANCE)
  }

  private suppressReaderTapGesture(): void {
    this.readerTapSuppressUntilMs = Date.now() + READER_TOUCH_TAP_SUPPRESS_MS
  }

  private consumeReaderTapSuppressed(): boolean {
    if (Date.now() <= this.readerTapSuppressUntilMs) {
      return true
    }
    return false
  }

  private onReaderOverlayTouch(event: TouchEvent): void {
    const touch: TouchObject | null = this.firstTouch(event)
    if (touch === null) {
      return
    }
    if (event.touches.length > 1 || event.changedTouches.length > 1) {
      this.suppressReaderTapGesture()
      return
    }
    if (event.type === TouchType.Down) {
      this.readerTapStartX = touch.x
      this.readerTapStartY = touch.y
      return
    }
    if (event.type === TouchType.Move) {
      if (this.movedBeyondTap(this.readerTapStartX, this.readerTapStartY, touch.x, touch.y)) {
        this.suppressReaderTapGesture()
      }
      return
    }
    if (event.type === TouchType.Cancel) {
      this.suppressReaderTapGesture()
    }
  }

  private clearZoomGate(): void {
    this.imageZoomed = false
    this.verticalZoomedPage = -1
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
    return ReaderSpreadResolver.isDoublePage(this.readMode.mode, this.readMode.doublePageEnabled)
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
    this.turnTo(this.vm.currentIndex - 1)
  }

  private toNext(): void {
    if (this.doublePageEnabled()) {
      this.turnSpread(1)
      return
    }
    this.turnTo(this.vm.currentIndex + 1)
  }

  private shouldAnimateAdjacentTurn(target: number): boolean {
    if (!this.readMode.pageTurnAnimation || this.isContinuousVerticalMode()) {
      return false
    }
    const currentPagerIndex: number = this.readerPagerIndexFor(this.vm.currentIndex)
    const targetPagerIndex: number = this.readerPagerIndexFor(target)
    return Math.abs(targetPagerIndex - currentPagerIndex) === 1
  }

  // Go to a (page-index) target. Continuous vertical scrolls the List; paged modes move Swiper.
  // A loaded in-range step reuses the swipe path (no jump spinner); a missing preview slot, even when
  // padded into images[], loads via jumpToPage so placeholders are not rendered as image pages.
  private turnTo(target: number): void {
    if (target < 0) {
      return
    }
    this.clearZoomGate()
    const animated: boolean = this.shouldAnimateAdjacentTurn(target)
    if (target >= this.vm.totalPages() || !this.vm.hasPreviewAt(target)) {
      this.jumpToPage(target, animated)
      return
    }
    if (this.isContinuousVerticalMode()) {
      this.vm.currentIndex = target
      this.listScroller.scrollToIndex(target)
    } else {
      if (animated) {
        this.animateReaderPagerToIndex(target)
      } else {
        this.vm.onPageChange(target)
        this.syncReaderPagerToIndex(target, false)
      }
    }
  }

  // Jump after loading every page up to the target. Paged modes set currentIndex so the Swiper's
  // reactive `.index()` moves there. Continuous vertical scrolls the List to the index.
  private jumpToPage(index: number, animated: boolean = false): void {
    this.clearZoomGate()
    const routeEpoch: number = this.readerRouteEpoch
    const gid: string = this.params.gid
    const token: string = this.params.token
    const isEx: boolean = connectSiteMode().isEx
    this.vm.jumpTo(index, !animated).then((target: number) => {
      if (!this.isReaderRouteIdentityCurrent(routeEpoch, gid, token, isEx)) {
        return
      }
      if (this.isContinuousVerticalMode()) {
        this.vm.currentIndex = target
        this.listScroller.scrollToIndex(target)
      } else if (animated) {
        this.animateReaderPagerToIndex(target, routeEpoch)
      } else {
        this.vm.currentIndex = target
        this.syncReaderPagerToIndex(target, false, routeEpoch)
      }
    })
  }

  private animateReaderPagerToIndex(
    index: number,
    routeEpoch: number = this.readerRouteEpoch,
  ): void {
    const targetPagerIndex: number = this.readerPagerIndexFor(index)
    setTimeout(() => {
      if (routeEpoch !== this.readerRouteEpoch || this.readerClosing) {
        return
      }
      try {
        if (this.doublePageEnabled()) {
          this.doublePageSwiperController.changeIndex(targetPagerIndex, true)
        } else {
          this.horizontalSwiperController.changeIndex(targetPagerIndex, true)
        }
      } catch (err) {
        const message: string = err instanceof Error ? err.message : `${err}`
        DiagnosticLogger.warn('reader', 'pager_animate_failed', message)
        this.vm.currentIndex = index
        this.syncReaderPagerToIndex(index, false, routeEpoch)
      }
    }, 0)
  }

  private syncReaderPagerToIndex(
    index: number,
    animated: boolean,
    routeEpoch: number = this.readerRouteEpoch,
  ): void {
    if (this.isContinuousVerticalMode()) {
      setTimeout(() => {
        if (routeEpoch !== this.readerRouteEpoch || this.readerClosing) {
          return
        }
        this.listScroller.scrollToIndex(index)
      }, 0)
      return
    }
    const targetPagerIndex: number = this.readerPagerIndexFor(index)
    this.readerPagerIndex = targetPagerIndex
    setTimeout(() => {
      if (routeEpoch !== this.readerRouteEpoch || this.readerClosing) {
        return
      }
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
              localSource: this.isLocalReaderSource(),
              imageKey: `${this.readerImageKey(this.vm.imageAt(index))}-${this.originalModeKeyForPage(this.vm.imageAt(index).page)}-${this.imageBlockRuleVersion}`,
              fileCacheKey: this.readerFileCacheKey(
                this.vm.imageAt(index),
                this.originalModeForPage(this.vm.imageAt(index).page),
              ),
              preferOriginal: this.originalModeForPage(this.vm.imageAt(index).page),
              initiallyLoaded: this.isPageImageLoaded(index),
              loadedSignal: this.loadedPageSignal,
              sourceReloadPage: this.sourceReloadPage,
              sourceReloadRequestId: this.sourceReloadRequestId,
              imageBlockWhitelistSaving: this.imageBlockWhitelistSaving,
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
              onImageFileReady: (page: number, filePath: string, bytes: number) => {
                this.rememberImageFile(page, filePath, bytes)
              },
              onImageMetrics: (page: number, width: number, height: number) => {
                this.rememberImageMetrics(page, width, height)
              },
              onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => {
                this.rememberImageEnhancement(page, model, applied, reason)
              },
              onImageBlockState: (page: number, blocked: boolean) => {
                this.rememberImageBlockState(page, blocked)
              },
              onAllowImageBlock: (page: number) => {
                this.allowImageBlockForPage(page)
              },
            })
          } else {
            this.ReaderPendingPage(index)
          }
        },
        (index: number) => this.vm.pageRenderKey(index),
      )
    }
    .index(this.readerPagerIndex)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .vertical(this.isPagedVerticalMode())
    .loop(false)
    .cachedCount(this.readerPreloadPages())
    .indicator(false)
    .disableSwipe(this.imageZoomed)
    .width('100%')
    .height('100%')
    .onChange((i: number) => {
      this.clearZoomGate()
      this.readerPagerIndex = i
      DiagnosticLogger.info('reader', 'paged_swipe_change', `index ${i} mode ${this.readMode.mode} hasPreview ${this.vm.hasPreviewAt(i)}`)
      this.vm.onPageChange(i)
    })
  }

  private spreadIndexForImage(index: number): number {
    return ReaderSpreadResolver.spreadIndexForImage(this.readMode.columnMode, index)
  }

  private spreadStartIndex(spreadIndex: number): number {
    return ReaderSpreadResolver.spreadStartIndex(this.readMode.columnMode, spreadIndex)
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
    return `${img.page}-${img.sUrl}`
  }

  private readerFileCacheKey(img: EhGalleryImage, original: boolean): string {
    return ImagePipelineService.readerFileCacheKey(
      this.params.gid,
      this.params.token,
      img.page,
      original,
    )
  }

  private readerImageIdentityKey(img: EhGalleryImage): string {
    return `page_${img.page}_${this.safeForEachKeyHash(img.sUrl)}`
  }

  private spreadImageIdentityKey(index: number): string {
    if (!this.hasSpreadImage(index)) {
      return 'empty'
    }
    const img: EhGalleryImage = this.vm.imageAt(index)
    return `${this.readerImageIdentityKey(img)}_${this.originalModeKeyForPage(img.page)}`
  }

  private spreadRenderKey(start: number): string {
    const secondIndex: number = this.spreadSecondIndex(start)
    return `spread_${start}_${this.spreadImageIdentityKey(start)}_${this.spreadImageIdentityKey(secondIndex)}_${this.imageBlockRuleVersion}`
  }

  private safeForEachKeyHash(value: string): string {
    let hash: number = 2166136261
    for (let i: number = 0; i < value.length; i++) {
      hash = hash ^ value.charCodeAt(i)
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(36)
  }

  private sliderTargetIndex(page: number): number {
    return ReaderSpreadResolver.sliderTargetIndex(page)
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

  private refreshSpreadStartSource(force: boolean = false): void {
    const key: string = `${this.doublePageEnabled()}-${this.readMode.columnMode}-${this.vm.totalPages()}`
    if (force || key !== this.spreadDataSourceKey) {
      this.spreadDataSourceKey = key
      this.spreadDataSource.setData(this.spreadStarts())
    }
  }

  private spreadStartSource(): BasicDataSource<number> {
    this.refreshSpreadStartSource()
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
              localSource: this.isLocalReaderSource(),
              second: this.hasSpreadImage(this.spreadSecondIndex(start)) ? this.vm.imageAt(this.spreadSecondIndex(start)) : new EhGalleryImage(),
              firstFileCacheKey: this.readerFileCacheKey(
                this.vm.imageAt(start),
                this.originalModeForPage(this.vm.imageAt(start).page),
              ),
              secondFileCacheKey: this.hasSpreadImage(this.spreadSecondIndex(start))
                ? this.readerFileCacheKey(
                    this.vm.imageAt(this.spreadSecondIndex(start)),
                    this.originalModeForPage(this.vm.imageAt(this.spreadSecondIndex(start)).page),
                  )
                : '',
              hasFirst: true,
              hasSecond: this.spreadSecondVisible(start) && this.hasSpreadImage(this.spreadSecondIndex(start)),
              firstPreferOriginal: this.originalModeForPage(this.vm.imageAt(start).page),
              secondPreferOriginal: this.hasSpreadImage(this.spreadSecondIndex(start))
                ? this.originalModeForPage(this.vm.imageAt(this.spreadSecondIndex(start)).page)
                : false,
              firstInitiallyLoaded: this.isPageImageLoaded(start),
              secondInitiallyLoaded: this.isPageImageLoaded(this.spreadSecondIndex(start)),
              viewportW: this.viewWidth,
              viewportH: this.viewHeight,
              imageBlockRuleVersion: this.imageBlockRuleVersion,
              imageBlockWhitelistSaving: this.imageBlockWhitelistSaving,
              loadedSignal: this.loadedPageSignal,
              sourceReloadPage: this.sourceReloadPage,
              sourceReloadRequestId: this.sourceReloadRequestId,
              rowReversed: this.spreadRowReversed(),
              spreadLayoutMode: this.readMode.spreadLayoutMode,
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
              onImageFileReady: (page: number, filePath: string, bytes: number) => {
                this.rememberImageFile(page, filePath, bytes)
              },
              onImageMetrics: (page: number, width: number, height: number) => {
                this.rememberImageMetrics(page, width, height)
              },
              onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => {
                this.rememberImageEnhancement(page, model, applied, reason)
              },
              onImageBlockState: (page: number, blocked: boolean) => {
                this.rememberImageBlockState(page, blocked)
              },
              onAllowImageBlock: (page: number) => {
                this.allowImageBlockForPage(page)
              },
            })
          }
        },
        (start: number) => this.spreadRenderKey(start),
      )
    }
    .index(this.readerPagerIndex)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .vertical(false)
    .loop(false)
    .cachedCount(this.readerPreloadPages())
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

  private tapZonePreviewRegions(): ReaderTapZoneRegion[] {
    return ReaderTapZoneResolver.regions(this.readMode.tapZoneLayout, this.readMode.tapZoneInvert)
  }

  private tapZonePercent(value: number): string {
    return `${value * 100}%`
  }

  private tapZoneActionColor(action: string): ResourceColor {
    if (action === ReaderTapZoneAction.PREVIOUS) {
      return ThemeConstants.READER_TAP_ZONE_PREVIOUS
    }
    if (action === ReaderTapZoneAction.NEXT) {
      return ThemeConstants.READER_TAP_ZONE_NEXT
    }
    if (action === ReaderTapZoneAction.LEFT) {
      return ThemeConstants.READER_TAP_ZONE_LEFT
    }
    if (action === ReaderTapZoneAction.RIGHT) {
      return ThemeConstants.READER_TAP_ZONE_RIGHT
    }
    return ThemeConstants.READER_TAP_ZONE_MENU
  }

  private tapZoneActionLabel(action: string): Resource {
    if (action === ReaderTapZoneAction.PREVIOUS) {
      return $r('app.string.reader_tap_zone_action_previous')
    }
    if (action === ReaderTapZoneAction.NEXT) {
      return $r('app.string.reader_tap_zone_action_next')
    }
    if (action === ReaderTapZoneAction.LEFT) {
      return $r('app.string.reader_tap_zone_action_left')
    }
    if (action === ReaderTapZoneAction.RIGHT) {
      return $r('app.string.reader_tap_zone_action_right')
    }
    return $r('app.string.reader_tap_zone_action_menu')
  }

  @Builder
  ReaderTapZonePreview() {
    Stack() {
      ForEach(
        this.tapZonePreviewRegions(),
        (region: ReaderTapZoneRegion) => {
          Stack({ alignContent: Alignment.Center }) {
            Text(this.tapZoneActionLabel(region.action))
              .fontSize(ThemeConstants.FONT_SIZE_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
                top: ThemeConstants.SPACE_XS,
                bottom: ThemeConstants.SPACE_XS,
              })
              .backgroundColor(ThemeConstants.OVERLAY_SCRIM)
              .borderRadius(ThemeConstants.RADIUS_ROUND)
          }
          .width(this.tapZonePercent(region.right - region.left))
          .height(this.tapZonePercent(region.bottom - region.top))
          .position({
            x: this.tapZonePercent(region.left),
            y: this.tapZonePercent(region.top),
          })
          .backgroundColor(this.tapZoneActionColor(region.action))
        },
        (region: ReaderTapZoneRegion) => region.key,
      )
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => {
      this.tapZonePreviewVisible = false
    })
  }

  @Builder
  ReaderTapOverlay() {
    Blank()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onTouch((event: TouchEvent) => {
        this.onReaderOverlayTouch(event)
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          TapGesture({ count: 2, distanceThreshold: 8 }).onAction((e?: GestureEvent) => {
            if (this.consumeReaderTapSuppressed()) {
              return
            }
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
                localSource: this.isLocalReaderSource(),
                imageKey: `${this.readerImageKey(this.vm.imageAt(index))}-${this.originalModeKeyForPage(this.vm.imageAt(index).page)}-${this.imageBlockRuleVersion}`,
                fileCacheKey: this.readerFileCacheKey(
                  this.vm.imageAt(index),
                  this.originalModeForPage(this.vm.imageAt(index).page),
                ),
                preferOriginal: this.originalModeForPage(this.vm.imageAt(index).page),
                initiallyLoaded: this.isPageImageLoaded(index),
                loadedSignal: this.loadedPageSignal,
                sourceReloadPage: this.sourceReloadPage,
                sourceReloadRequestId: this.sourceReloadRequestId,
                imageBlockWhitelistSaving: this.imageBlockWhitelistSaving,
                visible: this.isVerticalPageVisible(index),
                onZoomChange: (zoomed: boolean) => {
                  this.imageZoomed = zoomed
                  this.verticalZoomedPage = zoomed ? this.vm.imageAt(index).page : -1
                },
                onReaderTap: (x: number, y: number) => {
                  this.onReaderTap(x, y)
                },
                onImageLoaded: (page: number) => {
                  this.markPageImageLoaded(page)
                },
                onImageFileReady: (page: number, filePath: string, bytes: number) => {
                  this.rememberImageFile(page, filePath, bytes)
                },
                onImageMetrics: (page: number, width: number, height: number) => {
                  this.rememberImageMetrics(page, width, height)
                },
                onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => {
                  this.rememberImageEnhancement(page, model, applied, reason)
                },
                onImageBlockState: (page: number, blocked: boolean) => {
                  this.rememberImageBlockState(page, blocked)
                },
                onAllowImageBlock: (page: number) => {
                  this.allowImageBlockForPage(page)
                },
              })
            } else {
              this.ReaderPendingPage(index)
            }
          }
          .zIndex((this.vm.hasPreviewAt(index) && this.verticalZoomedPage === this.vm.imageAt(index).page) ? 1 : 0)
        },
        (index: number) => this.vm.pageRenderKey(index),
      )
    }
    .width('100%')
    .height('100%')
    .cachedCount(this.readerPreloadPages())
    .enableScrollInteraction(!this.imageZoomed)
    .scrollBar(BarState.Off)
    .onScrollIndex((start: number, end: number) => {
      this.verticalVisibleStart = start
      this.verticalVisibleEnd = end
      this.vm.onVerticalScroll(start, end)
    })
  }

  private isVerticalPageVisible(index: number): boolean {
    return index >= this.verticalVisibleStart && index <= this.verticalVisibleEnd
  }

  private modeLabel(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readMode.mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('app.string.read_mode_ttb')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private modeIconFor(mode: string): Resource {
    if (mode === ReadMode.RTL) {
      return $r('sys.symbol.arrow_left_and_square')
    }
    if (mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('sys.symbol.square_and_arrow_down_1')
    }
    if (mode === ReadMode.VERTICAL) {
      return $r('sys.symbol.scroll_vertical')
    }
    return $r('sys.symbol.arrow_right_and_square')
  }

  private modeIcon(): Resource {
    return this.modeIconFor(this.readMode.mode)
  }

  private setReaderMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, mode)
    this.readModeMenuShown = false
  }

  private doublePageIconColor(): ResourceColor {
    if (!this.isHorizontalPagedMode()) {
      return $r('sys.color.font_tertiary')
    }
    return this.readMode.doublePageEnabled ? ThemeConstants.BRAND_PRIMARY : Color.White
  }

  private onePageIconColor(): ResourceColor {
    return this.canTurnOnePageInDoublePage() ? Color.White : $r('sys.color.font_tertiary')
  }

  private showOnePageStepButton(): boolean {
    return this.isHorizontalPagedMode() && this.readMode.doublePageEnabled
  }

  private toggleDoublePage(): void {
    if (!this.isHorizontalPagedMode()) {
      return
    }
    if (this.readMode.columnMode !== ReadColumnMode.ODD_LEFT &&
      this.readMode.columnMode !== ReadColumnMode.EVEN_LEFT) {
      this.readMode.columnMode = ReadColumnMode.ODD_LEFT
    }
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setDoublePageEnabled(ctx, !this.readMode.doublePageEnabled)
    this.clearZoomGate()
    this.syncReaderPagerToIndex(this.vm.currentIndex, false)
  }

  private canTurnOnePageInDoublePage(): boolean {
    return this.showOnePageStepButton() && this.currentDoublePageStart() + 1 < this.vm.totalPages()
  }

  private currentDoublePageStart(): number {
    return this.spreadStartIndex(this.spreadIndexForImage(this.vm.currentIndex))
  }

  private columnModeForSpreadStart(index: number): string {
    if (index <= 0 || index % 2 === 0) {
      return ReadColumnMode.ODD_LEFT
    }
    return ReadColumnMode.EVEN_LEFT
  }

  private setCurrentGalleryColumnMode(columnMode: string): void {
    this.readMode.columnMode = columnMode
    this.refreshSpreadStartSource()
    if (this.params.gid.length > 0) {
      GalleryReadProgressSettings.setColumnMode(this.hostContext(), this.params.gid, columnMode)
    }
  }

  private turnOnePageInDoublePage(): void {
    if (!this.canTurnOnePageInDoublePage()) {
      return
    }
    const targetStart: number = this.currentDoublePageStart() + 1
    this.setCurrentGalleryColumnMode(this.columnModeForSpreadStart(targetStart))
    this.turnTo(targetStart)
  }

  // Page counter '5 / 120'; while dragging the slider it previews the target page (sliderPreview),
  // matching the live render once the drag commits. Shared by the top + bottom bars.
  private pageCountText(): string {
    const shown: number = this.sliderPreview >= 0 ? this.sliderPreview : this.vm.currentIndex + 1
    return `${shown} / ${this.vm.totalPages()}`
  }

  private superResolutionIndicatorVisible(): boolean {
    return this.readMode.superResolutionEnabled &&
      this.readMode.superResolutionModel !== ReaderSuperResolutionModel.NONE
  }

  private currentImageEnhancementIndex(): number {
    const page: number = this.vm.currentIndex + 1
    const model: string = this.readMode.superResolutionModel
    for (let i: number = 0; i < this.imageEnhancementPages.length; i++) {
      if (this.imageEnhancementPages[i] === page && this.imageEnhancementModels[i] === model) {
        return i
      }
    }
    return -1
  }

  private currentImageEnhancementProcessing(): boolean {
    const index: number = this.currentImageEnhancementIndex()
    return index >= 0 && this.imageEnhancementReasons[index] === 'processing'
  }

  private currentImageEnhancementApplied(): boolean {
    const index: number = this.currentImageEnhancementIndex()
    return index >= 0 && this.imageEnhancementApplied[index]
  }

  @Builder
  ReaderPersistentPageStatus() {
    ReaderPageStatusOverlay({
      value: this.pageCountText(),
      showPageNumber: this.readMode.showPageNumber,
      showEnhancement: this.superResolutionIndicatorVisible(),
      enhancementProcessing: this.currentImageEnhancementProcessing(),
      enhancementApplied: this.currentImageEnhancementApplied(),
      bottomMargin: this.layout.bottomAvoidHeight + ThemeConstants.READER_PAGE_NUMBER_BOTTOM_GAP,
    })
  }

  // Center-tap chrome toggle with a fade (eros_fe 300ms fastOutSlowIn; V2Next animateTo idiom). Hooks
  // the SAME onReaderTap center path — no new gesture.
  private toggleChrome(): void {
    const nextVisible: boolean = !this.showChrome
    this.setReaderStatusBarForChrome(nextVisible)
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
      this.showChrome = nextVisible
    })
  }

  // Reader settings entry (eros_fe top-bar ellipsis → readSetting, view_widget.dart:996-1015).
  private openReaderSettings(): void {
    this.settingsSheetShown = true
  }

  private closeReaderSettings(): void {
    this.settingsSheetShown = false
  }

  private spreadPageLabel(key: string, index: number): string {
    return AppStrings.get(key).replace('%d', `${index + 1}`)
  }

  private spreadBothOriginalLabel(): string {
    return this.allOriginalModeForIndexes(this.spreadVisualIndexes())
      ? AppStrings.get('reader_spread_original_disable_both')
      : AppStrings.get('reader_spread_original_enable_both')
  }

  @Builder
  private ReaderTopMoreMenu() {
    Menu() {
      if (this.hasTwoSpreadActions()) {
        MenuItem({
          content: $r('app.string.reader_reload_source'),
          builder: (): void => this.ReaderSourceReloadSubMenu(),
        })
        MenuItem({
          content: $r('app.string.reader_image_info'),
          builder: (): void => this.ReaderImageInfoSubMenu(),
        })
      } else {
        MenuItem({ content: $r('app.string.reader_reload_source') })
          .onClick(() => {
            this.readerTopMoreMenuShown = false
            this.requestSourceReload(this.vm.currentIndex)
          })
        MenuItem({ content: $r('app.string.reader_image_info') })
          .onClick(() => {
            this.readerTopMoreMenuShown = false
            this.showImageInfo(this.vm.currentIndex)
          })
      }
      if (this.canShowReaderImageBlockAction()) {
        MenuItem({ content: $r('app.string.reader_image_block_mark') })
          .enabled(!this.imageBlockRuleSaving)
          .onClick(() => {
            this.readerTopMoreMenuShown = false
            this.confirmMarkCurrentImageAsBlocked()
          })
      }
    }
  }

  @Builder
  private ReaderSourceReloadSubMenu() {
    Menu() {
      this.SourceReloadSpreadMenuItem(this.spreadVisualLeftIndex(), 'reader_spread_left_page')
      this.SourceReloadSpreadMenuItem(this.spreadVisualRightIndex(), 'reader_spread_right_page')
    }
  }

  @Builder
  private SourceReloadSpreadMenuItem(index: number, key: string) {
    if (this.hasSpreadImage(index)) {
      MenuItem({ content: this.spreadPageLabel(key, index) })
        .onClick(() => {
          this.readerTopMoreMenuShown = false
          this.requestSourceReload(index)
        })
    }
  }

  @Builder
  private ReaderImageInfoSubMenu() {
    Menu() {
      this.ImageInfoSpreadMenuItem(this.spreadVisualLeftIndex(), 'reader_spread_left_page')
      this.ImageInfoSpreadMenuItem(this.spreadVisualRightIndex(), 'reader_spread_right_page')
    }
  }

  @Builder
  private ImageInfoSpreadMenuItem(index: number, key: string) {
    if (this.hasSpreadImage(index)) {
      MenuItem({ content: this.spreadPageLabel(key, index) })
        .onClick(() => {
          this.readerTopMoreMenuShown = false
          this.showImageInfo(index)
        })
    }
  }

  @Builder
  private SaveSpreadMenuItem(index: number, key: string) {
    if (this.hasSpreadImage(index)) {
      MenuItem({ content: this.spreadPageLabel(key, index) })
        .onClick(() => {
          this.saveSpreadMenuShown = false
          this.saveImagesAtIndexes([index])
        })
    }
  }

  @Builder
  private OriginalSpreadMenuItem(index: number, key: string) {
    if (this.hasSpreadImage(index)) {
      MenuItem({
        content: this.spreadPageLabel(key, index),
        symbolEndIcon: this.originalModeForIndex(index)
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .enabled(this.originalModeForIndex(index) || this.originalAvailableForIndex(index))
        .onClick(() => {
          this.originalSpreadMenuShown = false
          this.toggleOriginalImagesAtIndexes([index])
        })
    }
  }

  @Builder
  private ReaderSaveSpreadMenu() {
    Menu() {
      this.SaveSpreadMenuItem(this.spreadVisualLeftIndex(), 'reader_spread_left_page')
      this.SaveSpreadMenuItem(this.spreadVisualRightIndex(), 'reader_spread_right_page')
      MenuItem({ content: AppStrings.get('reader_spread_save_both') })
        .onClick(() => {
          this.saveSpreadMenuShown = false
          this.saveImagesAtIndexes(this.spreadVisualIndexes())
        })
    }
  }

  @Builder
  private ReaderOriginalSpreadMenu() {
    Menu() {
      this.OriginalSpreadMenuItem(this.spreadVisualLeftIndex(), 'reader_spread_left_page')
      this.OriginalSpreadMenuItem(this.spreadVisualRightIndex(), 'reader_spread_right_page')
      MenuItem({ content: this.spreadBothOriginalLabel() })
        .enabled(this.originalSpreadBothActionEnabled())
        .onClick(() => {
          this.originalSpreadMenuShown = false
          this.toggleOriginalImagesAtIndexes(this.spreadVisualIndexes())
        })
    }
  }

  @Builder
  ReaderModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.read_mode_ltr'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.LTR)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.LTR
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setReaderMode(ReadMode.LTR)
      })
      MenuItem({
        content: $r('app.string.read_mode_rtl'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.RTL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setReaderMode(ReadMode.RTL)
      })
      MenuItem({
        content: $r('app.string.read_mode_ttb'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.TOP_TO_BOTTOM)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.TOP_TO_BOTTOM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setReaderMode(ReadMode.TOP_TO_BOTTOM)
      })
      MenuItem({
        content: $r('app.string.read_mode_vertical'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.VERTICAL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.VERTICAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setReaderMode(ReadMode.VERTICAL)
      })
    }
  }

  @Builder
  ReaderImageBlockActionMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.reader_image_block_mark') })
        .enabled(!this.imageBlockRuleSaving)
        .onClick(() => {
          this.imageBlockActionMenuShown = false
          this.confirmMarkCurrentImageAsBlocked()
        })
    }
  }

  private hasRenderableThumb(img: EhGalleryImage): boolean {
    return img.sUrl.length > 0 && img.thumbUrl.length > 0
  }

  private hasLocalThumb(img: EhGalleryImage): boolean {
    return this.isLocalReaderSource() && img.imageUrl.startsWith('file://')
  }

  private thumbKey(img: EhGalleryImage): string {
    return `thumb_${img.page}_${this.safeForEachKeyHash(`${img.sUrl}:${img.thumbUrl}`)}`
  }

  private jumpToThumb(index: number): void {
    this.jumpToPage(index)
    this.scrollThumbStripTo(index, true)
  }

  private toggleThumbStrip(): void {
    const nextVisible: boolean = !this.showThumbStrip
    this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, () => {
      this.showThumbStrip = nextVisible
    })
    if (nextVisible) {
      setTimeout(() => {
        this.scrollThumbStripTo(this.vm.currentIndex, false)
      }, 0)
    }
  }

  private scrollThumbStripTo(index: number, animated: boolean): void {
    if (!this.showThumbStrip || index < 0 || index >= this.vm.totalPages()) {
      return
    }
    this.thumbScroller.scrollToIndex(this.thumbListIndexForPageIndex(index), animated)
  }

  private thumbListIndexForPageIndex(index: number): number {
    return index
  }

  private thumbPageIndexes(): number[] {
    const total: number = this.vm.totalPages()
    const out: number[] = []
    for (let i: number = 0; i < total; i++) {
      out.push(i)
    }
    return out
  }

  // Top chrome bar — page count is an overlay at the viewport's geometric center, independent of
  // the asymmetric navigation/action groups behind it.
  @Builder
  ReaderTopBar() {
    Stack({ alignContent: Alignment.Center }) {
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
          this.closeReader()
        })
        Blank()
        Row() {
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
          .bindSheet(
            $$this.settingsSheetShown,
            this.settingsSheetContent(() => {
              this.closeReaderSettings()
            }),
            appSheetOptions({
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              showClose: false,
              onDisappear: () => {
                this.closeReaderSettings()
              },
            }),
          )
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([Color.White])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.common_more_actions'))
          .onClick(() => {
            this.readerTopMoreMenuShown = true
          })
          .bindMenu(this.readerTopMoreMenuShown, this.ReaderTopMoreMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.readerTopMoreMenuShown = false
            },
          })
        }
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      Row({ space: ThemeConstants.SPACE_XS }) {
        Text(this.pageCountText())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .maxLines(1)
        if (this.superResolutionIndicatorVisible()) {
          ReaderSuperResolutionStatusIcon({
            processing: this.currentImageEnhancementProcessing(),
            applied: this.currentImageEnhancementApplied(),
          })
        }
      }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(56)
    .padding({
      top: this.layout.topAvoidHeight,
      left: ThemeConstants.SPACE_SM,
      right: ThemeConstants.SPACE_SM,
    })
    .height(this.layout.topAvoidHeight + 56)
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
        this.ReaderThumbStrip()
      }
      .width('100%')
      .height(this.showThumbStrip ? READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2 : 0)
      .padding({
        top: this.showThumbStrip ? ThemeConstants.SPACE_SM : 0,
        bottom: this.showThumbStrip ? ThemeConstants.SPACE_SM : 0,
      })
      .margin({
        bottom: this.layout.bottomAvoidHeight + READER_BOTTOM_TOOLBAR_HEIGHT,
      })
      .backgroundColor('#CC000000')
      .clip(true)
      .hitTestBehavior(this.showThumbStrip ? HitTestMode.Default : HitTestMode.None)

      Column({ space: ThemeConstants.SPACE_XS }) {
        Row({ space: READER_PROGRESS_SLIDER_GAP }) {
          Text(`${this.readMode.mode === ReadMode.RTL ? this.vm.totalPages() :
            (this.sliderPreview >= 0 ? this.sliderPreview : this.sliderValue)}`)
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
            reverse: this.readMode.mode === ReadMode.RTL,
          })
            .layoutWeight(1)
            .trackColor(READER_CHROME_TRACK_BG)
            .selectedColor(ThemeConstants.BRAND_PRIMARY)
            .onChange((value: number, mode: SliderChangeMode) => {
              const page: number = Math.round(value)
              if (mode === SliderChangeMode.Begin) {
                this.sliderSyncToken++
              }
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
          Text(`${this.readMode.mode === ReadMode.RTL ?
            (this.sliderPreview >= 0 ? this.sliderPreview : this.sliderValue) : this.vm.totalPages()}`)
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
            this.openSaveAction()
          })
          .bindMenu(this.saveSpreadMenuShown, this.ReaderSaveSpreadMenu, {
            placement: Placement.TopRight,
            onDisappear: () => {
              this.saveSpreadMenuShown = false
            },
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
          .enabled(!this.originalImageResolving && this.originalActionEnabled())
          .onClick(() => {
            this.openOriginalAction()
          })
          .bindMenu(this.originalSpreadMenuShown, this.ReaderOriginalSpreadMenu, {
            placement: Placement.TopRight,
            onDisappear: () => {
              this.originalSpreadMenuShown = false
            },
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
            SymbolGlyph($r('sys.symbol.rectangle_grid_2x1'))
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
          if (this.showOnePageStepButton()) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.transfer'))
                .fontSize(READER_CHROME_ICON_SIZE)
                .fontColor([this.onePageIconColor()])
            }
            .width(READER_CHROME_ACTION_SIZE)
            .height(READER_CHROME_ACTION_SIZE)
            .backgroundColor(Color.Transparent)
            .enabled(this.canTurnOnePageInDoublePage())
            .onClick(() => {
              this.turnOnePageInDoublePage()
            })
          }
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([this.doublePageIconColor()])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(
            Color.Transparent
          )
          .enabled(this.isHorizontalPagedMode())
          .onClick(() => {
            this.toggleDoublePage()
          })
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.modeIcon())
              .fontSize(READER_CHROME_ICON_SIZE)
              .fontColor([Color.White])
          }
          .width(READER_CHROME_ACTION_SIZE)
          .height(READER_CHROME_ACTION_SIZE)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.modeLabel())
          .onClick(() => {
            this.readModeMenuShown = true
          })
          .bindMenu(this.readModeMenuShown, this.ReaderModeMenu, {
            placement: Placement.TopRight,
            onDisappear: () => {
              this.readModeMenuShown = false
            },
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
      (this.showThumbStrip ? READER_THUMB_STRIP_HEIGHT + ThemeConstants.SPACE_SM * 2 : 0))
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  ReaderThumbStrip() {
    List({
      initialIndex: this.thumbListIndexForPageIndex(this.vm.currentIndex),
      scroller: this.thumbScroller,
      space: ThemeConstants.SPACE_SM,
    }) {
      ForEach(
        this.thumbPageIndexes(),
        (index: number) => {
          ListItem() {
            this.ReaderThumbItem(index)
          }
          .margin({
            left: (this.readMode.mode === ReadMode.RTL
              ? index === this.vm.totalPages() - 1
              : index === 0) ? ThemeConstants.SPACE_LG : 0,
            right: (this.readMode.mode === ReadMode.RTL
              ? index === 0
              : index === this.vm.totalPages() - 1) ? ThemeConstants.SPACE_LG : 0,
          })
        },
        (index: number) => `thumb_${index}_${this.thumbKey(this.vm.imageAt(index))}`,
      )
    }
    .listDirection(Axis.Horizontal)
    .direction(this.readMode.mode === ReadMode.RTL ? Direction.Rtl : Direction.Ltr)
    .scrollBar(BarState.Off)
    .height(READER_THUMB_STRIP_HEIGHT)
    .width('100%')
  }

  @Builder
  ReaderThumbItem(index: number) {
    ReaderThumbTile({
      index: index,
      currentIndex: this.vm.currentIndex,
      image: this.vm.imageAt(index),
      localImage: this.hasLocalThumb(this.vm.imageAt(index)),
      renderableOnlineThumb: this.hasRenderableThumb(this.vm.imageAt(index)),
      onTap: (target: number) => {
        this.jumpToThumb(target)
      },
      onNeedWarm: (target: number, image: EhGalleryImage) => {
        DiagnosticLogger.info(
          'reader',
          'thumb_placeholder_appear',
          `index ${target} page ${image.page} sUrl ${image.sUrl.length} thumb ${image.thumbUrl.length}`,
        )
        this.vm.warmPreviewForIndex(target, 'thumb-strip')
      },
    })
  }
}

@ComponentV2
struct ReaderPageStatusOverlay {
  @Require @Param value: string
  @Require @Param showPageNumber: boolean
  @Require @Param showEnhancement: boolean
  @Require @Param enhancementProcessing: boolean
  @Require @Param enhancementApplied: boolean
  @Require @Param bottomMargin: number
  private controller: TextController = new TextController()

  @Monitor('value')
  onValueChanged(): void {
    this.updateStyledText()
  }

  private styledText(): MutableStyledString {
    const styled: MutableStyledString = new MutableStyledString(this.value, [])
    styled.setStyle({
      start: 0,
      length: this.value.length,
      styledKey: StyledStringKey.FONT,
      styledValue: new TextStyle({
        fontColor: ThemeConstants.READER_PAGE_NUMBER_TEXT,
        fontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
        fontWeight: FontWeight.Medium,
        strokeWidth: LengthMetrics.vp(-ThemeConstants.READER_PAGE_NUMBER_STROKE_WIDTH),
        strokeColor: ThemeConstants.READER_PAGE_NUMBER_OUTLINE,
      }),
    })
    return styled
  }

  private updateStyledText(): void {
    this.controller.setStyledString(this.styledText())
  }

  build() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      if (this.showPageNumber) {
        Text(undefined, { controller: this.controller })
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .onAppear(() => {
            this.updateStyledText()
          })
      }
      if (this.showEnhancement) {
        ReaderSuperResolutionStatusIcon({
          processing: this.enhancementProcessing,
          applied: this.enhancementApplied,
        })
      }
    }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: this.bottomMargin })
      .hitTestBehavior(HitTestMode.None)
  }
}

@ComponentV2
struct ReaderSuperResolutionStatusIcon {
  @Require @Param processing: boolean
  @Require @Param applied: boolean

  build() {
    if (this.processing) {
      LoadingProgress()
        .width(ThemeConstants.FONT_SIZE_BODY)
        .height(ThemeConstants.FONT_SIZE_BODY)
        .color(Color.White)
        .opacity(ThemeConstants.READER_ENHANCEMENT_STATUS_OPACITY)
    } else {
      SymbolGlyph($r('sys.symbol.AI_hd_rectangle'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor([this.applied ? ThemeConstants.BRAND_PRIMARY : Color.White])
        .opacity(ThemeConstants.READER_ENHANCEMENT_STATUS_OPACITY)
    }
  }
}

@ComponentV2
struct ReaderThumbTile {
  @Require @Param index: number
  @Require @Param currentIndex: number
  @Require @Param image: EhGalleryImage
  @Param localImage: boolean = false
  @Param renderableOnlineThumb: boolean = false
  @Event onTap: (index: number) => void = (_index: number) => {}
  @Event onNeedWarm: (index: number, image: EhGalleryImage) => void =
    (_index: number, _image: EhGalleryImage) => {}
  @Local decodedWidth: number = 0
  @Local decodedHeight: number = 0

  @Monitor('image')
  onLocalSourceChanged(): void {
    this.decodedWidth = 0
    this.decodedHeight = 0
  }

  private sourceWidth(): number {
    if (this.localImage) {
      return this.decodedWidth
    }
    return this.image.thumbWidth
  }

  private sourceHeight(): number {
    if (this.localImage) {
      return this.decodedHeight
    }
    return this.image.thumbHeight
  }

  private thumbSize(): ReaderThumbnailSize {
    return ReaderThumbnailGeometry.fitHeight(this.sourceWidth(), this.sourceHeight())
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.localImage) {
          EhImageKnifeImage({
            src: this.image.imageUrl,
            widthValue: this.thumbSize().width,
            heightValue: this.thumbSize().height,
            objectFit: ImageFit.Contain,
            radius: ThemeConstants.RADIUS_SM,
            memoryOnly: true,
            priority: EH_IMAGE_PRIORITY_LOW,
            downSampling: EH_IMAGE_DOWNSAMPLING_DESIRED_SIZE_ASPECT_FIT,
            desiredWidth: 288,
            desiredHeight: 236,
            onImageInfo: (width: number, height: number) => {
              if (width > 0 && height > 0) {
                this.decodedWidth = width
                this.decodedHeight = height
              }
            },
          })
        } else if (this.renderableOnlineThumb) {
          EhSpriteThumbnail({
            url: this.image.thumbUrl,
            thumbWidth: this.image.thumbWidth,
            thumbHeight: this.image.thumbHeight,
            offsetX: this.image.thumbOffsetX,
            spriteWidth: this.image.spriteWidth,
            spriteHeight: this.image.spriteHeight,
            displayHeight: ReaderThumbnailGeometry.DISPLAY_HEIGHT,
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
          .width(this.thumbSize().width)
          .height(this.thumbSize().height)
          .backgroundColor('#26FFFFFF')
          .borderRadius(ThemeConstants.RADIUS_SM)
          .onAppear(() => {
            this.onNeedWarm(this.index, this.image)
          })
        }
      }
      .width(this.thumbSize().width)
      .height(this.thumbSize().height)
      .border({
        width: this.index === this.currentIndex ? 2 : 0,
        color: this.index === this.currentIndex ? ThemeConstants.BRAND_PRIMARY : Color.Transparent,
      })
      .borderRadius(ThemeConstants.RADIUS_SM)
      .clip(true)

      Text(`${this.index + 1}`)
        .fontSize(ThemeConstants.FONT_SIZE_META)
        .fontColor(this.index === this.currentIndex ? ThemeConstants.BRAND_PRIMARY : Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .height(18)
        .width(this.thumbSize().width)
        .textAlign(TextAlign.Center)
    }
    .width(this.thumbSize().width)
    .height(READER_THUMB_STRIP_HEIGHT)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onTap(this.index)
    })
  }
}

const MIN_DYNAMIC_MAX_SCALE: number = 4
const MAX_DYNAMIC_MAX_SCALE: number = 12
const MAX_EFFECTIVE_MAX_SCALE: number = 48
const NATIVE_SCALE_HEADROOM: number = 2
const DOUBLE_TAP_PRIMARY_SCALE: number = 2
const DOUBLE_TAP_FALLBACK_SCALE: number = 2
const DOUBLE_TAP_SCALE_EPSILON: number = 0.02
const PINCH_ELASTIC_MIN_SCALE: number = 0.8
const PINCH_UNDER_SCALE_RESISTANCE: number = 0.35
const IMAGE_AUTO_RETRY_LIMIT: number = 3

class ReaderZoomCoordinator {
  static isZoomed(scale: number): boolean {
    return scale > 1.01
  }

  static clampScale(value: number, maxScale: number = MIN_DYNAMIC_MAX_SCALE): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value < 1) {
      return 1
    }
    const boundedMax: number = ReaderZoomCoordinator.saneEffectiveMaxScale(maxScale)
    if (value > boundedMax) {
      return boundedMax
    }
    return value
  }

  static clampPinchScale(value: number, maxScale: number = MIN_DYNAMIC_MAX_SCALE): number {
    if (!Number.isFinite(value)) {
      return 1
    }
    if (value >= 1) {
      return ReaderZoomCoordinator.clampScale(value, maxScale)
    }
    const resisted: number = 1 - (1 - value) * PINCH_UNDER_SCALE_RESISTANCE
    return Math.max(PINCH_ELASTIC_MIN_SCALE, resisted)
  }

  static saneMaxScale(value: number): number {
    if (!Number.isFinite(value) || value < MIN_DYNAMIC_MAX_SCALE) {
      return MIN_DYNAMIC_MAX_SCALE
    }
    if (value > MAX_DYNAMIC_MAX_SCALE) {
      return MAX_DYNAMIC_MAX_SCALE
    }
    return value
  }

  static saneEffectiveMaxScale(value: number): number {
    if (!Number.isFinite(value) || value < MIN_DYNAMIC_MAX_SCALE) {
      return MIN_DYNAMIC_MAX_SCALE
    }
    if (value > MAX_EFFECTIVE_MAX_SCALE) {
      return MAX_EFFECTIVE_MAX_SCALE
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

  static nativeScale(
    intrinsicW: number,
    intrinsicH: number,
    displayW: number,
    displayH: number,
  ): number {
    if (intrinsicW <= 0 || intrinsicH <= 0 || displayW <= 0 || displayH <= 0) {
      return DOUBLE_TAP_FALLBACK_SCALE
    }
    const scaleW: number = intrinsicW / displayW
    const scaleH: number = intrinsicH / displayH
    const scale: number = Math.min(scaleW, scaleH)
    return scale > 0 && Number.isFinite(scale) ? scale : DOUBLE_TAP_FALLBACK_SCALE
  }

  static dynamicMaxScale(
    intrinsicW: number,
    intrinsicH: number,
    displayW: number,
    displayH: number,
  ): number {
    const native: number = ReaderZoomCoordinator.nativeScale(intrinsicW, intrinsicH, displayW, displayH)
    return ReaderZoomCoordinator.saneMaxScale(native * NATIVE_SCALE_HEADROOM)
  }

  static scaleForReferenceDisplay(
    targetReferenceScale: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
  ): number {
    if (
      !Number.isFinite(targetReferenceScale) || targetReferenceScale <= 0 ||
      displayW <= 0 || displayH <= 0 || referenceDisplayW <= 0 || referenceDisplayH <= 0
    ) {
      return targetReferenceScale
    }
    const scaleW: number = (referenceDisplayW * targetReferenceScale) / displayW
    const scaleH: number = (referenceDisplayH * targetReferenceScale) / displayH
    const scale: number = Math.min(scaleW, scaleH)
    return scale > 0 && Number.isFinite(scale) ? scale : targetReferenceScale
  }

  static dynamicMaxScaleForDisplay(
    intrinsicW: number,
    intrinsicH: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
  ): number {
    const referenceMax: number = ReaderZoomCoordinator.dynamicMaxScale(
      intrinsicW,
      intrinsicH,
      referenceDisplayW,
      referenceDisplayH,
    )
    return ReaderZoomCoordinator.saneEffectiveMaxScale(
      ReaderZoomCoordinator.scaleForReferenceDisplay(
        referenceMax,
        displayW,
        displayH,
        referenceDisplayW,
        referenceDisplayH,
      ),
    )
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

  static nearScale(first: number, second: number): boolean {
    return Math.abs(first - second) <= DOUBLE_TAP_SCALE_EPSILON
  }

  static nextDoubleTapScale(
    currentScale: number,
    maxScale: number,
    primaryScale: number,
    nativeScale: number,
    pinchAdjusted: boolean,
  ): number {
    if (pinchAdjusted && ReaderZoomCoordinator.isZoomed(currentScale)) {
      return 1
    }
    const primary: number = ReaderZoomCoordinator.clampScale(primaryScale, maxScale)
    const native: number = ReaderZoomCoordinator.clampScale(nativeScale, maxScale)
    if (!ReaderZoomCoordinator.isZoomed(currentScale)) {
      return primary
    }
    if (
      ReaderZoomCoordinator.nearScale(currentScale, primary) &&
      native > 1 + DOUBLE_TAP_SCALE_EPSILON
    ) {
      return native
    }
    return 1
  }

  static doubleTapTarget(
    currentScale: number,
    maxScale: number,
    nativeScale: number,
    pinchAdjusted: boolean = false,
  ): number {
    return ReaderZoomCoordinator.nextDoubleTapScale(
      currentScale,
      maxScale,
      DOUBLE_TAP_PRIMARY_SCALE,
      nativeScale,
      pinchAdjusted,
    )
  }

  static doubleTapTargetForDisplay(
    currentScale: number,
    maxScale: number,
    referenceNativeScale: number,
    displayW: number,
    displayH: number,
    referenceDisplayW: number,
    referenceDisplayH: number,
    pinchAdjusted: boolean = false,
  ): number {
    const primary: number = ReaderZoomCoordinator.scaleForReferenceDisplay(
      DOUBLE_TAP_PRIMARY_SCALE,
      displayW,
      displayH,
      referenceDisplayW,
      referenceDisplayH,
    )
    const native: number = ReaderZoomCoordinator.scaleForReferenceDisplay(
      referenceNativeScale,
      displayW,
      displayH,
      referenceDisplayW,
      referenceDisplayH,
    )
    return ReaderZoomCoordinator.nextDoubleTapScale(
      currentScale,
      maxScale,
      primary,
      native,
      pinchAdjusted,
    )
  }

  static pinchAnchor(
    center: number,
    viewport: number,
    displaySize: number,
    scale: number,
    offset: number
  ): number {
    const displayed: number = displaySize * scale
    if (displayed <= 0) {
      return 0.5
    }
    const displayStart: number = (viewport - displayed) / 2 + offset
    return (center - displayStart) / displayed
  }

  static anchoredOffset(
    center: number,
    viewport: number,
    displaySize: number,
    scale: number,
    anchor: number
  ): number {
    const displayed: number = displaySize * scale
    const point: number = (viewport - displayed) / 2 + displayed * anchor
    return center - point
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

async function readerImageBlockDecisionForFile(
  context: common.UIAbilityContext,
  filePath: string,
  page: number,
): Promise<ImageBlockDecision> {
  try {
    DiagnosticLogger.info(
      'imageknife',
      'reader_imageknife_block_decision',
      `page=${page} fileHash=${DiagnosticLogger.ownerHash(filePath)}`,
    )
    return await ImageBlockRuntimeService.decisionForFile(context, filePath)
  } catch (err) {
    DiagnosticLogger.warn('image-block', 'reader_decision_failed', `page=${page} ${(err as Error).message}`)
    return new ImageBlockDecision()
  }
}

function readerLogImageBlocked(page: number, decision: ImageBlockDecision): void {
  DiagnosticLogger.info(
    'image-block',
    'reader_image_blocked',
    `page=${page} source=${decision.sourceType} feed=${decision.feedId} rule=${DiagnosticLogger.ownerHash(decision.ruleId)} distance=${decision.distance} threshold=${decision.threshold}`,
  )
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
struct ReaderInterpolatedImage {
  @Param src: string = '';
  @Param widthValue: Length = '100%';
  @Param heightValue: Length = '100%';
  @Event onComplete: (event?: ReaderImageLoadEvent) => void = (_event?: ReaderImageLoadEvent) => {};
  @Event onError: () => void = () => {};
  @Local readMode: ReadModeState = connectReadMode();

  build() {
    // ImageKnifePro 1.0.16 does not expose ArkUI interpolation for its native Image node. Reader
    // sources are already local file-cache URIs, so preserve the Reader download/cache pipeline and
    // use system Image only for the final sampled render.
    Image(this.src)
      .objectFit(ImageFit.Contain)
      .interpolation(readerImageInterpolation(this.readMode.imageScalingQuality))
      .width(this.widthValue)
      .height(this.heightValue)
      .draggable(false)
      .onComplete((event?: ReaderImageLoadEvent) => {
        this.onComplete(event)
      })
      .onError(() => {
        this.onError()
      })
  }
}

function readerImageFormatFromFile(filePath: string): string {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
    const buffer: ArrayBuffer = new ArrayBuffer(16)
    const read: number = fileIo.readSync(file.fd, buffer, { length: 16 })
    const bytes: Uint8Array = new Uint8Array(buffer, 0, read)
    if (read >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'JPEG'
    }
    if (read >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
      return 'PNG'
    }
    if (read >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return 'GIF'
    }
    if (read >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'WebP'
    }
    if (read >= 12 && bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
      if (bytes[8] === 0x61 && bytes[9] === 0x76 && bytes[10] === 0x69 && (bytes[11] === 0x66 || bytes[11] === 0x73)) {
        return 'AVIF'
      }
      return 'HEIF'
    }
  } catch (err) {
    DiagnosticLogger.warn('reader', 'image_format_read_failed', (err as Error).message)
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
  return AppStrings.get('reader_image_info_unknown')
}

@ComponentV2
struct ReaderCacheWarmImage {
  @Param page: number = 0;
  @Param sourceUrl: string = '';
  @Param imageKey: string = '';
  @Param fileCacheKey: string = '';
  @Param translateX: number = 0;
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageFileReady: (page: number, filePath: string, bytes: number) => void =
    (_page: number, _filePath: string, _bytes: number) => {};

  private warmingKey: string = '';
  private warmingUrl: string = '';
  private warmedKey: string = '';
  private decodedKey: string = '';
  @Local warmDisplayUri: string = '';

  aboutToAppear(): void {
    this.warm()
  }

  aboutToDisappear(): void {
    this.cancelQueuedWarm()
  }

  @Monitor('sourceUrl')
  onSourceUrlChanged(): void {
    this.cancelQueuedWarm()
    this.warm()
  }

  @Monitor('imageKey')
  onImageKeyChanged(): void {
    this.cancelQueuedWarm()
    this.warm()
  }

  @Monitor('fileCacheKey')
  onFileCacheKeyChanged(): void {
    this.cancelQueuedWarm()
    this.warm()
  }

  private cacheKey(): string {
    return this.fileCacheKey
  }

  private markReady(result: CachedImageFileResult, key: string): void {
    this.warmedKey = key
    this.warmDisplayUri = result.displayUri
    this.onImageFileReady(this.page, result.filePath, result.bytes)
  }

  private async warmByImageKnifeOrFallback(
    context: common.UIAbilityContext,
    key: string,
    url: string,
  ): Promise<void> {
    try {
      const result: CachedImageFileResult = await ImagePipelineService.loadReaderFile(
        context,
        url,
        key,
        EH_IMAGE_PRIORITY_LOW,
      )
      if (this.warmingKey !== key || this.warmingUrl !== url) {
        return
      }
      DiagnosticLogger.info('image-cache', 'reader_warm_complete', `page ${this.page} ${result.bytes} bytes`)
      this.markReady(result, key)
    } catch (err) {
      if (this.warmingKey === key && this.warmingUrl === url) {
        DiagnosticLogger.warn('image-cache', 'reader_warm_failed', `page ${this.page}: ${(err as Error).message}`)
      }
    } finally {
      if (this.warmingKey === key && this.warmingUrl === url) {
        this.warmingKey = ''
        this.warmingUrl = ''
      }
    }
  }

  private cancelQueuedWarm(): void {
    if (this.warmingKey.length === 0) {
      return
    }
    const key: string = this.warmingKey
    this.warmingKey = ''
    this.warmingUrl = ''
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ImagePipelineService.cancelQueuedReaderFile(context, key)
  }

  private warm(): void {
    if (this.page <= 0 || this.fileCacheKey.length === 0) {
      this.cancelQueuedWarm()
      this.warmDisplayUri = ''
      return
    }
    const key: string = this.cacheKey()
    const url: string = this.sourceUrl
    if (key === this.warmedKey || (key === this.warmingKey && url === this.warmingUrl)) {
      return
    }
    this.cancelQueuedWarm()
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    const cached: CachedImageFileResult | null = ImagePipelineService.cachedReaderFile(context, key)
    if (cached !== null) {
      this.markReady(cached, key)
      return
    }
    if (url.length === 0) {
      this.warmDisplayUri = ''
      return
    }
    this.warmingKey = key
    this.warmingUrl = url
    this.warmDisplayUri = ''
    this.warmByImageKnifeOrFallback(context, key, url)
  }

  build() {
    if (this.warmDisplayUri.length > 0) {
      ReaderInterpolatedImage({
        src: this.warmDisplayUri,
        widthValue: '100%',
        heightValue: '100%',
        onComplete: (_event?: ReaderImageLoadEvent) => {
          if (this.decodedKey === this.warmedKey) {
            return
          }
          this.decodedKey = this.warmedKey
          this.onImageLoaded(this.page)
          DiagnosticLogger.info('image-cache', 'reader_warm_decoded', `page ${this.page}`)
          DiagnosticLogger.info('image', 'reader_image_display_decoded', `page=${this.page} warm=true`)
        },
        onError: () => {
          DiagnosticLogger.warn('image-cache', 'reader_warm_decode_failed', `page ${this.page}`)
        },
      })
        .translate({ x: this.translateX, y: 0 })
    }
  }
}

@ComponentV2
struct ReaderSpreadSurface {
  @Param first: EhGalleryImage = new EhGalleryImage();
  @Param second: EhGalleryImage = new EhGalleryImage();
  @Param localSource: boolean = false;
  @Param firstFileCacheKey: string = '';
  @Param secondFileCacheKey: string = '';
  @Param hasFirst: boolean = false;
  @Param hasSecond: boolean = false;
  @Param firstPreferOriginal: boolean = false;
  @Param secondPreferOriginal: boolean = false;
  @Param firstInitiallyLoaded: boolean = false;
  @Param secondInitiallyLoaded: boolean = false;
  @Param viewportW: number = 0;
  @Param viewportH: number = 0;
  @Param imageBlockRuleVersion: number = 0;
  @Param imageBlockWhitelistSaving: boolean = false;
  @Param loadedSignal: number = 0;
  @Param sourceReloadPage: number = 0;
  @Param sourceReloadRequestId: number = 0;
  @Param rowReversed: boolean = false;
  @Param spreadLayoutMode: string = ReadSpreadLayout.JOINED;
  @Param activeIndex: number = 0;
  @Param doubleTapSeq: number = 0;
  @Param doubleTapX: number = 0;
  @Param doubleTapY: number = 0;
  @Param doubleTapTargetPage: number = 0;
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageFileReady: (page: number, filePath: string, bytes: number) => void =
    (_page: number, _filePath: string, _bytes: number) => {};
  @Param onImageBlockState: (page: number, blocked: boolean) => void =
    (_page: number, _blocked: boolean) => {};
  @Param onAllowImageBlock: (page: number) => void = (_page: number) => {};
  @Param onImageMetrics: (page: number, width: number, height: number) => void =
    (_page: number, _width: number, _height: number) => {};
  @Param onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => void =
    (_page: number, _model: string, _applied: boolean, _reason: string) => {};

  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local zoomAnimating: boolean = false;
  @Local firstIntrinsicW: number = 0;
  @Local firstIntrinsicH: number = 0;
  @Local secondIntrinsicW: number = 0;
  @Local secondIntrinsicH: number = 0;
  @Local compW: number = 0;
  @Local compH: number = 0;
  @Local zoomFocusPage: number = 0;

  private pinchStartScale: number = 1;
  private pinchAnchorX: number = 0.5;
  private pinchAnchorY: number = 0.5;
  private panStartOffX: number = 0;
  private panStartOffY: number = 0;
  private isPinching: boolean = false;
  private pinchAdjustedSinceDoubleTap: boolean = false;
  private ignorePanSequence: boolean = false;
  private lastZoomed: boolean = false;
  private zoomAnimatingTimerId: number = 0;

  aboutToAppear(): void {
    this.applyViewportFallback()
  }

  @Monitor('viewportW')
  onViewportWChanged(): void {
    this.applyViewportFallback()
  }

  @Monitor('viewportH')
  onViewportHChanged(): void {
    this.applyViewportFallback()
  }

  private applyViewportFallback(): void {
    if (this.compW <= 0 && this.viewportW > 0) {
      this.compW = this.viewportW
    }
    if (this.compH <= 0 && this.viewportH > 0) {
      this.compH = this.viewportH
    }
  }

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
      this.zoomFocusPage = 0
    }
  }

  private pageForPoint(x: number): number {
    if (!this.hasSecond) {
      return this.hasFirst ? this.first.page : 0
    }
    let leftPane: boolean = x < this.compW / 2
    if (this.usesJoinedLayout()) {
      const leftEdge: number = (this.compW - this.joinedFrameW()) / 2
      const leftVisualPage: number = this.rowReversed ? this.second.page : this.first.page
      const boundary: number = leftEdge + this.paneWidthForPage(leftVisualPage)
      leftPane = x < boundary
    }
    if (this.rowReversed) {
      return leftPane ? this.second.page : this.first.page
    }
    return leftPane ? this.first.page : this.second.page
  }

  private intrinsicWForPage(page: number): number {
    if (this.hasFirst && this.first.page === page) {
      return this.firstIntrinsicW
    }
    if (this.hasSecond && this.second.page === page) {
      return this.secondIntrinsicW
    }
    return 0
  }

  private intrinsicHForPage(page: number): number {
    if (this.hasFirst && this.first.page === page) {
      return this.firstIntrinsicH
    }
    if (this.hasSecond && this.second.page === page) {
      return this.secondIntrinsicH
    }
    return 0
  }

  private imageFitScaleForPage(page: number): number {
    return ReaderZoomCoordinator.fitScale(
      this.paneWidthForPage(page),
      this.paneHeightForPage(page),
      this.intrinsicWForPage(page),
      this.intrinsicHForPage(page),
    )
  }

  private imageDisplayWForPage(page: number): number {
    return ReaderZoomCoordinator.displaySize(
      this.paneWidthForPage(page),
      this.intrinsicWForPage(page),
      this.imageFitScaleForPage(page),
    )
  }

  private imageDisplayHForPage(page: number): number {
    return ReaderZoomCoordinator.displaySize(
      this.paneHeightForPage(page),
      this.intrinsicHForPage(page),
      this.imageFitScaleForPage(page),
    )
  }

  private referenceFitScaleForPage(page: number): number {
    return ReaderZoomCoordinator.fitScale(
      this.compW,
      this.compH,
      this.intrinsicWForPage(page),
      this.intrinsicHForPage(page),
    )
  }

  private referenceDisplayWForPage(page: number): number {
    return ReaderZoomCoordinator.displaySize(
      this.compW,
      this.intrinsicWForPage(page),
      this.referenceFitScaleForPage(page),
    )
  }

  private referenceDisplayHForPage(page: number): number {
    return ReaderZoomCoordinator.displaySize(
      this.compH,
      this.intrinsicHForPage(page),
      this.referenceFitScaleForPage(page),
    )
  }

  private referenceNativeScaleForPage(page: number): number {
    return ReaderZoomCoordinator.nativeScale(
      this.intrinsicWForPage(page),
      this.intrinsicHForPage(page),
      this.referenceDisplayWForPage(page),
      this.referenceDisplayHForPage(page),
    )
  }

  private maxScaleForPage(page: number): number {
    return ReaderZoomCoordinator.dynamicMaxScaleForDisplay(
      this.intrinsicWForPage(page),
      this.intrinsicHForPage(page),
      this.imageDisplayWForPage(page),
      this.imageDisplayHForPage(page),
      this.referenceDisplayWForPage(page),
      this.referenceDisplayHForPage(page),
    )
  }

  private activeMaxScale(): number {
    if (this.includesPage(this.zoomFocusPage)) {
      return this.maxScaleForPage(this.zoomFocusPage)
    }
    const page: number = this.activeIndex + 1
    if (this.includesPage(page)) {
      return this.maxScaleForPage(page)
    }
    return this.maxScaleForPage(this.hasFirst ? this.first.page : 0)
  }

  private clampScale(value: number, maxScale: number = this.activeMaxScale()): number {
    return ReaderZoomCoordinator.clampScale(value, maxScale)
  }

  private paneCount(): number {
    return this.hasSecond ? 2 : 1
  }

  private paneWidth(): number {
    const count: number = this.paneCount()
    if (count <= 1) {
      return this.compW
    }
    return this.compW / count
  }

  private usesJoinedLayout(): boolean {
    return this.hasFirst && this.hasSecond && this.spreadLayoutMode === ReadSpreadLayout.JOINED
  }

  private saneImageRatio(width: number, height: number): number {
    if (width > 0 && height > 0) {
      const ratio: number = width / height
      return ratio > 0 && Number.isFinite(ratio) ? ratio : 0.75
    }
    return 0.75
  }

  private imageRatioForPage(page: number): number {
    return this.saneImageRatio(this.intrinsicWForPage(page), this.intrinsicHForPage(page))
  }

  private joinedRatioBoth(): number {
    if (!this.usesJoinedLayout()) {
      return this.saneImageRatio(this.compW, this.compH)
    }
    const ratio: number = this.imageRatioForPage(this.first.page) + this.imageRatioForPage(this.second.page)
    return ratio > 0 && Number.isFinite(ratio) ? ratio : 1.5
  }

  private joinedFrameH(): number {
    if (!this.usesJoinedLayout()) {
      return this.compH
    }
    const ratioBoth: number = this.joinedRatioBoth()
    if (this.compW <= 0 || this.compH <= 0 || ratioBoth <= 0) {
      return this.compH
    }
    const fitByWidth: number = this.compW / ratioBoth
    const height: number = Math.min(this.compH, fitByWidth)
    return height > 0 && Number.isFinite(height) ? height : this.compH
  }

  private joinedFrameW(): number {
    if (!this.usesJoinedLayout()) {
      return this.compW
    }
    const width: number = this.joinedFrameH() * this.joinedRatioBoth()
    return width > 0 && Number.isFinite(width) ? width : this.compW
  }

  private paneWidthForPage(page: number): number {
    if (!this.usesJoinedLayout()) {
      return this.paneWidth()
    }
    const width: number = this.joinedFrameH() * this.imageRatioForPage(page)
    return width > 0 && Number.isFinite(width) ? width : this.paneWidth()
  }

  private paneHeightForPage(_page: number): number {
    return this.usesJoinedLayout() ? this.joinedFrameH() : this.compH
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
    if (this.usesJoinedLayout()) {
      return this.joinedFrameW()
    }
    const firstW: number = this.hasFirst ? this.imageDisplayW(this.firstIntrinsicW, this.firstIntrinsicH) : 0
    const secondW: number = this.hasSecond ? this.imageDisplayW(this.secondIntrinsicW, this.secondIntrinsicH) : 0
    const total: number = firstW + secondW
    return total > 0 ? total : this.compW
  }

  private displayH(): number {
    if (this.usesJoinedLayout()) {
      return this.joinedFrameH()
    }
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
    this.zoomScale = this.clampScale(this.zoomScale)
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
  }

  private resetZoom(): void {
    this.zoomScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.pinchAdjustedSinceDoubleTap = false
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
    const page: number = this.pageForPoint(tapX)
    this.zoomFocusPage = page
    const maxScale: number = this.maxScaleForPage(page)
    const target: number = ReaderZoomCoordinator.doubleTapTargetForDisplay(
      this.zoomScale,
      maxScale,
      this.referenceNativeScaleForPage(page),
      this.imageDisplayWForPage(page),
      this.imageDisplayHForPage(page),
      this.referenceDisplayWForPage(page),
      this.referenceDisplayHForPage(page),
      this.pinchAdjustedSinceDoubleTap,
    )
    this.pinchAdjustedSinceDoubleTap = false
    if (target === 1) {
      this.resetZoom()
      this.notifyZoom()
      return
    }
    const anchorX: number = ReaderZoomCoordinator.pinchAnchor(tapX, this.compW, this.displayW(), this.zoomScale, this.offsetX)
    const anchorY: number = ReaderZoomCoordinator.pinchAnchor(tapY, this.compH, this.displayH(), this.zoomScale, this.offsetY)
    const nextX: number = ReaderZoomCoordinator.anchoredOffset(tapX, this.compW, this.displayW(), target, anchorX)
    const nextY: number = ReaderZoomCoordinator.anchoredOffset(tapY, this.compH, this.displayH(), target, anchorY)
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

  private spreadImageKey(image: EhGalleryImage, preferOriginal: boolean): string {
    return `${image.page}-${image.sUrl}-${preferOriginal ? 'orig' : 'fit'}-${this.imageBlockRuleVersion}`
  }

  private fileCacheKeyForPage(page: number): string {
    return this.hasFirst && this.first.page === page ? this.firstFileCacheKey : this.secondFileCacheKey
  }

  private isActiveSpread(): boolean {
    const activePage: number = this.activeIndex + 1
    return (this.hasFirst && this.first.page === activePage) ||
      (this.hasSecond && this.second.page === activePage)
  }

  @Builder
  SpreadImageLayer(image: EhGalleryImage, hasImage: boolean, preferOriginal: boolean, initiallyLoaded: boolean) {
    if (hasImage) {
      ReaderSpreadImageLayer({
        image: image,
        localSource: this.localSource,
        imageKey: this.spreadImageKey(image, preferOriginal),
        fileCacheKey: this.fileCacheKeyForPage(image.page),
        preferOriginal: preferOriginal,
        initiallyLoaded: initiallyLoaded,
        loadedSignal: this.loadedSignal,
        imageBlockWhitelistSaving: this.imageBlockWhitelistSaving,
        sourceReloadPage: this.sourceReloadPage,
        sourceReloadRequestId: this.sourceReloadRequestId,
        active: this.isActiveSpread(),
        onImageLoaded: (page: number) => {
          this.onImageLoaded(page)
        },
        onImageFileReady: (page: number, filePath: string, bytes: number) => {
          this.onImageFileReady(page, filePath, bytes)
        },
        onImageBlockState: (page: number, blocked: boolean) => {
          this.onImageBlockState(page, blocked)
        },
        onAllowImageBlock: (page: number) => {
          this.onAllowImageBlock(page)
        },
        onImageMetrics: (page: number, width: number, height: number) => {
          this.recordImageMetrics(page, width, height)
          this.onImageMetrics(page, width, height)
        },
        onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => {
          this.onImageEnhancementState(page, model, applied, reason)
        },
      })
    } else {
      Blank()
    }
  }

  @Builder
  SpreadImageSlot(image: EhGalleryImage, hasImage: boolean, preferOriginal: boolean, initiallyLoaded: boolean) {
    Column() {
      this.SpreadImageLayer(image, hasImage, preferOriginal, initiallyLoaded)
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  JoinedSpreadImageSlot(image: EhGalleryImage, hasImage: boolean, preferOriginal: boolean, initiallyLoaded: boolean) {
    Column() {
      this.SpreadImageLayer(image, hasImage, preferOriginal, initiallyLoaded)
    }
    .width(this.paneWidthForPage(image.page))
    .height(this.joinedFrameH())
  }

  build() {
    Stack() {
      if (this.usesJoinedLayout()) {
        Row() {
          if (this.rowReversed) {
            this.JoinedSpreadImageSlot(this.second, true, this.secondPreferOriginal, this.secondInitiallyLoaded)
            this.JoinedSpreadImageSlot(this.first, true, this.firstPreferOriginal, this.firstInitiallyLoaded)
          } else {
            this.JoinedSpreadImageSlot(this.first, true, this.firstPreferOriginal, this.firstInitiallyLoaded)
            this.JoinedSpreadImageSlot(this.second, true, this.secondPreferOriginal, this.secondInitiallyLoaded)
          }
        }
        .width(this.joinedFrameW())
        .height(this.joinedFrameH())
        .justifyContent(FlexAlign.Center)
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.offsetX, y: this.offsetY })
        .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
      } else {
        Row() {
          if (!this.hasSecond) {
            this.SpreadImageSlot(this.first, this.hasFirst, this.firstPreferOriginal, this.firstInitiallyLoaded)
          } else if (this.rowReversed) {
            this.SpreadImageSlot(this.second, true, this.secondPreferOriginal, this.secondInitiallyLoaded)
            this.SpreadImageSlot(this.first, this.hasFirst, this.firstPreferOriginal, this.firstInitiallyLoaded)
          } else {
            this.SpreadImageSlot(this.first, this.hasFirst, this.firstPreferOriginal, this.firstInitiallyLoaded)
            this.SpreadImageSlot(this.second, true, this.secondPreferOriginal, this.secondInitiallyLoaded)
          }
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.offsetX, y: this.offsetY })
        .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
      }
    }
    .alignContent(Alignment.Center)
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
            this.ignorePanSequence = true
            this.zoomAnimating = false
            this.zoomFocusPage = this.pageForPoint(e.pinchCenterX as number)
            this.pinchStartScale = this.zoomScale
            this.pinchAnchorX = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              this.zoomScale,
              this.offsetX
            )
            this.pinchAnchorY = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              this.zoomScale,
              this.offsetY
            )
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e) {
              return
            }
            this.zoomFocusPage = this.pageForPoint(e.pinchCenterX as number)
            const nextScale: number = ReaderZoomCoordinator.clampPinchScale(
              this.pinchStartScale * (e.scale as number),
              this.maxScaleForPage(this.zoomFocusPage),
            )
            this.pinchAdjustedSinceDoubleTap = true
            const nextX: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              nextScale,
              this.pinchAnchorX
            )
            const nextY: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              nextScale,
              this.pinchAnchorY
            )
            const clampedX: number = this.clampOffsetX(nextX, nextScale)
            const clampedY: number = this.clampOffsetY(nextY, nextScale)
            this.zoomScale = nextScale
            this.offsetX = clampedX
            this.offsetY = clampedY
          })
          .onActionEnd(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          })
          .onActionCancel(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: this.panDistance() })
          .onActionStart(() => {
            this.ignorePanSequence = this.isPinching
            this.panStartOffX = this.offsetX
            this.panStartOffY = this.offsetY
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e || this.ignorePanSequence || this.isPinching || !ReaderZoomCoordinator.isZoomed(this.zoomScale)) {
              return
            }
            this.offsetX = this.clampOffsetX(this.panStartOffX + (e.offsetX as number), this.zoomScale)
            this.offsetY = this.clampOffsetY(this.panStartOffY + (e.offsetY as number), this.zoomScale)
          })
          .onActionEnd(() => {
            this.ignorePanSequence = false
          }),
      ),
    )
  }
}

@ComponentV2
struct ReaderSpreadImageLayer {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Param localSource: boolean = false;
  @Param imageKey: string = '';
  @Param fileCacheKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param sourceReloadPage: number = 0;
  @Param sourceReloadRequestId: number = 0;
  @Param imageBlockWhitelistSaving: boolean = false;
  @Param active: boolean = false;
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageFileReady: (page: number, filePath: string, bytes: number) => void =
    (_page: number, _filePath: string, _bytes: number) => {};
  @Param onImageBlockState: (page: number, blocked: boolean) => void =
    (_page: number, _blocked: boolean) => {};
  @Param onAllowImageBlock: (page: number) => void = (_page: number) => {};
  @Param onImageMetrics: (page: number, width: number, height: number) => void =
    (_page: number, _width: number, _height: number) => {};
  @Param onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => void =
    (_page: number, _model: string, _applied: boolean, _reason: string) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local imageBlocked: boolean = false;
  @Local imageBlockPreviewUri: string = '';
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local readMode: ReadModeState = connectReadMode();
  private autoRetryCount: number = 0;
  private sourceRequests: ReaderImageSourceRequestGate = new ReaderImageSourceRequestGate();
  private resolvedFilePath: string = '';
  private resolvedDisplayUri: string = '';

  aboutToAppear(): void {
    this.resolve()
  }

  aboutToDisappear(): void {
    this.sourceRequests.invalidate()
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

  @Monitor('sourceReloadRequestId')
  onSourceReloadRequested(): void {
    if (this.sourceReloadRequestId > 0 && this.sourceReloadPage === this.image.page) {
      this.retrySource()
    }
  }

  @Monitor('active')
  onActiveChanged(): void {
    if (!this.active || this.imageBlocked) {
      return
    }
    if (this.imageUrl.length === 0) {
      this.resolve()
      return
    }
    if (this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  @Monitor('readMode.superResolutionEnabled', 'readMode.superResolutionModel',
    'readMode.superResolutionBackend',
    'readMode.superResolutionMaxHeight')
  onSuperResolutionSettingChanged(): void {
    if (this.resolvedDisplayUri.length > 0) {
      this.imageUrl = this.resolvedDisplayUri
    }
    if (this.active && !this.imageBlocked && this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  private resetImageState(): void {
    this.autoRetryCount = 0
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
  }

  private async resolve(changeSource: boolean = false): Promise<void> {
    const source: ReaderImageSourceRequest = this.sourceRequests.begin(
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
    if (!changeSource && !source.image.imageUrl.startsWith('file://')) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const cached: CachedImageFileResult | null =
        ImagePipelineService.cachedReaderFile(context, source.fileCacheKey)
      if (cached !== null) {
        await this.loadResolvedImage(source, '', cached)
        return
      }
    }
    if (source.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        this.imageBlocked = false
        this.imageBlockPreviewUri = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(source.image, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        source.image.originImageUrl = original
        if (!this.commitResolvedSource(source)) {
          return
        }
        DiagnosticLogger.info('reader', 'display_original', `page ${source.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(source, original, undefined, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        if (!this.isCurrentSource(source)) {
          return
        }
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'spread_original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && source.image.imageUrl.length > 0) {
      await this.loadResolvedImage(source, source.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(source.image, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      source.image.imageUrl = resolved
      if (!this.commitResolvedSource(source)) {
        return
      }
      await this.loadResolvedImage(source, resolved, undefined, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      if (!this.isCurrentSource(source)) {
        return
      }
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'spread_resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(
    source: ReaderImageSourceRequest,
    resolved: string,
    cachedResult?: CachedImageFileResult,
    forceReload: boolean = false,
  ): Promise<void> {
    if (!this.isCurrentSource(source)) {
      return
    }
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result: CachedImageFileResult = cachedResult !== undefined
      ? cachedResult
      : await ImagePipelineService.loadReaderFile(
          context,
          resolved,
          source.fileCacheKey,
          this.loadPriority(),
          (progress: CachedImageProgress) => {
            if (!this.isCurrentSource(source)) {
              return
            }
            this.imageProgressLoaded = progress.loaded
            this.imageProgressTotal = progress.total
          },
          forceReload,
        )
    if (!this.isCurrentSource(source)) {
      return
    }
    this.onImageFileReady(source.image.page, result.filePath, result.bytes)
    this.imageProgressLoaded = result.bytes
    this.imageProgressTotal = result.bytes
    if (!ReaderImageLoadPresentation.shouldSkipCompletionHold(result)) {
      await readerDelay(READER_LOADING_COMPLETION_HOLD_MS)
    }
    if (!this.isCurrentSource(source)) {
      return
    }
    if (await this.applyImageBlockDecision(source, context, result.filePath, result.bytes, result.displayUri)) {
      return
    }
    this.imageUrl = result.displayUri
    this.resolvedFilePath = result.filePath
    this.resolvedDisplayUri = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    if (this.active) {
      this.applySuperResolution(result.filePath, result.displayUri, source.fileCacheKey, this.imageKey)
    }
  }

  private async applySuperResolution(
    filePath: string,
    displayUri: string,
    fileCacheKey: string,
    imageKey: string,
  ): Promise<void> {
    if (!this.active || this.imageBlocked) {
      return
    }
    const enabled: boolean = this.readMode.superResolutionEnabled
    const model: string = this.readMode.superResolutionModel
    const backend: string = this.readMode.superResolutionBackend
    const maxHeight: number = this.readMode.superResolutionMaxHeight
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.onImageEnhancementState(
      this.image.page,
      model,
      false,
      enabled && model !== ReaderSuperResolutionModel.NONE ? 'queued' : 'disabled',
    )
    const result: ReaderSuperResolutionResult = await ReaderSuperResolutionService.process(
      context,
      filePath,
      fileCacheKey,
      (state: ReaderSuperResolutionTaskState): void => {
        this.onImageEnhancementState(this.image.page, model, false, state)
      },
    )
    if (!this.active || this.imageBlocked ||
      this.readMode.superResolutionEnabled !== enabled ||
      this.readMode.superResolutionModel !== model ||
      this.readMode.superResolutionBackend !== backend ||
      this.readMode.superResolutionMaxHeight !== maxHeight ||
      this.fileCacheKey !== fileCacheKey || this.imageKey !== imageKey ||
      this.resolvedFilePath !== filePath || this.resolvedDisplayUri !== displayUri) {
      return
    }
    this.onImageEnhancementState(this.image.page, model, result.applied, result.reason)
    if (result.applied) {
      this.imageUrl = result.displayUri
    }
  }

  private loadPriority(): number {
    return ReaderImageLoadPriority.forVisible(this.active)
  }

  private async applyImageBlockDecision(
    source: ReaderImageSourceRequest,
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
    displayUri: string,
  ): Promise<boolean> {
    const decision: ImageBlockDecision = await readerImageBlockDecisionForFile(context, filePath, source.image.page)
    if (!this.isCurrentSource(source)) {
      return true
    }
    if (!decision.blocked) {
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.onImageBlockState(source.image.page, false)
      return false
    }
    this.imageBlocked = true
    this.imageBlockPreviewUri = displayUri
    this.onImageBlockState(source.image.page, true)
    this.imageUrl = ''
    this.imageLoaded = true
    this.imageProgressLoaded = bytes
    this.imageProgressTotal = bytes
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.onImageLoaded(source.image.page)
    readerLogImageBlocked(source.image.page, decision)
    return true
  }

  private isCurrentSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.isCurrent(
      source,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private commitResolvedSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.commitResolvedImage(
      source,
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!this.localSource) {
      ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
    }
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(!this.localSource)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!this.localSource) {
        ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
      }
      this.autoRetryCount++
      this.sourceRequests.invalidate()
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.failed = false
      this.resolve(!this.localSource)
      return
    }
    this.failed = true
  }

  private markImageLoaded(): void {
    this.autoRetryCount = 0
    if (!this.imageLoaded) {
      this.imageLoaded = true
      this.onImageLoaded(this.image.page)
    }
  }

  private onImageDecoded(width: number, height: number): void {
    this.markImageLoaded()
    if (width > 0 && height > 0) {
      this.onImageMetrics(this.image.page, width, height)
    }
    DiagnosticLogger.info(
      'image',
      'reader_image_display_decoded',
      `page=${this.image.page} width=${width} height=${height}`,
    )
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
        ReaderInterpolatedImage({
          src: this.imageUrl,
          widthValue: '100%',
          heightValue: '100%',
          onComplete: (event?: ReaderImageLoadEvent) => {
            if (event && event.width && event.height) {
              this.onImageDecoded(event.width, event.height)
            } else {
              this.markImageLoaded()
            }
          },
          onError: () => {
            DiagnosticLogger.warn('reader', 'spread_image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          },
        })
      } else if (this.imageBlocked) {
        ReaderImageBlockedOverlay({
          page: this.image.page,
          previewUri: this.imageBlockPreviewUri,
          allowing: this.imageBlockWhitelistSaving,
          onAllow: (page: number) => {
            this.onAllowImageBlock(page)
          },
        })
      }
      // Keep one loading subtree alive across resolving and connection setup. Replacing it when
      // only the label changes restarts the in-flight indeterminate animation at the leading edge.
      if (!this.failed && !this.imageBlocked && !this.imageLoaded) {
        ReaderLoadingStage({
          label: this.imageUrl.length > 0
            ? $r('app.string.reader_loading_decoding')
            : this.sourceImageUrl.length > 0
              ? $r('app.string.reader_loading_image')
              : $r('app.string.reader_loading_resolving'),
          loaded: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressLoaded
            : 0,
          total: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressTotal
            : 0,
        })
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
  @Param localSource: boolean = false;
  @Param imageKey: string = '';
  @Param fileCacheKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param sourceReloadPage: number = 0;
  @Param sourceReloadRequestId: number = 0;
  @Param imageBlockWhitelistSaving: boolean = false;
  @Param activeIndex: number = 0;
  @Param doubleTapSeq: number = 0;
  @Param doubleTapX: number = 0;
  @Param doubleTapY: number = 0;
  @Param doubleTapTargetPage: number = 0;
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageFileReady: (page: number, filePath: string, bytes: number) => void =
    (_page: number, _filePath: string, _bytes: number) => {};
  @Param onImageBlockState: (page: number, blocked: boolean) => void =
    (_page: number, _blocked: boolean) => {};
  @Param onAllowImageBlock: (page: number) => void = (_page: number) => {};
  @Param onImageMetrics: (page: number, width: number, height: number) => void =
    (_page: number, _width: number, _height: number) => {};
  @Param onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => void =
    (_page: number, _model: string, _applied: boolean, _reason: string) => {};

  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local imageBlocked: boolean = false;
  @Local imageBlockPreviewUri: string = '';
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local zoomAnimating: boolean = false;
  @Local intrinsicW: number = 0;
  @Local intrinsicH: number = 0;
  @Local readMode: ReadModeState = connectReadMode();

  private pinchStartScale: number = 1;
  private pinchAnchorX: number = 0.5;
  private pinchAnchorY: number = 0.5;
  private panStartOffX: number = 0;
  private panStartOffY: number = 0;
  private isPinching: boolean = false;
  private pinchAdjustedSinceDoubleTap: boolean = false;
  private ignorePanSequence: boolean = false;
  private compW: number = 0;
  private compH: number = 0;
  private lastZoomed: boolean = false;
  private autoRetryCount: number = 0;
  private sourceRequests: ReaderImageSourceRequestGate = new ReaderImageSourceRequestGate();
  private zoomAnimatingTimerId: number = 0;
  private resolvedFilePath: string = '';
  private resolvedDisplayUri: string = '';

  aboutToAppear(): void {
    this.resolve()
  }

  aboutToDisappear(): void {
    this.sourceRequests.invalidate()
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

  @Monitor('sourceReloadRequestId')
  onSourceReloadRequested(): void {
    if (this.sourceReloadRequestId > 0 && this.sourceReloadPage === this.image.page) {
      this.retrySource()
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
    if (!this.isActive()) {
      this.resetZoom()
      this.notifyZoom()
      return
    }
    if (this.imageUrl.length === 0 && !this.imageBlocked) {
      this.resolve()
      return
    }
    if (!this.imageBlocked && this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  @Monitor('readMode.superResolutionEnabled', 'readMode.superResolutionModel',
    'readMode.superResolutionBackend',
    'readMode.superResolutionMaxHeight')
  onSuperResolutionSettingChanged(): void {
    if (this.resolvedDisplayUri.length > 0) {
      this.imageUrl = this.resolvedDisplayUri
    }
    if (this.isActive() && !this.imageBlocked && this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  private isActive(): boolean {
    return this.image.page === this.activeIndex + 1
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) — re-resolves via /s/?nl= for a
  // different host, bypassing the cached URL.
  private async resolve(changeSource: boolean = false): Promise<void> {
    const source: ReaderImageSourceRequest = this.sourceRequests.begin(
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
    if (!changeSource && !source.image.imageUrl.startsWith('file://')) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const cached: CachedImageFileResult | null =
        ImagePipelineService.cachedReaderFile(context, source.fileCacheKey)
      if (cached !== null) {
        await this.loadResolvedImage(source, '', cached)
        return
      }
    }
    if (source.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        this.imageBlocked = false
        this.imageBlockPreviewUri = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(source.image, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        source.image.originImageUrl = original
        if (!this.commitResolvedSource(source)) {
          return
        }
        DiagnosticLogger.info('reader', 'display_original', `page ${source.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(source, original, undefined, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        if (!this.isCurrentSource(source)) {
          return
        }
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && source.image.imageUrl.length > 0) {
      await this.loadResolvedImage(source, source.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(source.image, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      source.image.imageUrl = resolved
      if (!this.commitResolvedSource(source)) {
        return
      }
      await this.loadResolvedImage(source, resolved, undefined, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      if (!this.isCurrentSource(source)) {
        return
      }
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(
    source: ReaderImageSourceRequest,
    resolved: string,
    cachedResult?: CachedImageFileResult,
    forceReload: boolean = false,
  ): Promise<void> {
    if (!this.isCurrentSource(source)) {
      return
    }
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result: CachedImageFileResult = cachedResult !== undefined
      ? cachedResult
      : await ImagePipelineService.loadReaderFile(
          context,
          resolved,
          source.fileCacheKey,
          this.loadPriority(),
          (progress: CachedImageProgress) => {
            if (!this.isCurrentSource(source)) {
              return
            }
            this.imageProgressLoaded = progress.loaded
            this.imageProgressTotal = progress.total
          },
          forceReload,
        )
    if (!this.isCurrentSource(source)) {
      return
    }
    this.onImageFileReady(source.image.page, result.filePath, result.bytes)
    this.imageProgressLoaded = result.bytes
    this.imageProgressTotal = result.bytes
    if (!ReaderImageLoadPresentation.shouldSkipCompletionHold(result)) {
      await readerDelay(READER_LOADING_COMPLETION_HOLD_MS)
    }
    if (!this.isCurrentSource(source)) {
      return
    }
    if (await this.applyImageBlockDecision(source, context, result.filePath, result.bytes, result.displayUri)) {
      return
    }
    this.imageUrl = result.displayUri
    this.resolvedFilePath = result.filePath
    this.resolvedDisplayUri = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    if (this.isActive()) {
      this.applySuperResolution(result.filePath, result.displayUri, source.fileCacheKey, this.imageKey)
    }
  }

  private async applySuperResolution(
    filePath: string,
    displayUri: string,
    fileCacheKey: string,
    imageKey: string,
  ): Promise<void> {
    if (!this.isActive() || this.imageBlocked) {
      return
    }
    const enabled: boolean = this.readMode.superResolutionEnabled
    const model: string = this.readMode.superResolutionModel
    const backend: string = this.readMode.superResolutionBackend
    const maxHeight: number = this.readMode.superResolutionMaxHeight
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.onImageEnhancementState(
      this.image.page,
      model,
      false,
      enabled && model !== ReaderSuperResolutionModel.NONE ? 'queued' : 'disabled',
    )
    const result: ReaderSuperResolutionResult = await ReaderSuperResolutionService.process(
      context,
      filePath,
      fileCacheKey,
      (state: ReaderSuperResolutionTaskState): void => {
        this.onImageEnhancementState(this.image.page, model, false, state)
      },
    )
    if (!this.isActive() || this.imageBlocked ||
      this.readMode.superResolutionEnabled !== enabled ||
      this.readMode.superResolutionModel !== model ||
      this.readMode.superResolutionBackend !== backend ||
      this.readMode.superResolutionMaxHeight !== maxHeight ||
      this.fileCacheKey !== fileCacheKey || this.imageKey !== imageKey ||
      this.resolvedFilePath !== filePath || this.resolvedDisplayUri !== displayUri) {
      return
    }
    this.onImageEnhancementState(this.image.page, model, result.applied, result.reason)
    if (result.applied) {
      this.imageUrl = result.displayUri
    }
  }

  private loadPriority(): number {
    return ReaderImageLoadPriority.forVisible(this.isActive())
  }

  private async applyImageBlockDecision(
    source: ReaderImageSourceRequest,
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
    displayUri: string,
  ): Promise<boolean> {
    const decision: ImageBlockDecision = await readerImageBlockDecisionForFile(context, filePath, source.image.page)
    if (!this.isCurrentSource(source)) {
      return true
    }
    if (!decision.blocked) {
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.onImageBlockState(source.image.page, false)
      return false
    }
    this.imageBlocked = true
    this.imageBlockPreviewUri = displayUri
    this.onImageBlockState(source.image.page, true)
    this.imageUrl = ''
    this.imageLoaded = true
    this.imageProgressLoaded = bytes
    this.imageProgressTotal = bytes
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.onImageLoaded(source.image.page)
    readerLogImageBlocked(source.image.page, decision)
    return true
  }

  private isCurrentSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.isCurrent(
      source,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private commitResolvedSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.commitResolvedImage(
      source,
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private resetSourceState(): void {
    this.autoRetryCount = 0
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.intrinsicW = 0
    this.intrinsicH = 0
  }

  // Retry on failure: re-source (换源) — clear the dead URL and re-resolve from a different host.
  private retrySource(): void {
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!this.localSource) {
      ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
    }
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(!this.localSource)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!this.localSource) {
        ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
      }
      this.autoRetryCount++
      this.sourceRequests.invalidate()
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.failed = false
      this.resolve(!this.localSource)
      return
    }
    this.failed = true
  }

  private markImageLoaded(): void {
    this.autoRetryCount = 0
    if (!this.imageLoaded) {
      this.imageLoaded = true
      this.onImageLoaded(this.image.page)
    }
  }

  private onImageDecoded(width: number, height: number): void {
    if (width > 0 && height > 0) {
      this.intrinsicW = this.getUIContext().px2vp(width)
      this.intrinsicH = this.getUIContext().px2vp(height)
      DiagnosticLogger.info(
        'reader',
        'image_decoded',
        `page=${this.image.page} width=${width} height=${height} urlHash=${DiagnosticLogger.ownerHash(this.imageUrl)}`,
      )
    }
    this.onImageMetrics(this.image.page, width, height)
    DiagnosticLogger.info(
      'image',
      'reader_image_display_decoded',
      `page=${this.image.page} width=${width} height=${height}`,
    )
    this.markImageLoaded()
    this.clampOffset()
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

  private nativeScale(): number {
    return ReaderZoomCoordinator.nativeScale(this.intrinsicW, this.intrinsicH, this.displayW(), this.displayH())
  }

  private maxScale(): number {
    return ReaderZoomCoordinator.dynamicMaxScale(this.intrinsicW, this.intrinsicH, this.displayW(), this.displayH())
  }

  private clampScale(value: number): number {
    return ReaderZoomCoordinator.clampScale(value, this.maxScale())
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
    this.zoomScale = this.clampScale(this.zoomScale)
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
  }

  private resetZoom(): void {
    this.zoomScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.pinchAdjustedSinceDoubleTap = false
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
    const target: number = ReaderZoomCoordinator.doubleTapTarget(
      this.zoomScale,
      this.maxScale(),
      this.nativeScale(),
      this.pinchAdjustedSinceDoubleTap,
    )
    this.pinchAdjustedSinceDoubleTap = false
    if (target === 1) {
      this.resetZoom()
      this.notifyZoom()
    } else {
      const anchorX: number = ReaderZoomCoordinator.pinchAnchor(tapX, this.compW, this.displayW(), this.zoomScale, this.offsetX)
      const anchorY: number = ReaderZoomCoordinator.pinchAnchor(tapY, this.compH, this.displayH(), this.zoomScale, this.offsetY)
      const nextX: number = ReaderZoomCoordinator.anchoredOffset(tapX, this.compW, this.displayW(), target, anchorX)
      const nextY: number = ReaderZoomCoordinator.anchoredOffset(tapY, this.compH, this.displayH(), target, anchorY)
      this.zoomScale = target
      this.offsetX = this.clampOffsetX(nextX, target)
      this.offsetY = this.clampOffsetY(nextY, target)
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
        ReaderInterpolatedImage({
          src: this.imageUrl,
          widthValue: '100%',
          heightValue: '100%',
          onComplete: (event?: ReaderImageLoadEvent) => {
            if (event && event.width && event.height) {
              this.onImageDecoded(event.width, event.height)
            } else {
              this.markImageLoaded()
              this.clampOffset()
            }
          },
          onError: () => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          },
        })
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.offsetX, y: this.offsetY })
          .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
      } else if (this.imageBlocked) {
        ReaderImageBlockedOverlay({
          page: this.image.page,
          previewUri: this.imageBlockPreviewUri,
          allowing: this.imageBlockWhitelistSaving,
          onAllow: (page: number) => {
            this.onAllowImageBlock(page)
          },
        })
      }
      if (!this.failed && !this.imageBlocked && !this.imageLoaded) {
        ReaderLoadingStage({
          label: this.imageUrl.length > 0
            ? $r('app.string.reader_loading_decoding')
            : this.sourceImageUrl.length > 0
              ? $r('app.string.reader_loading_image')
              : $r('app.string.reader_loading_resolving'),
          loaded: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressLoaded
            : 0,
          total: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressTotal
            : 0,
        })
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
            this.ignorePanSequence = true
            this.zoomAnimating = false
            this.pinchStartScale = this.zoomScale
            this.pinchAnchorX = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              this.zoomScale,
              this.offsetX
            )
            this.pinchAnchorY = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              this.zoomScale,
              this.offsetY
            )
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e) {
              return
            }
            const nextScale: number = ReaderZoomCoordinator.clampPinchScale(
              this.pinchStartScale * (e.scale as number),
              this.maxScale(),
            )
            this.pinchAdjustedSinceDoubleTap = true
            const nextX: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              nextScale,
              this.pinchAnchorX
            )
            const nextY: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              nextScale,
              this.pinchAnchorY
            )
            const clampedX: number = this.clampOffsetX(nextX, nextScale)
            const clampedY: number = this.clampOffsetY(nextY, nextScale)
            this.zoomScale = nextScale
            this.offsetX = clampedX
            this.offsetY = clampedY
          })
          .onActionEnd(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          })
          .onActionCancel(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: this.panDistance() })
          .onActionStart(() => {
            this.ignorePanSequence = this.isPinching
            this.panStartOffX = this.offsetX
            this.panStartOffY = this.offsetY
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e || this.ignorePanSequence || this.isPinching || !ReaderZoomCoordinator.isZoomed(this.zoomScale)) {
              return
            }
            const nextX: number = this.clampOffsetX(this.panStartOffX + (e.offsetX as number), this.zoomScale)
            const nextY: number = this.clampOffsetY(this.panStartOffY + (e.offsetY as number), this.zoomScale)
            this.offsetX = nextX
            this.offsetY = nextY
          })
          .onActionEnd(() => {
            this.ignorePanSequence = false
          }),
      ),
    )
  }
}

const DEFAULT_VERTICAL_RATIO: number = 0.7

/**
 * One page in the vertical (continuous) reader: a full-width image whose height follows the
 * loaded image's aspect ratio (captured in onComplete). The image owns pinch / double-tap zoom; when
 * zoomed it reports up so the parent List can pause scrolling while pan moves the image.
 */
@ComponentV2
struct ReaderVerticalImage {
  @Param image: EhGalleryImage = new EhGalleryImage();
  @Param localSource: boolean = false;
  @Param imageKey: string = '';
  @Param fileCacheKey: string = '';
  @Param preferOriginal: boolean = false;
  @Param initiallyLoaded: boolean = false;
  @Param loadedSignal: number = 0;
  @Param sourceReloadPage: number = 0;
  @Param sourceReloadRequestId: number = 0;
  @Param imageBlockWhitelistSaving: boolean = false;
  @Param visible: boolean = false;
  @Param onReaderTap: (x: number, y: number) => void = (_x: number, _y: number) => {};
  @Param onZoomChange: (zoomed: boolean) => void = (_zoomed: boolean) => {};
  @Param onImageLoaded: (page: number) => void = (_page: number) => {};
  @Param onImageFileReady: (page: number, filePath: string, bytes: number) => void =
    (_page: number, _filePath: string, _bytes: number) => {};
  @Param onImageBlockState: (page: number, blocked: boolean) => void =
    (_page: number, _blocked: boolean) => {};
  @Param onAllowImageBlock: (page: number) => void = (_page: number) => {};
  @Param onImageMetrics: (page: number, width: number, height: number) => void =
    (_page: number, _width: number, _height: number) => {};
  @Param onImageEnhancementState: (page: number, model: string, applied: boolean, reason: string) => void =
    (_page: number, _model: string, _applied: boolean, _reason: string) => {};
  @Local imageUrl: string = '';
  @Local imageLoaded: boolean = false;
  @Local sourceImageUrl: string = '';
  @Local imageProgressLoaded: number = 0;
  @Local imageProgressTotal: number = 0;
  @Local imageBlocked: boolean = false;
  @Local imageBlockPreviewUri: string = '';
  @Local failed: boolean = false;
  @Local failureKind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Local ratio: number = DEFAULT_VERTICAL_RATIO;
  @Local zoomScale: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local zoomAnimating: boolean = false;
  @Local intrinsicW: number = 0;
  @Local intrinsicH: number = 0;
  @Local readMode: ReadModeState = connectReadMode();
  private pinchStartScale: number = 1;
  private pinchAnchorX: number = 0.5;
  private pinchAnchorY: number = 0.5;
  private panStartOffX: number = 0;
  private panStartOffY: number = 0;
  private isPinching: boolean = false;
  private pinchAdjustedSinceDoubleTap: boolean = false;
  private ignorePanSequence: boolean = false;
  private compW: number = 0;
  private compH: number = 0;
  private lastZoomed: boolean = false;
  private autoRetryCount: number = 0;
  private sourceRequests: ReaderImageSourceRequestGate = new ReaderImageSourceRequestGate();
  private zoomAnimatingTimerId: number = 0;
  private tapStartX: number = 0;
  private tapStartY: number = 0;
  private tapCancelled: boolean = false;
  private skipNextTapUp: boolean = false;
  private singleTapTimerId: number = 0;
  private resolvedFilePath: string = '';
  private resolvedDisplayUri: string = '';

  aboutToAppear(): void {
    this.resolve()
  }

  aboutToDisappear(): void {
    this.sourceRequests.invalidate()
    if (this.zoomAnimatingTimerId > 0) {
      clearTimeout(this.zoomAnimatingTimerId)
      this.zoomAnimatingTimerId = 0
    }
    this.clearPendingSingleTap()
    this.resetZoom()
    this.notifyZoom()
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

  @Monitor('sourceReloadRequestId')
  onSourceReloadRequested(): void {
    if (this.sourceReloadRequestId > 0 && this.sourceReloadPage === this.image.page) {
      this.retrySource()
    }
  }

  @Monitor('visible')
  onVisibleChanged(): void {
    if (!this.visible || this.imageBlocked) {
      return
    }
    if (this.imageUrl.length === 0) {
      this.resolve()
      return
    }
    if (this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  @Monitor('readMode.superResolutionEnabled', 'readMode.superResolutionModel',
    'readMode.superResolutionBackend',
    'readMode.superResolutionMaxHeight')
  onSuperResolutionSettingChanged(): void {
    if (this.resolvedDisplayUri.length > 0) {
      this.imageUrl = this.resolvedDisplayUri
    }
    if (this.visible && !this.imageBlocked && this.resolvedFilePath.length > 0) {
      this.applySuperResolution(
        this.resolvedFilePath,
        this.resolvedDisplayUri,
        this.fileCacheKey,
        this.imageKey,
      )
    }
  }

  // `changeSource` re-sources a broken/509 image (eros_fe 换源) via /s/?nl=, bypassing the cache.
  private async resolve(changeSource: boolean = false): Promise<void> {
    const source: ReaderImageSourceRequest = this.sourceRequests.begin(
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
    if (!changeSource && !source.image.imageUrl.startsWith('file://')) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      const cached: CachedImageFileResult | null =
        ImagePipelineService.cachedReaderFile(context, source.fileCacheKey)
      if (cached !== null) {
        await this.loadResolvedImage(source, '', cached)
        return
      }
    }
    if (source.preferOriginal) {
      try {
        this.imageUrl = ''
        this.imageLoaded = false
        this.sourceImageUrl = ''
        this.imageBlocked = false
        this.imageBlockPreviewUri = ''
        const original: string = await ImageResolveService.getInstance().resolveOriginal(source.image, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        source.image.originImageUrl = original
        if (!this.commitResolvedSource(source)) {
          return
        }
        DiagnosticLogger.info('reader', 'display_original', `page ${source.image.page} fullimg ${original.indexOf('/fullimg') >= 0}`)
        await this.loadResolvedImage(source, original, undefined, changeSource)
        if (!this.isCurrentSource(source)) {
          return
        }
        this.failed = false
        this.failureKind = ReaderImageFailureKind.Generic
      } catch (err) {
        if (!this.isCurrentSource(source)) {
          return
        }
        const e: Error = err as Error
        this.failureKind = readerFailureKindFromError(e)
        DiagnosticLogger.warn('reader', 'vertical_original_failed', e.message)
        this.failed = true
      }
      return
    }
    if (!changeSource && source.image.imageUrl.length > 0) {
      await this.loadResolvedImage(source, source.image.imageUrl)
      return
    }
    try {
      this.imageUrl = ''
      this.imageLoaded = false
      this.sourceImageUrl = ''
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      const resolved: string = await ImageResolveService.getInstance().resolve(source.image, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      source.image.imageUrl = resolved
      if (!this.commitResolvedSource(source)) {
        return
      }
      await this.loadResolvedImage(source, resolved, undefined, changeSource)
      if (!this.isCurrentSource(source)) {
        return
      }
      this.failed = false
      this.failureKind = ReaderImageFailureKind.Generic
    } catch (err) {
      if (!this.isCurrentSource(source)) {
        return
      }
      const e: Error = err as Error
      this.failureKind = readerFailureKindFromError(e)
      DiagnosticLogger.warn('reader', 'resolve_failed', e.message)
      this.retrySourceAutomatically()
    }
  }

  private async loadResolvedImage(
    source: ReaderImageSourceRequest,
    resolved: string,
    cachedResult?: CachedImageFileResult,
    forceReload: boolean = false,
  ): Promise<void> {
    if (!this.isCurrentSource(source)) {
      return
    }
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.sourceImageUrl = resolved
    this.imageUrl = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    const result: CachedImageFileResult = cachedResult !== undefined
      ? cachedResult
      : await ImagePipelineService.loadReaderFile(
          context,
          resolved,
          source.fileCacheKey,
          this.loadPriority(),
          (progress: CachedImageProgress) => {
            if (!this.isCurrentSource(source)) {
              return
            }
            this.imageProgressLoaded = progress.loaded
            this.imageProgressTotal = progress.total
          },
          forceReload,
        )
    if (!this.isCurrentSource(source)) {
      return
    }
    this.onImageFileReady(source.image.page, result.filePath, result.bytes)
    this.imageProgressLoaded = result.bytes
    this.imageProgressTotal = result.bytes
    if (!ReaderImageLoadPresentation.shouldSkipCompletionHold(result)) {
      await readerDelay(READER_LOADING_COMPLETION_HOLD_MS)
    }
    if (!this.isCurrentSource(source)) {
      return
    }
    if (await this.applyImageBlockDecision(source, context, result.filePath, result.bytes, result.displayUri)) {
      return
    }
    this.imageUrl = result.displayUri
    this.resolvedFilePath = result.filePath
    this.resolvedDisplayUri = result.displayUri
    this.imageLoaded = this.initiallyLoaded
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    if (this.visible) {
      this.applySuperResolution(result.filePath, result.displayUri, source.fileCacheKey, this.imageKey)
    }
  }

  private async applySuperResolution(
    filePath: string,
    displayUri: string,
    fileCacheKey: string,
    imageKey: string,
  ): Promise<void> {
    if (!this.visible || this.imageBlocked) {
      return
    }
    const enabled: boolean = this.readMode.superResolutionEnabled
    const model: string = this.readMode.superResolutionModel
    const backend: string = this.readMode.superResolutionBackend
    const maxHeight: number = this.readMode.superResolutionMaxHeight
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.onImageEnhancementState(
      this.image.page,
      model,
      false,
      enabled && model !== ReaderSuperResolutionModel.NONE ? 'queued' : 'disabled',
    )
    const result: ReaderSuperResolutionResult = await ReaderSuperResolutionService.process(
      context,
      filePath,
      fileCacheKey,
      (state: ReaderSuperResolutionTaskState): void => {
        this.onImageEnhancementState(this.image.page, model, false, state)
      },
    )
    if (!this.visible || this.imageBlocked ||
      this.readMode.superResolutionEnabled !== enabled ||
      this.readMode.superResolutionModel !== model ||
      this.readMode.superResolutionBackend !== backend ||
      this.readMode.superResolutionMaxHeight !== maxHeight ||
      this.fileCacheKey !== fileCacheKey || this.imageKey !== imageKey ||
      this.resolvedFilePath !== filePath || this.resolvedDisplayUri !== displayUri) {
      return
    }
    this.onImageEnhancementState(this.image.page, model, result.applied, result.reason)
    if (result.applied) {
      this.imageUrl = result.displayUri
    }
  }

  private loadPriority(): number {
    return ReaderImageLoadPriority.forVisible(this.visible)
  }

  private async applyImageBlockDecision(
    source: ReaderImageSourceRequest,
    context: common.UIAbilityContext,
    filePath: string,
    bytes: number,
    displayUri: string,
  ): Promise<boolean> {
    const decision: ImageBlockDecision = await readerImageBlockDecisionForFile(context, filePath, source.image.page)
    if (!this.isCurrentSource(source)) {
      return true
    }
    if (!decision.blocked) {
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.onImageBlockState(source.image.page, false)
      return false
    }
    this.imageBlocked = true
    this.imageBlockPreviewUri = displayUri
    this.onImageBlockState(source.image.page, true)
    this.imageUrl = ''
    this.imageLoaded = true
    this.imageProgressLoaded = bytes
    this.imageProgressTotal = bytes
    this.autoRetryCount = 0
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.onImageLoaded(source.image.page)
    readerLogImageBlocked(source.image.page, decision)
    return true
  }

  private isCurrentSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.isCurrent(
      source,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private commitResolvedSource(source: ReaderImageSourceRequest): boolean {
    return this.sourceRequests.commitResolvedImage(
      source,
      this.image,
      this.imageKey,
      this.fileCacheKey,
      this.preferOriginal,
    )
  }

  private resetSourceState(): void {
    this.autoRetryCount = 0
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.resolvedFilePath = ''
    this.resolvedDisplayUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.ratio = DEFAULT_VERTICAL_RATIO
    this.intrinsicW = 0
    this.intrinsicH = 0
  }

  private retrySource(): void {
    this.autoRetryCount = 0
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!this.localSource) {
      ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
    }
    this.sourceRequests.invalidate()
    this.sourceImageUrl = ''
    this.imageUrl = ''
    this.imageLoaded = false
    this.imageProgressLoaded = 0
    this.imageProgressTotal = 0
    this.imageBlocked = false
    this.imageBlockPreviewUri = ''
    this.failed = false
    this.failureKind = ReaderImageFailureKind.Generic
    this.resolve(!this.localSource)
  }

  private retrySourceAutomatically(): void {
    if (this.autoRetryCount < IMAGE_AUTO_RETRY_LIMIT) {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      if (!this.localSource) {
        ImagePipelineService.removeReaderFile(context, this.fileCacheKey)
      }
      this.autoRetryCount++
      this.sourceRequests.invalidate()
      this.sourceImageUrl = ''
      this.imageUrl = ''
      this.imageLoaded = false
      this.imageProgressLoaded = 0
      this.imageProgressTotal = 0
      this.imageBlocked = false
      this.imageBlockPreviewUri = ''
      this.failed = false
      this.resolve(!this.localSource)
      return
    }
    this.failed = true
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

  private nativeScale(): number {
    return ReaderZoomCoordinator.nativeScale(this.intrinsicW, this.intrinsicH, this.displayW(), this.displayH())
  }

  private maxScale(): number {
    return ReaderZoomCoordinator.dynamicMaxScale(this.intrinsicW, this.intrinsicH, this.displayW(), this.displayH())
  }

  private clampScale(value: number): number {
    return ReaderZoomCoordinator.clampScale(value, this.maxScale())
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
    this.zoomScale = this.clampScale(this.zoomScale)
    this.offsetX = this.clampOffsetX(this.offsetX, this.zoomScale)
    this.offsetY = this.clampOffsetY(this.offsetY, this.zoomScale)
  }

  private resetZoom(): void {
    this.zoomScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.pinchAdjustedSinceDoubleTap = false
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

  private firstTouch(event: TouchEvent): TouchObject | null {
    if (event.touches.length > 0) {
      return event.touches[0]
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    return null
  }

  private movedBeyondTap(x: number, y: number): boolean {
    const dx: number = x - this.tapStartX
    const dy: number = y - this.tapStartY
    return (dx * dx + dy * dy) > (READER_VERTICAL_TAP_MAX_DISTANCE * READER_VERTICAL_TAP_MAX_DISTANCE)
  }

  private clearPendingSingleTap(): void {
    if (this.singleTapTimerId > 0) {
      clearTimeout(this.singleTapTimerId)
      this.singleTapTimerId = 0
    }
  }

  private scheduleSingleTap(x: number, y: number): void {
    this.clearPendingSingleTap()
    this.singleTapTimerId = setTimeout((): void => {
      this.singleTapTimerId = 0
      this.onReaderTap(x, y)
    }, READER_VERTICAL_SINGLE_TAP_DELAY_MS)
  }

  private onImageTouch(event: TouchEvent): void {
    const touch: TouchObject | null = this.firstTouch(event)
    if (touch === null) {
      return
    }
    if (event.touches.length > 1 || event.changedTouches.length > 1) {
      this.tapCancelled = true
      this.clearPendingSingleTap()
      return
    }
    if (event.type === TouchType.Down) {
      if (this.singleTapTimerId > 0) {
        this.clearPendingSingleTap()
        this.skipNextTapUp = true
      }
      this.tapStartX = touch.x
      this.tapStartY = touch.y
      this.tapCancelled = false
      return
    }
    if (event.type === TouchType.Move) {
      if (this.movedBeyondTap(touch.x, touch.y)) {
        this.tapCancelled = true
        this.clearPendingSingleTap()
      }
      return
    }
    if (event.type === TouchType.Up) {
      if (!this.tapCancelled && !this.skipNextTapUp && !this.movedBeyondTap(touch.x, touch.y)) {
        this.scheduleSingleTap(touch.windowX, touch.windowY)
      }
      this.skipNextTapUp = false
      this.tapCancelled = false
      return
    }
    if (event.type === TouchType.Cancel) {
      this.tapCancelled = true
      this.skipNextTapUp = false
      this.clearPendingSingleTap()
    }
  }

  private onDoubleTap(tapX: number, tapY: number): void {
    this.clearPendingSingleTap()
    this.skipNextTapUp = false
    this.beginZoomAnimation()
    const target: number = ReaderZoomCoordinator.doubleTapTarget(
      this.zoomScale,
      this.maxScale(),
      this.nativeScale(),
      this.pinchAdjustedSinceDoubleTap,
    )
    this.pinchAdjustedSinceDoubleTap = false
    if (target === 1) {
      this.resetZoom()
      this.notifyZoom()
      return
    }
    const anchorX: number = ReaderZoomCoordinator.pinchAnchor(tapX, this.compW, this.displayW(), this.zoomScale, this.offsetX)
    const anchorY: number = ReaderZoomCoordinator.pinchAnchor(tapY, this.compH, this.displayH(), this.zoomScale, this.offsetY)
    const nextX: number = ReaderZoomCoordinator.anchoredOffset(tapX, this.compW, this.displayW(), target, anchorX)
    const nextY: number = ReaderZoomCoordinator.anchoredOffset(tapY, this.compH, this.displayH(), target, anchorY)
    this.zoomScale = target
    this.offsetX = this.clampOffsetX(nextX, target)
    this.offsetY = this.clampOffsetY(nextY, target)
    this.notifyZoom()
  }

  private markImageLoaded(): void {
    this.autoRetryCount = 0
    if (!this.imageLoaded) {
      this.imageLoaded = true
      this.onImageLoaded(this.image.page)
    }
  }

  private onImageDecoded(width: number, height: number): void {
    if (width > 0 && height > 0) {
      this.ratio = width / height
      this.intrinsicW = this.getUIContext().px2vp(width)
      this.intrinsicH = this.getUIContext().px2vp(height)
      DiagnosticLogger.info(
        'reader',
        'image_decoded',
        `page=${this.image.page} width=${width} height=${height} urlHash=${DiagnosticLogger.ownerHash(this.imageUrl)}`,
      )
    }
    this.onImageMetrics(this.image.page, width, height)
    DiagnosticLogger.info(
      'image',
      'reader_image_display_decoded',
      `page=${this.image.page} width=${width} height=${height}`,
    )
    this.markImageLoaded()
    this.clampOffset()
  }

  private zoomZIndex(): number {
    return ReaderZoomCoordinator.isZoomed(this.zoomScale) ? 1 : 0
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
        ReaderInterpolatedImage({
          src: this.imageUrl,
          widthValue: '100%',
          heightValue: '100%',
          onComplete: (event?: ReaderImageLoadEvent) => {
            if (event && event.width && event.height) {
              this.onImageDecoded(event.width, event.height)
            } else {
              this.markImageLoaded()
              this.clampOffset()
            }
          },
          onError: () => {
            DiagnosticLogger.warn('reader', 'image_load_failed', `page ${this.image.page}`)
            this.imageLoaded = false
            this.retrySourceAutomatically()
          },
        })
          .width('100%')
          .aspectRatio(this.ratio)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.offsetX, y: this.offsetY })
          .animation({ duration: this.zoomAnimating ? READER_ZOOM_ANIM_DURATION : 0, curve: Curve.FastOutSlowIn })
      } else if (this.imageBlocked) {
        ReaderImageBlockedOverlay({
          page: this.image.page,
          compact: true,
          previewUri: this.imageBlockPreviewUri,
          allowing: this.imageBlockWhitelistSaving,
          onAllow: (page: number) => {
            this.onAllowImageBlock(page)
          },
        })
      }
      if (!this.failed && !this.imageBlocked && !this.imageLoaded) {
        ReaderLoadingStage({
          label: this.imageUrl.length > 0
            ? $r('app.string.reader_loading_decoding')
            : this.sourceImageUrl.length > 0
              ? $r('app.string.reader_loading_image')
              : $r('app.string.reader_loading_resolving'),
          compact: true,
          loaded: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressLoaded
            : 0,
          total: this.sourceImageUrl.length > 0 && this.imageUrl.length === 0
            ? this.imageProgressTotal
            : 0,
        })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 220 })
    .zIndex(this.zoomZIndex())
    .onAreaChange((_o: Area, n: Area) => {
      this.compW = n.width as number
      this.compH = n.height as number
      this.clampOffset()
    })
    .onTouch((event: TouchEvent) => {
      this.onImageTouch(event)
    })
    .gesture(
      GestureGroup(
        GestureMode.Parallel,
        TapGesture({ count: 2, distanceThreshold: 8 }).onAction((e?: GestureEvent) => {
          const loc = e ? e.tapLocation : undefined
          const tapX: number = loc ? (loc.x as number) : this.compW / 2
          const tapY: number = loc ? (loc.y as number) : this.compH / 2
          this.onDoubleTap(tapX, tapY)
        }),
        PinchGesture({ fingers: 2 })
          .onActionStart((e?: GestureEvent) => {
            if (!e) {
              return
            }
            this.isPinching = true
            this.ignorePanSequence = true
            this.tapCancelled = true
            this.clearPendingSingleTap()
            this.zoomAnimating = false
            this.pinchStartScale = this.zoomScale
            this.pinchAnchorX = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              this.zoomScale,
              this.offsetX
            )
            this.pinchAnchorY = ReaderZoomCoordinator.pinchAnchor(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              this.zoomScale,
              this.offsetY
            )
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e) {
              return
            }
            const nextScale: number = ReaderZoomCoordinator.clampPinchScale(
              this.pinchStartScale * (e.scale as number),
              this.maxScale(),
            )
            this.pinchAdjustedSinceDoubleTap = true
            const nextX: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterX as number,
              this.compW,
              this.displayW(),
              nextScale,
              this.pinchAnchorX
            )
            const nextY: number = ReaderZoomCoordinator.anchoredOffset(
              e.pinchCenterY as number,
              this.compH,
              this.displayH(),
              nextScale,
              this.pinchAnchorY
            )
            this.zoomScale = nextScale
            this.offsetX = this.clampOffsetX(nextX, nextScale)
            this.offsetY = this.clampOffsetY(nextY, nextScale)
          })
          .onActionEnd(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else if (this.zoomScale <= 1.01) {
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          })
          .onActionCancel(() => {
            this.isPinching = false
            if (this.zoomScale < 1) {
              this.beginZoomAnimation()
              this.resetZoom()
            } else {
              this.clampOffset()
            }
            this.notifyZoom()
          }),
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: this.panDistance() })
          .onActionStart(() => {
            this.ignorePanSequence = this.isPinching
            this.tapCancelled = true
            this.clearPendingSingleTap()
            this.panStartOffX = this.offsetX
            this.panStartOffY = this.offsetY
          })
          .onActionUpdate((e?: GestureEvent) => {
            if (!e || this.ignorePanSequence || this.isPinching || !ReaderZoomCoordinator.isZoomed(this.zoomScale)) {
              return
            }
            this.offsetX = this.clampOffsetX(this.panStartOffX + (e.offsetX as number), this.zoomScale)
            this.offsetY = this.clampOffsetY(this.panStartOffY + (e.offsetY as number), this.zoomScale)
          })
          .onActionEnd(() => {
            this.ignorePanSequence = false
          }),
      ),
    )
  }
}

@ComponentV2
struct ReaderLoadingBar {
  @Param compact: boolean = false;
  @Param determinate: boolean = false;
  @Param ratio: number = 0;
  @Param barFillColor: ResourceColor = READER_LOADING_BAR_FG;
  @Param barTrackColor: ResourceColor = READER_LOADING_BAR_BG;
  @Local indeterminatePosition: number = 0;
  @Local trackWidth: number = 0;

  private indeterminateStartTimer: number = -1
  private indeterminateTimer: number = -1

  aboutToAppear(): void {
    this.syncIndeterminateAnimation()
  }

  aboutToDisappear(): void {
    this.stopIndeterminateAnimation()
  }

  @Monitor('determinate')
  private onDeterminateChanged(): void {
    this.syncIndeterminateAnimation()
  }

  private syncIndeterminateAnimation(): void {
    if (this.determinate) {
      this.stopIndeterminateAnimation()
      this.indeterminatePosition = 0
      return
    }
    this.startIndeterminateAnimation()
  }

  private startIndeterminateAnimation(): void {
    if (this.trackWidth <= 0 || this.indeterminateStartTimer >= 0 || this.indeterminateTimer >= 0) {
      return
    }
    // Keep the first rendered frame at the leading edge. Small images can cross several loading
    // stages before one 900 ms cycle finishes, so moving to the trailing edge during mount makes
    // every short-lived stage look frozen on the right.
    this.indeterminatePosition = 0
    this.indeterminateStartTimer = setTimeout(() => {
      this.indeterminateStartTimer = -1
      if (this.determinate) {
        return
      }
      this.moveIndeterminateSlider()
      this.indeterminateTimer = setInterval(() => {
        this.moveIndeterminateSlider()
      }, READER_LOADING_INDETERMINATE_ANIM_DURATION)
    }, 0)
  }

  private stopIndeterminateAnimation(): void {
    if (this.indeterminateStartTimer >= 0) {
      clearTimeout(this.indeterminateStartTimer)
      this.indeterminateStartTimer = -1
    }
    if (this.indeterminateTimer >= 0) {
      clearInterval(this.indeterminateTimer)
      this.indeterminateTimer = -1
    }
  }

  private moveIndeterminateSlider(): void {
    const next: number = this.indeterminatePosition > 0 ? 0 : 1
    // The fill node already declares the same transition below. Starting another imperative
    // transaction as the Reader destination mounts can leave the previous animation node alive
    // through a rapid close/reopen on API 24.
    this.indeterminatePosition = next
  }

  private barWidth(): number {
    if (this.trackWidth > 0) {
      return this.trackWidth
    }
    return READER_LOADING_BAR_MAX_WIDTH
  }

  private sliderWidth(): number {
    return this.barWidth() * READER_LOADING_SLIDER_WIDTH_RATIO
  }

  private clampedRatio(): number {
    if (this.ratio < 0) {
      return 0
    }
    if (this.ratio > 1) {
      return 1
    }
    return this.ratio
  }

  private fillWidth(): number {
    if (this.determinate) {
      return this.barWidth() * this.clampedRatio()
    }
    return this.sliderWidth()
  }

  private sliderX(): number {
    if (this.determinate) {
      return 0
    }
    return (this.barWidth() - this.sliderWidth()) * this.indeterminatePosition
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.determinate) {
        Row()
          .width(this.fillWidth())
          .height(READER_LOADING_BAR_HEIGHT)
          .backgroundColor(this.barFillColor)
          .borderRadius(READER_LOADING_BAR_RADIUS)
          .animation({ duration: READER_LOADING_PROGRESS_ANIM_DURATION, curve: Curve.EaseOut })
      } else {
        Row()
          .width(this.sliderWidth())
          .height(READER_LOADING_BAR_HEIGHT)
          .backgroundColor(this.barFillColor)
          .borderRadius(READER_LOADING_BAR_RADIUS)
          .translate({ x: this.sliderX() })
          .animation({ duration: READER_LOADING_INDETERMINATE_ANIM_DURATION, curve: Curve.EaseInOut })
      }
    }
    .width(READER_LOADING_BAR_WIDTH_PERCENT)
    .constraintSize({ maxWidth: READER_LOADING_BAR_MAX_WIDTH })
    .height(READER_LOADING_BAR_HEIGHT)
    .backgroundColor(this.barTrackColor)
    .borderRadius(READER_LOADING_BAR_RADIUS)
    .clip(true)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.trackWidth = area.width as number
      this.syncIndeterminateAnimation()
    })
  }
}

@ComponentV2
struct ReaderLoadingStage {
  @Param label: ResourceStr = '';
  @Param compact: boolean = false;
  @Param loaded: number = 0;
  @Param total: number = 0;
  @Local readMode: ReadModeState = connectReadMode();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();

  private contentColor(): ResourceColor {
    return readerForegroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private secondaryColor(): ResourceColor {
    return readerSecondaryForegroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private trackColor(): ResourceColor {
    return readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
      ? READER_LOADING_BAR_BG
      : READER_LOADING_BAR_LIGHT_BG
  }

  private hasProgress(): boolean {
    return this.total > 0
  }

  private progressRatio(): number {
    if (!this.hasProgress()) {
      return 0
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
      ReaderLoadingBar({
        compact: this.compact,
        determinate: this.hasProgress(),
        ratio: this.progressRatio(),
        barFillColor: this.contentColor(),
        barTrackColor: this.trackColor(),
      })
      Text(this.label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.contentColor())
        .textAlign(TextAlign.Center)
      Text(this.hasProgress() ? this.progressPercent() : '0%')
        .fontSize(ThemeConstants.FONT_SIZE_META)
        .fontColor(this.secondaryColor())
        .textAlign(TextAlign.Center)
        .opacity(this.hasProgress() ? 1 : 0)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeConstants.SPACE_XL)
  }
}

@ComponentV2
struct ReaderImageBlockedOverlay {
  @Param page: number = 0;
  @Param compact: boolean = false;
  @Param previewUri: string = '';
  @Param allowing: boolean = false;
  @Param onAllow: (page: number) => void = (_page: number) => {};

  private iconSize(): number {
    return this.compact ? 40 : 64
  }

  private contentWidth(): number {
    return this.compact ? 196 : 280
  }

  private overlayHeight(): Length {
    return this.compact ? 220 : '100%'
  }

  @Builder
  BackgroundLayer() {
    if (this.previewUri.length > 0) {
      EhImageKnifeImage({
        src: this.previewUri,
        memoryOnly: true,
        widthValue: '100%',
        heightValue: '100%',
        objectFit: ImageFit.Contain,
        priority: EH_IMAGE_PRIORITY_LOW,
      })
        .scale({ x: 1.02, y: 1.02 })
        .blur(ThemeConstants.COVER_BG_BLUR_RADIUS + 40)
        .opacity(1)
        .renderGroup(true)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.BackgroundLayer()
      Column({ space: ThemeConstants.SPACE_MD }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(this.iconSize())
          .fontColor([Color.White])
        Text($r('app.string.reader_image_blocked'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(2)
        Text($r('app.string.reader_image_blocked_hint'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor('#CCFFFFFF')
          .textAlign(TextAlign.Center)
          .maxLines(2)
        if (this.page > 0) {
          Text(`P${this.page}`)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor('#BBFFFFFF')
            .textAlign(TextAlign.Center)
            .maxLines(1)
        }
        if (this.allowing) {
          Button($r('app.string.reader_image_block_allow'))
            .type(ButtonType.Capsule)
            .enabled(false)
        } else {
          Button($r('app.string.reader_image_block_allow'))
            .type(ButtonType.Capsule)
            .onClick(() => {
              this.onAllow(this.page)
            })
        }
      }
      .width(this.contentWidth())
      .padding(ThemeConstants.SPACE_LG)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(this.overlayHeight())
    .clip(true)
    .hitTestBehavior(HitTestMode.Default)
  }
}

@ComponentV2
struct ReaderFailureOverlay {
  @Param page: number = 0;
  @Param kind: ReaderImageFailureKind = ReaderImageFailureKind.Generic;
  @Param compact: boolean = false;
  @Param onRetry: () => void = () => {};
  @Local readMode: ReadModeState = connectReadMode();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();

  private contentColor(): ResourceColor {
    return readerForegroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
  }

  private hintColor(): ResourceColor {
    return readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
      ? READER_FAILURE_HINT_DARK
      : READER_FAILURE_HINT_LIGHT
  }

  private pageColor(): ResourceColor {
    return readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
      ? READER_FAILURE_PAGE_DARK
      : READER_FAILURE_PAGE_LIGHT
  }

  private controlTint(): ResourceColor {
    return readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark)
      ? ThemeConstants.READER_CONTROL_LIGHT_TINT
      : ThemeConstants.READER_CONTROL_DARK_TINT
  }

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
        .fontColor([this.contentColor()])
      Text(this.failureTitle())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.contentColor())
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Text(this.failureHint())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor(this.hintColor())
        .textAlign(TextAlign.Center)
        .maxLines(2)
      if (this.page > 0) {
        Text(`P${this.page}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(this.pageColor())
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
      Button($r('app.string.reader_retry_source'))
        .type(ButtonType.Capsule)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.contentColor())
        .backgroundColor(this.controlTint())
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
