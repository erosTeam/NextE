import { common } from '@kit.AbilityKit'
import { resourceManager } from '@kit.LocalizationKit'
import { connectLanguageState } from '../state/AppearanceState'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * App string accessor. The `shared` HAR carries NO localized resources — user-facing
 * strings live in `entry/` + `AppScope/` resource qualifiers (base + zh_CN + en_US +
 * ja_JP). This wrapper resolves a key off the entry context's resourceManager so shared
 * code (which has no $r('app.string.*') of its own) can still surface localized text.
 *
 * In-app LANGUAGE switch (LanguageSettings): an override ResourceManager pinned to the chosen locale
 * re-resolves strings WITHOUT a restart, and get() reads the LanguageState.effectiveLocale signal so any
 * computed label assembled in a build() repaints when the language changes (V2Next AppStrings pattern).
 */
export class AppStrings {
  private static context: common.UIAbilityContext | null = null
  private static overrideResMgr: resourceManager.ResourceManager | null = null

  static init(context: common.UIAbilityContext): void {
    AppStrings.context = context
  }

  /**
   * Pin (or clear) an override locale for immediate language switching. Empty locale = follow system
   * (drop the override). Returns the applied locale ('' when cleared).
   */
  static setOverrideLocale(locale: string): string {
    if (locale.length === 0 || !AppStrings.context) {
      AppStrings.overrideResMgr = null
      return locale
    }
    try {
      const config: resourceManager.Configuration =
        AppStrings.context.resourceManager.getOverrideConfiguration()
      config.locale = locale
      AppStrings.context.resourceManager.updateOverrideConfiguration(config)
      AppStrings.overrideResMgr =
        AppStrings.context.resourceManager.getOverrideResourceManager(config)
    } catch (error) {
      DiagnosticLogger.warn(
        'i18n',
        'override_locale_failed',
        `${locale}: ${(error as Error).message}`,
      )
      AppStrings.overrideResMgr = null
    }
    return locale
  }

  static get(name: string): string {
    // Read the locale signal so labels assembled in a build() repaint on a language switch. The compare is
    // always false (length >= 0); it exists only to register the @Trace dependency.
    const observed: string = connectLanguageState().effectiveLocale
    if (observed.length < 0) {
      return name
    }
    const mgr: resourceManager.ResourceManager | undefined =
      AppStrings.overrideResMgr ?? AppStrings.context?.resourceManager
    if (!mgr) {
      return name
    }
    try {
      return mgr.getStringByNameSync(name)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('i18n', 'string_lookup_failed', `${name}: ${e.message}`)
      return name
    }
  }
}
