import { common, Want } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  CodexOAuthDeviceSession,
  CodexOAuthTokenSet,
  CodexUsageSnapshot,
  CodexUsageWindow,
  ComicTranslationCodexUsageService,
  ComicTranslationModelCatalogService,
  ConciseListRow,
  DiagnosticLogger,
  ExperimentalCodexOAuthService,
  GroupedListSection,
  LLM_CONSUMER_COMMENT_TRANSLATION,
  LLM_CONSUMER_MANGA_TRANSLATION,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmConsumerBinding,
  LlmSourceProfile,
  LlmSourceProfileRepository,
  LlmSourceProfilesState,
  LlmSourceSecretStore,
  SecondaryListScaffold,
  ThemeConstants,
  connectLlmSourceProfiles,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'
import { LlmSourceDetailRouteParams } from './LlmSourceManagerPage'

@ComponentV2
export struct LlmSourceDetailPage {
  @Local private sources: LlmSourceProfilesState = connectLlmSourceProfiles();
  @Local private sourceProfileId: string = '';
  @Local private sourceType: string = '';
  @Local private nameDraft: string = '';
  @Local private baseUrlDraft: string = '';
  @Local private apiKeyDraft: string = '';
  @Local private supportsComments: boolean = false;
  @Local private supportsManga: boolean = false;
  @Local private supportsCatalog: boolean = false;
  @Local private loaded: boolean = false;
  @Local private secretLoaded: boolean = false;
  @Local private modelCatalogLoading: boolean = false;
  @Local private modelCatalogCount: number = 0;
  @Local private codexConnected: boolean = false;
  @Local private codexAccountId: string = '';
  @Local private codexLoginBusy: boolean = false;
  @Local private codexUserCode: string = '';
  @Local private codexVerificationUrl: string = '';
  @Local private codexUsage: CodexUsageSnapshot | null = null;
  @Local private codexUsageRefreshing: boolean = false;
  @Local private deleting: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    if (!this.deleting) {
      this.persistDrafts(false)
    }
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private profile(): LlmSourceProfile | null {
    return this.sources.findById(this.sourceProfileId)
  }

  private async load(sourceProfileId: string): Promise<void> {
    const profile: LlmSourceProfile | null = this.sources.findById(sourceProfileId)
    if (profile === null) {
      this.toast($r('app.string.llm_source_missing'))
      this.stack.pop()
      return
    }
    this.sourceProfileId = sourceProfileId
    this.sourceType = profile.sourceType
    this.nameDraft = profile.displayName
    this.baseUrlDraft = profile.baseUrl
    this.supportsComments = profile.capabilities.chatCompletions
    this.supportsManga = profile.capabilities.responses && profile.capabilities.imageInput
    this.supportsCatalog = profile.capabilities.modelCatalog
    this.loaded = true
    if (profile.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
      this.apiKeyDraft = await LlmSourceSecretStore.readApiKey(this.ctx(), sourceProfileId)
      this.secretLoaded = true
      return
    }
    this.secretLoaded = true
    const tokens: CodexOAuthTokenSet | null = await LlmSourceSecretStore.readCodexTokens(
      this.ctx(),
      sourceProfileId,
    )
    if (this.sourceProfileId !== sourceProfileId) {
      return
    }
    this.codexConnected = tokens !== null
    this.codexAccountId = tokens?.accountId ?? ''
    if (tokens !== null && tokens.accountId.length > 0) {
      const cached: CodexUsageSnapshot | null = await ComicTranslationCodexUsageService.cachedSource(
        this.ctx(),
        sourceProfileId,
        tokens.accountId,
      )
      if (this.sourceProfileId === sourceProfileId && cached !== null) {
        this.codexUsage = cached
      }
      this.refreshCodexUsage()
    }
  }

