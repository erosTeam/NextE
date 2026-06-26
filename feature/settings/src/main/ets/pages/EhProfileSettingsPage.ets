import { HdsNavDestination, IconStyleMode } from '@kit.UIDesignKit'
import {
  ColorMetrics,
  LengthMetrics,
  MultiCapsuleSegmentButtonV2,
  SegmentButtonV2Items,
  SegmentButtonV2ItemOptions,
} from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  AppModalScaffold,
  appSheetOptions,
  AppStrings,
  ConciseListRow,
  EhApiService,
  EhConstants,
  EhProfile,
  EhProfileSettings,
  EhUconfigCategory,
  EhUconfigToggleItem,
  GalleryWebParams,
  GroupedListSection,
  SecondaryListScaffold,
  SettingsCheckedMenuItem,
  SiteModeState,
  ThemeConstants,
  connectNavStack,
  connectSiteMode,
  immersiveTitleBarOpts,
} from 'shared'

/** One excluded-language table row: the language name + its present variant toggles (orig/trans/rewrite). */
class EhLanguageRow {
  name: string = ''
  variants: EhUconfigToggleItem[] = []

  constructor(name: string) {
    this.name = name
  }
}

/** One radio-group choice: the EH form value + its display label. */
class UcOption {
  value: number
  label: ResourceStr

  constructor(value: number, label: ResourceStr) {
    this.value = value
    this.label = label
  }
}

/**
 * Native editor for the EH user config (uconfig.php). Loads via EhApiService.getUserConfig, edits the
 * reactive EhProfileSettings model in place, and writes back with the Save action (POST, non-idempotent).
 * The top-right also opens EH's own /uconfig.php in the in-app WebView. Profile switching (sp) and the
 * xn/xl exclusion lists are deferred to a follow-up.
 */
@ComponentV2
export struct EhProfileSettingsPage {
  @Local site: SiteModeState = connectSiteMode();
  @Local settings: EhProfileSettings = new EhProfileSettings();
  @Local langRows: EhLanguageRow[] = [];
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local failed: boolean = false;
  @Local profileBusy: boolean = false;
  @Local nameSheetShown: boolean = false;
  @Local nameInput: string = '';
  private nameAction: string = 'create';
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  aboutToAppear(): void {
    this.load()
  }

  private load(): void {
    this.loading = true
    this.failed = false
    EhApiService.getInstance()
      .getUserConfig(this.site.isEx)
      .then((s: EhProfileSettings) => {
        this.applyLoaded(s)
        this.loading = false
      })
      .catch(() => {
        this.failed = true
        this.loading = false
      })
  }

  private applyLoaded(s: EhProfileSettings): void {
    this.settings = s
    this.langRows = EhProfileSettingsPage.groupLanguages(s.excludedLanguages)
  }

  // ── Profile actions (POST uconfig.php; the response is the resulting profile's config). ──
  private profileOptions(): UcOption[] {
    return this.settings.profiles.map((p: EhProfile) => new UcOption(p.value, p.name))
  }

  private currentProfileName(): string {
    for (let i: number = 0; i < this.settings.profiles.length; i++) {
      if (this.settings.profiles[i].value === this.settings.selectedProfile) {
        return this.settings.profiles[i].name
      }
    }
    return ''
  }

  private runProfileAction(action: string, profileSet: string, name: string): void {
    if (this.profileBusy) {
      return
    }
    this.profileBusy = true
    EhApiService.getInstance()
      .postProfileAction(this.site.isEx, action, profileSet, name)
      .then((s: EhProfileSettings) => {
        this.applyLoaded(s)
        this.toast($r('app.string.ehp_profile_done'))
      })
      .catch(() => {
        this.toast($r('app.string.ehp_profile_failed'))
      })
      .finally(() => {
        this.profileBusy = false
      })
  }

  private selectProfile(value: number): void {
    if (value !== this.settings.selectedProfile) {
      this.runProfileAction('', `${value}`, '')
    }
  }

  private openNameSheet(action: string): void {
    this.nameAction = action
    this.nameInput = action === 'rename' ? this.currentProfileName() : ''
    this.nameSheetShown = true
  }

