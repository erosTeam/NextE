import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  ArchiveBotBalanceResult,
  ArchiveBotCheckInResult,
  ArchiveBotService,
  ArchiveBotType,
  ConciseListRow,
  DiagnosticLogger,
  DownloadDirectoryImportResult,
  DownloadOriginalMode,
  DownloadQueueSettings,
  DownloadSettings,
  DownloadSettingsState,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectDownloadSettings,
  immersiveTitleBar,
} from 'shared'

/**
 * Download settings page grounded in eros_fe DownloadSettingPage:
 * the queue tab shows tasks, while this settings surface owns policy controls.
 * This first lane exposes only settings that already have persisted NextE state.
 */
@ComponentV2
export struct DownloadSettingsPage {
  @Local downloadSettings: DownloadSettingsState = connectDownloadSettings();
  @Local originalMenuShown: boolean = false;
  @Local archiveBotMenuShown: boolean = false;
  @Local archiveBotAddressDraft: string = '';
  @Local archiveBotApiKeyDraft: string = '';
  @Local archiveBotBalanceBusy: boolean = false;
  @Local archiveBotCheckInBusy: boolean = false;
  @Local archiveBotBalanceStatus: string = '';
  @Local archiveBotCheckInStatus: string = '';
  @Local archiveBotBalanceAutoRefreshing: boolean = false;
  @Local downloadRestoreBusy: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.archiveBotAddressDraft = this.downloadSettings.archiveBotAddress
    this.archiveBotApiKeyDraft = this.downloadSettings.archiveBotApiKey
    this.refreshArchiveBotBalanceSilently()
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private originalModeLabel(): Resource {
    if (this.downloadSettings.originalMode === DownloadOriginalMode.OFF) {
      return $r('app.string.common_off')
    }
    if (this.downloadSettings.originalMode === DownloadOriginalMode.ALWAYS) {
      return $r('app.string.download_original_always')
    }
    return $r('app.string.download_original_ask')
  }

  private setOriginalMode(mode: string): void {
    DownloadSettings.setOriginalMode(this.ctx(), mode)
  }

  private archiveBotTypeLabel(): Resource {
    if (this.downloadSettings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME) {
      return $r('app.string.download_archive_bot_archive_at_home')
    }
    return $r('app.string.download_archive_bot_eh_ar_bot')
  }

  private setArchiveBotType(type: string): void {
    DownloadSettings.setArchiveBotType(this.ctx(), type)
    this.archiveBotAddressDraft = DownloadSettings.archiveBotDefaultAddress(type)
  }

  private saveArchiveBotAddress(): void {
    DownloadSettings.setArchiveBotAddress(this.ctx(), this.archiveBotAddressDraft)
  }

  private saveArchiveBotApiKey(): void {
    DownloadSettings.setArchiveBotApiKey(this.ctx(), this.archiveBotApiKeyDraft)
  }

  private canCheckArchiveBotBalance(): boolean {
    return !this.archiveBotBalanceBusy && DownloadSettings.archiveBotReady(this.downloadSettings)
  }

  private canCheckInArchiveBot(): boolean {
    return !this.archiveBotCheckInBusy && DownloadSettings.archiveBotReady(this.downloadSettings)
  }

  private balanceSubtitle(): ResourceStr {
    if (this.archiveBotBalanceStatus.length > 0) {
      return this.archiveBotBalanceStatus
    }
    if (this.downloadSettings.archiveBotBalanceGp >= 0) {
      return AppStrings.get('download_archive_bot_balance_result')
        .replace('%s', `${this.downloadSettings.archiveBotBalanceGp}`)
    }
    return $r('app.string.download_archive_bot_balance_hint')
  }

  private checkInSubtitle(): ResourceStr {
    return this.archiveBotCheckInStatus.length > 0 ? this.archiveBotCheckInStatus :
      $r('app.string.download_archive_bot_checkin_hint')
  }

  private async refreshArchiveBotBalanceSilently(): Promise<void> {
    if (this.archiveBotBalanceAutoRefreshing || !DownloadSettings.archiveBotReady(this.downloadSettings)) {
      return
    }
    this.archiveBotBalanceAutoRefreshing = true
    DiagnosticLogger.info('download', 'archive_bot_balance_auto_refresh_start', this.downloadSettings.archiveBotType)
    try {
      const result: ArchiveBotBalanceResult = await ArchiveBotService.requestBalance(this.downloadSettings)
      if (result.hasBalance) {
        this.archiveBotBalanceStatus = AppStrings.get('download_archive_bot_balance_result').replace('%s', `${result.gp}`)
        await DownloadSettings.setArchiveBotBalance(this.ctx(), result.gp)
        DiagnosticLogger.info('download', 'archive_bot_balance_auto_refresh_done', `gp=${result.gp}`)
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'archive_bot_balance_auto_refresh_failed', (error as Error).message)
    }
    this.archiveBotBalanceAutoRefreshing = false
  }

