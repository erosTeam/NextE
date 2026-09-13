import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON, PointerMatrix } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { window } from '@kit.ArkUI'

async function captureAxis(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  const layout = `${cache}/rkit-axis-${name}.json`
  const screen = `${cache}/rkit-axis-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  if (typeof driver.dumpLayout === 'function') expect(await driver.dumpLayout(layout)).assertTrue()
  else {
    const result = await delegator.executeShellCommand(`uitest dumpLayout -p /data/local/tmp/rkit-axis-${name}.json`, 15)
    expect(result.exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(screen)).assertTrue()
}

async function axisPage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}

async function axisImage(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(400)
  }
  expect(false).assertTrue()
}

async function axisSwipe(driver: Driver, vertical: boolean, forward: boolean): Promise<void> {
  const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
  const x = Math.round((bounds.left + bounds.right) / 2)
  const y = Math.round((bounds.top + bounds.bottom) / 2)
  const extent = vertical ? bounds.bottom - bounds.top : bounds.right - bounds.left
  // Cross half the native page even at a non-fling velocity; the initial 46% slow
  // trajectory could legitimately settle on the same page and was not a paging acceptance.
  const offset = Math.round(extent * 0.31) * (forward ? 1 : -1)
  await driver.swipe(vertical ? x : x + offset, vertical ? y + offset : y,
    vertical ? x : x - offset, vertical ? y - offset : y, 700)
  await driver.delayMs(700)
}

/** Named protocol only: real native swipes, no session command injection or preference writes. */
export default function readerPagingAxisTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderPagingAxisTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderPagingAxisTrial', (): void => {
    it('verticalNativePagingAndReturnHorizontal', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabPage: '1', readerLabChrome: 'true', readerLabVolumeKeys: 'false' } })
      await driver.delayMs(1800)
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      try {
        const ability = await delegator.getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        await axisImage(driver)
        expect(await axisPage(driver)).assertEqual(2)
        await (await driver.findComponent(ON.id('rkit-reading-mode'))).click()
        await captureAxis(driver, 'menu')
        await (await driver.findComponent(ON.id('rkit-vertical-paged'))).click()
        await driver.delayMs(600)
        expect(await axisPage(driver)).assertEqual(2)
        await captureAxis(driver, 'vertical-p2')
        await axisSwipe(driver, true, true); await axisImage(driver)
        expect(await axisPage(driver)).assertEqual(3)
        await captureAxis(driver, 'vertical-p3')
        await axisSwipe(driver, true, false); await axisImage(driver)
        expect(await axisPage(driver)).assertEqual(2)
        await captureAxis(driver, 'vertical-return-p2')
        const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
        const x = Math.round((bounds.left + bounds.right) / 2)
        const y = Math.round((bounds.top + bounds.bottom) / 2)
        const points = PointerMatrix.create(2, 12)
        for (let step = 0; step < 12; step++) {
          const offset = Math.round((bounds.right - bounds.left) * (0.16 + 0.13 * step / 11))
          points.setPoint(0, step, { x: x - offset, y })
          points.setPoint(1, step, { x: x + offset, y })
        }
        expect(await driver.injectMultiPointerAction(points, 600)).assertTrue()
        await driver.delayMs(500)
        // Device acceptance additionally requires this run's ReaderViewport pinch scale>1
        // and reviewed original before/after pixels. Injection/page continuity alone is NOT a zoom pass.
        console.info('[ReaderPagingAxisTest] zoom_evidence_requires_transform_and_pixel_review')
        await captureAxis(driver, 'zoom-before-pan')
        await axisSwipe(driver, true, true)
        expect(await axisPage(driver)).assertEqual(2)
        await captureAxis(driver, 'zoom-after-pan')
        await driver.doubleClick(x, y); await driver.delayMs(500)
        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
        await driver.delayMs(1400)
        const landscape = await driver.getDisplaySize()
        expect(landscape.x > landscape.y).assertTrue()
        expect(await axisPage(driver)).assertEqual(2)
        await captureAxis(driver, 'landscape-p2')
        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        await driver.delayMs(1400)
        const portrait = await driver.getDisplaySize()
        expect(portrait.y > portrait.x).assertTrue()
        expect(await axisPage(driver)).assertEqual(2)
        await (await driver.findComponent(ON.id('rkit-reading-mode'))).click()
        await (await driver.findComponent(ON.text('单页'))).click()
        await driver.delayMs(600)
        await axisSwipe(driver, false, true); await axisImage(driver)
        expect(await axisPage(driver)).assertEqual(3)
        await captureAxis(driver, 'horizontal-p3')
      } catch (error) {
        console.error(`[ReaderPagingAxisTest] failure=${(error as Error).message}`)
        try { await captureAxis(driver, 'exception') } catch (_) {}
        throw (error as Error)
      } finally {
        try {
          if (mainWindow !== null && originalOrientation !== null) {
            await mainWindow.setPreferredOrientation(originalOrientation)
            await driver.delayMs(400)
            expect(mainWindow.getPreferredOrientation()).assertEqual(originalOrientation)
            console.info(`[ReaderPagingAxisTest] restored_orientation=${mainWindow.getPreferredOrientation()} original=${originalOrientation}`)
          }
        } finally {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
          else if (await driver.findComponent(ON.id('rkit-native-pager')) !== null) await driver.pressBack()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-native-pager'))).assertNull()
          await captureAxis(driver, 'closed')
        }
      }
    })
  })
}
