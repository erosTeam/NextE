import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  ListMode,
  ListModeSettings,
  ListModeState,
  GalleryDetailTransitionSettings,
  GalleryDetailTransitionMode,
  GalleryDetailTransitionSettingsState,
  SecondaryListScaffold,
  ThemeConstants,
  ListRowDivider,
  GalleryTitleSettings,
  GalleryTitleState,
  HomeTabSettings,
  HomeTabAutoHideState,
  connectNavStack,
  NavStackHolder,
  connectGalleryTitle,
  connectHomeTabAutoHide,
  ThumbnailModeSettings,
  ThumbnailModeState,
  CoverBackgroundSettings,
  CoverBackgroundState,
  connectListMode,
  connectGalleryDetailTransitionSettings,
  connectThumbnailMode,
  connectCoverBackground,
  ActionAlignmentSettings,
  ActionAlignmentState,
  ActionAlignmentOption,
  connectActionAlignment,
  ReadButtonStyleSettings,
  ReadButtonStyleOption,
  ReadButtonStyleState,
  connectReadButtonStyle,
  ScreenOrientationSettings,
  ScreenOrientationOption,
  ScreenOrientationState,
  connectScreenOrientation,
  TabletLayoutSettings,
  TabletLayoutOption,
  TabletLayoutState,
  connectTabletLayout,
  MotionHandStateService,
  immersiveTitleBar,
  ThemeSettings,
  ThemeColorSettings,
  ThemeColorOption,
  ImmersiveMaterialSettings,
  ImmersiveMaterialOption,
  ImmersiveMaterialSettingsState,
  connectImmersiveMaterialSettings,
  LanguageSettings,
  ThemeDisplayState,
  connectThemeDisplay,
  ThemeColorState,
  connectThemeColor,
  LanguageState,
  connectLanguageState,
  SettingsCheckedMenuItem,
  AppColorPicker,
  AppModalScaffold,
  appSheetOptions,
} from 'shared'

/**
 * Layout settings page grounded in eros_fe LayoutSettingPage. This lane only moves existing NextE
 * layout controls into a dedicated settings child page; translation and tabbar customization are
 * owned by their dedicated settings areas.
 */
@ComponentV2
export struct LayoutSettingsPage {
  @Local listMode: ListModeState = connectListMode();
  @Local galleryDetailTransitionSettings: GalleryDetailTransitionSettingsState =
    connectGalleryDetailTransitionSettings();
  @Local galleryTitle: GalleryTitleState = connectGalleryTitle();
  @Local thumbMode: ThumbnailModeState = connectThumbnailMode();
  @Local coverBg: CoverBackgroundState = connectCoverBackground();
  @Local homeTab: HomeTabAutoHideState = connectHomeTabAutoHide();
  @Local actionAlign: ActionAlignmentState = connectActionAlignment();
  @Local readButtonStyle: ReadButtonStyleState = connectReadButtonStyle();
  @Local screenOrientation: ScreenOrientationState = connectScreenOrientation();
  @Local tabletLayout: TabletLayoutState = connectTabletLayout();
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Local themeColor: ThemeColorState = connectThemeColor();
  @Local language: LanguageState = connectLanguageState();
  @Local immersiveMaterial: ImmersiveMaterialSettingsState = connectImmersiveMaterialSettings();
  @Local colorPickerShown: boolean = false;
  @Local draftCustomColor: string = '#3377FF';
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private prevColor: string = '';
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // --- Appearance header (the "界面" page top): dark mode + theme color + language ---

  private themeModeLabel(): ResourceStr {
    if (this.themeDisplay.mode === ThemeSettings.MODE_LIGHT) {
      return $r('app.string.theme_light')
    }
    if (this.themeDisplay.mode === ThemeSettings.MODE_DARK) {
      return $r('app.string.theme_dark')
    }
    return $r('app.string.appearance_follow_system')
  }

  private themeColorLabel(): ResourceStr {
    return ThemeColorSettings.label(this.themeColor.color)
  }

