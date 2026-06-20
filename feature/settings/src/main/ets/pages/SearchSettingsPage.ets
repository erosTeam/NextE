import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  SearchFilterSettings,
  SearchFilterState,
  SearchHistorySettings,
  SearchHistoryState,
  ThemeConstants,
  connectSearchFilter,
  connectSearchHistory,
  immersiveTitleBar,
} from 'shared'

/**
 * Search settings page grounded in eros_fe SearchSettingPage's Settings-tree placement, but scoped to
 * NextE's existing search data: persisted history and advanced filter profile management.
 */
@ComponentV2
export struct SearchSettingsPage {
  @Local history: SearchHistoryState = connectSearchHistory();
  @Local filter: SearchFilterState = connectSearchFilter();
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private historyCountText(): string {
    return `${this.history.items.length}`
  }

  private filterStateText(): Resource {
    return this.filter.isActive()
      ? $r('app.string.search_settings_filter_active')
      : $r('app.string.search_settings_filter_clean')
  }

  private async clearHistory(): Promise<void> {
    await SearchHistorySettings.clear(this.ctx())
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.search_history_clear_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.search_history_clear'),
        fontColor: Color.Red,
        action: () => {
          this.clearHistory()
        },
      },
    })
  }

  private async resetFilters(): Promise<void> {
    await SearchFilterSettings.reset(this.ctx())
  }

  private confirmResetFilters(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.search_settings_filter_reset_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.search_settings_filter_reset'),
        fontColor: Color.Red,
        action: () => {
          this.resetFilters()
        },
      },
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
              title: $r('app.string.search_settings_history_count'),
              subtitle: $r('app.string.search_settings_history_hint'),
              leadingIcon: $r('sys.symbol.clock'),
              trailingText: this.historyCountText(),
              showChevron: false,
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.search_history_clear'),
              leadingIcon: $r('sys.symbol.trash'),
              destructive: true,
              showChevron: false,
              action: () => {
                this.confirmClearHistory()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.search_settings_filter_profile'),
              subtitle: $r('app.string.search_settings_filter_hint'),
              leadingIcon: $r('sys.symbol.funnel'),
              trailingText: this.filterStateText(),
              showChevron: false,
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.search_settings_filter_reset'),
              leadingIcon: $r('sys.symbol.arrow_counterclockwise'),
              destructive: true,
              showChevron: false,
              action: () => {
                this.confirmResetFilters()
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_search')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
