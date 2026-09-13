import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, MatchPattern, ON, PointerMatrix } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'

async function captureChrome(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-chrome-${name}.json`
  const screen = `${cache}/rkit-chrome-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  expect(await driver.dumpLayout(layout)).assertTrue()
  expect(await driver.screenCap(screen)).assertTrue()
}


async function waitChromeImage(driver: Driver, owner: string): Promise<string> {
  for (let attempt = 0; attempt < 80; attempt++) {
    const images = await driver.findComponents(ON.type('Image').within(ON.id(owner)))
    if (images.length === 1 &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(owner))) === null &&
      await driver.findComponent(ON.id('^rkit-failure-page-[0-9]+$', MatchPattern.REG_EXP)
        .within(ON.id(owner))) === null) {
      const id = await images[0].getId()
      if (id.length > 0) return id
    }
    await driver.delayMs(250)
  }
  throw new Error(`Reader image did not settle: ${owner}`)
}

async function waitChromeImageGeneration(driver: Driver, owner: string, previousId: string): Promise<string> {
  for (let attempt = 0; attempt < 80; attempt++) {
    const images = await driver.findComponents(ON.type('Image').within(ON.id(owner)))
    if (images.length === 1 &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(owner))) === null &&
      await driver.findComponent(ON.id('^rkit-failure-page-[0-9]+$', MatchPattern.REG_EXP)
        .within(ON.id(owner))) === null) {
      const id = await images[0].getId()
      if (id.length > 0 && id !== previousId) return id
    }
    await driver.delayMs(250)
  }
  throw new Error(`Reader image request generation did not change: ${owner}`)
}

async function chromePage(driver: Driver): Promise<number> {
  const value = await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()
  return Number(value.split('/')[0].trim())
}

/** This UI sequence runs only under an explicit named device protocol. */
export default function readerChromeTest(): void {
  readerHostSettingsTest()
  readerHostTranslationActionsTest()
  readerManualReloadTest()
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderChromeTrial' || typeof work !== 'string' || work.length === 0 || typeof unit !== 'string' || unit.length === 0) return
  describe('ReaderChromeTrial', (): void => {
    it('chromeDoesNotOwnTheViewport', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true' },
      })
      await driver.delayMs(2200)
      const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
      const x = Math.round((bounds.left + bounds.right) / 2)
      const y = Math.round((bounds.top + bounds.bottom) / 2)
      await captureChrome(driver, 'shown')
      await driver.click(x, y); await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-close'))).assertNull()
      await captureChrome(driver, 'hidden')
      await driver.doubleClick(x, y); await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-close'))).assertNull()
      await captureChrome(driver, 'double-tap')
      const points = PointerMatrix.create(2, 12)
      for (let step = 0; step < 12; step++) {
        const distance = (bounds.right - bounds.left) * (0.36 - 0.29 * step / 11)
        points.setPoint(0, step, { x: Math.round(x - distance), y })
        points.setPoint(1, step, { x: Math.round(x + distance), y })
      }
      expect(await driver.injectMultiPointerAction(points, 600)).assertTrue()
      await driver.delayMs(400)
      await captureChrome(driver, 'pinch-reset')
      expect(await driver.findComponent(ON.id('rkit-close'))).assertNull()
      await driver.click(x, y); await driver.delayMs(500)
      await captureChrome(driver, 'reset-shown')
      await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
      await driver.delayMs(800)
      const slider = await (await driver.findComponent(ON.id('rkit-source-slider'))).getBounds()
      await driver.click(Math.round(slider.left + (slider.right - slider.left) * 0.4),
        Math.round((slider.top + slider.bottom) / 2))
      await driver.delayMs(1500)
      await captureChrome(driver, 'spread-seek')
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await (await driver.findComponent(ON.text('连续'))).click()
      await driver.delayMs(1000)
      await captureChrome(driver, 'continuous')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureChrome(driver, 'closed')
    })

    it('sourceSeekAndDirectionRemainReadingIntents', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true' },
      })
      await driver.delayMs(1200)
      await waitChromeImage(driver, 'rkit-image-viewport')
      const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
      const x = Math.round((viewport.left + viewport.right) / 2)
      const y = Math.round((viewport.top + viewport.bottom) / 2)
      const baseline = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      await driver.doubleClick(x, y); await driver.delayMs(500)
      const zoomed = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      expect(zoomed.right - zoomed.left > baseline.right - baseline.left ||
        zoomed.bottom - zoomed.top > baseline.bottom - baseline.top).assertTrue()
      const slider = await (await driver.findComponent(ON.id('rkit-source-slider'))).getBounds()
      await driver.click(slider.left + 44, Math.round((slider.top + slider.bottom) / 2))
      await driver.delayMs(600)
      expect(await chromePage(driver)).assertEqual(1)
      const reset = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      expect(Math.abs(reset.left - baseline.left) <= 1 && Math.abs(reset.right - baseline.right) <= 1 &&
        Math.abs(reset.top - baseline.top) <= 1 && Math.abs(reset.bottom - baseline.bottom) <= 1).assertTrue()
      await captureChrome(driver, 'navigation-same-source')
      await driver.click(Math.round(viewport.right - (viewport.right - viewport.left) / 6), y)
      await driver.delayMs(600)
      expect(await chromePage(driver)).assertEqual(2)
      await waitChromeImage(driver, 'rkit-image-viewport')
      await captureChrome(driver, 'navigation-ltr')
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await (await driver.findComponent(ON.text('右→左'))).click()
      await driver.delayMs(600)
      expect(await chromePage(driver)).assertEqual(2)
      await captureChrome(driver, 'navigation-rtl')
      await driver.click(Math.round(viewport.left + (viewport.right - viewport.left) / 6), y)
      await driver.delayMs(600)
      expect(await chromePage(driver)).assertEqual(3)
      await waitChromeImage(driver, 'rkit-image-viewport')
      await captureChrome(driver, 'navigation-rtl-next')
      await driver.click(Math.round(viewport.right - (viewport.right - viewport.left) / 6), y)
      await driver.delayMs(600)
      expect(await chromePage(driver)).assertEqual(2)
      await captureChrome(driver, 'navigation-rtl-previous')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureChrome(driver, 'navigation-closed')
    })
  })
}

