import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode, LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import {
  ThemeConstants,
  AppStrings,
  connectNavStack,
  immersiveTitleBarOpts,
  SecondaryListScaffold,
  GroupedListSection,
  SectionHeader,
  ConciseListRow,
  InlineEditRow,
  SettingsCheckedMenuItem,
  CategorySelector,
  AdvancedSearchControls,
  TagQueryComposer,
  TagRow,
  TagQuery,
  QueryTag,
  TagRowItem,
  TagTranslationService,
  connectTagTranslationSettings,
  SearchFilterState,
  connectCustomProfiles,
  CustomProfile,
  CustomProfilesSettings,
  newProfileUuid,
  connectFavSelection,
  FavSelectionState,
  Favcat,
  ListMode,
  PROFILE_DISPLAY_GLOBAL,
  PROFILE_TYPE_GALLERY,
  PROFILE_TYPE_POPULAR,
  PROFILE_TYPE_WATCHED,
  PROFILE_TYPE_TOPLIST,
  PROFILE_TYPE_FAVORITE,
} from 'shared'

/** One option for a dropdown row (string value + resolved label). */
class SelectOption {
  value: string
  label: ResourceStr

  constructor(value: string, label: ResourceStr) {
    this.value = value
    this.label = label
  }
}

interface TypeOption {
  value: string
  labelKey: string
}

const TYPE_OPTIONS: TypeOption[] = [
  { value: PROFILE_TYPE_GALLERY, labelKey: 'tab_type_gallery' },
  { value: PROFILE_TYPE_POPULAR, labelKey: 'tab_type_popular' },
  { value: PROFILE_TYPE_WATCHED, labelKey: 'tab_type_watched' },
  { value: PROFILE_TYPE_TOPLIST, labelKey: 'tab_type_toplist' },
  { value: PROFILE_TYPE_FAVORITE, labelKey: 'tab_type_favorite' },
]
const DISPLAY_OPTIONS: TypeOption[] = [
  { value: PROFILE_DISPLAY_GLOBAL, labelKey: 'view_follow_global' },
  { value: ListMode.LIST, labelKey: 'view_list' },
  { value: ListMode.SIMPLE_LIST, labelKey: 'view_simple' },
  { value: ListMode.GRID, labelKey: 'view_grid' },
  { value: ListMode.WATERFALL, labelKey: 'view_waterfall' },
  { value: ListMode.WATERFALL_COMPACT, labelKey: 'view_waterfall_compact' },
  { value: ListMode.COVER_WALL, labelKey: 'view_cover_wall' },
]
const TOPLIST_TLS: number[] = [11, 12, 13, 15]

/**
 * Create / edit one custom home sub-tab profile. Built ENTIRELY from the app's standard list components —
 * SecondaryListScaffold + SectionHeader + GroupedListSection + ConciseListRow (dropdown / value rows), the
 * name edited in an AppModalScaffold sheet, the tag query via the shared TagQueryComposer, categories via
 * CategorySelector, advanced via AdvancedSearchControls. No hand-rolled rows, so margins / text indent /
 * dropdown icons match every other settings screen by construction. Built-ins reduce to name-only.
 */
