import { UIContext } from '@kit.ArkUI'
import { HdsTabsController } from '@kit.UIDesignKit'
import { HdsCapsuleBarButton, ThemeConstants } from 'shared'

export const VERTICAL_READ_WIDTH: number = ThemeConstants.BUTTON_HEIGHT
const TEXT_WIDTH: number = VERTICAL_READ_WIDTH - ThemeConstants.SPACE_XS * 2
const CONTENT_GAP: number = ThemeConstants.SPACE_XS
const CONTENT_PADDING: number = ThemeConstants.SPACE_MD

export function verticalReadTextHeight(uiContext: UIContext, label: Resource): number {
  const size: SizeOptions | undefined = uiContext.getMeasureUtils().measureTextSize({
    textContent: label,
    constraintWidth: TEXT_WIDTH,
    fontSize: ThemeConstants.FONT_SIZE_BODY,
    fontWeight: FontWeight.Medium,
    textAlign: TextAlign.Center,
  })
  return Math.ceil(uiContext.px2vp((size?.height ?? 0) as number))
}

export function verticalReadHeight(uiContext: UIContext, label: Resource): number {
  const iconHeight: number = uiContext.px2vp(uiContext.fp2px(ThemeConstants.FONT_SIZE_HEADING))
  return Math.max(
    VERTICAL_READ_WIDTH + ThemeConstants.SPACE_XL + ThemeConstants.SPACE_LG,
    iconHeight + CONTENT_GAP + verticalReadTextHeight(uiContext, label) + CONTENT_PADDING * 2,
  )
}

/** Fixed thickness in both materials. Text wraps vertically at its original size, including resume pages. */
@ComponentV2
export struct GalleryVerticalReadButton {
  @Param label: Resource = $r('app.string.detail_read');
  @Param usesHdsMaterial: boolean = true;
  @Event action: () => void = () => {};
  private materialController: HdsTabsController = new HdsTabsController();

  @Builder
  private Content() {
    Column({ space: CONTENT_GAP }) {
      SymbolGlyph(this.usesHdsMaterial ? $r('sys.symbol.doc_plaintext_fill') : $r('sys.symbol.doc_plaintext'))
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontColor([this.usesHdsMaterial ? ThemeConstants.BRAND_PRIMARY : ThemeConstants.TEXT_ON_BRAND])
      Text(this.label)
        .width(TEXT_WIDTH)
        .height(verticalReadTextHeight(this.getUIContext(), this.label))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.usesHdsMaterial ? ThemeConstants.BRAND_PRIMARY : ThemeConstants.TEXT_ON_BRAND)
        .textAlign(TextAlign.Center)
    }
    .width(VERTICAL_READ_WIDTH)
    .height(verticalReadHeight(this.getUIContext(), this.label))
    .justifyContent(FlexAlign.Center)
  }

  build() {
    if (this.usesHdsMaterial) {
      HdsCapsuleBarButton({
        controller: this.materialController,
        barWidth: VERTICAL_READ_WIDTH,
        barHeight: verticalReadHeight(this.getUIContext(), this.label),
        activityPadding: ThemeConstants.SPACE_LG,
        barBottomMargin: ThemeConstants.SPACE_LG,
        onButtonClick: this.action,
      }) {
        Column() { this.Content() }
          .translate({ y: -ThemeConstants.SPACE_XS })
      }
    } else {
      Button({ type: ButtonType.Capsule }) { this.Content() }
        .width(VERTICAL_READ_WIDTH)
        .height(verticalReadHeight(this.getUIContext(), this.label))
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .shadow(ShadowStyle.OUTER_DEFAULT_MD)
        .accessibilityText(this.label)
        .onClick(() => { this.action() })
    }
  }
}
