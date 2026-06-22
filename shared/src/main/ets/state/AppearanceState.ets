import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive APP THEME signal (ThemeSettings is the single writer). `mode` is the user choice
 * (system/light/dark); `effectiveDark` is the resolved dark state — components hosted in a CACHED
 * ComponentContent (the sub-tab pills) read it so they repaint when the system flips dark/light, which
 * otherwise leaves their `$r('sys.color.*')` tokens stale because the cached subtree never rebuilds.
 */
@ObservedV2
export class ThemeDisplayState {
  @Trace mode: string = 'system'
  @Trace effectiveDark: boolean = false
}

const THEME_DISPLAY_KEY: string = 'v2:themeDisplay'

export function connectThemeDisplay(): ThemeDisplayState {
  return AppStorageV2.connect(ThemeDisplayState, THEME_DISPLAY_KEY, () => new ThemeDisplayState())!
}

/**
 * Reactive APP LANGUAGE signal (LanguageSettings is the single writer). `mode` is the user choice
 * (system / zh-Hans / en-US / ja-JP); `effectiveLocale` is the resolved locale. AppStrings.get() reads
 * `effectiveLocale` so computed string labels repaint on an in-app language switch without a restart.
 */
@ObservedV2
export class LanguageState {
  @Trace mode: string = 'system'
  @Trace effectiveLocale: string = ''
}

const LANGUAGE_KEY: string = 'v2:language'

export function connectLanguageState(): LanguageState {
  return AppStorageV2.connect(LanguageState, LANGUAGE_KEY, () => new LanguageState())!
}
