import {
  SELECTOR_BAR_HEIGHT,
  ActiveKeyState,
  ToplistFilterState,
  HomeSourceState,
  connectTagTranslationSettings,
  TagTranslationSettingsState,
  connectToplistFilter,
  LocalBlockState,
  connectLocalBlock,
  connectHomeSource,
  AuthState,
  connectAuth,
  SiteModeState,
  connectSiteMode,
  ThemeConstants,
  AppStrings,
  GalleryDetailBackToTopState,
  connectGalleryDetailBackToTop,
} from 'shared'
import { GalleryListViewModel } from '../viewmodel/GalleryListViewModel'
import { GalleryListBody } from './GalleryListBody'
import { common } from '@kit.AbilityKit'
import { CustomContentDialog } from '@kit.ArkUI'

/**
 * One retained toplist-PERIOD page (V2Next FeedListPage pattern; mirrors GallerySourcePage). NextE
 * presents the period control (全部/年榜/月榜/昨日 = tl 11/12/13/15) as a subtab, so each period owns its
 * OWN GalleryListViewModel + datasource + scroller, kept alive by ToplistPage's Swiper. Switching period
 * away and back preserves that period's list AND scroll — no shared-list reload. HomeSourceState.toplistTl
 * stays a pure selection bus (it holds no data).
 *
 * Lazy first-load: a period loads its first page only when it FIRST becomes the active tab. Although
 * toplist.php itself is e-hentai only, its response carries the active Cookie and user-tag filtering, so
 * retained periods refetch when the account or 表/里 context changes.
 */
