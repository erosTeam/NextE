import { SymbolGlyphModifier } from '@kit.ArkUI'
import { ReadMode, appMenuOptions, readerModeLabel, readerModeSymbol } from 'shared'

/** The native NextE direction control is reused by both reader backends. */
@ComponentV2
export struct ReaderModeControl {
  @Param readerMode: string = ReadMode.LTR
  @Param controlEnabled: boolean = true
  @Param supportsHorizontalContinuous: boolean = false
  @Event onModeChange: (mode: string) => void = (_mode: string): void => {}
  @Event onMenuVisible: (visible: boolean) => void = (_visible: boolean): void => {}
  @Local private modeShown: boolean = false

  private choose(mode: string): void { this.onModeChange(mode); this.modeShown = false }

  private modeIconFor(mode: string): Resource {
    return readerModeSymbol(mode, $r('sys.symbol.square_and_arrow_down_1'))
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
      if (this.supportsHorizontalContinuous) {
        MenuItem({
          content: $r('app.string.read_mode_horizontal_continuous_ltr'),
          symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.HORIZONTAL_CONTINUOUS_LTR)),
          symbolEndIcon: this.readerMode === ReadMode.HORIZONTAL_CONTINUOUS_LTR
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined,
        }).onClick(() => {
          this.choose(ReadMode.HORIZONTAL_CONTINUOUS_LTR)
        })
        MenuItem({
          content: $r('app.string.read_mode_horizontal_continuous_rtl'),
          symbolStartIcon: new SymbolGlyphModifier(this.modeIconFor(ReadMode.HORIZONTAL_CONTINUOUS_RTL)),
          symbolEndIcon: this.readerMode === ReadMode.HORIZONTAL_CONTINUOUS_RTL
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined,
        }).onClick(() => {
          this.choose(ReadMode.HORIZONTAL_CONTINUOUS_RTL)
        })
      }
    }
  }

  build() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.modeIconFor(this.readerMode))
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .enabled(this.controlEnabled)
          .accessibilityText(readerModeLabel(this.readerMode))
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
