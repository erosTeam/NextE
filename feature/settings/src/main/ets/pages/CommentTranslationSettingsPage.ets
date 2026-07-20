import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  COMMENT_TRANSLATION_DISPLAY_BILINGUAL,
  COMMENT_TRANSLATION_DISPLAY_REPLACE,
  CommentTranslationService,
  CommentTranslationSettings,
  CommentTranslationSettingsSnapshot,
  CommentTranslationSettingsState,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectCommentTranslationSettings,
  immersiveTitleBar,
} from 'shared'
@ComponentV2
export struct CommentTranslationSettingsPage {
  @Local settings: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local displayMenuShown: boolean = false;
  @Local modelMenuShown: boolean = false;
  @Local fetchingModels: boolean = false;
  @Local modelOptions: string[] = [];
  @Local apiUrlDraft: string = '';
  @Local apiKeyDraft: string = '';
  @Local modelDraft: string = '';
  @Local clearingCache: boolean = false;
  @Local validatingApi: boolean = false;
  @Local cacheCount: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.apiUrlDraft = this.settings.apiUrl
    this.apiKeyDraft = this.settings.apiKey
    this.modelDraft = this.settings.model
    this.refreshCacheCount()
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private snapshot(): CommentTranslationSettingsSnapshot {
    const snapshot = new CommentTranslationSettingsSnapshot()
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
    const snapshot = this.snapshot()
    snapshot.enabled = value
    this.save(snapshot)
  }

  private setAutoTranslate(value: boolean): void {
    const snapshot = this.snapshot()
    snapshot.autoTranslate = value
    this.save(snapshot)
  }

  private setUseGoogleOnly(value: boolean): void {
    const snapshot = this.snapshot()
    snapshot.useGoogleOnly = value
    this.save(snapshot)
  }

  private setDisplayMode(mode: string): void {
    const snapshot = this.snapshot()
    snapshot.displayMode = mode
    this.save(snapshot)
    this.displayMenuShown = false
  }

  private setApiUrl(value: string): void {
    this.apiUrlDraft = value
    const snapshot = this.snapshot()
    snapshot.apiUrl = value.trim()
    this.save(snapshot)
  }

  private setApiKey(value: string): void {
    this.apiKeyDraft = value
    const snapshot = this.snapshot()
    snapshot.apiKey = value.trim()
    this.save(snapshot)
  }

  private setModel(value: string): void {
    this.modelDraft = value
    const snapshot = this.snapshot()
    snapshot.model = value.trim()
    this.save(snapshot)
  }

  private displayModeText(): Resource {
    return this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
      ? $r('app.string.comment_translation_display_bilingual')
      : $r('app.string.comment_translation_display_replace')
  }

  private apiUrlText(): string {
    return this.settings.apiUrl.length > 0 ? this.settings.apiUrl : 'https://api.openai.com'
  }

  private modelText(): string {
    return this.settings.model.length > 0 ? this.settings.model : 'gpt-4o-mini'
  }

  private keyStateText(): Resource {
    return this.settings.apiKey.length > 0
      ? $r('app.string.comment_translation_api_key_saved')
      : $r('app.string.comment_translation_api_key_empty')
  }

  private refreshCacheCount(): void {
    CommentTranslationService.count(this.ctx()).then((count: number) => {
      this.cacheCount = count
    })
  }

