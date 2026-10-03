import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ReadMode, appMenuOptions } from 'shared'

/** The native NextE direction control is reused by both reader backends. */
@ComponentV2
export struct ReaderModeControl {
  @Param readerMode: string = ReadMode.LTR
  @Param controlEnabled: boolean = true
  @Event onModeChange: (mode: string) => void = (_mode: string): void => {}
  @Event onMenuVisible: (visible: boolean) => void = (_visible: boolean): void => {}
  @Local private modeShown: boolean = false

  private choose(mode: string): void { this.onModeChange(mode); this.modeShown = false }

  private modeLabel(): Resource {
    if (this.readerMode === ReadMode.RTL) {
      return $r('app.string.read_mode_rtl')
    }
    if (this.readerMode === ReadMode.TOP_TO_BOTTOM) {
      return $r('app.string.read_mode_ttb')
    }
    if (this.readerMode === ReadMode.VERTICAL) {
      return $r('app.string.read_mode_vertical')
    }
    return $r('app.string.read_mode_ltr')
  }

  private modeIconFor(mode: string): Resource {
    if (mode === ReadMode.RTL) {
      return $r('sys.symbol.arrow_left_and_square')
    }
    if (mode === ReadMode.TOP_TO_BOTTOM) {
      return $r('sys.symbol.square_and_arrow_down_1')
    }
    if (mode === ReadMode.VERTICAL) {
      return $r('sys.symbol.scroll_vertical')
    }
    return $r('sys.symbol.arrow_right_and_square')
  }

  private modeIcon(): Resource {
    return this.modeIconFor(this.readerMode)
  }

  @Builder
  ModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.read_mode_ltr'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.LTR)),
        symbolEndIcon:
          this.readerMode === ReadMode.LTR
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.choose(ReadMode.LTR)
      })
      MenuItem({
        content: $r('app.string.read_mode_rtl'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.RTL)),
        symbolEndIcon:
          this.readerMode === ReadMode.RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.choose(ReadMode.RTL)
      })
      MenuItem({
        content: $r('app.string.read_mode_ttb'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.TOP_TO_BOTTOM)),
        symbolEndIcon:
          this.readerMode === ReadMode.TOP_TO_BOTTOM
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.choose(ReadMode.TOP_TO_BOTTOM)
      })
      MenuItem({
        content: $r('app.string.read_mode_vertical'),
        symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.VERTICAL)),
        symbolEndIcon:
          this.readerMode === ReadMode.VERTICAL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
      }).onClick(() => {
        this.choose(ReadMode.VERTICAL)
      })
    }
  }

  build() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.modeIcon())
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .enabled(this.controlEnabled)
          .accessibilityText(this.modeLabel())
          .onClick(() => {
            this.modeShown = true
          })
          .bindMenu(this.modeShown, this.ModeMenu, appMenuOptions({
            placement: Placement.TopRight,
            aboutToAppear: (): void => { this.onMenuVisible(true) },
            onDisappear: () => {
              this.modeShown = false
              this.onMenuVisible(false)
            },
          }))
  }
}