  private confirmNameSheet(): void {
    const name: string = this.nameInput.trim()
    if (name.length === 0) {
      return
    }
    this.nameSheetShown = false
    if (this.nameAction === 'rename') {
      this.runProfileAction('rename', `${this.settings.selectedProfile}`, name)
    } else {
      this.runProfileAction('create', '', name)
    }
  }

  private confirmDeleteProfile(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.ehp_profile_delete'),
      message: $r('app.string.ehp_profile_delete_confirm'),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.ehp_profile_delete'),
        fontColor: Color.Red,
        action: () => {
          this.runProfileAction('delete', `${this.settings.selectedProfile}`, '')
        },
      },
    })
  }

  private save(): void {
    if (this.loading || this.saving) {
      return
    }
    this.saving = true
    EhApiService.getInstance()
      .saveUserConfig(this.site.isEx, this.settings)
      .then(() => {
        this.toast($r('app.string.ehp_saved'))
      })
      .catch(() => {
        this.toast($r('app.string.ehp_save_failed'))
      })
      .finally(() => {
        this.saving = false
      })
  }

  private openWeb(): void {
    const url: string = `${EhConstants.baseUrl(this.site.isEx)}/uconfig.php`
    this.stack.pushPathByName('GalleryWeb', new GalleryWebParams(url, AppStrings.get('ehp_title')))
  }

  // ── Title bar with Save + open-in-web actions (top-right). ──
  private titleContent(): Record<string, Object> {
    const saveContent: Record<string, Object> = {
      'label': AppStrings.get('common_save'),
      'icon': $r('sys.symbol.checkmark'),
      'isEnabled': !this.loading && !this.saving,
      'type': IconStyleMode.NORMAL,
      'action': () => {
        this.save()
      },
    }
    const webContent: Record<string, Object> = {
      'label': AppStrings.get('ehp_open_web'),
      'icon': $r('sys.symbol.link'),
      'isEnabled': true,
      'type': IconStyleMode.NORMAL,
      'action': () => {
        this.openWeb()
      },
    }
    const saveItem: Record<string, Object> = { 'content': saveContent }
    const webItem: Record<string, Object> = { 'content': webContent }
    const items: Object[] = [saveItem, webItem]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 2 }
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('ehp_title') }
    return { 'title': title, 'menu': menu }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SecondaryListScaffold({
          scroller: this.scroller,
          bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
        }) {
          if (this.loading) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(32)
                  .height(32)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 64 })
            }
          } else if (this.failed) {
            ListItem() {
              Column({ space: ThemeConstants.SPACE_MD }) {
                Text($r('app.string.ehp_load_failed'))
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .fontColor($r('sys.color.font_secondary'))
                Button($r('app.string.common_retry'))
                  .onClick(() => {
                    this.load()
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 64 })
            }
          } else {
            ListItem() {
              this.ProfileSection()
            }
            ListItem() {
              this.ImageSection()
            }
            ListItem() {
              this.DisplaySection()
            }
            ListItem() {
              this.CategorySection()
            }
            ListItem() {
              this.ThumbnailSection()
            }
            ListItem() {
              this.CommentTagSection()
            }
            ListItem() {
              this.NamespaceSection()
            }
            ListItem() {
              this.LanguageSection()
            }
            ListItem() {
              this.FavoriteSortSection()
            }
            ListItem() {
              this.RatingSection()
            }
            ListItem() {
              this.ArchiverSection()
            }
            ListItem() {
              this.MpvSection()
            }
            ListItem() {
              this.HathSection()
            }
            ListItem() {
              this.ExcludedUploaderSection()
            }
            ListItem() {
              this.FavoriteNamesSection()
            }
          }
        }
        this.NameSheetHost()
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBarOpts(this.titleContent()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  // ───────────────────────── presence (permission gating) ─────────────────────────
  // Keep only the options this account actually has on the page (e.g. drop rc=200 without the Hath
  // perk, or uh donator options). Falls back to all when the page exposed no values for the code.
  private filterOptions(code: string, all: UcOption[]): UcOption[] {
    const present: number[] | undefined = this.settings.radioValues.get(code)
    if (present === undefined || present.length === 0) {
      return all
    }
    return all.filter((o: UcOption) => present.indexOf(o.value) >= 0)
  }

  // True when the page has this field at all (a checkbox/select absent for the account → hide the row).
  private hasField(code: string): boolean {
    return this.settings.fieldNames.indexOf(code) >= 0
  }

  // ───────────────────────── option lists ─────────────────────────
  private uhOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_uh_0')),
      new UcOption(1, $r('app.string.ehp_uh_1')),
      new UcOption(2, $r('app.string.ehp_uh_2')),
      new UcOption(3, $r('app.string.ehp_uh_3')),
    ]
  }

  private xrOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_auto')),
      new UcOption(5, '2400x'),
      new UcOption(4, '1600x'),
      new UcOption(3, '1280x'),
      new UcOption(1, '780x'),
    ]
  }

  private tlOptions(): UcOption[] {
    return [new UcOption(0, $r('app.string.ehp_tl_0')), new UcOption(1, $r('app.string.ehp_tl_1'))]
  }

  private dmOptions(): UcOption[] {
    return [
      new UcOption(3, $r('app.string.ehp_dm_3')),
      new UcOption(4, $r('app.string.ehp_dm_4')),
      new UcOption(0, $r('app.string.ehp_dm_0')),
      new UcOption(2, $r('app.string.ehp_dm_2')),
      new UcOption(1, $r('app.string.ehp_dm_1')),
    ]
  }

  private pnOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_pn_0')),
      new UcOption(1, $r('app.string.ehp_pn_1')),
      new UcOption(2, $r('app.string.ehp_pn_2')),
    ]
  }

  private ltOptions(): UcOption[] {
    return [new UcOption(0, $r('app.string.ehp_lt_0')), new UcOption(1, $r('app.string.ehp_lt_1'))]
  }

  private tsOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_auto')),
      new UcOption(1, $r('app.string.ehp_normal')),
      new UcOption(2, $r('app.string.ehp_small')),
    ]
  }

  private trOptions(): UcOption[] {
    return [
      new UcOption(0, '4'),
      new UcOption(1, '8'),
      new UcOption(2, '20'),
      new UcOption(3, '40'),
    ]
  }

  private csOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_cs_0')),
      new UcOption(1, $r('app.string.ehp_cs_1')),
      new UcOption(2, $r('app.string.ehp_cs_2')),
    ]
  }

  private scOptions(): UcOption[] {
    return [new UcOption(0, $r('app.string.ehp_sc_0')), new UcOption(1, $r('app.string.ehp_sc_1'))]
  }

  private tbOptions(): UcOption[] {
    return [new UcOption(0, $r('app.string.ehp_tb_0')), new UcOption(1, $r('app.string.ehp_tb_1'))]
  }

  private fsOptions(): UcOption[] {
    return [new UcOption(0, $r('app.string.ehp_fs_0')), new UcOption(1, $r('app.string.ehp_fs_1'))]
  }

  private rcOptions(): UcOption[] {
    return [
      new UcOption(0, '25'),
      new UcOption(1, '50'),
      new UcOption(2, '100'),
      new UcOption(3, '200'),
    ]
  }

  private arOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_ar_0')),
      new UcOption(1, $r('app.string.ehp_ar_1')),
      new UcOption(2, $r('app.string.ehp_ar_2')),
      new UcOption(3, $r('app.string.ehp_ar_3')),
      new UcOption(4, $r('app.string.ehp_ar_4')),
      new UcOption(5, $r('app.string.ehp_ar_5')),
    ]
  }

  private msOptions(): UcOption[] {
    return [
      new UcOption(0, $r('app.string.ehp_ms_0')),
      new UcOption(1, $r('app.string.ehp_ms_1')),
      new UcOption(2, $r('app.string.ehp_ms_2')),
    ]
  }

  // ───────────────────────── sections ─────────────────────────
  // Profile management: switch the active profile + create / rename / set-default / delete.
  @Builder
  ProfileSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_profile'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_profile_current'),
          options: this.profileOptions(),
          current: this.settings.selectedProfile,
          onPick: (v: number) => {
            this.selectProfile(v)
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.ehp_profile_create'),
          leadingIcon: $r('sys.symbol.plus'),
          showChevron: false,
          isEnabled: !this.profileBusy,
          action: () => {
            this.openNameSheet('create')
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.ehp_profile_rename'),
          leadingIcon: $r('sys.symbol.square_and_pencil'),
          showChevron: false,
          isEnabled: !this.profileBusy,
          action: () => {
            this.openNameSheet('rename')
          },
        })
        // 设为默认 only when the current profile is not already the default.
        if (this.settings.selectedProfile !== this.settings.defaultProfile) {
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.ehp_profile_default'),
            leadingIcon: $r('sys.symbol.checkmark'),
            showChevron: false,
            isEnabled: !this.profileBusy,
            action: () => {
              this.runProfileAction('default', `${this.settings.selectedProfile}`, '')
            },
          })
        }
        // 删除 only when there is more than one profile and this is not the default (EH won't delete it).
        if (
          this.settings.profiles.length > 1 &&
          this.settings.selectedProfile !== this.settings.defaultProfile
        ) {
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.ehp_profile_delete'),
            leadingIcon: $r('sys.symbol.trash'),
            destructive: true,
            showChevron: false,
            isEnabled: !this.profileBusy,
            action: () => {
              this.confirmDeleteProfile()
            },
          })
        }
      }
    }
  }

  @Builder
  NameSheetHost() {
    Blank()
      .width(1)
      .height(1)
      .bindSheet(
        $$this.nameSheetShown,
        this.NameSheet(),
        appSheetOptions({ detents: [SheetSize.LARGE], showClose: false }),
      )
  }

  @Builder
  NameSheet() {
    AppModalScaffold({
      title:
        this.nameAction === 'rename'
          ? $r('app.string.ehp_profile_rename')
          : $r('app.string.ehp_profile_create'),
      confirmIcon: $r('sys.symbol.checkmark'),
      confirmText: $r('app.string.common_save'),
      closeAction: () => {
        this.nameSheetShown = false
      },
      confirmAction: () => {
        this.confirmNameSheet()
      },
    }) {
      ListItem() {
        Column() {
          TextInput({ text: this.nameInput, placeholder: $r('app.string.ehp_profile_name_hint') })
            .onChange((v: string) => {
              this.nameInput = v
            })
        }
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  ImageSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_image'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_uh'),
          options: this.filterOptions('uh', this.uhOptions()),
          current: this.settings.loadImageThroughHAtH,
          onPick: (v: number) => {
            this.settings.loadImageThroughHAtH = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_xr'),
          options: this.filterOptions('xr', this.xrOptions()),
          current: this.settings.imageSize,
          onPick: (v: number) => {
            this.settings.imageSize = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_rx'),
          value: this.settings.imageSizeHorizontal,
          numeric: true,
          onChange: (v: string) => {
            this.settings.imageSizeHorizontal = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_ry'),
          value: this.settings.imageSizeVertical,
          numeric: true,
          onChange: (v: string) => {
            this.settings.imageSizeVertical = v
          },
        })
        // 原图 (oi) lives here, not under MPV; hidden for accounts that can't use it.
        if (this.hasField('oi')) {
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.ehp_oi'),
            hasSwitch: true,
            checked: this.settings.originalImages === 1,
            switchAction: (value: boolean) => {
              this.settings.originalImages = value ? 1 : 0
            },
          })
        }
      }
    }
  }

  @Builder
  DisplaySection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_display'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_tl'),
          options: this.filterOptions('tl', this.tlOptions()),
          current: this.settings.galleryNameDisplay,
          onPick: (v: number) => {
            this.settings.galleryNameDisplay = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_dm'),
          options: this.filterOptions('dm', this.dmOptions()),
          current: this.settings.frontPageSettings,
          onPick: (v: number) => {
            this.settings.frontPageSettings = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_pn'),
          options: this.filterOptions('pn', this.pnOptions()),
          current: this.settings.showGalleryPageNumbers,
          onPick: (v: number) => {
            this.settings.showGalleryPageNumbers = v
          },
        })
      }
    }
  }

  // Front-page default categories (ct_*): switch ON = shown on the front page / in searches.
  @Builder
  CategorySection() {
    if (this.settings.categories.length > 0) {
      Column() {
        this.SectionHeader($r('app.string.ehp_sec_cats'))
        GroupedListSection() {
          ForEach(
            this.settings.categories,
            (cat: EhUconfigCategory, index: number) => {
              ConciseListRow({
                title: cat.label,
                hasSwitch: true,
                checked: !cat.hidden,
                switchAction: (value: boolean) => {
                  cat.hidden = !value
                },
              })
              if (index < this.settings.categories.length - 1) {
                this.rowDivider()
              }
            },
            (cat: EhUconfigCategory) => cat.key,
          )
        }
      }
    }
  }

  @Builder
  ThumbnailSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_thumb'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_lt'),
          options: this.filterOptions('lt', this.ltOptions()),
          current: this.settings.mouseOverThumbnails,
          onPick: (v: number) => {
            this.settings.mouseOverThumbnails = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_ts'),
          options: this.filterOptions('ts', this.tsOptions()),
          current: this.settings.thumbnailSize,
          onPick: (v: number) => {
            this.settings.thumbnailSize = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tr'),
          options: this.filterOptions('tr', this.trOptions()),
          current: this.settings.thumbnailRows,
          onPick: (v: number) => {
            this.settings.thumbnailRows = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_tp'),
          value: this.settings.thumbnailScaling,
          numeric: true,
          suffix: '%',
          onChange: (v: string) => {
            this.settings.thumbnailScaling = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_vp'),
          value: this.settings.viewportOverride,
          numeric: true,
          suffix: 'px',
          onChange: (v: string) => {
            this.settings.viewportOverride = v
          },
        })
      }
    }
  }

  @Builder
  CommentTagSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_comment_tag'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_cs'),
          options: this.filterOptions('cs', this.csOptions()),
          current: this.settings.sortOrderComments,
          onPick: (v: number) => {
            this.settings.sortOrderComments = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_sc'),
          options: this.filterOptions('sc', this.scOptions()),
          current: this.settings.showCommentVotes,
          onPick: (v: number) => {
            this.settings.showCommentVotes = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tb'),
          options: this.filterOptions('tb', this.tbOptions()),
          current: this.settings.sortOrderTags,
          onPick: (v: number) => {
            this.settings.sortOrderTags = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_ft'),
          value: this.settings.tagFilteringThreshold,
          numeric: true,
          onChange: (v: string) => {
            this.settings.tagFilteringThreshold = v
          },
        })
        this.rowDivider()
        UcTextRow({
          title: $r('app.string.ehp_wt'),
          value: this.settings.tagWatchingThreshold,
          numeric: true,
          onChange: (v: string) => {
            this.settings.tagWatchingThreshold = v
          },
        })
      }
    }
  }

  // Excluded tag namespaces (xn_*): exclude a namespace from default tag search.
  @Builder
  NamespaceSection() {
    if (this.settings.excludedNamespaces.length > 0) {
      Column() {
        this.SectionHeader($r('app.string.ehp_sec_xn'))
        GroupedListSection() {
          ForEach(
            this.settings.excludedNamespaces,
            (item: EhUconfigToggleItem, index: number) => {
              ConciseListRow({
                title: item.name,
                hasSwitch: true,
                checked: item.excluded,
                switchAction: (value: boolean) => {
                  item.excluded = value
                },
              })
              if (index < this.settings.excludedNamespaces.length - 1) {
                this.rowDivider()
              }
            },
            (item: EhUconfigToggleItem) => `xn_${item.ser}`,
          )
        }
      }
    }
  }

  // Group the flat xl toggle list into one row per language (preserving page order).
  private static groupLanguages(items: EhUconfigToggleItem[]): EhLanguageRow[] {
    const rows: EhLanguageRow[] = []
    const byName: Map<string, EhLanguageRow> = new Map<string, EhLanguageRow>()
    for (let i: number = 0; i < items.length; i++) {
      const item: EhUconfigToggleItem = items[i]
      let row: EhLanguageRow | undefined = byName.get(item.name)
      if (row === undefined) {
        row = new EhLanguageRow(item.name)
        byName.set(item.name, row)
        rows.push(row)
      }
      row.variants.push(item)
    }
    return rows
  }

  // Excluded languages (xl_*): EH's table — one row per language with a multi-select segmented control
  // (original/translated/rewrite) on the right. Each row is its own component so it can own the
  // MultiCapsuleSegmentButtonV2 selectedIndexes state.
  @Builder
  LanguageSection() {
    if (this.langRows.length > 0) {
      Column() {
        this.SectionHeader($r('app.string.ehp_sec_xl'))
        GroupedListSection() {
          ForEach(
            this.langRows,
            (row: EhLanguageRow, index: number) => {
              LanguageVariantRow({ row: row })
              if (index < this.langRows.length - 1) {
                this.rowDivider()
              }
            },
            (row: EhLanguageRow) => row.name,
          )
        }
      }
    }
  }

  @Builder
  FavoriteSortSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_fav'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_fs'),
          options: this.filterOptions('fs', this.fsOptions()),
          current: this.settings.sortOrderFavorites,
          onPick: (v: number) => {
            this.settings.sortOrderFavorites = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_rc'),
          options: this.filterOptions('rc', this.rcOptions()),
          current: this.settings.searchResultCount,
          onPick: (v: number) => {
            this.settings.searchResultCount = v
          },
        })
      }
    }
  }

  @Builder
  RatingSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_rating'))
      GroupedListSection() {
        UcTextRow({
          title: $r('app.string.ehp_ru'),
          value: this.settings.ratings,
          placeholder: 'RRGGB',
          onChange: (v: string) => {
            this.settings.ratings = v
          },
        })
      }
    }
  }

  @Builder
  ArchiverSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_archiver'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_ar'),
          options: this.filterOptions('ar', this.arOptions()),
          current: this.settings.archiverSettings,
          onPick: (v: number) => {
            this.settings.archiverSettings = v
          },
        })
      }
    }
  }

  @Builder
  MpvSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_mpv'))
      GroupedListSection() {
        ConciseListRow({
          title: $r('app.string.ehp_qb'),
          hasSwitch: true,
          checked: this.settings.alwaysUseMpv === 1,
          switchAction: (value: boolean) => {
            this.settings.alwaysUseMpv = value ? 1 : 0
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_ms'),
          options: this.filterOptions('ms', this.msOptions()),
          current: this.settings.mpvStyle,
          onPick: (v: number) => {
            this.settings.mpvStyle = v
          },
        })
        this.rowDivider()
        // mt is inverted: pane shown when the form value is 0 (eros_fe parity).
        ConciseListRow({
          title: $r('app.string.ehp_mt'),
          hasSwitch: true,
          checked: this.settings.mpvThumbnailPane === 0,
          switchAction: (value: boolean) => {
            this.settings.mpvThumbnailPane = value ? 0 : 1
          },
        })
      }
    }
  }

  @Builder
  HathSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_hath'))
      GroupedListSection() {
        UcTextRow({
          title: $r('app.string.ehp_hh'),
          value: this.settings.hentaiAtHomeLocalNetworkHost,
          placeholder: 'IP:Port',
          onChange: (v: string) => {
            this.settings.hentaiAtHomeLocalNetworkHost = v
          },
        })
      }
    }
  }

  @Builder
  ExcludedUploaderSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_exclude_uploader'))
      GroupedListSection() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          TextArea({
            text: this.settings.excludedUploaders,
            placeholder: $r('app.string.ehp_xu_hint'),
          })
            .height(120)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => {
              this.settings.excludedUploaders = v
            })
        }
        .width('100%')
        .padding(ThemeConstants.SPACE_MD)
      }
    }
  }

  @Builder
  FavoriteNamesSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_fav_names'))
      GroupedListSection() {
        ForEach(
          this.settings.favorites,
          (name: string, index: number) => {
            UcTextRow({
              title: `${index}`,
              value: name,
              placeholder: $r('app.string.ehp_fav_name_hint'),
              onChange: (v: string) => {
                this.settings.favorites[index] = v
              },
            })
            if (index < this.settings.favorites.length - 1) {
              this.rowDivider()
            }
          },
          (name: string, index: number) => `fav_${index}`,
        )
      }
    }
  }

  @Builder
  SectionHeader(title: ResourceStr) {
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
}

