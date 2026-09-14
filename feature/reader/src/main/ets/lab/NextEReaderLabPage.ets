import { ReaderTrialLayoutCommit, ReaderSystemImageSaveHost, ReaderKeepScreenOn, ReaderTapAction,
  ReaderRuntimePolicyIntent, ReaderHostAction } from '@reader-kit/ui'
import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { connectSiteMode, connectReadMode, ReadModeState, connectLayoutSafeArea, LayoutSafeAreaState,
  connectThemeDisplay, ReaderBackgroundMode, ThemeDisplayState, ThemeConstants, immersiveTitleBar, EhHttpClient,
  GalleryReadProgressSettings, ReadMode, readerSuperResolutionSetInteractionPaused, AppStrings,
  CommentTranslationService, ComicVisualProviderSettings, ImageBlockSettingsState,
  connectImageBlockSettings } from 'shared'
import { appSheetOptions } from 'shared'
import { ReaderPagedSession, ReaderUnitKey, ReaderInputPort, ReaderImageShareHost, ReaderImageSaveHost,
  ReaderLayout, ReaderObservedPosition, ReaderDisplayPolicy, ReaderVariantPreference, ReaderPagedFrame,
  ReaderPage } from '@reader-kit/core'
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
import {
  NextEReaderTranslationConfiguration,
  NextEReaderTranslationProvider,
} from './NextEReaderTranslationProvider'
import {
  NextEReaderImageBlockMarkResult,
  NextEReaderImageBlockProvider,
} from './NextEReaderImageBlockProvider'

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
  private adapter: NextEReaderLabAdapter | null = null
  private imageBlockProvider: NextEReaderImageBlockProvider | null = null
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
  @Local private currentSourceIndex: number = -1
  @Local private translationRequestedPages: number[] = []
  @Local private translationAppliedPages: number[] = []
  @Local private translationHiddenPages: number[] = []
  @Local private translationAutoFailedPages: number[] = []
  @Local private translationAutoEnabled: boolean = false
  @Local private translationBusyPage: number = -1
  @Local private translationErrorPage: number = -1
  @Local private translationPreferenceRevision: number = 0
  @Local private imageBlockSettings: ImageBlockSettingsState = connectImageBlockSettings()
  @Local private imageBlockRuleSaving: boolean = false
  private translationAutoScheduleEpoch: number = 0

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context.applicationInfo.debug) return
    const forcedImageBlockSourceIndex = connectNextEReaderLabContextProbe().deliver(this.request.work, context)
    this.volumeDisposed = false
    this.keepScreenOn = new ReaderKeepScreenOn(context)
    if (this.request.readingChrome && this.managesTrialWindow) this.trialWindow.open(context)
    const isEx = this.entrySite.length > 0 ? this.entrySite === 'ex' : connectSiteMode().isEx
    this.unitKey = new ReaderUnitKey(isEx ? 'ex' : 'eh', this.request.work, this.request.work)
    const adapter = new NextEReaderLabAdapter(context, this.request.unit, isEx)
    this.adapter = adapter
    this.imageShare = new ReaderLabShareProbe(adapter, this.request.shareProbe)
    this.imageSave = new ReaderSystemImageSaveHost(context, async (uri: string, path: string): Promise<void> => {
      await EhHttpClient.getInstance().downloadBinaryToFile(uri, path)
    })
    const imageBlockProvider = new NextEReaderImageBlockProvider(context, adapter, (message: string): void => {
      this.getUIContext().getPromptAction().showToast({ message })
    }, forcedImageBlockSourceIndex)
    this.imageBlockProvider = imageBlockProvider
    const variantProvider = new NextEReaderSuperResolutionProvider(context, imageBlockProvider,
      (): NextEReaderSuperResolutionConfiguration => this.superResolutionConfiguration())
    const translationProvider = new NextEReaderTranslationProvider(context, variantProvider,
      (page: ReaderPage): NextEReaderTranslationConfiguration => this.translationConfiguration(page))
    const session = new ReaderPagedSession(adapter, new ReaderLabAssetProbe(translationProvider, this.request.thumbnailFailurePage,
      this.request.informationProbe, this.request.readingChrome ? this.request.failurePage : -1,
      this.request.originalVariantProbe), adapter)
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

  private translationConfiguration(_page: ReaderPage): NextEReaderTranslationConfiguration {
    const targetLanguage = CommentTranslationService.targetLanguage()
    const sourceLanguage = this.adapter?.sourceLanguage() ?? 'auto'
    const site = this.entrySite.length > 0 ? this.entrySite : (connectSiteMode().isEx ? 'ex' : 'eh')
    return new NextEReaderTranslationConfiguration(
      this.request.preferencesReadWrite,
      `nexte-gallery:${site}:${this.request.work}:${targetLanguage}`,
      targetLanguage,
      sourceLanguage,
      ComicVisualProviderSettings.runtimeRevision(),
    )
  }

  private translationFrame(sourceIndex: number): ReaderPagedFrame | null {
    return this.session?.snapshot().frames.find(
      (frame: ReaderPagedFrame): boolean => frame.part.sourceIndex === sourceIndex,
    ) ?? null
  }

  private translationWindowFrame(sourceIndex: number): ReaderPagedFrame | null {
    const state = this.session?.snapshot()
    if (state === null || state === undefined) return null
    for (const item of state.window) {
      const frame = item.frames.find(
        (candidate: ReaderPagedFrame): boolean => candidate.part.sourceIndex === sourceIndex,
      )
      if (frame !== undefined) return frame
    }
    return null
  }

  private translationPage(sourceIndex: number): ReaderPage | null {
    const framePage = this.translationWindowFrame(sourceIndex)?.asset.page
    if (framePage !== null && framePage !== undefined) return framePage
    return this.session?.snapshot().pageMetadata.find(
      (page: ReaderPage): boolean => page.sourceIndex === sourceIndex,
    ) ?? null
  }

  private translationIdentity(sourceIndex: number): string {
    const page = this.translationPage(sourceIndex)
    return page === null ? '' : this.translationConfiguration(page).identity()
  }

  private pageIncluded(values: number[], sourceIndex: number): boolean {
    return values.includes(sourceIndex)
  }

  private includePage(values: number[], sourceIndex: number): number[] {
    return values.includes(sourceIndex) ? values : values.concat([sourceIndex])
  }

  private excludePage(values: number[], sourceIndex: number): number[] {
    return values.filter((value: number): boolean => value !== sourceIndex)
  }

  private variantPreference(sourceIndex: number): ReaderVariantPreference {
    const translationRequested = this.pageIncluded(this.translationRequestedPages, sourceIndex) ||
      (this.translationAutoEnabled && sourceIndex === this.currentSourceIndex &&
        !this.pageIncluded(this.translationAutoFailedPages, sourceIndex))
    const identity = this.translationIdentity(sourceIndex)
    if (translationRequested && !this.pageIncluded(this.translationHiddenPages, sourceIndex) && identity.length > 0) {
      return new ReaderVariantPreference('translated', identity)
    }
    const enhancement = this.superResolutionConfiguration()
    return enhancement.enabled
      ? new ReaderVariantPreference('enhanced', enhancement.identity())
      : new ReaderVariantPreference()
  }

  private translationActions(): ReaderHostAction[] {
    if (!this.request.preferencesReadWrite || this.currentSourceIndex < 0) return []
    const translated = this.translationFrame(this.currentSourceIndex)?.asset.variant === 'translated' ||
      (this.pageIncluded(this.translationAppliedPages, this.currentSourceIndex) &&
        !this.pageIncluded(this.translationHiddenPages, this.currentSourceIndex))
    const hidden = this.pageIncluded(this.translationHiddenPages, this.currentSourceIndex)
    const label = translated ? AppStrings.get('reader_comic_translation_show_original') :
      hidden ? AppStrings.get('reader_comic_translation_show_result') :
        AppStrings.get('reader_comic_translation_action')
    const configured = this.translationIdentity(this.currentSourceIndex).length > 0
    return [
      new ReaderHostAction('translate-page', label, configured || translated || hidden,
        translated, this.translationBusyPage >= 0),
      new ReaderHostAction('translate-auto', AppStrings.get('reader_comic_translation_auto'), configured,
        this.translationAutoEnabled, this.translationBusyPage >= 0),
    ]
  }

  private hostActions(): ReaderHostAction[] {
    const actions = this.translationActions()
    const page = this.translationFrame(this.currentSourceIndex)?.asset.page ?? null
    if (this.imageBlockProvider?.canMark(page, this.imageBlockSettings.enabled) === true) {
      actions.push(new ReaderHostAction('mark-image-blocked', AppStrings.get('reader_image_block_mark'),
        !this.imageBlockRuleSaving, false, this.imageBlockRuleSaving))
    }
    return actions
  }

  private currentTranslationTarget(source: ReaderUnitKey, navigation: number, sourceIndex: number): boolean {
    const state = this.session?.snapshot()
    return state?.phase === 'ready' && state.unit?.key.equals(source) === true &&
      state.navigationRevision === navigation && state.anchor?.sourceIndexHint === sourceIndex
  }

  private handleTranslationAction(id: string, source: ReaderUnitKey, navigation: number, sourceIndex: number): void {
    if (!this.currentTranslationTarget(source, navigation, sourceIndex)) return
    if (id === 'translate-auto') {
      this.toggleTranslationAuto(sourceIndex)
      return
    }
    if (id !== 'translate-page' || this.translationBusyPage >= 0) return
    const translated = this.translationFrame(sourceIndex)?.asset.variant === 'translated' ||
      (this.pageIncluded(this.translationAppliedPages, sourceIndex) &&
        !this.pageIncluded(this.translationHiddenPages, sourceIndex))
    const hidden = this.pageIncluded(this.translationHiddenPages, sourceIndex)
    if (translated) {
      this.translationHiddenPages = this.includePage(this.translationHiddenPages, sourceIndex)
      this.translationRequestedPages = this.excludePage(this.translationRequestedPages, sourceIndex)
    } else {
      this.translationHiddenPages = this.excludePage(this.translationHiddenPages, sourceIndex)
      this.translationAutoFailedPages = this.excludePage(this.translationAutoFailedPages, sourceIndex)
      this.translationRequestedPages = this.includePage(this.translationRequestedPages, sourceIndex)
      this.translationBusyPage = sourceIndex
      this.translationErrorPage = -1
    }
    if (hidden) this.translationRequestedPages = this.includePage(this.translationRequestedPages, sourceIndex)
    this.translationPreferenceRevision += 1
  }

  private handleHostAction(id: string, source: ReaderUnitKey, navigation: number, sourceIndex: number): void {
    if (id === 'mark-image-blocked') {
      this.confirmMarkCurrentImageAsBlocked(source, navigation, sourceIndex)
      return
    }
    this.handleTranslationAction(id, source, navigation, sourceIndex)
  }

  private confirmMarkCurrentImageAsBlocked(source: ReaderUnitKey, navigation: number, sourceIndex: number): void {
    const page = this.translationFrame(sourceIndex)?.asset.page ?? null
    if (!this.currentTranslationTarget(source, navigation, sourceIndex) || this.imageBlockRuleSaving ||
      this.imageBlockProvider?.canMark(page, this.imageBlockSettings.enabled) !== true) return
    this.getUIContext().showAlertDialog({
      title: AppStrings.get('reader_image_block_mark'),
      message: AppStrings.get('reader_image_block_mark_confirm'),
      primaryButton: { value: AppStrings.get('common_cancel'), action: (): void => {} },
      secondaryButton: {
        value: AppStrings.get('reader_image_block_mark'),
        action: (): void => { void this.markCurrentImageAsBlocked(source, navigation, sourceIndex) },
      },
    })
  }

  private async markCurrentImageAsBlocked(source: ReaderUnitKey, navigation: number, sourceIndex: number): Promise<void> {
    if (!this.currentTranslationTarget(source, navigation, sourceIndex) || this.imageBlockRuleSaving) return
    const page = this.translationFrame(sourceIndex)?.asset.page ?? null
    if (this.imageBlockProvider?.canMark(page, this.imageBlockSettings.enabled) !== true) {
      this.getUIContext().getPromptAction().showToast({ message: AppStrings.get('reader_image_block_mark_waiting') })
      return
    }
    this.imageBlockRuleSaving = true
    try {
      const result: NextEReaderImageBlockMarkResult = await this.imageBlockProvider.mark(
        page, this.imageBlockSettings.enabled, this.gallerySourceUrl())
      if (result === 'failed') {
        this.getUIContext().getPromptAction().showToast({ message: AppStrings.get('reader_image_block_mark_failed') })
        return
      }
      if (result === 'waiting') {
        this.getUIContext().getPromptAction().showToast({ message: AppStrings.get('reader_image_block_mark_waiting') })
        return
      }
      if (result === 'added') {
        this.getUIContext().getPromptAction().showToast({ message: AppStrings.get('reader_image_block_mark_added') })
        await this.reloadCurrentSource(source, navigation, sourceIndex)
      }
    } finally {
      this.imageBlockRuleSaving = false
    }
  }

  private gallerySourceUrl(): string {
    return this.request.work.length > 0 && this.request.unit.length > 0
      ? `https://e-hentai.org/g/${this.request.work}/${this.request.unit}/`
      : ''
  }

  private async reloadCurrentSource(source: ReaderUnitKey, navigation: number, sourceIndex: number): Promise<void> {
    const state = this.session?.snapshot()
    if (state === null || state === undefined || state.phase !== 'ready' ||
      state.unit?.key.equals(source) !== true || state.navigationRevision !== navigation) return
    const item = state.window.find((candidate): boolean => candidate.frames.some(
      (frame: ReaderPagedFrame): boolean => frame.part.sourceIndex === sourceIndex))
    const frame = item?.frames.find((candidate: ReaderPagedFrame): boolean => candidate.part.sourceIndex === sourceIndex)
    if (item === undefined || frame === undefined) return
    await this.session?.reloadItem(state.topologyRevision, navigation, item.key,
      frame.slotId, frame.asset.requestId)
  }

  private toggleTranslationAuto(sourceIndex: number): void {
    if (this.translationBusyPage >= 0) return
    if (this.translationAutoEnabled) {
      this.translationAutoEnabled = false
      this.translationAutoScheduleEpoch += 1
      this.translationPreferenceRevision += 1
      return
    }
    if (this.translationIdentity(sourceIndex).length === 0) return
    this.getUIContext().showAlertDialog({
      title: AppStrings.get('reader_comic_translation_auto'),
      message: AppStrings.get('reader_comic_translation_auto_confirm'),
      primaryButton: { value: AppStrings.get('common_cancel'), action: (): void => {} },
      secondaryButton: {
        value: AppStrings.get('common_on'),
        action: (): void => {
          this.translationAutoFailedPages = []
          this.translationHiddenPages = this.excludePage(this.translationHiddenPages, sourceIndex)
          this.translationAutoEnabled = true
          if (this.translationFrame(sourceIndex)?.asset.variant !== 'translated') this.translationBusyPage = sourceIndex
          else this.scheduleNextAutoTranslation(sourceIndex)
          this.translationPreferenceRevision += 1
        },
      },
    })
  }

  private handleVariantSelection(sourceIndex: number, preference: ReaderVariantPreference,
    result: 'changed' | 'unchanged' | 'unavailable' | 'stale'): void {
    if (preference.variant !== 'translated') return
    if (this.translationBusyPage === sourceIndex) this.translationBusyPage = -1
    if (result === 'changed' || result === 'unchanged') {
      this.translationRequestedPages = this.includePage(this.translationRequestedPages, sourceIndex)
      this.translationAppliedPages = this.includePage(this.translationAppliedPages, sourceIndex)
      this.translationAutoFailedPages = this.excludePage(this.translationAutoFailedPages, sourceIndex)
      if (this.translationErrorPage === sourceIndex) this.translationErrorPage = -1
      if (this.translationAutoEnabled && sourceIndex === this.currentSourceIndex) {
        this.scheduleNextAutoTranslation(sourceIndex)
      }
      return
    }
    if (result === 'unavailable') {
      this.translationRequestedPages = this.excludePage(this.translationRequestedPages, sourceIndex)
      if (this.translationAutoEnabled) {
        this.translationAutoFailedPages = this.includePage(this.translationAutoFailedPages, sourceIndex)
      }
      if (sourceIndex === this.currentSourceIndex) {
        this.translationErrorPage = sourceIndex
        this.scheduleNextAutoTranslation(sourceIndex)
      }
      this.translationPreferenceRevision += 1
    }
  }

  private scheduleNextAutoTranslation(sourceIndex: number): void {
    const epoch = ++this.translationAutoScheduleEpoch
    const prepare = (attempt: number): void => {
      if (epoch !== this.translationAutoScheduleEpoch || !this.translationAutoEnabled ||
        this.currentSourceIndex !== sourceIndex || this.volumeDisposed || this.closeRequested || this.hostClosing) return
      const state = this.session?.snapshot()
      const session = this.session
      const next = sourceIndex + 1
      if (session === null || state?.phase !== 'ready' || state.unit === null || next >= state.unit.pageCount ||
        this.pageIncluded(this.translationAppliedPages, next) ||
        this.pageIncluded(this.translationAutoFailedPages, next) ||
        this.pageIncluded(this.translationHiddenPages, next)) return
      const frame = this.translationWindowFrame(next)
      if (frame?.asset.phase !== 'displayed') {
        if (attempt < 20) setTimeout((): void => prepare(attempt + 1), 100)
        return
      }
      const identity = this.translationIdentity(next)
      if (identity.length === 0) {
        if (attempt < 20) setTimeout((): void => prepare(attempt + 1), 100)
        return
      }
      this.translationBusyPage = next
      this.translationPreferenceRevision += 1
      const preference = new ReaderVariantPreference('translated', identity)
      void session.prepareVariantForSource(next, state.unit.key.copy(), state.navigationRevision,
        'translated', identity).then((result: 'changed' | 'unchanged' | 'unavailable' | 'stale'): void => {
          if (result === 'stale' && this.currentSourceIndex === next) return
          this.handleVariantSelection(next, preference, result)
        })
    }
    setTimeout((): void => prepare(0), 0)
  }

  private observeReaderPosition(position: ReaderObservedPosition): void {
    const sourceIndex = position.anchor.sourceIndexHint
    if (this.currentSourceIndex !== sourceIndex) {
      this.currentSourceIndex = sourceIndex
      if (this.translationAutoEnabled && !this.pageIncluded(this.translationAutoFailedPages, sourceIndex) &&
        !this.pageIncluded(this.translationHiddenPages, sourceIndex) &&
        this.translationFrame(sourceIndex)?.asset.variant !== 'translated') this.translationBusyPage = sourceIndex
      else if (this.translationAutoEnabled && this.translationFrame(sourceIndex)?.asset.variant === 'translated') {
        this.scheduleNextAutoTranslation(sourceIndex)
      }
      this.translationPreferenceRevision += 1
    }
    this.persistObserved(position)
  }

  private setEnhancementInteractionBusy(busy: boolean): void {
    if (this.enhancementInteractionTimer >= 0) {
      clearTimeout(this.enhancementInteractionTimer)
      this.enhancementInteractionTimer = -1
    }
    if (busy) {
      readerSuperResolutionSetInteractionPaused(true)
      return
    }
    this.enhancementInteractionTimer = setTimeout((): void => {
      this.enhancementInteractionTimer = -1
      readerSuperResolutionSetInteractionPaused(false)
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
    this.translationAutoScheduleEpoch += 1
    this.translationAutoEnabled = false
    this.translationBusyPage = -1
    if (this.enhancementInteractionTimer >= 0) clearTimeout(this.enhancementInteractionTimer)
    this.enhancementInteractionTimer = -1
    readerSuperResolutionSetInteractionPaused(false)
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
              preloadDepth: this.readMode.preloadPages,
              preferredVariant: this.readMode.superResolutionEnabled ? 'enhanced' : 'default',
              preferredVariantIdentity: this.superResolutionIdentity(),
              variantPreferenceResolver: (sourceIndex: number): ReaderVariantPreference =>
                this.variantPreference(sourceIndex),
              variantPreferenceRevision: this.translationPreferenceRevision,
              onVariantSelection: (sourceIndex: number, preference: ReaderVariantPreference,
                result: 'changed' | 'unchanged' | 'unavailable' | 'stale'): void => {
                this.handleVariantSelection(sourceIndex, preference, result)
              },
              showPageNumber: this.readMode.showPageNumber,
              cropBorders: this.initialCropBorders(),
              cropAvailable: !this.request.thumbnailEntry,
              hostSettingsAvailable: this.request.preferencesReadWrite,
              onHostSettings: (): void => { this.openHostSettings() },
              hostActions: this.hostActions(),
              onHostAction: (id: string, source: ReaderUnitKey, navigation: number, sourceIndex: number): void => {
                this.handleHostAction(id, source, navigation, sourceIndex)
              },
              hostStatusVisible: this.currentSourceIndex >= 0 &&
                (this.translationBusyPage === this.currentSourceIndex || this.translationErrorPage === this.currentSourceIndex),
              hostStatusBusy: this.translationBusyPage === this.currentSourceIndex,
              hostStatusText: this.translationBusyPage === this.currentSourceIndex
                ? AppStrings.get('reader_comic_translation_running')
                : AppStrings.get('reader_comic_translation_failed'),
              onObservedPosition: (position: ReaderObservedPosition): void => { this.observeReaderPosition(position) },
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
            preloadDepth: this.readMode.preloadPages,
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
