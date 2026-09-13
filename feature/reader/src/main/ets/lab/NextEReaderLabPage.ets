import { ReaderTrialLayoutCommit, ReaderSystemImageSaveHost, ReaderKeepScreenOn, ReaderTapAction,
  ReaderRuntimePolicyIntent } from '@reader-kit/ui'
import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { connectSiteMode, connectReadMode, ReadModeState, connectLayoutSafeArea, LayoutSafeAreaState,
  connectThemeDisplay, ReaderBackgroundMode, ThemeDisplayState, ThemeConstants, immersiveTitleBar, EhHttpClient,
  GalleryReadProgressSettings, ReadMode, ReaderSuperResolutionService } from 'shared'
import { appSheetOptions } from 'shared'
import { ReaderPagedSession, ReaderUnitKey, ReaderInputPort, ReaderImageShareHost, ReaderImageSaveHost,
  ReaderLayout, ReaderObservedPosition, ReaderDisplayPolicy } from '@reader-kit/core'
import { ReaderEntryTransition, ReaderEntryPreviewSource } from '@reader-kit/ui'
import { ReaderLabRequest, ReaderLabSurface, ReaderSurface, ReaderTrialWindow, ReaderLabVisibilityState, connectReaderLabVisibility, ReaderLabAssetProbe, ReaderVolumeKeys } from '@reader-kit/ui'
import { NextEReaderLabAdapter } from './NextEReaderLabAdapter'
import { ReaderLabShareProbe } from '@reader-kit/ui'
import { connectGalleryReadProgress, ReaderTapZoneResolver } from 'shared'
import { NextEReaderInitialPolicy } from './NextEReaderInitialPolicy'
import { connectNextEReaderLabContextProbe } from './NextEReaderLabContextProbe'
import { NextEReaderRuntimePreferences } from './NextEReaderRuntimePreferences'
import {
  NextEReaderSuperResolutionConfiguration,
  NextEReaderSuperResolutionProvider,
} from './NextEReaderSuperResolutionProvider'

