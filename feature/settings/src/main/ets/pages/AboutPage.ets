import { HdsNavDestination } from '@kit.UIDesignKit'
import { bundleManager, common, Want } from '@kit.AbilityKit'
import { AdvancedDialogV2Button, CustomContentDialogV2, LengthMetrics } from '@kit.ArkUI'
import {
  AppStrings,
  AppRelease,
  AppReleaseCacheSnapshot,
  AppReleaseService,
  ConciseListRow,
  GroupedListSection,
  ReleaseNotesPager,
  SecondaryListScaffold,
  SectionHeader,
  ThemeConstants,
  immersiveTitleBar,
  DiagnosticLogger,
  SafeModeSettings,
  SafeModeState,
  connectSafeMode,
  connectNavStack,
  NavStackHolder,
} from 'shared'

const SYSTEM_SYMBOL_BROWSER_OPEN_TAPS: number = 5
const SYSTEM_SYMBOL_BROWSER_TAP_WINDOW_MS: number = 2500

@ComponentV2
export struct AboutPage {
  @Local appVersion: string = ''
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local safeModeTapCount: number = 0;
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  @Local platformTapCount: number = 0;
  @Local updateChecking: boolean = false;
  @Local updateChecked: boolean = false;
  @Local latestVersion: string = '';
  @Local canUpdate: boolean = false;
  @Local releaseHistory: AppRelease[] = [];
  @Local selectedReleaseIndex: number = 0;
  private updateDialogId: number = -1;
  private releaseSnapshot: AppReleaseCacheSnapshot = new AppReleaseCacheSnapshot();
  private releaseLoadGeneration: number = 0;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;
  private lastPlatformTapAt: number = 0;

  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .then((info) => {
        this.appVersion = info.versionName
        this.applyReleaseSnapshot(this.releaseSnapshot)
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('settings', 'about_bundle_info_failed', error.message)
      })
    this.loadReleaseHistory()
  }

  private versionText(): string {
    if (this.appVersion.length > 0) {
      return this.appVersion
    }
    return '1.3.2'
  }

  private updateSubtitle(): string {
    if (this.updateChecked && this.latestVersion.length > 0) {
      if (this.canUpdate) {
        return AppStrings.get('about_update_available').replace('%s', this.latestVersion)
      }
      return AppStrings.get('about_update_latest').replace('%s', this.latestVersion)
    }
    if (this.updateChecking) {
      return AppStrings.get('about_update_checking')
    }
    return AppStrings.get('about_update_hint')
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction()
      .openToast({ message: message })
      .catch((_error: Error) => {})
  }

  private onVersionTap(): void {
    if (!this.safeMode.buildEnabled) {
      return
    }
    this.safeModeTapCount += 1
    if (this.safeModeTapCount < 5) {
      return
    }
    this.safeModeTapCount = 0
    const wasUnlocked: boolean = this.safeMode.unlocked
    if (wasUnlocked) {
      SafeModeSettings.lock(this.ctx())
    } else {
      SafeModeSettings.unlock(this.ctx())
    }
    this.getUIContext().getPromptAction()
      .openToast({
        message: wasUnlocked
          ? $r('app.string.safe_mode_locked')
          : $r('app.string.safe_mode_unlocked'),
      })
      .catch((_error: Error) => {
        // Safe-mode state is already applied; toast failure is non-critical.
      })
  }

  private onPlatformTap(): void {
    const now: number = Date.now()
    if (now - this.lastPlatformTapAt > SYSTEM_SYMBOL_BROWSER_TAP_WINDOW_MS) {
      this.platformTapCount = 0
    }
    this.lastPlatformTapAt = now
    this.platformTapCount += 1
    if (this.platformTapCount < SYSTEM_SYMBOL_BROWSER_OPEN_TAPS) {
      return
    }
    this.platformTapCount = 0
    this.stack.pushPathByName('SystemSymbolBrowser', null)
  }

  private loadReleaseHistory(): void {
    const generation: number = this.releaseLoadGeneration + 1
    this.releaseLoadGeneration = generation
    const context: common.UIAbilityContext = this.ctx()
    AppReleaseService.loadCached(context)
      .then((cached: AppReleaseCacheSnapshot) => {
        if (!this.isCurrentReleaseLoad(generation)) {
          return cached
        }
        this.applyReleaseSnapshot(cached)
        this.updateChecking = true
        return AppReleaseService.refresh(context, cached, false)
      })
      .then((snapshot: AppReleaseCacheSnapshot) => {
        if (this.isCurrentReleaseLoad(generation)) {
          this.applyReleaseSnapshot(snapshot)
        }
      })
      .catch((error: Error) => {
        if (this.isCurrentReleaseLoad(generation)) {
          DiagnosticLogger.warn('settings', 'about_release_refresh_failed', error.message)
        }
      })
      .finally(() => {
        if (this.isCurrentReleaseLoad(generation)) {
          this.updateChecking = false
        }
      })
  }

  private loadReleaseHistoryForDialog(): void {
    const generation: number = this.releaseLoadGeneration + 1
    this.releaseLoadGeneration = generation
    this.updateChecking = true
    const context: common.UIAbilityContext = this.ctx()
    AppReleaseService.loadCached(context)
      .then((cached: AppReleaseCacheSnapshot) => {
        if (cached.releases.length > 0) {
          return cached
        }
        return AppReleaseService.refresh(context, cached, true)
      })
      .then((snapshot: AppReleaseCacheSnapshot) => {
        if (!this.isCurrentReleaseLoad(generation)) {
          return
        }
        this.applyReleaseSnapshot(snapshot)
        if (this.releaseHistory.length === 0) {
          throw new Error('release history unavailable')
        }
        this.showUpdateDialog()
      })
      .catch((error: Error) => {
        if (this.isCurrentReleaseLoad(generation)) {
          DiagnosticLogger.warn('settings', 'about_release_open_failed', error.message)
          this.toast(`${AppStrings.get('about_update_failed')}: ${error.message}`)
        }
      })
      .finally(() => {
        if (this.isCurrentReleaseLoad(generation)) {
          this.updateChecking = false
        }
      })
  }

  private isCurrentReleaseLoad(generation: number): boolean {
    return this.releaseLoadGeneration === generation
  }

  private applyReleaseSnapshot(snapshot: AppReleaseCacheSnapshot): void {
    const copied: AppReleaseCacheSnapshot = snapshot.copy()
    this.releaseSnapshot = copied
    this.releaseHistory = copied.releases
    const latest: AppRelease | null = AppReleaseService.latestStable(copied)
    if (latest === null || latest.version().length === 0) {
      this.latestVersion = ''
      this.canUpdate = false
      this.updateChecked = false
      this.selectedReleaseIndex = 0
      return
    }
    this.latestVersion = latest.version()
    this.canUpdate = AppReleaseService.compareVersions(this.versionText(), this.latestVersion) < 0
    this.updateChecked = true
    this.selectedReleaseIndex = AppReleaseService.indexForVersion(this.releaseHistory, this.versionText())
  }

  private onUpdateRowClick(): void {
    if (this.releaseHistory.length > 0) {
      this.showUpdateDialog()
      return
    }
    this.loadReleaseHistoryForDialog()
  }

  private showUpdateDialog(): void {
    if (this.releaseHistory.length === 0) {
      return
    }
    this.selectedReleaseIndex = AppReleaseService.indexForVersion(this.releaseHistory, this.versionText())
    this.updateDialogId = -1
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.UpdateDialog()
      },
      autoCancel: true,
      alignment: DialogAlignment.Center,
    })
      .then((dialogId: number) => {
        this.updateDialogId = dialogId
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('settings', 'about_update_dialog_open_failed', error.message)
        this.toast($r('app.string.about_update_failed'))
      })
  }

  private closeUpdateDialog(): void {
    const dialogId: number = this.updateDialogId
    if (dialogId < 0) {
      return
    }
    this.updateDialogId = -1
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(dialogId)
    } catch (_error) {
      // The dialog may already have been dismissed by a system gesture.
    }
  }

  @Builder
  private UpdateDialog() {
    CustomContentDialogV2({
      primaryTitle: this.canUpdate
        ? AppStrings.get('about_update_available').replace('%s', this.latestVersion)
        : AppStrings.get('about_release_notes'),
      contentBuilder: () => {
        this.UpdateDialogContent()
      },
      // The dialog, not the paged body, owns the separation from its fixed action area.
      // Keep the established 24vp horizontal inset and reserve the same bottom inset so
      // a long release-note viewport cannot visually run into the two action buttons
      // when the available height contracts in landscape.
      contentAreaPadding: {
        top: LengthMetrics.vp(0),
        bottom: LengthMetrics.vp(ThemeConstants.SPACE_XL),
        start: LengthMetrics.vp(ThemeConstants.SPACE_XL),
        end: LengthMetrics.vp(ThemeConstants.SPACE_XL),
      },
      buttons: [
        new AdvancedDialogV2Button({
          content: $r('app.string.common_cancel'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeUpdateDialog()
          },
        }),
        new AdvancedDialogV2Button({
          content: $r('app.string.about_update_open_release'),
          buttonStyle: ButtonStyleMode.TEXTUAL,
          action: () => {
            this.closeUpdateDialog()
            this.openReleasePage()
          },
        }),
      ],
    })
  }

  @Builder
  private UpdateDialogContent() {
    ReleaseNotesPager({
      releases: this.releaseHistory,
      initialIndex: this.selectedReleaseIndex,
      emptyText: AppStrings.get('about_update_no_notes'),
      focusRailImage: $r('app.media.release_notes_focus_rail'),
      onReleaseChanged: (index: number) => {
        this.selectedReleaseIndex = index
      },
      onLinkClick: (url: string) => {
        this.openReleaseNoteLink(url)
      },
    })
      .width('100%')
  }

  private openReleaseNoteLink(url: string): void {
    if (url.length === 0) {
      return
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url }
    this.ctx().startAbility(want).catch((error: Error) => {
      DiagnosticLogger.warn('settings', 'about_update_open_note_link_failed', error.message)
      this.toast($r('app.string.about_update_open_failed'))
    })
  }

  private openReleasePage(): void {
    const release: AppRelease | null = this.selectedRelease()
    if (release === null || release.htmlUrl.length === 0) {
      return
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: release.htmlUrl }
    this.ctx().startAbility(want).catch((error: Error) => {
      DiagnosticLogger.warn('settings', 'about_update_open_release_failed', error.message)
      this.toast($r('app.string.about_update_open_failed'))
    })
  }

  private selectedRelease(): AppRelease | null {
    if (this.releaseHistory.length === 0) {
      return null
    }
    const index: number = Math.max(0, Math.min(this.releaseHistory.length - 1, this.selectedReleaseIndex))
    return this.releaseHistory[index]
  }

  @Builder
  AppHeader() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text('NextE')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      Text($r('app.string.about_tagline'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
      Text(this.versionText())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .onClick(() => {
          this.onVersionTap()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_LG,
      top: ThemeConstants.SPACE_XL,
      bottom: ThemeConstants.SPACE_LG,
    })
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  DividerRow() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  AppInfoSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.about_app_name'),
        trailingText: 'NextE',
        showChevron: false,
      })
      this.DividerRow()
      ConciseListRow({
        title: $r('app.string.about_version'),
        trailingText: this.versionText(),
        showChevron: false,
        action: () => {
          this.onVersionTap()
        },
      })
      this.DividerRow()
      ConciseListRow({
        title: $r('app.string.about_check_update'),
        subtitle: this.updateSubtitle(),
        trailingText: this.updateChecking ? AppStrings.get('about_update_checking') : '',
        showChevron: this.releaseHistory.length > 0 || !this.updateChecking,
        isEnabled: this.releaseHistory.length > 0 || !this.updateChecking,
        action: () => {
          this.onUpdateRowClick()
        },
      })
      this.DividerRow()
      ConciseListRow({
        title: $r('app.string.about_platform'),
        trailingText: 'HarmonyOS NEXT',
        showChevron: false,
        action: () => {
          this.onPlatformTap()
        },
      })
    }
  }

  @Builder
  LicenseSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.about_source_license'),
        trailingText: 'MIT',
        showChevron: false,
      })
      this.DividerRow()
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text($r('app.string.about_unofficial_notice'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
        Text($r('app.string.about_eh_notice'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(ThemeConstants.SPACE_LG)
    }
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'About'
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          this.AppHeader()
        }
        ListItem() {
          SectionHeader({ title: $r('app.string.about_app_info') })
        }
        .margin({ top: ThemeConstants.SPACE_MD })
        ListItem() {
          this.AppInfoSection()
        }
        ListItem() {
          SectionHeader({ title: $r('app.string.about_license') })
        }
        .margin({ top: ThemeConstants.SPACE_MD })
        ListItem() {
          this.LicenseSection()
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_about')))
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDestination(this.stack)
    })
  }
}
