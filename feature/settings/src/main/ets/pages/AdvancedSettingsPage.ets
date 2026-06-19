import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'

/**
 * Advanced settings starts with the one maintenance capability NextE already owns: native hilog
 * diagnostics. FE has cache/proxy/import/export/log rows here; those remain future lanes.
 */
@ComponentV2
export struct AdvancedSettingsPage {
  private scroller: Scroller = new Scroller();

  private writeMarker(): void {
    DiagnosticLogger.info('diagnostics', 'manual_marker', `ts=${Date.now()}`)
    this.getUIContext().getPromptAction().showToast({
      message: $r('app.string.advanced_marker_written'),
    })
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
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.advanced_diagnostics'),
              subtitle: $r('app.string.advanced_diagnostics_hint'),
              leadingIcon: $r('sys.symbol.info_circle'),
              trailingText: 'HiLog',
              showChevron: false,
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.advanced_write_marker'),
              leadingIcon: $r('sys.symbol.gearshape'),
              showChevron: false,
              action: () => {
                this.writeMarker()
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_advanced')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
