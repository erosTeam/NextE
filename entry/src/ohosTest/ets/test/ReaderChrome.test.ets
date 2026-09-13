import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON, PointerMatrix } from '@kit.TestKit'
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


async function waitChromeImage(driver: Driver, owner: string): Promise<void> {
  for (let attempt = 0; attempt < 30; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id(owner))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(owner))) === null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}

async function chromePage(driver: Driver): Promise<number> {
  const value = await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()
  return Number(value.split('/')[0].trim())
}

/** This UI sequence runs only under an explicit named device protocol. */
export default function readerChromeTest(): void {
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
