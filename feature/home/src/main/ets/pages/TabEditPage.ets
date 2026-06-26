import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import {
  ThemeConstants,
  AppStrings,
  connectNavStack,
  immersiveTitleBarOpts,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  SettingsCheckedMenuItem,
  CategorySelector,
  AdvancedSearchControls,
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

/** One selectable option for a TabSelectRow dropdown (string value + resolved label). */
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
  { value: ListMode.COVER_WALL, labelKey: 'view_cover_wall' },
]
const TOPLIST_TLS: number[] = [11, 12, 13, 15]

/**
 * Create / edit one custom home sub-tab profile (eros_fe profile editor) — a full routed page (the user
 * chose a page over a half-modal). Built on the app's standard settings-form chrome: SecondaryListScaffold
 * + SectionHeader + GroupedListSection cards of ConciseListRow-based rows (TabSelectRow / TabTextRow), so
 * it reads exactly like EhProfileSettingsPage and the layout settings page — no hand-rolled rows. The
 * category grid + advanced controls are the shared CategorySelector / AdvancedSearchControls bound to a
 * TRANSIENT SearchFilterState seeded from the profile and read back on 保存. Built-ins reduce to name-only.
 */
@ComponentV2
export struct TabEditPage {
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();
  private uuid: string = '';
  @Local isCreate: boolean = true;
  @Local builtin: boolean = false;
  @Local name: string = '';
  @Local listType: string = PROFILE_TYPE_GALLERY;
  @Local searchText: string = '';
  @Local favcat: string = 'a';
  @Local toplistTl: number = 15;
  @Local displayMode: string = PROFILE_DISPLAY_GLOBAL;
  // Transient filter bound to the shared category/advanced controls; seeded on enter, read back on save.
  @Local filter: SearchFilterState = new SearchFilterState();
  @Local favSelection: FavSelectionState = connectFavSelection();
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
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // ── option lists ──────────────────────────────────────────────────────────
  private typeOptions(): SelectOption[] {
    return TYPE_OPTIONS.map((o: TypeOption) => new SelectOption(o.value, AppStrings.get(o.labelKey)))
  }

  private displayOptions(): SelectOption[] {
    return DISPLAY_OPTIONS.map(
      (o: TypeOption) => new SelectOption(o.value, AppStrings.get(o.labelKey)),
    )
  }

  private favcatOptions(): SelectOption[] {
    const out: SelectOption[] = [new SelectOption('a', AppStrings.get('favorites_all'))]
    this.favSelection.favList.forEach((f: Favcat) => {
      out.push(new SelectOption(f.favId, f.favTitle.length > 0 ? f.favTitle : f.favId))
    })
    return out
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
    const trimmed: string = this.name.trim()
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

  // ── shared form chrome (mirrors EhProfileSettingsPage) ──────────────────────
  @Builder
  private SectionHeader(title: ResourceStr) {
    Text(title)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        top: ThemeConstants.SPACE_MD,
        bottom: ThemeConstants.SPACE_XS,
      })
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
        alwaysEnableEdgeSpring: true,
      }) {
        // Basic: name, list type, (favorite folder)
        ListItem() {
          GroupedListSection() {
            TabTextRow({
              title: $r('app.string.tab_name_label'),
              value: this.name,
              placeholder: $r('app.string.tab_name_placeholder'),
              onChange: (v: string) => {
                this.name = v
              },
            })
            if (!this.builtin) {
              this.rowDivider()
              TabSelectRow({
                title: $r('app.string.tab_list_type'),
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
                  options: this.favcatOptions(),
                  current: this.favcat,
                  onPick: (v: string) => {
                    this.favcat = v
                  },
                })
              }
            }
          }
        }

        if (!this.builtin) {
          // Toplist period
          if (this.listType === PROFILE_TYPE_TOPLIST) {
            ListItem() {
              Column() {
                this.SectionHeader($r('app.string.tab_toplist_period'))
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
            }
          }

          // Category
          if (this.usesFilters()) {
            ListItem() {
              Column() {
                this.SectionHeader($r('app.string.tab_category'))
                GroupedListSection() {
                  CategorySelector({ filter: this.filter })
                }
              }
            }
            // Search text
            ListItem() {
              GroupedListSection() {
                TabTextRow({
                  title: $r('app.string.tab_search_text'),
                  value: this.searchText,
                  placeholder: $r('app.string.search_placeholder'),
                  onChange: (v: string) => {
                    this.searchText = v
                  },
                })
              }
            }
          }

          // Advanced search (its own master toggle heads the card)
          if (this.usesAdvanced()) {
            ListItem() {
              Column() {
                this.SectionHeader($r('app.string.tab_advanced'))
                GroupedListSection() {
                  AdvancedSearchControls({ filter: this.filter })
                }
              }
            }
          }

          // Display mode
          ListItem() {
            GroupedListSection() {
              TabSelectRow({
                title: $r('app.string.tab_display_mode'),
                options: this.displayOptions(),
                current: this.displayMode,
                onPick: (v: string) => {
                  this.displayMode = v
                },
              })
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

/** Label + dropdown row bound to a string-valued option set (ConciseListRow + bindMenu, app-standard). */
@ComponentV2
struct TabSelectRow {
  @Param title: ResourceStr = '';
  @Param options: SelectOption[] = [];
  @Param current: string = '';
  @Event onPick: (value: string) => void = () => {};
  @Local private menuShown: boolean = false;

  private currentLabel(): ResourceStr {
    for (let i: number = 0; i < this.options.length; i++) {
      if (this.options[i].value === this.current) {
        return this.options[i].label
      }
    }
    return ''
  }

  build() {
    Column() {
      ConciseListRow({
        title: this.title,
        trailingText: this.currentLabel(),
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
  }
}

/** Label + inline text field, built ON ConciseListRow so the title matches every other row exactly
 * (the input lives in the row's suffix slot). Mirrors EhProfileSettingsPage's UcTextRow. */
@ComponentV2
struct TabTextRow {
  @Param title: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Event onChange: (value: string) => void = () => {};

  build() {
    ConciseListRow({
      title: this.title,
      showChevron: false,
      suffixPaddingRight: ThemeConstants.SPACE_MD,
      suffixBuilderParam: () => {
        this.InputSuffix()
      },
    })
  }

  @Builder
  InputSuffix() {
    TextInput({ text: this.value, placeholder: this.placeholder })
      .textAlign(TextAlign.End)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_primary'))
      .backgroundColor(Color.Transparent)
      .padding(0)
      .width(200)
      .onChange((v: string) => {
        this.onChange(v)
      })
  }
}
