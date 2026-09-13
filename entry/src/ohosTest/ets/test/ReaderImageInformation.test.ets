import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { KeyCode } from '@kit.InputKit'
import { fileIo } from '@kit.CoreFileKit'
import { window } from '@kit.ArkUI'
import { ReaderTrialEntryProbe, connectReadMode } from 'shared'

const captureNames: string[] = ['baseline', 'single', 'single-return', 'spread', 'choice', 'left', 'right', 'returned', 'next', 'closed', 'exception',
  'recovery-baseline', 'failed', 'pending', 'changed', 'late', 'recovery-info', 'recovery-returned', 'recovery-closed',
  'original-baseline', 'original-info', 'original-on', 'original-off-info', 'original-off', 'original-closed',
  'original-spread-menu', 'original-spread-mixed', 'original-spread-left', 'original-spread-right',
  'original-both-left', 'original-both-right', 'original-default-left', 'original-default-right',
  'original-prepare-retained', 'original-decode-failed', 'original-recovered']
function clearInformationCaptures(): void {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  for (const name of captureNames) {
    for (const extension of ['json', 'png']) {
      const path = `${cache}/rkit-info-${name}.${extension}`
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    }
  }
}
async function captureInformation(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  expect(await driver.dumpLayout(`${cache}/rkit-info-${name}.json`)).assertTrue()
  expect(await driver.screenCap(`${cache}/rkit-info-${name}.png`)).assertTrue()
}
async function informationReady(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const more = await driver.findComponent(ON.id('rkit-more'))
    if (more !== null && await more.isEnabled()) return
    await driver.delayMs(500)
  }
  await captureInformation(driver, 'exception')
  expect(false).assertTrue()
}
async function openInformationMenu(driver: Driver): Promise<void> {
  await informationReady(driver)
  await (await driver.findComponent(ON.id('rkit-more'))).click()
  await driver.delayMs(400)
  await (await driver.findComponent(ON.id('rkit-image-info'))).click()
  await driver.delayMs(500)
}
async function assertInformation(driver: Driver, page: number, name: string, expectedOriginal: string = '', expectedVariant: string = ''): Promise<void> {
  const title = `图片信息 · 第 ${page} 页`
  for (let attempt = 0; attempt < 20; attempt++) {
    if (await driver.findComponent(ON.text(title)) !== null) break
    await driver.delayMs(300)
  }
  const found = await driver.findComponent(ON.text(title)) !== null
  if (!found) await captureInformation(driver, 'exception')
  expect(found).assertTrue()
  await captureInformation(driver, name)
  if (expectedOriginal.length > 0) {
    const message = await (await driver.findComponent(ON.type('AlertDialog'))).getText()
    expect(message.indexOf(`原图：${expectedOriginal}`) >= 0).assertTrue()
  }
  if (expectedVariant.length > 0) {
    const message = await (await driver.findComponent(ON.type('AlertDialog'))).getText()
    expect(message.indexOf(`当前：${expectedVariant}`) >= 0).assertTrue()
    await abilityDelegatorRegistry.getAbilityDelegator().print(`ReaderOriginal information page=${page} variant=${expectedVariant} message=${message}`)
  }
  await driver.triggerKey(KeyCode.KEYCODE_BACK)
  await driver.delayMs(600)
  expect(await driver.findComponent(ON.type('AlertDialog'))).assertNull()
  await informationReady(driver)
}

async function informationPage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}

async function assertSpreadVariant(driver: Driver, source: number, name: string, variant: string): Promise<void> {
  // The previous original-choice popup owns input until its native dismissal finishes.
  let dismissed = false
  for (let attempt = 0; attempt < 30; attempt++) {
    if (await driver.findComponent(ON.type('Menu')) === null) { dismissed = true; break }
    await driver.delayMs(100)
  }
  expect(dismissed).assertTrue()
  await driver.delayMs(400)
  await openInformationMenu(driver)
  let ready = false
  for (let attempt = 0; attempt < 60; attempt++) {
    const item = await driver.findComponent(ON.id(`rkit-info-source-${source}`))
    if (item !== null && await item.isEnabled()) { ready = true; await item.click(); break }
    await driver.delayMs(500)
  }
  expect(ready).assertTrue()
  await assertInformation(driver, source + 1, name, '可用', variant)
}

