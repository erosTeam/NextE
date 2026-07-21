import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  MANGA_TRANSLATOR_UI_UPSTREAM_TAG,
  MangaRenderingServiceSecretStore,
  MangaRenderingServiceSettings,
  MangaRenderingServiceSettingsSnapshot,
  MangaTranslatorUiSidecarConfig,
  MangaTranslatorUiSidecarConnectionResult,
  MangaTranslatorUiSidecarConnectionService,
  SecondaryListScaffold,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'

const CONNECTION_IDLE: string = 'idle'
const CONNECTION_RUNNING: string = 'running'
const CONNECTION_OK: string = 'ok'
const CONNECTION_FAILED: string = 'failed'

@ComponentV2
export struct MangaRenderingServiceSettingsPage {
  @Local private baseUrlDraft: string = '';
  @Local private credentialDraft: string = '';
  @Local private loaded: boolean = false;
  @Local private connectionState: string = CONNECTION_IDLE;
  @Local private connectionFailure: string = '';
  private scroller: Scroller = new Scroller();

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
      const credential: string = await MangaRenderingServiceSecretStore.read(this.ctx())
      this.baseUrlDraft = snapshot.baseUrl
      this.credentialDraft = credential
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
    try {
      await MangaRenderingServiceSettings.save(this.ctx(), snapshot)
      await MangaRenderingServiceSecretStore.save(this.ctx(), this.credentialDraft)
      const stored: MangaRenderingServiceSettingsSnapshot =
        await MangaRenderingServiceSettings.load(this.ctx())
      this.baseUrlDraft = stored.baseUrl
      return true
    } catch (error) {
      DiagnosticLogger.warn('comic-translation', 'render_service_save_failed', (error as Error).message)
      if (showFailureToast) {
        this.toast($r('app.string.comic_render_service_save_failed', (error as Error).message))
      }
      return false
    }
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
    config.baseUrl = this.baseUrlDraft
    config.authorizationValue = this.credentialDraft
    try {
      const result: MangaTranslatorUiSidecarConnectionResult =
        await MangaTranslatorUiSidecarConnectionService.check(config)
      this.connectionState = CONNECTION_OK
      this.toast($r('app.string.comic_render_service_check_success_revision', result.protocolRevision))
    } catch (error) {
      this.connectionState = CONNECTION_FAILED
      this.connectionFailure = (error as Error).message
      DiagnosticLogger.warn('comic-translation', 'render_service_check_failed', this.connectionFailure)
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
  private TextInputBox(field: string, placeholder: ResourceStr) {
    if (field === 'baseUrl') {
      TextInput({ text: $$this.baseUrlDraft, placeholder: placeholder })
        .type(InputType.Normal)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange(() => {
          this.connectionState = CONNECTION_IDLE
        })
    } else {
      TextInput({ text: $$this.credentialDraft, placeholder: placeholder })
        .type(InputType.Password)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .onChange(() => {
          this.connectionState = CONNECTION_IDLE
        })
    }
  }

  @Builder
  private TextInputRow(label: ResourceStr, field: string, placeholder: ResourceStr) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      this.TextInputBox(field, placeholder)
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
  private CheckingSuffix() {
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
        if (this.loaded) {
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.comic_render_service_profile'),
                subtitle: $r('app.string.comic_render_service_profile_hint'),
                leadingIcon: $r('sys.symbol.doc_plaintext_and_checkmark'),
                trailingText: `manga-translator-ui ${MANGA_TRANSLATOR_UI_UPSTREAM_TAG}`,
                showChevron: false,
              })
              this.rowDivider()
              this.TextInputRow(
                $r('app.string.comic_render_service_url'),
                'baseUrl',
                'http://192.168.1.10:5003',
              )
              this.rowDivider()
              this.TextInputRow(
                $r('app.string.comic_render_service_credential'),
                'credential',
                $r('app.string.comic_render_service_credential_hint'),
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