@ComponentV2
export struct TabEditPage {
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private uuid: string = '';
  @Local isCreate: boolean = true;
  @Local builtin: boolean = false;
  @Local name: string = '';
  // Edits land here (a plain member) instead of reassigning @Local name on every keystroke — reassigning the
  // @Local re-renders the whole page, which re-creates the ConciseListRow suffix and re-mounts the TextInput
  // (dropping the soft keyboard). `name` stays the stable seed the field is built from; `nameDraft` is saved.
  private nameDraft: string = '';
  @Local listType: string = PROFILE_TYPE_GALLERY;
  @Local searchText: string = '';
  @Local favcat: string = 'a';
  @Local toplistTl: number = 15;
  @Local displayMode: string = PROFILE_DISPLAY_GLOBAL;
  @Local filter: SearchFilterState = new SearchFilterState();
  @Local favSelection: FavSelectionState = connectFavSelection();
  // ns:text -> translated display name for the added tag rows (resolved async as searchText changes).
  @Local private trans: Map<string, string> = new Map<string, string>();
  @Local private periodItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '' },
    { text: '' },
    { text: '' },
    { text: '' },
  ]);

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.periodItems[0].text = AppStrings.get('toplist_all')
    this.periodItems[1].text = AppStrings.get('toplist_year')
    this.periodItems[2].text = AppStrings.get('toplist_month')
    this.periodItems[3].text = AppStrings.get('toplist_yesterday')
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private seedFromParam(param: string): void {
    this.uuid = param
    const p: CustomProfile | null =
      param.length > 0 ? connectCustomProfiles().findByUuid(param) : null
    if (p === null) {
      this.isCreate = true
      return
    }
    this.isCreate = false
    this.builtin = p.builtin
    this.name = p.name
    this.nameDraft = p.name
    this.listType = p.listType
    this.searchText = p.searchText
    this.favcat = p.favcat
    this.toplistTl = p.toplistTl
    this.displayMode = p.displayMode
    this.filter.selectedCats = p.selectedCats
    this.filter.advancedEnabled = p.advancedEnabled
    this.filter.minRating = p.minRating
    this.filter.pagesFrom = p.pagesFrom
    this.filter.pagesTo = p.pagesTo
    this.filter.requireTorrent = p.requireTorrent
    this.filter.showExpunged = p.showExpunged
    this.filter.disableLanguageFilter = p.disableLanguageFilter
    this.filter.disableUploaderFilter = p.disableUploaderFilter
    this.filter.disableTagFilter = p.disableTagFilter
    this.ensureTranslations()
  }

  // ── added tag rows (rendered here, in the scaffold List, so each gets native swipe-to-delete) ──
  private tagRowItems(): TagRowItem[] {
    const out: TagRowItem[] = []
    TagQuery.parse(this.searchText).forEach((t: QueryTag, i: number) => {
      const name: string | undefined = this.trans.get(TagQuery.keyOf(t))
      out.push(new TagRowItem(t, i, name !== undefined ? name : ''))
    })
    return out
  }

  @Monitor('searchText')
  private onSearchTextChanged(): void {
    this.ensureTranslations()
  }

  private async ensureTranslations(): Promise<void> {
    if (!connectTagTranslationSettings().enabled) {
      return
    }
    const tags: QueryTag[] = TagQuery.parse(this.searchText)
    let changed: boolean = false
    const next: Map<string, string> = new Map<string, string>()
    this.trans.forEach((v: string, k: string) => next.set(k, v))
    for (let i = 0; i < tags.length; i++) {
      const t: QueryTag = tags[i]
      if (t.namespace.length === 0) {
        continue
      }
      const key: string = TagQuery.keyOf(t)
      if (next.has(key)) {
        continue
      }
      try {
        const full: string = `${t.namespace}:${t.text}`
        const name: string = await TagTranslationService.translateFullTagAsync(this.ctx(), full)
        if (name.length > 0 && name !== full && name !== t.text) {
          next.set(key, name)
          changed = true
        }
      } catch (err) {
        // translation is best-effort; the raw token still shows.
      }
    }
    if (changed) {
      this.trans = next
    }
  }

  private setTagRelation(index: number, relation: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.searchText)
    if (index >= 0 && index < tags.length) {
      tags[index].relation = relation
      this.searchText = TagQuery.serialize(tags)
    }
  }

  private removeTag(index: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.searchText)
    if (index >= 0 && index < tags.length) {
      tags.splice(index, 1)
      this.searchText = TagQuery.serialize(tags)
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // ── option lists ──────────────────────────────────────────────────────────
  private typeOptions(): SelectOption[] {
    return TYPE_OPTIONS.map((o: TypeOption) => new SelectOption(o.value, AppStrings.get(o.labelKey)))
  }

  private displayOptions(): SelectOption[] {
    return DISPLAY_OPTIONS.map((o: TypeOption) => new SelectOption(o.value, AppStrings.get(o.labelKey)))
  }

  private favcatOptions(): SelectOption[] {
    const out: SelectOption[] = [new SelectOption('a', AppStrings.get('favorites_all'))]
    this.favSelection.favList.forEach((f: Favcat) => {
      out.push(new SelectOption(f.favId, f.favTitle.length > 0 ? f.favTitle : f.favId))
    })
    return out
  }

  private typeLabel(): string {
    for (let i = 0; i < TYPE_OPTIONS.length; i++) {
      if (TYPE_OPTIONS[i].value === this.listType) {
        return AppStrings.get(TYPE_OPTIONS[i].labelKey)
      }
    }
    return AppStrings.get('tab_type_gallery')
  }

  private displayLabel(): string {
    for (let i = 0; i < DISPLAY_OPTIONS.length; i++) {
      if (DISPLAY_OPTIONS[i].value === this.displayMode) {
        return AppStrings.get(DISPLAY_OPTIONS[i].labelKey)
      }
    }
    return AppStrings.get('view_follow_global')
  }

  private favcatLabel(): string {
    if (this.favcat === 'a') {
      return AppStrings.get('favorites_all')
    }
    const list: Favcat[] = this.favSelection.favList
    for (let i = 0; i < list.length; i++) {
      if (list[i].favId === this.favcat) {
        return list[i].favTitle.length > 0 ? list[i].favTitle : this.favcat
      }
    }
    return this.favcat
  }

  // ── derived state ─────────────────────────────────────────────────────────
  private usesFilters(): boolean {
    return (
      this.listType === PROFILE_TYPE_GALLERY ||
      this.listType === PROFILE_TYPE_WATCHED ||
      this.listType === PROFILE_TYPE_FAVORITE
    )
  }

  private usesAdvanced(): boolean {
    return this.listType === PROFILE_TYPE_GALLERY || this.listType === PROFILE_TYPE_WATCHED
  }

  private periodIndex(): number {
    const i: number = TOPLIST_TLS.indexOf(this.toplistTl)
    return i >= 0 ? i : 3
  }

  private periodForIndex(index: number): number {
    return index >= 0 && index < TOPLIST_TLS.length ? TOPLIST_TLS[index] : 15
  }

  // ── actions ───────────────────────────────────────────────────────────────
  private save(): void {
    const trimmed: string = this.nameDraft.trim()
    if (trimmed.length === 0) {
      this.toast($r('app.string.tab_name_required'))
      return
    }
    const p: CustomProfile = new CustomProfile()
    p.uuid = this.isCreate ? newProfileUuid() : this.uuid
    p.name = trimmed
    p.listType = this.listType
    p.searchText = this.searchText.trim()
    p.selectedCats = this.filter.selectedCats
    p.advancedEnabled = this.filter.advancedEnabled
    p.minRating = this.filter.minRating
    p.pagesFrom = this.filter.pagesFrom
    p.pagesTo = this.filter.pagesTo
    p.requireTorrent = this.filter.requireTorrent
    p.showExpunged = this.filter.showExpunged
    p.disableLanguageFilter = this.filter.disableLanguageFilter
    p.disableUploaderFilter = this.filter.disableUploaderFilter
    p.disableTagFilter = this.filter.disableTagFilter
    p.favcat = this.favcat
    p.toplistTl = this.toplistTl
    p.displayMode = this.displayMode
    p.builtin = this.builtin
    if (this.isCreate) {
      CustomProfilesSettings.add(this.ctx(), p)
    } else {
      CustomProfilesSettings.update(this.ctx(), p)
    }
    this.stack.pop()
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tab_delete_confirm_title'),
      message: $r('app.string.tab_delete_confirm_message'),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: Color.Red,
        action: () => {
          CustomProfilesSettings.remove(this.ctx(), this.uuid)
          this.stack.pop()
        },
      },
    })
  }

  private titleBar(): Record<string, Object> {
    const item: Record<string, Object> = {
      'label': AppStrings.get('common_save'),
      'icon': $r('sys.symbol.checkmark'),
      'isEnabled': true,
      'action': (): void => {
        this.save()
      },
    }
    const itemWrap: Record<string, Object> = { 'content': item }
    const menu: Record<string, Object> = { 'value': [itemWrap], 'maxCount': 1 }
    const titleText: string = this.isCreate
      ? AppStrings.get('tabs_create_title')
      : AppStrings.get('tabs_edit_title')
    const title: Record<string, Object> = { 'mainTitle': titleText }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  // 搜索词 = one card-styled ListItemGroup: the add field sits in the group's HEADER slot (a stable element
  // that isn't torn down when the item list changes), and each added tag is a swipe-to-delete item. This is
  // why the soft keyboard survives adding/removing tags — the input is the header, not a recycled item.
  @Builder
  private SearchFieldHeader() {
    Column() {
      TagQueryComposer({
        query: this.searchText,
        onQueryChange: (q: string) => {
          this.searchText = q
        },
      })
    }
    .width('100%')
  }

  @Builder
  private SearchGroup() {
    ListItemGroup({ header: this.SearchFieldHeader(), space: 0 }) {
      ForEach(
        this.tagRowItems(),
        (it: TagRowItem) => {
          ListItem() {
            Column() {
              this.rowDivider()
              TagRow({
                tag: it.tag,
                index: it.index,
                displayName: it.displayName,
                onSetRelation: (index: number, rel: number) => {
                  this.setTagRelation(index, rel)
                },
              })
            }
            .width('100%')
          }
          .swipeAction({
            end: () => {
              this.DeleteSwipe(it.index)
            },
          })
        },
        (it: TagRowItem, index: number) =>
          `tag_${index}_${it.tag.relation}_${it.tag.namespace}_${it.tag.text}_${it.displayName}`.replace(/[^A-Za-z0-9_]/g, '_'),
      )
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .clip(true)
    .padding(ThemeConstants.LIST_SECTION_INSET)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private DeleteSwipe(index: number) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.White])
      }
      .width(48)
      .height(40)
      .backgroundColor(Color.Red)
      .onClick(() => {
        this.removeTag(index)
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
      }) {
        // Basics — name, list type, (favcat), display mode.
        ListItem() {
          Column() {
            SectionHeader({ title: $r('app.string.tab_section_basic') })
            GroupedListSection() {
              InlineEditRow({
                title: $r('app.string.tab_name_label'),
                value: this.name,
                placeholder: $r('app.string.tab_name_placeholder'),
                onChange: (v: string) => {
                  this.nameDraft = v
                },
              })
              if (!this.builtin) {
                this.rowDivider()
                TabSelectRow({
                  title: $r('app.string.tab_list_type'),
                  value: this.typeLabel(),
                  options: this.typeOptions(),
                  current: this.listType,
                  onPick: (v: string) => {
                    this.listType = v
                  },
                })
                if (this.listType === PROFILE_TYPE_FAVORITE) {
                  this.rowDivider()
                  TabSelectRow({
                    title: $r('app.string.tab_favcat'),
                    value: this.favcatLabel(),
                    options: this.favcatOptions(),
                    current: this.favcat,
                    onPick: (v: string) => {
                      this.favcat = v
                    },
                  })
                }
                this.rowDivider()
                TabSelectRow({
                  title: $r('app.string.tab_display_mode'),
                  value: this.displayLabel(),
                  options: this.displayOptions(),
                  current: this.displayMode,
                  onPick: (v: string) => {
                    this.displayMode = v
                  },
                })
              }
            }
          }
          .alignItems(HorizontalAlign.Start)
        }

        if (!this.builtin) {
          // Toplist period
          if (this.listType === PROFILE_TYPE_TOPLIST) {
            ListItem() {
              Column() {
                SectionHeader({ title: $r('app.string.tab_toplist_period') })
                GroupedListSection() {
                  TabSegmentButtonV2({
                    items: this.periodItems,
                    selectedIndex: this.periodIndex(),
                    enableStateAnimation: true,
                    itemFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
                    itemSelectedFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_BODY),
                    onItemClicked: (index: number) => {
                      this.toplistTl = this.periodForIndex(index)
                    },
                  })
                    .width('100%')
                    .constraintSize({ minHeight: 44 })
                    .padding({
                      left: ThemeConstants.SPACE_SM,
                      right: ThemeConstants.SPACE_SM,
                      top: ThemeConstants.SPACE_SM,
                      bottom: ThemeConstants.SPACE_SM,
                    })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }

          if (this.usesFilters()) {
            // Search tags — header above, then a card-styled ListItemGroup (the add field + each tag as a
            // swipe-to-delete row; tight rows, native swipe — only possible because these are real ListItems).
            ListItem() {
              Column() {
                SectionHeader({ title: $r('app.string.tab_search_text') })
              }
              .alignItems(HorizontalAlign.Start)
            }
            this.SearchGroup()
            // Categories
            ListItem() {
              Column() {
                SectionHeader({ title: $r('app.string.tab_category') })
                GroupedListSection() {
                  CategorySelector({ filter: this.filter })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }

          // Advanced
          if (this.usesAdvanced()) {
            ListItem() {
              Column() {
                SectionHeader({ title: $r('app.string.tab_advanced') })
                GroupedListSection() {
                  AdvancedSearchControls({ filter: this.filter })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }

          // Delete (existing custom profiles only)
          if (!this.isCreate) {
            ListItem() {
              GroupedListSection() {
                ConciseListRow({
                  title: $r('app.string.common_delete'),
                  leadingIcon: $r('sys.symbol.trash'),
                  destructive: true,
                  showChevron: false,
                  action: () => {
                    this.confirmDelete()
                  },
                })
              }
            }
            .margin({ top: ThemeConstants.SPACE_LG })
          }
        }
      }
    }
    .titleBar(this.titleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const param: string = context.pathInfo.param as string
      this.seedFromParam(typeof param === 'string' ? param : '')
    })
  }
}

/** Label + value + dropdown row, on the standard ConciseListRow trailingDropdown (same arrow as every other
 * dropdown in the app); the menu is a checked-item list. No hand-rolled chrome. */
@ComponentV2
struct TabSelectRow {
  @Param title: ResourceStr = '';
  @Param value: string = '';
  @Param options: SelectOption[] = [];
  @Param current: string = '';
  @Event onPick: (value: string) => void = () => {};
  @Local private menuShown: boolean = false;

  build() {
    Column() {
      ConciseListRow({
        title: this.title,
        trailingText: this.value,
        trailingDropdown: true,
        action: () => {
          this.menuShown = true
        },
      })
    }
    .bindMenu(this.menuShown, this.OptionMenu, {
      placement: Placement.BottomRight,
      onDisappear: () => {
        this.menuShown = false
      },
    })
  }

  @Builder
  OptionMenu() {
    Menu() {
      ForEach(
        this.options,
        (option: SelectOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: option.value === this.current,
            selectAction: () => {
              this.onPick(option.value)
              this.menuShown = false
            },
          })
        },
        (option: SelectOption) => option.value,
      )
    }
    .backgroundColor($r('app.color.card_background'))
  }
}