  private async persistDrafts(showFailureToast: boolean = true): Promise<boolean> {
    const current: LlmSourceProfile | null = this.profile()
    if (!this.loaded || current === null) {
      return false
    }
    const candidate: LlmSourceProfile = current.copy()
    candidate.displayName = this.nameDraft.trim()
    if (candidate.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
      candidate.baseUrl = this.baseUrlDraft.trim().replace(/\/+$/, '')
      candidate.capabilities.chatCompletions = this.supportsComments
      candidate.capabilities.responses = this.supportsManga
      candidate.capabilities.imageInput = this.supportsManga
      candidate.capabilities.modelCatalog = this.supportsCatalog
      candidate.capabilities.usage = false
    } else {
      candidate.baseUrl = ''
      candidate.capabilities.chatCompletions = false
      candidate.capabilities.responses = true
      candidate.capabilities.imageInput = true
      candidate.capabilities.modelCatalog = true
      candidate.capabilities.usage = true
    }
    try {
      await LlmSourceProfileRepository.upsert(this.ctx(), candidate)
      if (candidate.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE && this.secretLoaded) {
        await LlmSourceSecretStore.saveApiKey(
          this.ctx(),
          candidate.sourceProfileId,
          this.apiKeyDraft,
        )
      }
      return true
    } catch (error) {
      DiagnosticLogger.warn('llm-source', 'profile_save_failed', (error as Error).message)
      if (showFailureToast) {
        this.toast($r('app.string.llm_source_save_failed', (error as Error).message))
      }
      return false
    }
  }

  private sourceTypeText(): ResourceStr {
    return this.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
      ? $r('app.string.llm_source_type_codex')
      : $r('app.string.llm_source_type_api')
  }

  private apiKeyStateText(): ResourceStr {
    return this.apiKeyDraft.trim().length > 0
      ? $r('app.string.comment_translation_api_key_saved')
      : $r('app.string.comment_translation_api_key_empty')
  }

  private catalogSubtitle(): ResourceStr {
    if (this.modelCatalogLoading) {
      return $r('app.string.comment_translation_fetch_models_loading')
    }
    if (this.modelCatalogCount > 0) {
      return $r('app.string.llm_source_catalog_count', this.modelCatalogCount)
    }
    return $r('app.string.llm_source_catalog_hint')
  }

  private async fetchModels(): Promise<void> {
    if (this.modelCatalogLoading || !await this.persistDrafts(true)) {
      return
    }
    this.modelCatalogLoading = true
    try {
      const models: string[] = await ComicTranslationModelCatalogService.fetchSource(
        this.ctx(),
        this.sourceProfileId,
      )
      this.modelCatalogCount = models.length
      this.toast(models.length > 0
        ? $r('app.string.llm_source_catalog_count', models.length)
        : $r('app.string.comment_translation_models_empty'))
    } catch (error) {
      DiagnosticLogger.warn('llm-source', 'model_catalog_failed', (error as Error).message)
      this.toast($r('app.string.comment_translation_models_failed', (error as Error).message))
    } finally {
      this.modelCatalogLoading = false
    }
  }

  private codexStatusSubtitle(): ResourceStr {
    if (this.codexLoginBusy && this.codexUserCode.length > 0) {
      return $r('app.string.comic_translation_codex_code', this.codexUserCode)
    }
    if (this.codexLoginBusy) {
      return $r('app.string.comic_translation_codex_requesting')
    }
    if (this.codexConnected) {
      return this.codexAccountId.length > 0
        ? this.codexAccountId
        : $r('app.string.comic_translation_codex_connected')
    }
    return $r('app.string.comic_translation_codex_login_hint')
  }

  private codexStatusTrailingText(): ResourceStr {
    if (this.codexConnected) {
      return $r('app.string.comic_translation_codex_connected')
    }
    if (this.codexLoginBusy && this.codexUserCode.length > 0) {
      return $r('app.string.llm_source_codex_copy_code')
    }
    return ''
  }