@ComponentV2
export struct NextEReaderLabPage {
  @Require @Param request: ReaderLabRequest
  @BuilderParam settingsSheetContent: (dismiss: () => void) => void
  @Param entryTransition: ReaderEntryTransition | null = null
  @Param entryPhase: string = 'finished'
  @Param entryPreview: ReaderEntryPreviewSource | null = null
  @Param entrySite: string = ''
  @Param managesTrialWindow: boolean = true
  @Param hostClosing: boolean = false
  @Param prepareChrome: ((isCurrent: () => boolean) => Promise<boolean>) | null = null
  @Event onClose: () => void = () => {}
  @Event onShown: () => void = () => {}
  @Event onStatusBarVisible: (visible: boolean) => void = () => {}
  @Local private session: ReaderPagedSession | null = null
  private imageShare: ReaderImageShareHost | null = null
  private imageSave: ReaderImageSaveHost | null = null
  @Local private labVisibility: ReaderLabVisibilityState = connectReaderLabVisibility()
  @Local private readMode: ReadModeState = connectReadMode()
  @Local private themeDisplay: ThemeDisplayState = connectThemeDisplay()
  @Local private routeActive: boolean = false
  @Local private safeArea: LayoutSafeAreaState = connectLayoutSafeArea()
  private unitKey: ReaderUnitKey = new ReaderUnitKey('', '', '')
  private trialWindow: ReaderTrialWindow = new ReaderTrialWindow(null, true)
  private keepScreenOn: ReaderKeepScreenOn | null = null
  @Local private closeRequested: boolean = false
  @Local private readerSettingsSheetShown: boolean = false
  private volumeDisposed: boolean = false
  private input: ReaderInputPort = new ReaderInputPort()
  private volumeKeys: ReaderVolumeKeys = new ReaderVolumeKeys(this.input)
  private enhancementInteractionTimer: number = -1

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context.applicationInfo.debug) return
    connectNextEReaderLabContextProbe().deliver(this.request.work, context)
    this.volumeDisposed = false
    this.keepScreenOn = new ReaderKeepScreenOn(context)
    if (this.request.readingChrome && this.managesTrialWindow) this.trialWindow.open(context)
    const isEx = this.entrySite.length > 0 ? this.entrySite === 'ex' : connectSiteMode().isEx
    this.unitKey = new ReaderUnitKey(isEx ? 'ex' : 'eh', this.request.work, this.request.work)
    const adapter = new NextEReaderLabAdapter(context, this.request.unit, isEx)
    this.imageShare = new ReaderLabShareProbe(adapter, this.request.shareProbe)
    this.imageSave = new ReaderSystemImageSaveHost(context, async (uri: string, path: string): Promise<void> => {
      await EhHttpClient.getInstance().downloadBinaryToFile(uri, path)
    })
    const variantProvider = new NextEReaderSuperResolutionProvider(context, adapter,
      (): NextEReaderSuperResolutionConfiguration => this.superResolutionConfiguration())
    const session = new ReaderPagedSession(adapter, new ReaderLabAssetProbe(variantProvider, this.request.thumbnailFailurePage,
      this.request.informationProbe, this.request.thumbnailEntry ? this.request.failurePage : -1, this.request.originalVariantProbe))
    if (this.request.readingChrome) {
      this.initializeSession(session)
      return
    }
    this.session = session
  }

  private initializeSession(session: ReaderPagedSession): void {
    if (this.volumeDisposed || this.closeRequested || this.hostClosing) return
    const progress = connectGalleryReadProgress()
    // EntryAbility mounts content after canonical bootstrap. Never repeat its best-effort restores here.
    if (this.readMode.restoreResult !== 'applied' || progress.restoreResult !== 'applied') {
      console.warn(`[NextEReaderLab] initial_policy_unavailable mode=${this.readMode.restoreResult} gallery=${progress.restoreResult}`)
      this.closeTrial(true)
      return
    }
    const column = progress.getColumnMode(this.request.work)
    const policy = NextEReaderInitialPolicy.resolve(this.readMode, column, this.request)
    session.setPolicy(policy)
    if (this.request.progressReadWrite && !this.request.pageIndexProvided) {
      this.request.pageIndex = progress.getIndex(this.request.work)
    }
    console.info(`[NextEReaderLab] initial_policy column=${column} cover=${policy.firstPageAlone} layout=${policy.layout} axis=${policy.pagingAxis} direction=${policy.direction} spread=${policy.spreadLayout}`)
    this.session = session
  }

  private readerCanvasDark(): boolean {
    if (this.readMode.backgroundMode === ReaderBackgroundMode.WHITE) return false
    if (this.readMode.backgroundMode === ReaderBackgroundMode.AUTO) return this.themeDisplay.effectiveDark
    return true
  }

  private readerCanvasBackground(): ResourceColor {
    if (this.readMode.backgroundMode === ReaderBackgroundMode.GRAY) return ThemeConstants.READER_BACKGROUND_GRAY
    if (this.readMode.backgroundMode === ReaderBackgroundMode.WHITE ||
      (this.readMode.backgroundMode === ReaderBackgroundMode.AUTO && !this.themeDisplay.effectiveDark)) {
      return ThemeConstants.READER_BACKGROUND_WHITE
    }
    return ThemeConstants.READER_BACKGROUND_BLACK
  }

  private readerCanvasForeground(): ResourceColor {
    return this.readerCanvasDark() ? ThemeConstants.READER_FOREGROUND_LIGHT : ThemeConstants.READER_FOREGROUND_DARK
  }

  private superResolutionConfiguration(): NextEReaderSuperResolutionConfiguration {
    return new NextEReaderSuperResolutionConfiguration(
      this.readMode.superResolutionEnabled,
      this.readMode.superResolutionModel,
      this.readMode.superResolutionBackend,
      this.readMode.superResolutionMaxHeight,
    )
  }

  private superResolutionIdentity(): string {
    return this.superResolutionConfiguration().identity()
  }

  private setEnhancementInteractionBusy(busy: boolean): void {
    if (this.enhancementInteractionTimer >= 0) {
      clearTimeout(this.enhancementInteractionTimer)
      this.enhancementInteractionTimer = -1
    }
    if (busy) {
      ReaderSuperResolutionService.setInteractionPaused(true)
      return
    }
    this.enhancementInteractionTimer = setTimeout((): void => {
      this.enhancementInteractionTimer = -1
      ReaderSuperResolutionService.setInteractionPaused(false)
    }, 420)
  }

  private persistObserved(position: ReaderObservedPosition): void {
    if (!this.request.progressReadWrite || !this.routeActive || !this.labVisibility.foreground ||
      this.closeRequested || this.hostClosing || position.anchor.unit.scope !== this.unitKey.scope ||
      position.anchor.unit.work !== this.unitKey.work || position.anchor.unit.unit !== this.unitKey.unit) return
    GalleryReadProgressSettings.setIndex(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.request.work,
      position.anchor.sourceIndexHint,
    )
  }

  private persistRuntimePolicy(policy: ReaderDisplayPolicy, intent: ReaderRuntimePolicyIntent): void {
    if (!this.request.preferencesReadWrite || !this.routeActive || !this.labVisibility.foreground ||
      this.closeRequested || this.hostClosing) return
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (intent === 'layout') void NextEReaderRuntimePreferences.applyLayout(context, policy)
    else if (intent === 'direction') void NextEReaderRuntimePreferences.applyDirection(context, policy)
    else if (intent === 'spread_layout') void NextEReaderRuntimePreferences.applySpreadLayout(context, policy)
    else if (intent === 'first_page_alone') {
      NextEReaderRuntimePreferences.applyFirstPageAlone(context, this.request.work, policy)
    }
  }

  private persistCrop(enabled: boolean, policy: ReaderDisplayPolicy): void {
    if (!this.request.preferencesReadWrite || !this.routeActive || !this.labVisibility.foreground ||
      this.closeRequested || this.hostClosing) return
    void NextEReaderRuntimePreferences.applyCrop(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      policy,
      enabled,
    )
  }

  private initialCropBorders(): boolean {
    if (this.request.thumbnailEntry) return false
    if (this.request.cropBorders) return true
    if (!this.request.preferencesReadWrite) return false
    return this.readMode.mode === ReadMode.VERTICAL
      ? this.readMode.cropBordersContinuous
      : this.readMode.cropBordersPaged
  }

  private resolveTapZone(x: number, y: number, layout: ReaderLayout): ReaderTapAction {
    if (this.readMode.restoreResult !== 'applied' || this.volumeDisposed || this.closeRequested || this.hostClosing ||
      !this.routeActive || !this.labVisibility.foreground || this.session === null) return 'none'
    const continuous = layout === 'continuous'
    const action = ReaderTapZoneResolver.resolve(
      continuous ? this.readMode.tapZoneLayoutContinuous : this.readMode.tapZoneLayoutPaged,
      continuous ? this.readMode.tapZoneInvertContinuous : this.readMode.tapZoneInvertPaged,
      x, y, 1, 1)
    if (action === 'previous' || action === 'next' || action === 'left' || action === 'right') return action
    return 'menu'
  }

  aboutToDisappear(): void {
    this.volumeDisposed = true
    if (this.enhancementInteractionTimer >= 0) clearTimeout(this.enhancementInteractionTimer)
    this.enhancementInteractionTimer = -1
    ReaderSuperResolutionService.setInteractionPaused(false)
    this.keepScreenOn?.close()
    this.entryTransition?.cancel(); this.entryPreview?.release()
    this.volumeKeys.close()
    if (this.request.progressReadWrite) {
      GalleryReadProgressSettings.flush(this.getUIContext().getHostContext() as common.UIAbilityContext)
    }
    if (this.managesTrialWindow) this.trialWindow.close()
  }

  private syncChromeVisible(visible: boolean): void {
    if (visible) return // The before-show gate already applied host visibility.
    const statusVisible = !connectReadMode().fullscreen || visible
    if (this.managesTrialWindow) this.trialWindow.setStatusBarVisible(statusVisible)
    else this.onStatusBarVisible(statusVisible)
  }

  private async prepareChromeShow(isCurrent: () => boolean): Promise<boolean> {
    const current = (): boolean => isCurrent() && !this.closeRequested && !this.hostClosing &&
      this.routeActive && this.labVisibility.foreground
    if (!current()) return false
    if (!this.managesTrialWindow) return this.prepareChrome === null ? false : this.prepareChrome(current)
    if (!await this.trialWindow.prepareStatusBarVisible() || !current()) return false
    return ReaderTrialLayoutCommit.wait(this.getUIContext(), (): string =>
      this.safeArea.topAvoidHeight > 0 ? `${this.safeArea.topAvoidHeight}:${this.safeArea.bottomAvoidHeight}` : '', current)
  }

  private closeTrial(initializationFailed: boolean = false): void {
    if (this.closeRequested) return
    this.closeRequested = true
    if (this.managesTrialWindow) this.trialWindow.close(async (): Promise<boolean> => {
      if (this.trialWindow.getCloseSystemAvoidAreaResult() === 'ready') {
        const ready = await ReaderTrialLayoutCommit.wait(this.getUIContext(), (): string =>
          this.safeArea.topAvoidHeight > 0 ? `${this.safeArea.topAvoidHeight}:${this.safeArea.bottomAvoidHeight}` : '',
          (): boolean => this.routeActive && this.labVisibility.foreground)
        console.info(`[ReaderTrialHost] standalone_close_layout_ready=${ready}`)
        return ready
      }
      return true
    }).then((): void => {
      if (this.routeActive || (initializationFailed && !this.volumeDisposed)) this.onClose()
    })
    else this.onClose()
  }

  syncKeepScreenOn(): void {
    console.info(`[ReaderKeepScreenOn] host route=${this.routeActive} foreground=${this.labVisibility.foreground} phase=${this.entryPhase} closing=${this.closeRequested || this.hostClosing} setting=${this.readMode.keepScreenOn}`)
    this.keepScreenOn?.setActive(this.request.readingChrome && this.routeActive && this.labVisibility.foreground &&
      !this.readerSettingsSheetShown &&
      this.entryPhase !== 'layout' && !this.closeRequested && !this.hostClosing && this.readMode.keepScreenOn)
  }

  @Monitor('readMode.keepScreenOn', 'closeRequested', 'hostClosing', 'readerSettingsSheetShown')
  syncKeepScreenOnPolicy(): void { this.syncKeepScreenOn() }

  @Monitor('routeActive', 'labVisibility.foreground', 'entryPhase', 'readMode.volumeKeyTurn',
    'readMode.volumeKeyTurnReady', 'closeRequested', 'hostClosing', 'readerSettingsSheetShown', 'session')
  syncReaderActivity(): void {
    this.syncKeepScreenOn()
    const enabled = this.request.volumeKeysOverride ?? (this.readMode.volumeKeyTurnReady && this.readMode.volumeKeyTurn)
    this.volumeKeys.setActive(!this.volumeDisposed && !this.closeRequested && !this.hostClosing &&
      this.session !== null && this.request.readingChrome && enabled &&
      this.routeActive && this.labVisibility.foreground && !this.readerSettingsSheetShown &&
      this.entryPhase !== 'layout')
  }

  private openHostSettings(): void {
    if (!this.request.preferencesReadWrite || this.closeRequested || this.hostClosing) return
    this.readerSettingsSheetShown = true
  }

  private closeHostSettings(): void {
    this.readerSettingsSheetShown = false
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.session !== null) {
          if (this.request.readingChrome) {
            ReaderSurface({ session: this.session, initialUnit: this.unitKey, initialIndex: this.request.pageIndex,
              imageInterpolation: this.readMode.imageScalingQuality === 'low' ? ImageInterpolation.Low :
                this.readMode.imageScalingQuality === 'high' ? ImageInterpolation.High : ImageInterpolation.Medium,
              canvasBackground: this.readerCanvasBackground(), canvasForeground: this.readerCanvasForeground(),
              input: this.input, imageShare: this.imageShare, imageSave: this.imageSave,
              tapZoneResolver: (x: number, y: number, layout: ReaderLayout): ReaderTapAction => this.resolveTapZone(x, y, layout),
              autoReadAvailable: true, autoReadSeconds: this.readMode.autoPageSeconds,
              pageTurnAnimation: this.request.pageTurnAnimationOverride ?? this.readMode.pageTurnAnimation,
              preferredVariant: this.readMode.superResolutionEnabled ? 'enhanced' : 'default',
              preferredVariantIdentity: this.superResolutionIdentity(),
              showPageNumber: this.readMode.showPageNumber,
              cropBorders: this.initialCropBorders(),
              cropAvailable: !this.request.thumbnailEntry,
              hostSettingsAvailable: this.request.preferencesReadWrite,
              onHostSettings: (): void => { this.openHostSettings() },
              onObservedPosition: (position: ReaderObservedPosition): void => { this.persistObserved(position) },
              onPolicyChanged: (policy: ReaderDisplayPolicy, intent: ReaderRuntimePolicyIntent): void => {
                this.persistRuntimePolicy(policy, intent)
              },
              onCropChanged: (enabled: boolean, policy: ReaderDisplayPolicy): void => {
                this.persistCrop(enabled, policy)
              },
              entryTransition: this.entryTransition, entryPreview: this.entryPreview,
              active: this.routeActive && this.labVisibility.foreground && !this.readerSettingsSheetShown,
              closing: this.closeRequested || this.hostClosing,
              beforeShowChrome: (isCurrent: () => boolean): Promise<boolean> => this.prepareChromeShow(isCurrent),
              topInset: this.safeArea.topAvoidHeight, bottomInset: this.safeArea.bottomAvoidHeight,
              accent: ThemeConstants.BRAND_PRIMARY, onClose: (): void => this.closeTrial(),
              onInteractionBusy: (busy: boolean): void => { this.setEnhancementInteractionBusy(busy) },
              onChromeVisible: (visible: boolean): void => this.syncChromeVisible(visible) })
          } else {
          ReaderLabSurface({ session: this.session, initialUnit: this.unitKey, initialIndex: this.request.pageIndex,
            failurePage: this.request.failurePage,
            failureLayout: this.request.failureLayout,
            delayedMetricsPage: this.request.delayedMetricsPage,
            active: this.routeActive && this.labVisibility.foreground })
          }
        }
      }
      .width('100%').height('100%')
      .padding({ top: this.request.readingChrome ? 0 : this.safeArea.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT,
        bottom: this.request.readingChrome ? 0 : this.safeArea.bottomAvoidHeight })
      .bindSheet(
        $$this.readerSettingsSheetShown,
        this.settingsSheetContent((): void => { this.closeHostSettings() }),
        appSheetOptions({
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          showClose: false,
          onDisappear: (): void => { this.closeHostSettings() },
        }),
      )
    }.titleBar(immersiveTitleBar($r('app.string.rkit_lab_title')))
    .hideTitleBar(this.request.readingChrome)
    .onBackPressed((): boolean => {
      if (!this.request.readingChrome) return false
      this.closeTrial()
      return true
    })
    .onShown((): void => { this.routeActive = true; this.onShown() })
    .onHidden((): void => { this.routeActive = false })
  }
}