/** A label + dropdown row bound to a uconfig radio group (ConciseListRow + bindMenu, app-standard). */
@ComponentV2
struct UcSelectRow {
  @Param title: ResourceStr = '';
  @Param options: UcOption[] = [];
  @Param current: number = 0;
  @Event onPick: (value: number) => void = () => {};
  @Local menuShown: boolean = false;

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
        (option: UcOption) => {
          SettingsCheckedMenuItem({
            label: option.label,
            selected: option.value === this.current,
            selectAction: () => {
              this.onPick(option.value)
              this.menuShown = false
            },
          })
        },
        (option: UcOption) => `${option.value}`,
      )
    }
  }
}

/**
 * Label + inline text field, built ON ConciseListRow so the title matches every other row exactly
 * (the input lives in the row's suffix slot). Never hand-roll the title.
 */
@ComponentV2
struct UcTextRow {
  @Param title: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param numeric: boolean = false;
  @Param suffix: string = '';
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
    Row({ space: ThemeConstants.SPACE_XS }) {
      TextInput({ text: this.value, placeholder: this.placeholder })
        .type(this.numeric ? InputType.Number : InputType.Normal)
        .textAlign(TextAlign.End)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor(Color.Transparent)
        .padding(0)
        .width(140)
        .onChange((v: string) => {
          this.onChange(v)
        })
      if (this.suffix.length > 0) {
        Text(this.suffix)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
      }
    }.alignItems(VerticalAlign.Center)
  }
}

