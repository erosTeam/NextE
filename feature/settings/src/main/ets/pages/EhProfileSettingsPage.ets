import { HdsNavDestination, IconStyleMode } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  EhApiService,
  EhConstants,
  EhProfileSettings,
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
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local failed: boolean = false;
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
        this.settings = s
        this.loading = false
      })
      .catch(() => {
        this.failed = true
        this.loading = false
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
      'type': IconStyleMode.SMALL,
      'action': () => {
        this.save()
      },
    }
    const webContent: Record<string, Object> = {
      'label': AppStrings.get('ehp_open_web'),
      'icon': $r('sys.symbol.link'),
      'isEnabled': true,
      'type': IconStyleMode.SMALL,
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
            this.ImageSection()
          }
          ListItem() {
            this.DisplaySection()
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
    }
    .titleBar(immersiveTitleBarOpts(this.titleContent()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
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
  @Builder
  ImageSection() {
    Column() {
      this.SectionHeader($r('app.string.ehp_sec_image'))
      GroupedListSection() {
        UcSelectRow({
          title: $r('app.string.ehp_uh'),
          options: this.uhOptions(),
          current: this.settings.loadImageThroughHAtH,
          onPick: (v: number) => {
            this.settings.loadImageThroughHAtH = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_xr'),
          options: this.xrOptions(),
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
          options: this.tlOptions(),
          current: this.settings.galleryNameDisplay,
          onPick: (v: number) => {
            this.settings.galleryNameDisplay = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_dm'),
          options: this.dmOptions(),
          current: this.settings.frontPageSettings,
          onPick: (v: number) => {
            this.settings.frontPageSettings = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_pn'),
          options: this.pnOptions(),
          current: this.settings.showGalleryPageNumbers,
          onPick: (v: number) => {
            this.settings.showGalleryPageNumbers = v
          },
        })
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
          options: this.ltOptions(),
          current: this.settings.mouseOverThumbnails,
          onPick: (v: number) => {
            this.settings.mouseOverThumbnails = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_ts'),
          options: this.tsOptions(),
          current: this.settings.thumbnailSize,
          onPick: (v: number) => {
            this.settings.thumbnailSize = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tr'),
          options: this.trOptions(),
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
          options: this.csOptions(),
          current: this.settings.sortOrderComments,
          onPick: (v: number) => {
            this.settings.sortOrderComments = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_sc'),
          options: this.scOptions(),
          current: this.settings.showCommentVotes,
          onPick: (v: number) => {
            this.settings.showCommentVotes = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tb'),
          options: this.tbOptions(),
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

  private langLabel(item: EhUconfigToggleItem): string {
    if (item.variant < 0) {
      return item.name
    }
    const variant: string =
      item.variant === 2
        ? AppStrings.get('ehp_xl_rewrite')
        : item.variant === 1
          ? AppStrings.get('ehp_xl_translated')
          : AppStrings.get('ehp_xl_original')
    return `${item.name} · ${variant}`
  }

  // Excluded languages (xl_*): galleries in a checked language never appear.
  @Builder
  LanguageSection() {
    if (this.settings.excludedLanguages.length > 0) {
      Column() {
        this.SectionHeader($r('app.string.ehp_sec_xl'))
        GroupedListSection() {
          ForEach(
            this.settings.excludedLanguages,
            (item: EhUconfigToggleItem, index: number) => {
              ConciseListRow({
                title: this.langLabel(item),
                hasSwitch: true,
                checked: item.excluded,
                switchAction: (value: boolean) => {
                  item.excluded = value
                },
              })
              if (index < this.settings.excludedLanguages.length - 1) {
                this.rowDivider()
              }
            },
            (item: EhUconfigToggleItem) => `xl_${item.ser}`,
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
          options: this.fsOptions(),
          current: this.settings.sortOrderFavorites,
          onPick: (v: number) => {
            this.settings.sortOrderFavorites = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_rc'),
          options: this.rcOptions(),
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
          options: this.arOptions(),
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
          options: this.msOptions(),
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

/** A label + inline text field row bound to a uconfig text input. */
@ComponentV2
struct UcTextRow {
  @Param title: ResourceStr = '';
  @Param value: string = '';
  @Param placeholder: ResourceStr = '';
  @Param numeric: boolean = false;
  @Param suffix: string = '';
  @Event onChange: (value: string) => void = () => {};

  build() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      Text(this.title)
        .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
        .fontWeight(FontWeight.Regular)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      TextInput({ text: this.value, placeholder: this.placeholder })
        .type(this.numeric ? InputType.Number : InputType.Normal)
        .textAlign(TextAlign.End)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .backgroundColor(Color.Transparent)
        .width(140)
        .onChange((v: string) => {
          this.onChange(v)
        })
      if (this.suffix.length > 0) {
        Text(this.suffix)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
    .constraintSize({ minHeight: 48 })
  }
}
