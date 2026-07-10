import { HdsNavDestination } from '@kit.UIDesignKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  AppSearchField,
  AppStrings,
  BasicDataSource,
  LayoutSafeAreaState,
  ThemeConstants,
  connectLayoutSafeArea,
  immersiveTitleBar,
} from 'shared'
import { SystemSymbolEntry, createSystemSymbolCatalog } from '../generated/SystemSymbolCatalog'

@ComponentV2
export struct SystemSymbolBrowserPage {
  @Local private keyword: string = ''
  @Local private resultCount: number = 0
  private layout: LayoutSafeAreaState = connectLayoutSafeArea()
  private allSymbols: SystemSymbolEntry[] = []
  private dataSource: BasicDataSource<SystemSymbolEntry> = new BasicDataSource<SystemSymbolEntry>()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    if (this.allSymbols.length === 0) {
      this.allSymbols = createSystemSymbolCatalog()
    }
    this.applyFilter('')
  }

  private applyFilter(value: string): void {
    this.keyword = value
    const query: string = value.trim().toLowerCase()
    const visible: SystemSymbolEntry[] = query.length === 0
      ? this.allSymbols
      : this.allSymbols.filter((item: SystemSymbolEntry) =>
        item.name.toLowerCase().includes(query),
      )
    this.dataSource.setData(visible)
    this.resultCount = visible.length
  }

  private copyResourceName(item: SystemSymbolEntry): void {
    const resourceName: string = item.resourceName()
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, resourceName)
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.toast(AppStrings.get('system_symbol_browser_copied').replace('%s', resourceName))
    } catch (_error) {
      this.toast($r('app.string.system_symbol_browser_copy_failed'))
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction()
      .openToast({ message: message })
      .catch((_error: Error) => {})
  }

  private resultSummary(): string {
    return AppStrings.get('system_symbol_browser_count').replace('%s', this.resultCount.toString())
  }

  @Builder
  private SymbolCard(item: SystemSymbolEntry) {
    Column({ space: ThemeConstants.SPACE_SM }) {
      SymbolGlyph(item.symbol)
        .fontSize(ThemeConstants.SYSTEM_SYMBOL_GLYPH_SIZE)
        .fontColor([$r('sys.color.font_primary')])
      Text(item.name)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .height(ThemeConstants.SYSTEM_SYMBOL_CARD_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .padding(ThemeConstants.SPACE_SM)
    .borderRadius(ThemeConstants.GALLERY_GRID_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityText(item.resourceName())
    .onClick(() => {
      this.copyResourceName(item)
    })
  }

  build() {
    HdsNavDestination() {
      Column() {
        Blank().height(this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT)
        Column({ space: ThemeConstants.SPACE_SM }) {
          AppSearchField({
            text: this.keyword,
            placeholder: $r('app.string.system_symbol_browser_search_hint'),
            onTextChange: (value: string) => {
              this.applyFilter(value)
            },
          })
          Text(this.resultSummary())
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          bottom: ThemeConstants.SPACE_MD,
        })
        if (this.resultCount === 0) {
          Text($r('app.string.search_no_results'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: ThemeConstants.SPACE_XXL })
          Blank().layoutWeight(1)
        } else {
          Grid(this.scroller) {
            LazyForEach(
              this.dataSource,
              (item: SystemSymbolEntry) => {
                GridItem() {
                  this.SymbolCard(item)
                }
              },
              (item: SystemSymbolEntry) => item.name,
            )
          }
          .columnsTemplate(`repeat(auto-fit, ${ThemeConstants.SYSTEM_SYMBOL_GRID_MIN_WIDTH}vp)`)
          .columnsGap(ThemeConstants.SPACE_SM)
          .rowsGap(ThemeConstants.SPACE_SM)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_XL,
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar(AppStrings.get('system_symbol_browser_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
