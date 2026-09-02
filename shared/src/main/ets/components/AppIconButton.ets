import { ThemeConstants } from '../theme/ThemeConstants'

/** Standard circular icon action with loading, enabled, tint, and accessibility states. */
@ComponentV2
export struct AppIconButton {
  @Param icon: Resource = $r('sys.symbol.circle');
  @Param label: Resource = $r('app.string.common_delete');
  @Param buttonSize: number = 44;
  @Param iconSize: number = ThemeConstants.FONT_SIZE_TITLE;
  @Param tint: ResourceColor = $r('sys.color.font_secondary');
  @Param loadingTint: ResourceColor = ThemeConstants.BRAND_PRIMARY;
  @Param buttonBackgroundColor: ResourceColor = Color.Transparent;
  @Param isEnabled: boolean = true;
  @Param loading: boolean = false;
  @Param stateEffect: boolean = true;
  @Param buttonOpacity: number = 1;
  @Event action?: () => void;

  build() {
    Button({ type: ButtonType.Circle, stateEffect: this.stateEffect && !this.loading }) {
      if (this.loading) {
        LoadingProgress()
          .width(this.iconSize)
          .height(this.iconSize)
          .color(this.loadingTint)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(this.iconSize)
          .fontColor([this.tint])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .width(this.buttonSize)
    .height(this.buttonSize)
    .backgroundColor(this.buttonBackgroundColor)
    .enabled(this.isEnabled && !this.loading)
    .opacity(this.buttonOpacity)
    .accessibilityText(this.label)
    .onClick(() => {
      if (this.action) {
        this.action()
      }
    })
  }
}
