import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  SecondaryListScaffold,
  SYNC_STATUS_FAILED,
  SYNC_STATUS_OK,
  SyncSettings,
  SyncSettingsSnapshot,
  SyncSettingsState,
  ThemeConstants,
  WebDavSyncConfig,
  WebDavSyncService,
  connectSyncSettings,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct WebDavSyncSettingsPage {
  @Local private settings: SyncSettingsState = connectSyncSettings();
  @Local private webdavUrlDraft: string = '';
  @Local private webdavUsernameDraft: string = '';
  @Local private webdavPasswordDraft: string = '';
  @Local private syncing: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.webdavUrlDraft = this.settings.webdavUrl
    this.webdavUsernameDraft = this.settings.webdavUsername
    this.webdavPasswordDraft = this.settings.webdavPassword
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private snapshot(): SyncSettingsSnapshot {
    const snapshot = SyncSettings.current()
    snapshot.webdavUrl = this.webdavUrlDraft
    snapshot.webdavUsername = this.webdavUsernameDraft
    snapshot.webdavPassword = this.webdavPasswordDraft
    return snapshot
  }

  private save(): void {
    SyncSettings.save(this.ctx(), this.snapshot())
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private toggleWebDav(enabled: boolean): void {
    const snapshot = this.snapshot()
    snapshot.webdavEnabled = enabled
    SyncSettings.save(this.ctx(), snapshot)
  }

  private canSync(): boolean {
    return !this.syncing && this.settings.webdavEnabled && this.webdavUrlDraft.trim().length > 0
  }

  private statusText(): ResourceStr {
    if (!this.settings.webdavEnabled) {
      return $r('app.string.sync_provider_disabled')
    }
    if (this.syncing) {
      return $r('app.string.sync_status_running')
    }
    if (this.webdavUrlDraft.trim().length <= 0) {
      return $r('app.string.sync_webdav_url_required')
    }
    if (this.settings.lastStatus === SYNC_STATUS_OK) {
      return $r('app.string.sync_status_success', this.formatTime(this.settings.lastRunAt))
    }
    if (this.settings.lastStatus === SYNC_STATUS_FAILED) {
      return $r('app.string.sync_status_failed', this.formatTime(this.settings.lastRunAt))
    }
    return $r('app.string.sync_status_never')
  }

  private formatTime(value: number): string {
    if (value <= 0) {
      return AppStrings.get('unknown_time')
    }
    const date = new Date(value)
    const year = date.getFullYear().toString().padStart(4, '0')
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hour = date.getHours().toString().padStart(2, '0')
    const minute = date.getMinutes().toString().padStart(2, '0')
    return `${year}-${month}-${day} ${hour}:${minute}`
  }

  private syncNow(): void {
    if (!this.canSync()) {
      if (this.webdavUrlDraft.trim().length <= 0) {
        this.toast($r('app.string.sync_webdav_url_required'))
      }
      return
    }
    this.syncing = true
    this.save()
    const config = new WebDavSyncConfig()
    config.directoryUrl = this.webdavUrlDraft.trim()
    config.username = this.webdavUsernameDraft.trim()
    config.password = this.webdavPasswordDraft
    config.selection = SyncSettings.selection(this.snapshot())
    DiagnosticLogger.info('sync', 'manual_webdav_sync_start', 'provider=webdav')
    WebDavSyncService.syncNow(this.ctx(), config)
      .then(() => {
        SyncSettings.markRun(this.ctx(), SYNC_STATUS_OK)
        DiagnosticLogger.info('sync', 'manual_webdav_sync_success', 'provider=webdav')
        this.toast($r('app.string.sync_now_done'))
      })
      .catch((error: Error) => {
        SyncSettings.markRun(this.ctx(), SYNC_STATUS_FAILED)
        DiagnosticLogger.warn('sync', 'manual_webdav_sync_failed', error.message)
        this.toast($r('app.string.sync_now_failed'))
      })
      .finally(() => {
        this.syncing = false
      })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private TextInputRow(
    label: ResourceStr,
    placeholder: ResourceStr,
    secret: boolean,
    field: string,
  ) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (field === 'url') {
        TextInput({ text: $$this.webdavUrlDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .onChange(() => {
            this.save()
          })
      } else if (field === 'username') {
        TextInput({ text: $$this.webdavUsernameDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .onChange(() => {
            this.save()
          })
      } else {
        TextInput({ text: $$this.webdavPasswordDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .onChange(() => {
            this.save()
          })
      }
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
  }

  @Builder
  private SyncingSuffix() {
    LoadingProgress()
      .width(22)
      .height(22)
      .color(ThemeConstants.BRAND_PRIMARY)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.sync_webdav'),
              subtitle: $r('app.string.sync_webdav_hint'),
              leadingIcon: $r('sys.symbol.externaldrive'),
              showChevron: false,
              hasSwitch: true,
              checked: this.settings.webdavEnabled,
              switchAction: (value: boolean) => {
                this.toggleWebDav(value)
              },
            })
            this.rowDivider()
            if (this.syncing) {
              ConciseListRow({
                title: $r('app.string.sync_webdav_now'),
                subtitle: this.statusText(),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                isEnabled: false,
                suffixBuilderParam: () => {
                  this.SyncingSuffix()
                },
              })
            } else {
              ConciseListRow({
                title: $r('app.string.sync_webdav_now'),
                subtitle: this.statusText(),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                isEnabled: this.canSync(),
                action: () => {
                  this.syncNow()
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            this.TextInputRow(
              $r('app.string.sync_webdav_url'),
              $r('app.string.sync_webdav_url_hint'),
              false,
              'url',
            )
            this.rowDivider()
            this.TextInputRow(
              $r('app.string.sync_webdav_username'),
              $r('app.string.sync_webdav_username_hint'),
              false,
              'username',
            )
            this.rowDivider()
            this.TextInputRow(
              $r('app.string.sync_webdav_password'),
              $r('app.string.sync_webdav_password_hint'),
              true,
              'password',
            )
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('sync_webdav')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
