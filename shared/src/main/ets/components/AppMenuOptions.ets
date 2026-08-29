import { AppPrompt } from '../utils/AppPrompt'

export function appMenuOptions(options: MenuOptions): MenuOptions {
  if (AppPrompt.systemMaterialRenderingBroken()) {
    // OpenHarmony 7.0.0.105 system regression: app-owned bindMenu surfaces can use this readable
    // translucent fallback. HDS-owned title-bar overflow menus stay untouched and must be retested
    // after the next system update instead of being replaced by an application-owned menu.
    options.backgroundColor = Color.Transparent
    options.backgroundEffect = {
      radius: 28,
      saturation: 1.15,
      brightness: 1.0,
      color: $r('sys.color.comp_background_secondary'),
      adaptiveColor: AdaptiveColor.AVERAGE,
    }
    return options
  }
  options.systemMaterial = AppPrompt.surfaceSystemMaterial()
  return options
}
