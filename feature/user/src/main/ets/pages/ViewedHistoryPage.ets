import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  CardEmptyState,
  ConciseListRow,
  GalleryDetailParams,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  ViewedGallery,
  ViewedHistorySettings,
  ViewedHistoryState,
  connectNavStack,
  connectViewedHistory,
  immersiveTitleBarOpts,
} from 'shared'

const HISTORY_PAGE_SIZE: number = 40

/**
 * Recently viewed galleries. eros_fe keeps History as an optional main tab; NextE already records
 * viewed galleries in `ViewedHistorySettings`, so this lane exposes that existing local data through a
 * secondary HDS settings surface before taking on configurable tabs.
 */
@ComponentV2
export struct ViewedHistoryPage {
  @Local history: ViewedHistoryState = connectViewedHistory();
  @Local visibleCount: number = HISTORY_PAGE_SIZE;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private titleFor(item: ViewedGallery): string {
    if (item.titleJp.length > 0) {
      return item.titleJp
    }
    if (item.title.length > 0) {
      return item.title
    }
    return `#${item.gid}`
  }

  private subtitleFor(item: ViewedGallery): string {
    const parts: string[] = []
    if (item.category.length > 0) {
      parts.push(item.category)
    }
    if (item.fileCount.length > 0) {
      parts.push(`${item.fileCount}P`)
    }
    if (item.uploader.length > 0) {
      parts.push(item.uploader)
    }
    return parts.join(' · ')
  }

  private timeFor(item: ViewedGallery): string {
    if (item.time <= 0) {
      return ''
    }
    const d: Date = new Date(item.time)
    const month: string = `${d.getMonth() + 1}`.padStart(2, '0')
    const day: string = `${d.getDate()}`.padStart(2, '0')
    const hour: string = `${d.getHours()}`.padStart(2, '0')
    const minute: string = `${d.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  private openGallery(item: ViewedGallery): void {
    if (item.gid.length === 0 || item.token.length === 0) {
      return
    }
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(item.gid, item.token, item.thumbUrl, this.titleFor(item)),
    )
  }

  private clearHistory(): void {
    this.visibleCount = HISTORY_PAGE_SIZE
    ViewedHistorySettings.clear(this.ctx())
  }

  private visibleItemCount(): number {
    return Math.min(this.visibleCount, this.history.items.length)
  }

  private visibleHistoryItems(): ViewedGallery[] {
    const max: number = this.visibleItemCount()
    const out: ViewedGallery[] = []
    for (let i = 0; i < max; i++) {
      out.push(this.history.items[i])
    }
    return out
  }

  private loadMoreHistory(): void {
    if (this.visibleCount < this.history.items.length) {
      this.visibleCount = Math.min(this.visibleCount + HISTORY_PAGE_SIZE, this.history.items.length)
    }
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.history_clear_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.history_clear'),
        fontColor: Color.Red,
        action: () => {
          this.clearHistory()
        },
      },
    })
  }

  private titleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('tab_history') }
    const clearInner: Record<string, Object> = {
      'label': $r('app.string.history_clear'),
      'icon': $r('sys.symbol.trash'),
      'isEnabled': this.history.items.length > 0,
      'action': () => {
        this.confirmClearHistory()
      },
    }
    const items: Record<string, Object>[] = [{ 'content': clearInner }]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 1 }
    const content: Record<string, Object> = {
      'title': title,
      'menu': menu,
    }
    return immersiveTitleBarOpts(content)
  }

  @Builder
  private HistoryRows() {
    if (this.history.items.length === 0) {
      ListItem() {
        CardEmptyState({ message: $r('app.string.history_empty') })
      }
    } else {
      ListItem() {
        GroupedListSection() {
          ForEach(
            this.visibleHistoryItems(),
            (item: ViewedGallery, index: number) => {
              ConciseListRow({
                title: this.titleFor(item),
                subtitle: this.subtitleFor(item),
                trailingText: this.timeFor(item),
                leadingImageUrl: item.thumbUrl,
                action: () => {
                  this.openGallery(item)
                },
              })
              if (index < this.visibleItemCount() - 1) {
                this.rowDivider()
              }
            },
            (item: ViewedGallery, index: number) =>
              `viewed_${index}_${item.gid}_${item.token}_${item.time}`.replace(/[^A-Za-z0-9_]/g, '_'),
          )
        }
      }
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        onReachEnd: () => {
          this.loadMoreHistory()
        },
      }) {
        this.HistoryRows()
      }
    }
    .titleBar(this.titleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
