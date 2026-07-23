export class ReaderComicTranslationAutoPolicy {
  static warmLookahead(configuredPreloadPages: number, autoEnabled: boolean): number {
    if (!autoEnabled) {
      return configuredPreloadPages
    }
    return Math.max(1, configuredPreloadPages)
  }

  static selectTarget(
    currentIndex: number,
    currentNeedsWork: boolean,
    currentSettled: boolean,
    nextNeedsWork: boolean,
  ): number {
    if (currentIndex < 0) {
      return -1
    }
    if (currentNeedsWork) {
      return currentIndex
    }
    if (!currentSettled || !nextNeedsWork) {
      return -1
    }
    return currentIndex + 1
  }
}
