import { common, Want } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  HuaweiCloudSyncService,
  SecondaryListScaffold,
  SYNC_STATUS_FAILED,
  SYNC_STATUS_OK,
  SyncSettings,
  SyncSettingsSnapshot,
  SyncSettingsState,
  ThemeConstants,
  connectNavStack,
  connectSyncSettings,
  immersiveTitleBar,
} from 'shared'

const HUAWEI_CLOUD_DEEP_LINK: string = 'hicloud://cloudDrive/getInfo?path=MainActivity'

@ComponentV2
export struct SyncSettingsPage {
  @Local private settings: SyncSettingsState = connectSyncSettings();
  @Local private cloudSwitching: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private snapshot(): SyncSettingsSnapshot {
    return SyncSettings.current()
  }

  private setDataset(field: string, enabled: boolean): void {
    const snapshot = this.snapshot()
    if (field === 'readProgress') {
      snapshot.datasetReadProgress = enabled
    } else if (field === 'viewedHistory') {
      snapshot.datasetViewedHistory = enabled
    } else if (field === 'localFavorites') {
      snapshot.datasetLocalFavorites = enabled
    } else if (field === 'searchHistory') {
      snapshot.datasetSearchHistory = enabled
    } else if (field === 'localBlock') {
      snapshot.datasetLocalBlock = enabled
    } else if (field === 'customProfiles') {
      snapshot.datasetCustomProfiles = enabled
    }
    SyncSettings.save(this.ctx(), snapshot)
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private canHuaweiCloudSync(): boolean {
    return HuaweiCloudSyncService.available() &&
      !this.settings.huaweiCloudSyncing &&
      !this.cloudSwitching &&
      this.settings.huaweiCloudEnabled
  }

  private webdavStatusText(): ResourceStr {
    if (!this.settings.webdavEnabled) {
      return $r('app.string.sync_provider_disabled')
    }
    if (this.settings.webdavUrl.trim().length <= 0) {
      return $r('app.string.sync_webdav_url_required')
    }
    if (this.settings.lastStatus === SYNC_STATUS_OK) {
      return $r('app.string.sync_status_success', this.formatTime(this.settings.lastRunAt))
    }
    if (this.settings.lastStatus === SYNC_STATUS_FAILED) {
      if (this.settings.lastDetail.length > 0) {
        return `${AppStrings.get('sync_now_failed')}: ${this.settings.lastDetail}`
      }
      return $r('app.string.sync_status_failed', this.formatTime(this.settings.lastRunAt))
    }
    return $r('app.string.sync_status_never')
  }

  private huaweiCloudStatusText(): ResourceStr {
    if (this.settings.huaweiCloudSyncing || this.cloudSwitching) {
      return $r('app.string.sync_status_running')
    }
    if (this.settings.huaweiCloudLastCloudDisabled) {
      return $r('app.string.sync_huawei_cloud_disabled_status')
    }
    if (this.settings.huaweiCloudLastStatus === SYNC_STATUS_OK) {
      return $r('app.string.sync_status_success', this.formatTime(this.settings.huaweiCloudLastRunAt))
    }
    if (this.settings.huaweiCloudLastStatus === SYNC_STATUS_FAILED) {
      const detail: string = this.huaweiCloudFailureDetail('')
      if (detail.length > 0) {
        return this.huaweiCloudFailureMessage('')
      }
      return $r('app.string.sync_status_failed', this.formatTime(this.settings.huaweiCloudLastRunAt))
    }
    return $r('app.string.sync_status_never')
  }

  private huaweiCloudFailureMessage(fallback: string): string {
    const detail: string = this.huaweiCloudFailureDetail(fallback)
    if (detail.length <= 0) {
      return AppStrings.get('sync_now_failed')
    }
    return `${AppStrings.get('sync_now_failed')}: ${detail}`
  }

  private huaweiCloudFailureDetail(fallback: string): string {
    let detail: string = HuaweiCloudSyncService.lastRunDetailMessage()
    if (detail.length <= 0) {
      detail = this.settings.huaweiCloudLastDetail
    }
    if (detail.length <= 0) {
      detail = fallback
    }
    return detail
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

  private toggleHuaweiCloud(enabled: boolean): void {
    if (!HuaweiCloudSyncService.available() || this.cloudSwitching) {
      return
    }
    const snapshot = this.snapshot()
    if (!enabled) {
      snapshot.huaweiCloudEnabled = false
      SyncSettings.save(this.ctx(), snapshot)
      return
    }
    this.cloudSwitching = true
    HuaweiCloudSyncService.ensurePermission(this.ctx())
      .then((granted: boolean) => {
        const next = this.snapshot()
        next.huaweiCloudEnabled = granted
        if (!granted) {
          SyncSettings.save(this.ctx(), next)
          this.toast($r('app.string.sync_huawei_cloud_permission_denied'))
          return false
        }
        return SyncSettings.save(this.ctx(), next)
          .then(() => HuaweiCloudSyncService.markDistributedTables(
            this.ctx(),
            SyncSettings.selection(next),
          ))
      })
      .then((marked: boolean | void) => {
        if (marked === false) {
          const next = this.snapshot()
          next.huaweiCloudEnabled = false
          SyncSettings.save(this.ctx(), next)
          this.toast($r('app.string.sync_now_failed'))
          return
        }
        if (marked === true) {
          this.toast($r('app.string.sync_huawei_cloud_enabled'))
        }
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('sync', 'huawei_cloud_enable_failed', error.message)
        const next = this.snapshot()
        next.huaweiCloudEnabled = false
        SyncSettings.save(this.ctx(), next)
        this.toast($r('app.string.sync_now_failed'))
      })
      .finally(() => {
        this.cloudSwitching = false
      })
  }

  private syncHuaweiCloudNow(): void {
    if (!this.canHuaweiCloudSync()) {
      return
    }
    DiagnosticLogger.info('sync', 'manual_huawei_cloud_sync_start', 'provider=huawei_cloud')
    HuaweiCloudSyncService.cloudSyncNow(this.ctx(), SyncSettings.selection(this.snapshot()))
      .then((ok: boolean) => {
        const detail: string = HuaweiCloudSyncService.lastRunDetailMessage()
        DiagnosticLogger.info('sync', 'manual_huawei_cloud_sync_done', `ok=${ok},detail=${detail}`)
        this.toast(ok ? $r('app.string.sync_now_done') : this.huaweiCloudFailureMessage(''))
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('sync', 'manual_huawei_cloud_sync_failed', error.message)
        this.toast(this.huaweiCloudFailureMessage(error.message))
      })
  }

  private openHuaweiCloudSpace(): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: HUAWEI_CLOUD_DEEP_LINK }
    this.ctx().startAbility(want).catch((error: Error) => {
      DiagnosticLogger.warn('sync', 'open_huawei_cloud_space_failed', error.message)
      this.toast($r('app.string.sync_huawei_cloud_open_failed'))
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
  private SyncingSuffix() {
    LoadingProgress()
      .width(22)
      .height(22)
      .color(ThemeConstants.BRAND_PRIMARY)
  }

  @Builder
  private DatasetRow(
    title: ResourceStr,
    subtitle: ResourceStr,
    checked: boolean,
    field: string,
  ) {
    ConciseListRow({
      title: title,
      subtitle: subtitle,
      showChevron: false,
      hasSwitch: true,
      checked: checked,
      switchAction: (value: boolean) => {
        this.setDataset(field, value)
      },
    })
  }

  @Builder
  private HuaweiCloudSyncRow() {
    if (this.settings.huaweiCloudSyncing || this.cloudSwitching) {
      ConciseListRow({
        title: $r('app.string.sync_huawei_cloud_now'),
        subtitle: this.huaweiCloudStatusText(),
        leadingIcon: $r('sys.symbol.cloud_and_arrow_up'),
        showChevron: false,
        isEnabled: false,
        suffixBuilderParam: () => {
          this.SyncingSuffix()
        },
      })
    } else {
      ConciseListRow({
        title: $r('app.string.sync_huawei_cloud_now'),
        subtitle: this.huaweiCloudStatusText(),
        leadingIcon: $r('sys.symbol.cloud_and_arrow_up'),
        showChevron: false,
        isEnabled: this.canHuaweiCloudSync(),
        action: () => {
          this.syncHuaweiCloudNow()
        },
      })
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
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.sync_webdav'),
              subtitle: this.webdavStatusText(),
              leadingIcon: $r('sys.symbol.externaldrive'),
              showChevron: true,
              action: () => {
                this.stack.pushPathByName('WebDavSyncSettings', null)
              },
            })
            if (HuaweiCloudSyncService.available()) {
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.sync_huawei_cloud'),
                subtitle: $r('app.string.sync_huawei_cloud_hint'),
                leadingIcon: $r('sys.symbol.cloud'),
                showChevron: false,
                hasSwitch: true,
                checked: this.settings.huaweiCloudEnabled,
                switchAction: (value: boolean) => {
                  this.toggleHuaweiCloud(value)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.sync_huawei_cloud_open_space'),
                subtitle: this.settings.huaweiCloudLastCloudDisabled ?
                  $r('app.string.sync_huawei_cloud_disabled_status') : $r('app.string.sync_huawei_cloud_open_space_hint'),
                leadingIcon: $r('sys.symbol.arrow_right_folder_fill'),
                showChevron: true,
                action: () => {
                  this.openHuaweiCloudSpace()
                },
              })
              this.rowDivider()
              this.HuaweiCloudSyncRow()
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            this.DatasetRow(
              $r('app.string.sync_dataset_read_progress'),
              $r('app.string.sync_dataset_read_progress_hint'),
              this.settings.datasetReadProgress,
              'readProgress',
            )
            this.rowDivider()
            this.DatasetRow(
              $r('app.string.sync_dataset_viewed_history'),
              $r('app.string.sync_dataset_viewed_history_hint'),
              this.settings.datasetViewedHistory,
              'viewedHistory',
            )
            this.rowDivider()
            this.DatasetRow(
              $r('app.string.sync_dataset_local_favorites'),
              $r('app.string.sync_dataset_local_favorites_hint'),
              this.settings.datasetLocalFavorites,
              'localFavorites',
            )
            this.rowDivider()
            this.DatasetRow(
              $r('app.string.sync_dataset_search_history'),
              $r('app.string.sync_dataset_search_history_hint'),
              this.settings.datasetSearchHistory,
              'searchHistory',
            )
            this.rowDivider()
            this.DatasetRow(
              $r('app.string.sync_dataset_local_block'),
              $r('app.string.sync_dataset_local_block_hint'),
              this.settings.datasetLocalBlock,
              'localBlock',
            )
            this.rowDivider()
            this.DatasetRow(
              $r('app.string.sync_dataset_custom_profiles'),
              $r('app.string.sync_dataset_custom_profiles_hint'),
              this.settings.datasetCustomProfiles,
              'customProfiles',
            )
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_sync')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
