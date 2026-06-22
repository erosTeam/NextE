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
  MotionHandStateService,
  immersiveTitleBar,
  ThemeSettings,
  ThemeColorSettings,
  ThemeColorOption,
  LanguageSettings,
  ThemeDisplayState,
  connectThemeDisplay,
  ThemeColorState,
  connectThemeColor,
  LanguageState,
  connectLanguageState,
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
  @Local viewMenuShown: boolean = false;
  @Local actionAlignMenuShown: boolean = false;
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Local themeColor: ThemeColorState = connectThemeColor();
  @Local language: LanguageState = connectLanguageState();
  @Local themeMenuShown: boolean = false;
  @Local themeColorMenuShown: boolean = false;
  @Local languageMenuShown: boolean = false;
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

  // Trailing of the 主题色 row: the CURRENT accent as a swatch + its label + a dropdown chevron (V2Next
  // SettingsThemeColorDropdownRow). currentColor() reads the @Trace so the swatch tracks the live color.
  @Builder
  ThemeColorSuffix() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      Circle({ width: 16, height: 16 }).fill(ThemeColorSettings.currentColor())
      Text(this.themeColorLabel())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor([$r('sys.color.font_tertiary')])
    }.alignItems(VerticalAlign.Center)
  }

  // A plain tappable-Row column (not Menu/MenuItem): a custom MenuItem builder swallows the click, so the
  // color dots + reliable onClick live in a Column that bindMenu renders as the popup.
  @Builder
  ThemeColorMenu() {
    Column() {
      ForEach(
        ThemeColorSettings.options(),
        (option: ThemeColorOption) => {
          Row({ space: ThemeConstants.SPACE_MD }) {
            Circle({ width: 18, height: 18 }).fill(option.color)
            Text(option.label)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
            if (ThemeColorSettings.normalize(this.themeColor.color) === option.value) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontColor([$r('sys.color.font_emphasize')])
            }
          }
          .width('100%')
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            top: ThemeConstants.SPACE_SM,
            bottom: ThemeConstants.SPACE_SM,
          })
          .onClick(() => {
            this.setThemeColor(option.value)
          })
        },
        (option: ThemeColorOption) => option.value,
      )
    }
    .width(184)
    .padding({ top: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
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
  }
}
