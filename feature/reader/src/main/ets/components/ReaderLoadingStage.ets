import { ThemeConstants, ReaderBackgroundMode, ReadModeState, ThemeDisplayState, connectReadMode, connectThemeDisplay } from 'shared'
import { ReaderLoadingStage as SharedReaderLoadingStage } from '@reader-kit/ui'

export function readerBackgroundIsDark(mode: string, effectiveDark: boolean): boolean {
  if (mode === ReaderBackgroundMode.WHITE) {
    return false
  }
  if (mode === ReaderBackgroundMode.AUTO) {
    return effectiveDark
  }
  return true
}

export function readerForegroundColor(mode: string, effectiveDark: boolean): ResourceColor {
  return readerBackgroundIsDark(mode, effectiveDark)
    ? ThemeConstants.READER_FOREGROUND_LIGHT
    : ThemeConstants.READER_FOREGROUND_DARK
}

@ComponentV2
export struct ReaderLoadingStage {
  @Param label: ResourceStr = ''
  @Param compact: boolean = false
  @Param loaded: number = 0
  @Param total: number = 0
  @Param showTransitionBackground: boolean = false
  @Local readMode: ReadModeState = connectReadMode()
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay()

  build() {
    SharedReaderLoadingStage({
      label: this.label, compact: this.compact, loaded: this.loaded, total: this.total,
      showTransitionBackground: this.showTransitionBackground,
      foreground: readerForegroundColor(this.readMode.backgroundMode, this.themeDisplay.effectiveDark),
      track: readerBackgroundIsDark(this.readMode.backgroundMode, this.themeDisplay.effectiveDark) ? '#33FFFFFF' : '#33000000',
    })
  }
}
