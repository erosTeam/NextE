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
  @Param closeIcon: Resource = $r('sys.symbol.xmark')
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
  layout: LayoutSafeAreaState = connectLayoutSafeArea()
  scroller: Scroller = new Scroller()

  build() {
    HdsNavigation() {
      List({ space: ThemeConstants.SPACE_SM, scroller: this.scroller }) {
        this.content()
        ListItem() {
          Column() {
            Blank()
              .height(this.layout.bottomAvoidHeight + ThemeConstants.SPACE_MD + this.keyboardPadding())
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
        subIcon: {
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
          value: this.showSecondaryAction && this.showConfirmAction ? [{
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

  private actionCount(): number {
    let count: number = 0
    if (this.showSecondaryAction) {
      count++
    }
    if (this.showConfirmAction) {
      count++
    }
    return count
  }
}
