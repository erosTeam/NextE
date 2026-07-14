import { AbilityConstant, UIAbility, Want, Configuration, common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { window } from '@kit.ArkUI'
import {
  AppStrings,
  DiagnosticLogger,
  DownloadQueueSettings,
  SettingsBootstrap,
  ThemeSettings,
  MotionHandStateService,
  publishPendingEhUrl,
  ClipboardLinkService,
  publishClipboardLinkCandidate,
  EhUrlRouter,
  LayoutSafeAreaBridge,
  InternalQaRoutes,
  HuaweiCloudSyncService,
  HuaweiCloudSyncScheduler,
  ImagePipelineService,
  ScreenOrientationSettings,
  SecuritySettings,
  connectSecuritySettings,
  connectSafeMode,
  SyncScheduler,
} from 'shared'

const TRANSPARENT_COLOR: string = '#00FFFFFF'
const ENTRY_PAGE: string = 'pages/Index'
const FALLBACK_TOP_AVOID: number = 40
const FALLBACK_BOTTOM_AVOID: number = 0

/**
 * NextE main ability. Restores persisted settings before the first page mounts, and is the
 * single writer of window safe-area / keyboard metrics into LayoutSafeAreaState (the
 * shared list scaffolds read those to inset content under the status bar + floating tab
 * bar). Deep links (/g/, /s/) are captured here and published as a command-bus signal.
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  private safeAreaUiContext: UIContext | null = null
  private avoidAreaChangeCallback: ((data: window.AvoidAreaOptions) => void) | null = null
  private windowSizeChangeCallback: ((size: window.Size) => void) | null = null
  private keyboardHeightCallback: ((height: number) => void) | null = null
  private mainContentReady: boolean = false
  private abilityForeground: boolean = false
  private startupDownloadResumeInFlight: boolean = false
  private clipboardProbeInFlight: boolean = false

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    HuaweiCloudSyncScheduler.bindExecutor((context: common.UIAbilityContext, reason: string) => {
      return HuaweiCloudSyncService.runScheduledSync(context, reason)
    })
    SyncScheduler.rememberContext(this.context)
    AppStrings.init(this.context)
    DiagnosticLogger.initializePersistentSink(this.context)
    DiagnosticLogger.info('app', 'session_start', 'EntryAbility.onCreate')
    ImagePipelineService.initialize(this.context)
    try {
      webview.WebviewController.initializeWebEngine()
      // Hardening for Cloudflare's Turnstile, which runs in a cross-origin iframe
      // (challenges.cloudflare.com) and sets verification cookies in a third-party context that
      // ArkWeb blocks by default. (The actual CF login-loop root cause was the WebView UA's OS token
      // — see EhLoginWebPage; this just keeps the challenge cookies from being dropped.)
      webview.WebCookieManager.putAcceptCookieEnabled(true)
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'initialize_web_engine_failed', e.message)
    }
    this.captureIncomingUrl(want)
    // Keep the theme signal fresh when the DEVICE flips dark/light in follow-system mode, so cached sub-tab
    // pills recolor immediately (the rest of the UI rebuilds on the config change on its own).
    try {
      this.context.getApplicationContext().on('environment', {
        onConfigurationUpdated: (config: Configuration) => {
          ThemeSettings.onSystemColorModeChanged(config.colorMode)
        },
        onMemoryLevel: (_level: AbilityConstant.MemoryLevel) => {},
      })
    } catch (error) {
      DiagnosticLogger.warn('app', 'environment_callback_register_failed', (error as Error).message)
    }
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureIncomingUrl(want)
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let win: window.Window | null = null
    try {
      win = windowStage.getMainWindowSync()
      win.setWindowLayoutFullScreen(true)
      win.setWindowSystemBarProperties({
        statusBarColor: TRANSPARENT_COLOR,
        navigationBarColor: TRANSPARENT_COLOR,
      })
      this.mainWindow = win
      this.watchMainWindowMetrics(win)
      ScreenOrientationSettings.bindWindowOrientationApplier((mode: string): void => {
        this.applyWindowOrientation(mode)
      })
      SecuritySettings.bindWindowPrivacyApplier((enabled: boolean): void => {
        this.applyWindowPrivacy(enabled)
      })
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'configure_window_failed', e.message)
    }
    SettingsBootstrap.loadAll(this.context).finally(() => {
      SyncScheduler.rememberContext(this.context)
      HuaweiCloudSyncService.tryEnableStartup(this.context).catch((error: Error) => {
        DiagnosticLogger.warn('sync', 'huawei_cloud_startup_failed', error.message)
      })
      SyncScheduler.requestAfterForeground(this.context, 'startup')
      // Subscribe grip detection + resolve the Read-button edge now that the alignment mode is restored,
      // so the floating button mounts on the correct side without a post-load hop.
      MotionHandStateService.start()
      windowStage.loadContent(ENTRY_PAGE, (err) => {
        if (err.code) {
          DiagnosticLogger.warn('app', 'load_content_failed', JSON.stringify(err))
        }
        try {
          const w: window.Window = win ?? windowStage.getMainWindowSync()
          this.mainWindow = w
          this.watchMainWindowMetrics(w)
          const uiCtx: UIContext = w.getUIContext()
          this.safeAreaUiContext = uiCtx
          this.refreshSafeAreaInsets(w, uiCtx)
          this.watchSafeAreaInsets(w, uiCtx)
          this.watchKeyboardHeight(w, uiCtx)
        } catch (e) {
          LayoutSafeAreaBridge.publishInsets(FALLBACK_TOP_AVOID, FALLBACK_BOTTOM_AVOID)
        }
        if (!err.code) {
          this.mainContentReady = true
          this.resumePendingDownloadsIfReady()
          SecuritySettings.lockIfNeeded(this.context, 'startup').finally(() => {
            this.probeClipboardLinkIfReady()
          })
        }
      })
    })
  }

  onDestroy(): void {
    this.safeAreaUiContext = null
    if (this.mainWindow) {
      this.unwatch(this.mainWindow)
    }
    DiagnosticLogger.info('app', 'session_end', 'EntryAbility.onDestroy')
    DiagnosticLogger.closePersistentSink()
  }

  onForeground(): void {
    this.abilityForeground = true
    this.resumePendingDownloadsIfReady()
    SyncScheduler.rememberContext(this.context)
    SyncScheduler.requestAfterForeground(this.context, 'foreground')
    ImagePipelineService.reloadOnForeground()
    SecuritySettings.lockIfNeeded(this.context, 'foreground').finally(() => {
      this.probeClipboardLinkIfReady()
    })
  }

  onBackground(): void {
    this.abilityForeground = false
    ImagePipelineService.clearOnBackground()
    SecuritySettings.recordBackground(this.context)
  }

  private resumePendingDownloadsIfReady(): void {
    if (!this.mainContentReady || !this.abilityForeground || this.startupDownloadResumeInFlight) {
      return
    }
    this.startupDownloadResumeInFlight = true
    DownloadQueueSettings.resumePendingDownloads(this.context).catch((error: Error) => {
      DiagnosticLogger.warn('download', 'startup_resume_failed', error.message)
    }).finally(() => {
      this.startupDownloadResumeInFlight = false
    })
  }

  private probeClipboardLinkIfReady(): void {
    if (!this.mainContentReady || !this.abilityForeground || this.clipboardProbeInFlight) {
      return
    }
    if (connectSecuritySettings().locked || connectSafeMode().restricted()) {
      return
    }
    this.clipboardProbeInFlight = true
    ClipboardLinkService.probe(this.context)
      .then((url: string) => {
        if (url.length > 0 && this.abilityForeground) {
          publishClipboardLinkCandidate(url)
        }
      })
      .finally(() => {
        this.clipboardProbeInFlight = false
      })
  }

  private applyWindowPrivacy(enabled: boolean): void {
    if (!this.mainWindow) {
      return
    }
    this.mainWindow.setWindowPrivacyMode(enabled)
      .then(() => {
        DiagnosticLogger.info('security', 'window_privacy_set', enabled ? 'on' : 'off')
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('security', 'window_privacy_failed', error.message)
      })
  }

  private applyWindowOrientation(mode: string): void {
    if (this.mainWindow === null) {
      return
    }
    const orientation: window.Orientation =
      mode === ScreenOrientationSettings.MODE_AUTO_ROTATION_UNSPECIFIED
        ? window.Orientation.AUTO_ROTATION_UNSPECIFIED
        : window.Orientation.UNSPECIFIED
    this.mainWindow.setPreferredOrientation(orientation)
      .then(() => {
        DiagnosticLogger.info('window', 'orientation_requested', mode)
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('window', 'orientation_request_failed', error.message)
      })
  }

  private refreshSafeAreaInsets(win: window.Window, uiCtx: UIContext): void {
    try {
      const top: number = Math.max(
        this.topHeight(win, uiCtx, window.AvoidAreaType.TYPE_SYSTEM),
        this.topHeight(win, uiCtx, window.AvoidAreaType.TYPE_CUTOUT),
      )
      const bottom: number = Math.max(
        this.bottomHeight(win, uiCtx, window.AvoidAreaType.TYPE_SYSTEM),
        this.bottomHeight(win, uiCtx, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR),
        this.bottomHeight(win, uiCtx, window.AvoidAreaType.TYPE_SYSTEM_GESTURE),
      )
      LayoutSafeAreaBridge.publishInsets(top, bottom)
    } catch (error) {
      LayoutSafeAreaBridge.publishInsets(FALLBACK_TOP_AVOID, FALLBACK_BOTTOM_AVOID)
    }
  }

  private topHeight(win: window.Window, uiCtx: UIContext, type: window.AvoidAreaType): number {
    try {
      return uiCtx.px2vp(win.getWindowAvoidArea(type).topRect.height)
    } catch (_error) {
      return 0
    }
  }

  private bottomHeight(win: window.Window, uiCtx: UIContext, type: window.AvoidAreaType): number {
    try {
      return uiCtx.px2vp(win.getWindowAvoidArea(type).bottomRect.height)
    } catch (_error) {
      return 0
    }
  }

  private watchSafeAreaInsets(win: window.Window, uiCtx: UIContext): void {
    this.avoidAreaChangeCallback = (_data: window.AvoidAreaOptions) => {
      this.refreshSafeAreaInsets(win, uiCtx)
    }
    try {
      win.on('avoidAreaChange', this.avoidAreaChangeCallback)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'watch_safe_area_failed', e.message)
    }
  }

  private publishMainWindowMetrics(win: window.Window): void {
    try {
      const rect = win.getWindowProperties().windowRect
      LayoutSafeAreaBridge.publishMainWindowSizePx(rect.width, rect.height)
    } catch (error) {
      DiagnosticLogger.warn('app', 'window_metrics_snapshot_failed', (error as Error).message)
    }
  }

  private watchMainWindowMetrics(win: window.Window): void {
    this.publishMainWindowMetrics(win)
    if (this.windowSizeChangeCallback !== null) {
      return
    }
    this.windowSizeChangeCallback = (size: window.Size) => {
      LayoutSafeAreaBridge.publishMainWindowSizePx(size.width, size.height)
      // Drop the width cache after fold/unfold, rotation, or split-window resizing so a remount never
      // reuses a stale pre-change gallery width.
      LayoutSafeAreaBridge.publishGalleryContentWidth(0)
      LayoutSafeAreaBridge.invalidateGalleryDetailContentWidths()
      if (this.safeAreaUiContext !== null) {
        this.refreshSafeAreaInsets(win, this.safeAreaUiContext)
      }
    }
    try {
      win.on('windowSizeChange', this.windowSizeChangeCallback)
    } catch (error) {
      this.windowSizeChangeCallback = null
      DiagnosticLogger.warn('app', 'watch_window_metrics_failed', (error as Error).message)
    }
  }

  private watchKeyboardHeight(win: window.Window, uiCtx: UIContext): void {
    this.keyboardHeightCallback = (height: number) => {
      LayoutSafeAreaBridge.publishKeyboardHeight(uiCtx.px2vp(Math.max(0, height)))
    }
    try {
      win.on('keyboardHeightChange', this.keyboardHeightCallback)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'watch_keyboard_failed', e.message)
    }
  }

  private unwatch(win: window.Window): void {
    try {
      if (this.avoidAreaChangeCallback) {
        win.off('avoidAreaChange', this.avoidAreaChangeCallback)
      }
      if (this.windowSizeChangeCallback) {
        win.off('windowSizeChange', this.windowSizeChangeCallback)
      }
      if (this.keyboardHeightCallback) {
        win.off('keyboardHeightChange', this.keyboardHeightCallback)
      }
    } catch (_error) {}
  }

  private captureIncomingUrl(want: Want): void {
    const uri: string = (want?.uri ?? '').trim()
    if (
      uri === InternalQaRoutes.COVER_FALLBACK_PROBE_URI ||
      uri === InternalQaRoutes.READER_GESTURE_PROBE_URI ||
      uri === InternalQaRoutes.IMAGE_BLOCK_READER_OPEN_URI ||
      uri === InternalQaRoutes.IMAGE_BLOCK_SETTINGS_OPEN_URI
    ) {
      publishPendingEhUrl(`${Date.now()}:${uri}`)
      return
    }
    if (uri.length === 0 || !EhUrlRouter.canHandle(uri)) {
      return
    }
    publishPendingEhUrl(`${Date.now()}:${uri}`)
  }
}
