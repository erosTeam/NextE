import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { BlurStrategy, DividerShowType, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType,
  hdsMaterial } from '@kit.UIDesignKit'
import { AppStrings } from '../i18n/AppStrings'
import { ThemeConstants } from '../theme/ThemeConstants'
import { AppPrompt } from '../utils/AppPrompt'
import { connectLayoutSafeArea, LayoutSafeAreaState } from '../state/LayoutSafeAreaState'
import { connectReaderDisplay, ReaderDisplayState } from '../state/ReaderDisplayState'

/** Reader-only variant of the Koma segmented sheet. Retain each native List and its position. */
@ComponentV2
export struct ReaderSettingsTabs {
  @BuilderParam modeItems: () => void
  @BuilderParam generalItems: () => void
  @BuilderParam filterContent: () => void
  @Local private selected: number = 0
  @Local private tabScrolled: boolean = false
  @Local private headerHeight: number = 48 + ThemeConstants.SPACE_MD + ThemeConstants.SPACE_SM
  @Local private display: ReaderDisplayState = connectReaderDisplay()
  @Local private layout: LayoutSafeAreaState = connectLayoutSafeArea()
  private filterHeight: number = 0
  private scrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller()]

  aboutToDisappear(): void { this.display.closePreview() }

  private select(index: number): void {
    if (index === this.selected) return
    this.selected = index
    this.tabScrolled = this.scrollers[index].currentOffset().yOffset > 0
    this.display.preview = null
    this.display.filterTabActive = index === 2
    this.updateHeight()
  }

  private updateHeight(): void {
    this.display.filterSheetHeight = this.selected === 2 && this.filterHeight > 0
      ? Math.ceil(this.headerHeight + this.filterHeight) : 0
  }

  @Builder
  private TabList(index: number, scroller: Scroller) {
    List({ scroller: scroller, space: ThemeConstants.SPACE_SM }) {
      ListItem() { Row().height(this.headerHeight).width('100%') }
      if (index === 0) {
        this.modeItems()
      } else if (index === 1) {
        this.generalItems()
      } else {
        ListItem() {
          Column() { this.filterContent() }
            .width('100%')
            .padding({ bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_SM })
            .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
              const height = Number(size.height)
              if (height > 0 && height !== this.filterHeight) {
                this.filterHeight = height
                this.updateHeight()
              }
            })
        }
      }
      if (index !== 2) {
        ListItem() { Row().height(this.layout.bottomAvoidHeight + ThemeConstants.SPACE_MD) }
      }
    }.width('100%').height('100%')
      .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .onDidScroll((): void => {
        if (this.selected === index) this.tabScrolled = scroller.currentOffset().yOffset > 0
      })
      .visibility(this.selected === index ? Visibility.Visible : Visibility.Hidden)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Stack() {
          this.TabList(0, this.scrollers[0])
          this.TabList(1, this.scrollers[1])
          this.TabList(2, this.scrollers[2])
        }.width('100%').height('100%')
      }
      .titleBar({
        enableComponentSafeArea: false,
        content: {
          title: { mainTitle: '' },
          divider: { showType: DividerShowType.OFF },
        },
        style: {
          systemMaterialEffect: deviceInfo.apiAvailable('6.1.0') ? {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
          } : undefined,
          blurStrategy: BlurStrategy.ENABLE,
          scrollEffectOpts: { enableScrollEffect: !this.tabScrolled, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        },
      }).titleMode(HdsNavigationTitleMode.MODAL).width('100%').height('100%')
      Column() {
        TabSegmentButtonV2({
          items: new SegmentButtonV2Items([
            { text: AppStrings.get('reader_settings_tab_mode') },
            { text: AppStrings.get('reader_settings_tab_general') },
            { text: AppStrings.get('reader_settings_tab_filters') },
          ]),
          selectedIndex: this.selected,
          enableStateAnimation: true,
          itemFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
          itemSelectedFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
          itemFontWeight: FontWeight.Medium,
          itemSelectedFontWeight: FontWeight.Bold,
          itemPadding: { top: LengthMetrics.vp(ThemeConstants.SPACE_XS), bottom: LengthMetrics.vp(ThemeConstants.SPACE_XS),
            start: LengthMetrics.vp(ThemeConstants.SPACE_MD), end: LengthMetrics.vp(ThemeConstants.SPACE_MD) },
          onItemClicked: (index: number): void => { this.select(index) },
        }).id('reader-settings-segments').width('100%').constraintSize({ minHeight: 48 })
          .padding(ThemeConstants.SPACE_XS)
      }.width('100%')
        .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD, top: ThemeConstants.SPACE_MD, bottom: ThemeConstants.SPACE_SM })
        .hitTestBehavior(HitTestMode.Transparent)
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          const height = Number(size.height)
          if (height > 0 && height !== this.headerHeight) {
            this.headerHeight = height
            this.updateHeight()
          }
        })
    }.width('100%').height('100%')
      .backgroundColor(AppPrompt.modalContentBackgroundColor($r('sys.color.ohos_id_color_sub_background')))
  }
}
