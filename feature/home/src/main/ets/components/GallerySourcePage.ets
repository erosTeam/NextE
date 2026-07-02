import {
  connectSiteMode,
  SiteModeState,
  connectTagTranslationSettings,
  TagTranslationSettingsState,
  SELECTOR_BAR_HEIGHT,
  ActiveKeyState,
  LocalBlockState,
  connectLocalBlock,
  connectCustomProfiles,
  CustomProfilesState,
  CustomProfile,
  SafeModeGate,
  SafeModeState,
  connectSafeMode,
  SAFE_MODE_PROFILE_UUID,
  DiagnosticLogger,
  HomeSourceState,
  connectHomeSource,
} from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from './GalleryListBody'
import { common } from '@kit.AbilityKit'

/**
 * One retained gallery-SOURCE page (V2Next FeedListPage pattern). Each source (默认/热门/订阅) gets its
 * OWN GallerySourcePage instance inside HomePage's Swiper, and each owns its OWN GalleryListViewModel +
 * datasource + (Index-bound) scroller. The Swiper keeps the instances alive (cachedCount), so switching
 * source away and back preserves that source's list AND scroll offset — no shared-list reload. This is
 * the retained-tab model the gate requires; HomeSourceState stays a pure selection bus (it holds no data).
 *
 * Lazy first-load: a source loads its first page only when it FIRST becomes the active tab, not eagerly
 * for every cached page — so opening Home does not fire every source's network at once. Activation is
 * driven by the host's SHARED ActiveKeyState (active.activeKey === sourceKey), NOT a per-render isActive
 * @Param — a cached page never receives an isActive update, so that signal missed the first load.
 */
@ComponentV2
export struct GallerySourcePage {
  // The custom profile uuid this page renders. Stable for this page's lifetime (the Swiper key).
  @Param sourceKey: string = '';
  // Shared active-key signal from the host; this page is active when active.activeKey === sourceKey.
  @Param active: ActiveKeyState = new ActiveKeyState();
  // Index-owned scroller for this source, so the title bar can bindToScrollable the ACTIVE source's list.
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local localBlock: LocalBlockState = connectLocalBlock();
  @Local profilesState: CustomProfilesState = connectCustomProfiles();
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local homeSource: HomeSourceState = connectHomeSource();
  // Per-tab display-mode override passed to the list body ('global' = follow the shared ListModeState).
  @Local displayMode: string = 'global';
  // First-load guard: load once on first activation; later activations reuse the retained list.
  private loadedOnce: boolean = false;
  // lastEditTime of the profile this VM is configured for; an edit bumps it → reconfigure + reload.
  private configuredEditTime: number = -1;
  private selectedJumpDate: Date = new Date();

