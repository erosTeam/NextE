import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ImmersiveMaterialSettings } from '../settings/ImmersiveMaterialSettings'

/**
 * Resolves API 26 native uiMaterial for app surfaces.
 * Native materials intentionally use semantic automatic grades; the user level setting only controls HDS material.
 */
export class AppPrompt {
  /**
   * OpenHarmony 7.0.0.105 reports API 26 uiMaterial as supported and enabled, but renders both MenuOptions
   * and ordinary component systemMaterial as a fully transparent layer. Limit the readable blur fallback to
   * that confirmed platform build so later fixed API 26 releases continue to use native immersive material.
   */
  static systemMaterialRenderingBroken(): boolean {
    return deviceInfo.osFullName === 'OpenHarmony-7.0.0.105'
  }

  static systemMaterialSupported(): boolean {
    return deviceInfo.apiAvailable('26.0.0')
  }

  static searchSystemMaterial(): uiMaterial.Material | undefined {
    if (!AppPrompt.systemMaterialSupported()) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.ULTRA_THIN,
      true,
    )
  }

  static surfaceSystemMaterial(): uiMaterial.Material | undefined {
    if (!AppPrompt.systemMaterialSupported()) {
      return undefined
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
    })
  }

  static modalSystemMaterial(): uiMaterial.Material | undefined {
    if (!AppPrompt.systemMaterialSupported()) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.ULTRA_THICK,
      false,
    )
  }

  /**
   * Floating multiline composers need a readable material while retaining native light feedback.
   * Keep this on the semantic automatic grade; the user material level only controls HDS surfaces.
   */
  static composerSystemMaterial(): uiMaterial.Material | undefined {
    if (!AppPrompt.systemMaterialSupported()) {
      return undefined
    }
    return ImmersiveMaterialSettings.systemMaterial(
      ImmersiveMaterialSettings.LEVEL_ADAPTIVE,
      uiMaterial.ImmersiveStyle.THICK,
      true,
    )
  }

  /**
   * Sheet content must not paint over the API 26 system material owned by bindSheet.
   * Keep the caller's solid color as the pre-26 fallback.
   */
  static modalContentBackgroundColor(fallback: ResourceColor): ResourceColor {
    if (!AppPrompt.systemMaterialSupported()) {
      return fallback
    }
    return Color.Transparent
  }
}
