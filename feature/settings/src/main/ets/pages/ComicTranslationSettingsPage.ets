import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
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
  ThemeConstants,
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
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  aboutToAppear(): void {
    this.restoreBinding()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
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
                title: $r('app.string.llm_binding_source'),
                subtitle: this.compatibleSources().length === 0
                  ? $r('app.string.llm_binding_no_compatible_source')
                  : $r('app.string.llm_binding_source_hint'),
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
                subtitle: this.fetchingModels
                  ? $r('app.string.comment_translation_fetch_models_loading')
                  : $r('app.string.llm_binding_model_hint'),
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
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('comic_translation_settings_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
