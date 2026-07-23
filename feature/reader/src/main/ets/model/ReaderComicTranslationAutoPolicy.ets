export class ReaderComicTranslationAutoPolicy {
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