  private copyCodexUserCode(): void {
    if (this.codexUserCode.length === 0) {
      return
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.codexUserCode,
      )
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.toast($r('app.string.llm_source_codex_code_copied'))
    } catch (error) {
      DiagnosticLogger.warn('llm-source', 'codex_code_copy_failed', (error as Error).message)
      this.toast($r('app.string.llm_source_codex_code_copy_failed'))
    }
  }

  private handleCodexAccountAction(): void {
    if (this.codexConnected) {
      this.confirmCodexLogout()
      return
    }
    if (this.codexLoginBusy) {
      this.copyCodexUserCode()
      return
    }
    this.startCodexLogin()
  }

  private startCodexLogin(): void {
    if (this.codexLoginBusy) {
      return
    }
    this.persistDrafts(true).then((saved: boolean) => {
      if (!saved) {
        return
      }
      this.codexLoginBusy = true
      this.codexUserCode = ''
      this.codexVerificationUrl = ''
      ExperimentalCodexOAuthService.requestDeviceCode()
        .then((session: CodexOAuthDeviceSession): Promise<CodexOAuthTokenSet> => {
          this.codexUserCode = session.userCode
          this.codexVerificationUrl = session.verificationUrl
          this.openCodexLoginPage()
          return ExperimentalCodexOAuthService.completeSourceDeviceLogin(
            this.ctx(),
            this.sourceProfileId,
            session,
          )
        })
        .then(async (tokens: CodexOAuthTokenSet): Promise<void> => {
          this.codexConnected = true
          this.codexAccountId = tokens.accountId
          const profile: LlmSourceProfile | null = this.profile()
          if (profile !== null) {
            const candidate: LlmSourceProfile = profile.copy()
            candidate.accountIdentityHash = ExperimentalCodexOAuthService.accountIdentityHash(
              tokens.accountId,
            )
            await LlmSourceProfileRepository.upsert(this.ctx(), candidate)
          }
          this.toast($r('app.string.comic_translation_codex_login_success'))
          this.refreshCodexUsage()
        })
        .catch((error: Error) => {
          DiagnosticLogger.warn('llm-source', 'codex_login_failed', error.message)
          this.toast($r('app.string.comic_translation_codex_login_failed', error.message))
        })
        .finally(() => {
          this.codexLoginBusy = false
          this.codexUserCode = ''
          this.codexVerificationUrl = ''
        })
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
      DiagnosticLogger.warn('llm-source', 'codex_open_failed', error.message)
      this.toast($r('app.string.comic_translation_codex_open_failed'))
    })
  }

  private confirmCodexLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.comic_translation_codex_logout'),
      message: $r('app.string.llm_source_codex_logout_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.comic_translation_codex_logout'),
        action: () => {
          this.logoutCodex()
        },
      },
    })
  }

  private async logoutCodex(): Promise<void> {
    try {
      await LlmSourceSecretStore.clearCodexTokens(this.ctx(), this.sourceProfileId)
      await ComicTranslationCodexUsageService.clearCachedSource(this.ctx(), this.sourceProfileId)
      const profile: LlmSourceProfile | null = this.profile()
      if (profile !== null) {
        const candidate: LlmSourceProfile = profile.copy()
        candidate.accountIdentityHash = ''
        await LlmSourceProfileRepository.upsert(this.ctx(), candidate)
      }
      this.codexConnected = false
      this.codexAccountId = ''
      this.codexUsage = null
      this.toast($r('app.string.comic_translation_codex_logout_success'))
    } catch (error) {
      DiagnosticLogger.warn('llm-source', 'codex_logout_failed', (error as Error).message)
      this.toast($r('app.string.comic_translation_codex_logout_failed'))
    }
  }

  private refreshCodexUsage(): void {
    if (!this.codexConnected || this.codexAccountId.length === 0 || this.codexUsageRefreshing) {
      return
    }
    const sourceProfileId: string = this.sourceProfileId
    const accountId: string = this.codexAccountId
    this.codexUsageRefreshing = true
    ComicTranslationCodexUsageService.fetchSource(this.ctx(), sourceProfileId)
      .then((snapshot: CodexUsageSnapshot): Promise<void> => {
        if (this.sourceProfileId !== sourceProfileId || this.codexAccountId !== accountId) {
          return Promise.resolve()
        }
        this.codexUsage = snapshot
        return ComicTranslationCodexUsageService.saveCachedSource(
          this.ctx(),
          sourceProfileId,
          accountId,
          snapshot,
        )
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('llm-source', 'codex_usage_background_failed', error.message)
      })
      .finally(() => {
        this.codexUsageRefreshing = false
      })
  }

  private usageText(): string {
    if (this.codexUsage === null) {
      return ''
    }
    const windows: string[] = []
    if (this.codexUsage.fiveHour !== null) {
      windows.push(this.usageWindowText('5H', this.codexUsage.fiveHour))
    }
    if (this.codexUsage.weekly !== null) {
      windows.push(this.usageWindowText('7D', this.codexUsage.weekly))
    }
    return windows.join(' · ')
  }

  private usageWindowText(label: string, window: CodexUsageWindow): string {
    const remaining: number = Math.max(0, Math.min(100, Math.round(100 - window.usedPercent)))
    return `${label} ${remaining}%`
  }

  private referencedConsumers(): string[] {
    const bindings: LlmConsumerBinding[] = [
      this.sources.commentBinding,
      this.sources.mangaBinding,
    ]
    return LlmSourceProfileRepository.referencedConsumers(this.sourceProfileId, bindings)
  }

  private consumerNames(consumers: string[]): string {
    const names: string[] = []
    if (consumers.indexOf(LLM_CONSUMER_COMMENT_TRANSLATION) >= 0) {
      names.push(AppStrings.get('comment_translation_settings_title'))
    }
    if (consumers.indexOf(LLM_CONSUMER_MANGA_TRANSLATION) >= 0) {
      names.push(AppStrings.get('comic_translation_settings_title'))
    }
    return names.join('、')
  }

  private confirmDelete(): void {
    if (this.deleting) {
      return
    }
    const consumers: string[] = this.referencedConsumers()
    const message: ResourceStr = consumers.length > 0
      ? $r('app.string.llm_source_delete_referenced', this.consumerNames(consumers))
      : $r('app.string.llm_source_delete_confirm')
    this.getUIContext().showAlertDialog({
      title: $r('app.string.llm_source_delete'),
      message: message,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        action: () => {
          this.deleteSource()
        },
      },
    })
  }

  private deleteSource(): void {
    this.deleting = true
    LlmSourceProfileRepository.remove(this.ctx(), this.sourceProfileId)
      .then(() => {
        this.stack.pop()
      })
      .catch((error: Error) => {
        this.deleting = false
        this.toast($r('app.string.llm_source_delete_failed', error.message))
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
  private TextInputBox(textLink: string, placeholder: ResourceStr, secret: boolean) {
    if (textLink === 'name') {
      TextInput({ text: $$this.nameDraft, placeholder: placeholder })
        .type(InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    } else if (textLink === 'baseUrl') {
      TextInput({ text: $$this.baseUrlDraft, placeholder: placeholder })
        .type(InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    } else {
      TextInput({ text: $$this.apiKeyDraft, placeholder: placeholder })
        .type(secret ? InputType.Password : InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    }
  }

  @Builder
  private TextInputRow(label: ResourceStr, textLink: string, placeholder: ResourceStr, secret: boolean) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      this.TextInputBox(textLink, placeholder, secret)
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
        if (this.loaded) {
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.llm_source_type'),
                leadingIcon: this.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
                  ? $r('sys.symbol.person')
                  : $r('sys.symbol.cloud'),
                trailingText: this.sourceTypeText(),
                showChevron: false,
              })
              this.rowDivider()
              this.TextInputRow(
                $r('app.string.llm_source_name'),
                'name',
                $r('app.string.llm_source_name_hint'),
                false,
              )
              if (this.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
                this.rowDivider()
                this.TextInputRow(
                  $r('app.string.llm_source_base_url'),
                  'baseUrl',
                  'https://api.openai.com',
                  false,
                )
                this.rowDivider()
                this.TextInputRow(
                  $r('app.string.llm_source_api_key'),
                  'apiKey',
                  this.apiKeyStateText(),
                  true,
                )
              }
            }
          }
          if (this.sourceType === LLM_SOURCE_TYPE_OPENAI_COMPATIBLE) {
            ListItem() {
              GroupedListSection() {
                ConciseListRow({
                  title: $r('app.string.llm_source_support_comments'),
                  subtitle: $r('app.string.llm_source_support_comments_hint'),
                  leadingIcon: $r('sys.symbol.translate'),
                  hasSwitch: true,
                  checked: this.supportsComments,
                  switchAction: (value: boolean) => {
                    if (!value && !this.supportsManga) {
                      return
                    }
                    this.supportsComments = value
                  },
                })
                this.rowDivider()
                ConciseListRow({
                  title: $r('app.string.llm_source_support_manga'),
                  subtitle: $r('app.string.llm_source_support_manga_hint'),
                  leadingIcon: $r('sys.symbol.picture'),
                  hasSwitch: true,
                  checked: this.supportsManga,
                  switchAction: (value: boolean) => {
                    if (!value && !this.supportsComments) {
                      return
                    }
                    this.supportsManga = value
                  },
                })
                this.rowDivider()
                ConciseListRow({
                  title: $r('app.string.llm_source_support_catalog'),
                  subtitle: $r('app.string.llm_source_support_catalog_hint'),
                  leadingIcon: $r('sys.symbol.arrow_down_circle'),
                  hasSwitch: true,
                  checked: this.supportsCatalog,
                  switchAction: (value: boolean) => {
                    this.supportsCatalog = value
                  },
                })
              }
            }
          } else {
            ListItem() {
              Column({ space: ThemeConstants.SPACE_SM }) {
                GroupedListSection() {
                  ConciseListRow({
                    title: this.codexConnected
                      ? $r('app.string.llm_source_codex_account')
                      : $r('app.string.comic_translation_codex_login'),
                    subtitle: this.codexStatusSubtitle(),
                    leadingIcon: $r('sys.symbol.person'),
                    trailingText: this.codexStatusTrailingText(),
                    showChevron: false,
                    action: () => {
                      this.handleCodexAccountAction()
                    },
                  })
                  if (this.usageText().length > 0) {
                    this.rowDivider()
                    ConciseListRow({
                      title: $r('app.string.comic_translation_codex_usage'),
                      subtitle: this.usageText(),
                      leadingIcon: $r('sys.symbol.gauge_with_dots_needle_33percent'),
                      trailingText: this.codexUsage?.planType ?? '',
                      showChevron: false,
                    })
                  }
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
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.llm_source_catalog'),
                subtitle: this.catalogSubtitle(),
                leadingIcon: $r('sys.symbol.arrow_down_circle'),
                trailingText: this.modelCatalogCount > 0 ? `${this.modelCatalogCount}` : '',
                showChevron: true,
                isEnabled: !this.modelCatalogLoading && this.supportsCatalog &&
                  (this.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
                    ? this.codexConnected
                    : this.apiKeyDraft.trim().length > 0),
                action: () => {
                  this.fetchModels()
                },
              })
            }
          }
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.llm_source_delete'),
                subtitle: $r('app.string.llm_source_delete_hint'),
                leadingIcon: $r('sys.symbol.trash'),
                destructive: true,
                showChevron: false,
                isEnabled: !this.deleting,
                action: () => {
                  this.confirmDelete()
                },
              })
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('llm_source_detail_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const params: LlmSourceDetailRouteParams | null =
        context.pathInfo.param as LlmSourceDetailRouteParams | null
      if (params === null || params.sourceProfileId.length === 0) {
        this.toast($r('app.string.llm_source_missing'))
        this.stack.pop()
        return
      }
      this.load(params.sourceProfileId)
    })
  }
}
