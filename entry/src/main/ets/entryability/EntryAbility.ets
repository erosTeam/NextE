import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AppStrings, DiagnosticLogger, SettingsBootstrap, publishPendingEhUrl, EhUrlRouter, LayoutSafeAreaBridge } from 'shared'

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
    AppStrings.init(this.context)
    DiagnosticLogger.info('app', 'session_start', 'EntryAbility.onCreate')
    this.captureIncomingUrl(want)
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
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('app', 'configure_window_failed', e.message)
    }
    SettingsBootstrap.loadAll(this.context).finally(() => {
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
    } catch (_error) {
    }
  }

  private captureIncomingUrl(want: Want): void {
    const uri: string = (want?.uri ?? '').trim()
    if (uri.length === 0 || !EhUrlRouter.canHandle(uri)) {
      return
    }
    publishPendingEhUrl(`${Date.now()}:${uri}`)
  }
}
