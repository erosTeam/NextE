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
  SecondaryListScaffold,
  ThemeConstants,
  GalleryTitleSettings,
  GalleryTitleState,
  HomeTabSettings,
  HomeTabAutoHideState,
  TagTranslationSettingsState,
  connectNavStack,
  connectGalleryTitle,
  connectHomeTabAutoHide,
  connectTagTranslationSettings,
  ThumbnailModeSettings,
  ThumbnailModeState,
  CoverBackgroundSettings,
  CoverBackgroundState,
  connectListMode,
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
 * layout controls into a dedicated settings child page; theme, locale, tag translation, and tabbar
 * customization remain separate future lanes.
 */
@ComponentV2
export struct LayoutSettingsPage {
  @Local listMode: ListModeState = connectListMode();
  @Local galleryTitle: GalleryTitleState = connectGalleryTitle();
  @Local thumbMode: ThumbnailModeState = connectThumbnailMode();
  @Local coverBg: CoverBackgroundState = connectCoverBackground();
  @Local homeTab: HomeTabAutoHideState = connectHomeTabAutoHide();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local actionAlign: ActionAlignmentState = connectActionAlignment();
  @Local readButtonStyle: ReadButtonStyleState = connectReadButtonStyle();
  @Local viewMenuShown: boolean = false;
  @Local actionAlignMenuShown: boolean = false;
  @Local readButtonStyleMenuShown: boolean = false;
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Local themeColor: ThemeColorState = connectThemeColor();
  @Local language: LanguageState = connectLanguageState();
  @Local themeMenuShown: boolean = false;
  @Local themeColorMenuShown: boolean = false;
  @Local languageMenuShown: boolean = false;
  @Local immersiveMaterial: ImmersiveMaterialSettingsState = connectImmersiveMaterialSettings();
  @Local immersiveMaterialMenuShown: boolean = false;
  @Local colorPickerShown: boolean = false;
  @Local draftCustomColor: string = '#3377FF';
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
    this.themeMenuShown = false
    ThemeSettings.setMode(this.ctx(), mode)
  }

  private setThemeColor(color: string): void {
    this.themeColorMenuShown = false
    ThemeColorSettings.setColor(this.ctx(), color)
  }

  private setImmersiveMaterial(level: string): void {
    this.immersiveMaterialMenuShown = false
    ImmersiveMaterialSettings.setLevel(this.ctx(), level)
  }

  private immersiveMaterialLabel(): ResourceStr {
    return ImmersiveMaterialSettings.label(this.immersiveMaterial.level)
  }

  @Builder
  ImmersiveMaterialMenu() {
    Menu() {
      ForEach(
        ImmersiveMaterialSettings.options(),
        (option: ImmersiveMaterialOption) => {
          MenuItem({
            content: option.label,
            symbolEndIcon:
              this.immersiveMaterial.level === option.value
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.setImmersiveMaterial(option.value)
          })
        },
        (option: ImmersiveMaterialOption) => option.value,
      )
    }
  }

  // The 自定义 menu item opens the shared AppColorPicker in a half-modal, seeded from the current accent.
  // colorChange previews live (apply, no persist); the sheet confirm persists, its close reverts.
  private openColorPicker(): void {
    this.themeColorMenuShown = false
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
    this.languageMenuShown = false
    LanguageSettings.setMode(this.ctx(), mode)
  }

  @Builder
  ThemeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.appearance_follow_system'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_SYSTEM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_SYSTEM)
        })
      MenuItem({
        content: $r('app.string.theme_light'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_LIGHT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_LIGHT)
        })
      MenuItem({
        content: $r('app.string.theme_dark'),
        symbolEndIcon:
          this.themeDisplay.mode === ThemeSettings.MODE_DARK
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setTheme(ThemeSettings.MODE_DARK)
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
    }.alignItems(VerticalAlign.Center)
  }

  // V2Next ThemeColorMenu: a standard Menu of SettingsCheckedMenuItem (paintpalette_fill color dot +
  // checkmark when selected). The platform MenuItem scrolls when items overflow, so the 自定义 entry fits
  // in the same dropdown as the presets.
  @Builder
  ThemeColorMenu() {
    Menu() {
      ForEach(
        ThemeColorSettings.options(),
        (option: ThemeColorOption) => {
          this.ThemeColorMenuItem(option)
        },
        (option: ThemeColorOption) => option.value,
      )
      this.CustomColorMenuItem()
    }
  }

  @Builder
  ThemeColorMenuItem(option: ThemeColorOption) {
    SettingsCheckedMenuItem({
      label: option.label,
      selected: ThemeColorSettings.normalize(this.themeColor.color) === option.value,
      showColorDot: true,
      color: option.color,
      selectAction: () => {
        this.setThemeColor(option.value)
      },
    })
  }

  // NextE-only entry (V2Next has presets only): a 自定义 item in the SAME dropdown that opens the
  // AppColorPicker half-modal. Its dot shows the live custom color when a custom accent is active.
  @Builder
  CustomColorMenuItem() {
    SettingsCheckedMenuItem({
      label: $r('app.string.theme_color_custom'),
      selected: ThemeColorSettings.isCustom(this.themeColor.color),
      showColorDot: true,
      color: ThemeColorSettings.isCustom(this.themeColor.color)
        ? ThemeColorSettings.currentColor()
        : $r('sys.color.font_tertiary'),
      selectAction: () => {
        this.openColorPicker()
      },
    })
  }

  @Builder
  LanguageMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.appearance_follow_system'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_SYSTEM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_SYSTEM)
        })
      MenuItem({
        content: $r('app.string.language_zh'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_ZH_CN
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_ZH_CN)
        })
      MenuItem({
        content: $r('app.string.language_en'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_EN
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_EN)
        })
      MenuItem({
        content: $r('app.string.language_ja'),
        symbolEndIcon:
          this.language.mode === LanguageSettings.MODE_JA
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setLanguage(LanguageSettings.MODE_JA)
        })
    }
  }

  private viewModeLabel(): Resource {
    if (this.listMode.mode === ListMode.COVER_WALL) {
      return $r('app.string.view_cover_wall')
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
    this.actionAlignMenuShown = false
  }

  private readButtonStyleLabel(): ResourceStr {
    return ReadButtonStyleSettings.label(this.readButtonStyle.style)
  }

  private setReadButtonStyle(style: string): void {
    ReadButtonStyleSettings.setStyle(this.ctx(), style)
    this.readButtonStyleMenuShown = false
  }

  private setHorizontalThumbnails(value: boolean): void {
    ThumbnailModeSettings.setHorizontalThumbnails(this.ctx(), value)
  }

  private tagTranslationStateText(): Resource {
    return this.tagTranslation.enabled ? $r('app.string.common_on') : $r('app.string.common_off')
  }

  @Builder
  ViewModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.view_list'),
        symbolEndIcon:
          this.listMode.mode === ListMode.LIST
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setViewMode(ListMode.LIST)
          this.viewMenuShown = false
        })
      MenuItem({
        content: $r('app.string.view_simple'),
        symbolEndIcon:
          this.listMode.mode === ListMode.SIMPLE_LIST
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setViewMode(ListMode.SIMPLE_LIST)
          this.viewMenuShown = false
        })
      MenuItem({
        content: $r('app.string.view_grid'),
        symbolEndIcon:
          this.listMode.mode === ListMode.GRID
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setViewMode(ListMode.GRID)
          this.viewMenuShown = false
        })
      MenuItem({
        content: $r('app.string.view_waterfall'),
        symbolEndIcon:
          this.listMode.mode === ListMode.WATERFALL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setViewMode(ListMode.WATERFALL)
          this.viewMenuShown = false
        })
      MenuItem({
        content: $r('app.string.view_cover_wall'),
        symbolEndIcon:
          this.listMode.mode === ListMode.COVER_WALL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      })
        .onClick(() => {
          this.setViewMode(ListMode.COVER_WALL)
          this.viewMenuShown = false
        })
    }
  }

  @Builder
  ActionAlignmentMenu() {
    Menu() {
      ForEach(
        ActionAlignmentSettings.availableOptions(this.actionAlign.holdingHandSupported),
        (option: ActionAlignmentOption) => {
          MenuItem({
            content: option.label,
            symbolEndIcon:
              ActionAlignmentSettings.effectiveMode(
                this.actionAlign.alignmentMode,
                this.actionAlign.holdingHandSupported,
              ) === option.mode
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.setActionAlignmentMode(option.mode)
          })
        },
        (option: ActionAlignmentOption) => option.mode,
      )
    }
  }

  @Builder
  ReadButtonStyleMenu() {
    Menu() {
      ForEach(
        ReadButtonStyleSettings.options(),
        (option: ReadButtonStyleOption) => {
          MenuItem({
            content: option.label,
            symbolEndIcon:
              ReadButtonStyleSettings.normalizeStyle(this.readButtonStyle.style) === option.style
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.setReadButtonStyle(option.style)
          })
        },
        (option: ReadButtonStyleOption) => option.style,
      )
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
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
                  action: () => {
                    this.themeMenuShown = true
                  },
                })
              }
              .bindMenu(this.themeMenuShown, this.ThemeMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.themeMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_theme_color'),
                  leadingIcon: $r('sys.symbol.paintbrush'),
                  suffixPaddingRight: 0,
                  suffixBuilderParam: () => {
                    this.ThemeColorSuffix()
                  },
                  action: () => {
                    this.themeColorMenuShown = true
                  },
                })
              }
              .bindMenu(this.themeColorMenuShown, this.ThemeColorMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.themeColorMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.immersive_material'),
                  leadingIcon: $r('sys.symbol.picture'),
                  trailingText: this.immersiveMaterialLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.immersiveMaterialMenuShown = true
                  },
                })
              }
              .bindMenu(this.immersiveMaterialMenuShown, this.ImmersiveMaterialMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.immersiveMaterialMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_language'),
                  leadingIcon: $r('sys.symbol.translate'),
                  trailingText: this.languageModeLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.languageMenuShown = true
                  },
                })
              }
              .bindMenu(this.languageMenuShown, this.LanguageMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.languageMenuShown = false
                },
              })
            }
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
                  action: () => {
                    this.viewMenuShown = true
                  },
                })
              }
              .bindMenu(this.viewMenuShown, this.ViewModeMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.viewMenuShown = false
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.settings_list_fixed_height'),
                leadingIcon: $r('sys.symbol.rectangle_grid_1x2'),
                hasSwitch: true,
                checked: this.listMode.fixedHeight,
                switchAction: (value: boolean) => {
                  this.setFixedHeight(value)
                },
              })
              this.rowDivider()
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
              this.rowDivider()
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
              this.rowDivider()
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
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_action_alignment'),
                  subtitle: $r('app.string.settings_action_alignment_hint'),
                  leadingIcon: $r('sys.symbol.doc_plaintext'),
                  trailingText: this.actionAlignmentLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.actionAlignMenuShown = true
                  },
                })
              }
              .bindMenu(this.actionAlignMenuShown, this.ActionAlignmentMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.actionAlignMenuShown = false
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_read_button_style'),
                  subtitle: $r('app.string.settings_read_button_style_hint'),
                  leadingIcon: $r('sys.symbol.paintbrush'),
                  trailingText: this.readButtonStyleLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.readButtonStyleMenuShown = true
                  },
                })
              }
              .bindMenu(this.readButtonStyleMenuShown, this.ReadButtonStyleMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.readButtonStyleMenuShown = false
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.tag_translation_title'),
              subtitle:
                this.tagTranslation.version.length > 0
                  ? this.tagTranslation.version
                  : $r('app.string.tag_translation_not_installed'),
              leadingIcon: $r('sys.symbol.textformat'),
              trailingText: this.tagTranslationStateText(),
              action: () => {
                this.stack.pushPathByName('TagTranslationSettings', null)
              },
            })
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
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.settings_horizontal_thumbnails'),
              leadingIcon: $r('sys.symbol.square_fill_grid_2x2'),
              hasSwitch: true,
              checked: this.thumbMode.horizontalThumbnails,
              switchAction: (value: boolean) => {
                this.setHorizontalThumbnails(value)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_layout')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.colorPickerShown, this.ColorPickerSheet(), appSheetOptions({
      detents: [SheetSize.LARGE],
      showClose: false,
    }))
  }
}
