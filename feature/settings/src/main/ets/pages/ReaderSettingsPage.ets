import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  ThemeConstants,
  connectReadMode,
  ReadModeState,
  ReadMode,
  ReadColumnMode,
  ReadModeSettings,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  AppStrings,
  immersiveTitleBar,
} from 'shared'

/**
 * Reader settings (eros_fe 阅读 settings category). Page-turn DIRECTION is a native dropdown picker:
 * the row shows the current mode (左→右 / 右→左 / 竖向) with a chevron, and tapping it opens a native
 * HDS `Menu` with the three options and a `checkmark` on the active one — the same native idiom as the
 * favorites order picker (V2Next TopicDetailComponents bindMenu). eros_fe presents direction as an
 * action sheet, NOT inline checkmark rows; this is the native equivalent, not a hand-rolled tick.
 */
@ComponentV2
export struct ReaderSettingsPage {
  @Local readMode: ReadModeState = connectReadMode();
  @Local dirMenuShown: boolean = false;
  @Local columnMenuShown: boolean = false;
  @Local autoPageMenuShown: boolean = false;
  private scroller: Scroller = new Scroller();

  private setMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, mode)
  }

  private setColumnMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setColumnMode(ctx, mode)
  }

  private setAutoPageSeconds(seconds: number): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setAutoPageSeconds(ctx, seconds)
  }

  private setVolumeKeyTurn(enabled: boolean): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setVolumeKeyTurn(ctx, enabled)
  }

  private modeLabel(): Resource {
    if (this.readMode.mode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readMode.mode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private columnModeLabel(): Resource {
    if (this.readMode.columnMode === ReadColumnMode.ODD_LEFT) {
      return $r('app.string.read_double_page_a')
    }
    if (this.readMode.columnMode === ReadColumnMode.EVEN_LEFT) {
      return $r('app.string.read_double_page_b')
    }
    return $r('app.string.common_off')
  }

  private autoPageLabel(): string {
    return `${this.readMode.autoPageSeconds}s`
  }

  // Native direction picker: a framework Menu/MenuItem with a checkmark symbolEndIcon on the active
  // mode (V2Next TopicDetailComponents.ets:192-227). Selecting one persists via ReadModeSettings + closes.
  @Builder
  DirMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.read_mode_ltr'),
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
        symbolEndIcon:
          this.readMode.mode === ReadMode.RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setMode(ReadMode.RTL)
        this.dirMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_mode_vertical'),
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
  ColumnMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.common_off'),
        symbolEndIcon:
          this.readMode.columnMode === ReadColumnMode.SINGLE
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setColumnMode(ReadColumnMode.SINGLE)
        this.columnMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_double_page_a'),
        symbolEndIcon:
          this.readMode.columnMode === ReadColumnMode.ODD_LEFT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setColumnMode(ReadColumnMode.ODD_LEFT)
        this.columnMenuShown = false
      })
      MenuItem({
        content: $r('app.string.read_double_page_b'),
        symbolEndIcon:
          this.readMode.columnMode === ReadColumnMode.EVEN_LEFT
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.setColumnMode(ReadColumnMode.EVEN_LEFT)
        this.columnMenuShown = false
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
              Column() {
                ConciseListRow({
                  title: $r('app.string.settings_reader_double_page'),
                  trailingText: this.columnModeLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.columnMenuShown = true
                  },
                })
              }
              .bindMenu(this.columnMenuShown, this.ColumnMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.columnMenuShown = false
                },
              })
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
              ConciseListRow({
                title: $r('app.string.settings_reader_volume_key'),
                subtitle: $r('app.string.settings_reader_volume_key_hint'),
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
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_reader')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
