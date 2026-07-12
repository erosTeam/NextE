import {
  ThemeConstants,
  EhGallery,
  GalleryCard,
  GalleryGridCard,
  GalleryWaterfallCard,
  GalleryCoverWallCard,
  GallerySimpleCard,
  GalleryDetailParams,
  ReaderParams,
  EhUrlRouter,
  EhConstants,
  EhTagSuggestion,
  QueryTag,
  TagQuery,
  TagRelation,
  TagTranslationService,
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
  PullRefreshWaterFlowScaffold,
  PullRefreshController,
  connectNavStack,
  connectReaderOverlayNavigation,
  SearchFilterState,
  connectSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_WATCHED,
  connectListMode,
  ListModeState,
  ListMode,
  connectSearchHistory,
  SearchHistoryState,
  connectTagTranslationSettings,
  TagTranslationSettingsState,
  SearchHistorySettings,
  SearchFilterSettings,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  FavSelectionState,
  connectFavSelection,
  immersiveTitleBarOpts,
  SearchPageParams,
  GalleryFavoriteMutationState,
  connectGalleryFavoriteMutation,
  GalleryRatingMutationState,
  connectGalleryRatingMutation,
  appSheetOptions,
  LocalBlockState,
  connectLocalBlock,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { BottomBuilderShowType, HdsNavDestination, HideMode } from '@kit.UIDesignKit'
import { ComponentContent, KeyboardAvoidMode, promptAction } from '@kit.ArkUI'
import { SearchViewModel } from '../viewmodel/SearchViewModel'
import { SearchFilterSheet } from '../components/SearchFilterSheet'
import { SearchPageFieldCCBuilder, SearchPageFieldState } from '../components/SearchPageField'

const SEARCH_FIELD_BOTTOM_HEIGHT: number = ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_SM
const SEARCH_HISTORY_CHIP_ANIM_DURATION: number = 180

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
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local favSel: FavSelectionState = connectFavSelection();
  @Local favoriteMutation: GalleryFavoriteMutationState = connectGalleryFavoriteMutation();
  @Local ratingMutation: GalleryRatingMutationState = connectGalleryRatingMutation();
  @Local localBlock: LocalBlockState = connectLocalBlock();
  @Local historyTranslations: Map<string, string> = new Map<string, string>();
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
  private suggestionScroller: Scroller = new Scroller();
  private historyScroller: Scroller = new Scroller();
  private refreshController: PullRefreshController = new PullRefreshController();
  private historyTranslationRun: number = 0;
  // Search field hosted in this pushed page's HDS title-bar bottomBuilder — cached ONCE (re-issuing
  // the titleBar opts must reuse the same field instance, not remount it and flap the IME).
  private fieldContent: ComponentContent<SearchPageFieldState> | null = null;

  aboutToAppear(): void {
    this.vm.setContext(this.ctx())
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.refreshHistoryTranslations()
  }

  aboutToDisappear(): void {
    SearchFilterSettings.flush(this.ctx())
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

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

  @Monitor('favSel.favList')
  onFavListChange(): void {
    this.vm.resolveVisibleFavoriteSlotsFrom(this.favSel.favList)
  }

  @Monitor('ratingMutation.version')
  onRatingMutation(): void {
    this.vm.applyRatingMutation(
      this.ratingMutation.gid,
      this.ratingMutation.userRating,
      this.ratingMutation.averageRating,
      this.ratingMutation.ratingCount,
      this.ratingMutation.colorRating,
    )
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    this.vm.reapplyTagTranslation()
    this.refreshHistoryTranslations()
  }

  @Monitor('history.items')
  onSearchHistoryItemsChange(): void {
    this.refreshHistoryTranslations()
  }

  @Monitor('history.translateEnabled')
  onSearchHistoryTranslateChange(): void {
    this.refreshHistoryTranslations()
  }

  @Monitor('localBlock.version')
  async onLocalBlockChange(): Promise<void> {
    await this.vm.applyLocalBlockChange()
  }

  @Monitor('fieldState.submitSeq')
  onSubmit(): void {
    this.runQuery(this.fieldState.keyword)
    this.vm.clearSuggestions()
  }

  @Monitor('fieldState.keyword')
  onKeywordChange(): void {
    const keyword: string = this.fieldState.keyword.trim()
    if (keyword.length === 0) {
      this.clearQueryToHistory()
      this.vm.clearSuggestions()
      return
    }
    if (this.vm.isCurrentQuery(keyword)) {
      this.vm.clearSuggestions()
      return
    }
    this.vm.scheduleTagSuggest(this.fieldState.keyword, this.ctx())
  }

  // A whole-string EH URL (no embedded substring) — eros_fe gates its URL-jump on searchText.isURL,
  // so a query that merely CONTAINS a gallery link still searches.
  private looksLikeBareUrl(s: string): boolean {
    return s.length > 0 && !s.includes(' ') && (s.startsWith('http://') || s.startsWith('https://'))
  }

  private formatSuggestionQuery(s: EhTagSuggestion): string {
    return EhConstants.exactTagSearchQuery(s.namespace, s.text)
  }

  private suggestionNamespaceLabel(namespace: string): string {
    const ns: string = EhConstants.expandNamespace(namespace)
    if (ns === 'artist') return AppStrings.get('tag_ns_artist')
    if (ns === 'female') return AppStrings.get('tag_ns_female')
    if (ns === 'male') return AppStrings.get('tag_ns_male')
    if (ns === 'parody') return AppStrings.get('tag_ns_parody')
    if (ns === 'character') return AppStrings.get('tag_ns_character')
    if (ns === 'group') return AppStrings.get('tag_ns_group')
    if (ns === 'language') return AppStrings.get('tag_ns_language')
    if (ns === 'reclass') return AppStrings.get('tag_ns_reclass')
    if (ns === 'cosplayer') return AppStrings.get('tag_ns_cosplayer')
    if (ns === 'misc') return AppStrings.get('tag_ns_misc')
    if (ns === 'mixed') return AppStrings.get('tag_ns_mixed')
    if (ns === 'location') return AppStrings.get('tag_ns_location')
    if (ns === 'other') return AppStrings.get('tag_ns_other')
    if (ns === 'uploader') return AppStrings.get('tag_ns_uploader')
    if (ns === 'temp') return AppStrings.get('tag_ns_temp')
    return ns
  }

  private suggestionTitle(s: EhTagSuggestion): string {
    return s.displayName.length > 0 ?
      `${this.suggestionNamespaceLabel(s.namespace)}:${s.displayName}` :
      this.formatSuggestionQuery(s)
  }

  private suggestionSubtitle(s: EhTagSuggestion): string {
    const query: string = this.formatSuggestionQuery(s)
    if (s.displayName.length > 0) {
      return query
    }
    if (s.namespace.length > 0) {
      return `${AppStrings.get('search_suggestion_namespace')}${EhConstants.expandNamespace(s.namespace)}`
    }
    return ''
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
    TagTranslationService.touchSuggestion(this.ctx(), s).then(() => {})
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
        connectReaderOverlayNavigation().open(
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

  private clearAllSearchHistory(): void {
    SearchHistorySettings.clear(this.ctx())
  }

  private relationPrefix(relation: number): string {
    if (relation === TagRelation.NOT) {
      return '-'
    }
    if (relation === TagRelation.OR) {
      return '~'
    }
    return ''
  }

  private historyRawPart(tag: QueryTag): string {
    const prefix: string = this.relationPrefix(tag.relation)
    if (tag.namespace.length > 0) {
      return `${prefix}${tag.namespace}:${tag.text}`
    }
    return `${prefix}${tag.text}`
  }

  private historyTranslatedPart(tag: QueryTag, translated: string): string {
    const prefix: string = this.relationPrefix(tag.relation)
    if (tag.namespace.length > 0) {
      return `${prefix}${this.suggestionNamespaceLabel(tag.namespace)}:${translated}`
    }
    return `${prefix}${translated}`
  }

  private historyFullTag(tag: QueryTag): string {
    const text: string = this.historyTranslationKeyText(tag.text)
    if (tag.namespace.length > 0) {
      return `${EhConstants.expandNamespace(tag.namespace)}:${text}`
    }
    return `misc:${text}`
  }

  private historyTranslationKeyText(value: string): string {
    let text: string = EhConstants.canonicalTagText(value).trim().toLowerCase()
    if (text.startsWith('"')) {
      text = text.substring(1).trim()
    }
    if (text.endsWith('"')) {
      text = text.substring(0, text.length - 1).trim()
    }
    if (text.endsWith('$')) {
      text = text.substring(0, text.length - 1).trim()
    }
    if (text.endsWith('"')) {
      text = text.substring(0, text.length - 1).trim()
    }
    return text
  }

  private translateHistoryQueryFromCache(query: string, tagTranslations: Map<string, string>): string {
    const tags: QueryTag[] = TagQuery.parse(query)
    if (tags.length === 0) {
      return ''
    }
    const parts: string[] = []
    let changed: boolean = false
    for (let i = 0; i < tags.length; i++) {
      const tag: QueryTag = tags[i]
      const fullTag: string = this.historyFullTag(tag)
      const translated: string | undefined = tagTranslations.get(fullTag)
      if (translated !== undefined && translated.length > 0 && translated !== fullTag && translated !== tag.text) {
        parts.push(this.historyTranslatedPart(tag, translated))
        changed = true
      } else {
        parts.push(this.historyRawPart(tag))
      }
    }
    return changed ? parts.join('   ') : ''
  }

  private collectHistoryFullTags(items: string[]): string[] {
    const seen: Set<string> = new Set<string>()
    const out: string[] = []
    for (let i = 0; i < items.length; i++) {
      const tags: QueryTag[] = TagQuery.parse(items[i])
      for (let j = 0; j < tags.length; j++) {
        const fullTag: string = this.historyFullTag(tags[j])
        if (fullTag.length > 0 && !seen.has(fullTag)) {
          seen.add(fullTag)
          out.push(fullTag)
        }
      }
    }
    return out
  }

  private async refreshHistoryTranslations(): Promise<void> {
    this.historyTranslationRun = this.historyTranslationRun + 1
    const run: number = this.historyTranslationRun
    if (this.history.items.length === 0) {
      this.applyHistoryTranslations(new Map<string, string>())
      return
    }
    const items: string[] = this.history.items.slice()
    const missingItems: string[] = []
    const next: Map<string, string> = new Map<string, string>()
    for (let i = 0; i < items.length; i++) {
      const query: string = items[i]
      const cached: string | undefined = this.historyTranslations.get(query)
      if (cached !== undefined) {
        next.set(query, cached)
      } else {
        missingItems.push(query)
      }
    }
    if (missingItems.length === 0) {
      if (next.size !== this.historyTranslations.size) {
        this.applyHistoryTranslations(next)
      }
      return
    }
    const tagTranslations: Map<string, string> = await TagTranslationService.translateFullTagsAsync(
      this.ctx(),
      this.collectHistoryFullTags(missingItems),
    )
    for (let i = 0; i < missingItems.length; i++) {
      if (run !== this.historyTranslationRun) {
        return
      }
      const query: string = missingItems[i]
      next.set(query, this.translateHistoryQueryFromCache(query, tagTranslations))
    }
    if (run === this.historyTranslationRun) {
      this.applyHistoryTranslations(next)
    }
  }

  private applyHistoryTranslations(next: Map<string, string>): void {
    this.getUIContext().animateTo(
      { duration: SEARCH_HISTORY_CHIP_ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        this.historyTranslations = next
      },
    )
  }

  private historyTranslation(query: string): string {
    const translated: string | undefined = this.historyTranslations.get(query)
    return translated !== undefined ? translated : ''
  }

  private toggleHistoryTranslation(): void {
    const nextEnabled: boolean = !this.history.translateEnabled
    DiagnosticLogger.info(
      'search',
      'history_translate_toggle',
      `from=${this.history.translateEnabled ? 'on' : 'off'} to=${nextEnabled ? 'on' : 'off'}`,
    )
    this.getUIContext().animateTo(
      { duration: SEARCH_HISTORY_CHIP_ANIM_DURATION, curve: Curve.EaseOut },
      () => {
        SearchHistorySettings.setTranslateEnabled(this.ctx(), nextEnabled)
      },
    )
  }

  @Builder
  private HistoryTranslateButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.translate'))
        .fontSize(18)
        .fontColor([
          this.history.translateEnabled
            ? ThemeConstants.BRAND_PRIMARY
            : $r('sys.color.font_tertiary'),
        ])
    }
    .onClick(() => {
      this.toggleHistoryTranslation()
    })
    .width(28)
    .height(28)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .accessibilityText($r('app.string.tag_translation_title'))
  }

  @Builder
  private HistoryClearButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_emphasize')])
    }
    .onClick(() => {
      this.confirmClearAllSearchHistory()
    })
    .width(28)
    .height(28)
    .backgroundColor(Color.Transparent)
    .padding(0)
    .accessibilityText($r('app.string.search_history_clear'))
  }

  private confirmClearAllSearchHistory(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.search_history_clear_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.search_history_clear'),
        fontColor: Color.Red,
        action: () => {
          this.clearAllSearchHistory()
        },
      },
    })
  }

  @Builder
  SearchSuggestionView() {
    List({ space: ThemeConstants.SPACE_XS, scroller: this.suggestionScroller }) {
      ListItem() {
        Column() {
          Blank().height(this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + SEARCH_FIELD_BOTTOM_HEIGHT)
        }
        .width('100%')
      }
      .clip(false)

      ForEach(
        this.vm.suggestions,
        (s: EhTagSuggestion) => {
          ListItem() {
            Row({ space: ThemeConstants.SPACE_MD }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(24)
                .fontColor([$r('sys.color.font_tertiary')])
              Column({ space: ThemeConstants.SPACE_XS }) {
                Text(this.suggestionTitle(s))
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.suggestionSubtitle(s).length > 0) {
                  Text(this.suggestionSubtitle(s))
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
        (s: EhTagSuggestion, index: number) =>
          `suggestion_${index}_${s.namespace}_${s.text}`.replace(/[^A-Za-z0-9_]/g, '_'),
      )

      ListItem() {
        Column() {
          Blank().height(this.layout.bottomAvoidHeight + ThemeConstants.SPACE_LG)
        }
        .width('100%')
      }
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Monitor('filter.applySeq')
  onFilterApply(): void {
    // Persist live filter edits so they survive a restart (eros_fe keeps the advanced-search profile).
    SearchFilterSettings.persist(this.ctx())
    if (this.fieldState.keyword.trim().length > 0) {
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
    if (this.history.items.length > 0) {
      Scroll(this.historyScroller) {
        Column() {
          Row() {
            Text($r('app.string.search_history'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            this.HistoryTranslateButton()
            this.HistoryClearButton()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ bottom: ThemeConstants.SPACE_SM })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(
              this.history.items,
              (q: string) => {
                Column({ space: ThemeConstants.SPACE_XS }) {
                  Text(q)
                    .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                    .fontColor($r('sys.color.font_primary'))
                    .constraintSize({ maxWidth: '100%' })
                  if (this.history.translateEnabled && this.historyTranslation(q).length > 0) {
                    Text(this.historyTranslation(q))
                      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                      .fontColor($r('sys.color.font_secondary'))
                      .constraintSize({ maxWidth: '100%' })
                  }
                }
                  .alignItems(HorizontalAlign.Start)
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(ThemeConstants.RADIUS_ROUND)
                  .padding({
                    left: ThemeConstants.SPACE_MD,
                    right: ThemeConstants.SPACE_MD,
                    top: ThemeConstants.SPACE_XS,
                    bottom: ThemeConstants.SPACE_XS,
                  })
                  .margin({ right: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
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
        }
        .width('100%')
        .padding({
          left: ThemeConstants.SPACE_LG,
          right: ThemeConstants.SPACE_LG,
          top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + SEARCH_FIELD_BOTTOM_HEIGHT +
          ThemeConstants.SPACE_MD,
          bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_LG,
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    } else {
      Column() {
        Text($r('app.string.search_hint'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center)
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
      .justifyContent(FlexAlign.Center)
    }
  }

  private loadMoreIfTailAppeared(index: number): void {
    if (index < this.vm.itemCount - 1) {
      return
    }
    if (this.vm.canLoadMore()) {
      this.vm.loadMore()
    }
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
              pinchModeKey: ListMode.GRID,
              gap: ThemeConstants.GALLERY_GRID_GAP,
              horizontalPadding: ThemeConstants.GALLERY_GRID_GAP,
              topPadding: SEARCH_FIELD_BOTTOM_HEIGHT,
              bottomPadding: ThemeConstants.FLOAT_BAR_HEIGHT + ThemeConstants.SPACE_LG,
              itemCount: this.vm.itemCount,
              nearEndThreshold: 4,
              controller: this.refreshController,
              onRefresh: async () => {
                await this.vm.refresh()
              },
              onBottomRefresh: async () => {
                await this.vm.loadMore()
              },
              canStartBottomRefresh: () => this.vm.canLoadMore(),
              onReachEnd: () => {
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              onNearEnd: () => {
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              showFooter: true,
              footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
              footerHasMore: this.vm.hasMore,
              footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
              onFooterRetry: () => {
                this.vm.loadMore()
              },
            }) {
              LazyForEach(
                this.vm.dataSource,
                (g: EhGallery, index: number) => {
                  GridItem() {
                    GalleryGridCard({ gallery: g })
                  }
                  .onAppear(() => {
                    this.loadMoreIfTailAppeared(index)
                  })
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
                (g: EhGallery) => g.renderKey(),
              )
            }
          } else if (this.listMode.mode === ListMode.WATERFALL) {
            PullRefreshWaterFlowScaffold({
              scroller: this.scroller,
              minColumnWidth: ThemeConstants.GALLERY_WATERFALL_MIN_W,
              pinchModeKey: ListMode.WATERFALL,
              itemCount: this.vm.itemCount,
              nearEndThreshold: 4,
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
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              onNearEnd: () => {
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              showFooter: true,
              footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
              footerHasMore: this.vm.hasMore,
              footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
              onFooterRetry: () => {
                this.vm.loadMore()
              },
            }) {
              LazyForEach(
                this.vm.dataSource,
                (g: EhGallery, index: number) => {
                  FlowItem() {
                    GalleryWaterfallCard({ gallery: g })
                  }
                  .width('100%')
                  .onAppear(() => {
                    this.loadMoreIfTailAppeared(index)
                  })
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
                (g: EhGallery) => g.renderKey(),
              )
            }
          } else if (this.listMode.mode === ListMode.COVER_WALL) {
            PullRefreshWaterFlowScaffold({
              scroller: this.scroller,
              minColumnWidth: ThemeConstants.GALLERY_COVER_WALL_MIN_W,
              pinchModeKey: ListMode.COVER_WALL,
              itemCount: this.vm.itemCount,
              nearEndThreshold: 4,
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
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              onNearEnd: () => {
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              showFooter: true,
              footerIsLoading: this.vm.isLoadingMore || this.vm.isLoading,
              footerHasMore: this.vm.hasMore,
              footerIsError: this.vm.errorMessage.length > 0 && this.vm.hasMore,
              onFooterRetry: () => {
                this.vm.loadMore()
              },
            }) {
              LazyForEach(
                this.vm.dataSource,
                (g: EhGallery, index: number) => {
                  FlowItem() {
                    GalleryCoverWallCard({ gallery: g })
                  }
                  .width('100%')
                  .onAppear(() => {
                    this.loadMoreIfTailAppeared(index)
                  })
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
                (g: EhGallery) => g.renderKey(),
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
                if (this.vm.canLoadMore()) {
                  this.vm.loadMore()
                }
              },
              onContentWidth: (contentWidth: number) => {
                this.listContentWidth = contentWidth
              },
            }) {
              LazyForEach(
                this.vm.dataSource,
                (g: EhGallery, index: number) => {
                  ListItem() {
                    if (this.listMode.mode === ListMode.SIMPLE_LIST) {
                      GallerySimpleCard({ gallery: g })
                    } else {
                      GalleryCard({ gallery: g, listContentWidth: this.listContentWidth })
                    }
                  }
                  .onAppear(() => {
                    this.loadMoreIfTailAppeared(index)
                  })
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
                (g: EhGallery) => g.renderKey(),
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
      // The HDS title-bar menu is created from `searchMenu()` data and exposes only its action
      // callback here, not an app-owned trigger node. Keep this page host for that no-anchor flow.
      .bindSheet($$this.showFilter, this.FilterSheet(), appSheetOptions({
        detents: [SheetSize.LARGE],
        showClose: false,
      }))
    }
    .titleBar(this.searchTitleBar())
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: false,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP,
    })
    .bindToScrollable([this.scroller, this.suggestionScroller, this.historyScroller])
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      // The favorites title-bar magnifier pushed us with a favorite scope param (eros_fe
      // goSearchPage(searchType: favorite)). Seed the VM scope, but leave the page in compose/history
      // state until the user submits a non-empty query; favorite browse without f_search must be a
      // separate explicit entry, not the title-bar search action.
      if (context.pathInfo.param instanceof SearchPageParams) {
        const p: SearchPageParams = context.pathInfo.param as SearchPageParams
        this.fieldState.focusOnAppear = p.focusOnAppear
        if (p.searchType === 'favorite') {
          this.isFavoriteScope = true
          this.vm.seedFavoriteScope(p.favcat)
        }
        if (p.initialQuery.length > 0) {
          this.fieldState.keyword = p.initialQuery
          this.fieldState.seedSeq = this.fieldState.seedSeq + 1
          this.runQuery(p.initialQuery)
        }
      } else {
        this.fieldState.focusOnAppear = true
      }
    })
  }
}
