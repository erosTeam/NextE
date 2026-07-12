import {
  HdsListItemCard,
  PrefixCustomBuilder,
  PrefixImage,
  SuffixCustomBuilder,
  SuffixSwitch,
  SuffixText,
  SuffixTextAndArrow,
} from '@kit.UIDesignKit'
import { ImageModifier, TextModifier } from '@kit.ArkUI'
import { ThemeConstants } from '../theme/ThemeConstants'

/**
 * One native HDS list row (ported from V2Next, atop `HdsListItemCard`). Drives the title /
 * subtitle / trailing text / chevron / switch / counter / leading-image / custom-builder
 * variants from @Param flags, so settings, favorites, and detail rows share one component
 * instead of each page hand-rolling a Row. Adaptations vs V2Next: NextE has no in-app locale
 * override, so resources render directly (no LanguageState passthrough); and the leading
 * image is normalized inline (EH urls are already absolute https) instead of via ImageUtils.
 */
@ComponentV2
export struct ConciseListRow {
  @Param title: ResourceStr = '';
  @Param subtitle: ResourceStr = '';
  @Param subtitleMaxLines: number = 2;
  @Param trailingText: ResourceStr = '';
  @Param leadingImageUrl: string = '';
  // Leading SymbolGlyph icon (e.g. $r('sys.symbol.person')) — eros_fe-style icon-led settings rows.
  @Param leadingIcon: Resource | undefined = undefined;
  @Param count: number = -1;
  @Param destructive: boolean = false;
  @Param showChevron: boolean = true;
  @Param trailingDropdown: boolean = false;
  @Param hasSwitch: boolean = false;
  @Param hasCounter: boolean = false;
  @Param counterValue: string = '';
  @Param counterDecreaseEnabled: boolean = true;
  @Param counterIncreaseEnabled: boolean = true;
  @Param checked: boolean = false;
  // A selected row is a navigational location marker, distinct from a switch's checked state.
  @Param selected: boolean = false;
  @Param isEnabled: boolean = true;
  @Param primaryColor: ResourceColor | undefined = undefined;
  @Param secondaryColor: ResourceColor | undefined = undefined;
  @Param suffixPaddingRight: Length = ThemeConstants.SPACE_MD;
  @Event action?: () => void;
  @BuilderParam suffixBuilderParam?: () => void;
  @BuilderParam prefixBuilderParam?: () => void;
  @Event switchAction?: (value: boolean) => void;
  @Event counterDecreaseAction?: () => void;
  @Event counterIncreaseAction?: () => void;

  // A leading icon or image supplies the leading inset, so the title needs no extra text-indent.
  private hasLeading(): boolean {
    return this.leadingImageUrl.length > 0 || this.leadingIcon !== undefined
  }