  private confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.comment_translation_clear_cache_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_clear'),
        fontColor: Color.Red,
        action: () => {
          this.clearCache()
        },
      },
    })
  }

  private clearCache(): void {
    if (this.clearingCache) {
      return
    }
    this.clearingCache = true
    CommentTranslationService.clear(this.ctx())
      .then(() => {
        this.cacheCount = 0
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r('app.string.comment_translation_cache_cleared'),
          })
      })
      .finally(() => {
        this.clearingCache = false
      })
  }

  private validateApi(): void {
    if (this.validatingApi) {
      return
    }
    if (this.settings.apiKey.length === 0) {
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message: $r('app.string.comment_translation_validate_missing_key'),
        })
      return
    }
    this.validatingApi = true
    CommentTranslationService.validateConfiguredLlm()
      .then(() => {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r('app.string.comment_translation_validate_success'),
          })
      })
      .catch((error: Error) => {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r('app.string.comment_translation_validate_failed', error.message),
          })
      })
      .finally(() => {
        this.validatingApi = false
      })
  }

  private fetchModels(): void {
    if (this.fetchingModels) {
      return
    }
    if (this.settings.apiKey.length === 0) {
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message: $r('app.string.comment_translation_validate_missing_key'),
        })
      return
    }
    this.fetchingModels = true
    CommentTranslationService.fetchConfiguredLlmModels()
      .then((models: string[]) => {
        this.modelOptions = models
        if (models.length === 0) {
          this.getUIContext()
            .getPromptAction()
            .showToast({
              message: $r('app.string.comment_translation_models_empty'),
            })
          return
        }
        if (this.settings.model.length === 0 || models.length === 1) {
          this.setModel(models[0])
        }
        this.modelMenuShown = true
      })
      .catch((error: Error) => {
        this.getUIContext()
          .getPromptAction()
          .showToast({
            message: $r('app.string.comment_translation_models_failed', error.message),
          })
      })
      .finally(() => {
        this.fetchingModels = false
      })
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
        symbolEndIcon:
          this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_REPLACE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setDisplayMode(COMMENT_TRANSLATION_DISPLAY_REPLACE)
        })
      MenuItem({
        content: $r('app.string.comment_translation_display_bilingual'),
        symbolEndIcon:
          this.settings.displayMode === COMMENT_TRANSLATION_DISPLAY_BILINGUAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setDisplayMode(COMMENT_TRANSLATION_DISPLAY_BILINGUAL)
        })
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
            symbolEndIcon:
              this.modelText() === model
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.setModel(model)
            this.modelMenuShown = false
          })
        },
        (model: string) => model,
      )
    }
  }

  @Builder
  private TextInputField(
    field: string,
    placeholder: ResourceStr,
    secret: boolean,
    onChange: (value: string) => void,
  ) {
    if (field === 'apiUrl') {
      TextInput({ text: $$this.apiUrlDraft, placeholder: placeholder })
        .type(secret ? InputType.Password : InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange((next: string) => {
          onChange(next)
        })
    } else if (field === 'apiKey') {
      TextInput({ text: $$this.apiKeyDraft, placeholder: placeholder })
        .type(secret ? InputType.Password : InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange((next: string) => {
          onChange(next)
        })
    } else {
      TextInput({ text: $$this.modelDraft, placeholder: placeholder })
        .type(secret ? InputType.Password : InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange((next: string) => {
          onChange(next)
        })
    }
  }

  @Builder
  private TextFieldRow(
    label: ResourceStr,
    field: string,
    placeholder: ResourceStr,
    secret: boolean,
    onChange: (value: string) => void,
  ) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      this.TextInputField(field, placeholder, secret, onChange)
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
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
            this.TextFieldRow(
              $r('app.string.comment_translation_api_url'),
              'apiUrl',
              $r('app.string.comment_translation_api_url_hint'),
              false,
              (value: string) => {
                this.setApiUrl(value)
              },
            )
            this.rowDivider()
            this.TextFieldRow(
              $r('app.string.comment_translation_api_key'),
              'apiKey',
              this.keyStateText(),
              true,
              (value: string) => {
                this.setApiKey(value)
              },
            )
            this.rowDivider()
            this.TextFieldRow(
              $r('app.string.comment_translation_model'),
              'model',
              $r('app.string.comment_translation_model_hint'),
              false,
              (value: string) => {
                this.setModel(value)
              },
            )
            this.rowDivider()
            Column() {
              ConciseListRow({
                title: $r('app.string.comment_translation_fetch_models'),
                subtitle: this.fetchingModels
                  ? $r('app.string.comment_translation_fetch_models_loading')
                  : $r('app.string.comment_translation_fetch_models_hint'),
                leadingIcon: $r('sys.symbol.arrow_down_circle'),
                trailingText: this.modelOptions.length > 0 ? `${this.modelOptions.length}` : '',
                showChevron: true,
                isEnabled:
                  this.settings.enabled && !this.settings.useGoogleOnly && !this.fetchingModels,
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
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.comment_translation_effective_service'),
              subtitle: this.apiUrlText(),
              leadingIcon: $r('sys.symbol.externaldrive'),
              trailingText: this.modelText(),
              showChevron: false,
              isEnabled: this.settings.enabled && !this.settings.useGoogleOnly,
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.comment_translation_validate_api'),
              subtitle: this.settings.useGoogleOnly
                ? $r('app.string.comment_translation_validate_google_only_hint')
                : $r('app.string.comment_translation_validate_api_hint'),
              leadingIcon: $r('sys.symbol.checkmark'),
              showChevron: false,
              isEnabled:
                this.settings.enabled && !this.settings.useGoogleOnly && !this.validatingApi,
              action: () => {
                this.validateApi()
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
