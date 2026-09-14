import { AppStorageV2 } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

export class NextEReaderLabSourceFacts {
  kind: string = ''
  work: string = ''
  index: number = -1
  fileCount: number = 0
  seedCount: number = 0
  exactImagePage: boolean = false

  copy(): NextEReaderLabSourceFacts {
    const out = new NextEReaderLabSourceFacts()
    out.kind = this.kind; out.work = this.work; out.index = this.index
    out.fileCount = this.fileCount; out.seedCount = this.seedCount
    out.exactImagePage = this.exactImagePage
    return out
  }
}

/** One-shot debug fixture handoff; no Context or preference value is retained. */
@ObservedV2
export class NextEReaderLabContextProbe {
  private epoch: number = 0
  private work: string = ''
  private receiver: ((context: common.UIAbilityContext) => void) | null = null
  private forcedImageBlockSourceIndex: number = -1
  private sourceFacts: NextEReaderLabSourceFacts = new NextEReaderLabSourceFacts()

  arm(work: string, receiver: (context: common.UIAbilityContext) => void,
    forcedImageBlockSourceIndex: number = -1): number {
    this.epoch += 1
    this.work = work
    this.receiver = receiver
    this.forcedImageBlockSourceIndex = forcedImageBlockSourceIndex
    return this.epoch
  }

  deliver(work: string, context: common.UIAbilityContext): number {
    if (!context.applicationInfo.debug || this.work !== work) return -1
    const receiver = this.receiver
    const forcedImageBlockSourceIndex = this.forcedImageBlockSourceIndex
    this.receiver = null
    this.work = ''
    this.forcedImageBlockSourceIndex = -1
    receiver?.(context)
    return forcedImageBlockSourceIndex
  }

  cancel(epoch: number): void {
    if (epoch !== this.epoch) return
    this.receiver = null
    this.work = ''
    this.forcedImageBlockSourceIndex = -1
  }

  resetSource(work: string): void {
    this.sourceFacts = new NextEReaderLabSourceFacts()
    this.sourceFacts.work = work
  }

  reportSource(work: string, kind: string, index: number, fileCount: number, seedCount: number,
    exactImagePage: boolean): void {
    if (this.sourceFacts.work !== work) return
    this.sourceFacts.kind = kind; this.sourceFacts.index = index; this.sourceFacts.fileCount = fileCount
    this.sourceFacts.seedCount = seedCount; this.sourceFacts.exactImagePage = exactImagePage
  }

  readSource(work: string): NextEReaderLabSourceFacts {
    return this.sourceFacts.work === work ? this.sourceFacts.copy() : new NextEReaderLabSourceFacts()
  }
}

export function connectNextEReaderLabContextProbe(): NextEReaderLabContextProbe {
  return AppStorageV2.connect(NextEReaderLabContextProbe, () => new NextEReaderLabContextProbe())!
}