  private languageModeLabel(): ResourceStr {
    if (this.language.mode === LanguageSettings.MODE_ZH_CN) {
      return $r('app.string.language_zh')
    }
    if (this.language.mode === LanguageSettings.MODE_EN) {
      return $r('app.string.language_en')
    }
    if (this.language.mode === LanguageSettings.MODE_JA) {
      return $r('app.string.language_ja')
    }
    return $r('app.string.appearance_follow_system')
  }

  private setTheme(mode: string): void {
    ThemeSettings.setMode(this.ctx(), mode)
  }

  private setThemeColor(color: string): void {
    ThemeColorSettings.setColor(this.ctx(), color)
  }

  private setImmersiveMaterial(level: string): void {
    ImmersiveMaterialSettings.setLevel(this.ctx(), level)
  }

  private immersiveMaterialLabel(): ResourceStr {
    return ImmersiveMaterialSettings.label(this.immersiveMaterial.level)
  }

  @Builder
  ImmersiveMaterialMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        ImmersiveMaterialSettings.options(),
        (option: ImmersiveMaterialOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: this.immersiveMaterial.level === option.value,
            selectAction: () => {
              select(() => {
                this.setImmersiveMaterial(option.value)
              })
            },
          })
        },
        (option: ImmersiveMaterialOption) => option.value,
      )
    }
  }

  // The 自定义 menu item opens the shared AppColorPicker in a half-modal, seeded from the current accent.
  // colorChange previews live (apply, no persist); the sheet confirm persists, its close reverts.
  private openColorPicker(): void {
    this.prevColor = this.themeColor.color
    this.draftCustomColor = ThemeColorSettings.customSeed(this.themeColor.color)
    this.colorPickerShown = true
  }

  @Builder
  ColorPickerSheet() {
    AppModalScaffold({
      title: $r('app.string.theme_color_custom'),
      confirmText: $r('app.string.common_ok'),
      closeAction: () => {
        ThemeColorSettings.apply(this.prevColor)
        this.colorPickerShown = false
      },
      confirmAction: () => {
        ThemeColorSettings.setColor(this.ctx(), this.draftCustomColor)
        this.colorPickerShown = false
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          AppColorPicker({
            title: $r('app.string.settings_theme_color'),
            color: this.draftCustomColor,
            colorChange: (value: string) => {
              this.draftCustomColor = value
              ThemeColorSettings.apply(value)
            },
          })
        }.width('100%')
      }
    }
  }

  private setLanguage(mode: string): void {
    LanguageSettings.setMode(this.ctx(), mode)
  }

  @Builder
  ThemeMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.appearance_follow_system'),
        selected: this.themeDisplay.mode === ThemeSettings.MODE_SYSTEM,
        selectAction: () => {
          select(() => {
            this.setTheme(ThemeSettings.MODE_SYSTEM)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.theme_light'),
        selected: this.themeDisplay.mode === ThemeSettings.MODE_LIGHT,
        selectAction: () => {
          select(() => {
            this.setTheme(ThemeSettings.MODE_LIGHT)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.theme_dark'),
        selected: this.themeDisplay.mode === ThemeSettings.MODE_DARK,
        selectAction: () => {
          select(() => {
            this.setTheme(ThemeSettings.MODE_DARK)
          })
        },
      })
    }
  }

  // Trailing of the 主题色 row: the CURRENT accent as a swatch, then the SAME label + arrow that
  // ConciseListRow.DropdownSuffix renders (arrowtriangle_down_fill), so this row matches the other
  // dropdown rows. currentColor() reads the @Trace so the swatch tracks the live color.
  @Builder
  ThemeColorSuffix() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Circle({ width: 16, height: 16 }).fill(ThemeColorSettings.currentColor())
      Text(this.themeColorLabel())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_tertiary')])
        .padding({ left: 4, right: 12 })
    }
    .alignItems(VerticalAlign.Center)
  }

  // V2Next ThemeColorMenu: a standard Menu of SettingsCheckedMenuItem (paintpalette_fill color dot +
  // checkmark when selected). The platform MenuItem scrolls when items overflow, so the 自定义 entry fits
  // in the same dropdown as the presets.
  @Builder
  ThemeColorMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        ThemeColorSettings.options(),
        (option: ThemeColorOption) => {
          this.ThemeColorMenuItem(option, select)
        },
        (option: ThemeColorOption) => option.value,
      )
      this.CustomColorMenuItem(select)
    }
  }

  @Builder
  ThemeColorMenuItem(option: ThemeColorOption, select: (action: () => void) => void) {
    SettingsCheckedMenuItem({
      label: option.label,
      selected: ThemeColorSettings.normalize(this.themeColor.color) === option.value,
      showColorDot: true,
      color: option.color,
      selectAction: () => {
        select(() => {
          this.setThemeColor(option.value)
        })
      },
    })
  }

  // NextE-only entry (V2Next has presets only): a 自定义 item in the SAME dropdown that opens the
  // AppColorPicker half-modal. Its dot shows the live custom color when a custom accent is active.
  @Builder
  CustomColorMenuItem(select: (action: () => void) => void) {
    SettingsCheckedMenuItem({
      label: $r('app.string.theme_color_custom'),
      selected: ThemeColorSettings.isCustom(this.themeColor.color),
      showColorDot: true,
      color: ThemeColorSettings.isCustom(this.themeColor.color)
        ? ThemeColorSettings.currentColor()
        : $r('sys.color.font_tertiary'),
      selectAction: () => {
        select(() => {
          this.openColorPicker()
        })
      },
    })
  }

  @Builder
  LanguageMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.appearance_follow_system'),
        selected: this.language.mode === LanguageSettings.MODE_SYSTEM,
        selectAction: () => {
          select(() => {
            this.setLanguage(LanguageSettings.MODE_SYSTEM)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.language_zh'),
        selected: this.language.mode === LanguageSettings.MODE_ZH_CN,
        selectAction: () => {
          select(() => {
            this.setLanguage(LanguageSettings.MODE_ZH_CN)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.language_en'),
        selected: this.language.mode === LanguageSettings.MODE_EN,
        selectAction: () => {
          select(() => {
            this.setLanguage(LanguageSettings.MODE_EN)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.language_ja'),
        selected: this.language.mode === LanguageSettings.MODE_JA,
        selectAction: () => {
          select(() => {
            this.setLanguage(LanguageSettings.MODE_JA)
          })
        },
      })
    }
  }

  private viewModeLabel(): Resource {
    if (this.listMode.mode === ListMode.COVER_WALL) {
      return $r('app.string.view_cover_wall')
    }
    if (this.listMode.mode === ListMode.WATERFALL_COMPACT) {
      return $r('app.string.view_waterfall_compact')
    }
    if (this.listMode.mode === ListMode.WATERFALL) {
      return $r('app.string.view_waterfall')
    }
    if (this.listMode.mode === ListMode.GRID) {
      return $r('app.string.view_grid')
    }
    if (this.listMode.mode === ListMode.SIMPLE_LIST) {
      return $r('app.string.view_simple')
    }
    return $r('app.string.view_list')
  }

  private setViewMode(mode: string): void {
    ListModeSettings.setMode(this.ctx(), mode)
  }

  private setFixedHeight(value: boolean): void {
    ListModeSettings.setFixedHeight(this.ctx(), value)
  }

  private galleryDetailTransitionLabel(): ResourceStr {
    if (this.galleryDetailTransitionSettings.mode === GalleryDetailTransitionMode.SYSTEM) {
      return $r('app.string.settings_gallery_detail_transition_system')
    }
    if (this.galleryDetailTransitionSettings.mode === GalleryDetailTransitionMode.COVER_EXPAND) {
      return $r('app.string.settings_gallery_detail_transition_cover_expand')
    }
    return $r('app.string.settings_gallery_detail_transition_seamless')
  }

  private setGalleryDetailTransitionMode(mode: string): void {
    GalleryDetailTransitionSettings.setMode(this.ctx(), mode)
  }

  private setReaderThumbnailTransitionEnabled(enabled: boolean): void {
    GalleryDetailTransitionSettings.setReaderThumbnailEnabled(this.ctx(), enabled)
  }

  @Builder
  GalleryDetailTransitionMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.settings_gallery_detail_transition_system'),
        selected: this.galleryDetailTransitionSettings.mode === GalleryDetailTransitionMode.SYSTEM,
        selectAction: () => {
          select(() => {
            this.setGalleryDetailTransitionMode(GalleryDetailTransitionMode.SYSTEM)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.settings_gallery_detail_transition_seamless'),
        selected: this.galleryDetailTransitionSettings.mode === GalleryDetailTransitionMode.SEAMLESS,
        selectAction: () => {
          select(() => {
            this.setGalleryDetailTransitionMode(GalleryDetailTransitionMode.SEAMLESS)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.settings_gallery_detail_transition_cover_expand'),
        selected: this.galleryDetailTransitionSettings.mode === GalleryDetailTransitionMode.COVER_EXPAND,
        selectAction: () => {
          select(() => {
            this.setGalleryDetailTransitionMode(GalleryDetailTransitionMode.COVER_EXPAND)
          })
        },
      })
    }
  }

  // --- Column-width (grid density) control: slider + live preview, only for grid-like modes ---

  private isGridLikeMode(): boolean {
    return (
      this.listMode.mode === ListMode.GRID ||
      this.listMode.mode === ListMode.WATERFALL ||
      this.listMode.mode === ListMode.WATERFALL_COMPACT ||
      this.listMode.mode === ListMode.COVER_WALL
    )
  }

  private setJapaneseTitleInGalleryPage(value: boolean): void {
    GalleryTitleSettings.setJapaneseTitleInGalleryPage(this.ctx(), value)
  }

  private setHideGalleryThumbnails(value: boolean): void {
    ThumbnailModeSettings.setHideGalleryThumbnails(this.ctx(), value)
  }

  private setHomeTabAutoHide(value: boolean): void {
    HomeTabSettings.save(this.ctx(), value)
  }

  private setBlurringOfCoverBackground(value: boolean): void {
    CoverBackgroundSettings.setBlurringOfCoverBackground(this.ctx(), value)
  }

  private actionAlignmentLabel(): ResourceStr {
    return ActionAlignmentSettings.modeLabel(
      this.actionAlign.alignmentMode,
      this.actionAlign.holdingHandSupported,
    )
  }

  private setActionAlignmentMode(mode: string): void {
    ActionAlignmentSettings.save(this.ctx(), mode)
    MotionHandStateService.applyAlignmentMode(mode)
  }

  private readButtonStyleLabel(): ResourceStr {
    return ReadButtonStyleSettings.label(this.readButtonStyle.style)
  }

  private setReadButtonStyle(style: string): void {
    ReadButtonStyleSettings.setStyle(this.ctx(), style)
  }

  private screenOrientationLabel(): ResourceStr {
    return ScreenOrientationSettings.label(this.screenOrientation.mode)
  }

  private setScreenOrientation(mode: string): void {
    ScreenOrientationSettings.setMode(this.ctx(), mode)
  }

  private tabletLayoutLabel(): ResourceStr {
    return TabletLayoutSettings.label(this.tabletLayout.mode)
  }

  private setTabletLayout(mode: string): void {
    TabletLayoutSettings.setMode(this.ctx(), mode)
  }

  private setHorizontalThumbnails(value: boolean): void {
    ThumbnailModeSettings.setHorizontalThumbnails(this.ctx(), value)
  }

  @Builder
  ViewModeMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.view_list'),
        selected: this.listMode.mode === ListMode.LIST,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.LIST)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.view_simple'),
        selected: this.listMode.mode === ListMode.SIMPLE_LIST,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.SIMPLE_LIST)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.view_grid'),
        selected: this.listMode.mode === ListMode.GRID,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.GRID)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.view_waterfall'),
        selected: this.listMode.mode === ListMode.WATERFALL,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.WATERFALL)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.view_waterfall_compact'),
        selected: this.listMode.mode === ListMode.WATERFALL_COMPACT,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.WATERFALL_COMPACT)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.view_cover_wall'),
        selected: this.listMode.mode === ListMode.COVER_WALL,
        selectAction: () => {
          select(() => {
            this.setViewMode(ListMode.COVER_WALL)
          })
        },
      })
    }
  }

  @Builder
  ActionAlignmentMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        ActionAlignmentSettings.availableOptions(this.actionAlign.holdingHandSupported),
        (option: ActionAlignmentOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: ActionAlignmentSettings.effectiveMode( this.actionAlign.alignmentMode, this.actionAlign.holdingHandSupported, ) === option.mode,
            selectAction: () => {
              select(() => {
                this.setActionAlignmentMode(option.mode)
              })
            },
          })
        },
        (option: ActionAlignmentOption) => option.mode,
      )
    }
  }

  @Builder
  ReadButtonStyleMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        ReadButtonStyleSettings.options(),
        (option: ReadButtonStyleOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: ReadButtonStyleSettings.normalizeStyle(this.readButtonStyle.style) === option.style,
            selectAction: () => {
              select(() => {
                this.setReadButtonStyle(option.style)
              })
            },
          })
        },
        (option: ReadButtonStyleOption) => option.style,
      )
    }
  }

  @Builder
  ScreenOrientationMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        ScreenOrientationSettings.options(),
        (option: ScreenOrientationOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: ScreenOrientationSettings.normalizeMode(this.screenOrientation.mode) === option.mode,
            selectAction: () => {
              select(() => {
                this.setScreenOrientation(option.mode)
              })
            },
          })
        },
        (option: ScreenOrientationOption) => option.mode,
      )
    }
  }

  @Builder
  TabletLayoutMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(
        TabletLayoutSettings.options(),
        (option: TabletLayoutOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: TabletLayoutSettings.normalizeMode(this.tabletLayout.mode) === option.mode,
            selectAction: () => {
              select(() => {
                this.setTabletLayout(option.mode)
              })
            },
          })
        },
        (option: TabletLayoutOption) => option.mode,
      )
    }
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'LayoutSettings'
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          Column() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_theme'),
                  leadingIcon: $r('sys.symbol.moon'),
                  trailingText: this.themeModeLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ThemeMenu(select)
                  },
                })
              }
              ListRowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_theme_color'),
                  leadingIcon: $r('sys.symbol.paintbrush'),
                  suffixPaddingRight: 0,
                  suffixBuilderParam: () => {
                    this.ThemeColorSuffix()
                  },
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ThemeColorMenu(select)
                  },
                })
              }
              .bindSheet($$this.colorPickerShown, this.ColorPickerSheet(), appSheetOptions({
                detents: [SheetSize.LARGE],
                showClose: false,
              }))
              ListRowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.immersive_material'),
                  leadingIcon: $r('sys.symbol.picture'),
                  trailingText: this.immersiveMaterialLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ImmersiveMaterialMenu(select)
                  },
                })
              }
              ListRowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_language'),
                  leadingIcon: $r('sys.symbol.translate'),
                  trailingText: this.languageModeLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.LanguageMenu(select)
                  },
                })
              }
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            Column() {
              ConciseListRow({
                title: $r('app.string.settings_screen_orientation'),
                leadingIcon: $r('sys.symbol.rectangle_portrait_rotate'),
                trailingText: this.screenOrientationLabel(),
                trailingDropdown: true,
                dropdownMenuEnabled: true,
                dropdownMenuBuilder: (select: (action: () => void) => void) => {
                  this.ScreenOrientationMenu(select)
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.settings_tablet_layout'),
              leadingIcon: $r('sys.symbol.rectangle_split_2x1'),
              trailingText: this.tabletLayoutLabel(),
              trailingDropdown: true,
              dropdownMenuEnabled: true,
              dropdownMenuBuilder: (select: (action: () => void) => void) => {
                this.TabletLayoutMenu(select)
              },
            })
          }
        }
        ListItem() {
          Column() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_view'),
                  leadingIcon: $r('sys.symbol.square_grid_2x2'),
                  trailingText: this.viewModeLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ViewModeMenu(select)
                  },
                })
              }
              if (this.isGridLikeMode()) {
                ListRowDivider()
                ConciseListRow({
                  title: $r('app.string.settings_column_width'),
                  subtitle: $r('app.string.settings_column_width_hint'),
                  leadingIcon: $r('sys.symbol.arrowtriangle_2_inward_square'),
                  action: () => {
                    this.stack.pushPathByName('ColumnDensity', null)
                  },
                })
              }
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_gallery_detail_transition'),
                subtitle: $r('app.string.settings_gallery_detail_transition_hint'),
                leadingIcon: $r('sys.symbol.arrowtriangle_2_inward_square'),
                trailingText: this.galleryDetailTransitionLabel(),
                trailingDropdown: true,
                dropdownMenuEnabled: true,
                dropdownMenuBuilder: (select: (action: () => void) => void) => {
                  this.GalleryDetailTransitionMenu(select)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_reader_thumbnail_transition'),
                subtitle: $r('app.string.settings_reader_thumbnail_transition_hint'),
                leadingIcon: $r('sys.symbol.picture_on_square'),
                hasSwitch: true,
                checked: this.galleryDetailTransitionSettings.readerThumbnailEnabled,
                switchAction: (value: boolean) => {
                  this.setReaderThumbnailTransitionEnabled(value)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_list_fixed_height'),
                leadingIcon: $r('sys.symbol.rectangle_grid_1x2'),
                hasSwitch: true,
                checked: this.listMode.fixedHeight,
                switchAction: (value: boolean) => {
                  this.setFixedHeight(value)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_blurring_of_cover_background'),
                subtitle: $r('app.string.settings_blurring_of_cover_background_hint'),
                leadingIcon: $r('sys.symbol.picture'),
                hasSwitch: true,
                checked: this.coverBg.blurringOfCoverBackground,
                switchAction: (value: boolean) => {
                  this.setBlurringOfCoverBackground(value)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_japanese_title_in_gallery'),
                subtitle: $r('app.string.settings_japanese_title_in_gallery_hint'),
                leadingIcon: $r('sys.symbol.textformat'),
                hasSwitch: true,
                checked: this.galleryTitle.japaneseTitleInGalleryPage,
                switchAction: (value: boolean) => {
                  this.setJapaneseTitleInGalleryPage(value)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.settings_home_tab_auto_hide'),
                subtitle: $r('app.string.settings_home_tab_auto_hide_hint'),
                leadingIcon: $r('sys.symbol.rectangle_grid_1x2'),
                hasSwitch: true,
                checked: this.homeTab.autoHide,
                switchAction: (value: boolean) => {
                  this.setHomeTabAutoHide(value)
                },
              })
              ListRowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_action_alignment'),
                  subtitle: $r('app.string.settings_action_alignment_hint'),
                  leadingIcon: $r('sys.symbol.doc_plaintext'),
                  trailingText: this.actionAlignmentLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ActionAlignmentMenu(select)
                  },
                })
              }
              ListRowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_read_button_style'),
                  subtitle: $r('app.string.settings_read_button_style_hint'),
                  leadingIcon: $r('sys.symbol.paintbrush'),
                  trailingText: this.readButtonStyleLabel(),
                  trailingDropdown: true,
                  dropdownMenuEnabled: true,
                  dropdownMenuBuilder: (select: (action: () => void) => void) => {
                    this.ReadButtonStyleMenu(select)
                  },
                })
              }
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.settings_hide_gallery_thumbnails'),
              leadingIcon: $r('sys.symbol.picture'),
              hasSwitch: true,
              checked: this.thumbMode.hideGalleryThumbnails,
              switchAction: (value: boolean) => {
                this.setHideGalleryThumbnails(value)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.settings_horizontal_thumbnails'),
              leadingIcon: $r('sys.symbol.square_fill_grid_2x2'),
              hasSwitch: true,
              checked: this.thumbMode.horizontalThumbnails,
              switchAction: (value: boolean) => {
                this.setHorizontalThumbnails(value)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.settings_thumbnail_column_width'),
              subtitle: $r('app.string.settings_thumbnail_column_width_hint'),
              leadingIcon: $r('sys.symbol.square_grid_2x2'),
              action: () => {
                this.stack.pushPathByName('ThumbnailColumnDensity', null)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_layout')))
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDestination(this.stack)
    })
  }
}
