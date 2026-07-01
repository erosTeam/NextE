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
 * Security settings page grounded in eros_fe SecuritySettingPage.
 * Mutations are confirmed through native HarmonyOS authentication before persistence.
 */
@ComponentV2
export struct SecuritySettingsPage {
  @Local securitySettings: SecuritySettingsState = connectSecuritySettings();
  @Local recentTasksProtectionChecked: boolean = connectSecuritySettings().recentTasksProtectionEnabled;
  @Local recentTasksProtectionBusy: boolean = false;
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
    this.autoLockMenuShown = false
    SecuritySettings.setAutoLockSecondsWithAuth(this.ctx(), seconds).then((ok: boolean) => {
      if (!ok) {
        this.toast($r('app.string.security_unlock_failed'))
      }
    })
  }

  private setRecentTasksProtection(value: boolean): void {
    const current: boolean = this.securitySettings.recentTasksProtectionEnabled
    this.recentTasksProtectionChecked = current
    if (this.recentTasksProtectionBusy || value === current) {
      return
    }
    this.recentTasksProtectionBusy = true
    SecuritySettings.setRecentTasksProtectionWithAuth(this.ctx(), value).then((ok: boolean) => {
      this.recentTasksProtectionChecked = this.securitySettings.recentTasksProtectionEnabled
      if (!ok) {
        this.toast($r('app.string.security_unlock_failed'))
      }
    }).finally(() => {
      this.recentTasksProtectionBusy = false
      this.recentTasksProtectionChecked = this.securitySettings.recentTasksProtectionEnabled
    })
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  @Monitor('securitySettings.recentTasksProtectionEnabled')
  private syncRecentTasksProtectionSwitch(): void {
    this.recentTasksProtectionChecked = this.securitySettings.recentTasksProtectionEnabled
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
                checked: this.recentTasksProtectionChecked,
                isEnabled: !this.recentTasksProtectionBusy,
                switchAction: (value: boolean) => {
                  this.setRecentTasksProtection(value)
                },
              })
              this.rowDivider()
              Column() {
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
              .bindMenu(this.autoLockMenuShown, this.AutoLockMenu, {
                placement: Placement.BottomRight,
                onDisappear: () => {
                  this.autoLockMenuShown = false
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
