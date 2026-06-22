import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectActionAlignment, ActionAlignmentState } from '../state/ActionAlignmentState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export type ActionAlignmentMode = 'smartGrip' | 'followOperation' | 'fixedLeft' | 'fixedRight' | ''

export interface ActionAlignmentOption {
  label: ResourceStr
  mode: ActionAlignmentMode
}

/**
 * Floating Read-button alignment mode (ported from V2Next ReplyActionAlignmentSettings — "智感握姿").
 * Holds the mode constants + resolution helpers (normalize / default / effective / options) and is the
 * single writer of ActionAlignmentState.alignmentMode. Persistence mirrors ListModeSettings (direct
 * preferences), not V2Next's descriptor framework. MotionHandStateService consumes the resolved mode and
 * writes ActionHandEdgeState; this class stays free of that dependency (no import cycle).
 */
export class ActionAlignmentSettings {
  static readonly MODE_UNSET: ActionAlignmentMode = ''
  static readonly MODE_SMART_GRIP: ActionAlignmentMode = 'smartGrip'
  static readonly MODE_FOLLOW_OPERATION: ActionAlignmentMode = 'followOperation'
  static readonly MODE_FIXED_LEFT: ActionAlignmentMode = 'fixedLeft'
  static readonly MODE_FIXED_RIGHT: ActionAlignmentMode = 'fixedRight'

  static normalizeMode(mode: string): ActionAlignmentMode {
    const value: string = (mode || '').trim()
    if (
      value === ActionAlignmentSettings.MODE_SMART_GRIP ||
      value === ActionAlignmentSettings.MODE_FOLLOW_OPERATION ||
      value === ActionAlignmentSettings.MODE_FIXED_LEFT ||
      value === ActionAlignmentSettings.MODE_FIXED_RIGHT
    ) {
      return value as ActionAlignmentMode
    }
    return ActionAlignmentSettings.MODE_UNSET
  }

  // When unset, default to smartGrip on grip-capable devices (it auto-follows the holding hand), else
  // followOperation (infers the side from where the user taps) — mirrors V2Next defaultMode.
  static defaultMode(smartGripSupported: boolean): ActionAlignmentMode {
    return smartGripSupported
      ? ActionAlignmentSettings.MODE_SMART_GRIP
      : ActionAlignmentSettings.MODE_FOLLOW_OPERATION
  }

  // The mode actually in force: unset → default; smartGrip on an unsupported device → followOperation.
  static effectiveMode(mode: string, smartGripSupported: boolean): ActionAlignmentMode {
    const normalized: ActionAlignmentMode = ActionAlignmentSettings.normalizeMode(mode)
    if (normalized === ActionAlignmentSettings.MODE_UNSET) {
      return ActionAlignmentSettings.defaultMode(smartGripSupported)
    }
    if (normalized === ActionAlignmentSettings.MODE_SMART_GRIP && !smartGripSupported) {
      return ActionAlignmentSettings.MODE_FOLLOW_OPERATION
    }
    return normalized
  }

  static availableOptions(smartGripSupported: boolean): ActionAlignmentOption[] {
    const options: ActionAlignmentOption[] = []
    if (smartGripSupported) {
      options.push({
        label: $r('app.string.smart_grip'),
        mode: ActionAlignmentSettings.MODE_SMART_GRIP,
      })
    }
    options.push({
      label: $r('app.string.follow_operation'),
      mode: ActionAlignmentSettings.MODE_FOLLOW_OPERATION,
    })
    options.push({
      label: $r('app.string.fixed_left'),
      mode: ActionAlignmentSettings.MODE_FIXED_LEFT,
    })
    options.push({
      label: $r('app.string.fixed_right'),
      mode: ActionAlignmentSettings.MODE_FIXED_RIGHT,
    })
    return options
  }

  static modeLabel(mode: string, smartGripSupported: boolean): ResourceStr {
    const effective: ActionAlignmentMode = ActionAlignmentSettings.effectiveMode(
      mode,
      smartGripSupported,
    )
    if (effective === ActionAlignmentSettings.MODE_SMART_GRIP) {
      return $r('app.string.smart_grip')
    }
    if (effective === ActionAlignmentSettings.MODE_FIXED_LEFT) {
      return $r('app.string.fixed_left')
    }
    if (effective === ActionAlignmentSettings.MODE_FIXED_RIGHT) {
      return $r('app.string.fixed_right')
    }
    return $r('app.string.follow_operation')
  }

  // Seed the runtime state mirror (used by restore); does NOT persist.
  static apply(mode: string): void {
    connectActionAlignment().alignmentMode = ActionAlignmentSettings.normalizeMode(mode)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const mode: string = store.getSync(StorageKeys.ACTION_ALIGNMENT_MODE, '') as string
      ActionAlignmentSettings.apply(mode)
    } catch (error) {
      DiagnosticLogger.warn('settings', 'action_alignment_restore_failed', (error as Error).message)
    }
  }

  static async save(context: common.UIAbilityContext, mode: string): Promise<void> {
    const normalized: ActionAlignmentMode = ActionAlignmentSettings.normalizeMode(mode)
    connectActionAlignment().alignmentMode = normalized
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.ACTION_ALIGNMENT_MODE, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'action_alignment_save_failed', (error as Error).message)
    }
  }
}
