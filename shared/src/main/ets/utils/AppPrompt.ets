import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ImmersiveMaterialSettings } from '../settings/ImmersiveMaterialSettings'

/**
 * Resolves API 26 native uiMaterial for app surfaces.
 * Native materials intentionally use semantic automatic grades; the user level setting only controls HDS material.
 */
export class AppPrompt {
  static searchSystemMaterial(): uiMaterial.Material | undefined {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.ULTRA_THIN,
      true,
    )
  }

  static surfaceSystemMaterial(): uiMaterial.Material | undefined {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.THICK,
      false,
    )
  }

  static modalSystemMaterial(): uiMaterial.Material | undefined {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.ULTRA_THICK,
      false,
    )
  }

  /**
   * Sheet content must not paint over the API 26 system material owned by bindSheet.
   * Keep the caller's solid color as the pre-26 fallback.
   */
  static modalContentBackgroundColor(fallback: ResourceColor): ResourceColor {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return fallback
    }
    return Color.Transparent
  }
}
