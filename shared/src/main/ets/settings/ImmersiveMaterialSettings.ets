import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { hdsMaterial } from '@kit.UIDesignKit'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectImmersiveMaterialSettings } from '../state/ImmersiveMaterialSettingsState'

// "沉浸光感材质" — ported from V2Next (shared/.../settings/ImmersiveMaterialSettings.ets). A 4-level choice:
// 自动 (ADAPTIVE) plus three IMMERSIVE grades, the latter only offered when the device's HDS supports the
// IMMERSIVE material type. effect() drives the title-bar / floating-tab-bar systemMaterialEffect. The
// uiMaterial.ImmersiveMaterial helper V2Next also exposes is omitted — NextE has no consumer for it.
const LEVEL_ADAPTIVE: string = 'adaptive'
const LEVEL_EXQUISITE: string = 'exquisite'
const LEVEL_GENTLE: string = 'gentle'
const LEVEL_SMOOTH: string = 'smooth'

export interface ImmersiveMaterialOption {
  label: ResourceStr
  value: string
}

export interface ImmersiveMaterialEffect {
  materialType: hdsMaterial.MaterialType
  materialLevel: hdsMaterial.MaterialLevel
}

export class ImmersiveMaterialSettings {
  static readonly LEVEL_ADAPTIVE: string = LEVEL_ADAPTIVE
  static readonly LEVEL_EXQUISITE: string = LEVEL_EXQUISITE
  static readonly LEVEL_GENTLE: string = LEVEL_GENTLE
  static readonly LEVEL_SMOOTH: string = LEVEL_SMOOTH
  static readonly DEFAULT_LEVEL: string = LEVEL_ADAPTIVE

  static options(): ImmersiveMaterialOption[] {
    const options: ImmersiveMaterialOption[] = [
      { label: $r('app.string.common_auto'), value: LEVEL_ADAPTIVE },
    ]
    if (ImmersiveMaterialSettings.immersiveSupported()) {
      options.push(
        { label: $r('app.string.immersive_material_exquisite'), value: LEVEL_EXQUISITE },
        { label: $r('app.string.immersive_material_gentle'), value: LEVEL_GENTLE },
        { label: $r('app.string.immersive_material_smooth'), value: LEVEL_SMOOTH },
      )
    }
    return options
  }

  static immersiveSupported(): boolean {
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
      for (let i = 0; i < types.length; i++) {
        if (types[i] === hdsMaterial.MaterialType.IMMERSIVE) {
          return true
        }
      }
      return false
    } catch (_error) {
      return true
    }
  }

  static apply(level: string): void {
    connectImmersiveMaterialSettings().level = ImmersiveMaterialSettings.normalizeLevel(level)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const level: string = store.getSync(
        StorageKeys.IMMERSIVE_MATERIAL_LEVEL,
        LEVEL_ADAPTIVE,
      ) as string
      ImmersiveMaterialSettings.apply(level)
    } catch (error) {
      DiagnosticLogger.warn(
        'settings',
        'immersive_material_restore_failed',
        (error as Error).message,
      )
    }
  }

  static async setLevel(context: common.UIAbilityContext, level: string): Promise<void> {
    const normalized: string = ImmersiveMaterialSettings.normalizeLevel(level)
    ImmersiveMaterialSettings.apply(normalized)
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      store.putSync(StorageKeys.IMMERSIVE_MATERIAL_LEVEL, normalized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'immersive_material_save_failed', (error as Error).message)
    }
  }

  static normalizeLevel(level: string): string {
    const value: string = (level || '').trim()
    if (value === LEVEL_EXQUISITE || value === LEVEL_GENTLE || value === LEVEL_SMOOTH) {
      return value
    }
    return LEVEL_ADAPTIVE
  }

  static label(level: string): ResourceStr {
    const normalized: string = ImmersiveMaterialSettings.normalizeLevel(level)
    if (normalized === LEVEL_EXQUISITE) {
      return $r('app.string.immersive_material_exquisite')
    }
    if (normalized === LEVEL_GENTLE) {
      return $r('app.string.immersive_material_gentle')
    }
    if (normalized === LEVEL_SMOOTH) {
      return $r('app.string.immersive_material_smooth')
    }
    return $r('app.string.common_auto')
  }

  static effect(level: string): ImmersiveMaterialEffect {
    const normalized: string = ImmersiveMaterialSettings.normalizeLevel(level)
    if (!ImmersiveMaterialSettings.immersiveSupported()) {
      return {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
      }
    }
    if (normalized === LEVEL_EXQUISITE) {
      return {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE,
      }
    }
    if (normalized === LEVEL_GENTLE) {
      return {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.GENTLE,
      }
    }
    if (normalized === LEVEL_SMOOTH) {
      return {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.SMOOTH,
      }
    }
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
    }
  }
}
