import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  AutoLockTimeout,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  SettingsCheckedMenuItem,
  SecurityAuthResult,
  SecuritySettings,
  SecuritySettingsState,
  ThemeConstants,
  ListRowDivider,
  connectSecuritySettings,
  immersiveTitleBar,
} from 'shared'

/**
 * Security settings page grounded in eros_fe SecuritySettingPage.
 * Auto-lock enable/disable is confirmed through native HarmonyOS authentication before persistence.
 */
@ComponentV2
export struct SecuritySettingsPage {
  @Local securitySettings: SecuritySettingsState = connectSecuritySettings();
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
    SecuritySettings.setAutoLockSecondsWithBoundaryAuth(this.ctx(), seconds).then((result: SecurityAuthResult) => {
      if (result === SecurityAuthResult.UNAVAILABLE) {
        this.toast($r('app.string.security_auth_unavailable'))
      } else if (result !== SecurityAuthResult.SUCCESS) {
        this.toast($r('app.string.security_unlock_failed'))
      }
    })
  }

  private setRecentTasksProtection(value: boolean): void {
    SecuritySettings.setRecentTasksProtection(this.ctx(), value)
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  @Builder
  AutoLockMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(SecuritySettings.autoLockValues(), (seconds: number) => {
        SettingsCheckedMenuItem({
          label: this.autoLockLabel(seconds),
          selected: this.securitySettings.autoLockSeconds === seconds,
          selectAction: () => {
            select(() => {
              this.setAutoLock(seconds)
            })
          },
        })
      }, (seconds: number) => `${seconds}`)
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
          Column() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.security_recent_tasks_blur'),
                subtitle: $r('app.string.security_recent_tasks_blur_hint'),
                leadingIcon: $r('sys.symbol.eye_slash'),
                hasSwitch: true,
                checked: this.securitySettings.recentTasksProtectionEnabled,
                switchAction: (value: boolean) => {
                  this.setRecentTasksProtection(value)
                },
              })
              ListRowDivider()
              ConciseListRow({
                title: $r('app.string.security_auto_lock'),
                subtitle: $r('app.string.security_auto_lock_hint'),
                leadingIcon: $r('sys.symbol.lock'),
                trailingText: this.autoLockLabel(this.securitySettings.autoLockSeconds),
                trailingDropdown: true,
                dropdownMenuEnabled: true,
                dropdownMenuBuilder: (select: (action: () => void) => void) => {
                  this.AutoLockMenu(select)
                },
              })
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_security')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
