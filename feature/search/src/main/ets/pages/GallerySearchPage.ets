import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GallerySimpleCard,
  GalleryDetailParams,
  ReaderParams,
  EhUrlRouter,
  GalleryRef,
  ImagePageRouteService,
  ImagePageRouteTarget,
  DiagnosticLogger,
  PageLoadingState,
  PageErrorState,
  CardEmptyState,
  LoadingFooter,
  PullRefreshListScaffold,
  PullRefreshGridScaffold,
  PullRefreshController,
  SearchActionState,
  connectSearchAction,
  connectNavStack,
  SearchFilterState,
  connectSearchFilter,
  connectListMode,
  ListModeState,
  ListMode,
  connectSearchHistory,
  SearchHistoryState,
  SearchHistorySettings,
  SearchFilterSettings,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  immersiveTitleBarOpts,
  SearchPageParams,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { ComponentContent } from '@kit.ArkUI'
import { SearchViewModel } from '../viewmodel/SearchViewModel'
import { SearchFilterSheet } from '../components/SearchFilterSheet'
import { SearchPageFieldCCBuilder } from '../components/SearchPageField'

/**
 * Table-site search — a PUSHED page (eros_fe pushes a dedicated search page from the gallery
 * appbar's search icon, custom_tabbar_page.dart:219-229; NOT a bottom tab). The search INPUT is
 * hosted in THIS page's HDS title bar (HdsNavDestination titleBar `stackBuilderComponent` =
 * SearchPageField) — the body has no search row. It reacts to the field's submit via the shared
 * SearchActionState bus (`submitSeq` on Enter; `keyword` holds the text), consumes a cross-page
 * `pendingQuery` (Similar/uploader search) on appear, and renders results through the shared
 * PullRefreshListScaffold, same as the gallery list.
 */
@ComponentV2
export struct GallerySearchPage {
  @Local vm: SearchViewModel = new SearchViewModel();
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local listMode: ListModeState = connectListMode();
  @Local history: SearchHistoryState = connectSearchHistory();
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local showFilter: boolean = false;
  @Local listContentWidth: number = 0;
  // Favorite scope (eros_fe SearchType.favorite): set from the route param when the favorites title-bar
  // magnifier pushes here. Hides the gallery advanced-filter trigger (eros_fe hides cats/advanced for
  // favorite, gallery_filter_view.dart:74-82) and makes the page browse favorites.php f_search.
  @Local isFavoriteScope: boolean = false;
  private actionState: SearchActionState = connectSearchAction();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  private lastHandledQuery: string = '';
  // Search field hosted in this pushed page's HDS title bar — cached ONCE (re-issuing the titleBar
  // opts must reuse the same field instance, not remount it and flap the IME).
  private fieldContent: ComponentContent<Object> | null = null;

  private ensureFieldContent(): ComponentContent<Object> {
    if (this.fieldContent === null) {
      this.fieldContent = new ComponentContent<Object>(
        this.getUIContext(),
        wrapBuilder<[Object]>(SearchPageFieldCCBuilder),
        new Object(),
      )
    }
    return this.fieldContent
  }

