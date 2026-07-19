import { AppStrings, ThemeConstants } from 'shared'

export const HISTORY_PINNED_DAY_HEADER_HEIGHT: number =
  ThemeConstants.FONT_SIZE_BODY + ThemeConstants.SPACE_SM + ThemeConstants.SPACE_XS

const HISTORY_DAY_BEFORE_YESTERDAY: number = 2

/** Stable local calendar-day identity used by both regular and HDS-mirrored headers. */
export function historyLocalDayStart(time: number): number {
  const date: Date = new Date(time)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

/** Resolve the human-facing label at render time; never persist or group by this text. */
export function historyDayLabel(dayStart: number, currentDayStart: number): string {
  const dayDelta: number = Math.round((currentDayStart - dayStart) / 86400000)
  if (dayDelta === 0) {
    return AppStrings.get('history_today')
  }
  if (dayDelta === 1) {
    return AppStrings.get('history_yesterday')
  }
  if (dayDelta === HISTORY_DAY_BEFORE_YESTERDAY) {
    return AppStrings.get('history_day_before_yesterday')
  }
  const date: Date = new Date(dayStart)
  const month: string = `${date.getMonth() + 1}`.padStart(2, '0')
  const day: string = `${date.getDate()}`.padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

/** State owned by one history destination and rendered by its cached HDS bottomBuilder content. */
@ObservedV2
export class HistoryPinnedDayHeaderState {
  @Trace dayStart: number = 0
  @Trace currentDayStart: number = historyLocalDayStart(Date.now())
  @Trace visible: boolean = false
  // Window coordinate of the pinned row's upper edge. The ordinary ListItemGroup header must
  // actually move behind this edge before its HDS mirror is allowed to appear.
  @Trace pinSurfaceTopY: number = -1
}

/**
 * Passive date-context mirror for the HDS title-bar bottom slot.
 * It uses the same caption and horizontal inset as the ListItemGroup header it mirrors.
 */
@ComponentV2
export struct HistoryPinnedDayHeader {
  @Param state: HistoryPinnedDayHeaderState = new HistoryPinnedDayHeaderState()

  build() {
    Column() {
      if (this.state.visible) {
        Row() {
          Text(historyDayLabel(this.state.dayStart, this.state.currentDayStart))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeConstants.BRAND_PRIMARY)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: ThemeConstants.SPACE_MD + ThemeConstants.SPACE_SM,
          right: ThemeConstants.SPACE_MD + ThemeConstants.SPACE_SM,
        })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(HISTORY_PINNED_DAY_HEADER_HEIGHT)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.state.pinSurfaceTopY = newValue.globalPosition.y as number
    })
  }
}

@Builder
export function HistoryPinnedDayHeaderCCBuilder(state: HistoryPinnedDayHeaderState) {
  HistoryPinnedDayHeader({ state: state })
}
