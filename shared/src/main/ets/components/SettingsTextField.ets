import { ThemeConstants } from '../theme/ThemeConstants'

/** Standard full-width labeled text field used inside settings cards. */
@ComponentV2
export struct SettingsTextField {
  @Param label: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param inputType: InputType = InputType.Normal;
  @Param isEnabled: boolean = true;
  @Event onChange: (value: string) => void = () => {};
  @Local private fieldText: string = '';

  aboutToAppear(): void {
    this.fieldText = this.value
  }

  @Monitor('value')
  private onExternalValueChange(): void {
    if (this.value !== this.fieldText) {
      this.fieldText = this.value
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(this.label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fieldText, placeholder: this.placeholder })
        .type(this.inputType)
        .width('100%')
        .height(48)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
        .enabled(this.isEnabled)
        .onChange((value: string) => {
          this.fieldText = value
          this.onChange(value)
        })
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
  }
}