/** A displayed shared-reader source can be force-reloaded without leaving its reading target. */
function readerManualReloadTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderManualReloadTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderManualReloadTrial', (): void => {
    it('reloadsTheExactVisibleSource', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true', readerLabVolumeKeys: 'false',
        },
      })
      const beforeId = await waitChromeImage(driver, 'rkit-image-viewport')
      expect(await chromePage(driver)).assertEqual(1)
      const more = await driver.findComponent(ON.id('rkit-more'))
      expect(more !== null).assertTrue()
      if (more !== null) await more.click()
      const reload = await driver.findComponent(ON.id('rkit-reload-source'))
      expect(reload !== null).assertTrue()
      await captureChrome(driver, 'reload-source-menu')
      if (reload !== null) await reload.click()
      const afterId = await waitChromeImageGeneration(driver, 'rkit-image-viewport', beforeId)
      expect(afterId === beforeId).assertFalse()
      expect(await chromePage(driver)).assertEqual(1)
      await captureChrome(driver, 'reload-source-finished')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
    })

    it('reloadsOneExactSpreadSource', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true',
          readerLabVolumeKeys: 'false',
        },
      })
      await waitChromeImage(driver, 'rkit-image-viewport')
      await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
      await driver.delayMs(800)
      await waitChromeImage(driver, 'rkit-image-viewport')
      const page = await chromePage(driver)
      const more = await driver.findComponent(ON.id('rkit-more'))
      expect(more !== null).assertTrue()
      if (more !== null) await more.click()
      const reload = await driver.findComponent(ON.id('rkit-reload-source-spread'))
      expect(reload !== null).assertTrue()
      if (reload !== null) await reload.click()
      await driver.delayMs(300)
      const choices = await driver.findComponents(ON.id('^rkit-reload-source-[0-9]+$', MatchPattern.REG_EXP))
      expect(choices.length).assertEqual(2)
      const choiceId = await choices[0].getId()
      const choiceMatch = /^rkit-reload-source-([0-9]+)$/.exec(choiceId)
      expect(choiceMatch !== null).assertTrue()
      if (choiceMatch === null) throw new Error(`Unexpected reload choice id: ${choiceId}`)
      const targetSource = Number(choiceMatch[1])
      const parts = await driver.findComponents(
        ON.id('^rkit-part-[0-9]+-whole$', MatchPattern.REG_EXP).within(ON.id('rkit-image-viewport')),
      )
      expect(parts.length).assertEqual(2)
      const sourceIndices: number[] = []
      for (const part of parts) {
        const id = await part.getId()
        const match = /^rkit-part-([0-9]+)-whole$/.exec(id)
        if (match === null) throw new Error(`Unexpected spread part id: ${id}`)
        sourceIndices.push(Number(match[1]))
      }
      expect(sourceIndices.includes(targetSource)).assertTrue()
      const otherSource = sourceIndices.find((source: number): boolean => source !== targetSource)
      if (otherSource === undefined) throw new Error('Spread reload requires one non-target source')
      const targetOwner = `rkit-part-${targetSource}-whole`
      const otherOwner = `rkit-part-${otherSource}-whole`
      const targetBeforeId = await waitChromeImage(driver, targetOwner)
      const otherBeforeId = await waitChromeImage(driver, otherOwner)
      await captureChrome(driver, 'reload-spread-choice')
      await choices[0].click()
      const targetAfterId = await waitChromeImageGeneration(driver, targetOwner, targetBeforeId)
      expect(targetAfterId === targetBeforeId).assertFalse()
      expect(await waitChromeImage(driver, otherOwner)).assertEqual(otherBeforeId)
      const settledImages = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
      expect(settledImages.length).assertEqual(2)
      expect(await chromePage(driver)).assertEqual(page)
      await captureChrome(driver, 'reload-spread-finished')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
    })
  })
}

