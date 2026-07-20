import { common } from '@kit.AbilityKit'
import { ComponentContent } from '@kit.ArkUI'
import { BottomBuilderShowType, HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  CardEmptyState,
  EhGallery,
  GalleryDetailParams,
  GallerySimpleCard,
  LoadingFooter,
  NavStackHolder,
  PageErrorState,
  PageLoadingState,
  PullRefreshController,
  PullRefreshListScaffold,
  ThemeConstants,
  ViewedHistoryState,
  connectNavStack,
  connectViewedHistory,
  gallerySimpleReuseId,
  immersiveTitleBarOpts,
} from 'shared'
import {
  ViewedHistoryDayGroup,
  ViewedHistoryListRow,
  ViewedHistoryViewModel,
} from '../viewmodel/ViewedHistoryViewModel'
import {
  HISTORY_PINNED_DAY_HEADER_HEIGHT,
  HistoryPinnedDayHeaderCCBuilder,
  HistoryPinnedDayHeaderState,
  historyDayLabel,
  historyLocalDayStart,
} from '../components/HistoryPinnedDayHeader'

/** RDB-paged, virtualized viewed-history list using the gallery simple-row visual language. */
@ComponentV2
export struct ViewedHistoryPage {
  @Local vm: ViewedHistoryViewModel = new ViewedHistoryViewModel();
  @Local history: ViewedHistoryState = connectViewedHistory();
  // This changes at the next local midnight so both ordinary and pinned headers update while the
  // destination remains mounted. Day groups never store these relative strings.
  @Local currentDayStart: number = historyLocalDayStart(Date.now());
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  @Local pinnedDayHeaderState: HistoryPinnedDayHeaderState = new HistoryPinnedDayHeaderState()
  private pinnedDayHeaderContent: ComponentContent<HistoryPinnedDayHeaderState> | null = null;
  private dayRolloverTimer: number = -1
  // Window coordinate of the List viewport. Group rectangles from Scroller are relative to this
  // viewport, so this is the only conversion needed to compare them with the HDS pin surface.
  private historyListGlobalY: number = -1

  aboutToAppear(): void {
    this.resetPinnedDayHeader()
    this.vm.setContext(this.ctx())
    this.vm.loadInitial()
    this.refreshCurrentDay()
    this.scheduleCurrentDayRefresh()
  }

  aboutToDisappear(): void {
    if (this.dayRolloverTimer >= 0) {
      clearTimeout(this.dayRolloverTimer)
      this.dayRolloverTimer = -1
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private titleFor(gallery: EhGallery): string {
    const title: string = gallery.title()
    return title.length > 0 ? title : `#${gallery.gid}`
  }

  private openGallery(gallery: EhGallery): void {
    if (gallery.gid.length === 0 || gallery.token.length === 0) {
      return
    }
    this.stack.pushPathByName(
      'GalleryDetail',
      new GalleryDetailParams(gallery.gid, gallery.token, gallery.thumbUrl, this.titleFor(gallery)),
    )
  }

  private clearHistory(): void {
    this.vm.clear()
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
      'isEnabled': this.vm.itemCount > 0,
      'action': () => {
        this.confirmClearHistory()
      },
    }
    const items: Record<string, Object>[] = [{ 'content': clearInner }]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 1 }
    const content: Record<string, Object> = {
      'title': title,
      'menu': menu,
      'bottomBuilder': this.pinnedDayBottomBuilder(this.ensurePinnedDayHeaderContent()),
    }
    return immersiveTitleBarOpts(content)
  }

  private ensurePinnedDayHeaderContent(): ComponentContent<HistoryPinnedDayHeaderState> {
    if (this.pinnedDayHeaderContent === null) {
      this.pinnedDayHeaderContent = new ComponentContent<HistoryPinnedDayHeaderState>(
        this.getUIContext(),
        wrapBuilder<[HistoryPinnedDayHeaderState]>(HistoryPinnedDayHeaderCCBuilder),
        this.pinnedDayHeaderState,
      )
    }
    return this.pinnedDayHeaderContent
  }

  private pinnedDayBottomBuilder(
    content: ComponentContent<HistoryPinnedDayHeaderState>,
  ): Record<string, Object> {
    return {
      'builderComponent': content,
      'height': HISTORY_PINNED_DAY_HEADER_HEIGHT,
      'showType': BottomBuilderShowType.DIRECTLY_SHOW,
    }
  }

  private refreshCurrentDay(): void {
    const currentDayStart: number = historyLocalDayStart(Date.now())
    this.currentDayStart = currentDayStart
    this.pinnedDayHeaderState.currentDayStart = currentDayStart
    this.syncPinnedDayHeader()
  }

