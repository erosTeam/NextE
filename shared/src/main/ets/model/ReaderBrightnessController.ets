import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { ReaderDisplaySettings, readerWindowBrightness } from './ReaderDisplaySettings'

/** One host owner for both reader backends. Coalesces slider writes; restores the exact entry value. */
export class ReaderBrightnessController {
  private currentWindow: window.Window | null = null
  private original: number = -1
  private applied: number | null = null
  private requested: number | null = null
  private running: Promise<void> | null = null
  private generation: number = 0
  private settledGeneration: number = 0
  private timer: number = -1

  update(context: common.UIAbilityContext, active: boolean, settings: ReaderDisplaySettings): void {
    this.requested = active && settings.brightnessEnabled ? readerWindowBrightness(settings) : null
    this.generation += 1
    // Match the reference's 100ms brightness sampling. Entry/restore are immediate;
    // only successive slider samples are coalesced (Window API discourages continuous writes).
    if (this.requested === null || this.currentWindow === null) {
      if (this.timer >= 0) clearTimeout(this.timer)
      this.timer = -1
      this.start(context)
    } else if (this.timer < 0) {
      this.timer = setTimeout((): void => { this.timer = -1; this.start(context) }, 100)
    }
  }

  private start(context: common.UIAbilityContext): void {
    if (this.running !== null) return
    this.running = this.drain(context).catch((): void => {
      this.settledGeneration = this.generation
      console.warn('[ReaderDisplay] window brightness write failed')
    }).finally((): void => {
      this.running = null
      if (this.settledGeneration !== this.generation && this.timer < 0) this.start(context)
    })
  }

  private async drain(context: common.UIAbilityContext): Promise<void> {
    while (true) {
      const desired = this.requested
      const generation = this.generation
      if (desired === null) {
        if (this.currentWindow !== null) {
          await this.currentWindow.setWindowBrightness(this.original)
          this.currentWindow = null
          this.applied = null
        }
      } else {
        if (this.currentWindow === null) {
          const target = await window.getLastWindow(context)
          if (this.requested === null) continue
          this.original = target.getWindowProperties().brightness
          this.currentWindow = target
        }
        if (desired !== this.applied) {
          await this.currentWindow.setWindowBrightness(desired)
          this.applied = desired
        }
      }
      if (generation === this.generation) { this.settledGeneration = generation; return }
    }
  }
}