  private isActive(): boolean {
    return this.active.activeKey === this.sourceKey
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private profileForSource(): CustomProfile | null {
    if (this.safeMode.restricted() || this.sourceKey === SAFE_MODE_PROFILE_UUID) {
      return SafeModeGate.safeProfile()
    }
    return connectCustomProfiles().findByUuid(this.sourceKey)
  }

  aboutToAppear(): void {
    // Configure the VM from this page's custom profile (sourceKey is the profile uuid) before any load;
    // loadData() runs right after. Fall back to the front-page source if the profile is missing.
    const profile: CustomProfile | null = this.profileForSource()
    if (profile !== null) {
      this.vm.configureFromProfile(profile)
      this.configuredEditTime = profile.lastEditTime
      this.displayMode = profile.displayMode
    } else {
      this.vm.syncSource('', 0)
    }
    this.vm.setContext(this.ctx())
    DiagnosticLogger.info(
      'home-list-anchor',
      'source_appear',
      `sourceKey=${this.sourceKey} active=${this.active.activeKey} loadedOnce=${this.loadedOnce} editTime=${this.configuredEditTime} vm=${this.vm.debugState()}`,
    )
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  // A live edit to THIS page's profile (type/category/search/favcat) bumps its lastEditTime; reconfigure
  // the retained VM and reload so the active tab reflects the change without an app restart.
  @Monitor('profilesState.profiles')
  onProfileEdited(): void {
    if (this.safeMode.restricted() || this.sourceKey === SAFE_MODE_PROFILE_UUID) {
      return
    }
    const profile: CustomProfile | null = this.profilesState.findByUuid(this.sourceKey)
    if (profile === null) {
      return
    }
    // Display-mode change only re-renders (no refetch).
    if (profile.displayMode !== this.displayMode) {
      this.displayMode = profile.displayMode
    }
    // Content-affecting edit (type/category/search/favcat) bumps lastEditTime → reconfigure + reload.
    if (profile.lastEditTime === this.configuredEditTime) {
      return
    }
    DiagnosticLogger.info(
      'home-list-anchor',
      'source_profile_reload',
      `sourceKey=${this.sourceKey} oldEditTime=${this.configuredEditTime} newEditTime=${profile.lastEditTime} loadedOnce=${this.loadedOnce} vm=${this.vm.debugState()}`,
    )
    this.configuredEditTime = profile.lastEditTime
    this.vm.configureFromProfile(profile)
    if (this.loadedOnce) {
      this.vm.reload()
    }
  }

  // Load the first page the first time this source becomes active; retained afterwards. The host's @Trace
  // activeKey reaches even cached pages, so this fires reliably on a bar tap or swipe to this source.
  @Monitor('active.activeKey')
  onActiveChange(): void {
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  @Monitor('homeSource.cmdSeq')
  onHomeCommand(): void {
    if (!this.isActive()) {
      return
    }
    DiagnosticLogger.info(
      'home-list-anchor',
      'home_command_receive',
      `sourceKey=${this.sourceKey} kind=${this.homeSource.cmdKind} seq=${this.homeSource.cmdSeq} vm=${this.vm.debugState()}`,
    )
    if (this.homeSource.cmdKind === 'openDateJumpAfterDialog') {
      this.openDateJumpAfterDialog()
    } else if (this.homeSource.cmdKind === 'jumpGalleryFirstPage') {
      this.jumpToFirstPage()
    }
  }

  private loadOnce(): void {
    DiagnosticLogger.info(
      'home-list-anchor',
      'source_load_once',
      `sourceKey=${this.sourceKey} active=${this.active.activeKey} loadedOnce=${this.loadedOnce} vm=${this.vm.debugState()}`,
    )
    if (this.loadedOnce) {
      return
    }
    this.loadedOnce = true
    this.vm.loadData()
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private static formatDate(value: Date): string {
    const month: number = value.getMonth() + 1
    const day: number = value.getDate()
    return `${value.getFullYear()}-${GallerySourcePage.pad2(month)}-${GallerySourcePage.pad2(day)}`
  }

  private openDateJumpAfterDialog(): void {
    if (!this.vm.canJumpToDateAfter()) {
      DiagnosticLogger.info('home-list-anchor', 'date_jump_dialog_blocked', this.vm.debugState())
      return
    }
    DiagnosticLogger.info('home-list-anchor', 'date_jump_dialog_open', this.vm.debugState())
    this.getUIContext().showDatePickerDialog({
      start: new Date(2007, 2, 20),
      end: new Date(),
      selected: this.selectedJumpDate,
      onDateAccept: (value: Date) => {
        this.selectedJumpDate = value
        this.loadedOnce = true
        const seek: string = GallerySourcePage.formatDate(value)
        this.vm.jumpToDateAfter(seek)
          .then((ok: boolean) => {
            if (ok) {
              setTimeout(() => {
                this.scroller.scrollToIndex(0)
              }, 50)
            }
          })
          .catch((_error: Error) => {
          })
      },
    })
  }

  private jumpToFirstPage(): void {
    if (this.vm.shouldJumpGalleryFirstPage()) {
      this.vm.jumpGalleryFirstPage()
        .then((ok: boolean) => {
          if (ok) {
            setTimeout(() => {
              this.scroller.scrollToIndex(0)
            }, 50)
          }
        })
        .catch((_error: Error) => {
        })
      return
    }
    this.scroller.scrollToIndex(0)
  }

  // A 表/里 site switch invalidates this source's rows; reload only if it has already loaded (an
  // unvisited source reloads naturally on its first activation with the new site).
  @Monitor('siteMode.isEx')
  onSiteChange(): void {
    if (this.loadedOnce) {
      DiagnosticLogger.info('home-list-anchor', 'source_site_reload', `sourceKey=${this.sourceKey} vm=${this.vm.debugState()}`)
      this.vm.reload()
    }
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    if (this.loadedOnce) {
      this.vm.reapplyTagTranslation()
    }
  }

  @Monitor('localBlock.version')
  async onLocalBlockChange(): Promise<void> {
    if (this.loadedOnce) {
      DiagnosticLogger.info('home-list-anchor', 'source_local_block', `sourceKey=${this.sourceKey} vm=${this.vm.debugState()}`)
      await this.vm.applyLocalBlockChange()
    }
  }

  build() {
    GalleryListBody({
      vm: this.vm,
      topPadding: SELECTOR_BAR_HEIGHT,
      scroller: this.scroller,
      overrideMode: this.displayMode,
      onDidScroll: (offset: number, state: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(offset, state)
        }
      },
    })
  }
}
