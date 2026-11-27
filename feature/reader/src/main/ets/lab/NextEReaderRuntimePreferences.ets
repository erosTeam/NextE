import { common } from '@kit.AbilityKit'
import { ReaderDisplayPolicy } from '@reader-kit/core'
import {
  connectReadMode,
  GalleryReadProgressSettings,
  ReadColumnMode,
  ReadModeSettings,
  ReadSpreadLayout,
} from 'shared'
import { NextEReaderInitialPolicy } from './NextEReaderInitialPolicy'

/** Maps neutral reader-kit menu intents onto NextE-owned persistence. */
export class NextEReaderRuntimePreferences {
  static async applyLayout(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    const current = connectReadMode()
    await NextEReaderRuntimePreferences.applyReadingMode(context, policy)
    if (policy.layout === 'single' && policy.pagingAxis === 'horizontal' && current.doublePageEnabled) {
      await ReadModeSettings.setDoublePageEnabled(context, false)
    } else if (policy.layout === 'spread' && !current.doublePageEnabled) {
      await ReadModeSettings.setDoublePageEnabled(context, true)
    }
  }

  static async applyDirection(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    if (policy.layout === 'continuous' ? policy.continuousAxis === 'vertical' : policy.pagingAxis === 'vertical') return
    await NextEReaderRuntimePreferences.applyReadingMode(context, policy)
  }

  /** A direction choice never changes the independent double-page preference. */
  static async applyReadingMode(context: common.UIAbilityContext, policy: ReaderDisplayPolicy): Promise<void> {
    const mode = NextEReaderInitialPolicy.modeForPolicy(policy)
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
