import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GallerySimpleCard,
  GalleryDetailParams,
  ReaderParams,
  EhUrlRouter,
  EhConstants,
  EhTagSuggestion,
  GalleryRef,
  ImagePageRouteService,
  ImagePageRouteTarget,
  DiagnosticLogger,
  PageLoadingState,
  PageErrorState,
  CardEmptyState,
  AppStrings,
  LoadingFooter,
  PullRefreshListScaffold,
  PullRefreshGridScaffold,
  PullRefreshController,
  connectNavStack,
  SearchFilterState,
  connectSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_WATCHED,
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
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { BottomBuilderShowType, HdsNavDestination, HideMode } from '@kit.UIDesignKit'
import { ComponentContent, promptAction } from '@kit.ArkUI'
import { SearchViewModel } from '../viewmodel/SearchViewModel'
import { SearchFilterSheet } from '../components/SearchFilterSheet'
import { SearchPageFieldCCBuilder, SearchPageFieldState } from '../components/SearchPageField'

const SEARCH_FIELD_BOTTOM_HEIGHT: number = ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_SM

/**
 * Table-site search — a PUSHED page (eros_fe pushes a dedicated search page from the gallery
 * appbar's search icon, custom_tabbar_page.dart:219-229; NOT a bottom tab). The title area keeps
 * the native back button, current search scope title, and page-level actions; the search INPUT is
 * pinned in the HDS title bar bottomBuilder. It reacts to a page-owned field state (not the app-wide
 * search bus) so stacked Search(A) -> Detail -> Search(B) sessions do not steal each other's query.
 * Action-seeded tag/uploader searches arrive as SearchPageParams.initialQuery route params.
 */
@ComponentV2
export struct GallerySearchPage {
  @Local vm: SearchViewModel = new SearchViewModel();
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local listMode: ListModeState = connectListMode();
  @Local history: SearchHistoryState = connectSearchHistory();
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local showFilter: boolean = false;
  @Local listContentWidth: number = 0;
  @Local imagePageErrorUrl: string = '';
  @Local imagePageResolving: boolean = false;
  // Favorite scope (eros_fe SearchType.favorite): set from the route param when the favorites title-bar
  // magnifier pushes here. The filter entry stays visible; favorite-specific limitations belong inside
  // the sheet, not in a hidden page action.
  @Local isFavoriteScope: boolean = false;
  @Local fieldState: SearchPageFieldState = new SearchPageFieldState();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  // Search field hosted in this pushed page's HDS title-bar bottomBuilder — cached ONCE (re-issuing
  // the titleBar opts must reuse the same field instance, not remount it and flap the IME).
  private fieldContent: ComponentContent<SearchPageFieldState> | null = null;

  private ensureFieldContent(): ComponentContent<SearchPageFieldState> {
    if (this.fieldContent === null) {
      this.fieldContent = new ComponentContent<SearchPageFieldState>(
        this.getUIContext(),
        wrapBuilder<[SearchPageFieldState]>(SearchPageFieldCCBuilder),
        this.fieldState,
      )
    }
    return this.fieldContent
  }

  private searchBottomBuilder(content: ComponentContent<SearchPageFieldState>): Record<string, Object> {
    return {
      'builderComponent': content,
      'height': SEARCH_FIELD_BOTTOM_HEIGHT,
      'showType': BottomBuilderShowType.DIRECTLY_SHOW,
    }
  }

  private scopeTitle(): ResourceStr {
    if (this.isFavoriteScope || this.vm.isFavoriteScope || this.filter.searchScope === SEARCH_SCOPE_FAVORITE) {
      return $r('app.string.search_scope_favorite')
    }
    if (this.filter.searchScope === SEARCH_SCOPE_WATCHED) {
      return $r('app.string.search_scope_watched')
    }
    return $r('app.string.search_scope_gallery')
  }

