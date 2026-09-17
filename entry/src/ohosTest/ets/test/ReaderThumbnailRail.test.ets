import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'

async function captureRail(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-rail-${name}.json`
  const screen = `${cache}/rkit-rail-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  if (typeof driver.dumpLayout === 'function') expect(await driver.dumpLayout(layout)).assertTrue()
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
async function waitThumbnail(driver: Driver, index: number): Promise<void> {
  for (let attempt = 0; attempt < 30; attempt++) {
    if (await driver.findComponent(ON.id(`rkit-thumb-state-${index}-displayed`)) !== null) return
    await driver.delayMs(250)
  }
  expect(false).assertTrue()
}
export default function readerThumbnailRailTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  const selectedClass = args['-s class']
  if (typeof work !== 'string' || work.length === 0 || typeof unit !== 'string' || unit.length === 0) return
  if (selectedClass === 'ReaderThumbnailRailTrial') describe('ReaderThumbnailRailTrial', (): void => {
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
      // The runtime menu mounts asynchronously and its direction row names the *target*
      // direction, so accept either label before toggling it.
      const RTL_ROW: string = '右→左'
      const LTR_ROW: string = '左→右'
      let direction = await driver.findComponent(ON.text(RTL_ROW))
      if (direction === null) direction = await driver.findComponent(ON.text(LTR_ROW))
      for (let attempt = 0; attempt < 20 && direction === null; attempt++) {
        await driver.delayMs(150)
        direction = await driver.findComponent(ON.text(RTL_ROW))
        if (direction === null) direction = await driver.findComponent(ON.text(LTR_ROW))
      }
      expect(direction !== null).assertTrue()
      if (direction !== null) await direction.click()
      await driver.delayMs(1000)
      expect(await pageNumber(driver)).assertEqual(selected + 1)
      await captureRail(driver, 'rtl')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(400)
      await captureRail(driver, 'rail-hidden')
      expect(await driver.findComponent(ON.id('rkit-thumbnail-rail-wrapper'))).assertNull()
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
  if (selectedClass === 'ReaderThumbnailRailLifecycleTrial') describe('ReaderThumbnailRailLifecycleTrial', (): void => {
    it('hidesByClippingAndReopensTheRetainedDecodedRail', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true' },
      })
      await driver.delayMs(1600); await waitOriginal(driver)
      const page = await pageNumber(driver)
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await waitThumbnail(driver, 0)
      await captureRail(driver, 'lifecycle-opened')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(400)
      await captureRail(driver, 'lifecycle-hidden')
      expect(await driver.findComponent(ON.id('rkit-thumbnail-rail-wrapper'))).assertNull()
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(500)
      expect(await pageNumber(driver)).assertEqual(page)
      expect(await driver.findComponent(ON.id('rkit-thumb-state-0-displayed')) !== null).assertTrue()
      await captureRail(driver, 'lifecycle-reopened')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(600)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureRail(driver, 'lifecycle-closed')
      console.info('[ReaderThumbnailRailLifecycleTrial] hiddenFromUiTree=true decodedAfterReopen=true pageStable=true')
    })
  })
}