async function informationRecoveryTrial(work: string, unit: string, mode: string): Promise<void> {
  clearInformationCaptures()
  const driver = Driver.create()
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
    parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true',
      readerLabInformationProbe: mode === 'failure' ? 'fail-once' : 'delay-once' } })
  await driver.delayMs(1500); await informationReady(driver)
  expect(await informationPage(driver)).assertEqual(2)
  await captureInformation(driver, 'recovery-baseline')
  await openInformationMenu(driver)
  let expectedPage = 2
  if (mode === 'failure') {
    await informationReady(driver)
    await captureInformation(driver, 'failed')
    expect(await driver.findComponent(ON.type('AlertDialog'))).assertNull()
    expect(await informationPage(driver)).assertEqual(2)
  } else {
    expect(await (await driver.findComponent(ON.id('rkit-more'))).isEnabled()).assertFalse()
    await captureInformation(driver, 'pending')
    if (mode === 'page') {
      const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
      await driver.click(Math.round(bounds.left + (bounds.right - bounds.left) * 0.8),
        Math.round((bounds.top + bounds.bottom) / 2))
      expectedPage = 3
      await driver.delayMs(500); await informationReady(driver)
    } else if (mode === 'close') {
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
    } else {
      const ability = await delegator.getCurrentTopAbility()
      try {
        await delegator.doAbilityBackground(ability); await driver.delayMs(500)
        expect(delegator.getAbilityState(ability)).assertEqual(abilityDelegatorRegistry.AbilityLifecycleState.BACKGROUND)
        await captureInformation(driver, 'changed')
      } finally {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      }
      await driver.delayMs(700); await informationReady(driver)
    }
    if (mode !== 'background') await captureInformation(driver, 'changed')
    await driver.delayMs(3500)
    await captureInformation(driver, 'late')
    expect(await driver.findComponent(ON.type('AlertDialog'))).assertNull()
    if (mode === 'close') {
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true' } })
      await driver.delayMs(1500); await informationReady(driver)
    }
    expect(await informationPage(driver)).assertEqual(expectedPage)
  }
  await openInformationMenu(driver)
  await assertInformation(driver, expectedPage, 'recovery-info')
  expect(await informationPage(driver)).assertEqual(expectedPage)
  await captureInformation(driver, 'recovery-returned')
  await (await driver.findComponent(ON.id('rkit-close'))).click()
  await driver.delayMs(700)
  expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
  await captureInformation(driver, 'recovery-closed')
}