  private primaryTextModifier(): TextModifier {
    return new TextModifier()
      .textIndent(this.hasLeading() ? undefined : ThemeConstants.LIST_ROW_TEXT_INDENT)
      .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
      .fontWeight(FontWeight.Regular)
      .fontColor(this.primaryColor ?? (this.destructive ? Color.Red : $r('sys.color.font_primary')))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  private secondaryTextModifier(): TextModifier {
    return new TextModifier()
      .textIndent(this.hasLeading() ? undefined : ThemeConstants.LIST_ROW_TEXT_INDENT)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(this.secondaryColor ?? $r('sys.color.font_secondary'))
      .maxLines(this.subtitleMaxLines)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  private trailingTextModifier(): TextModifier {
    return new TextModifier()
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(this.secondaryColor ?? $r('sys.color.font_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  // EH images are already absolute https; only normalize protocol-relative ('//') urls.
  private normalizeImageUrl(path: string): string {
    if (path.length === 0) {
      return ''
    }
    if (path.startsWith('//')) {
      return `https:${path}`
    }
    return path
  }

  @Builder
  private WrappedSuffixBuilder() {
    Row() {
      if (this.suffixBuilderParam) {
        this.suffixBuilderParam()
      }
    }
    .padding({ left: ThemeConstants.SPACE_SM, right: this.suffixPaddingRight })
  }

  @Builder
  private WrappedPrefixBuilder() {
    Row() {
      if (this.prefixBuilderParam) {
        this.prefixBuilderParam()
      }
    }
    .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
  }

  private suffixItem():
    | SuffixTextAndArrow
    | SuffixText
    | SuffixCustomBuilder
    | SuffixSwitch
    | undefined {
    if (this.suffixBuilderParam) {
      return new SuffixCustomBuilder(() => {
        this.WrappedSuffixBuilder()
      })
    }

    if (this.hasSwitch) {
      return new SuffixSwitch({
        isCheck: this.checked,
        selectColor: ThemeConstants.BRAND_PRIMARY,
        enable: this.isEnabled,
        onChange: (value: boolean) => {
          if (this.isEnabled && this.switchAction) {
            this.switchAction(value)
          }
        },
      })
    }
    if (this.hasCounter) {
      return new SuffixCustomBuilder(() => {
        this.CounterSuffix()
      })
    }
    if (this.count >= 0) {
      return new SuffixTextAndArrow({ text: `${this.count}` }, { color: Color.Gray })
    }
    if (this.trailingText) {
      if (this.trailingDropdown) {
        return new SuffixCustomBuilder(() => {
          this.DropdownSuffix()
        })
      }
      if (this.showChevron) {
        return new SuffixTextAndArrow(
          {
            text: this.trailingText,
            modifier: this.trailingTextModifier(),
          },
          { color: Color.Gray },
        )
      }
      return new SuffixText({
        text: this.trailingText,
        modifier: this.trailingTextModifier(),
      })
    }
    if (this.showChevron) {
      return new SuffixTextAndArrow({ text: `` }, { color: Color.Gray })
    }
    return undefined
  }

  @Builder
  private CounterSuffix() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      this.CounterButton('−', this.counterDecreaseEnabled, () => {
        if (this.counterDecreaseAction) {
          this.counterDecreaseAction()
        }
      })
      Text(this.counterValue)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.secondaryColor ?? $r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width(44)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      this.CounterButton('+', this.counterIncreaseEnabled, () => {
        if (this.counterIncreaseAction) {
          this.counterIncreaseAction()
        }
      })
    }
    .alignItems(VerticalAlign.Center)
    .opacity(this.isEnabled ? 1.0 : 0.45)
    .padding({ right: ThemeConstants.SPACE_MD })
  }

  @Builder
  private CounterButton(label: string, enabled: boolean, action: () => void) {
    Button() {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .borderRadius(ThemeConstants.RADIUS_ROUND)
    .width(32)
    .height(30)
    .enabled(enabled && this.isEnabled)
    .opacity(enabled ? 1.0 : 0.45)
    .onClick(action)
  }

  @Builder
  private DropdownSuffix() {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(this.trailingText)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.secondaryColor ?? $r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_tertiary')])
        .padding({ left: 4, right: 12 })
    }.alignItems(VerticalAlign.Center)
  }

  @Builder
  private IconPrefix() {
    Row() {
      if (this.leadingIcon !== undefined) {
        SymbolGlyph(this.leadingIcon)
          .fontSize(22)
          .fontColor([
            this.destructive ? Color.Red : (this.secondaryColor ?? $r('sys.color.font_secondary')),
          ])
      }
    }
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_SM })
  }

  private prefixItem(): PrefixImage | PrefixCustomBuilder | undefined {
    if (this.prefixBuilderParam) {
      return new PrefixCustomBuilder(() => {
        this.WrappedPrefixBuilder()
      })
    }
    if (this.leadingIcon !== undefined) {
      return new PrefixCustomBuilder(() => {
        this.IconPrefix()
      })
    }

    const imageUrl: string = this.normalizeImageUrl(this.leadingImageUrl)
    if (imageUrl.length > 0) {
      return new PrefixImage({
        image: imageUrl,
        modifier: new ImageModifier().alt($r('sys.media.ohos_app_icon')),
      })
    }
    return undefined
  }

  @Builder
  private RowContent() {
    HdsListItemCard({
      textItem: {
        primaryText: {
          text: this.title,
          modifier: this.primaryTextModifier(),
        },
        secondaryText: this.subtitle
          ? {
              text: this.subtitle,
              modifier: this.secondaryTextModifier(),
            }
          : undefined,
      },
      cardPrefixMargin: 0,
      cardSuffixMargin: 0,
      prefixItem: this.prefixItem(),
      suffixItem: this.suffixItem(),
      cardBackgroundColor: this.selected
        ? $r('app.color.navigation_item_selected')
        : Color.Transparent,
      cardBorderRadius: ThemeConstants.LIST_ROW_RADIUS,
      hoverBorderRadius: ThemeConstants.LIST_ROW_RADIUS,
      enable: this.hasSwitch ? true : this.isEnabled,
      accessibilityOptions: {
        accessibilitySelected: this.selected,
      },
      onClick: () => {
        if (this.isEnabled && this.action) {
          this.action()
        }
      },
    })
  }

  build() {
    Column() {
      this.RowContent()
    }
    .width('100%')
    .opacity(this.isEnabled ? 1.0 : 0.4)
  }
}
