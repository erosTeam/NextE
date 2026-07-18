import { common } from '@kit.AbilityKit'
import { HdsNavDestination, IconStyleMode } from '@kit.UIDesignKit'
import {
  AppStrings,
  AppModalScaffold,
  ConciseListRow,
  GroupedListSection,
  ReaderSuperResolutionModel,
  ReaderSuperResolutionModelDefinition,
  ReaderSuperResolutionModelService,
  ReadModeSettings,
  ReadModeState,
  SecondaryListScaffold,
  ThemeConstants,
  connectReadMode,
  immersiveTitleBar,
} from 'shared'

@ObservedV2
class ReaderSuperResolutionModelFileState {
  definition: ReaderSuperResolutionModelDefinition
  @Trace installed: boolean = false
  @Trace downloading: boolean = false

  constructor(definition: ReaderSuperResolutionModelDefinition) {
    this.definition = definition
  }
}

/** Local model-file management. Active-model selection remains in ReaderSettingsPage. */
@ComponentV2
export struct ReaderSuperResolutionModelsPage {
  @Param modal: boolean = false
  @Param modalCloseIcon: Resource = $r('sys.symbol.xmark')
  @Param modalCloseIconStyle: IconStyleMode = IconStyleMode.SMALL
  @Event closeAction?: () => void
  @Event modelsChanged?: () => void
  @Local readMode: ReadModeState = connectReadMode()
  @Local modelStates: ReaderSuperResolutionModelFileState[] = []
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    if (this.modelStates.length === 0) {
      const definitions: ReaderSuperResolutionModelDefinition[] =
        ReaderSuperResolutionModelService.definitions()
      const states: ReaderSuperResolutionModelFileState[] = []
      for (let i: number = 0; i < definitions.length; i++) {
        states.push(new ReaderSuperResolutionModelFileState(definitions[i]))
      }
      this.modelStates = states
    }
    this.refreshInstallState()
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private async refreshInstallState(): Promise<void> {
    for (let i: number = 0; i < this.modelStates.length; i++) {
      this.modelStates[i].installed = await ReaderSuperResolutionModelService.isInstalled(
        this.context(),
        this.modelStates[i].definition.id,
      )
    }
  }