export default function readerImageInformationTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork'], unit = args['-s readerLabUnit']
  const trial = args['-s class']
  if ((trial === 'ReaderCropToggleTrial' || trial === 'ReaderCropZoomToggleTrial') && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('runtimeMenuCropOnOffRetainsPageAndRestoresGeometry', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const layout = args['-s readerLabCropLayout'] === 'continuous' ? 'continuous' :
          args['-s readerLabCropLayout'] === 'spread' ? 'spread' : 'single'
        const sourceIndex = 4
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
            readerLabPage: `${sourceIndex}`, readerLabChrome: 'true', readerLabCropBorders: 'false' } })
        await informationReady(driver)
        if (layout !== 'single') {
          await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
          await driver.delayMs(300)
          await (await driver.findComponent(ON.text(layout === 'spread' ? '双页' : '连续'))).click()
          await driver.delayMs(600); await informationReady(driver)
        }
        const cropImage = ON.id(`rkit-cropped-image-${sourceIndex}-whole`)
        expect(await informationPage(driver)).assertEqual(sourceIndex + 1)
        expect(await driver.findComponent(cropImage) === null).assertTrue()
        const zoomTrial = trial === 'ReaderCropZoomToggleTrial'
        const bodyImage = ON.type('Image').within(ON.id('rkit-image-viewport'))
        const originalBounds = zoomTrial ? await (await driver.findComponent(bodyImage)).getBounds() : null
        if (zoomTrial) {
          const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
          await driver.doubleClick(Math.round(viewport.left + (viewport.right - viewport.left) * 0.45),
            Math.round(viewport.top + (viewport.bottom - viewport.top) * 0.45))
          await driver.delayMs(500)
        }
        const zoomBounds = zoomTrial ? await (await driver.findComponent(bodyImage)).getBounds() : null
        if (zoomBounds !== null && originalBounds !== null) expect(zoomBounds.right - zoomBounds.left > originalBounds.right - originalBounds.left ||
          zoomBounds.bottom - zoomBounds.top > originalBounds.bottom - originalBounds.top).assertTrue()
        await captureInformation(driver, 'baseline')
        const ability = await delegator.getCurrentTopAbility(), win = await window.getLastWindow(ability.context)
        const utils = win.getUIContext().getComponentUtils()
        const height = (): number => layout === 'continuous' ?
          utils.getRectangleById(`rkit-continuous-page-${sourceIndex}`).size.height :
          utils.getRectangleById(`rkit-part-${sourceIndex}-whole`).size.height
        const before = height()
        await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
        await driver.delayMs(300)
        const toggle = await driver.findComponent(ON.id('rkit-crop-toggle'))
        expect(toggle !== null).assertTrue()
        await captureInformation(driver, 'choice')
        await toggle.click()
        for (let i = 0; i < 40 && await driver.findComponent(cropImage) === null; i++) await driver.delayMs(250)
        expect(await driver.findComponent(cropImage) !== null).assertTrue()
        expect(await informationPage(driver)).assertEqual(sourceIndex + 1)
        await captureInformation(driver, 'changed')
        await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
        await driver.delayMs(300)
        await (await driver.findComponent(ON.id('rkit-crop-toggle'))).click()
        for (let i = 0; i < 40 && await driver.findComponent(cropImage) !== null; i++) await driver.delayMs(250)
        expect(await driver.findComponent(cropImage) === null).assertTrue()
        await driver.delayMs(500)
        expect(await informationPage(driver)).assertEqual(sourceIndex + 1)
        const after = height()
        await delegator.print(`ReaderCropToggle layout=${layout} page=${sourceIndex + 1} before=${before} after=${after}`)
        expect(Math.abs(before - after) <= 1).assertTrue()
        await captureInformation(driver, 'returned')
        if (zoomBounds !== null) {
          const restored = await (await driver.findComponent(bodyImage)).getBounds()
          // UiTest clips image bounds to the viewport; whole screenshots remain required for content-position acceptance.
          await delegator.print(`ReaderCropZoom before=${JSON.stringify(zoomBounds)} after=${JSON.stringify(restored)}`)
          expect(Math.abs(restored.left - zoomBounds.left) <= 2 && Math.abs(restored.top - zoomBounds.top) <= 2 &&
            Math.abs(restored.right - zoomBounds.right) <= 2 && Math.abs(restored.bottom - zoomBounds.bottom) <= 2).assertTrue()
        }
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await driver.delayMs(800); await captureInformation(driver, 'closed')
      })
    })
    return
  }
  if ((trial === 'ReaderCropTrial' || trial === 'ReaderCropSpreadTrial' || trial === 'ReaderCropContinuousTrial') &&
    typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('standaloneBodyCropKeepsSourcePageAndCloses', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const spreadCrop = trial === 'ReaderCropSpreadTrial', continuousCrop = trial === 'ReaderCropContinuousTrial'
        const layoutTrial = spreadCrop || continuousCrop
        let sourceIndex = layoutTrial ? 4 : 3
        const open = async (crop: boolean): Promise<void> => {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: `${sourceIndex}`, readerLabChrome: 'true', readerLabVolumeKeys: layoutTrial ? 'true' : 'false',
              readerLabCropBorders: crop ? 'true' : 'false' } })
          await informationReady(driver)
          if (layoutTrial) {
            await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
            await driver.delayMs(300)
            await (await driver.findComponent(ON.text(spreadCrop ? '双页' : '连续'))).click()
            await driver.delayMs(600); await informationReady(driver)
          }
          expect(await informationPage(driver)).assertEqual(sourceIndex + 1)
        }
        let selected = layoutTrial
        for (; !selected && sourceIndex < 8; sourceIndex++) {
          await open(true)
          for (let attempt = 0; attempt < 20; attempt++) {
            if (await driver.findComponent(ON.id(`rkit-cropped-image-${sourceIndex}-whole`)) !== null) { selected = true; break }
            await driver.delayMs(250)
          }
          await delegator.print(`ReaderCrop discovery page=${sourceIndex + 1} detected=${selected}`)
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(800)
          if (selected) break
        }
        expect(selected).assertTrue()
        await open(false)
        await captureInformation(driver, 'baseline')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await driver.delayMs(800)
        await open(true)
        let cropped = false
        for (let attempt = 0; attempt < 40; attempt++) {
          if (await driver.findComponent(ON.id(`rkit-cropped-image-${sourceIndex}-whole`)) !== null) { cropped = true; break }
          await driver.delayMs(250)
        }
        await captureInformation(driver, cropped ? 'changed' : 'exception')
        await delegator.print(`ReaderCrop sample=${sourceIndex + 1} detected=${cropped}`)
        expect(cropped).assertTrue()
        expect(await informationPage(driver)).assertEqual(sourceIndex + 1)
        if (spreadCrop) {
          await driver.triggerKey(KeyCode.KEYCODE_VOLUME_DOWN); await driver.delayMs(700); await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(7)
          await captureInformation(driver, 'next')
          await driver.triggerKey(KeyCode.KEYCODE_VOLUME_UP); await driver.delayMs(700); await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(5)
          await captureInformation(driver, 'returned')
        } else if (continuousCrop) {
          const ability = await delegator.getCurrentTopAbility(), win = await window.getLastWindow(ability.context)
          const utils = win.getUIContext().getComponentUtils()
          const beforeHeight = utils.getRectangleById('rkit-continuous-page-4').size.height
          const list = await (await driver.findComponent(ON.id('rkit-continuous-list'))).getBounds()
          const x = Math.round((list.left + list.right) / 2)
          for (let i = 0; i < 12 && await informationPage(driver) < 9; i++) {
            await driver.swipe(x, Math.round(list.top + (list.bottom - list.top) * .8),
              x, Math.round(list.top + (list.bottom - list.top) * .2), 900)
            await driver.delayMs(600)
          }
          expect(await informationPage(driver) >= 9).assertTrue()
          await captureInformation(driver, 'next')
          for (let i = 0; i < 12 && await informationPage(driver) > 5; i++) {
            await driver.triggerKey(KeyCode.KEYCODE_VOLUME_UP); await driver.delayMs(700)
          }
          await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(5)
          const afterHeight = utils.getRectangleById('rkit-continuous-page-4').size.height
          await delegator.print(`ReaderCrop continuous rowBefore=${beforeHeight} rowAfter=${afterHeight}`)
          expect(Math.abs(beforeHeight - afterHeight) <= 1).assertTrue()
          await captureInformation(driver, 'returned')
        }
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await driver.delayMs(800)
        await captureInformation(driver, 'closed')
      })
    })
    return
  }
  if (trial === 'ReaderKeepScreenOnTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('foregroundReadingOwnsKeepAwakeAndReleasesOnBackgroundAndClose', 0, async (): Promise<void> => {
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
        await driver.delayMs(1000)
        const ability = await delegator.getCurrentTopAbility()
        const mainWindow = await window.getLastWindow(ability.context)
        const before = mainWindow.getWindowProperties().isKeepScreenOn
        const setting = connectReadMode().keepScreenOn
        await delegator.print(`ReaderKeepScreenOn before=${before} setting=${setting}`)
        expect(setting).assertTrue()
        const verify = async (label: string, expected: boolean): Promise<void> => {
          for (let i = 0; i < 30; i++) {
            if (mainWindow.getWindowProperties().isKeepScreenOn === expected) break
            await driver.delayMs(100)
          }
          const value = mainWindow.getWindowProperties().isKeepScreenOn
          await delegator.print(`ReaderKeepScreenOn ${label}=${value}`)
          expect(value).assertEqual(expected)
        }
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
            readerLabPage: '1', readerLabChrome: 'true' } })
        await informationReady(driver); await verify('shown', true)
        await delegator.doAbilityBackground(ability); await verify('background', before)
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
        await informationReady(driver); await verify('resumed', true)
        expect(await informationPage(driver)).assertEqual(2)
        await captureInformation(driver, 'returned')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await verify('closed', before)
        expect(connectReadMode().keepScreenOn).assertEqual(setting)
      })
    })
    return
  }
  if ((trial === 'ReaderSpreadShiftTrial' || trial === 'ReaderSpreadShiftLastTrial') && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('rtlSpreadRePairsOnePageThenTurnsWithinTheNewPairing', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const last = trial === 'ReaderSpreadShiftLastTrial'
        try {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: last ? '44' : '1', readerLabChrome: 'true', readerLabVolumeKeys: 'true' } })
          await informationReady(driver)
          expect(await driver.findComponent(ON.id('rkit-shift-spread'))).assertNull()
          await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
          await driver.delayMs(400)
          await (await driver.findComponent(ON.text('右→左'))).click()
          await driver.delayMs(400)
          await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
          await informationReady(driver)
          await captureInformation(driver, 'baseline')
          await (await driver.findComponent(ON.id('rkit-shift-spread'))).click()
          await driver.delayMs(500); await informationReady(driver)
          if (last) {
            expect(await informationPage(driver)).assertEqual(46)
            expect(await (await driver.findComponent(ON.id('rkit-shift-spread'))).isEnabled()).assertFalse()
            await captureInformation(driver, 'changed')
            await driver.triggerKey(KeyCode.KEYCODE_VOLUME_DOWN); await driver.delayMs(600)
            expect(await informationPage(driver)).assertEqual(46)
            await (await driver.findComponent(ON.id('rkit-close'))).click()
            await driver.delayMs(700)
            expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
            await captureInformation(driver, 'closed')
            return
          }
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, 'changed')
          await openInformationMenu(driver)
          expect(await driver.findComponent(ON.id('rkit-info-source-1')) !== null).assertTrue()
          expect(await driver.findComponent(ON.id('rkit-info-source-2')) !== null).assertTrue()
          expect(await driver.findComponent(ON.id('rkit-info-source-0'))).assertNull()
          await driver.triggerKey(KeyCode.KEYCODE_BACK); await driver.delayMs(600)
          await driver.triggerKey(KeyCode.KEYCODE_VOLUME_DOWN)
          await driver.delayMs(700); await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(4)
          await captureInformation(driver, 'next')
          await driver.triggerKey(KeyCode.KEYCODE_VOLUME_UP)
          await driver.delayMs(700); await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, 'returned')
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          await captureInformation(driver, 'closed')
        } catch (error) {
          await captureInformation(driver, 'exception')
          throw error as Error
        }
      })
    })
    return
  }
  if (trial === 'ReaderStandaloneStatusTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('observesStandaloneWindowOwnerWithoutChangingProperties', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
            readerLabPage: '1', readerLabChrome: 'true' } })
        await informationReady(driver)
        const ability = await delegator.getCurrentTopAbility()
        const mainWindow = await window.getLastWindow(ability.context)
        await delegator.print(`ReaderStandaloneStatus shown properties=${JSON.stringify(mainWindow.getWindowSystemBarProperties())} events=${JSON.stringify(ReaderTrialEntryProbe.read().windowEvents)}`)
        await captureInformation(driver, 'original-baseline')
        if (args['-s statusIconProbe'] === 'true' || args['-s statusIconProbe'] === 'content') {
          if (args['-s statusIconProbe'] === 'content') {
            await mainWindow.setWindowSystemBarProperties({ statusBarContentColor: '#FFFFFFFF' })
          } else {
            await mainWindow.setWindowSystemBarProperties({ isStatusBarLightIcon: true })
          }
          await driver.delayMs(500)
          await delegator.print(`ReaderStandaloneStatus iconOnly properties=${JSON.stringify(mainWindow.getWindowSystemBarProperties())}`)
          await captureInformation(driver, 'original-recovered')
        }
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await driver.delayMs(700)
        expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
        await delegator.print(`ReaderStandaloneStatus closed properties=${JSON.stringify(mainWindow.getWindowSystemBarProperties())} events=${JSON.stringify(ReaderTrialEntryProbe.read().windowEvents)}`)
        await captureInformation(driver, 'original-closed')
      })
    })
    return
  }
  if ((trial === 'ReaderOriginalPrepareFailureTrial' || trial === 'ReaderOriginalDecodeFailureTrial') &&
    typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('originalFailurePreservesItsResolutionBoundaryAndRetryVariant', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const prepareFailure = trial === 'ReaderOriginalPrepareFailureTrial'
        try {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: '1', readerLabChrome: 'true',
              readerLabOriginalVariantProbe: prepareFailure ? 'prepare-fail-once' : 'decode-fail-once' } })
          await informationReady(driver)
          await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          if (prepareFailure) {
            await informationReady(driver)
            expect(await driver.findComponent(ON.id('rkit-failure-page-2'))).assertNull()
            await openInformationMenu(driver)
            await assertInformation(driver, 2, 'original-prepare-retained', '可用', '重采样图片')
            await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          } else {
            let failed = false
            for (let attempt = 0; attempt < 40; attempt++) {
              if (await driver.findComponent(ON.id('rkit-failure-page-2')) !== null) { failed = true; break }
              await driver.delayMs(250)
            }
            expect(failed).assertTrue()
            expect(await informationPage(driver)).assertEqual(2)
            await captureInformation(driver, 'original-decode-failed')
            await (await driver.findComponent(ON.id('rkit-retry-page-2'))).click()
          }
          await informationReady(driver)
          expect(await driver.findComponent(ON.id('rkit-failure-page-2'))).assertNull()
          await openInformationMenu(driver)
          await assertInformation(driver, 2, 'original-recovered', '可用', '原图')
          expect(await informationPage(driver)).assertEqual(2)
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          await captureInformation(driver, 'original-closed')
        } catch (error) {
          await captureInformation(driver, 'exception'); throw error as Error
        } finally {
          if (await driver.findComponent(ON.type('AlertDialog')) !== null) await driver.pressBack()
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
        }
      })
    })
    return
  }
  if (trial === 'ReaderOriginalSpreadTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('rtlVisualSidesAndBatchRetainIndependentVariantsAndPosition', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        try {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: '1', readerLabChrome: 'true' } })
          await informationReady(driver)
          await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
          await driver.delayMs(400)
          await (await driver.findComponent(ON.text('右→左'))).click()
          await driver.delayMs(400)
          await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
          await informationReady(driver)
          // Reflow preserves the selected source P2, not the spread's first source P1.
          expect(await informationPage(driver)).assertEqual(2)
          await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          let ready = false
          for (let attempt = 0; attempt < 60; attempt++) {
            const left = await driver.findComponent(ON.id('rkit-original-source-1'))
            const right = await driver.findComponent(ON.id('rkit-original-source-0'))
            if (left !== null && right !== null && await left.isEnabled() && await right.isEnabled()) {
              expect((await left.getText()).indexOf('2') >= 0).assertTrue()
              expect((await right.getText()).indexOf('1') >= 0).assertTrue()
              ready = true; break
            }
            await driver.delayMs(500)
          }
          expect(ready).assertTrue()
          await captureInformation(driver, 'original-spread-menu')
          await (await driver.findComponent(ON.id('rkit-original-source-1'))).click()
          await assertSpreadVariant(driver, 1, 'original-spread-left', '原图')
          await assertSpreadVariant(driver, 0, 'original-spread-right', '重采样图片')
          expect(await informationPage(driver)).assertEqual(2)
          await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          await driver.delayMs(400)
          await captureInformation(driver, 'original-spread-mixed')
          await (await driver.findComponent(ON.id('rkit-original-both'))).click()
          await assertSpreadVariant(driver, 0, 'original-both-right', '原图')
          await assertSpreadVariant(driver, 1, 'original-both-left', '原图')
          await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          await driver.delayMs(400)
          await (await driver.findComponent(ON.id('rkit-original-both'))).click()
          await assertSpreadVariant(driver, 0, 'original-default-right', '重采样图片')
          await assertSpreadVariant(driver, 1, 'original-default-left', '重采样图片')
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, 'original-off')
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          await captureInformation(driver, 'original-closed')
        } catch (error) {
          await captureInformation(driver, 'exception'); throw error as Error
        } finally {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
        }
      })
    })
    return
  }
  if (trial === 'ReaderOriginalSingleTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('singlePageSwitchesOriginalAndBackWithoutChangingPosition', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
        try {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: '1', readerLabChrome: 'true' } })
          await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(2)
          const action = await driver.findComponent(ON.id('rkit-original-image'))
          expect(action !== null && await action.isEnabled()).assertTrue()
          await captureInformation(driver, 'original-baseline')
          await action.click()
          await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, 'original-on')
          await openInformationMenu(driver)
          await assertInformation(driver, 2, 'original-info', '可用', '原图')
          await (await driver.findComponent(ON.id('rkit-original-image'))).click()
          await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, 'original-off')
          await openInformationMenu(driver)
          await assertInformation(driver, 2, 'original-off-info', '可用', '重采样图片')
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          await captureInformation(driver, 'original-closed')
        } catch (error) {
          await captureInformation(driver, 'exception')
          throw error as Error
        } finally {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
        }
      })
    })
    return
  }
  if (trial === 'ReaderInformationAvailabilityTrial' && typeof work === 'string' && work.length > 0) {
    describe(trial, (): void => {
      it('samePageRetainsOriginalAvailabilityAcrossFreshTrialSessions', 0, async (): Promise<void> => {
        clearInformationCaptures()
        const driver = Driver.create()
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const expected = args['-s readerLabExpectedOriginal']
        expect(typeof expected === 'string' && expected.length > 0).assertTrue()
        for (let visit = 0; visit < 2; visit++) {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
            parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
              readerLabPage: '1', readerLabChrome: 'true' } })
          await driver.delayMs(1500); await informationReady(driver)
          expect(await informationPage(driver)).assertEqual(2)
          await captureInformation(driver, visit === 0 ? 'baseline' : 'recovery-baseline')
          await openInformationMenu(driver)
          await assertInformation(driver, 2, visit === 0 ? 'single' : 'recovery-info',
            typeof expected === 'string' ? expected : '')
          expect(await informationPage(driver)).assertEqual(2)
          await (await driver.findComponent(ON.id('rkit-close'))).click()
          await driver.delayMs(700)
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          await captureInformation(driver, visit === 0 ? 'closed' : 'recovery-closed')
        }
      })
    })
    return
  }
  if (typeof work === 'string' && work.length > 0 &&
    (trial === 'ReaderInformationFailureTrial' || trial === 'ReaderInformationPageCancelTrial' ||
      trial === 'ReaderInformationCloseCancelTrial' || trial === 'ReaderInformationBackgroundTrial')) {
    describe(trial, (): void => {
      it('metadataFailureOrLateResultDoesNotBreakReadingOrFreshInformation', 0, async (): Promise<void> => {
        await informationRecoveryTrial(work, typeof unit === 'string' ? unit : '',
          trial === 'ReaderInformationFailureTrial' ? 'failure' : trial === 'ReaderInformationPageCancelTrial' ? 'page' :
            trial === 'ReaderInformationCloseCancelTrial' ? 'close' : 'background')
      })
    })
    return
  }
  if (args['-s class'] !== 'ReaderImageInformationTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderImageInformationTrial', (): void => {
    it('actualFileInformationKeepsSingleAndBothSpreadSourceIdentities', 0, async (): Promise<void> => {
      clearInformationCaptures()
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabPage: '1', readerLabChrome: 'true', readerLabVolumeKeys: 'true' } })
      await driver.delayMs(1500); await informationReady(driver)
      await captureInformation(driver, 'baseline')
      await openInformationMenu(driver)
      await assertInformation(driver, 2, 'single')
      await captureInformation(driver, 'single-return')
      await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
      await driver.delayMs(700); await informationReady(driver)
      await captureInformation(driver, 'spread')
      await openInformationMenu(driver)
      await captureInformation(driver, 'choice')
      await (await driver.findComponent(ON.id('rkit-info-source-0'))).click()
      await assertInformation(driver, 1, 'left')
      await openInformationMenu(driver)
      await (await driver.findComponent(ON.id('rkit-info-source-1'))).click()
      await assertInformation(driver, 2, 'right')
      await captureInformation(driver, 'returned')
      await driver.triggerKey(KeyCode.KEYCODE_VOLUME_DOWN)
      await driver.delayMs(700); await informationReady(driver)
      expect((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).trim().startsWith('3 /')).assertTrue()
      await captureInformation(driver, 'next')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureInformation(driver, 'closed')
    })
  })
}
