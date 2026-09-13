import { common } from '@kit.AbilityKit'
import { ReaderDisplayPolicy } from '@reader-kit/core'
import {
  connectReadMode,
  GalleryReadProgressSettings,
  ReadColumnMode,
  ReadMode,
  ReadModeSettings,
  ReadSpreadLayout,
} from 'shared'

/** Maps neutral reader-kit menu intents onto NextE-owned persistence. */
export class NextEReaderRuntimePreferences {
  static async applyLayout(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    const current = connectReadMode()
    let mode: string
    if (policy.layout === 'continuous') mode = ReadMode.VERTICAL
    else if (policy.layout === 'single' && policy.pagingAxis === 'vertical') mode = ReadMode.TOP_TO_BOTTOM
    else mode = policy.direction === 'rtl' ? ReadMode.RTL : ReadMode.LTR
    if (current.mode !== mode) await ReadModeSettings.setMode(context, mode)
    if (policy.layout === 'single' && policy.pagingAxis === 'horizontal' && current.doublePageEnabled) {
      await ReadModeSettings.setDoublePageEnabled(context, false)
    } else if (policy.layout === 'spread' && !current.doublePageEnabled) {
      await ReadModeSettings.setDoublePageEnabled(context, true)
    }
  }

  static async applyDirection(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    if (policy.layout === 'continuous' || policy.pagingAxis === 'vertical') return
    const mode = policy.direction === 'rtl' ? ReadMode.RTL : ReadMode.LTR
    if (connectReadMode().mode !== mode) await ReadModeSettings.setMode(context, mode)
  }

  static async applySpreadLayout(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    const layout = policy.spreadLayout === 'split' ? ReadSpreadLayout.SPLIT : ReadSpreadLayout.JOINED
    if (connectReadMode().spreadLayoutMode !== layout) {
      await ReadModeSettings.setSpreadLayoutMode(context, layout)
    }
  }

  static applyFirstPageAlone(context: common.UIAbilityContext, gid: string, policy: ReaderDisplayPolicy): void {
    GalleryReadProgressSettings.setColumnMode(
      context,
      gid,
      policy.firstPageAlone ? ReadColumnMode.EVEN_LEFT : ReadColumnMode.ODD_LEFT,
    )
  }

  static async applyCrop(
    context: common.UIAbilityContext,
    policy: ReaderDisplayPolicy,
    enabled: boolean,
  ): Promise<void> {
    const current = connectReadMode()
    if (policy.layout === 'continuous') {
      if (current.cropBordersContinuous !== enabled) {
        await ReadModeSettings.setCropBordersContinuous(context, enabled)
      }
    } else if (current.cropBordersPaged !== enabled) {
      await ReadModeSettings.setCropBordersPaged(context, enabled)
    }
  }
}
