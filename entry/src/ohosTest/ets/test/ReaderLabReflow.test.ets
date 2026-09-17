import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { window } from '@kit.ArkUI'

async function capture(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  const screen = `${cache}/rkit-reflow-${name}.png`
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  // Driver.dumpLayout starts at API 26; device 197 retains the uitest CLI.
  const layout = await delegator.executeShellCommand(
    `uitest dumpLayout -p /data/local/tmp/rkit-reflow-${name}.json -a`, 15)
  expect(layout.exitCode).assertEqual(0)
  expect(await driver.screenCap(screen)).assertTrue()
  console.info(`[ReaderLabReflowTest] checkpoint=${name}`)
}

async function waitContinuousPage(driver: Driver): Promise<void> {
  // Switching layout briefly re-enters the catalog phase (0 / 0) before the
  // continuous row is laid out, so poll the real node instead of a fixed delay.
  for (let attempt = 0; attempt < 240; attempt++) {
    const page = await driver.findComponent(ON.id('rkit-continuous-page-0'))
    if (page !== null &&
      await driver.findComponent(ON.type('Image').within(ON.id('rkit-continuous-page-0'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-continuous-page-0'))) === null) return
    await driver.delayMs(250)
  }
  expect(false).assertTrue()
}

/** Explicit device acceptance only; never navigates from the ordinary test suite. */
export default function readerLabReflowTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const selected = args['-s class']
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if ((selected !== 'ReaderLabReflowOriginal' && selected !== 'ReaderLabReflowSprite') ||
    typeof work !== 'string' || typeof unit !== 'string' || work.length === 0 || unit.length === 0) return
  describe(selected, (): void => {
    it('rotateSameContinuousImage', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit } })
      const driver = Driver.create()
      await driver.delayMs(2500)
      await (await driver.findComponent(ON.id('rkit-layout'))).click()
      await (await driver.findComponent(ON.text('连续'))).click()
      await waitContinuousPage(driver)
      if (selected === 'ReaderLabReflowSprite') {
        await (await driver.findComponent(ON.id('rkit-asset-kind'))).click()
        await driver.delayMs(1500)
      }
      const bounds = await (await driver.findComponent(ON.id('rkit-continuous-page-0'))).getBounds()
      const x = Math.round((bounds.left + bounds.right) / 2)
      const y = Math.round((bounds.top + bounds.bottom) / 2)
      await driver.doubleClick(x, y)
      await driver.delayMs(400)
      await driver.swipe(x, y, x + 200, y, 600)
      await driver.delayMs(500)
      const ability = await delegator.getCurrentTopAbility()
      const main = await window.getLastWindow(ability.context)
      const original = main.getPreferredOrientation()
      try {
        await capture(driver, 'zoomed-portrait')
        await main.setPreferredOrientation(window.Orientation.LANDSCAPE)
        await driver.delayMs(1600)
        await capture(driver, 'landscape')
        const size = await driver.getDisplaySize()
        expect(size.x > size.y).assertTrue()
        await main.setPreferredOrientation(window.Orientation.PORTRAIT)
        await driver.delayMs(1600)
        await capture(driver, 'returned-portrait')
        await driver.swipe(x, y, x - 200, y, 600)
        await driver.delayMs(500)
        await capture(driver, 'post-rotation-pan')
      } finally {
        await main.setPreferredOrientation(original)
        console.info(`[ReaderLabReflowTest] restored_orientation_policy=${main.getPreferredOrientation()} original=${original}`)
      }
      expect(await (await driver.findComponent(ON.id('rkit-page-position'))).getText()).assertContain('1 / ')
    })
  })
}
