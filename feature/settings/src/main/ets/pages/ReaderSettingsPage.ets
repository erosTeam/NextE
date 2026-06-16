import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  ThemeConstants,
  connectReadMode,
  ReadModeState,
  ReadMode,
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
  private scroller: Scroller = new Scroller();

  private setMode(mode: string): void {
    const ctx: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext
    ReadModeSettings.setMode(ctx, mode)
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

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        ListItem() {
          Column() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_reader_direction'),
                trailingText: this.modeLabel(),
                trailingDropdown: true,
                action: () => {
                  this.dirMenuShown = true
                },
              })
            }
          }
          .bindMenu(this.dirMenuShown, this.DirMenu, {
            placement: Placement.Bottom,
            onDisappear: () => {
              this.dirMenuShown = false
            },
          })
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_reader')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
