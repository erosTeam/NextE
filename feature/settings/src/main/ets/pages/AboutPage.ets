import { HdsNavDestination } from '@kit.UIDesignKit'
import { bundleManager, common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
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

@ComponentV2
export struct AboutPage {
  @Local appVersion: string = ''
  @Local safeMode: SafeModeState = connectSafeMode();
  @Local safeModeTapCount: number = 0;
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
    return '1.1.2'
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
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
