import { AppStorageV2 } from '@kit.ArkUI'

/**
 * V2-safe holder for the app's single `NavPathStack` (pattern from V2Next).
 *
 * `stack` is never observed as reactive state — consumers use it purely as a method
 * target (pushPathByName / pop); `NavPathStack` self-manages the observation that
 * `Navigation(stack)` binds to. Sharing the one instance app-wide through AppStorageV2
 * lets any @ComponentV2 push routes without a V1 @Provide/@Consume tail.
 */
@ObservedV2
export class NavStackHolder {
  @Trace stack: NavPathStack = new NavPathStack()
}

const NAV_STACK_KEY: string = 'v2:navStack'

export function connectNavStack(): NavStackHolder {
  return AppStorageV2.connect(NavStackHolder, NAV_STACK_KEY, () => new NavStackHolder())!
}
