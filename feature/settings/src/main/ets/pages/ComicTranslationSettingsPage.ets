import { common, Want } from '@kit.AbilityKit'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH,
  COMIC_TRANSLATION_PROVIDER_OPENAI_API,
  CodexOAuthDeviceSession,
  CodexOAuthTokenSet,
  CodexUsageSnapshot,
  CodexUsageWindow,
  ComicTranslationCodexUsageService,
  ComicTranslationModelCatalogService,
  ComicTranslationProviderSettings,
  ComicTranslationProviderSettingsSnapshot,
  ComicTranslationProviderSettingsState,
  ConciseListRow,
  DiagnosticLogger,
  ExperimentalCodexOAuthService,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectComicTranslationProviderSettings,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct ComicTranslationSettingsPage {
  @Local private settings: ComicTranslationProviderSettingsState =
    connectComicTranslationProviderSettings();
  @Local private providerMenuShown: boolean = false;
  @Local private modelMenuShown: boolean = false;
  @Local private fetchingModels: boolean = false;
  @Local private modelOptions: string[] = [];
  @Local private codexUsageLoading: boolean = false;
  @Local private codexUsage: CodexUsageSnapshot | null = null;
  @Local private apiUrlDraft: string = '';
  @Local private apiKeyDraft: string = '';
  @Local private apiModelDraft: string = '';
  @Local private codexModelDraft: string = '';
  @Local private codexLoginBusy: boolean = false;
  @Local private codexUserCode: string = '';
  @Local private codexVerificationUrl: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.apiUrlDraft = this.settings.apiBaseUrl
    this.apiKeyDraft = this.settings.apiKey
    this.apiModelDraft = this.settings.apiModel
    this.codexModelDraft = this.settings.codexModel
    if (this.settings.codexConnected) {
      this.restoreCodexUsageAndRefresh()
    }
  }

  aboutToDisappear(): void {
    this.saveDrafts()
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private snapshot(): ComicTranslationProviderSettingsSnapshot {
    const snapshot: ComicTranslationProviderSettingsSnapshot =
      new ComicTranslationProviderSettingsSnapshot()
    snapshot.provider = this.settings.provider
    snapshot.apiBaseUrl = this.apiUrlDraft
    snapshot.apiKey = this.apiKeyDraft
    snapshot.apiModel = this.apiModelDraft
    snapshot.codexModel = this.codexModelDraft
    return snapshot
  }

  private saveDrafts(): void {
    ComicTranslationProviderSettings.save(this.ctx(), this.snapshot())
  }

  private selectProvider(provider: string): void {
    const snapshot: ComicTranslationProviderSettingsSnapshot = this.snapshot()
    snapshot.provider = provider
    ComicTranslationProviderSettings.save(this.ctx(), snapshot)
    this.providerMenuShown = false
    this.modelMenuShown = false
    this.modelOptions = []
  }

  private providerText(): ResourceStr {
    return this.settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      ? $r('app.string.comic_translation_provider_codex')
      : $r('app.string.comic_translation_provider_api')
  }

  private codexStatusText(): ResourceStr {
    if (this.codexLoginBusy && this.codexUserCode.length > 0) {
      return $r('app.string.comic_translation_codex_code', this.codexUserCode)
    }
    if (this.codexLoginBusy) {
      return $r('app.string.comic_translation_codex_requesting')
    }
    if (this.settings.codexConnected) {
      return this.settings.codexAccountId.length > 0
        ? $r('app.string.comic_translation_codex_connected_account', this.settings.codexAccountId)
        : $r('app.string.comic_translation_codex_connected')
    }
    return $r('app.string.comic_translation_codex_disconnected')
  }

  private apiKeyStateText(): ResourceStr {
    return this.settings.apiKey.length > 0
      ? $r('app.string.comment_translation_api_key_saved')
      : $r('app.string.comment_translation_api_key_empty')
  }

  private selectedModelText(): ResourceStr {
    const selected: string = this.settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
      ? this.codexModelDraft.trim()
      : this.apiModelDraft.trim()
    return selected.length > 0
      ? selected
      : $r('app.string.comic_translation_model_not_selected')
  }

  private selectModel(model: string): void {
    if (this.settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH) {
      this.codexModelDraft = model
    } else {
      this.apiModelDraft = model
    }
    this.saveDrafts()
    this.modelMenuShown = false
  }

  private fetchModels(): void {
    if (this.fetchingModels) {
      return
    }
    this.saveDrafts()
    this.fetchingModels = true
    ComicTranslationModelCatalogService.fetchConfigured(this.ctx())
      .then((models: string[]) => {
        this.modelOptions = models
        if (models.length === 0) {
          this.toast($r('app.string.comment_translation_models_empty'))
          return
        }
        const current: string = this.settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
          ? this.codexModelDraft.trim()
          : this.apiModelDraft.trim()
        if (current.length === 0) {
          this.selectModel(models[0])
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

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private restoreCodexUsageAndRefresh(): void {
    const accountId: string = this.settings.codexAccountId
    ComicTranslationCodexUsageService.cached(this.ctx(), accountId)
      .then((snapshot: CodexUsageSnapshot | null) => {
        if (!this.settings.codexConnected || this.settings.codexAccountId !== accountId) {
          return
        }
        if (snapshot !== null) {
          this.codexUsage = snapshot
        }
      })
      .finally(() => {
        if (this.settings.codexConnected && this.settings.codexAccountId === accountId) {
          this.fetchCodexUsage(false)
        }
      })
  }

  private fetchCodexUsage(showFailureToast: boolean = true): void {
    if (!this.settings.codexConnected || this.codexUsageLoading) {
      return
    }
    const accountId: string = this.settings.codexAccountId
    this.codexUsageLoading = true
    ComicTranslationCodexUsageService.fetch(this.ctx())
      .then((snapshot: CodexUsageSnapshot) => {
        if (!this.settings.codexConnected || this.settings.codexAccountId !== accountId) {
          return
        }
        this.codexUsage = snapshot
        ComicTranslationCodexUsageService.saveCached(this.ctx(), accountId, snapshot)
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('comic-translation', 'codex_usage_failed', error.message)
        if (showFailureToast) {
          this.toast($r('app.string.comic_translation_codex_usage_failed', error.message))
        }
      })
      .finally(() => {
        this.codexUsageLoading = false
      })
  }

  private usageSubtitle(): string {
    if (this.codexUsage === null) {
      return AppStrings.get(this.codexUsageLoading
        ? 'comic_translation_codex_usage_loading'
        : 'comic_translation_codex_usage_hint')
    }
    const windows: string[] = []
    if (this.codexUsage.fiveHour !== null) {
      windows.push(this.usageWindowSummary('5H', this.codexUsage.fiveHour))
    }
    if (this.codexUsage.weekly !== null) {
      windows.push(this.usageWindowSummary('7D', this.codexUsage.weekly))
    }
    return windows.join('\n')
  }

  private usageWindowSummary(label: string, window: CodexUsageWindow): string {
    return `${label}  ${this.usageRemainingPercent(window)} · ${this.usageResetText(window)}`
  }

  private usageRemainingPercent(window: CodexUsageWindow): string {
    const remainingPercent: number = Math.max(0, Math.min(100, Math.round(100 - window.usedPercent)))
    return `${remainingPercent}%`
  }

  private usagePlanText(): string {
    return this.codexUsage?.planType ?? ''
  }

  private usageResetText(window: CodexUsageWindow): string {
    if (window.resetsAtMs <= 0) {
      return AppStrings.get('comic_translation_codex_usage_reset_unknown')
    }
    const remainingMinutes: number = Math.max(
      0,
      Math.ceil((window.resetsAtMs - Date.now()) / 60000),
    )
    if (remainingMinutes <= 0) {
      return AppStrings.get('comic_translation_codex_usage_reset_due')
    }
    if (remainingMinutes < 60) {
      return AppStrings.get('comic_translation_codex_usage_reset_minutes')
        .replace('%d', `${remainingMinutes}`)
    }
    const remainingHours: number = Math.floor(remainingMinutes / 60)
    const minutes: number = remainingMinutes % 60
    if (remainingHours < 48) {
      return AppStrings.get('comic_translation_codex_usage_reset_hours_minutes')
        .replace('%d', `${remainingHours}`)
        .replace('%d', `${minutes}`)
    }
    const remainingDays: number = Math.floor(remainingHours / 24)
    const hours: number = remainingHours % 24
    return AppStrings.get('comic_translation_codex_usage_reset_days_hours')
      .replace('%d', `${remainingDays}`)
      .replace('%d', `${hours}`)
  }

  private startCodexLogin(): void {
    if (this.codexLoginBusy) {
      return
    }
    this.saveDrafts()
    this.codexLoginBusy = true
    this.codexUserCode = ''
    this.codexVerificationUrl = ''
    ExperimentalCodexOAuthService.requestDeviceCode()
      .then((session: CodexOAuthDeviceSession): Promise<CodexOAuthTokenSet> => {
        this.codexUserCode = session.userCode
        this.codexVerificationUrl = session.verificationUrl
        this.openCodexLoginPage()
        return ExperimentalCodexOAuthService.completeDeviceLogin(this.ctx(), session)
      })
      .then(() => {
        this.toast($r('app.string.comic_translation_codex_login_success'))
        this.fetchModels()
        this.fetchCodexUsage(false)
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('comic-translation', 'codex_oauth_login_failed', error.message)
        this.toast($r('app.string.comic_translation_codex_login_failed', error.message))
      })
      .finally(() => {
        this.codexLoginBusy = false
        this.codexUserCode = ''
        this.codexVerificationUrl = ''
      })
  }

  private openCodexLoginPage(): void {
    if (this.codexVerificationUrl.length === 0) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: this.codexVerificationUrl,
    }
    this.ctx().startAbility(want).catch((error: Error) => {
      DiagnosticLogger.warn('comic-translation', 'codex_oauth_open_browser_failed', error.message)
      this.toast($r('app.string.comic_translation_codex_open_failed'))
    })
  }

  private logoutCodex(): void {
    ComicTranslationProviderSettings.clearCodexTokens(this.ctx())
      .then(() => ComicTranslationCodexUsageService.clearCached(this.ctx()))
      .then(() => {
        this.codexUsage = null
        this.toast($r('app.string.comic_translation_codex_logout_success'))
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('comic-translation', 'codex_oauth_logout_failed', error.message)
        this.toast($r('app.string.comic_translation_codex_logout_failed'))
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
  private ProviderMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.comic_translation_provider_api'),
        symbolEndIcon:
          this.settings.provider === COMIC_TRANSLATION_PROVIDER_OPENAI_API
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.selectProvider(COMIC_TRANSLATION_PROVIDER_OPENAI_API)
      })
      MenuItem({
        content: $r('app.string.comic_translation_provider_codex'),
        symbolEndIcon:
          this.settings.provider === COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.selectProvider(COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH)
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
              this.selectedModelText() === model
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

  @Builder
  private TextInputRow(label: ResourceStr, placeholder: ResourceStr, secret: boolean, field: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (field === 'apiUrl') {
        TextInput({ text: $$this.apiUrlDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
      } else if (field === 'apiKey') {
        TextInput({ text: $$this.apiKeyDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
      } else if (field === 'apiModel') {
        TextInput({ text: $$this.apiModelDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
      } else {
        TextInput({ text: $$this.codexModelDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
      }
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
  private LoginProgressSuffix() {
    LoadingProgress()
      .width(22)
      .height(22)
      .color(ThemeConstants.BRAND_PRIMARY)
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
                title: $r('app.string.comic_translation_provider'),
                subtitle: $r('app.string.comic_translation_provider_hint'),
                leadingIcon: $r('sys.symbol.cloud'),
                trailingText: this.providerText(),
                trailingDropdown: true,
                action: () => {
                  this.providerMenuShown = true
                },
              })
            }
            .bindMenu(this.providerMenuShown, this.ProviderMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.providerMenuShown = false
              },
            })
          }
        }
        if (this.settings.provider === COMIC_TRANSLATION_PROVIDER_OPENAI_API) {
          ListItem() {
            GroupedListSection() {
              this.TextInputRow(
                $r('app.string.comic_translation_api_url'),
                'https://api.openai.com/v1',
                false,
                'apiUrl',
              )
              this.rowDivider()
              this.TextInputRow(
                $r('app.string.comic_translation_api_key'),
                this.apiKeyStateText(),
                true,
                'apiKey',
              )
              this.rowDivider()
              this.TextInputRow(
                $r('app.string.comic_translation_model'),
                'gpt-4o-mini',
                false,
                'apiModel',
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
                  isEnabled: this.apiKeyDraft.trim().length > 0 && !this.fetchingModels,
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
                title: $r('app.string.comic_translation_api_direct_title'),
                subtitle: $r('app.string.comic_translation_api_direct_hint'),
                leadingIcon: $r('sys.symbol.exclamationmark_circle'),
                showChevron: false,
              })
            }
          }
        } else {
          ListItem() {
            Column({ space: ThemeConstants.SPACE_SM }) {
              GroupedListSection() {
                ConciseListRow({
                  title: $r('app.string.comic_translation_codex_status'),
                  subtitle: this.codexStatusText(),
                  leadingIcon: $r('sys.symbol.person'),
                  showChevron: false,
                })
                this.rowDivider()
                if (this.codexLoginBusy) {
                  ConciseListRow({
                    title: $r('app.string.comic_translation_codex_waiting'),
                    subtitle: this.codexStatusText(),
                    leadingIcon: $r('sys.symbol.key'),
                    showChevron: false,
                    isEnabled: false,
                    suffixBuilderParam: () => {
                      this.LoginProgressSuffix()
                    },
                  })
                  if (this.codexVerificationUrl.length > 0) {
                    this.rowDivider()
                    ConciseListRow({
                      title: $r('app.string.comic_translation_codex_open_page'),
                      subtitle: this.codexVerificationUrl,
                      leadingIcon: $r('sys.symbol.externaldrive'),
                      showChevron: false,
                      action: () => {
                        this.openCodexLoginPage()
                      },
                    })
                  }
                } else if (this.settings.codexConnected) {
                  ConciseListRow({
                    title: $r('app.string.comic_translation_codex_logout'),
                    leadingIcon: $r('sys.symbol.trash'),
                    showChevron: false,
                    destructive: true,
                    action: () => {
                      this.logoutCodex()
                    },
                  })
                } else {
                  ConciseListRow({
                    title: $r('app.string.comic_translation_codex_login'),
                    subtitle: $r('app.string.comic_translation_codex_login_hint'),
                    leadingIcon: $r('sys.symbol.key'),
                    showChevron: false,
                    action: () => {
                      this.startCodexLogin()
                    },
                  })
                }
                this.rowDivider()
                Column() {
                  ConciseListRow({
                    title: $r('app.string.comic_translation_codex_model'),
                    subtitle: this.fetchingModels
                      ? $r('app.string.comment_translation_fetch_models_loading')
                      : $r('app.string.comic_translation_codex_model_hint'),
                    leadingIcon: $r('sys.symbol.arrow_down_circle'),
                    trailingText: this.selectedModelText(),
                    trailingDropdown: true,
                    isEnabled: this.settings.codexConnected && !this.fetchingModels,
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
                  title: $r('app.string.comic_translation_codex_usage'),
                  subtitle: this.usageSubtitle(),
                  subtitleMaxLines: 2,
                  leadingIcon: $r('sys.symbol.gauge_with_dots_needle_33percent'),
                  trailingText: this.usagePlanText(),
                  showChevron: false,
                  isEnabled: this.settings.codexConnected,
                  action: () => {
                    this.fetchCodexUsage()
                  },
                })
              }
              Text($r('app.string.comic_translation_codex_experimental_hint'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding({
                  left: ThemeConstants.SPACE_MD,
                  right: ThemeConstants.SPACE_MD,
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('comic_translation_settings_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
