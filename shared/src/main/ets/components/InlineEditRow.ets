import { ThemeConstants } from '../theme/ThemeConstants'
import { ConciseListRow } from './ConciseListRow'

/**
 * Label + inline editable text field on a standard ConciseListRow (title left, value right). The ONE shared
 * inline-text settings row — used by the EH config editor, the custom-tab editor, etc. (don't hand-roll a
 * per-page copy). Two correctness points baked in:
 *  - mirror pattern: the external value seeds a private @Local once and build() reads ONLY the @Local, so
 *    typing never re-mounts the field (no soft-keyboard flap);
 *  - an explicit field height, so the text caret isn't clipped top/bottom (the bug in the old per-page copies
 *    that used padding(0) with no height).
 */
@ComponentV2
export struct InlineEditRow {
  @Param title: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param numeric: boolean = false;
  // Optional trailing unit text after the field (e.g. a "px" suffix).
  @Param suffix: string = '';
  @Event onChange: (value: string) => void = () => {};
  @Local private fieldText: string = '';

  aboutToAppear(): void {
    this.fieldText = this.value
  }

  @Monitor('value')
  onExternalChange(): void {
    if (this.value !== this.fieldText) {
      this.fieldText = this.value
    }
  }

  build() {
    ConciseListRow({
      title: this.title,
      showChevron: false,
      suffixPaddingRight: ThemeConstants.SPACE_MD,
      suffixBuilderParam: () => {
        this.InputSuffix()
      },
    })
  }

  @Builder
  InputSuffix() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      TextInput({ text: this.fieldText, placeholder: this.placeholder })
        .type(this.numeric ? InputType.Number : InputType.Normal)
        .textAlign(TextAlign.End)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor(Color.Transparent)
        .height(40)
        .padding({ top: 0, bottom: 0, left: 0, right: 2 })
        .width(this.numeric ? 120 : 200)
        .onChange((v: string) => {
          this.fieldText = v
          this.onChange(v)
        })
      if (this.suffix.length > 0) {
        Text(this.suffix)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .alignItems(VerticalAlign.Center)
  }
}