  private async checkArchiveBotBalance(): Promise<void> {
    if (!this.canCheckArchiveBotBalance()) {
      return
    }
    this.archiveBotBalanceBusy = true
    DiagnosticLogger.info('download', 'archive_bot_balance_check_start', this.downloadSettings.archiveBotType)
    try {
      const result: ArchiveBotBalanceResult = await ArchiveBotService.requestBalance(this.downloadSettings)
      this.archiveBotBalanceStatus = AppStrings.get('download_archive_bot_balance_result').replace('%s', `${result.gp}`)
      if (result.hasBalance) {
        await DownloadSettings.setArchiveBotBalance(this.ctx(), result.gp)
      }
      DiagnosticLogger.info('download', 'archive_bot_balance_check_done', `gp=${result.gp}`)
    } catch (error) {
      this.archiveBotBalanceStatus = (error as Error).message
      DiagnosticLogger.warn('download', 'archive_bot_balance_check_failed', (error as Error).message)
    }
    this.archiveBotBalanceBusy = false
  }

  private async checkInArchiveBot(): Promise<void> {
    if (!this.canCheckInArchiveBot()) {
      return
    }
    this.archiveBotCheckInBusy = true
    DiagnosticLogger.info('download', 'archive_bot_checkin_start', this.downloadSettings.archiveBotType)
    try {
      const result: ArchiveBotCheckInResult = await ArchiveBotService.requestCheckIn(this.downloadSettings)
      this.archiveBotCheckInStatus = result.message.length > 0 && result.reward <= 0
        ? result.message
        : result.hasReward && result.hasBalance
        ? AppStrings.get('download_archive_bot_checkin_result')
          .replace('%s', `${result.reward}`)
          .replace('%s', `${result.gp}`)
        : result.message
      if (result.hasBalance && (result.gp > 0 || result.reward > 0)) {
        await DownloadSettings.setArchiveBotBalance(this.ctx(), result.gp)
      }
      DiagnosticLogger.info('download', 'archive_bot_checkin_done', `reward=${result.reward} gp=${result.gp}`)
    } catch (error) {
      this.archiveBotCheckInStatus = (error as Error).message
      DiagnosticLogger.warn('download', 'archive_bot_checkin_failed', (error as Error).message)
    }
    this.archiveBotCheckInBusy = false
  }

