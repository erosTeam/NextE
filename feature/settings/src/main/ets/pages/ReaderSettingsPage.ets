import { HdsNavDestination, IconStyleMode } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ReaderSuperResolutionModelsPage } from './ReaderSuperResolutionModelsPage'
import {
  ThemeConstants,
  connectReadMode,
  ReadModeState,
  ReadMode,
  ReaderBackgroundMode,
  ReaderImageScalingQuality,
  READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT,
  ReaderSuperResolutionModel,
  ReaderSuperResolutionModelService,
  ReadSpreadLayout,
  ReaderTapZoneInvert,
  ReaderTapZoneLayout,
  ReadModeSettings,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  AppStrings,
  connectNavStack,
  NavStackHolder,
  immersiveTitleBar,
  AppModalScaffold,
  SectionHeader,
} from 'shared'

/**
 * Reader settings (eros_fe 阅读 settings category). Page-turn mode is a native dropdown picker:
 * the row shows the current mode with a chevron, and tapping it opens a native
 * HDS `Menu` with the options and a `checkmark` on the active one — the same native idiom as the
 * favorites order picker (V2Next TopicDetailComponents bindMenu). eros_fe presents direction as an
 * action sheet, NOT inline checkmark rows; this is the native equivalent, not a hand-rolled tick.
 */
