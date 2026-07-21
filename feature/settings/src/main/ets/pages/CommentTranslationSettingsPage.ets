import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  COMMENT_TRANSLATION_DISPLAY_REPLACE,
  CommentTranslationService,
  CommentTranslationSettings,
  CommentTranslationSettingsSnapshot,
  CommentTranslationSettingsState,
  ComicTranslationModelCatalogService,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceProfileRepository,
  LlmSourceProfilesState,
  SecondaryListScaffold,
  ThemeConstants,
  connectCommentTranslationSettings,
  connectLlmSourceProfiles,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct CommentTranslationSettingsPage {
  @Local private settings: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local private llmSources: LlmSourceProfilesState = connectLlmSourceProfiles();
  @Local private displayMenuShown: boolean = false;
  @Local private sourceMenuShown: boolean = false;
  @Local private modelMenuShown: boolean = false;
  @Local private fetchingModels: boolean = false;
  @Local private modelOptions: string[] = [];
  @Local private selectedSourceId: string = '';
  @Local private selectedModelId: string = '';
  @Local private cacheCount: number = 0;
  @Local private clearingCache: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  aboutToAppear(): void {
    this.restoreBinding()
    this.refreshCacheCount()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private snapshot(): CommentTranslationSettingsSnapshot {
    const snapshot: CommentTranslationSettingsSnapshot = new CommentTranslationSettingsSnapshot()
    snapshot.enabled = this.settings.enabled
    snapshot.autoTranslate = this.settings.autoTranslate
    snapshot.displayMode = this.settings.displayMode
    snapshot.useGoogleOnly = this.settings.useGoogleOnly
    snapshot.apiUrl = this.settings.apiUrl
    snapshot.apiKey = this.settings.apiKey
    snapshot.model = this.settings.model
    return snapshot
  }

  private save(snapshot: CommentTranslationSettingsSnapshot): void {
    CommentTranslationSettings.save(this.ctx(), snapshot)
  }

  private setEnabled(value: boolean): void {
    const snapshot: CommentTranslationSettingsSnapshot = this.snapshot()
    snapshot.enabled = value
    this.save(snapshot)
  }

  private setAutoTranslate(value: boolean): void {
    const snapshot: CommentTranslationSettingsSnapshot = this.snapshot()
    snapshot.autoTranslate = value
    this.save(snapshot)
  }

  private setUseGoogleOnly(value: boolean): void {
    const snapshot: CommentTranslationSettingsSnapshot = this.snapshot()
    snapshot.useGoogleOnly = value
    this.save(snapshot)
  }

  private setDisplayMode(value: string): void {
    const snapshot: CommentTranslationSettingsSnapshot = this.snapshot()
    snapshot.displayMode = value
    this.save(snapshot)
    this.displayMenuShown = false
  }

  private displayModeText(): ResourceStr {
    return this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
      ? $r('app.string.comment_translation_display_bilingual')
      : $r('app.string.comment_translation_display_replace')
  }

  private compatibleSources(): LlmSourceProfile[] {
    const profiles: LlmSourceProfile[] = []
    for (let index: number = 0; index < this.llmSources.profiles.length; index++) {
      const profile: LlmSourceProfile = this.llmSources.profiles[index]
      if (profile.capabilities.chatCompletions) {
        profiles.push(profile)
      }
    }
    return profiles
  }

  private restoreBinding(): void {
    const binding: LlmConsumerBinding = this.llmSources.commentBinding
    const profile: LlmSourceProfile | null = this.llmSources.findById(binding.sourceProfileId)
    if (profile === null || !profile.capabilities.chatCompletions || !binding.configured()) {
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
        DiagnosticLogger.warn('comment-translation', 'model_catalog_failed', error.message)
        this.toast($r('app.string.comment_translation_models_failed', error.message))
      })
      .finally(() => {
        this.fetchingModels = false
      })
  }

  private selectModel(modelId: string): void {
    const binding: LlmConsumerBinding = new LlmConsumerBinding()
    binding.consumerId = LLM_CONSUMER_COMMENT_TRANSLATION
    binding.sourceProfileId = this.selectedSourceId
    binding.modelId = modelId
    LlmSourceProfileRepository.saveBinding(this.ctx(), binding)
      .then(() => {
        this.selectedModelId = modelId
        this.modelMenuShown = false
      })
      .catch((error: Error) => {
        this.toast($r('app.string.llm_binding_save_failed', error.message))
      })
  }

  private refreshCacheCount(): void {
    CommentTranslationService.count(this.ctx())
      .then((count: number) => {
        this.cacheCount = count
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('comment-translation', 'cache_count_failed', error.message)
      })
  }

  private confirmClearCache(): void {
    if (this.clearingCache) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.comment_translation_clear_cache'),
      message: $r('app.string.comment_translation_clear_cache_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        action: () => {
          this.clearCache()
        },
      },
    })
  }

  private clearCache(): void {
    this.clearingCache = true
    CommentTranslationService.clear(this.ctx())
      .then(() => {
        this.cacheCount = 0
        this.toast($r('app.string.comment_translation_cache_cleared'))
      })
      .finally(() => {
        this.clearingCache = false
      })
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
  private DisplayModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.comment_translation_display_replace'),
        symbolEndIcon: this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_REPLACE
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setDisplayMode(COMMENT_TRANSLATION_DISPLAY_REPLACE)
      })
      MenuItem({
        content: $r('app.string.comment_translation_display_bilingual'),
        symbolEndIcon: this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setDisplayMode(COMMENT_TRANSLATION_DISPLAY_BILINGUAL)
      })
    }
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
            ConciseListRow({
              title: $r('app.string.comment_translation_enable'),
              subtitle: $r('app.string.comment_translation_enable_hint'),
              leadingIcon: $r('sys.symbol.translate'),
              hasSwitch: true,
              checked: this.settings.enabled,
              switchAction: (value: boolean) => {
                this.setEnabled(value)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.comment_translation_auto'),
              subtitle: $r('app.string.comment_translation_auto_hint'),
              leadingIcon: $r('sys.symbol.clock'),
              hasSwitch: true,
              checked: this.settings.autoTranslate,
              isEnabled: this.settings.enabled,
              switchAction: (value: boolean) => {
                this.setAutoTranslate(value)
              },
            })
            this.rowDivider()
            Column() {
              ConciseListRow({
                title: $r('app.string.comment_translation_display_mode'),
                leadingIcon: $r('sys.symbol.textformat'),
                trailingText: this.displayModeText(),
                trailingDropdown: true,
                isEnabled: this.settings.enabled,
                action: () => {
                  this.displayMenuShown = true
                },
              })
            }
            .bindMenu(this.displayMenuShown, this.DisplayModeMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.displayMenuShown = false
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.comment_translation_google_only'),
              subtitle: $r('app.string.comment_translation_google_only_hint'),
              leadingIcon: $r('sys.symbol.cloud'),
              hasSwitch: true,
              checked: this.settings.useGoogleOnly,
              isEnabled: this.settings.enabled,
              switchAction: (value: boolean) => {
                this.setUseGoogleOnly(value)
              },
            })
            this.rowDivider()
            Column() {
              ConciseListRow({
                title: $r('app.string.llm_binding_source'),
                subtitle: this.compatibleSources().length === 0
                  ? $r('app.string.llm_binding_no_compatible_source')
                  : $r('app.string.llm_binding_source_hint'),
                leadingIcon: $r('sys.symbol.externaldrive'),
                trailingText: this.selectedSourceText(),
                trailingDropdown: this.compatibleSources().length > 0,
                showChevron: this.compatibleSources().length === 0,
                isEnabled: this.settings.enabled && !this.settings.useGoogleOnly,
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
                isEnabled: this.settings.enabled && !this.settings.useGoogleOnly &&
                  this.selectedSourceId.length > 0 && !this.fetchingModels,
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
              title: $r('app.string.comment_translation_clear_cache'),
              subtitle: $r('app.string.comment_translation_cache_entries', this.cacheCount),
              leadingIcon: $r('sys.symbol.trash'),
              destructive: true,
              showChevron: false,
              isEnabled: !this.clearingCache,
              action: () => {
                this.confirmClearCache()
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('comment_translation_settings_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
