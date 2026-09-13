import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'

async function captureRail(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-rail-${name}.json`
  const screen = `${cache}/rkit-rail-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  expect(await driver.dumpLayout(layout)).assertTrue()
  expect(await driver.screenCap(screen)).assertTrue()
}
async function pageNumber(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}
async function waitOriginal(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 30; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}
export default function readerThumbnailRailTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderThumbnailRailTrial' || typeof work !== 'string' || work.length === 0 || typeof unit !== 'string' || unit.length === 0) return
  describe('ReaderThumbnailRailTrial', (): void => {
    it('previewScrollingDoesNotTurnPagesAndTileSelectionDoes', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true' },
      })
      await driver.delayMs(1600); await waitOriginal(driver)
      const before = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      await captureRail(driver, 'baseline')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(2500)
      await captureRail(driver, 'opened')
      const after = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      expect(before.left === after.left && before.top === after.top && before.right === after.right && before.bottom === after.bottom).assertTrue()
      const thumb = await (await driver.findComponent(ON.id('rkit-thumb-image-0'))).getBounds()
      expect(Math.abs((thumb.right - thumb.left) / (thumb.bottom - thumb.top) -
        (before.right - before.left) / (before.bottom - before.top)) < 0.05).assertTrue()
      const rail = await (await driver.findComponent(ON.id('rkit-thumbnail-rail'))).getBounds()
      const y = Math.round((rail.top + rail.bottom) / 2)
      for (let count = 0; count < 3; count++) {
        await driver.swipe(rail.right - 100, y, rail.left + 100, y, 600)
        await driver.delayMs(500)
      }
      await driver.delayMs(1500)
      expect(await pageNumber(driver)).assertEqual(1)
      await captureRail(driver, 'scrolled')
      let selected = -1
      for (let index = 4; index < 40; index++) {
        const tile = await driver.findComponent(ON.id(`rkit-thumbnail-${index}`))
        if (tile === null) continue
        const bounds = await tile.getBounds()
        if (bounds.left >= rail.left && bounds.right <= rail.right && bounds.right > bounds.left) {
          selected = index; await tile.click(); break
        }
      }
      expect(selected >= 4).assertTrue()
      await driver.delayMs(700)
      expect(await pageNumber(driver)).assertEqual(selected + 1)
      await waitOriginal(driver)
      await captureRail(driver, 'selected')
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await (await driver.findComponent(ON.text('右→左'))).click()
      await driver.delayMs(1000)
      expect(await pageNumber(driver)).assertEqual(selected + 1)
      await captureRail(driver, 'rtl')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(400)
      expect(await driver.findComponent(ON.id('rkit-thumbnail-rail'))).assertNull()
      await captureRail(driver, 'rail-hidden')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(1500)
      expect(await pageNumber(driver)).assertEqual(selected + 1)
      await captureRail(driver, 'reopened')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(600)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureRail(driver, 'closed')
    })
  })
}
