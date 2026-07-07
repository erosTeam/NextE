import { HdsNavDestination } from '@kit.UIDesignKit'
import { bundleManager, common, Want } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import {
  AppStrings,
  ConciseListRow,
  EhConstants,
  GroupedListSection,
  SecondaryListScaffold,
  SectionHeader,
  ThemeConstants,
  immersiveTitleBar,
  DiagnosticLogger,
  SafeModeSettings,
  SafeModeState,
  connectSafeMode,
} from 'shared'

const APP_RELEASE_API_URL: string = 'https://api.github.com/repos/erosTeam/NextE/releases/latest'
const APP_UPDATE_CONNECT_TIMEOUT_MS: number = 15000
const APP_UPDATE_READ_TIMEOUT_MS: number = 20000
const RELEASE_BODY_MAX_CHARS: number = 1800

class AppReleaseResponse {
  tag_name: string = ''
  body: string = ''
  html_url: string = ''
}

@ComponentV2
export struct AboutPage {
  @Local appVersion: string = ''
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local safeModeTapCount: number = 0;
  @Local updateChecking: boolean = false;
  @Local updateChecked: boolean = false;
  @Local latestVersion: string = '';
  @Local canUpdate: boolean = false;
  private releasePageUrl: string = '';
  private releaseBody: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .then((info) => {
        this.appVersion = info.versionName
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('settings', 'about_bundle_info_failed', error.message)
      })
  }

  private versionText(): string {
    if (this.appVersion.length > 0) {
      return this.appVersion
    }
    return '1.1.8'
  }

  private updateSubtitle(): string {
    if (this.updateChecking) {
      return AppStrings.get('about_update_checking')
    }
    if (!this.updateChecked || this.latestVersion.length === 0) {
      return AppStrings.get('about_update_hint')
    }
    if (this.canUpdate) {
      return AppStrings.get('about_update_available').replace('%s', this.latestVersion)
    }
    return AppStrings.get('about_update_latest').replace('%s', this.latestVersion)
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
    if (!this.safeMode.buildEnabled || this.safeMode.unlocked) {
      return
    }
    this.safeModeTapCount += 1
    if (this.safeModeTapCount < 5) {
      return
    }
    SafeModeSettings.unlock(this.ctx())
    this.getUIContext().getPromptAction()
      .openToast({ message: $r('app.string.safe_mode_unlocked') })
      .catch((_error: Error) => {
        // Unlock state is already persisted; toast failure is non-critical.
      })
  }

  private checkUpdate(): void {
    if (this.updateChecking) {
      return
    }
    this.updateChecking = true
    this.fetchLatestRelease()
      .then((release: AppReleaseResponse) => {
        const remote: string = AboutPage.normalizeVersion(release.tag_name)
        if (remote.length === 0) {
          throw new Error('release version unavailable')
        }
        this.latestVersion = remote
        this.releasePageUrl = release.html_url.trim()
        this.releaseBody = release.body.trim()
        this.canUpdate = AboutPage.compareVersions(this.versionText(), remote) < 0
        this.updateChecked = true
        if (this.canUpdate) {
          this.showUpdateDialog()
        } else {
          this.toast(AppStrings.get('about_update_latest').replace('%s', remote))
        }
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('settings', 'about_update_check_failed', error.message)
        this.toast(`${AppStrings.get('about_update_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.updateChecking = false
      })
  }

  private async fetchLatestRelease(): Promise<AppReleaseResponse> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const header: Record<string, string> = {
        'User-Agent': EhConstants.USER_AGENT,
        'Accept': 'application/vnd.github+json,application/json,*/*',
        'Accept-Language': EhConstants.ACCEPT_LANGUAGE,
      }
      const resp: http.HttpResponse = await req.request(APP_RELEASE_API_URL, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: APP_UPDATE_CONNECT_TIMEOUT_MS,
        readTimeout: APP_UPDATE_READ_TIMEOUT_MS,
        usingCache: false,
      })
      const code: number = resp.responseCode as number
      if (code !== 200) {
        throw new Error(`GitHub release HTTP ${code}`)
      }
      const body: string = typeof resp.result === 'string' ? (resp.result as string) : ''
      try {
        return JSON.parse(body) as AppReleaseResponse
      } catch (_error) {
        throw new Error('GitHub release JSON invalid')
      }
    } finally {
      req.destroy()
    }
  }

  private showUpdateDialog(): void {
    const notes: string = this.releaseNotesPreview()
    this.getUIContext().showAlertDialog({
      title: AppStrings.get('about_update_available').replace('%s', this.latestVersion),
      message: notes,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.about_update_open_release'),
        action: () => {
          this.openReleasePage()
        },
      },
    })
  }

  private releaseNotesPreview(): string {
    const body: string = this.releaseBody.length > 0 ? this.releaseBody : AppStrings.get('about_update_no_notes')
    if (body.length <= RELEASE_BODY_MAX_CHARS) {
      return body
    }
    return `${body.substring(0, RELEASE_BODY_MAX_CHARS)}\n\n${AppStrings.get('about_update_notes_truncated')}`
  }

  private openReleasePage(): void {
    if (this.releasePageUrl.length === 0) {
      return
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: this.releasePageUrl }
    this.ctx().startAbility(want).catch((error: Error) => {
      DiagnosticLogger.warn('settings', 'about_update_open_release_failed', error.message)
      this.toast($r('app.string.about_update_open_failed'))
    })
  }

  private static normalizeVersion(value: string): string {
    let out: string = value.trim()
    if (out.startsWith('v') || out.startsWith('V')) {
      out = out.substring(1)
    }
    const plus: number = out.indexOf('+')
    if (plus >= 0) {
      out = out.substring(0, plus)
    }
    const dash: number = out.indexOf('-')
    if (dash >= 0) {
      out = out.substring(0, dash)
    }
    return out.trim()
  }

  private static compareVersions(current: string, latest: string): number {
    const a: string[] = AboutPage.normalizeVersion(current).split('.')
    const b: string[] = AboutPage.normalizeVersion(latest).split('.')
    const max: number = Math.max(a.length, b.length)
    for (let i: number = 0; i < max; i++) {
      const left: number = i < a.length ? Number.parseInt(a[i], 10) : 0
      const right: number = i < b.length ? Number.parseInt(b[i], 10) : 0
      const safeLeft: number = Number.isFinite(left) ? left : 0
      const safeRight: number = Number.isFinite(right) ? right : 0
      if (safeLeft < safeRight) {
        return -1
      }
      if (safeLeft > safeRight) {
        return 1
      }
    }
    return 0
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
        showChevron: !this.updateChecking,
        isEnabled: !this.updateChecking,
        action: () => {
          this.checkUpdate()
        },
      })
      this.DividerRow()
      ConciseListRow({
        title: $r('app.string.about_platform'),
        trailingText: 'HarmonyOS NEXT',
        showChevron: false,
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
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
