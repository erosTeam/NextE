import { AppStorageV2 } from '@kit.ArkUI'

/**
 * One-shot intent channel for a tap on a pinned shared SubTabBar. The bar lives in the HDS title-bar
 * tree while its RetainedSubtabHost lives in the page tree, so this carries only the requested target;
 * it never becomes the selected/persisted key. The host starts the native Swiper animation from this
 * request, then publishes its settled key through the existing surface-owned selection writer.
 */
@ObservedV2
export class SubtabTransitionState {
  @Trace scope: string = ''
  @Trace targetKey: string = ''
  // A repeated tap on a target remains a distinct UI request, even when the key text is unchanged.
  @Trace requestSeq: number = 0
}

export const SUBTAB_TRANSITION_SCOPE_HOME: string = 'home'
export const SUBTAB_TRANSITION_SCOPE_TOPLIST: string = 'toplist'
export const SUBTAB_TRANSITION_SCOPE_FAVORITES: string = 'favorites'

const SUBTAB_TRANSITION_V2_KEY: string = 'v2_subtabTransition'

export function connectSubtabTransition(): SubtabTransitionState {
  return AppStorageV2.connect(
    SubtabTransitionState,
    SUBTAB_TRANSITION_V2_KEY,
    () => new SubtabTransitionState(),
  )!
}

/** Single writer for a click-driven shared-subtab transition request. */
export class SubtabTransitionBridge {
  static request(scope: string, targetKey: string): void {
    const state: SubtabTransitionState = connectSubtabTransition()
    state.scope = scope
    state.targetKey = targetKey
    state.requestSeq = state.requestSeq + 1
  }
}
