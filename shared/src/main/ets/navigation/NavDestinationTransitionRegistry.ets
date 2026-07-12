/**
 * Bridges one root Navigation transition to the destination that owns the visual state.
 *
 * ArkUI gives the transition proxy only to Navigation, while the destination owns the
 * opacity/translation properties that must change. Entries are keyed by the framework's
 * navDestinationId and removed when that destination disappears.
 */
export interface NavDestinationTransitionCallbacks {
  prepare: () => void
  play: () => void
  reset: () => void
}

export class NavDestinationTransitionRegistry {
  private static callbacks: Map<string, NavDestinationTransitionCallbacks> =
    new Map<string, NavDestinationTransitionCallbacks>()

  static register(id: string, callbacks: NavDestinationTransitionCallbacks): void {
    NavDestinationTransitionRegistry.callbacks.set(id, callbacks)
  }

  static unregister(id: string): void {
    NavDestinationTransitionRegistry.callbacks.delete(id)
  }

  static prepare(id: string): boolean {
    const callbacks: NavDestinationTransitionCallbacks | undefined =
      NavDestinationTransitionRegistry.callbacks.get(id)
    if (callbacks === undefined) {
      return false
    }
    callbacks.prepare()
    return true
  }

  static play(id: string): void {
    const callbacks: NavDestinationTransitionCallbacks | undefined =
      NavDestinationTransitionRegistry.callbacks.get(id)
    if (callbacks !== undefined) {
      callbacks.play()
    }
  }

  static reset(id: string): void {
    const callbacks: NavDestinationTransitionCallbacks | undefined =
      NavDestinationTransitionRegistry.callbacks.get(id)
    if (callbacks !== undefined) {
      callbacks.reset()
    }
  }
}