/**
 * One excluded-language row: language name (via ConciseListRow, so the title matches) + a multi-select
 * variant segmented control (MultiCapsuleSegmentButtonV2) in the suffix. Each segment = one variant;
 * checked = excluded.
 */
@ComponentV2
struct LanguageVariantRow {
  @Param row: EhLanguageRow = new EhLanguageRow('');
  @Local items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  @Local selectedIndexes: number[] = [];

  aboutToAppear(): void {
    const opts: SegmentButtonV2ItemOptions[] = []
    const sel: number[] = []
    for (let i: number = 0; i < this.row.variants.length; i++) {
      const v: EhUconfigToggleItem = this.row.variants[i]
      opts.push({ text: LanguageVariantRow.variantText(v.variant) })
      if (v.excluded) {
        sel.push(i)
      }
    }
    this.items = new SegmentButtonV2Items(opts)
    this.selectedIndexes = sel
  }

  private static variantText(variant: number): string {
    return variant === 2
      ? AppStrings.get('ehp_xl_rewrite')
      : variant === 1
        ? AppStrings.get('ehp_xl_translated')
        : AppStrings.get('ehp_xl_original')
  }

  build() {
    ConciseListRow({
      title: this.row.name,
      showChevron: false,
      suffixPaddingRight: ThemeConstants.SPACE_MD,
      suffixBuilderParam: () => {
        this.SegmentSuffix()
      },
    })
  }

  @Builder
  SegmentSuffix() {
    MultiCapsuleSegmentButtonV2({
      items: this.items,
      selectedIndexes: this.selectedIndexes,
      itemFontSize: LengthMetrics.vp(ThemeConstants.FONT_SIZE_CAPTION),
      itemSelectedFontColor: ColorMetrics.resourceColor(ThemeConstants.TEXT_ON_BRAND),
      itemSelectedBackgroundColor: ColorMetrics.resourceColor(ThemeConstants.BRAND_PRIMARY),
      $selectedIndexes: (indexes: number[]) => {
        this.selectedIndexes = indexes
        for (let i: number = 0; i < this.row.variants.length; i++) {
          this.row.variants[i].excluded = indexes.indexOf(i) >= 0
        }
      },
    })
      // The control fills its container by default, which would swallow the language name; size it to
      // the segment count so the title keeps its space.
      .width(this.row.variants.length * 70)
      .flexShrink(0)
  }
}