  private scheduleCurrentDayRefresh(): void {
    if (this.dayRolloverTimer >= 0) {
      clearTimeout(this.dayRolloverTimer)
    }
    const now: Date = new Date()
    const nextLocalMidnight: number = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() + 1,
    ).getTime()
    this.dayRolloverTimer = setTimeout(() => {
      this.dayRolloverTimer = -1
      this.refreshCurrentDay()
      this.scheduleCurrentDayRefresh()
    }, Math.max(1, nextLocalMidnight - now.getTime() + 1))
  }

  private onHistoryDidScroll(_offset: number): void {
    this.syncPinnedDayHeader()
  }

  private resetPinnedDayHeader(): void {
    this.pinnedDayHeaderState.visible = false
  }

  private onHistoryListArea(area: Area): void {
    this.historyListGlobalY = area.globalPosition.y as number
    this.syncPinnedDayHeader()
  }

  @Monitor('pinnedDayHeaderState.pinSurfaceTopY')
  private onPinnedDaySurfaceChanged(): void {
    this.syncPinnedDayHeader()
  }

  @Monitor('history.revision')
  private onHistoryRevisionChanged(): void {
    this.vm.reloadIfChanged(this.history.revision)
  }

  private syncPinnedDayHeader(): void {
    const pinSurfaceTopY: number = this.pinnedDayHeaderState.pinSurfaceTopY
    if (pinSurfaceTopY < 0 || this.historyListGlobalY < 0) {
      this.pinnedDayHeaderState.visible = false
      return
    }
    const pinSurfaceYInList: number = pinSurfaceTopY - this.historyListGlobalY
    let activeGroup: ViewedHistoryDayGroup | undefined = undefined
    let activeHeaderY: number = -Infinity
    for (let index: number = 0; index < this.vm.dayGroups.length; index++) {
      const group: ViewedHistoryDayGroup = this.vm.dayGroups[index]
      // Index 0 is PullRefreshListScaffold's top reserve. Each day is one ListItemGroup.
      const groupRect = this.scroller.getItemRect(index + 1)
      if (
        groupRect.height > 0 &&
        groupRect.y < pinSurfaceYInList &&
        groupRect.y > activeHeaderY
      ) {
        activeGroup = group
        activeHeaderY = groupRect.y
      }
    }
    if (activeGroup === undefined) {
      this.pinnedDayHeaderState.visible = false
      return
    }
    this.pinnedDayHeaderState.dayStart = activeGroup.dayStart
    this.pinnedDayHeaderState.currentDayStart = this.currentDayStart
    this.pinnedDayHeaderState.visible = true
  }

  @Builder
  private HistoryRows() {
    if (
      this.vm.itemCount === 0 &&
      this.vm.errorMessage.length === 0 &&
      (this.vm.isLoading || !this.vm.loaded)
    ) {
      ListItem() {
        Column() {
          PageLoadingState({ expand: false })
        }
        .height(240)
        .justifyContent(FlexAlign.Center)
      }
    } else if (this.vm.itemCount === 0 && this.vm.errorMessage.length > 0) {
      ListItem() {
        Column() {
          PageErrorState({
            message: this.vm.errorMessage,
            expand: false,
            retryAction: () => {
              this.vm.loadInitial(true)
            },
          })
        }
        .height(240)
        .justifyContent(FlexAlign.Center)
      }
    } else if (this.vm.itemCount === 0) {
      ListItem() {
        CardEmptyState({ message: $r('app.string.history_empty'), expand: false })
      }
    } else {
      this.HistoryDayGroups()
      ListItem() {
        LoadingFooter({
          isLoading: this.vm.isLoadingMore || this.vm.isLoading,
          hasMore: this.vm.hasMore,
          isError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
          onRetry: () => {
            this.vm.loadMore()
          },
        })
      }
    }
  }

  @Builder
  private HistoryDayGroups() {
    ForEach(
      this.vm.dayGroups,
      (group: ViewedHistoryDayGroup) => {
        ListItemGroup({ header: this.HistoryDayHeader(group), space: 0 }) {
          LazyForEach(
            group.dataSource,
            (row: ViewedHistoryListRow) => {
              ListItem() {
                GallerySimpleCard({ gallery: row.gallery })
                  .reuse({ reuseId: () => gallerySimpleReuseId(row.gallery) })
              }
              .swipeAction({
                end: () => {
                  this.DeleteSwipe(row.gallery.gid)
                },
              })
              .onAppear(() => {
                this.vm.loadMoreIfNearTailGallery(row.gallery.gid)
              })
              .onClick(() => {
                this.openGallery(row.gallery)
              })
            },
            (row: ViewedHistoryListRow) =>
              `viewed_${row.gallery.gid.replace(/[^A-Za-z0-9_]/g, '_')}`,
          )
        }
      },
      (group: ViewedHistoryDayGroup) => group.key,
    )
  }

  @Builder
  private HistoryDayHeader(group: ViewedHistoryDayGroup) {
      Text(historyDayLabel(group.dayStart, this.currentDayStart))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeConstants.BRAND_PRIMARY)
      .width('100%')
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
        top: ThemeConstants.SPACE_SM,
        bottom: ThemeConstants.SPACE_XS,
      })
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  private DeleteSwipe(gid: string) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.White])
      }
      .width(48)
      .height(40)
      .backgroundColor(Color.Red)
      .accessibilityText($r('app.string.common_delete'))
      .onClick(() => {
        this.vm.remove(gid)
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'History'
  }

  build() {
    HdsNavDestination() {
      PullRefreshListScaffold({
        scroller: this.scroller,
        controller: this.refreshController,
        listSpace: 0,
        // HDS owns the readable pinned date mirror in its bottomBuilder. Native pinning would sit
        // underneath the immersive title layer and duplicate the date when it becomes obscured.
        stickyHeaders: false,
        bottomPadding: ThemeConstants.SPACE_XL,
        itemCount: this.vm.itemCount,
        onRefresh: async () => {
          await this.vm.loadInitial(true)
        },
        onBottomRefresh: async () => {
          await this.vm.loadMore()
        },
        canStartBottomRefresh: () => this.vm.canLoadMore(),
        onReachEnd: () => {
          this.vm.loadMore()
        },
        onDidScroll: (offset: number, _state: ScrollState) => {
          this.onHistoryDidScroll(offset)
        },
        onListAreaChange: (area: Area) => {
          this.onHistoryListArea(area)
        },
      }) {
        this.HistoryRows()
      }
    }
    .titleBar(this.titleBar())
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.resetPinnedDayHeader()
      this.refreshFirstSecondaryDestination(this.stack)
      this.refreshCurrentDay()
      this.scheduleCurrentDayRefresh()
      this.vm.reloadIfChanged(this.history.revision)
    })
  }
}
