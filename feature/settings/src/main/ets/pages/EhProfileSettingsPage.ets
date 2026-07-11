import { HdsNavDestination, IconStyleMode } from '@kit.UIDesignKit'
import {
  ColorMetrics,
  KeyboardAvoidMode,
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
  AuthState,
  CookieJarSettings,
  ConciseListRow,
  EhCookieStore,
  InlineEditRow,
  EhApiService,
  EhConstants,
  EhProfile,
  EhProfileSettings,
  EhProfileSettingsRequestContext,
  EhProfileSettingsRequestFence,
  EhRadioOption,
  EhUconfigCategory,
  EhUconfigToggleItem,
  GalleryWebParams,
  GroupedListSection,
  SecondaryListScaffold,
  SettingsCheckedMenuItem,
  SiteModeState,
  ThemeConstants,
  connectAuth,
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
 * The top-right also opens EH's own /uconfig.php in the in-app WebView. Profile actions persist the
 * server-confirmed `sp` selection; xn/xl lists are edited directly in the native form.
 */
@ComponentV2
export struct EhProfileSettingsPage {
  @Local auth: AuthState = connectAuth();
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
  private nameProfileSet: string = '';
  private nameSheetContext: EhProfileSettingsRequestContext | null = null;
  private loadedContext: EhProfileSettingsRequestContext | null = null;
  private loadRun: number = 0;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private currentRequestContext(): EhProfileSettingsRequestContext {
    const cookieStore: EhCookieStore = EhCookieStore.getInstance()
    return new EhProfileSettingsRequestContext(
      cookieStore.get(EhConstants.COOKIE_MEMBER_ID),
      cookieStore.get(EhConstants.COOKIE_PASS_HASH),
      this.site.isEx,
    )
  }

  private contextMatchesCurrent(request: EhProfileSettingsRequestContext): boolean {
    return EhProfileSettingsRequestFence.matches(request, this.currentRequestContext())
  }

  private currentLoadedContext(): EhProfileSettingsRequestContext | null {
    const context: EhProfileSettingsRequestContext | null = this.loadedContext
    if (context === null || !this.contextMatchesCurrent(context)) {
      return null
    }
    return context
  }

  private canStartWrite(): boolean {
    return (
      !this.loading &&
      !this.saving &&
      !this.profileBusy &&
      this.currentLoadedContext() !== null
    )
  }

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.load()
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  @Monitor('auth.memberId')
  private onActiveAccountChanged(): void {
    this.load()
  }

  @Monitor('site.isEx')
  private onSiteModeChanged(): void {
    this.load()
  }

  private load(): void {
    this.loadRun = this.loadRun + 1
    const run: number = this.loadRun
    const request: EhProfileSettingsRequestContext = this.currentRequestContext()
    this.loadedContext = null
    this.nameSheetShown = false
    this.nameSheetContext = null
    this.loading = true
    this.failed = false
    if (!this.contextMatchesCurrent(request)) {
      this.failed = true
      this.loading = false
      return
    }
    EhApiService.getInstance()
      .getUserConfig(request.isEx)
      .then((s: EhProfileSettings) => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(request)) {
          this.load()
          return
        }
        this.applyLoaded(s, request)
        this.loading = false
      })
      .catch(() => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(request)) {
          this.load()
          return
        }
        this.failed = true
        this.loading = false
      })
  }

  private applyLoaded(s: EhProfileSettings, context: EhProfileSettingsRequestContext): void {
    this.settings = s
    this.langRows = EhProfileSettingsPage.groupLanguages(s.excludedLanguages)
    this.loadedContext = context
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

  private runProfileAction(
    action: string,
    profileSet: string,
    name: string,
    expectedContext: EhProfileSettingsRequestContext | null,
  ): void {
    if (this.loading || this.saving || this.profileBusy) {
      return
    }
    const loadedContext: EhProfileSettingsRequestContext | null = this.loadedContext
    if (
      expectedContext === null ||
      loadedContext === null ||
      !EhProfileSettingsRequestFence.matches(expectedContext, loadedContext) ||
      !this.contextMatchesCurrent(expectedContext)
    ) {
      this.load()
      return
    }
    const run: number = this.loadRun
    this.profileBusy = true
    EhApiService.getInstance()
      .postProfileAction(expectedContext.isEx, action, profileSet, name)
      .then(async (s: EhProfileSettings) => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(expectedContext)) {
          this.load()
          return
        }
        const persisted: boolean = await this.persistSelectedProfile(s, expectedContext, run)
        if (!persisted) {
          if (run === this.loadRun && this.contextMatchesCurrent(expectedContext)) {
            this.load()
          }
          return
        }
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(expectedContext)) {
          this.load()
          return
        }
        this.applyLoaded(s, expectedContext)
        this.toast($r('app.string.ehp_profile_done'))
      })
      .catch(() => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(expectedContext)) {
          this.load()
          return
        }
        this.toast($r('app.string.ehp_profile_failed'))
      })
      .finally(() => {
        this.profileBusy = false
      })
  }

  private async persistSelectedProfile(
    settings: EhProfileSettings,
    context: EhProfileSettingsRequestContext,
    run: number,
  ): Promise<boolean> {
    const selected: string = settings.selectedProfileCookieValue()
    if (selected.length === 0 || run !== this.loadRun || !this.contextMatchesCurrent(context)) {
      return false
    }
    return await CookieJarSettings.persistServerSelectedProfile(
      this.ctx(),
      context.memberId,
      context.passHash,
      context.isEx,
      selected,
    )
  }

  private selectProfile(value: number): void {
    const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
    if (context === null) {
      this.load()
      return
    }
    if (value !== this.settings.selectedProfile) {
      this.runProfileAction('', `${value}`, '', context)
    }
  }

  private openNameSheet(action: string): void {
    if (!this.canStartWrite()) {
      this.load()
      return
    }
    const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
    if (context === null) {
      this.load()
      return
    }
    this.nameAction = action
    this.nameProfileSet = action === 'rename' ? `${this.settings.selectedProfile}` : ''
    this.nameSheetContext = context
    this.nameInput = action === 'rename' ? this.currentProfileName() : ''
    this.nameSheetShown = true
  }

  private confirmNameSheet(): void {
    const name: string = this.nameInput.trim()
    if (name.length === 0) {
      return
    }
    const action: string = this.nameAction
    const profileSet: string = this.nameProfileSet
    const context: EhProfileSettingsRequestContext | null = this.nameSheetContext
    this.nameSheetShown = false
    this.nameSheetContext = null
    if (action === 'rename') {
      this.runProfileAction('rename', profileSet, name, context)
    } else {
      this.runProfileAction('create', '', name, context)
    }
  }

  private confirmDeleteProfile(): void {
    if (!this.canStartWrite()) {
      this.load()
      return
    }
    const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
    if (context === null) {
      this.load()
      return
    }
    const profileSet: string = `${this.settings.selectedProfile}`
    this.getUIContext().showAlertDialog({
      title: $r('app.string.ehp_profile_delete'),
      message: $r('app.string.ehp_profile_delete_confirm'),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.ehp_profile_delete'),
        fontColor: Color.Red,
        action: () => {
          this.runProfileAction('delete', profileSet, '', context)
        },
      },
    })
  }

  private save(): void {
    if (this.loading || this.saving || this.profileBusy) {
      return
    }
    const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
    if (context === null) {
      this.load()
      return
    }
    const run: number = this.loadRun
    const settings: EhProfileSettings = this.settings.copy()
    this.saving = true
    EhApiService.getInstance()
      .saveUserConfig(context.isEx, settings)
      .then(() => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(context)) {
          this.load()
          return
        }
        this.toast($r('app.string.ehp_saved'))
      })
      .catch(() => {
        if (run !== this.loadRun) {
          return
        }
        if (!this.contextMatchesCurrent(context)) {
          this.load()
          return
        }
        this.toast($r('app.string.ehp_save_failed'))
      })
      .finally(() => {
        this.saving = false
      })
  }

  private openWeb(): void {
    const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
    if (context === null) {
      this.load()
      return
    }
    const url: string = `${EhConstants.baseUrl(context.isEx)}/uconfig.php`
    this.stack.pushPathByName('GalleryWeb', new GalleryWebParams(url, AppStrings.get('ehp_title')))
  }

  // ── Title bar with Save + open-in-web actions (top-right). ──
  private titleContent(): Record<string, Object> {
    const saveContent: Record<string, Object> = {
      'label': AppStrings.get('common_save'),
      'icon': $r('sys.symbol.checkmark'),
      'isEnabled': this.canStartWrite(),
      'type': IconStyleMode.NORMAL,
      'action': () => {
        this.save()
      },
    }
    const webContent: Record<string, Object> = {
      'label': AppStrings.get('ehp_open_web'),
      'icon': $r('sys.symbol.link'),
      'isEnabled': this.currentLoadedContext() !== null,
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

  // ───────────────────────── options (parsed from the page) ─────────────────────────
  // Options come STRAIGHT from the page (real values + labels + only what this account has — so e.g.
  // EH's current resample resolutions show, not a stale hard-coded list). A known page-English label is
  // glossed to Chinese; anything else (resolutions, new options) shows the page's own text verbatim.
  private pageOptions(code: string): UcOption[] {
    const opts: EhRadioOption[] | undefined = this.settings.radioGroups.get(code)
    if (opts === undefined) {
      return []
    }
    return opts.map((o: EhRadioOption) => new UcOption(o.value, this.localizeOption(o.label)))
  }

  private localizeOption(label: string): string {
    const key: string | undefined = EhProfileSettingsPage.optionZh().get(label)
    return key !== undefined ? AppStrings.get(key) : label
  }

  // Page-English option label → i18n key. Keyed by exact text so it never overrides with a wrong gloss:
  // if EH changes a label (e.g. new resolutions) it just falls through to the page text.
  private static optionZhCache: Map<string, string> | null = null;
  private static optionZh(): Map<string, string> {
    if (EhProfileSettingsPage.optionZhCache !== null) {
      return EhProfileSettingsPage.optionZhCache
    }
    const m: Map<string, string> = new Map<string, string>()
    m.set('Any client (Recommended)', 'ehp_uh_0')
    m.set(
      'Default port clients only (Can be slower. Enable if behind firewall/proxy that blocks outgoing non-standard ports.)',
      'ehp_uh_1',
    )
    m.set(
      'No [Modern/HTTPS] (Donator only. You will not be able to browse as many pages. Recommended only if having severe problems.)',
      'ehp_uh_2',
    )
    m.set(
      'No [Legacy/HTTP] (Donator only. May not work by default in modern browsers. Recommended for legacy/outdated browsers only.)',
      'ehp_uh_3',
    )
    m.set('Auto', 'ehp_auto')
    m.set('Normal', 'ehp_normal')
    m.set('Small', 'ehp_small')
    m.set('Default Title', 'ehp_tl_0')
    m.set('Japanese Title (if available)', 'ehp_tl_1')
    m.set('Compact', 'ehp_dm_0')
    m.set('Thumbnail', 'ehp_dm_1')
    m.set('Extended', 'ehp_dm_2')
    m.set('Minimal', 'ehp_dm_3')
    m.set('Minimal+', 'ehp_dm_4')
    m.set('None', 'ehp_pn_0')
    m.set('Page Number Only', 'ehp_pn_1')
    m.set('Page Number + Name', 'ehp_pn_2')
    m.set(
      'On mouse-over (pages load faster, but there may be a slight delay before a thumb appears)',
      'ehp_lt_0',
    )
    m.set(
      'On page load (pages take longer to load, but there is no delay for loading a thumb after the page has loaded)',
      'ehp_lt_1',
    )
    m.set('Oldest comments first', 'ehp_cs_0')
    m.set('Recent comments first', 'ehp_cs_1')
    m.set('By highest score', 'ehp_cs_2')
    m.set('On score hover or click', 'ehp_sc_0')
    m.set('Always', 'ehp_sc_1')
    m.set('Alphabetical', 'ehp_tb_0')
    m.set('By tag power', 'ehp_tb_1')
    m.set('By last gallery update time', 'ehp_fs_0')
    m.set('By favorited time', 'ehp_fs_1')
    m.set('Manual Select, Manual Start (Default)', 'ehp_ar_0')
    m.set('Manual Select, Auto Start', 'ehp_ar_1')
    m.set('Auto Select Original, Manual Start', 'ehp_ar_2')
    m.set('Auto Select Original, Auto Start', 'ehp_ar_3')
    m.set('Auto Select Resample, Manual Start', 'ehp_ar_4')
    m.set('Auto Select Resample, Auto Start', 'ehp_ar_5')
    m.set('Align left', 'ehp_ms_0')
    m.set('Align center 1', 'ehp_ms_1')
    m.set('Align center 2', 'ehp_ms_2')
    EhProfileSettingsPage.optionZhCache = m
    return m
  }

  // True when the page has this field at all (a checkbox/select absent for the account → hide the row).
  private hasField(code: string): boolean {
    return this.settings.fieldNames.indexOf(code) >= 0
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
          isEnabled: this.canStartWrite(),
          action: () => {
            this.openNameSheet('create')
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.ehp_profile_rename'),
          leadingIcon: $r('sys.symbol.square_and_pencil'),
          showChevron: false,
          isEnabled: this.canStartWrite(),
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
            isEnabled: this.canStartWrite(),
            action: () => {
              const context: EhProfileSettingsRequestContext | null = this.currentLoadedContext()
              this.runProfileAction('default', `${this.settings.selectedProfile}`, '', context)
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
            isEnabled: this.canStartWrite(),
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
          options: this.pageOptions('uh'),
          current: this.settings.loadImageThroughHAtH,
          onPick: (v: number) => {
            this.settings.loadImageThroughHAtH = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_xr'),
          options: this.pageOptions('xr'),
          current: this.settings.imageSize,
          onPick: (v: number) => {
            this.settings.imageSize = v
          },
        })
        this.rowDivider()
        InlineEditRow({
          title: $r('app.string.ehp_rx'),
          value: this.settings.imageSizeHorizontal,
          numeric: true,
          onChange: (v: string) => {
            this.settings.imageSizeHorizontal = v
          },
        })
        this.rowDivider()
        InlineEditRow({
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
          options: this.pageOptions('tl'),
          current: this.settings.galleryNameDisplay,
          onPick: (v: number) => {
            this.settings.galleryNameDisplay = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_dm'),
          options: this.pageOptions('dm'),
          current: this.settings.frontPageSettings,
          onPick: (v: number) => {
            this.settings.frontPageSettings = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_pn'),
          options: this.pageOptions('pn'),
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
          options: this.pageOptions('lt'),
          current: this.settings.mouseOverThumbnails,
          onPick: (v: number) => {
            this.settings.mouseOverThumbnails = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_ts'),
          options: this.pageOptions('ts'),
          current: this.settings.thumbnailSize,
          onPick: (v: number) => {
            this.settings.thumbnailSize = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tr'),
          options: this.pageOptions('tr'),
          current: this.settings.thumbnailRows,
          onPick: (v: number) => {
            this.settings.thumbnailRows = v
          },
        })
        this.rowDivider()
        InlineEditRow({
          title: $r('app.string.ehp_tp'),
          value: this.settings.thumbnailScaling,
          numeric: true,
          suffix: '%',
          onChange: (v: string) => {
            this.settings.thumbnailScaling = v
          },
        })
        this.rowDivider()
        InlineEditRow({
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
          options: this.pageOptions('cs'),
          current: this.settings.sortOrderComments,
          onPick: (v: number) => {
            this.settings.sortOrderComments = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_sc'),
          options: this.pageOptions('sc'),
          current: this.settings.showCommentVotes,
          onPick: (v: number) => {
            this.settings.showCommentVotes = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_tb'),
          options: this.pageOptions('tb'),
          current: this.settings.sortOrderTags,
          onPick: (v: number) => {
            this.settings.sortOrderTags = v
          },
        })
        this.rowDivider()
        InlineEditRow({
          title: $r('app.string.ehp_ft'),
          value: this.settings.tagFilteringThreshold,
          numeric: true,
          onChange: (v: string) => {
            this.settings.tagFilteringThreshold = v
          },
        })
        this.rowDivider()
        InlineEditRow({
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
          options: this.pageOptions('fs'),
          current: this.settings.sortOrderFavorites,
          onPick: (v: number) => {
            this.settings.sortOrderFavorites = v
          },
        })
        this.rowDivider()
        UcSelectRow({
          title: $r('app.string.ehp_rc'),
          options: this.pageOptions('rc'),
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
        InlineEditRow({
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
          options: this.pageOptions('ar'),
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
          options: this.pageOptions('ms'),
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
        InlineEditRow({
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
        // The TextArea carries its own modest inset (matching the list rows); no extra wrapper padding
        // so the box doesn't look over-margined.
        TextArea({
          text: this.settings.excludedUploaders,
          placeholder: $r('app.string.ehp_xu_hint'),
        })
          .width('100%')
          .height(116)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor(Color.Transparent)
          .padding({
            left: ThemeConstants.SPACE_MD,
            right: ThemeConstants.SPACE_MD,
            top: ThemeConstants.SPACE_SM,
            bottom: ThemeConstants.SPACE_SM,
          })
          .onChange((v: string) => {
            this.settings.excludedUploaders = v
          })
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
            InlineEditRow({
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
