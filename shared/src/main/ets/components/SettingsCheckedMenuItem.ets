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
  @Event selectAction?: () => void;

  build() {
    MenuItem({
      content: this.label,
      symbolStartIcon: this.showColorDot
        ? new SymbolGlyphModifier($r('sys.symbol.paintpalette_fill'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor([this.color])
        : undefined,
      symbolEndIcon: this.selected
        ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
        : undefined,
    }).onClick(() => {
      if (this.selectAction) {
        this.selectAction()
      }
    })
  }
}
