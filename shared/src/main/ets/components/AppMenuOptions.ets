import { AppPrompt } from '../utils/AppPrompt'

export function appMenuOptions(options: MenuOptions): MenuOptions {
  options.systemMaterial = AppPrompt.surfaceSystemMaterial()
  return options
}
