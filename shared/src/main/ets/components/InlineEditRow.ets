import { ThemeConstants } from '../theme/ThemeConstants'
import { ConciseListRow } from './ConciseListRow'

/**
 * Label + inline editable text field on a standard ConciseListRow (title left, value right).
 *
 * The editable node is a direct, stable child of this component. Never place it inside
 * ConciseListRow.suffixBuilderParam: HDS materializes that slot through SuffixCustomBuilder, whose content can
 * be replaced when the bound text changes and therefore drop the TextInput focus/IME session.
 */
@ComponentV2
export struct InlineEditRow {
  @Param title: ResourceStr = '';
  @Param subtitle: ResourceStr = '';
  @Param subtitleMaxLines: number = 2;
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param numeric: boolean = false;
  @Param isEnabled: boolean = true;
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

  private fieldWidth(): number {
    return this.numeric ? 120 : 200
  }

  private reservedSuffixWidth(): number {
    return this.fieldWidth() + (this.suffix.length > 0 ? 32 : 0)
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      ConciseListRow({
        title: this.title,
        subtitle: this.subtitle,
        subtitleMaxLines: this.subtitleMaxLines,
        showChevron: false,
        isEnabled: this.isEnabled,
        suffixPaddingRight: ThemeConstants.SPACE_MD,
        suffixBuilderParam: () => {
          this.SuffixReservation()
        },
      })
      this.InputOverlay()
    }
    .width('100%')
  }

  @Builder
  private SuffixReservation() {
    Blank()
      .width(this.reservedSuffixWidth())
  }

  @Builder
  private InputOverlay() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      TextInput({ text: this.fieldText, placeholder: this.placeholder })
        .type(this.numeric ? InputType.Number : InputType.Normal)
        .textAlign(TextAlign.End)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .backgroundColor(Color.Transparent)
        .height(40)
        .enabled(this.isEnabled)
        .padding({ top: 0, bottom: 0, left: 0, right: 2 })
        .width(this.fieldWidth())
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
    .padding({ right: ThemeConstants.SPACE_MD })
    .opacity(this.isEnabled ? 1.0 : 0.4)
  }
}