  private modelTitle(model: string): ResourceStr {
    if (model === ReaderSuperResolutionModel.ESPCN_X2) {
      return $r('app.string.settings_reader_super_resolution_espcn_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS) {
      return $r('app.string.settings_reader_super_resolution_realesrgan_x2plus')
    }
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_ANIMEVIDEO_V3_X2) {
      return $r('app.string.settings_reader_super_resolution_realesrgan_animevideov3_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X) {
      return $r('app.string.settings_reader_super_resolution_waifu2x_art_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X) {
      return $r('app.string.settings_reader_super_resolution_waifu2x_cunet_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE) {
      return $r('app.string.settings_reader_super_resolution_realcugan_se_2x_conservative')
    }
    return $r('app.string.settings_reader_super_resolution_waifu2x_photo_noise0_2x')
  }

  private modelTitleText(model: string): string {
    if (model === ReaderSuperResolutionModel.ESPCN_X2) {
      return AppStrings.get('settings_reader_super_resolution_espcn_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_X2PLUS) {
      return AppStrings.get('settings_reader_super_resolution_realesrgan_x2plus')
    }
    if (model === ReaderSuperResolutionModel.REAL_ESRGAN_ANIMEVIDEO_V3_X2) {
      return AppStrings.get('settings_reader_super_resolution_realesrgan_animevideov3_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X) {
      return AppStrings.get('settings_reader_super_resolution_waifu2x_art_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.WAIFU2X_CUNET_NOISE0_2X) {
      return AppStrings.get('settings_reader_super_resolution_waifu2x_cunet_noise0_2x')
    }
    if (model === ReaderSuperResolutionModel.REAL_CUGAN_SE_2X_CONSERVATIVE) {
      return AppStrings.get('settings_reader_super_resolution_realcugan_se_2x_conservative')
    }
    return AppStrings.get('settings_reader_super_resolution_waifu2x_photo_noise0_2x')
  }

  private notifyModelsChanged(): void {
    if (this.modelsChanged) {
      this.modelsChanged()
    }
  }

  private modelSubtitle(definition: ReaderSuperResolutionModelDefinition): string {
    const scope: string = AppStrings.get(definition.usageScopeStringKey)
    let performanceKey: string = 'settings_reader_super_resolution_performance_seconds'
    if (definition.reference800pElapsedMs >= 60000) {
      performanceKey = 'settings_reader_super_resolution_performance_minutes'
    } else if (definition.reference800pElapsedMs >= 10000) {
      performanceKey = 'settings_reader_super_resolution_performance_tens_seconds'
    }
    const performance: string = AppStrings.get(performanceKey)
    const bytes: number = definition.bytes()
    const size: string = bytes < 1024 * 1024
      ? `${Math.round(bytes / 1024)} KB`
      : `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    return `${scope} · ${performance} · ${size}`
  }

  private async downloadModel(state: ReaderSuperResolutionModelFileState): Promise<void> {
    if (state.installed || state.downloading) {
      return
    }
    state.downloading = true
    try {
      await ReaderSuperResolutionModelService.install(this.context(), state.definition.id)
      state.installed = true
      if (this.readMode.superResolutionModel === ReaderSuperResolutionModel.NONE) {
        ReadModeSettings.setSuperResolutionModel(this.context(), state.definition.id)
      }
      this.notifyModelsChanged()
      this.toast($r('app.string.settings_reader_super_resolution_model_downloaded'))
    } catch (_error) {
      this.toast($r('app.string.settings_reader_super_resolution_model_download_failed'))
    } finally {
      state.downloading = false
    }
  }

  private confirmRemoveModel(state: ReaderSuperResolutionModelFileState): void {
    const message: string = AppStrings.get('settings_reader_super_resolution_model_delete_confirm')
      .replace('%s', this.modelTitleText(state.definition.id))
    this.getUIContext().showAlertDialog({
      message: message,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: Color.Red,
        action: () => {
          this.removeModel(state)
        },
      },
    })
  }

  private removeModel(state: ReaderSuperResolutionModelFileState): void {
    if (!state.installed || state.downloading) {
      return
    }
    ReaderSuperResolutionModelService.remove(this.context(), state.definition.id)
    state.installed = false
    if (this.readMode.superResolutionModel === state.definition.id) {
      let replacement: string = ReaderSuperResolutionModel.NONE
      for (let i: number = 0; i < this.modelStates.length; i++) {
        if (this.modelStates[i].installed) {
          replacement = this.modelStates[i].definition.id
          break
        }
      }
      ReadModeSettings.setSuperResolutionModel(this.context(), replacement)
      if (replacement === ReaderSuperResolutionModel.NONE) {
        ReadModeSettings.setSuperResolutionEnabled(this.context(), false)
      }
    }
    this.notifyModelsChanged()
    this.toast($r('app.string.settings_reader_super_resolution_model_deleted'))
  }

  @Builder
  private ModelAction(state: ReaderSuperResolutionModelFileState) {
    if (state.downloading) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        LoadingProgress()
          .width(ThemeConstants.FONT_SIZE_TITLE)
          .height(ThemeConstants.FONT_SIZE_TITLE)
          .color(ThemeConstants.BRAND_PRIMARY)
      }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .backgroundColor(Color.Transparent)
      .enabled(false)
      .accessibilityText($r('app.string.settings_reader_super_resolution_model_downloading_short'))
    } else {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(state.installed
          ? $r('sys.symbol.trash')
          : $r('sys.symbol.arrow_down_to_line'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([state.installed ? Color.Red : ThemeConstants.BRAND_PRIMARY])
      }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .height(ThemeConstants.DOWNLOAD_TASK_ACTION_BUTTON_SIZE)
      .backgroundColor(Color.Transparent)
      .accessibilityText(state.installed
        ? $r('app.string.common_delete')
        : $r('app.string.settings_reader_super_resolution_model_download'))
      .onClick(() => {
        if (state.installed) {
          this.confirmRemoveModel(state)
        } else {
          this.downloadModel(state)
        }
      })
    }
  }

  @Builder
  private ModelRow(state: ReaderSuperResolutionModelFileState) {
    ConciseListRow({
      title: this.modelTitle(state.definition.id),
      subtitle: this.modelSubtitle(state.definition),
      showChevron: false,
      suffixPaddingRight: 0,
      suffixBuilderParam: () => {
        this.ModelAction(state)
      },
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
  private ModelFileList() {
    ListItem() {
      GroupedListSection() {
        ForEach(
          this.modelStates,
          (state: ReaderSuperResolutionModelFileState, index: number) => {
            this.ModelRow(state)
            if (index < this.modelStates.length - 1) {
              this.rowDivider()
            }
          },
          (state: ReaderSuperResolutionModelFileState): string => state.definition.id,
        )
      }
    }
  }

  build() {
    if (this.modal) {
      AppModalScaffold({
        title: $r('app.string.settings_reader_super_resolution_models'),
        showConfirmAction: false,
        closeIcon: this.modalCloseIcon,
        closeIconStyle: this.modalCloseIconStyle,
        closeAction: () => {
          if (this.closeAction) {
            this.closeAction()
          }
        },
      }) {
        this.ModelFileList()
      }
    } else {
      HdsNavDestination() {
        SecondaryListScaffold({
          scroller: this.scroller,
          bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
        }) {
          this.ModelFileList()
        }
      }
      .titleBar(immersiveTitleBar(AppStrings.get('settings_reader_super_resolution_models')))
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    }
  }
}
