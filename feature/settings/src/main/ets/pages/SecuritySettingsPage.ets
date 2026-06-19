import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  AutoLockTimeout,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  SecuritySettings,
  SecuritySettingsState,
  ThemeConstants,
  connectSecuritySettings,
  immersiveTitleBar,
} from 'shared'

/**
 * Security settings page grounded in eros_fe SecuritySettingPage. This lane exposes the Settings
 * route and persists the auto-lock preference foundation; real recent-task privacy and biometric
 * lock enforcement stay disabled until their HarmonyOS APIs/lifecycle are implemented and validated.
 */
@ComponentV2
export struct SecuritySettingsPage {
  @Local securitySettings: SecuritySettingsState = connectSecuritySettings();
  @Local autoLockMenuShown: boolean = false;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private autoLockLabel(seconds: number): ResourceStr {
    if (seconds === AutoLockTimeout.INSTANT) {
      return $r('app.string.security_auto_lock_instant')
    }
    if (seconds === AutoLockTimeout.SECONDS_30) {
      return $r('app.string.security_auto_lock_30s')
    }
    if (seconds === AutoLockTimeout.MINUTES_1) {
      return $r('app.string.security_auto_lock_1m')
    }
    if (seconds === AutoLockTimeout.MINUTES_5) {
      return $r('app.string.security_auto_lock_5m')
    }
    if (seconds === AutoLockTimeout.MINUTES_10) {
      return $r('app.string.security_auto_lock_10m')
    }
    if (seconds === AutoLockTimeout.MINUTES_30) {
      return $r('app.string.security_auto_lock_30m')
    }
    if (seconds === AutoLockTimeout.HOURS_1) {
      return $r('app.string.security_auto_lock_1h')
    }
    if (seconds === AutoLockTimeout.HOURS_5) {
      return $r('app.string.security_auto_lock_5h')
    }
    return $r('app.string.security_auto_lock_disabled')
  }

  private setAutoLock(seconds: number): void {
    SecuritySettings.setAutoLockSeconds(this.ctx(), seconds)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  AutoLockMenu() {
    Menu() {
      ForEach(SecuritySettings.autoLockValues(), (seconds: number) => {
        MenuItem({
          content: this.autoLockLabel(seconds),
          symbolEndIcon: this.securitySettings.autoLockSeconds === seconds
            ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
            : undefined,
        }).onClick(() => {
          this.setAutoLock(seconds)
          this.autoLockMenuShown = false
        })
      }, (seconds: number) => `${seconds}`)
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        ListItem() {
          Column() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.security_recent_tasks_blur'),
                subtitle: $r('app.string.security_recent_tasks_blur_hint'),
                leadingIcon: $r('sys.symbol.eye_slash'),
                hasSwitch: true,
                checked: false,
                isEnabled: false,
              })
              this.rowDivider()
              ConciseListRow({
                title: $r('app.string.security_auto_lock'),
                subtitle: $r('app.string.security_auto_lock_hint'),
                leadingIcon: $r('sys.symbol.lock'),
                trailingText: this.autoLockLabel(this.securitySettings.autoLockSeconds),
                trailingDropdown: true,
                action: () => {
                  this.autoLockMenuShown = true
                },
              })
            }
          }
          .bindMenu(this.autoLockMenuShown, this.AutoLockMenu, {
            placement: Placement.Bottom,
            onDisappear: () => {
              this.autoLockMenuShown = false
            },
          })
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_security')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