@ComponentV2
export struct ReaderSettingsPage {
  @Param sheetPresentation: boolean = false;
  @Event closeSheet?: () => void;
  @Local readMode: ReadModeState = connectReadMode();
  @Local dirMenuShown: boolean = false;
  @Local spreadLayoutMenuShown: boolean = false;
  @Local autoPageMenuShown: boolean = false;
  @Local preloadPageMenuShown: boolean = false;
  @Local tapZoneMenuShown: boolean = false;
  @Local tapZoneInvertMenuShown: boolean = false;
  @Local backgroundMenuShown: boolean = false;
  @Local imageScalingQualityMenuShown: boolean = false;
  @Local superResolutionModelMenuShown: boolean = false;
  @Local superResolutionMaxHeightMenuShown: boolean = false;
  @Local installedSuperResolutionModels: string[] = [];
  @Local superResolutionModelsPanelShown: boolean = false;
  @Local sheetPanelWidth: number = 0;
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshSuperResolutionModels()
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private setMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, mode)
  }

  private setDoublePageEnabled(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setDoublePageEnabled(ctx, enabled)
  }

  private setSpreadLayoutMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setSpreadLayoutMode(ctx, mode)
  }

  private setAutoPageSeconds(seconds: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setAutoPageSeconds(ctx, seconds)
  }

  private setPreloadPages(pages: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setPreloadPages(ctx, pages)
  }

  private setVolumeKeyTurn(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setVolumeKeyTurn(ctx, enabled)
  }

  private setTapZoneLayout(layout: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setTapZoneLayout(ctx, layout)
  }

  private setTapZoneInvert(invert: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setTapZoneInvert(ctx, invert)
  }

  private setBackgroundMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setBackgroundMode(ctx, mode)
  }

  private setImageScalingQuality(quality: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setImageScalingQuality(ctx, quality)
  }

  private setSuperResolutionEnabled(enabled: boolean): void {
    if (enabled && this.installedSuperResolutionModels.length === 0) {
      return
    }
    ReadModeSettings.setSuperResolutionEnabled(this.context(), enabled)
  }

  private async refreshSuperResolutionModels(): Promise<void> {
    this.installedSuperResolutionModels =
      await ReaderSuperResolutionModelService.installedModels(this.context())
    let selectedInstalled: boolean = false
    for (let i: number = 0; i < this.installedSuperResolutionModels.length; i++) {
      if (this.installedSuperResolutionModels[i] === this.readMode.superResolutionModel) {
        selectedInstalled = true
        break
      }
    }
    if (!selectedInstalled) {
      const replacement: string = this.installedSuperResolutionModels.length > 0
        ? this.installedSuperResolutionModels[0]
        : ReaderSuperResolutionModel.NONE
      ReadModeSettings.setSuperResolutionModel(this.context(), replacement)
      if (replacement === ReaderSuperResolutionModel.NONE) {
        ReadModeSettings.setSuperResolutionEnabled(this.context(), false)
      }
    }
  }

  private setSuperResolutionModel(model: string): void {
    ReadModeSettings.setSuperResolutionModel(this.context(), model)
  }

  private openSuperResolutionModelManagement(): void {
    if (this.sheetPresentation) {
      this.getUIContext().animateTo({
        duration: ThemeConstants.ANIM_DURATION,
        curve: Curve.EaseOut,
      }, () => {
        this.superResolutionModelsPanelShown = true
      })
      return
    }
    this.stack.pushPathByName('ReaderSuperResolutionModels', null)
  }

  private closeSuperResolutionModelManagement(): void {
    this.refreshSuperResolutionModels()
    this.getUIContext().animateTo({
      duration: ThemeConstants.ANIM_DURATION,
      curve: Curve.EaseOut,
    }, () => {
      this.superResolutionModelsPanelShown = false
    })
  }

  private setSuperResolutionMaxHeight(maxHeight: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setSuperResolutionMaxHeight(ctx, maxHeight)
  }

  private setShowPageNumber(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setShowPageNumber(ctx, enabled)
  }

  private setFullscreen(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setFullscreen(ctx, enabled)
  }

  private setKeepScreenOn(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setKeepScreenOn(ctx, enabled)
  }

  private setPageTurnAnimation(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setPageTurnAnimation(ctx, enabled)
  }

  private modeLabel(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readMode.mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('app.string.read_mode_ttb')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private modeIconFor(mode: string): Resource {
    if (mode === ReadMode.RTL) {
      return $r('sys.symbol.arrow_left_and_square')
    }
    if (mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('sys.symbol.single_page_flipping')
    }
    if (mode === ReadMode.VERTICAL) {
      return $r('sys.symbol.scroll_vertical')
    }
    return $r('sys.symbol.arrow_right_and_square')
  }

  private doublePageAvailable(): boolean {
    return this.readMode.mode === ReadMode.LTR || this.readMode.mode === ReadMode.RTL
  }

  private spreadLayoutLabel(): Resource {
    if (this.readMode.spreadLayoutMode === ReadSpreadLayout.SPLIT) {
      return $r('app.string.settings_reader_spread_layout_split')
    }
    return $r('app.string.settings_reader_spread_layout_joined')
  }

  private autoPageLabel(): string {
    return `${this.readMode.autoPageSeconds}s`
  }

  private preloadPageLabel(): string {
    return `${this.readMode.preloadPages}`
  }

  private tapZoneLabel(): Resource {
    if (this.readMode.tapZoneLayout === ReaderTapZoneLayout.L_SHAPED) {
      return $r('app.string.settings_reader_tap_zone_l_shaped')
    }
    if (this.readMode.tapZoneLayout === ReaderTapZoneLayout.KINDLE) {
      return $r('app.string.settings_reader_tap_zone_kindle')
    }
    if (this.readMode.tapZoneLayout === ReaderTapZoneLayout.EDGE) {
      return $r('app.string.settings_reader_tap_zone_edge')
    }
    return $r('app.string.settings_reader_tap_zone_right_left')
  }

  private tapZoneInvertLabel(): Resource {
    if (this.readMode.tapZoneInvert === ReaderTapZoneInvert.HORIZONTAL) {
      return $r('app.string.settings_reader_tap_zone_invert_horizontal')
    }
    if (this.readMode.tapZoneInvert === ReaderTapZoneInvert.VERTICAL) {
      return $r('app.string.settings_reader_tap_zone_invert_vertical')
    }
    if (this.readMode.tapZoneInvert === ReaderTapZoneInvert.BOTH) {
      return $r('app.string.settings_reader_tap_zone_invert_both')
    }
    return $r('app.string.settings_reader_tap_zone_invert_none')
  }

  private backgroundModeLabel(): Resource {
    if (this.readMode.backgroundMode === ReaderBackgroundMode.GRAY) {
      return $r('app.string.settings_reader_background_gray')
    }
    if (this.readMode.backgroundMode === ReaderBackgroundMode.WHITE) {
      return $r('app.string.settings_reader_background_white')
    }
    if (this.readMode.backgroundMode === ReaderBackgroundMode.AUTO) {
      return $r('app.string.settings_reader_background_auto')
    }
    return $r('app.string.settings_reader_background_black')
  }

  private imageScalingQualityLabel(): Resource {
    if (this.readMode.imageScalingQuality === ReaderImageScalingQuality.LOW) {
      return $r('app.string.settings_reader_image_scaling_quality_standard')
    }
    if (this.readMode.imageScalingQuality === ReaderImageScalingQuality.HIGH) {
      return $r('app.string.settings_reader_image_scaling_quality_high')
    }
    return $r('app.string.settings_reader_image_scaling_quality_optimized')
  }

  private superResolutionModelLabel(): ResourceStr {
    if (this.installedSuperResolutionModels.length === 0) {
      return $r('app.string.settings_reader_super_resolution_models_none_installed')
    }
    return this.superResolutionModelTitle(this.readMode.superResolutionModel)
  }

  private superResolutionModelTitle(model: string): ResourceStr {
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

  private superResolutionMaxHeightLabel(): string {
    return `${this.readMode.superResolutionMaxHeight}px`
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  // Native direction picker: a framework Menu/MenuItem with a checkmark symbolEndIcon on the active
  // mode (V2Next TopicDetailComponents.ets:192-227). Selecting one persists via ReadModeSettings + closes.
  @Builder
  DirMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.read_mode_ltr'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.LTR)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.LTR
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.LTR)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_rtl'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.RTL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.RTL)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_ttb'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.TOP_TO_BOTTOM)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.TOP_TO_BOTTOM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.TOP_TO_BOTTOM)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_vertical'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.VERTICAL)),
        symbolEndIcon:
          this.readMode.mode === ReadMode.VERTICAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.VERTICAL)
        this.dirMenuShown = false
      })
    }
  }

  @Builder
  AutoPageMenu() {
    Menu() {
      MenuItem({
        content: '2s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 2
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(2)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '3s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 3
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(3)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '5s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 5
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(5)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '8s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 8
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(8)
        this.autoPageMenuShown = false
      })
      MenuItem({
        content: '10s',
        symbolEndIcon:
          this.readMode.autoPageSeconds === 10
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setAutoPageSeconds(10)
        this.autoPageMenuShown = false
      })
    }
  }

  @Builder
  SpreadLayoutMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_spread_layout_joined'),
        symbolEndIcon:
          this.readMode.spreadLayoutMode === ReadSpreadLayout.JOINED
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setSpreadLayoutMode(ReadSpreadLayout.JOINED)
        this.spreadLayoutMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_spread_layout_split'),
        symbolEndIcon:
          this.readMode.spreadLayoutMode === ReadSpreadLayout.SPLIT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setSpreadLayoutMode(ReadSpreadLayout.SPLIT)
        this.spreadLayoutMenuShown = false
      })
    }
  }

  @Builder
  PreloadPageMenu() {
    Menu() {
      MenuItem({
        content: '0',
        symbolEndIcon:
          this.readMode.preloadPages === 0
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(0)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '1',
        symbolEndIcon:
          this.readMode.preloadPages === 1
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(1)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '2',
        symbolEndIcon:
          this.readMode.preloadPages === 2
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(2)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '3',
        symbolEndIcon:
          this.readMode.preloadPages === 3
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(3)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '4',
        symbolEndIcon:
          this.readMode.preloadPages === 4
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(4)
        this.preloadPageMenuShown = false
      })
      MenuItem({
        content: '5',
        symbolEndIcon:
          this.readMode.preloadPages === 5
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setPreloadPages(5)
        this.preloadPageMenuShown = false
      })
    }
  }

  @Builder
  TapZoneMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_right_left'),
        symbolEndIcon:
          this.readMode.tapZoneLayout === ReaderTapZoneLayout.RIGHT_LEFT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneLayout(ReaderTapZoneLayout.RIGHT_LEFT)
        this.tapZoneMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_l_shaped'),
        symbolEndIcon:
          this.readMode.tapZoneLayout === ReaderTapZoneLayout.L_SHAPED
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneLayout(ReaderTapZoneLayout.L_SHAPED)
        this.tapZoneMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_kindle'),
        symbolEndIcon:
          this.readMode.tapZoneLayout === ReaderTapZoneLayout.KINDLE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneLayout(ReaderTapZoneLayout.KINDLE)
        this.tapZoneMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_edge'),
        symbolEndIcon:
          this.readMode.tapZoneLayout === ReaderTapZoneLayout.EDGE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneLayout(ReaderTapZoneLayout.EDGE)
        this.tapZoneMenuShown = false
      })
    }
  }

  @Builder
  TapZoneInvertMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_invert_none'),
        symbolEndIcon:
          this.readMode.tapZoneInvert === ReaderTapZoneInvert.NONE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneInvert(ReaderTapZoneInvert.NONE)
        this.tapZoneInvertMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_invert_horizontal'),
        symbolEndIcon:
          this.readMode.tapZoneInvert === ReaderTapZoneInvert.HORIZONTAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneInvert(ReaderTapZoneInvert.HORIZONTAL)
        this.tapZoneInvertMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_invert_vertical'),
        symbolEndIcon:
          this.readMode.tapZoneInvert === ReaderTapZoneInvert.VERTICAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneInvert(ReaderTapZoneInvert.VERTICAL)
        this.tapZoneInvertMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_tap_zone_invert_both'),
        symbolEndIcon:
          this.readMode.tapZoneInvert === ReaderTapZoneInvert.BOTH
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setTapZoneInvert(ReaderTapZoneInvert.BOTH)
        this.tapZoneInvertMenuShown = false
      })
    }
  }

  @Builder
  BackgroundMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_background_black'),
        symbolEndIcon:
          this.readMode.backgroundMode === ReaderBackgroundMode.BLACK
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setBackgroundMode(ReaderBackgroundMode.BLACK)
        this.backgroundMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_background_gray'),
        symbolEndIcon:
          this.readMode.backgroundMode === ReaderBackgroundMode.GRAY
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setBackgroundMode(ReaderBackgroundMode.GRAY)
        this.backgroundMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_background_white'),
        symbolEndIcon:
          this.readMode.backgroundMode === ReaderBackgroundMode.WHITE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setBackgroundMode(ReaderBackgroundMode.WHITE)
        this.backgroundMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_background_auto'),
        symbolEndIcon:
          this.readMode.backgroundMode === ReaderBackgroundMode.AUTO
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setBackgroundMode(ReaderBackgroundMode.AUTO)
        this.backgroundMenuShown = false
      })
    }
  }

  @Builder
  ImageScalingQualityMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.settings_reader_image_scaling_quality_standard'),
        symbolEndIcon:
          this.readMode.imageScalingQuality === ReaderImageScalingQuality.LOW
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setImageScalingQuality(ReaderImageScalingQuality.LOW)
        this.imageScalingQualityMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_image_scaling_quality_optimized'),
        symbolEndIcon:
          this.readMode.imageScalingQuality === ReaderImageScalingQuality.MEDIUM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setImageScalingQuality(ReaderImageScalingQuality.MEDIUM)
        this.imageScalingQualityMenuShown = false
      })
      MenuItem({
        content: $r('app.string.settings_reader_image_scaling_quality_high'),
        symbolEndIcon:
          this.readMode.imageScalingQuality === ReaderImageScalingQuality.HIGH
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setImageScalingQuality(ReaderImageScalingQuality.HIGH)
        this.imageScalingQualityMenuShown = false
      })
    }
  }

  @Builder
  SuperResolutionModelMenu() {
    Menu() {
      ForEach(this.installedSuperResolutionModels, (model: string) => {
        MenuItem({
          content: this.superResolutionModelTitle(model),
          symbolEndIcon:
            this.readMode.superResolutionModel === model
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
        }).onClick(() => {
          this.setSuperResolutionModel(model)
          this.superResolutionModelMenuShown = false
        })
      }, (model: string): string => model)
    }
  }

  @Builder
  SuperResolutionMaxHeightMenu() {
    Menu() {
      ForEach([1000, 1500, READER_SUPER_RESOLUTION_MAX_SOURCE_HEIGHT], (maxHeight: number) => {
        MenuItem({
          content: `${maxHeight}px`,
          symbolEndIcon:
            this.readMode.superResolutionMaxHeight === maxHeight
              ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
              : undefined,
        }).onClick(() => {
          this.setSuperResolutionMaxHeight(maxHeight)
          this.superResolutionMaxHeightMenuShown = false
        })
      }, (maxHeight: number): string => `${maxHeight}`)
    }
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'ReaderSettings'
  }

  @Builder
  private SettingsListItems() {
    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_layout') })
        GroupedListSection() {
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_direction'),
              trailingText: this.modeLabel(),
              trailingDropdown: true,
              action: () => {
                this.dirMenuShown = true
              },
            })
          }
          .bindMenu(this.dirMenuShown, this.DirMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.dirMenuShown = false
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_double_page'),
            hasSwitch: true,
            checked: this.doublePageAvailable() && this.readMode.doublePageEnabled,
            isEnabled: this.doublePageAvailable(),
            showChevron: false,
            action: () => {
              if (this.doublePageAvailable()) {
                this.setDoublePageEnabled(!this.readMode.doublePageEnabled)
              }
            },
            switchAction: (value: boolean) => {
              if (this.doublePageAvailable()) {
                this.setDoublePageEnabled(value)
              }
            },
          })
          this.rowDivider()
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_spread_layout'),
              trailingText: this.spreadLayoutLabel(),
              trailingDropdown: true,
              isEnabled: this.doublePageAvailable(),
              action: () => {
                if (this.doublePageAvailable()) {
                  this.spreadLayoutMenuShown = true
                }
              },
            })
          }
          .bindMenu(this.spreadLayoutMenuShown, this.SpreadLayoutMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.spreadLayoutMenuShown = false
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_page_turn_animation'),
            hasSwitch: true,
            checked: this.readMode.pageTurnAnimation,
            showChevron: false,
            action: () => {
              this.setPageTurnAnimation(!this.readMode.pageTurnAnimation)
            },
            switchAction: (value: boolean) => {
              this.setPageTurnAnimation(value)
            },
          })
        }
      }
    }

    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_tap_zones') })
        GroupedListSection() {
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_tap_zones'),
              trailingText: this.tapZoneLabel(),
              trailingDropdown: true,
              action: () => {
                this.tapZoneMenuShown = true
              },
            })
          }
          .bindMenu(this.tapZoneMenuShown, this.TapZoneMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.tapZoneMenuShown = false
            },
          })
          this.rowDivider()
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_tap_zone_invert'),
              trailingText: this.tapZoneInvertLabel(),
              trailingDropdown: true,
              action: () => {
                this.tapZoneInvertMenuShown = true
              },
            })
          }
          .bindMenu(this.tapZoneInvertMenuShown, this.TapZoneInvertMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.tapZoneInvertMenuShown = false
            },
          })
        }
      }
    }

    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_display') })
        GroupedListSection() {
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_background'),
              trailingText: this.backgroundModeLabel(),
              trailingDropdown: true,
              action: () => {
                this.backgroundMenuShown = true
              },
            })
          }
          .bindMenu(this.backgroundMenuShown, this.BackgroundMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.backgroundMenuShown = false
            },
          })
          this.rowDivider()
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_image_scaling_quality'),
              subtitle: $r('app.string.settings_reader_image_scaling_quality_hint'),
              subtitleMaxLines: 3,
              trailingText: this.imageScalingQualityLabel(),
              trailingDropdown: true,
              action: () => {
                this.imageScalingQualityMenuShown = true
              },
            })
          }
          .bindMenu(this.imageScalingQualityMenuShown, this.ImageScalingQualityMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.imageScalingQualityMenuShown = false
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_show_page_number'),
            hasSwitch: true,
            checked: this.readMode.showPageNumber,
            showChevron: false,
            action: () => {
              this.setShowPageNumber(!this.readMode.showPageNumber)
            },
            switchAction: (value: boolean) => {
              this.setShowPageNumber(value)
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_fullscreen'),
            hasSwitch: true,
            checked: this.readMode.fullscreen,
            showChevron: false,
            action: () => {
              this.setFullscreen(!this.readMode.fullscreen)
            },
            switchAction: (value: boolean) => {
              this.setFullscreen(value)
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_keep_screen_on'),
            hasSwitch: true,
            checked: this.readMode.keepScreenOn,
            showChevron: false,
            action: () => {
              this.setKeepScreenOn(!this.readMode.keepScreenOn)
            },
            switchAction: (value: boolean) => {
              this.setKeepScreenOn(value)
            },
          })
        }
      }
    }

    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_image_enhancement') })
        GroupedListSection() {
          ConciseListRow({
            title: $r('app.string.settings_reader_super_resolution'),
            hasSwitch: true,
            checked: this.readMode.superResolutionEnabled,
            isEnabled: this.installedSuperResolutionModels.length > 0,
            showChevron: false,
            action: () => {
              if (this.installedSuperResolutionModels.length > 0) {
                this.setSuperResolutionEnabled(!this.readMode.superResolutionEnabled)
              }
            },
            switchAction: (value: boolean) => {
              this.setSuperResolutionEnabled(value)
            },
          })
          this.rowDivider()
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_super_resolution_model'),
              trailingText: this.superResolutionModelLabel(),
              trailingDropdown: true,
              isEnabled: this.installedSuperResolutionModels.length > 0,
              action: () => {
                if (this.installedSuperResolutionModels.length > 0) {
                  this.superResolutionModelMenuShown = true
                }
              },
            })
          }
          .bindMenu(this.superResolutionModelMenuShown, this.SuperResolutionModelMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.superResolutionModelMenuShown = false
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_super_resolution_models'),
            action: () => {
              this.openSuperResolutionModelManagement()
            },
          })
          this.rowDivider()
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_super_resolution_max_height'),
              subtitle: $r('app.string.settings_reader_super_resolution_max_height_hint'),
              subtitleMaxLines: 3,
              trailingText: this.superResolutionMaxHeightLabel(),
              trailingDropdown: true,
              isEnabled: this.readMode.superResolutionEnabled &&
                this.readMode.superResolutionModel !== ReaderSuperResolutionModel.NONE,
              action: () => {
                if (this.readMode.superResolutionEnabled &&
                  this.readMode.superResolutionModel !== ReaderSuperResolutionModel.NONE) {
                  this.superResolutionMaxHeightMenuShown = true
                }
              },
            })
          }
          .bindMenu(this.superResolutionMaxHeightMenuShown, this.SuperResolutionMaxHeightMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.superResolutionMaxHeightMenuShown = false
            },
          })
        }
      }
    }

    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_controls') })
        GroupedListSection() {
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_auto_page_interval'),
              trailingText: this.autoPageLabel(),
              trailingDropdown: true,
              action: () => {
                this.autoPageMenuShown = true
              },
            })
          }
          .bindMenu(this.autoPageMenuShown, this.AutoPageMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.autoPageMenuShown = false
            },
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.settings_reader_volume_key'),
            subtitle: $r('app.string.settings_reader_volume_key_hint'),
            subtitleMaxLines: 3,
            hasSwitch: true,
            checked: this.readMode.volumeKeyTurn,
            showChevron: false,
            action: () => {
              this.setVolumeKeyTurn(!this.readMode.volumeKeyTurn)
            },
            switchAction: (value: boolean) => {
              this.setVolumeKeyTurn(value)
            },
          })
        }
      }
    }

    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        SectionHeader({ title: $r('app.string.settings_reader_group_loading') })
        GroupedListSection() {
          Column() {
            ConciseListRow({
              title: $r('app.string.settings_reader_preload_pages'),
              trailingText: this.preloadPageLabel(),
              trailingDropdown: true,
              action: () => {
                this.preloadPageMenuShown = true
              },
            })
          }
          .bindMenu(this.preloadPageMenuShown, this.PreloadPageMenu, {
            placement: Placement.BottomRight,
            onDisappear: () => {
              this.preloadPageMenuShown = false
            },
          })
        }
      }
    }
  }

  @Builder
  private ReaderSettingsSheetPage() {
    AppModalScaffold({
      title: $r('app.string.settings_reader'),
      showConfirmAction: false,
      closeAction: () => {
        if (this.closeSheet) {
          this.closeSheet()
        }
      },
    }) {
      this.SettingsListItems()
    }
  }

  @Builder
  private SuperResolutionModelsSheetPage() {
    ReaderSuperResolutionModelsPage({
      modal: true,
      modalCloseIcon: $r('sys.media.ohos_ic_compnent_titlebar_back'),
      modalCloseIconStyle: IconStyleMode.NORMAL,
      closeAction: () => {
        this.closeSuperResolutionModelManagement()
      },
      modelsChanged: () => {
        this.refreshSuperResolutionModels()
      },
    })
  }

  @Builder
  private ReaderSettingsSheetPanel() {
    Stack() {
      Column() {
        this.ReaderSettingsSheetPage()
      }
      .width('100%')
      .height('100%')
      .translate({
        x: this.superResolutionModelsPanelShown ? -this.sheetPanelWidth : 0,
      })

      Column() {
        this.SuperResolutionModelsSheetPage()
      }
      .width('100%')
      .height('100%')
      .opacity(this.sheetPanelWidth > 0 ? 1 : 0)
      .translate({
        x: this.superResolutionModelsPanelShown ? 0 : this.sheetPanelWidth,
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.sheetPanelWidth = area.width as number
    })
  }

  build() {
    if (this.sheetPresentation) {
      this.ReaderSettingsSheetPanel()
    } else {
      HdsNavDestination() {
        SecondaryListScaffold({
          scroller: this.scroller,
          bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
        }) {
          this.SettingsListItems()
        }
      }
      .titleBar(immersiveTitleBar(AppStrings.get('settings_reader')))
      .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .onReady((context: NavDestinationContext) => {
        this.refreshFirstSecondaryDestination(context.pathStack)
      })
      .onWillShow(() => {
        this.refreshFirstSecondaryDestination(this.stack)
        this.refreshSuperResolutionModels()
      })
    }
  }
}
