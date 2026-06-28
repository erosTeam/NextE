import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  ConciseListRow,
  DownloadOriginalMode,
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
  private scroller: Scroller = new Scroller();

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

  private adjustConcurrency(delta: number): void {
    DownloadSettings.setConcurrency(this.ctx(), this.downloadSettings.concurrency + delta)
  }

  private adjustRequestInterval(delta: number): void {
    DownloadSettings.setRequestIntervalSeconds(this.ctx(), this.downloadSettings.requestIntervalSeconds + delta)
  }

  private adjustRetryCount(delta: number): void {
    DownloadSettings.setRetryCount(this.ctx(), this.downloadSettings.retryCount + delta)
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
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
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
                leadingIcon: $r('sys.symbol.arrow_down_to_line_circle_fill'),
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
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_download')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
