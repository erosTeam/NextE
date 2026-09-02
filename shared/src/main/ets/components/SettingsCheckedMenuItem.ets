import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * A standard MenuItem with an optional leading color dot (a tinted paintpalette_fill) and a trailing
 * checkmark when selected. Ported verbatim from V2Next so settings dropdown menus (theme color, etc.) use
 * the platform MenuItem — which scrolls when items overflow — instead of a hand-rolled list.
 */
@ComponentV2
export struct SettingsCheckedMenuItem {
  @Param label: ResourceStr = '';
  @Param selected: boolean = false;
  @Param showColorDot: boolean = false;
  @Param color: ResourceColor = Color.Transparent;
  @Param symbolStartIcon: SymbolGlyphModifier | undefined = undefined;
  @Param isEnabled: boolean = true;
  @Event selectAction?: () => void;

  build() {
    MenuItem({
      content: this.label,
      symbolStartIcon: this.symbolStartIcon !== undefined
        ? this.symbolStartIcon
        : this.showColorDot
          ? new SymbolGlyphModifier($r('sys.symbol.paintpalette_fill'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor([this.color])
          : undefined,
      symbolEndIcon: this.selected
        ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
        : undefined,
    })
    .enabled(this.isEnabled)
    .onClick(() => {
      if (this.isEnabled && this.selectAction) {
        this.selectAction()
      }
    })
  }
}
