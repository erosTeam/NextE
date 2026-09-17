import { AppStorageV2 } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { ReaderCancellation } from '@reader-kit/core'

/** Debug-test seam for a local translated file; never calls or replaces a configured production service. */
@ObservedV2
export class NextEReaderTranslationProbe {
  private epoch: number = 0
  private work: string = ''
  private localPath: string = ''
  private receiver: ((sourceIndex: number, stage: string, identity: string) => void) | null = null
  private action: ((id: string) => boolean) | null = null
  private unavailableSources: number[] = []
  private pausedSource: number = -1
  private pausedEpoch: number = 0
  private releasePause: (() => void) | null = null

  arm(work: string, localPath: string,
    receiver: (sourceIndex: number, stage: string, identity: string) => void,
    pausedSource: number = -1): number {
    this.releaseCurrentPause()
    this.epoch += 1
    this.work = work
    this.localPath = localPath
    this.receiver = receiver
    this.action = null
    this.unavailableSources = []
    this.pausedSource = pausedSource
    return this.epoch
  }

  /** One-shot Debug-only gate used to prove navigation retires an in-flight translation owner. */
  async pauseBeforeResult(context: common.UIAbilityContext, work: string, sourceIndex: number,
    cancellation: ReaderCancellation): Promise<void> {
    if (!context.applicationInfo.debug || this.work !== work || this.pausedSource !== sourceIndex) return
    const epoch = this.epoch
    this.pausedSource = -1
    this.pausedEpoch = epoch
    await new Promise<void>((resolve): void => {
      let settled: boolean = false
      let detach: () => void = (): void => {}
      const finish = (): void => {
        if (settled) return
        settled = true
        detach()
        if (this.pausedEpoch === epoch) {
          this.pausedEpoch = 0
          this.releasePause = null
        }
        resolve()
      }
      detach = cancellation.onCancel(finish)
      this.releasePause = finish
    })
  }

  release(epoch: number): void {
    if (epoch !== this.epoch) return
    this.releaseCurrentPause()
  }

  setUnavailable(epoch: number, sourceIndex: number, unavailable: boolean): boolean {
    if (epoch !== this.epoch || !Number.isInteger(sourceIndex) || sourceIndex < 0) return false
    if (unavailable && !this.unavailableSources.includes(sourceIndex)) {
      this.unavailableSources = this.unavailableSources.concat([sourceIndex])
    } else if (!unavailable) {
      this.unavailableSources = this.unavailableSources.filter((value: number): boolean => value !== sourceIndex)
    }
    return true
  }

  unavailable(context: common.UIAbilityContext, work: string, sourceIndex: number): boolean {
    return context.applicationInfo.debug && this.work === work && this.unavailableSources.includes(sourceIndex)
  }

  bindAction(context: common.UIAbilityContext, work: string, action: (id: string) => boolean): void {
    if (!context.applicationInfo.debug || this.work !== work) return
    this.action = action
  }

  invoke(epoch: number, id: string): boolean {
    if (epoch !== this.epoch || this.action === null) return false
    return this.action(id)
  }

  result(context: common.UIAbilityContext, work: string): string {
    if (!context.applicationInfo.debug || this.work !== work) return ''
    return this.localPath
  }

  deliver(context: common.UIAbilityContext, work: string, sourceIndex: number,
    stage: string, identity: string): void {
    if (!context.applicationInfo.debug || this.work !== work) return
    this.receiver?.(sourceIndex, stage, identity)
  }

  cancel(epoch: number): void {
    if (epoch !== this.epoch) return
    this.releaseCurrentPause()
    this.work = ''
    this.localPath = ''
    this.receiver = null
    this.action = null
    this.unavailableSources = []
    this.pausedSource = -1
  }

  private releaseCurrentPause(): void {
    const release = this.releasePause
    this.releasePause = null
    this.pausedEpoch = 0
    release?.()
  }
}

export function connectNextEReaderTranslationProbe(): NextEReaderTranslationProbe {
  return AppStorageV2.connect(NextEReaderTranslationProbe, () => new NextEReaderTranslationProbe())!
}
