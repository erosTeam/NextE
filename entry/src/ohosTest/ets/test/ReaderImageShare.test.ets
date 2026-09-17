import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { KeyCode } from '@kit.InputKit'
import { fileIo } from '@kit.CoreFileKit'

function clearShareCaptures(): void {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const names = ['baseline', 'panel', 'returned', 'next', 'next-panel', 'next-returned', 'closed',
    'exception', 'recovery-baseline', 'failed', 'pending', 'changed', 'late',
    'recovery-panel', 'recovery-returned', 'recovery-closed', 'original-information']
  for (const name of names) {
    for (const extension of ['json', 'png']) {
      const path = `${cache}/rkit-share-${name}.${extension}`
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    }
  }
}

async function captureShare(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  const layout = `${cache}/rkit-share-${name}.json`
  const screen = `${cache}/rkit-share-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  // Driver.dumpLayout is absent on some SDK builds; fall back to the uitest CLI like the other
  // NextE trials do, so the share evidence capture works on the same device.
  if (typeof driver.dumpLayout === 'function') expect(await driver.dumpLayout(layout)).assertTrue()
  else {
    expect((await delegator.executeShellCommand(
      `uitest dumpLayout -p /data/local/tmp/rkit-share-${name}.json`, 15)).exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(screen)).assertTrue()
}
async function sharePage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}
async function shareImageReady(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(500)
  }
  await captureShare(driver, 'exception')
  expect(false).assertTrue()
}
async function shareAndCancel(driver: Driver, page: number, prefix: string): Promise<void> {
  const button = await driver.findComponent(ON.id('rkit-share-image'))
  expect(await button.isEnabled()).assertTrue()
  await button.click()
  await driver.delayMs(3000)
  // The screenshot is separately inspected for the actual system sheet and record.
  // Button busy alone never accepts successful platform presentation.
  await captureShare(driver, `${prefix}panel`)
  expect(await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()).assertFalse()
  await driver.triggerKey(KeyCode.KEYCODE_BACK)
  for (let attempt = 0; attempt < 20; attempt++) {
    const current = await driver.findComponent(ON.id('rkit-share-image'))
    if (current !== null && await current.isEnabled()) break
    await driver.delayMs(500)
  }
  expect(await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()).assertTrue()
  expect(await sharePage(driver)).assertEqual(page)
  await shareImageReady(driver)
  await captureShare(driver, `${prefix}returned`)
}

async function shareRecoveryTrial(work: string, unit: string, mode: string): Promise<void> {
  clearShareCaptures()
  const driver = Driver.create()
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
    parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true',
      readerLabShareProbe: mode === 'failure' ? 'fail-once' : 'delay-once' } })
  await driver.delayMs(1800); await shareImageReady(driver)
  expect(await sharePage(driver)).assertEqual(2)
  await captureShare(driver, 'recovery-baseline')
  await (await driver.findComponent(ON.id('rkit-share-image'))).click()
  if (mode === 'failure') {
    for (let attempt = 0; attempt < 40; attempt++) {
      if (await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()) break
      await driver.delayMs(100)
    }
    await driver.delayMs(100)
    expect(await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()).assertTrue()
    expect(await sharePage(driver)).assertEqual(2)
    await captureShare(driver, 'failed')
    await shareAndCancel(driver, 2, 'recovery-')
  } else {
    await driver.delayMs(300)
    expect(await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()).assertFalse()
    await captureShare(driver, 'pending')
    if (mode === 'page') {
      const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
      await driver.click(Math.round(bounds.left + (bounds.right - bounds.left) * 0.8),
        Math.round((bounds.top + bounds.bottom) / 2))
      await driver.delayMs(500)
      expect(await sharePage(driver)).assertEqual(3)
      await captureShare(driver, 'changed')
      await driver.delayMs(3500)
      expect(await sharePage(driver)).assertEqual(3)
      expect(await (await driver.findComponent(ON.id('rkit-share-image'))).isEnabled()).assertTrue()
      await captureShare(driver, 'late')
      await shareAndCancel(driver, 3, 'recovery-')
    } else {
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureShare(driver, 'changed')
      await driver.delayMs(3500)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureShare(driver, 'late')
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true' } })
      await driver.delayMs(1800); await shareImageReady(driver)
      await shareAndCancel(driver, 2, 'recovery-')
    }
  }
  await (await driver.findComponent(ON.id('rkit-close'))).click()
  await driver.delayMs(700)
  expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
  await captureShare(driver, 'recovery-closed')
}

export default function readerImageShareTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  const trial = args['-s class']
  if (trial === 'ReaderOriginalVariantShareTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('selectedOriginalOpensSystemShareAndCancellationRetainsPage', 0, async (): Promise<void> => {
        clearShareCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
            readerLabPage: '1', readerLabChrome: 'true' } })
        await shareImageReady(driver)
        await (await driver.findComponent(ON.id('rkit-original-image'))).click()
        let ready = false
        for (let attempt = 0; attempt < 60; attempt++) {
          const more = await driver.findComponent(ON.id('rkit-more'))
          if (more !== null && await more.isEnabled()) { ready = true; break }
          await driver.delayMs(500)
        }
        expect(ready).assertTrue()
        await (await driver.findComponent(ON.id('rkit-more'))).click()
        await driver.delayMs(400)
        await (await driver.findComponent(ON.id('rkit-image-info'))).click()
        await driver.delayMs(500)
        const information = await driver.findComponent(ON.type('AlertDialog'))
        expect(information !== null && (await information.getText()).indexOf('当前：原图') >= 0).assertTrue()
        await captureShare(driver, 'original-information')
        await driver.pressBack(); await driver.delayMs(600)
        await shareAndCancel(driver, 2, '')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await driver.delayMs(700)
        expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
        await captureShare(driver, 'closed')
      })
    })
    return
  }
  if (typeof work === 'string' && work.length > 0 &&
    (trial === 'ReaderShareFailureTrial' || trial === 'ReaderSharePageCancelTrial' || trial === 'ReaderShareCloseCancelTrial')) {
    describe(trial, (): void => {
      it('preparationFailureOrCancellationKeepsFreshActionsUsable', 0, async (): Promise<void> => {
        await shareRecoveryTrial(work, typeof unit === 'string' ? unit : '',
          trial === 'ReaderShareFailureTrial' ? 'failure' : trial === 'ReaderSharePageCancelTrial' ? 'page' : 'close')
      })
    })
    return
  }
  if (args['-s class'] !== 'ReaderImageShareTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderImageShareTrial', (): void => {
    it('currentOriginalShareCancelsWithoutLosingPageAndAllowsFreshAction', 0, async (): Promise<void> => {
      clearShareCaptures()
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabPage: '1', readerLabChrome: 'true', readerLabVolumeKeys: 'true' } })
      await driver.delayMs(1800); await shareImageReady(driver)
      if (args['-s readerShareSpread'] === 'true') {
        await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
        await driver.delayMs(700); await shareImageReady(driver)
      }
      expect(await sharePage(driver)).assertEqual(2)
      await captureShare(driver, 'baseline')
      await shareAndCancel(driver, 2, '')
      await driver.triggerKey(KeyCode.KEYCODE_VOLUME_DOWN)
      await driver.delayMs(700); await shareImageReady(driver)
      expect(await sharePage(driver)).assertEqual(3)
      await captureShare(driver, 'next')
      await shareAndCancel(driver, 3, 'next-')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureShare(driver, 'closed')
    })
  })
}
