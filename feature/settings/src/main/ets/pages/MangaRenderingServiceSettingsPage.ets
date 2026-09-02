import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  MANGA_TRANSLATOR_UI_DETECTION_BALANCED,
  MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL,
  MANGA_TRANSLATOR_UI_INPAINTER_FAST,
  MANGA_TRANSLATOR_UI_INPAINTER_QUALITY,
  MANGA_TRANSLATOR_UI_UPSTREAM_TAG,
  MangaRenderingServiceCredential,
  MangaRenderingServiceSecretStore,
  MangaRenderingServiceSettings,
  MangaRenderingServiceSettingsSnapshot,
  MangaTranslatorUiSidecarConfig,
  MangaTranslatorUiSidecarConnectionResult,
  MangaTranslatorUiSidecarConnectionService,
  MangaTranslatorUiSidecarSessionService,
  SecondaryListScaffold,
  SettingsTextField,
  SettingsCheckedMenuItem,
  ThemeConstants,
  ListRowDivider,
  immersiveTitleBar,
} from 'shared'

const CONNECTION_IDLE: string = 'idle'
const CONNECTION_RUNNING: string = 'running'
const CONNECTION_OK: string = 'ok'
const CONNECTION_FAILED: string = 'failed'

@ComponentV2
export struct MangaRenderingServiceSettingsPage {
  @Local private baseUrlDraft: string = '';
  @Local private usernameDraft: string = '';
  @Local private passwordDraft: string = '';
  @Local private credentialDirty: boolean = false;
  @Local private legacyCredentialPresent: boolean = false;
  @Local private loaded: boolean = false;
  @Local private connectionState: string = CONNECTION_IDLE;
  @Local private connectionFailure: string = '';
  @Local private detectionProfile: string = MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL;
  @Local private inpaintingProfile: string = MANGA_TRANSLATOR_UI_INPAINTER_QUALITY;
  private scroller: Scroller = new Scroller();
  private loadedCredential: MangaRenderingServiceCredential =
    new MangaRenderingServiceCredential();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.load()
  }

  aboutToDisappear(): void {
    if (this.loaded) {
      this.persist(false)
    }
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private async load(): Promise<void> {
    try {
      const snapshot: MangaRenderingServiceSettingsSnapshot =
        await MangaRenderingServiceSettings.load(this.ctx())
      const credential: MangaRenderingServiceCredential =
        await MangaRenderingServiceSecretStore.read(this.ctx())
      this.baseUrlDraft = snapshot.baseUrl
      this.detectionProfile = snapshot.detectionProfile
      this.inpaintingProfile = snapshot.inpaintingProfile
      this.loadedCredential = credential.copy()
      this.usernameDraft = credential.username
      this.passwordDraft = credential.password
      this.legacyCredentialPresent = credential.hasLegacySession()
      this.credentialDirty = false
      this.loaded = true
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'render_service_load_failed', (error as Error).message)
      this.toast($r('app.string.comic_render_service_save_failed', (error as Error).message))
    }
  }

  private async persist(showFailureToast: boolean = true): Promise<boolean> {
    const snapshot: MangaRenderingServiceSettingsSnapshot =
      new MangaRenderingServiceSettingsSnapshot()
    snapshot.baseUrl = this.baseUrlDraft
    snapshot.detectionProfile = this.detectionProfile
    snapshot.inpaintingProfile = this.inpaintingProfile
    try {
      const credential: MangaRenderingServiceCredential | null = this.credentialDirty
        ? this.draftCredential()
        : null
      await MangaRenderingServiceSettings.save(this.ctx(), snapshot)
      if (credential !== null) {
        await MangaRenderingServiceSecretStore.save(this.ctx(), credential)
        this.loadedCredential = credential.copy()
        this.legacyCredentialPresent = credential.hasLegacySession()
        this.credentialDirty = false
        MangaTranslatorUiSidecarSessionService.clearCachedSessions()
      }
      const stored: MangaRenderingServiceSettingsSnapshot =
        await MangaRenderingServiceSettings.load(this.ctx())
      this.baseUrlDraft = stored.baseUrl
      this.detectionProfile = stored.detectionProfile
      this.inpaintingProfile = stored.inpaintingProfile
      return true
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'render_service_save_failed', (error as Error).message)
      if (showFailureToast) {
        this.toast($r('app.string.comic_render_service_save_failed', (error as Error).message))
      }
      return false
    }
  }

  private draftCredential(): MangaRenderingServiceCredential {
    if (this.usernameDraft.length === 0 && this.passwordDraft.length === 0) {
      return new MangaRenderingServiceCredential()
    }
    return MangaRenderingServiceCredential.account(this.usernameDraft, this.passwordDraft)
  }

  private effectiveCredential(): MangaRenderingServiceCredential {
    return this.credentialDirty ? this.draftCredential() : this.loadedCredential.copy()
  }

  private passwordPlaceholder(): ResourceStr {
    if (this.legacyCredentialPresent && !this.credentialDirty) {
      return $r('app.string.comic_render_service_legacy_credential_hint')
    }
    return $r('app.string.comic_render_service_password_hint')
  }

  private connectionSubtitle(): ResourceStr {
    if (this.connectionState === CONNECTION_RUNNING) {
      return $r('app.string.comic_render_service_check_running')
    }
    if (this.connectionState === CONNECTION_OK) {
      return $r('app.string.comic_render_service_check_success')
    }
    if (this.connectionState === CONNECTION_FAILED && this.connectionFailure.length > 0) {
      return $r('app.string.comic_render_service_check_failed', this.connectionFailure)
    }
    return $r('app.string.comic_render_service_check_hint')
  }

  private connectionFailureText(error: Error): string {
    if (error.message === 'Manga rendering service session is invalid' &&
      this.effectiveCredential().hasLegacySession()) {
      return AppStrings.get('comic_render_service_session_expired')
    }
    if (error.message.startsWith('Manga rendering service')) {
      return AppStrings.get('comic_render_service_check_generic_reason')
    }
    return error.message
  }

  private async checkConnection(): Promise<void> {
    if (this.connectionState === CONNECTION_RUNNING || !await this.persist(true)) {
      return
    }
    if (this.baseUrlDraft.length === 0) {
      this.toast($r('app.string.comic_render_service_url_required'))
      return
    }
    this.connectionState = CONNECTION_RUNNING
    this.connectionFailure = ''
    const config: MangaTranslatorUiSidecarConfig = new MangaTranslatorUiSidecarConfig()
    const credential: MangaRenderingServiceCredential = this.effectiveCredential()
    config.baseUrl = this.baseUrlDraft
    config.username = credential.username
    config.password = credential.password
    config.sessionToken = credential.legacySessionToken
    config.applyProfile(
      'auto',
      this.detectionProfile,
      this.inpaintingProfile,
    )
    try {
      const result: MangaTranslatorUiSidecarConnectionResult =
        await MangaTranslatorUiSidecarConnectionService.check(config)
      this.connectionState = CONNECTION_OK
      this.toast($r('app.string.comic_render_service_check_success_revision', result.protocolRevision))
    } catch (error) {
      this.connectionState = CONNECTION_FAILED
      const failure: Error = error as Error
      this.connectionFailure = this.connectionFailureText(failure)
      DiagnosticLogger.warn('comic-translation', 'render_service_check_failed', failure.message)
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private detectionProfileText(): ResourceStr {
    return this.detectionProfile === MANGA_TRANSLATOR_UI_DETECTION_BALANCED
      ? $r('app.string.comic_render_service_detection_balanced')
      : $r('app.string.comic_render_service_detection_high_recall')
  }

  private inpaintingProfileText(): ResourceStr {
    return this.inpaintingProfile === MANGA_TRANSLATOR_UI_INPAINTER_FAST
      ? $r('app.string.comic_render_service_inpainting_fast')
      : $r('app.string.comic_render_service_inpainting_quality')
  }

  private selectDetectionProfile(value: string): void {
    this.detectionProfile = value
    this.connectionState = CONNECTION_IDLE
    this.persist(true)
  }

  private selectInpaintingProfile(value: string): void {
    this.inpaintingProfile = value
    this.connectionState = CONNECTION_IDLE
    this.persist(true)
  }

  @Builder
  private TextInputRow(label: ResourceStr, field: string, placeholder: ResourceStr) {
    if (field === 'baseUrl') {
      SettingsTextField({
        label: label,
        value: this.baseUrlDraft,
        placeholder: placeholder,
        onChange: (value: string) => {
          this.baseUrlDraft = value
          this.connectionState = CONNECTION_IDLE
        },
      })
    } else if (field === 'username') {
      SettingsTextField({
        label: label,
        value: this.usernameDraft,
        placeholder: placeholder,
        onChange: (value: string) => {
          this.usernameDraft = value
          this.credentialDirty = true
          this.connectionState = CONNECTION_IDLE
        },
      })
    } else {
      SettingsTextField({
        label: label,
        value: this.passwordDraft,
        placeholder: placeholder,
        inputType: InputType.Password,
        onChange: (value: string) => {
          this.passwordDraft = value
          this.credentialDirty = true
          this.connectionState = CONNECTION_IDLE
        },
      })
    }
  }

  @Builder
  private CheckingSuffix() {
    LoadingProgress()
      .width(22)
      .height(22)
      .color(ThemeConstants.BRAND_PRIMARY)
  }

  @Builder
  private DetectionProfileMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.comic_render_service_detection_high_recall'),
        selected: this.detectionProfile === MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL,
        selectAction: () => {
          select(() => {
            this.selectDetectionProfile(MANGA_TRANSLATOR_UI_DETECTION_HIGH_RECALL)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.comic_render_service_detection_balanced'),
        selected: this.detectionProfile === MANGA_TRANSLATOR_UI_DETECTION_BALANCED,
        selectAction: () => {
          select(() => {
            this.selectDetectionProfile(MANGA_TRANSLATOR_UI_DETECTION_BALANCED)
          })
        },
      })
    }
  }

  @Builder
  private InpaintingProfileMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.comic_render_service_inpainting_quality'),
        selected: this.inpaintingProfile === MANGA_TRANSLATOR_UI_INPAINTER_QUALITY,
        selectAction: () => {
          select(() => {
            this.selectInpaintingProfile(MANGA_TRANSLATOR_UI_INPAINTER_QUALITY)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.comic_render_service_inpainting_fast'),
        selected: this.inpaintingProfile === MANGA_TRANSLATOR_UI_INPAINTER_FAST,
        selectAction: () => {
          select(() => {
            this.selectInpaintingProfile(MANGA_TRANSLATOR_UI_INPAINTER_FAST)
          })
        },
      })
    }
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
                title: $r('app.string.comic_render_service_profile'),
                leadingIcon: $r('sys.symbol.doc_plaintext_and_checkmark'),
                trailingText: `manga-translator-ui ${MANGA_TRANSLATOR_UI_UPSTREAM_TAG}`,
                showChevron: false,
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.comic_render_service_detection'),
                leadingIcon: $r('sys.symbol.character_viewfinder'),
                trailingText: this.detectionProfileText(),
                trailingDropdown: true,
                dropdownMenuEnabled: true,
                dropdownMenuBuilder: (select: (action: () => void) => void) => {
                  this.DetectionProfileMenu(select)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.comic_render_service_inpainting'),
                leadingIcon: $r('sys.symbol.picture'),
                trailingText: this.inpaintingProfileText(),
                trailingDropdown: true,
                dropdownMenuEnabled: true,
                dropdownMenuBuilder: (select: (action: () => void) => void) => {
                  this.InpaintingProfileMenu(select)
                },
              })
              ListRowDivider()
              this.TextInputRow(
                $r('app.string.comic_render_service_url'),
                'baseUrl',
                'http://192.168.1.10:5003',
              )
              ListRowDivider()
              this.TextInputRow(
                $r('app.string.comic_render_service_username'),
                'username',
                $r('app.string.comic_render_service_username_hint'),
              )
              ListRowDivider()
              this.TextInputRow(
                $r('app.string.comic_render_service_password'),
                'password',
                this.passwordPlaceholder(),
              )
            }
          }
          ListItem() {
            GroupedListSection() {
              if (this.connectionState === CONNECTION_RUNNING) {
                ConciseListRow({
                  title: $r('app.string.comic_render_service_check'),
                  subtitle: this.connectionSubtitle(),
                  leadingIcon: $r('sys.symbol.checkmark_circle'),
                  showChevron: false,
                  action: () => {
                    this.checkConnection()
                  },
                  suffixBuilderParam: () => {
                    this.CheckingSuffix()
                  },
                })
              } else {
                ConciseListRow({
                  title: $r('app.string.comic_render_service_check'),
                  subtitle: this.connectionSubtitle(),
                  subtitleMaxLines: 2,
                  leadingIcon: $r('sys.symbol.checkmark_circle'),
                  trailingText: this.connectionState === CONNECTION_OK
                    ? $r('app.string.comic_render_service_available')
                    : '',
                  showChevron: false,
                  action: () => {
                    this.checkConnection()
                  },
                })
              }
            }
          }
          ListItem() {
            Text($r('app.string.comic_render_service_security_hint'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('comic_render_service_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
