import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, MatchPattern, ON } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { connectReadMode, ReadModeSettings, ReaderSuperResolutionModel } from 'shared'

const CAPTURE_PREFIX: string = 'reader-legacy-enh-crash'

async function entryContext(driver: Driver): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  for (let attempt: number = 0; attempt < 80; attempt++) {
    try {
      const ability = await delegator.getCurrentTopAbility()
      if (ability.context.abilityInfo.name === 'EntryAbility') return ability.context
    } catch (_) {}
    await driver.delayMs(100)
  }
  throw new Error('EntryAbility context unavailable')
}

async function waitId(driver: Driver, id: string, attempts: number = 120): Promise<Component> {
  for (let attempt: number = 0; attempt < attempts; attempt++) {
    const component = await driver.findComponent(ON.id(id))
    if (component !== null) return component
    await driver.delayMs(250)
  }
  throw new Error('component unavailable: ' + id)
}

async function capture(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  try { await driver.screenCap(cache + '/' + CAPTURE_PREFIX + '-' + name + '.png') } catch (_) {}
}

/** Open the first Home gallery card through the real waterfall cover. */
async function openFirstHomeGalleryDetail(driver: Driver): Promise<string> {
  const pattern = '^gallery-list-primary-1-waterfall-[0-9]+-cover$'
  const selector = ON.id(pattern, MatchPattern.REG_EXP).within(ON.id('nexte-root-navigation'))
  for (let attempt: number = 0; attempt < 120; attempt++) {
    const covers = await driver.findComponents(selector) ?? []
    if (covers.length > 0) {
      const cover = covers[0]
      const id: string = await cover.getId()
      await cover.click()
      await waitId(driver, 'gallery-detail-pane', 160)
      const m: RegExpMatchArray | null = id.match(/waterfall-([0-9]+)-cover/)
      return m === null ? '' : m[1]
    }
    await driver.delayMs(250)
  }
  throw new Error('Home gallery card unavailable')
}

async function tapDetailReadAction(driver: Driver): Promise<void> {
  await waitId(driver, 'gallery-detail-pane', 160)
  for (let attempt: number = 0; attempt < 120; attempt++) {
    for (const pattern of ['^阅读$', '^继续 P[0-9]+$', '^Read$', '^Resume P[0-9]+$']) {
      const candidates = await driver.findComponents(ON.text(pattern, MatchPattern.REG_EXP)) ?? []
      if (candidates.length > 0) {
        const bounds = await candidates[0].getBounds()
        if (bounds.right > bounds.left && bounds.bottom > bounds.top) {
          await candidates[0].click()
          return
        }
      }
    }
    await driver.delayMs(250)
  }
  throw new Error('Detail Read action unavailable')
}

export default function readerLegacyEnhancementCrashTrialTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'ReaderLegacyEnhancementCrashTrial') return
  describe('ReaderLegacyEnhancementCrashTrial', (): void => {
    it('opensLegacyReaderWithSuperResolutionAndTurnsPages', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      const context: common.UIAbilityContext = await entryContext(driver)
      const readMode = connectReadMode()
      const prevEnabled: boolean = readMode.superResolutionEnabled
      const prevModel: string = readMode.superResolutionModel
      const prevHeight: number = readMode.superResolutionMaxHeight
      try {
        const model: string = prevModel !== ReaderSuperResolutionModel.NONE
          ? prevModel
          : ReaderSuperResolutionModel.WAIFU2X_ART_NOISE0_2X
        await ReadModeSettings.setSuperResolutionModel(context, model)
        await ReadModeSettings.setSuperResolutionMaxHeight(context, 2000)
        await ReadModeSettings.setSuperResolutionEnabled(context, true)
        console.info('[ReaderLegacyEnhancementCrashTrial] enabled=true model=' + model)
        const gid: string = await openFirstHomeGalleryDetail(driver)
        console.info('[ReaderLegacyEnhancementCrashTrial] detail gid=' + gid)
        await tapDetailReadAction(driver)
        const surface: Component = await waitId(driver, 'reader_key_surface', 240)
        console.info('[ReaderLegacyEnhancementCrashTrial] legacy reader opened')
        await capture(driver, 'legacy-open')
        const bounds = await surface.getBounds()
        const midY: number = Math.round((bounds.top + bounds.bottom) / 2)
        for (let turn: number = 1; turn <= 6; turn++) {
          await driver.swipe(Math.round(bounds.left + (bounds.right - bounds.left) * 0.85), midY,
            Math.round(bounds.left + (bounds.right - bounds.left) * 0.15), midY, 600)
          await driver.delayMs(900)
          console.info('[ReaderLegacyEnhancementCrashTrial] turned=' + turn)
          await capture(driver, 'legacy-turn-' + turn)
        }
        expect(await driver.findComponent(ON.id('reader_key_surface')) !== null).assertTrue()
        console.info('[ReaderLegacyEnhancementCrashTrial] survived 6 turns')
      } finally {
        try {
          await ReadModeSettings.setSuperResolutionEnabled(context, prevEnabled)
          await ReadModeSettings.setSuperResolutionModel(context, prevModel)
          await ReadModeSettings.setSuperResolutionMaxHeight(context, prevHeight)
        } catch (_) {}
      }
    })
  })
}
