import { AbilityConstant, UIAbility, Want, Configuration, common } from '@kit.AbilityKit'
import { webview } from '@kit.ArkWeb'
import { window } from '@kit.ArkUI'
import {
  AppStrings,
  DiagnosticLogger,
  SettingsBootstrap,
  ThemeSettings,
  MotionHandStateService,
  publishPendingEhUrl,
  EhUrlRouter,
  LayoutSafeAreaBridge,
  InternalQaRoutes,
  HuaweiCloudSyncService,
  HuaweiCloudSyncScheduler,
  ImageKnifeProRuntime,
  SecuritySettings,
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
  private avoidAreaChangeCallback: ((data: window.AvoidAreaOptions) => void) | null = null
  private windowSizeChangeCallback: ((size: window.Size) => void) | null = null
  private keyboardHeightCallback: ((height: number) => void) | null = null

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    HuaweiCloudSyncScheduler.bindExecutor((context: common.UIAbilityContext, reason: string) => {
      return HuaweiCloudSyncService.runScheduledSync(context, reason)
    })
    SyncScheduler.rememberContext(this.context)
    AppStrings.init(this.context)
    DiagnosticLogger.initializePersistentSink(this.context)
    DiagnosticLogger.info('app', 'session_start', 'EntryAbility.onCreate')
    ImageKnifeProRuntime.initialize(this.context)
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
          const uiCtx: UIContext = w.getUIContext()
          this.refreshSafeAreaInsets(w, uiCtx)
          this.watchSafeAreaInsets(w, uiCtx)
          this.watchKeyboardHeight(w, uiCtx)
          SecuritySettings.lockIfNeeded(this.context, 'startup')
        } catch (e) {
          LayoutSafeAreaBridge.publishInsets(FALLBACK_TOP_AVOID, FALLBACK_BOTTOM_AVOID)
        }
      })
    })
  }

  onDestroy(): void {
    if (this.mainWindow) {
      this.unwatch(this.mainWindow)
    }
    DiagnosticLogger.info('app', 'session_end', 'EntryAbility.onDestroy')
    DiagnosticLogger.closePersistentSink()
  }

  onForeground(): void {
    SyncScheduler.rememberContext(this.context)
    SyncScheduler.requestAfterForeground(this.context, 'foreground')
    ImageKnifeProRuntime.reloadOnForeground()
    SecuritySettings.lockIfNeeded(this.context, 'foreground')
  }

  onBackground(): void {
    ImageKnifeProRuntime.clearOnBackground()
    SecuritySettings.recordBackground(this.context)
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
    this.windowSizeChangeCallback = (_size: window.Size) => {
      this.refreshSafeAreaInsets(win, uiCtx)
      // Window width changed (fold/unfold, rotation, split-screen): drop the cached gallery content width
      // so a remounting list recomputes its column count from the new width, not the stale pre-fold one.
      LayoutSafeAreaBridge.publishGalleryContentWidth(0)
    }
    try {
      win.on('avoidAreaChange', this.avoidAreaChangeCallback)
      win.on('windowSizeChange', this.windowSizeChangeCallback)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'watch_safe_area_failed', e.message)
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