/** The shared surface exposes NextE translation actions without invoking either action. */
function readerHostTranslationActionsTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderHostTranslationActionsTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderHostTranslationActionsTrial', (): void => {
    it('sharedChromeExposesHostTranslationActions', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true',
          readerLabPreferencesReadWrite: 'true', readerLabVolumeKeys: 'false',
        },
      })
      await waitChromeImage(driver, 'rkit-image-viewport')
      const more = await driver.findComponent(ON.id('rkit-more'))
      expect(more !== null).assertTrue()
      if (more !== null) await more.click()
      for (let attempt = 0; attempt < 20; attempt++) {
        if (await driver.findComponent(ON.id('rkit-host-action-translate-page')) !== null &&
          await driver.findComponent(ON.id('rkit-host-action-translate-auto')) !== null) break
        await driver.delayMs(250)
      }
      expect(await driver.findComponent(ON.id('rkit-host-action-translate-page')) !== null).assertTrue()
      expect(await driver.findComponent(ON.id('rkit-host-action-translate-auto')) !== null).assertTrue()
      await captureChrome(driver, 'host-translation-actions')
      await driver.pressBack(); await driver.delayMs(400)
      expect(await driver.findComponent(ON.id('rkit-close')) !== null).assertTrue()
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
    })
  })
}

/** The shared surface delegates to NextE's existing settings sheet without changing a setting. */
function readerHostSettingsTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderHostSettingsTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderHostSettingsTrial', (): void => {
    it('sharedChromeOpensAndReturnsFromHostSettings', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true',
          readerLabPreferencesReadWrite: 'true', readerLabVolumeKeys: 'false',
        },
      })
      await waitChromeImage(driver, 'rkit-image-viewport')
      const hostSettings = await driver.findComponent(ON.id('rkit-host-settings'))
      expect(hostSettings !== null).assertTrue()
      expect(await driver.findComponent(ON.id('rkit-runtime-settings'))).assertNull()
      if (hostSettings !== null) await hostSettings.click()
      for (let attempt = 0; attempt < 40; attempt++) {
        if (await driver.findComponent(ON.text('双页模式')) !== null) break
        await driver.delayMs(250)
      }
      expect(await driver.findComponent(ON.text('双页模式')) !== null).assertTrue()
      await captureChrome(driver, 'host-settings-open')
      await driver.pressBack(); await driver.delayMs(600)
      expect(await driver.findComponent(ON.id('rkit-host-settings')) !== null).assertTrue()
      await captureChrome(driver, 'host-settings-returned')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
    })
  })
}