@ComponentV2
export struct ToplistPeriodPage {
  // Toplist period: tl 11 all-time / 12 year / 13 month / 15 yesterday. Stable (the Swiper key).
  @Param periodTl: number = 15;
  // Shared active-key signal from the host; active when active.activeKey === this period's key (`${tl}`).
  @Param active: ActiveKeyState = new ActiveKeyState();
  // Index-bound scroller for this period (title auto-hide follows the active period's list).
  @Param scroller: Scroller = new Scroller();
  @Event onDidScroll?: (offset: number, state: ScrollState) => void;
  @Local vm: GalleryListViewModel = new GalleryListViewModel();
  @Local auth: AuthState = connectAuth();
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local toplistFilter: ToplistFilterState = connectToplistFilter();
  @Local localBlock: LocalBlockState = connectLocalBlock();
  @Local homeSource: HomeSourceState = connectHomeSource();
  @Local galleryDetailBackToTop: GalleryDetailBackToTopState = connectGalleryDetailBackToTop();
  @Local jumpPageText: string = '';
  @Local jumpError: string = '';
  private jumpSubmitting: boolean = false;
  private loadedOnce: boolean = false;
  private jumpDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.toplist_jump_page'),
      contentBuilder: () => {
        this.ToplistJumpDialogContent()
      },
      buttons: [
        {
          value: $r('app.string.common_cancel'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeJumpDialog()
          },
        },
        {
          value: $r('app.string.toplist_jump_page'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.confirmToplistJump()
          },
        },
      ],
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
  });

  private isActive(): boolean {
    return this.active.activeKey === `${this.periodTl}`
  }

  private primaryBackToTopEnabled(): boolean {
    return this.isActive() && this.galleryDetailBackToTop.primaryEnabled()
  }

  private reportPrimaryUserScroll(): void {
    if (this.isActive()) {
      this.galleryDetailBackToTop.selectPrimary()
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.vm.syncSource('toplist', this.periodTl)
    this.vm.setContext(this.ctx())
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  // Host's @Trace activeKey reaches cached pages, so first activation (tap or swipe) fires reliably.
  @Monitor('active.activeKey')
  onActiveChange(): void {
    if (this.isActive()) {
      this.loadOnce()
    }
  }

  @Monitor('homeSource.cmdSeq')
  onHomeCommand(): void {
    if (this.isActive() && this.homeSource.cmdKind === 'openToplistJumpDialog') {
      this.openJumpDialog()
    } else if (this.isActive() && this.homeSource.cmdKind === 'jumpToplistFirstPage') {
      this.jumpToFirstPage()
    }
  }

  private loadOnce(): void {
    if (this.loadedOnce) {
      return
    }
    this.loadedOnce = true
    this.vm.loadData()
  }

  @Monitor('auth.memberId')
  onAccountChange(): void {
    if (this.loadedOnce) {
      this.vm.reload(true)
    }
  }

  @Monitor('siteMode.isEx')
  onSiteChange(): void {
    if (this.loadedOnce) {
      this.vm.reload(true)
    }
  }

  @Monitor('tagTranslation.enabled')
  onTagTranslationChange(): void {
    if (this.loadedOnce) {
      this.vm.reapplyTagTranslation()
    }
  }

  @Monitor('toplistFilter.applyHiddenUserTags')
  onToplistFilterChange(): void {
    if (this.loadedOnce) {
      this.vm.reload(true)
    }
  }

  @Monitor('localBlock.version')
  async onLocalBlockChange(): Promise<void> {
    if (this.loadedOnce) {
      await this.vm.applyLocalBlockChange()
    }
  }

  private openJumpDialog(): void {
    this.jumpPageText = `${this.vm.currentToplistPageNumber()}`
    this.jumpError = ''
    this.jumpDialogController.open()
  }

  private closeJumpDialog(): void {
    try {
      this.jumpDialogController.close()
    } catch (_error) {
      // Dialog may already be dismissed by tapping outside.
    }
  }

  private normalizeJumpInput(value: string): string {
    return (value || '').replace(/[^0-9]/g, '')
  }

  private jumpHelpText(): string {
    const pageCount: number = this.vm.toplistPageCount()
    if (pageCount <= 0) {
      return AppStrings.get('toplist_jump_help')
    }
    return `${AppStrings.get('toplist_jump_help')} 1 - ${pageCount}`
  }

  private confirmToplistJump(): void {
    if (this.jumpSubmitting) {
      return
    }
    const page: number = Number.parseInt(this.jumpPageText, 10)
    const pageCount: number = this.vm.toplistPageCount()
    if (Number.isNaN(page) || page <= 0 || (pageCount > 0 && page > pageCount)) {
      this.jumpError = AppStrings.get('toplist_jump_invalid')
      return
    }
    this.jumpSubmitting = true
    this.vm.jumpToToplistPage(page)
      .then((ok: boolean) => {
        this.jumpSubmitting = false
        if (!ok) {
          this.jumpError = AppStrings.get('common_load_failed')
          return
        }
        this.closeJumpDialog()
        setTimeout(() => {
          this.scroller.scrollToIndex(0)
        }, 50)
      })
      .catch((_error: Error) => {
        this.jumpSubmitting = false
        this.jumpError = AppStrings.get('common_load_failed')
      })
  }

  private jumpToFirstPage(): void {
    if (this.jumpSubmitting) {
      return
    }
    this.jumpSubmitting = true
    this.vm.reload()
      .then((committed: boolean) => {
        this.jumpSubmitting = false
        if (committed) {
          setTimeout(() => {
            this.scroller.scrollToIndex(0)
          }, 50)
        }
      })
      .catch((_error: Error) => {
        this.jumpSubmitting = false
      })
  }

  @Builder
  ToplistJumpDialogContent() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text(this.jumpHelpText())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({
        text: this.jumpPageText,
        placeholder: $r('app.string.toplist_jump_placeholder'),
      })
        .type(InputType.Number)
        .inputFilter('^[0-9]*$')
        .defaultFocus(true)
        .width('100%')
        .onChange((value: string) => {
          this.jumpPageText = this.normalizeJumpInput(value)
          this.jumpError = ''
        })
      if (this.jumpError.length > 0) {
        Text(this.jumpError)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor(Color.Red)
          .width('100%')
      }
    }.width('100%')
  }

  build() {
    GalleryListBody({
      vm: this.vm,
      topPadding: SELECTOR_BAR_HEIGHT,
      scroller: this.scroller,
      backToTop: this.primaryBackToTopEnabled(),
      onDidScroll: (offset: number, state: ScrollState) => {
        if (this.onDidScroll) {
          this.onDidScroll(offset, state)
        }
      },
      onUserScroll: () => {
        this.reportPrimaryUserScroll()
      },
    })
  }
}
