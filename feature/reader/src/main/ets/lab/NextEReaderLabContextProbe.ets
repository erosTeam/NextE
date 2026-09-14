import { AppStorageV2 } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

/** One-shot debug fixture handoff; no Context or preference value is retained. */
@ObservedV2
export class NextEReaderLabContextProbe {
  private epoch: number = 0
  private work: string = ''
  private receiver: ((context: common.UIAbilityContext) => void) | null = null
  private forcedImageBlockSourceIndex: number = -1

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
}

export function connectNextEReaderLabContextProbe(): NextEReaderLabContextProbe {
  return AppStorageV2.connect(NextEReaderLabContextProbe, () => new NextEReaderLabContextProbe())!
}
