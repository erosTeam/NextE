import { HdsNavigation, HdsNavigationTitleMode, IconStyleMode } from '@kit.UIDesignKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'

@ComponentV2
export struct AppModalScaffold {
  @BuilderParam content: () => void
  @Param title: ResourceStr = ''
  @Param includeKeyboardPadding: boolean = false
  @Param enableComponentSafeArea: boolean = true
  @Param contentBackgroundColor: ResourceColor = $r('sys.color.ohos_id_color_sub_background')
  @Param closeInMenu: boolean = false
  @Param closeIcon: Resource = $r('sys.symbol.xmark')
  @Param footerReserveHeight: number = 0
  @Param showFooterActionOne: boolean = false
  @Param footerActionOneIcon: Resource = $r('sys.symbol.checkmark')
  @Param footerActionOneText: ResourceStr = ''
  @Param footerActionOneColor: ResourceColor = $r('sys.color.font_secondary')
  @Param footerActionOneEnabled: boolean = true
  @Param showFooterActionTwo: boolean = false
  @Param footerActionTwoIcon: Resource = $r('sys.symbol.checkmark')
  @Param footerActionTwoText: ResourceStr = ''
  @Param footerActionTwoColor: ResourceColor = $r('sys.color.font_secondary')
  @Param footerActionTwoEnabled: boolean = true
  @Param showFooterActionThree: boolean = false
  @Param footerActionThreeIcon: Resource = $r('sys.symbol.checkmark')
  @Param footerActionThreeText: ResourceStr = ''
  @Param footerActionThreeColor: ResourceColor = $r('sys.color.font_secondary')
  @Param footerActionThreeEnabled: boolean = true
  @Param confirmIcon: Resource = $r('sys.symbol.checkmark')
  @Param confirmText: ResourceStr = ''
  @Param showConfirmAction: boolean = true
  @Param confirmEnabled: boolean = true
  @Param confirmLoading: boolean = false
  @Param secondaryIcon: Resource = $r('sys.symbol.trash')
  @Param secondaryText: ResourceStr = ''
  @Param showSecondaryAction: boolean = false
  @Param secondaryEnabled: boolean = true
  @Event closeAction?: () => void
  @Event secondaryAction?: () => void
  @Event confirmAction?: () => void
  @Event footerActionOne?: () => void
  @Event footerActionTwo?: () => void
  @Event footerActionThree?: () => void
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  scroller: Scroller = new Scroller()

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsNavigation() {
        List({ space: ThemeConstants.SPACE_SM, scroller: this.scroller }) {
          this.content()
          ListItem() {
            Column() {
              Blank()
                .height(this.layout.bottomAvoidHeight + ThemeConstants.SPACE_MD + this.keyboardPadding() +
                  this.footerReserveHeight)
            }
            .width('100%')
          }
        }
        .height('100%')
        .width('100%')
        .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
      .titleBar({
        enableComponentSafeArea: this.enableComponentSafeArea,
        content: {
          title: {
            mainTitle: this.title,
          },
          subIcon: this.closeInMenu ? undefined : {
            content: {
              label: 'modal_close',
              icon: this.closeIcon,
              isEnabled: !this.confirmLoading,
              type: IconStyleMode.SMALL,
              action: () => {
                if (this.closeAction) {
                  this.closeAction()
                }
              },
            },
          },
          menu: {
            value: this.closeInMenu ? [{
              content: {
                label: 'modal_close',
                icon: this.closeIcon,
                isEnabled: !this.confirmLoading,
                type: IconStyleMode.SMALL,
                action: () => {
                  if (this.closeAction) {
                    this.closeAction()
                  }
                },
              },
            }] : this.showSecondaryAction && this.showConfirmAction ? [{
              content: {
                label: this.secondaryText,
                icon: this.secondaryIcon,
                isEnabled: this.secondaryEnabled && !this.confirmLoading,
                type: IconStyleMode.SMALL,
                action: () => {
                  if (this.secondaryAction) {
                    this.secondaryAction()
                  }
                },
              },
            }, {
              content: {
                label: this.confirmText,
                icon: this.confirmIcon,
                isEnabled: this.confirmEnabled && !this.confirmLoading,
                type: IconStyleMode.SMALL,
                action: () => {
                  if (this.confirmAction) {
                    this.confirmAction()
                  }
                },
              },
            }] : this.showSecondaryAction ? [{
              content: {
                label: this.secondaryText,
                icon: this.secondaryIcon,
                isEnabled: this.secondaryEnabled && !this.confirmLoading,
                type: IconStyleMode.SMALL,
                action: () => {
                  if (this.secondaryAction) {
                    this.secondaryAction()
                  }
                },
              },
            }] : this.showConfirmAction ? [{
              content: {
                label: this.confirmText,
                icon: this.confirmIcon,
                isEnabled: this.confirmEnabled && !this.confirmLoading,
                type: IconStyleMode.SMALL,
                action: () => {
                  if (this.confirmAction) {
                    this.confirmAction()
                  }
                },
              },
            }] : [],
            maxCount: this.actionCount(),
          },
        },
      })
      .titleMode(HdsNavigationTitleMode.MODAL)
      .bindToScrollable([this.scroller])
      .height('100%')
      .width('100%')

      if (this.hasFooterActions()) {
        Column() {
          Row({ space: ThemeConstants.SPACE_SM }) {
            if (this.showFooterActionOne) {
              this.FooterAction(this.footerActionOneText, this.footerActionOneIcon,
                this.footerActionOneColor, this.footerActionOneEnabled, () => {
                  if (this.footerActionOne) {
                    this.footerActionOne()
                  }
                })
            }
            if (this.showFooterActionTwo) {
              this.FooterAction(this.footerActionTwoText, this.footerActionTwoIcon,
                this.footerActionTwoColor, this.footerActionTwoEnabled, () => {
                  if (this.footerActionTwo) {
                    this.footerActionTwo()
                  }
                })
            }
            if (this.showFooterActionThree) {
              this.FooterAction(this.footerActionThreeText, this.footerActionThreeIcon,
                this.footerActionThreeColor, this.footerActionThreeEnabled, () => {
                  if (this.footerActionThree) {
                    this.footerActionThree()
                  }
                })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          top: ThemeConstants.SPACE_SM,
          bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_MD,
        })
        .backgroundColor(this.contentBackgroundColor)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.contentBackgroundColor)
  }

  private keyboardPadding(): number {
    if (!this.includeKeyboardPadding) {
      return 0
    }
    return Math.max(0, this.layout.keyboardHeight)
  }

  private hasFooterActions(): boolean {
    return this.showFooterActionOne || this.showFooterActionTwo || this.showFooterActionThree
  }

  @Builder
  private FooterAction(label: ResourceStr, icon: Resource, tint: ResourceColor, enabled: boolean, action: () => void) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([tint])
      }
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width(44)
      .height(44)
      .enabled(enabled)
      .onClick(action)

      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor(tint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
  }

  private actionCount(): number {
    let count: number = 0
    if (this.closeInMenu) {
      count++
    }
    if (this.showSecondaryAction) {
      count++
    }
    if (this.showConfirmAction) {
      count++
    }
    return count
  }
}
