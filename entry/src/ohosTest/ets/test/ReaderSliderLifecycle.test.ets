import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'

async function captureSeek(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-seek-${name}.json`
  const screen = `${cache}/rkit-seek-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  expect(await driver.dumpLayout(layout)).assertTrue()
  expect(await driver.screenCap(screen)).assertTrue()
}
async function seekPage(driver: Driver): Promise<number> {
  // The toggle-thumbnails click re-renders the surface, so the page chrome can be transiently
  // unavailable right after it; wait for it (bounded) instead of reading it once and crashing.
  for (let attempt = 0; attempt < 16; attempt++) {
    const chrome = await driver.findComponent(ON.id('rkit-chrome-page'))
    if (chrome !== null) return Number((await chrome.getText()).split('/')[0].trim())
    await driver.delayMs(250)
  }
  expect(false).assertTrue()
  return -1
}
async function waitSeekOriginal(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}
export default function readerSliderLifecycleTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderSliderLifecycleTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderSliderLifecycleTrial', (): void => {
    it('rtlCancelledGestureDoesNotCommitAndFreshGestureDoes', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '', readerLabChrome: 'true',
          // Pin the Debug-only entry direction to LTR so the runtime row '右→左' (switch to RTL)
          // is present to click; device 197/237 persist RTL, where the row would read '左→右'.
          readerLabEntryLayout: 'single', readerLabEntryDirection: 'ltr' },
      })
      await driver.delayMs(1800); await waitSeekOriginal(driver)
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await (await driver.findComponent(ON.text('右→左'))).click()
      await driver.delayMs(600)
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(1800)
      expect(await seekPage(driver)).assertEqual(1)
      const ability = await delegator.getCurrentTopAbility()
      const slider = await (await driver.findComponent(ON.id('rkit-source-slider'))).getBounds()
      const y = Math.round((slider.top + slider.bottom) / 2)
      const start = slider.right - 48
      await captureSeek(driver, 'rtl-before-cancel')
      const began = Date.now()
      let backgroundAt = 0
      // Ability lifecycle dispatch is separate from UiTest. Never issue concurrent Driver calls.
      const background = new Promise<void>((resolve, reject): void => {
        setTimeout((): void => {
          delegator.doAbilityBackground(ability).then((): void => {
            backgroundAt = Date.now()
            resolve()
          }).catch(reject)
        }, 900)
      })
      try {
        await driver.swipe(start, y, slider.left + 48, y, 200)
        const ended = Date.now()
        await background
        expect(backgroundAt > began && backgroundAt < ended).assertTrue()
        expect(delegator.getAbilityState(ability)).assertEqual(abilityDelegatorRegistry.AbilityLifecycleState.BACKGROUND)
        console.info(`[ReaderSeekTest] begin=${began} background=${backgroundAt} end=${ended}`)
        await captureSeek(driver, 'background')
      } finally {
        try { await background } finally {
          // Resume without replaying the original debug Want as a new trial request.
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
        }
      }
      await driver.delayMs(1200)
      await captureSeek(driver, 'restored')
      // NextE retires the shared reader route when the app backgrounds (its own
      // ReaderLifecycleRecoveryTrial / ReaderInformationBackgroundTrial assert that), so the
      // interrupted gesture cannot be re-observed on the same route. Assert the route retired,
      // then re-enter explicitly: because the cancelled RTL drag did not commit, the fresh route
      // opens again on the same page 1 / slider 1.
      let retired = false
      for (let attempt = 0; attempt < 40; attempt++) {
            if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null) { retired = true; break }
            await driver.delayMs(250)
      }
      expect(retired).assertTrue()
      await delegator.startAbility({
            bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
        readerLabChrome: 'true', readerLabEntryLayout: 'single', readerLabEntryDirection: 'ltr' },
      })
      await driver.delayMs(1800); await waitSeekOriginal(driver)
      expect(await seekPage(driver)).assertEqual(1)
      expect(Number(await (await driver.findComponent(ON.id('rkit-source-slider'))).getText())).assertEqual(1)
      // Re-enter pinned LTR, then switch to RTL through the runtime row (the row shows the target,
      // so '右→左' is present because the fresh route is LTR) and open the rail.
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await driver.delayMs(400)
      await (await driver.findComponent(ON.text('右→左'))).click()
      await driver.delayMs(600)
      await (await driver.findComponent(ON.id('rkit-toggle-thumbnails'))).click()
      await driver.delayMs(1800)
      expect(await seekPage(driver)).assertEqual(1)
      expect(await driver.findComponent(ON.id('rkit-thumbnail-0')) !== null).assertTrue()
      const freshSlider = await (await driver.findComponent(ON.id('rkit-source-slider'))).getBounds()
      const freshY = Math.round((freshSlider.top + freshSlider.bottom) / 2)
      const freshStart = freshSlider.right - 48
      await captureSeek(driver, 'rtl-fresh-before')
      await driver.swipe(freshStart, freshY, freshStart - 140, freshY, 200)
      await driver.delayMs(700)
      const selected = await seekPage(driver)
      expect(selected > 1).assertTrue()
      await waitSeekOriginal(driver)
      await captureSeek(driver, 'rtl-released')
      expect(await driver.findComponent(ON.id(`rkit-thumbnail-${selected - 1}`)) !== null).assertTrue()
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureSeek(driver, 'closed')
    })
  })
}
