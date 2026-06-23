import { BlurStrategy, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit'
import {
  ImmersiveMaterialSettings,
  ImmersiveMaterialEffect,
} from '../settings/ImmersiveMaterialSettings'
import { connectImmersiveMaterialSettings } from '../state/ImmersiveMaterialSettingsState'

/**
 * IMMERSIVE system material when the device supports it, else ADAPTIVE — so a device that lacks the
 * IMMERSIVE material degrades gracefully instead of requesting an unsupported type (V2Next gates the
 * same way via ImmersiveMaterialSettings.immersiveSupported() → getSystemMaterialTypes()). Used by
 * both the title bar and the floating tab bar. materialLevel stays ADAPTIVE in both branches.
 */
export function immersiveMaterialType(): hdsMaterial.MaterialType {
  try {
    const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
    for (let i = 0; i < types.length; i++) {
      if (types[i] === hdsMaterial.MaterialType.IMMERSIVE) {
        return hdsMaterial.MaterialType.IMMERSIVE
      }
    }
    return hdsMaterial.MaterialType.ADAPTIVE
  } catch (_e) {
    return hdsMaterial.MaterialType.ADAPTIVE
  }
}

/**
 * V2Next's immersive title-bar treatment (V2Next Index.ets:1377-1392 / navDestTitleBarOpts): a
 * GRADIENT_BLUR scroll effect + immersive system material on the title bar, so content scrolling
 * under the status bar / title bar is progressively blurred (a soft frosted gradient) instead of
 * showing through a plain transparent bar sharply. Supported with systemMaterialEffect since
 * 6.1.0(23). Pass the page's already-assembled title-bar `content` record (title / bottomBuilder /
 * menu / stackBuilderComponent); this wraps it with the shared style so EVERY title bar (tabs +
 * pushed destinations) renders the same immersive backdrop.
 */
export function immersiveTitleBarOpts(content: Record<string, Object>): Record<string, Object> {
  // Drive the title-bar material from the user's 沉浸光感材质 choice (falls back to ADAPTIVE on devices
  // without IMMERSIVE support, i.e. the previous behaviour).
  const eff: ImmersiveMaterialEffect = ImmersiveMaterialSettings.effect(
    connectImmersiveMaterialSettings().level,
  )
  const mat: Record<string, Object> = {
    'materialType': eff.materialType,
    'materialLevel': eff.materialLevel,
  }
  const scrollOpts: Record<string, Object> = {
    'enableScrollEffect': true,
    'scrollEffectType': ScrollEffectType.GRADIENT_BLUR,
  }
  const style: Record<string, Object> = {
    'systemMaterialEffect': mat,
    'scrollEffectOpts': scrollOpts,
  }
  return {
    'avoidLayoutSafeArea': true,
    'enableComponentSafeArea': false,
    'blurStrategy': BlurStrategy.ENABLE,
    'content': content,
    'style': style,
  }
}

/** Convenience for the common "just a centered title" pushed page (most NavDestinations). */
export function immersiveTitleBar(mainTitle: ResourceStr): Record<string, Object> {
  const title: Record<string, Object> = { 'mainTitle': mainTitle }
  const content: Record<string, Object> = { 'title': title }
  return immersiveTitleBarOpts(content)
}
