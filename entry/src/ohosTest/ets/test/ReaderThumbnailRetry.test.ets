import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'

async function captureRetry(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-thumb-retry-${name}.json`
  const screen = `${cache}/rkit-thumb-retry-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  expect(await driver.dumpLayout(layout)).assertTrue()
  expect(await driver.screenCap(screen)).assertTrue()
}
async function retryPage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}
async function waitRetryImage(driver: Driver, owner: string): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id(owner))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(owner))) === null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}
async function waitThumbnailDecoded(driver: Driver, index: number): Promise<void> {
  // Image creation precedes decoding. The existing session reaches displayed only
  // after the native Image.onComplete(loadingStatus=1), not when a URI arrives.
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.id(`rkit-thumb-state-${index}-displayed`)) !== null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}
export default function readerThumbnailRetryTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderThumbnailRetryTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderThumbnailRetryTrial', (): void => {
    it('retryRecoversOnlyPreviewThenFreshSelectionSeeks', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabChrome: 'true', readerLabFailThumbnailPage: '1' },
      })
      await driver.delayMs(1800)
      await waitRetryImage(driver, 'rkit-image-viewport')
      await captureRetry(driver, 'original')
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      for (let attempt = 0; attempt < 30; attempt++) {
        if (await driver.findComponent(ON.id('rkit-thumb-retry-1')) !== null) break
        await driver.delayMs(300)
      }
      expect(await driver.findComponent(ON.id('rkit-thumb-retry-1')) !== null).assertTrue()
      await waitThumbnailDecoded(driver, 0)
      expect(await retryPage(driver)).assertEqual(1)
      await captureRetry(driver, 'failed')
      await (await driver.findComponent(ON.id('rkit-thumb-retry-1'))).click()
      await waitThumbnailDecoded(driver, 1)
      await driver.delayMs(400)
      expect(await retryPage(driver)).assertEqual(1)
      expect(await driver.findComponent(ON.id('rkit-thumb-retry-1'))).assertNull()
      expect(await driver.findComponent(ON.id('rkit-source-slider')) !== null).assertTrue()
      await captureRetry(driver, 'recovered')
      await (await driver.findComponent(ON.id('rkit-thumbnail-1'))).click()
      await driver.delayMs(500)
      expect(await retryPage(driver)).assertEqual(2)
      await waitRetryImage(driver, 'rkit-image-viewport')
      await captureRetry(driver, 'selected')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureRetry(driver, 'closed')
    })
  })
}