  // Title text carries the active scope while the field lives in bottomBuilder; shares the app's
  // immersive title-bar style so the status/title/search bar gets the same GRADIENT_BLUR backdrop.
  private searchTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = { 'mainTitle': this.scopeTitle() }
    const content: Record<string, Object> = {
      'title': title,
      'bottomBuilder': this.searchBottomBuilder(this.ensureFieldContent()),
      'menu': this.searchMenu(),
    }
    return immersiveTitleBarOpts(content)
  }

  private searchMenu(): Record<string, Object> {
    const filterInner: Record<string, Object> = {
      'label': $r('app.string.filter'),
      'icon': $r('sys.symbol.funnel'),
      'isEnabled': true,
      'action': () => {
        this.showFilter = true
      },
    }
    const items: Record<string, Object>[] = [{ 'content': filterInner }]
    return { 'value': items, 'maxCount': 1 }
  }

  @Monitor('favoriteMutation.version')
  onFavoriteMutation(): void {
    this.vm.applyFavoriteMutation(
      this.favoriteMutation.gid,
      this.favoriteMutation.favcat,
      this.favoriteMutation.favTitle,
    )
  }

  @Monitor('fieldState.submitSeq')
  onSubmit(): void {
    this.runQuery(this.fieldState.keyword)
    this.vm.clearSuggestions()
  }

  @Monitor('fieldState.keyword')
  onKeywordChange(): void {
    if (this.fieldState.keyword.trim().length === 0) {
      this.clearQueryToHistory()
      this.vm.clearSuggestions()
      return
    }
    this.vm.scheduleTagSuggest(this.fieldState.keyword)
  }

  // A whole-string EH URL (no embedded substring) — eros_fe gates its URL-jump on searchText.isURL,
  // so a query that merely CONTAINS a gallery link still searches.
  private looksLikeBareUrl(s: string): boolean {
    return s.length > 0 && !s.includes(' ') && (s.startsWith('http://') || s.startsWith('https://'))
  }

  private formatSuggestionQuery(s: EhTagSuggestion): string {
    const tag: string = s.text.trim()
    const ns: string = EhConstants.compactNamespace(s.namespace)
    if (tag.length === 0) {
      return ''
    }
    const exact: string = tag.indexOf(' ') >= 0 ? `"${tag}$"` : `${tag}$`
    return ns.length > 0 ? `${ns}:${exact}` : exact
  }

  private replaceLastToken(query: string, replacement: string): string {
    const trimmedRight: string = query.replace(/\s+$/, '')
    const m: RegExpMatchArray | null = trimmedRight.match(/^(.*[ ;"])?([^ ;"]*)$/)
    const prefix: string = m !== null && m[1] !== undefined ? m[1] : ''
    return `${prefix}${replacement} `
  }

  private acceptSuggestion(s: EhTagSuggestion): void {
    const next: string = this.replaceLastToken(this.fieldState.keyword, this.formatSuggestionQuery(s))
    this.fieldState.keyword = next
    this.fieldState.seedSeq = this.fieldState.seedSeq + 1
    this.vm.clearSuggestions()
  }

  /**
   * Single entry point for a submitted query. A pasted BARE gallery/image-page URL jumps straight to
   * the gallery/reader (eros_fe regGalleryUrl/regGalleryPageUrl → _jumpToUrl); otherwise record
   * history and search. Empty ordinary search never implicitly browses by filter; it returns to
   * history/blank so filter edits do not surprise-trigger network requests.
   */
  private runQuery(query: string): void {
    const trimmed: string = query.trim()
    this.imagePageErrorUrl = ''
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
    if (trimmed.length === 0) {
      this.clearQueryToHistory()
      return
    }
    if (trimmed.length > 0) {
      this.recordHistory(trimmed)
    }
    this.vm.search(trimmed)
  }

  private openImagePageUrl(url: string): void {
    this.imagePageErrorUrl = ''
    this.imagePageResolving = true
    ImagePageRouteService.resolve(url)
      .then((target: ImagePageRouteTarget) => {
        this.imagePageResolving = false
        this.stack.pushPathByName(
          'Reader',
          new ReaderParams(target.gid, target.token, target.index, target.fileCount, '', [target.seedImage], 0, 0),
        )
      })
      .catch((err: Error) => {
        this.imagePageResolving = false
        DiagnosticLogger.warn('search', 'image_page_jump_failed', err.message)
        this.imagePageErrorUrl = url
      })
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private recordHistory(query: string): void {
    SearchHistorySettings.add(this.ctx(), query)
  }

  private clearQueryToHistory(): void {
    this.imagePageErrorUrl = ''
    this.imagePageResolving = false
    this.vm.clearSearchState()
  }

  // Tap a recent-search chip: fill the title-bar field (seedSeq) and run it.
  private searchFromHistory(query: string): void {
    this.fieldState.keyword = query
    this.fieldState.seedSeq = this.fieldState.seedSeq + 1
    this.runQuery(query)
  }

  private deleteSearchHistory(query: string): void {
    SearchHistorySettings.remove(this.ctx(), query)
    promptAction.showToast({ message: $r('app.string.search_history_deleted') })
  }

  @Builder
  SearchSuggestionView() {
    List({ space: ThemeConstants.SPACE_XS }) {
      ForEach(
        this.vm.suggestions,
        (s: EhTagSuggestion) => {
          ListItem() {
            Row({ space: ThemeConstants.SPACE_MD }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(24)
                .fontColor([$r('sys.color.font_tertiary')])
              Column({ space: ThemeConstants.SPACE_XS }) {
                Text(this.formatSuggestionQuery(s))
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (s.namespace.length > 0) {
                  Text(`${AppStrings.get('search_suggestion_namespace')}${EhConstants.expandNamespace(s.namespace)}`)
                    .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({
              left: ThemeConstants.SPACE_LG,
              right: ThemeConstants.SPACE_LG,
              top: ThemeConstants.SPACE_SM,
              bottom: ThemeConstants.SPACE_SM,
            })
            .onClick(() => {
              this.acceptSuggestion(s)
            })
          }
        },
        (s: EhTagSuggestion) => `${s.namespace}:${s.text}`,
      )
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + SEARCH_FIELD_BOTTOM_HEIGHT,
      bottom: ThemeConstants.SPACE_LG,
    })
  }

  @Monitor('filter.applySeq')
  onFilterApply(): void {
    // Persist live filter edits so they survive a restart (eros_fe keeps the advanced-search profile).
    SearchFilterSettings.persist(this.ctx())
    if (this.fieldState.keyword.trim().length > 0 || this.vm.isFavoriteScope) {
      this.vm.reapplyFilters()
    }
  }

  @Builder
  FilterSheet() {
    SearchFilterSheet({
      onClose: () => {
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
                .gesture(
                  LongPressGesture({ repeat: false, duration: 500 })
                    .onAction(() => {
                      this.deleteSearchHistory(q)
                    }),
                )
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
      top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + SEARCH_FIELD_BOTTOM_HEIGHT +
      ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_LG,
    })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          if (this.imagePageResolving) {
            PageLoadingState()
          } else if (this.imagePageErrorUrl.length > 0) {
            PageErrorState({
              message: $r('app.string.image_page_open_failed'),
              retryAction: () => {
                this.openImagePageUrl(this.imagePageErrorUrl)
              },
            })
          } else if (this.vm.isLoading && this.vm.itemCount === 0) {
            PageLoadingState()
          } else if (this.vm.suggestionCount > 0) {
            this.SearchSuggestionView()
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
            CardEmptyState({ message: $r('app.string.search_no_results') })
          } else if (this.listMode.mode === ListMode.GRID) {
            PullRefreshGridScaffold({
              scroller: this.scroller,
              minColumnWidth: ThemeConstants.GALLERY_GRID_MIN_W,
              gap: ThemeConstants.GALLERY_GRID_GAP,
              horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
              topPadding: SEARCH_FIELD_BOTTOM_HEIGHT,
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
              LazyForEach(
                this.vm.dataSource,
                (g: EhGallery) => {
                  GridItem() {
                    GalleryGridCard({ gallery: g })
                  }
                  .onClick(() => {
                    this.stack.pushPathByName(
                      'GalleryDetail',
                      new GalleryDetailParams(
                        g.gid,
                        g.token,
                        g.thumbUrl,
                        g.title(),
                        g.fileCount,
                        g.imgWidth,
                        g.imgHeight,
                      ),
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
              topPadding: SEARCH_FIELD_BOTTOM_HEIGHT,
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
                      new GalleryDetailParams(
                        g.gid,
                        g.token,
                        g.thumbUrl,
                        g.title(),
                        g.fileCount,
                        g.imgWidth,
                        g.imgHeight,
                      ),
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .bindSheet($$this.showFilter, this.FilterSheet(), {
        detents: [SheetSize.LARGE],
        showClose: false,
      })
    }
    .titleBar(this.searchTitleBar())
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: false,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP,
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      // The favorites title-bar magnifier pushed us with a favorite scope param (eros_fe
      // goSearchPage(searchType: favorite)). Seed the VM scope and browse the favcat immediately;
      // typing in the title-bar field then runs favorites.php f_search via the same runQuery →
      // vm.search path. There is no bespoke favorites search box — this is the ONE adaptive page.
      if (context.pathInfo.param instanceof SearchPageParams) {
        const p: SearchPageParams = context.pathInfo.param as SearchPageParams
        this.fieldState.focusOnAppear = p.focusOnAppear
        if (p.searchType === 'favorite') {
          this.isFavoriteScope = true
          this.vm.seedFavoriteScope(p.favcat)
          this.vm.search('')
        }
        if (p.initialQuery.length > 0) {
          this.fieldState.keyword = p.initialQuery
          this.fieldState.seedSeq = this.fieldState.seedSeq + 1
          this.runQuery(p.initialQuery)
        }
      }
    })
  }
}
