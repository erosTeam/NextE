import { common } from '@kit.AbilityKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * App string accessor. The `shared` HAR carries NO localized resources — user-facing
 * strings live in `entry/` + `AppScope/` resource qualifiers (base + zh_CN + en_US +
 * ja_JP). This wrapper resolves a key off the entry context's resourceManager so shared
 * code (which has no $r('app.string.*') of its own) can still surface localized text.
 *
 * M0: thin sync wrapper. M1+ swaps in a LanguageState-aware override ResourceManager so
 * an in-app language switch re-resolves without restart (V2Next pattern).
 */
export class AppStrings {
  private static context: common.UIAbilityContext | null = null

  static init(context: common.UIAbilityContext): void {
    AppStrings.context = context
  }

  static get(name: string): string {
    const ctx = AppStrings.context
    if (!ctx) {
      return name
    }
    try {
      return ctx.resourceManager.getStringByNameSync(name)
    } catch (error) {
      const e = error as Error
      DiagnosticLogger.warn('i18n', 'string_lookup_failed', `${name}: ${e.message}`)
      return name
    }
  }
}
