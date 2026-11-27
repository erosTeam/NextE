import { ReadMode } from '../state/ReadModeState'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export function readerModeLabel(mode: string): Resource {
  switch (mode) {
    case ReadMode.RTL:
      return $r('app.string.read_mode_rtl')
    case ReadMode.TOP_TO_BOTTOM:
      return $r('app.string.read_mode_ttb')
    case ReadMode.VERTICAL:
      return $r('app.string.read_mode_vertical')
    case ReadMode.HORIZONTAL_CONTINUOUS_LTR:
      return $r('app.string.read_mode_horizontal_continuous_ltr')
    case ReadMode.HORIZONTAL_CONTINUOUS_RTL:
      return $r('app.string.read_mode_horizontal_continuous_rtl')
    default:
      return $r('app.string.read_mode_ltr')
  }
}

export function readerModeSymbol(mode: string, verticalPagingSymbol: Resource): Resource {
  switch (mode) {
    case ReadMode.RTL:
      return $r('sys.symbol.arrow_left_and_square')
    case ReadMode.TOP_TO_BOTTOM:
      return verticalPagingSymbol
    case ReadMode.VERTICAL:
      return $r('sys.symbol.scroll_vertical')
    case ReadMode.HORIZONTAL_CONTINUOUS_LTR:
      return $r('sys.symbol.arrow_right_to_line')
    case ReadMode.HORIZONTAL_CONTINUOUS_RTL:
      return $r('sys.symbol.arrow_left_to_line')
    default:
      return $r('sys.symbol.arrow_right_and_square')
  }
}

export function showReaderEntryDirection(context: UIContext, mode: string): void {
  try {
    context.getPromptAction().showToast({ message: readerModeLabel(mode), duration: 1600 })
  } catch (error) {
    DiagnosticLogger.warn('reader', 'entry_direction_toast_failed', (error as Error).message)
  }
}
