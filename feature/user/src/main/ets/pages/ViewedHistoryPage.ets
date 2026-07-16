import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
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
import { ViewedHistoryViewModel } from '../viewmodel/ViewedHistoryViewModel'

/** RDB-paged, virtualized viewed-history list using the gallery simple-row visual language. */
@ComponentV2
export struct ViewedHistoryPage {
  @Local vm: ViewedHistoryViewModel = new ViewedHistoryViewModel();
  @Local history: ViewedHistoryState = connectViewedHistory();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();

  aboutToAppear(): void {
    this.vm.setContext(this.ctx())
    this.vm.loadInitial()
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
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
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
      LazyForEach(
        this.vm.dataSource,
        (gallery: EhGallery, index: number) => {
          ListItem() {
            GallerySimpleCard({ gallery: gallery })
              .reuse({ reuseId: () => gallerySimpleReuseId(gallery) })
          }
          .swipeAction({
            end: () => {
              this.DeleteSwipe(gallery.gid)
            },
          })
          .onAppear(() => {
            this.vm.loadMoreIfNearTail(index)
          })
          .onClick(() => {
            this.openGallery(gallery)
          })
        },
        (gallery: EhGallery) =>
          `viewed_${gallery.gid.replace(/[^A-Za-z0-9_]/g, '_')}`,
      )
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
      this.refreshFirstSecondaryDestination(this.stack)
      this.vm.reloadIfChanged(this.history.revision)
    })
  }
}
