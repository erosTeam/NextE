import { ThemeConstants } from '../theme/ThemeConstants'

/** Stable numeric page field shared by page-jump dialogs. Dialog ownership remains with the caller. */
@ComponentV2
export struct PageJumpDialogContent {
  @Param helpText: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param errorText: ResourceStr = '';
  @Param errorColor: ResourceColor = $r('sys.color.ohos_id_color_warning');
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

  private normalized(value: string): string {
    return (value || '').replace(/[^0-9]/g, '')
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.helpText)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ text: this.fieldText, placeholder: this.placeholder })
        .type(InputType.Number)
        .inputFilter('^[0-9]*$')
        .defaultFocus(true)
        .width('100%')
        .onChange((value: string) => {
          const normalized: string = this.normalized(value)
          this.fieldText = normalized
          this.onChange(normalized)
        })
      if (`${this.errorText}`.length > 0) {
        Text(this.errorText)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(this.errorColor)
          .width('100%')
      }
    }
    .width('100%')
  }
}
