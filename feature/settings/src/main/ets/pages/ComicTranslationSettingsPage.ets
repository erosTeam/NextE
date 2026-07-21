import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  COMIC_VISUAL_ROUTE_LOCAL,
  COMIC_VISUAL_ROUTE_TORII,
  ComicVisualProviderSettings,
  ComicVisualProviderSettingsSnapshot,
  ComicTranslationLiveEvaluationReport,
  ComicTranslationLiveEvaluationService,
  ComicTranslationModelCatalogService,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceProfileRepository,
  LlmSourceProfilesState,
  SecondaryListScaffold,
  TORII_BILLING_BYOK,
  TORII_BILLING_MANAGED,
  TORII_BYOK_ANTHROPIC,
  TORII_BYOK_DEEPSEEK,
  TORII_BYOK_GOOGLE,
  TORII_BYOK_OPENAI,
  TORII_BYOK_OPENROUTER,
  TORII_BYOK_XAI,
  TORII_DEFAULT_MODEL_ID,
  ThemeConstants,
  ToriiCreditsService,
  ToriiCreditsSnapshot,
  ToriiTranslatorModel,
  ToriiTranslatorModelCatalog,
  ToriiWholePageCredential,
  ToriiWholePageSecretStore,
  connectLlmSourceProfiles,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct ComicTranslationSettingsPage {
  @Local private llmSources: LlmSourceProfilesState = connectLlmSourceProfiles();
  @Local private sourceMenuShown: boolean = false;
  @Local private modelMenuShown: boolean = false;
  @Local private fetchingModels: boolean = false;
  @Local private modelOptions: string[] = [];
  @Local private selectedSourceId: string = '';
  @Local private selectedModelId: string = '';
  @Local private liveEvaluationRunning: boolean = false;
  @Local private liveEvaluationReport: ComicTranslationLiveEvaluationReport | null = null;
  @Local private visualRouteMenuShown: boolean = false;
  @Local private toriiModelMenuShown: boolean = false;
  @Local private toriiBillingMenuShown: boolean = false;
  @Local private toriiProviderMenuShown: boolean = false;
  @Local private visualRoute: string = COMIC_VISUAL_ROUTE_LOCAL;
  @Local private toriiModelId: string = TORII_DEFAULT_MODEL_ID;
  @Local private toriiBillingMode: string = TORII_BILLING_MANAGED;
  @Local private toriiByokProvider: string = TORII_BYOK_OPENROUTER;
  @Local private toriiApiKeyDraft: string = '';
  @Local private toriiByokApiKeyDraft: string = '';
  @Local private toriiCredits: ToriiCreditsSnapshot | null = null;
  @Local private toriiCreditsRefreshing: boolean = false;
  @Local private visualSettingsLoaded: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.restoreBinding()
    this.loadVisualSettings()
  }

  aboutToDisappear(): void {
    if (this.visualSettingsLoaded) {
      this.persistVisualSettings(false)
    }
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private async loadVisualSettings(): Promise<void> {
    try {
      const snapshot: ComicVisualProviderSettingsSnapshot =
        await ComicVisualProviderSettings.load(this.ctx())
      const credential: ToriiWholePageCredential =
        await ToriiWholePageSecretStore.read(this.ctx())
      this.visualRoute = snapshot.route
      this.toriiModelId = snapshot.toriiModelId
      this.toriiBillingMode = snapshot.toriiBillingMode
      this.toriiByokProvider = snapshot.toriiByokProvider
      this.toriiApiKeyDraft = credential.toriiApiKey
      this.toriiByokApiKeyDraft = credential.byokApiKey
      this.toriiCredits = await ToriiCreditsService.cached(
        this.ctx(),
        credential.toriiApiKey,
      )
      this.visualSettingsLoaded = true
      if (snapshot.route === COMIC_VISUAL_ROUTE_TORII) {
        this.refreshToriiCredits()
      }
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'visual_settings_load_failed',
        (error as Error).message,
      )
      this.toast($r('app.string.comic_torii_save_failed', (error as Error).message))
    }
  }

  private async persistVisualSettings(showFailureToast: boolean = true): Promise<boolean> {
    const snapshot: ComicVisualProviderSettingsSnapshot =
      new ComicVisualProviderSettingsSnapshot()
    snapshot.route = this.visualRoute
    snapshot.toriiModelId = this.toriiModelId
    snapshot.toriiBillingMode = this.toriiBillingMode
    snapshot.toriiByokProvider = this.toriiByokProvider
    const credential: ToriiWholePageCredential = new ToriiWholePageCredential()
    credential.toriiApiKey = this.toriiApiKeyDraft.trim()
    credential.byokApiKey = this.toriiByokApiKeyDraft.trim()
    try {
      await ComicVisualProviderSettings.save(this.ctx(), snapshot)
      await ToriiWholePageSecretStore.save(this.ctx(), credential)
      this.toriiApiKeyDraft = credential.toriiApiKey
      this.toriiByokApiKeyDraft = credential.byokApiKey
      return true
    } catch (error) {
      DiagnosticLogger.warn(
        'comic-translation',
        'visual_settings_save_failed',
        (error as Error).message,
      )
      if (showFailureToast) {
        this.toast($r('app.string.comic_torii_save_failed', (error as Error).message))
      }
      return false
    }
  }

  private visualRouteText(): ResourceStr {
    return this.visualRoute === COMIC_VISUAL_ROUTE_TORII
      ? $r('app.string.comic_visual_route_torii')
      : $r('app.string.comic_visual_route_local')
  }

  private selectVisualRoute(route: string): void {
    this.visualRouteMenuShown = false
    if (route === this.visualRoute) {
      return
    }
    if (route === COMIC_VISUAL_ROUTE_TORII) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.comic_visual_route_torii_confirm_title'),
        message: $r('app.string.comic_visual_route_torii_confirm'),
        primaryButton: {
          value: $r('app.string.common_cancel'),
          action: () => {},
        },
        secondaryButton: {
          value: $r('app.string.common_ok'),
          action: () => {
            this.visualRoute = COMIC_VISUAL_ROUTE_TORII
            this.persistVisualSettings(true)
            this.refreshToriiCredits()
          },
        },
      })
      return
    }
    this.visualRoute = COMIC_VISUAL_ROUTE_LOCAL
    this.persistVisualSettings(true)
  }

  private toriiModels(): ToriiTranslatorModel[] {
    const all: ToriiTranslatorModel[] = ToriiTranslatorModelCatalog.all()
    const output: ToriiTranslatorModel[] = []
    for (let index: number = 0; index < all.length; index++) {
      if (ToriiTranslatorModelCatalog.compatible(
        all[index].modelId,
        this.toriiBillingMode,
        this.toriiByokProvider,
      )) {
        output.push(all[index])
      }
    }
    return output
  }

  private toriiModelText(): string {
    const model: ToriiTranslatorModel | null =
      ToriiTranslatorModelCatalog.find(this.toriiModelId)
    if (model === null) {
      return this.toriiModelId
    }
    return `${model.displayName} · ${model.baseCredits}+`
  }

  private selectToriiModel(modelId: string): void {
    this.toriiModelId = modelId
    this.toriiModelMenuShown = false
    this.persistVisualSettings(true)
  }

  private selectToriiBilling(mode: string): void {
    this.toriiBillingMode = mode
    this.toriiBillingMenuShown = false
    this.ensureCompatibleToriiModel()
    this.persistVisualSettings(true)
  }

  private selectToriiProvider(provider: string): void {
    this.toriiByokProvider = provider
    this.toriiProviderMenuShown = false
    this.ensureCompatibleToriiModel()
    this.persistVisualSettings(true)
  }

  private ensureCompatibleToriiModel(): void {
    if (ToriiTranslatorModelCatalog.compatible(
      this.toriiModelId,
      this.toriiBillingMode,
      this.toriiByokProvider,
    )) {
      return
    }
    const models: ToriiTranslatorModel[] = this.toriiModels()
    if (models.length > 0) {
      this.toriiModelId = models[0].modelId
    }
  }

  private toriiBillingText(): ResourceStr {
    return this.toriiBillingMode === TORII_BILLING_BYOK
      ? $r('app.string.comic_torii_billing_byok')
      : $r('app.string.comic_torii_billing_managed')
  }

  private toriiNotice(): ResourceStr {
    return this.toriiBillingMode === TORII_BILLING_BYOK
      ? $r('app.string.comic_torii_notice_byok')
      : $r('app.string.comic_torii_notice_managed')
  }

  private refreshToriiCredits(): void {
    const apiKey: string = this.toriiApiKeyDraft.trim()
    if (apiKey.length === 0 || this.toriiCreditsRefreshing) {
      return
    }
    this.toriiCreditsRefreshing = true
    ToriiCreditsService.fetch(apiKey)
      .then((snapshot: ToriiCreditsSnapshot): Promise<void> => {
        if (this.toriiApiKeyDraft.trim() !== apiKey) {
          return Promise.resolve()
        }
        this.toriiCredits = snapshot
        return ToriiCreditsService.saveCached(this.ctx(), apiKey, snapshot)
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn(
          'comic-translation',
          'torii_credits_background_failed',
          error.message,
        )
      })
      .finally(() => {
        this.toriiCreditsRefreshing = false
      })
  }

  private toriiCreditsText(): string {
    if (this.toriiCredits === null) {
      return ''
    }
    return this.toriiCredits.credits.toFixed(2).replace(/\.00$/, '')
  }

  private toriiProviderText(provider: string = this.toriiByokProvider): string {
    if (provider === TORII_BYOK_OPENROUTER) {
      return 'OpenRouter'
    }
    if (provider === TORII_BYOK_OPENAI) {
      return 'OpenAI'
    }
    if (provider === TORII_BYOK_GOOGLE) {
      return 'Google Gemini'
    }
    if (provider === TORII_BYOK_ANTHROPIC) {
      return 'Anthropic'
    }
    if (provider === TORII_BYOK_DEEPSEEK) {
      return 'DeepSeek'
    }
    if (provider === TORII_BYOK_XAI) {
      return 'xAI'
    }
    return provider
  }

  private compatibleSources(): LlmSourceProfile[] {
    const profiles: LlmSourceProfile[] = []
    for (let index: number = 0; index < this.llmSources.profiles.length; index++) {
      const profile: LlmSourceProfile = this.llmSources.profiles[index]
      if (profile.capabilities.responses && profile.capabilities.imageInput) {
        profiles.push(profile)
      }
    }
    return profiles
  }

  private restoreBinding(): void {
    const binding: LlmConsumerBinding = this.llmSources.mangaBinding
    const profile: LlmSourceProfile | null = this.llmSources.findById(binding.sourceProfileId)
    if (profile === null || !profile.capabilities.responses ||
      !profile.capabilities.imageInput || !binding.configured()) {
      this.selectedSourceId = ''
      this.selectedModelId = ''
      return
    }
    this.selectedSourceId = binding.sourceProfileId
    this.selectedModelId = binding.modelId
  }

  private selectedSourceText(): ResourceStr {
    const profile: LlmSourceProfile | null = this.llmSources.findById(this.selectedSourceId)
    return profile === null
      ? $r('app.string.llm_binding_not_configured')
      : profile.displayName
  }

  private selectedModelText(): ResourceStr {
    if (this.fetchingModels) {
      return $r('app.string.comment_translation_fetch_models_loading')
    }
    return this.selectedModelId.length > 0
      ? this.selectedModelId
      : $r('app.string.llm_binding_not_configured')
  }

  private openSourceSelector(): void {
    if (this.compatibleSources().length === 0) {
      this.stack.pushPathByName('LlmSourceManager', null)
      return
    }
    this.sourceMenuShown = true
  }

  private selectSource(sourceProfileId: string): void {
    this.sourceMenuShown = false
    if (sourceProfileId === this.selectedSourceId) {
      return
    }
    this.selectedSourceId = sourceProfileId
    this.selectedModelId = ''
    this.modelOptions = []
    this.liveEvaluationReport = null
    // Publish source and model together only after the user picks a model.
    this.fetchModels()
  }

  private fetchModels(): void {
    if (this.fetchingModels || this.selectedSourceId.length === 0) {
      return
    }
    this.fetchingModels = true
    ComicTranslationModelCatalogService.fetchSource(this.ctx(), this.selectedSourceId)
      .then((models: string[]) => {
        this.modelOptions = models
        if (models.length === 0) {
          this.toast($r('app.string.comment_translation_models_empty'))
          return
        }
        this.modelMenuShown = true
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('comic-translation', 'model_catalog_failed', error.message)
        this.toast($r('app.string.comment_translation_models_failed', error.message))
      })
      .finally(() => {
        this.fetchingModels = false
      })
  }

  private selectModel(modelId: string): void {
    const binding: LlmConsumerBinding = new LlmConsumerBinding()
    binding.consumerId = LLM_CONSUMER_MANGA_TRANSLATION
    binding.sourceProfileId = this.selectedSourceId
    binding.modelId = modelId
    LlmSourceProfileRepository.saveBinding(this.ctx(), binding)
      .then(() => {
        this.selectedModelId = modelId
        this.modelMenuShown = false
        this.liveEvaluationReport = null
      })
      .catch((error: Error) => {
        this.toast($r('app.string.llm_binding_save_failed', error.message))
      })
  }

  private liveEvaluationAvailable(): boolean {
    return this.llmSources.mangaBinding.configured() &&
      this.llmSources.findById(this.llmSources.mangaBinding.sourceProfileId) !== null
  }

  private liveEvaluationSubtitle(): ResourceStr {
    if (this.liveEvaluationRunning) {
      return $r('app.string.comic_translation_live_evaluation_running')
    }
    if (this.liveEvaluationReport === null) {
      return $r('app.string.comic_translation_live_evaluation_hint')
    }
    const report: ComicTranslationLiveEvaluationReport = this.liveEvaluationReport
    const pageText: string = `${report.completedPages()}/2`
    if (report.errorCode.length > 0) {
      return AppStrings.get('comic_translation_live_evaluation_failed')
        .replace('%s', report.errorCode)
        .replace('%s', pageText)
    }
    return AppStrings.get('comic_translation_live_evaluation_result')
      .replace('%s', pageText)
      .replace('%s', `${report.matchedBlocks()}/${report.expectedBlocks()}`)
      .replace('%s', this.liveEvaluationBytes(report.totalImageBytes))
      .replace('%s', this.liveEvaluationElapsed(report.elapsedMs()))
  }

  private liveEvaluationTrailingText(): ResourceStr {
    if (this.liveEvaluationReport === null || this.liveEvaluationRunning) {
      return ''
    }
    return this.liveEvaluationReport.passed()
      ? $r('app.string.comic_translation_live_evaluation_passed')
      : $r('app.string.comic_translation_live_evaluation_not_passed')
  }

  private liveEvaluationBytes(bytes: number): string {
    if (bytes >= 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    }
    return `${Math.max(0, Math.round(bytes / 1024))} KB`
  }

  private liveEvaluationElapsed(elapsedMs: number): string {
    if (elapsedMs >= 1000) {
      return `${(elapsedMs / 1000).toFixed(1)} s`
    }
    return `${Math.max(0, elapsedMs)} ms`
  }

  private confirmLiveEvaluation(): void {
    if (!this.liveEvaluationAvailable() || this.liveEvaluationRunning) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.comic_translation_live_evaluation_title'),
      message: $r('app.string.comic_translation_live_evaluation_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.comic_translation_live_evaluation_start'),
        action: () => {
          this.runLiveEvaluation()
        },
      },
    })
  }

  private async runLiveEvaluation(): Promise<void> {
    if (!this.liveEvaluationAvailable() || this.liveEvaluationRunning) {
      return
    }
    this.liveEvaluationRunning = true
    try {
      const report: ComicTranslationLiveEvaluationReport =
        await ComicTranslationLiveEvaluationService.run(this.ctx())
      this.liveEvaluationReport = report
      this.toast(report.passed()
        ? $r('app.string.comic_translation_live_evaluation_passed')
        : $r('app.string.comic_translation_live_evaluation_not_passed'))
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'live_evaluation_failed', (error as Error).message)
      this.toast($r('app.string.comic_translation_live_evaluation_not_passed'))
    } finally {
      this.liveEvaluationRunning = false
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private VisualRouteMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.comic_visual_route_local'),
        symbolEndIcon: this.visualRoute === COMIC_VISUAL_ROUTE_LOCAL
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.selectVisualRoute(COMIC_VISUAL_ROUTE_LOCAL)
      })
      MenuItem({
        content: $r('app.string.comic_visual_route_torii'),
        symbolEndIcon: this.visualRoute === COMIC_VISUAL_ROUTE_TORII
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.selectVisualRoute(COMIC_VISUAL_ROUTE_TORII)
      })
    }
  }

  @Builder
  private ToriiModelMenu() {
    Menu() {
      ForEach(
        this.toriiModels(),
        (model: ToriiTranslatorModel) => {
          MenuItem({
            content: `${model.displayName} · ${model.baseCredits}+`,
            symbolEndIcon: this.toriiModelId === model.modelId
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
          }).onClick(() => {
            this.selectToriiModel(model.modelId)
          })
        },
        (model: ToriiTranslatorModel) => model.modelId,
      )
    }
  }

  @Builder
  private ToriiBillingMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.comic_torii_billing_managed'),
        symbolEndIcon: this.toriiBillingMode === TORII_BILLING_MANAGED
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.selectToriiBilling(TORII_BILLING_MANAGED)
      })
      MenuItem({
        content: $r('app.string.comic_torii_billing_byok'),
        symbolEndIcon: this.toriiBillingMode === TORII_BILLING_BYOK
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.selectToriiBilling(TORII_BILLING_BYOK)
      })
    }
  }

  @Builder
  private ToriiProviderMenu() {
    Menu() {
      ForEach(
        ToriiTranslatorModelCatalog.byokProviders(),
        (provider: string) => {
          MenuItem({
            content: this.toriiProviderText(provider),
            symbolEndIcon: this.toriiByokProvider === provider
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
          }).onClick(() => {
            this.selectToriiProvider(provider)
          })
        },
        (provider: string) => provider,
      )
    }
  }

  @Builder
  private ToriiSecretInput(field: string, placeholder: ResourceStr) {
    if (field === 'torii') {
      TextInput({ text: $$this.toriiApiKeyDraft, placeholder: placeholder })
        .type(InputType.Password)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange(() => {
          this.toriiCredits = null
        })
    } else {
      TextInput({ text: $$this.toriiByokApiKeyDraft, placeholder: placeholder })
        .type(InputType.Password)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    }
  }

  @Builder
  private ToriiSecretRow(
    label: ResourceStr,
    field: string,
    placeholder: ResourceStr,
  ) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      this.ToriiSecretInput(field, placeholder)
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
  }

  @Builder
  private SourceMenu() {
    Menu() {
      ForEach(
        this.compatibleSources(),
        (profile: LlmSourceProfile) => {
          MenuItem({
            content: profile.displayName,
            symbolEndIcon: this.selectedSourceId === profile.sourceProfileId
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
          }).onClick(() => {
            this.selectSource(profile.sourceProfileId)
          })
        },
        (profile: LlmSourceProfile) => profile.sourceProfileId,
      )
    }
  }

  @Builder
  private ModelMenu() {
    Menu() {
      ForEach(
        this.modelOptions,
        (model: string) => {
          MenuItem({
            content: model,
            symbolEndIcon: this.selectedModelId === model
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
          }).onClick(() => {
            this.selectModel(model)
          })
        },
        (model: string) => model,
      )
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            Column() {
              ConciseListRow({
                title: $r('app.string.comic_visual_route'),
                leadingIcon: $r('sys.symbol.picture'),
                trailingText: this.visualRouteText(),
                trailingDropdown: true,
                action: () => {
                  this.visualRouteMenuShown = true
                },
              })
            }
            .bindMenu(this.visualRouteMenuShown, this.VisualRouteMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.visualRouteMenuShown = false
              },
            })
          }
        }
        if (this.visualRoute === COMIC_VISUAL_ROUTE_LOCAL) {
          ListItem() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.llm_binding_source'),
                  leadingIcon: $r('sys.symbol.cloud'),
                  trailingText: this.selectedSourceText(),
                  trailingDropdown: this.compatibleSources().length > 0,
                  showChevron: this.compatibleSources().length === 0,
                  action: () => {
                    this.openSourceSelector()
                  },
                })
              }
              .bindMenu(this.sourceMenuShown, this.SourceMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.sourceMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.llm_binding_model'),
                  leadingIcon: $r('sys.symbol.arrow_down_circle'),
                  trailingText: this.selectedModelText(),
                  trailingDropdown: true,
                  isEnabled: this.selectedSourceId.length > 0 && !this.fetchingModels,
                  action: () => {
                    this.fetchModels()
                  },
                })
              }
              .bindMenu(this.modelMenuShown, this.ModelMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.modelMenuShown = false
                },
              })
            }
          }
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.comic_translation_live_evaluation_title'),
                subtitle: this.liveEvaluationSubtitle(),
                subtitleMaxLines: 2,
                leadingIcon: $r('sys.symbol.checkmark_circle'),
                trailingText: this.liveEvaluationTrailingText(),
                showChevron: false,
                isEnabled: this.liveEvaluationAvailable() && !this.liveEvaluationRunning,
                action: () => {
                  this.confirmLiveEvaluation()
                },
              })
            }
          }
        } else {
          ListItem() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.comic_torii_model'),
                  leadingIcon: $r('sys.symbol.translate'),
                  trailingText: this.toriiModelText(),
                  trailingDropdown: true,
                  action: () => {
                    this.toriiModelMenuShown = true
                  },
                })
              }
              .bindMenu(this.toriiModelMenuShown, this.ToriiModelMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.toriiModelMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.comic_torii_billing'),
                  leadingIcon: $r('sys.symbol.creditcard'),
                  trailingText: this.toriiBillingText(),
                  trailingDropdown: true,
                  action: () => {
                    this.toriiBillingMenuShown = true
                  },
                })
              }
              .bindMenu(this.toriiBillingMenuShown, this.ToriiBillingMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.toriiBillingMenuShown = false
                },
              })
              this.rowDivider()
              this.ToriiSecretRow(
                $r('app.string.comic_torii_api_key'),
                'torii',
                $r('app.string.comic_torii_api_key_hint'),
              )
              if (this.toriiCredits !== null) {
                this.rowDivider()
                ConciseListRow({
                  title: $r('app.string.comic_torii_available_credits'),
                  leadingIcon: $r('sys.symbol.creditcard'),
                  trailingText: this.toriiCreditsText(),
                  showChevron: false,
                })
              }
              if (this.toriiBillingMode === TORII_BILLING_BYOK) {
                this.rowDivider()
                Column() {
                  ConciseListRow({
                    title: $r('app.string.comic_torii_byok_provider'),
                    leadingIcon: $r('sys.symbol.key'),
                    trailingText: this.toriiProviderText(),
                    trailingDropdown: true,
                    action: () => {
                      this.toriiProviderMenuShown = true
                    },
                  })
                }
                .bindMenu(this.toriiProviderMenuShown, this.ToriiProviderMenu, {
                  placement: Placement.BottomRight,
                  onDisappear: () => {
                    this.toriiProviderMenuShown = false
                  },
                })
                this.rowDivider()
                this.ToriiSecretRow(
                  $r('app.string.comic_torii_byok_api_key'),
                  'byok',
                  $r('app.string.comic_torii_byok_api_key_hint'),
                )
              }
            }
          }
          ListItem() {
            Text(this.toriiNotice())
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
              })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('comic_translation_settings_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