  // No title text (the field IS the title area); shares the app's immersive title-bar style so the
  // status bar / title bar gets the same GRADIENT_BLUR backdrop as the tab pages.
  private searchTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': ' ' }
    const content: Record<string, Object> = {
      'title': title,
      'stackBuilderComponent': this.ensureFieldContent(),
    }
    return immersiveTitleBarOpts(content)
  }

  // A freshly pushed search page starts empty (mirror V2Next SearchPage.aboutToAppear): reset the
  // shared field so the title-bar input doesn't show the previous session's query and the page doesn't
  // auto-run it. A pending cross-page query (consumed next) re-seeds the field, so it still wins.
  aboutToAppear(): void {
    this.actionState.keyword = ''
    this.actionState.seedSeq = this.actionState.seedSeq + 1
    this.consumePendingQuery()
  }

  @Monitor('actionState.pendingQuery')
  onPendingQuery(): void {
    this.consumePendingQuery()
  }

  private consumePendingQuery(): void {
    const pq: string = this.actionState.pendingQuery
    if (pq.length === 0 || pq === this.lastHandledQuery) {
      return
    }
    this.lastHandledQuery = pq
    const sep: number = pq.indexOf(':')
    const query: string = sep >= 0 ? pq.substring(sep + 1) : pq
    // Seed the title-bar field so it reflects the active cross-page query (e.g. the detail page's
    // Similar/uploader search), matching eros_fe seeding searchTextController — the user can see/edit it.
    if (query.length > 0) {
      this.actionState.keyword = query
      this.actionState.seedSeq = this.actionState.seedSeq + 1
    }
    this.runQuery(query)
    // Clear the consumed request so a later plain open (title-bar icon) doesn't resurrect it.
    this.actionState.clearPending()
  }

  @Monitor('actionState.submitSeq')
  onSubmit(): void {
    this.runQuery(this.actionState.keyword)
  }

  // A whole-string EH URL (no embedded substring) — eros_fe gates its URL-jump on searchText.isURL,
  // so a query that merely CONTAINS a gallery link still searches.
  private looksLikeBareUrl(s: string): boolean {
    return s.length > 0 && !s.includes(' ') && (s.startsWith('http://') || s.startsWith('https://'))
  }

  /**
   * Single entry point for a submitted query. A pasted BARE gallery/image-page URL jumps straight to
   * the gallery/reader (eros_fe regGalleryUrl/regGalleryPageUrl → _jumpToUrl); otherwise record history and search. Note: empty-query
   * browse-by-filter below is a NextE enhancement (EH supports /?f_cats=…) — eros_fe instead clears
   * on empty text and applies category filters on the home list, not via an empty search.
   */
  private runQuery(query: string): void {
    const trimmed: string = query.trim()
    if (this.looksLikeBareUrl(trimmed)) {
      const ref: GalleryRef | null = EhUrlRouter.parseGallery(trimmed)
      if (ref !== null) {
        this.stack.pushPathByName('GalleryDetail', new GalleryDetailParams(ref.gid, ref.token))
        return
      }
      if (EhUrlRouter.parseImagePage(trimmed) !== null) {
        this.openImagePageUrl(trimmed)
        return
      }
    }
    if (trimmed.length === 0 && !this.filter.isActive()) {
      return
    }
    if (trimmed.length > 0) {
      this.recordHistory(trimmed)
    }
    this.vm.search(trimmed)
  }

  private openImagePageUrl(url: string): void {
    ImagePageRouteService.resolve(url)
      .then((target: ImagePageRouteTarget) => {
        this.stack.pushPathByName(
          'Reader',
          new ReaderParams(target.gid, target.token, target.index, 0, '', [target.seedImage], 0, 0),
        )
      })
      .catch((err: Error) => {
        DiagnosticLogger.warn('search', 'image_page_jump_failed', err.message)
        this.recordHistory(url)
        this.vm.search(url)
      })
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private recordHistory(query: string): void {
    SearchHistorySettings.add(this.ctx(), query)
  }

  // Tap a recent-search chip: fill the title-bar field (seedSeq) and run it.
  private searchFromHistory(query: string): void {
    this.actionState.keyword = query
    this.actionState.seedSeq = this.actionState.seedSeq + 1
    this.runQuery(query)
  }

  @Monitor('filter.applySeq')
  onFilterApply(): void {
    // Persist the applied filters so they survive a restart (eros_fe keeps the advanced-search profile).
    SearchFilterSettings.persist(this.ctx())
    this.vm.reapplyFilters()
  }

  @Builder
  FilterSheet() {
    SearchFilterSheet({
      onApply: () => {
        this.showFilter = false
      },
    })
  }

  // Search landing: a filter trigger is available UP FRONT (eros_fe exposes category/advanced filters
  // before searching, not only after results), then recent-search chips (tap to re-run / clear all),
  // or a centered hint when there's no history.
  @Builder
  SearchHistoryView() {
    Column() {
      if (!this.isFavoriteScope) {
        Row() {
          Blank()
          this.FilterTrigger()
        }
        .width('100%')
        .padding({ bottom: ThemeConstants.SPACE_MD })
      }

      if (this.history.items.length > 0) {
        Row() {
          Text($r('app.string.search_history'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          Text($r('app.string.search_history_clear'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_emphasize'))
            .onClick(() => {
              SearchHistorySettings.clear(this.ctx())
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ bottom: ThemeConstants.SPACE_SM })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(
            this.history.items,
            (q: string) => {
              Text(q)
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_primary'))
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(ThemeConstants.RADIUS_ROUND)
                .padding({
                  left: ThemeConstants.SPACE_MD,
                  right: ThemeConstants.SPACE_MD,
                  top: ThemeConstants.SPACE_XS,
                  bottom: ThemeConstants.SPACE_XS,
                })
                .margin({ right: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '90%' })
                .onClick(() => {
                  this.searchFromHistory(q)
                })
            },
            (q: string) => q,
          )
        }.width('100%')
      } else {
        Column() {
          Text($r('app.string.search_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
      top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_LG,
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  FilterTrigger() {
    Text($r('app.string.filter'))
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(
        this.filter.isActive() ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'),
      )
      .backgroundColor(
        this.filter.isActive() ? ThemeConstants.BRAND_PRIMARY : $r('app.color.card_background'),
      )
      .borderRadius(ThemeConstants.RADIUS_ROUND)
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .onClick(() => {
        this.showFilter = true
      })
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.vm.isLoading && this.vm.itemCount === 0) {
          PageLoadingState()
        } else if (!this.vm.hasSearched) {
          this.SearchHistoryView()
        } else if (this.vm.itemCount === 0 && this.vm.errorMessage.length > 0) {
          PageErrorState({
            message: this.vm.errorMessage,
            retryAction: () => {
              this.vm.refresh()
            },
          })
        } else if (this.vm.itemCount === 0) {
          CardEmptyState({ message: $r('app.string.common_no_content') })
        } else if (this.listMode.mode === ListMode.GRID) {
          PullRefreshGridScaffold({
            scroller: this.scroller,
            bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
            controller: this.refreshController,
            onRefresh: async () => {
              await this.vm.refresh()
            },
            onBottomRefresh: async () => {
              await this.vm.loadMore()
            },
            canStartBottomRefresh: () => this.vm.canLoadMore(),
            onReachEnd: () => {
              this.vm.loadMore()
            },
          }) {
            if (!this.isFavoriteScope) {
              GridItem() {
                Row() {
                  this.FilterTrigger()
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
              }
              .columnStart(0)
              .columnEnd(1)
            }
            LazyForEach(
              this.vm.dataSource,
              (g: EhGallery) => {
                GridItem() {
                  GalleryGridCard({ gallery: g })
                }
                .onClick(() => {
                  this.stack.pushPathByName(
                    'GalleryDetail',
                    new GalleryDetailParams(g.gid, g.token, g.thumbUrl, g.title(), g.fileCount),
                  )
                })
              },
              (g: EhGallery) => g.gid,
            )
          }
        } else {
          // LIST (cards) and SIMPLE_LIST (compact divider rows) share one scaffold.
          PullRefreshListScaffold({
            scroller: this.scroller,
            listSpace: this.listMode.mode === ListMode.SIMPLE_LIST ? 0 : ThemeConstants.SPACE_SM,
            bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
            controller: this.refreshController,
            onRefresh: async () => {
              await this.vm.refresh()
            },
            onBottomRefresh: async () => {
              await this.vm.loadMore()
            },
            canStartBottomRefresh: () => this.vm.canLoadMore(),
            onReachEnd: () => {
              this.vm.loadMore()
            },
            onContentWidth: (contentWidth: number) => {
              this.listContentWidth = contentWidth
            },
          }) {
            if (!this.isFavoriteScope) {
              ListItem() {
                Row() {
                  this.FilterTrigger()
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
                .padding({ bottom: ThemeConstants.SPACE_XS })
              }
            }
            LazyForEach(
              this.vm.dataSource,
              (g: EhGallery) => {
                ListItem() {
                  if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                    GallerySimpleCard({ gallery: g })
                  } else {
                    GalleryCard({ gallery: g, listContentWidth: this.listContentWidth })
                  }
                }
                .onClick(() => {
                  this.stack.pushPathByName(
                    'GalleryDetail',
                    new GalleryDetailParams(g.gid, g.token, g.thumbUrl, g.title(), g.fileCount),
                  )
                })
              },
              (g: EhGallery) => g.gid,
            )
            ListItem() {
              LoadingFooter({
                // Include page-level search/filter reloads so preserved old results never show a
                // terminal "no more" footer while their replacement request is in flight.
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .bindSheet($$this.showFilter, this.FilterSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        title: { title: $r('app.string.filter') },
        showClose: true,
      })
    }
    .titleBar(this.searchTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      // The favorites title-bar magnifier pushed us with a favorite scope param (eros_fe
      // goSearchPage(searchType: favorite)). Seed the VM scope and browse the favcat immediately;
      // typing in the title-bar field then runs favorites.php f_search via the same runQuery →
      // vm.search path. There is no bespoke favorites search box — this is the ONE adaptive page.
      if (context.pathInfo.param instanceof SearchPageParams) {
        const p: SearchPageParams = context.pathInfo.param as SearchPageParams
        if (p.searchType === 'favorite') {
          this.isFavoriteScope = true
          this.vm.seedFavoriteScope(p.favcat)
          this.vm.search('')
        }
      }
    })
  }
}