  private showToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {})
  }

  private async restoreDownloadTasks(): Promise<void> {
    if (this.downloadRestoreBusy) {
      return
    }
    this.downloadRestoreBusy = true
    DiagnosticLogger.info('download', 'download_directory_import_start', 'settings')
    try {
      const result: DownloadDirectoryImportResult =
        await DownloadQueueSettings.importTasksFromDownloadDirectory(this.ctx())
      const imported: number = result.galleryTasks + result.archiverTasks
      const scanned: number = result.scannedGalleryTasks + result.scannedArchiverTasks
      if (imported > 0) {
        this.showToast(AppStrings.get('download_restore_tasks_done').replace('%s', `${imported}`))
      } else if (scanned > 0) {
        this.showToast($r('app.string.download_restore_tasks_existing'))
      } else {
        this.showToast($r('app.string.download_restore_tasks_none'))
      }
    } catch (error) {
      DiagnosticLogger.warn('download', 'download_directory_import_failed', (error as Error).message)
      this.showToast($r('app.string.download_restore_tasks_failed'))
    }
    this.downloadRestoreBusy = false
  }

  private adjustConcurrency(delta: number): void {
    DownloadSettings.setConcurrency(this.ctx(), this.downloadSettings.concurrency + delta)
  }

  private adjustRequestInterval(delta: number): void {
    DownloadSettings.setRequestIntervalSeconds(this.ctx(), this.downloadSettings.requestIntervalSeconds + delta)
  }

  private adjustRetryCount(delta: number): void {
    DownloadSettings.setRetryCount(this.ctx(), this.downloadSettings.retryCount + delta)
  }

  private setAutoRetryFailed(enabled: boolean): void {
    DownloadSettings.setAutoRetryFailed(this.ctx(), enabled)
  }

  private speedLimitLabel(): string {
    return this.downloadSettings.speedLimitKbps > 0 ? `${this.downloadSettings.speedLimitKbps}K` :
    AppStrings.get('common_off')
  }

  private adjustSpeedLimit(delta: number): void {
    DownloadSettings.setSpeedLimitKbps(
      this.ctx(),
      this.downloadSettings.speedLimitKbps + delta * DownloadSettings.speedLimitStepKbps(),
    )
  }

  @Builder
  OriginalModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.common_off'),
        symbolEndIcon: this.downloadSettings.originalMode === DownloadOriginalMode.OFF
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setOriginalMode(DownloadOriginalMode.OFF)
        this.originalMenuShown = false
      })
      MenuItem({
        content: $r('app.string.download_original_ask'),
        symbolEndIcon: this.downloadSettings.originalMode === DownloadOriginalMode.ASK
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setOriginalMode(DownloadOriginalMode.ASK)
        this.originalMenuShown = false
      })
      MenuItem({
        content: $r('app.string.download_original_always'),
        symbolEndIcon: this.downloadSettings.originalMode === DownloadOriginalMode.ALWAYS
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setOriginalMode(DownloadOriginalMode.ALWAYS)
        this.originalMenuShown = false
      })
    }
  }

  @Builder
  ArchiveBotTypeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.download_archive_bot_eh_ar_bot'),
        symbolEndIcon: this.downloadSettings.archiveBotType === ArchiveBotType.EH_AR_BOT
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setArchiveBotType(ArchiveBotType.EH_AR_BOT)
        this.archiveBotMenuShown = false
      })
      MenuItem({
        content: $r('app.string.download_archive_bot_archive_at_home'),
        symbolEndIcon: this.downloadSettings.archiveBotType === ArchiveBotType.ARCHIVE_AT_HOME
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setArchiveBotType(ArchiveBotType.ARCHIVE_AT_HOME)
        this.archiveBotMenuShown = false
      })
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private TextInputRow(label: ResourceStr, placeholder: ResourceStr, secret: boolean, field: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(label)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (field === 'address') {
        TextInput({ text: $$this.archiveBotAddressDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .onChange(() => {
            this.saveArchiveBotAddress()
          })
      } else {
        TextInput({ text: $$this.archiveBotApiKeyDraft, placeholder: placeholder })
          .type(secret ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(48)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .onChange(() => {
            this.saveArchiveBotApiKey()
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
  private BusySuffix() {
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
          Column() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.download_concurrency'),
                subtitle: $r('app.string.download_concurrency_hint'),
                leadingIcon: $r('sys.symbol.arrow_down_to_line'),
                hasCounter: true,
                counterValue: `${this.downloadSettings.concurrency}`,
                counterDecreaseEnabled:
                  this.downloadSettings.concurrency > DownloadSettings.minConcurrency(),
                counterIncreaseEnabled:
                  this.downloadSettings.concurrency < DownloadSettings.maxConcurrency(),
                showChevron: false,
                counterDecreaseAction: () => {
                  this.adjustConcurrency(-1)
                },
                counterIncreaseAction: () => {
                  this.adjustConcurrency(1)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.download_request_interval'),
                subtitle: $r('app.string.download_request_interval_hint'),
                leadingIcon: $r('sys.symbol.clock'),
                hasCounter: true,
                counterValue: `${this.downloadSettings.requestIntervalSeconds}`,
                counterDecreaseEnabled:
                  this.downloadSettings.requestIntervalSeconds > DownloadSettings.minRequestIntervalSeconds(),
                counterIncreaseEnabled:
                  this.downloadSettings.requestIntervalSeconds < DownloadSettings.maxRequestIntervalSeconds(),
                showChevron: false,
                counterDecreaseAction: () => {
                  this.adjustRequestInterval(-1)
                },
                counterIncreaseAction: () => {
                  this.adjustRequestInterval(1)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.download_retry_count'),
                subtitle: $r('app.string.download_retry_count_hint'),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                hasCounter: true,
                counterValue: `${this.downloadSettings.retryCount}`,
                counterDecreaseEnabled:
                  this.downloadSettings.retryCount > DownloadSettings.minRetryCount(),
                counterIncreaseEnabled:
                  this.downloadSettings.retryCount < DownloadSettings.maxRetryCount(),
                showChevron: false,
                counterDecreaseAction: () => {
                  this.adjustRetryCount(-1)
                },
                counterIncreaseAction: () => {
                  this.adjustRetryCount(1)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.download_auto_retry_failed'),
                subtitle: $r('app.string.download_auto_retry_failed_hint'),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                hasSwitch: true,
                checked: this.downloadSettings.autoRetryFailed,
                showChevron: false,
                switchAction: (value: boolean) => {
                  this.setAutoRetryFailed(value)
                },
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.download_speed_limit'),
                subtitle: $r('app.string.download_speed_limit_hint'),
                leadingIcon: $r('sys.symbol.clock'),
                hasCounter: true,
                counterValue: this.speedLimitLabel(),
                counterDecreaseEnabled:
                  this.downloadSettings.speedLimitKbps > DownloadSettings.minSpeedLimitKbps(),
                counterIncreaseEnabled:
                  this.downloadSettings.speedLimitKbps < DownloadSettings.maxSpeedLimitKbps(),
                showChevron: false,
                counterDecreaseAction: () => {
                  this.adjustSpeedLimit(-1)
                },
                counterIncreaseAction: () => {
                  this.adjustSpeedLimit(1)
                },
              })
              this.rowDivider()
              Column() {
                ConciseListRow({
                  title: $r('app.string.download_original_images'),
                  subtitle: $r('app.string.download_original_hint'),
                  leadingIcon: $r('sys.symbol.picture'),
                  trailingText: this.originalModeLabel(),
                  trailingDropdown: true,
                  action: () => {
                    this.originalMenuShown = true
                  },
                })
              }
              .bindMenu(this.originalMenuShown, this.OriginalModeMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.originalMenuShown = false
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            if (this.downloadRestoreBusy) {
              ConciseListRow({
                title: $r('app.string.download_restore_tasks'),
                subtitle: $r('app.string.download_restore_tasks_scanning'),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                isEnabled: false,
                suffixBuilderParam: () => {
                  this.BusySuffix()
                },
              })
            } else {
              ConciseListRow({
                title: $r('app.string.download_restore_tasks'),
                subtitle: $r('app.string.download_restore_tasks_hint'),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                action: () => {
                  this.restoreDownloadTasks()
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            Column() {
              ConciseListRow({
                title: $r('app.string.download_archive_bot_protocol'),
                subtitle: $r('app.string.download_archive_bot_hint'),
                leadingIcon: $r('sys.symbol.externaldrive'),
                trailingText: this.archiveBotTypeLabel(),
                trailingDropdown: true,
                action: () => {
                  this.archiveBotMenuShown = true
                },
              })
            }
            .bindMenu(this.archiveBotMenuShown, this.ArchiveBotTypeMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.archiveBotMenuShown = false
              },
            })
            this.rowDivider()
            this.TextInputRow(
              $r('app.string.download_archive_bot_address'),
              $r('app.string.download_archive_bot_address_hint'),
              false,
              'address',
            )
            this.rowDivider()
            this.TextInputRow(
              $r('app.string.download_archive_bot_api_key'),
              $r('app.string.download_archive_bot_api_key_hint'),
              true,
              'apiKey',
            )
            this.rowDivider()
            if (this.archiveBotBalanceBusy) {
              ConciseListRow({
                title: $r('app.string.download_archive_bot_balance'),
                subtitle: this.balanceSubtitle(),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                isEnabled: false,
                suffixBuilderParam: () => {
                  this.BusySuffix()
                },
              })
            } else {
              ConciseListRow({
                title: $r('app.string.download_archive_bot_balance'),
                subtitle: this.balanceSubtitle(),
                leadingIcon: $r('sys.symbol.arrow_clockwise'),
                showChevron: false,
                isEnabled: this.canCheckArchiveBotBalance(),
                action: () => {
                  this.checkArchiveBotBalance()
                },
              })
            }
            this.rowDivider()
            if (this.archiveBotCheckInBusy) {
              ConciseListRow({
                title: $r('app.string.download_archive_bot_checkin'),
                subtitle: this.checkInSubtitle(),
                leadingIcon: $r('sys.symbol.checkmark'),
                showChevron: false,
                isEnabled: false,
                suffixBuilderParam: () => {
                  this.BusySuffix()
                },
              })
            } else {
              ConciseListRow({
                title: $r('app.string.download_archive_bot_checkin'),
                subtitle: this.checkInSubtitle(),
                leadingIcon: $r('sys.symbol.checkmark'),
                showChevron: false,
                isEnabled: this.canCheckInArchiveBot(),
                action: () => {
                  this.checkInArchiveBot()
                },
              })
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_download')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
