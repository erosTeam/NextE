import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, SymbolGlyphModifier, TabSegmentButtonV2 } from '@kit.ArkUI'
import {
  ThemeConstants,
  AppStrings,
  connectNavStack,
  immersiveTitleBarOpts,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
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
 * chose a page over a half-modal). The category grid + advanced controls are the shared CategorySelector
 * / AdvancedSearchControls bound to a TRANSIENT SearchFilterState seeded from the profile and read back on
 * save. Built-ins reduce to name-only (their type/search/cats are fixed). 保存 validates a non-empty name.
 */
@ComponentV2
export struct TabEditPage {
  private stack: NavPathStack = connectNavStack().stack;
  private uuid: string = '';
  @Local isCreate: boolean = true;
  @Local builtin: boolean = false;
  @Local name: string = '';
  @Local listType: string = PROFILE_TYPE_GALLERY;
  @Local searchText: string = '';
  @Local favcat: string = 'a';
  @Local toplistTl: number = 15;
  @Local displayMode: string = 'global';
  // Transient filter bound to the shared category/advanced controls; seeded on enter, read back on save.
  @Local filter: SearchFilterState = new SearchFilterState();
  @Local favSelection: FavSelectionState = connectFavSelection();
  @Local private periodItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '' },
    { text: '' },
    { text: '' },
    { text: '' },
  ]);
  @Local private typeMenuShown: boolean = false;
  @Local private favcatMenuShown: boolean = false;
  @Local private displayMenuShown: boolean = false;

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

  private typeLabelText(): string {
    for (let i = 0; i < TYPE_OPTIONS.length; i++) {
      if (TYPE_OPTIONS[i].value === this.listType) {
        return AppStrings.get(TYPE_OPTIONS[i].labelKey)
      }
    }
    return AppStrings.get('tab_type_gallery')
  }

  private displayLabelText(): string {
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

  @Builder
  private SectionLabel(label: ResourceStr) {
    Text(label)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .margin({ left: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_XS })
  }

  @Builder
  private TypeMenu() {
    Menu() {
      ForEach(
        TYPE_OPTIONS,
        (opt: TypeOption) => {
          MenuItem({
            content: $r(`app.string.${opt.labelKey}`),
            symbolEndIcon:
              this.listType === opt.value
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.listType = opt.value
            this.typeMenuShown = false
          })
        },
        (opt: TypeOption) => opt.value,
      )
    }
  }

  @Builder
  private FavcatMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.favorites_all'),
        symbolEndIcon:
          this.favcat === 'a' ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined,
      }).onClick(() => {
        this.favcat = 'a'
        this.favcatMenuShown = false
      })
      ForEach(
        this.favSelection.favList,
        (f: Favcat) => {
          MenuItem({
            content: f.favTitle.length > 0 ? f.favTitle : f.favId,
            symbolEndIcon:
              this.favcat === f.favId
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.favcat = f.favId
            this.favcatMenuShown = false
          })
        },
        (f: Favcat) => f.favId,
      )
    }
  }

  @Builder
  private DisplayMenu() {
    Menu() {
      ForEach(
        DISPLAY_OPTIONS,
        (opt: TypeOption) => {
          MenuItem({
            content: $r(`app.string.${opt.labelKey}`),
            symbolEndIcon:
              this.displayMode === opt.value
                ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
                : undefined,
          }).onClick(() => {
            this.displayMode = opt.value
            this.displayMenuShown = false
          })
        },
        (opt: TypeOption) => opt.value,
      )
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({ bottomPadding: ThemeConstants.SPACE_XL, alwaysEnableEdgeSpring: true }) {
        // Name
        ListItem() {
          Column() {
            this.SectionLabel($r('app.string.tab_name_label'))
            GroupedListSection() {
              TextInput({ text: this.name, placeholder: $r('app.string.tab_name_placeholder') })
                .width('100%')
                .height(48)
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(ThemeConstants.RADIUS_ROUND)
                .onChange((value: string) => {
                  this.name = value
                })
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        if (!this.builtin) {
          // List type
          ListItem() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.tab_list_type'),
                  trailingText: this.typeLabelText(),
                  trailingDropdown: true,
                  action: () => {
                    this.typeMenuShown = true
                  },
                })
              }
              .bindMenu(this.typeMenuShown, this.TypeMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.typeMenuShown = false
                },
              })
            }
          }
          // Favorite favcat selector
          if (this.listType === PROFILE_TYPE_FAVORITE) {
            ListItem() {
              GroupedListSection() {
                Column() {
                  ConciseListRow({
                    title: $r('app.string.tab_favcat'),
                    trailingText: this.favcatLabel(),
                    trailingDropdown: true,
                    action: () => {
                      this.favcatMenuShown = true
                    },
                  })
                }
                .bindMenu(this.favcatMenuShown, this.FavcatMenu, {
                  placement: Placement.BottomRight,
                  onDisappear: () => {
                    this.favcatMenuShown = false
                  },
                })
              }
            }
          }
          // Toplist period
          if (this.listType === PROFILE_TYPE_TOPLIST) {
            ListItem() {
              Column() {
                this.SectionLabel($r('app.string.tab_toplist_period'))
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
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }
          // Category
          if (this.usesFilters()) {
            ListItem() {
              Column() {
                this.SectionLabel($r('app.string.tab_category'))
                GroupedListSection() {
                  CategorySelector({ filter: this.filter })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
            // Search text
            ListItem() {
              Column() {
                this.SectionLabel($r('app.string.tab_search_text'))
                GroupedListSection() {
                  TextInput({ text: this.searchText, placeholder: $r('app.string.search_placeholder') })
                    .width('100%')
                    .height(48)
                    .fontSize(ThemeConstants.FONT_SIZE_BODY)
                    .backgroundColor($r('app.color.card_background'))
                    .borderRadius(ThemeConstants.RADIUS_ROUND)
                    .onChange((value: string) => {
                      this.searchText = value
                    })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }
          // Advanced search
          if (this.usesAdvanced()) {
            ListItem() {
              Column() {
                this.SectionLabel($r('app.string.tab_advanced'))
                GroupedListSection() {
                  AdvancedSearchControls({ filter: this.filter })
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
          }
          // Display mode (per-tab renderer; 'global' follows the shared default)
          ListItem() {
            GroupedListSection() {
              Column() {
                ConciseListRow({
                  title: $r('app.string.tab_display_mode'),
                  trailingText: this.displayLabelText(),
                  trailingDropdown: true,
                  action: () => {
                    this.displayMenuShown = true
                  },
                })
              }
              .bindMenu(this.displayMenuShown, this.DisplayMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.displayMenuShown = false
                },
              })
            }
          }
          // Delete (existing custom profiles only)
          if (!this.isCreate) {
            ListItem() {
              GroupedListSection() {
                Row() {
                  Text($r('app.string.common_delete'))
                    .fontSize(ThemeConstants.FONT_SIZE_BODY)
                    .fontColor(Color.Red)
                    .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(18)
                    .fontColor([Color.Red])
                }
                .width('100%')
                .height(48)
                .onClick(() => {
                  this.confirmDelete()
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
