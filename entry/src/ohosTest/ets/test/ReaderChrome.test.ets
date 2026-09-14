import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, MatchPattern, ON, PointerMatrix } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { connectNextEReaderLabContextProbe } from 'reader'

const CHROME_CAPTURE_PREFIX: string = 'rkit-chrome-'

function clearChromeCaptures(names: string[]): void {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  for (const name of names) {
    const layout = `${cache}/${CHROME_CAPTURE_PREFIX}${name}.json`
    const screen = `${cache}/${CHROME_CAPTURE_PREFIX}${name}.png`
    if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
    if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  }
}

async function waitChromeId(driver: Driver, id: string): Promise<Component> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const found = await driver.findComponent(ON.id(id))
    if (found !== null) return found
    await driver.delayMs(250)
  }
  const menuItems = await driver.findComponents(ON.type('MenuItem'))
  const visible: string[] = []
  if (menuItems !== null) {
    for (const item of menuItems) {
      visible.push(`${await item.getId()}:${await item.getText()}:${await item.isEnabled() ? 'enabled' : 'disabled'}`)
    }
  }
  throw new Error(`Reader endpoint did not appear: ${id}; menuItems=${visible.join('|')}`)
}

async function waitChromeEnabled(driver: Driver, id: string): Promise<Component> {
  for (let attempt = 0; attempt < 60; attempt++) {
    const found = await driver.findComponent(ON.id(id))
    if (found !== null && await found.isEnabled()) return found
    await driver.delayMs(250)
  }
  const states: string[] = []
  for (const probeId of ['rkit-runtime-settings', 'rkit-host-settings', 'rkit-toggle-spread',
    'rkit-share-image', 'rkit-original-image', 'rkit-more']) {
    const probe = await driver.findComponent(ON.id(probeId))
    states.push(`${probeId}=${probe === null ? 'absent' : await probe.isEnabled() ? 'enabled' : 'disabled'}`)
  }
  const activity = await driver.findComponent(ON.id('rkit-host-activity'))
  const host = activity === null ? 'host=absent' : `host=${await activity.getText()}`
  await captureChrome(driver, 'enabled-timeout')
  throw new Error(`Reader endpoint did not become enabled: ${id}; ${host}; ${states.join(',')}`)
}

async function waitChromePattern(driver: Driver, pattern: string, count: number): Promise<Component[]> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const found = await driver.findComponents(ON.id(pattern, MatchPattern.REG_EXP))
    if (found !== null && found.length === count) return found
    await driver.delayMs(250)
  }
  throw new Error(`Reader endpoints did not appear: ${pattern} count=${count}`)
}

async function waitChromeGone(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 60; attempt++) {
    if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
      await driver.findComponent(ON.id('rkit-reading-surface')) === null &&
      await driver.findComponent(ON.id('rkit-phase')) === null) return
    await driver.delayMs(250)
  }
  throw new Error('Reader trial did not close')
}

async function closeChromeTrial(driver: Driver): Promise<void> {
  if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
    await driver.findComponent(ON.id('rkit-reading-surface')) === null &&
    await driver.findComponent(ON.id('rkit-phase')) === null) return
  if (await driver.findComponent(ON.type('Menu')) !== null) {
    await driver.pressBack()
    await driver.delayMs(300)
  }
  let close = await driver.findComponent(ON.id('rkit-close'))
  if (close === null) {
    await driver.pressBack()
    await driver.delayMs(300)
    close = await driver.findComponent(ON.id('rkit-close'))
  }
  if (close !== null) await close.click()
  else await driver.pressBack()
  await waitChromeGone(driver)
}

async function bestEffortCloseChromeTrial(driver: Driver): Promise<void> {
  try {
    await closeChromeTrial(driver)
  } catch (_) {}
}

async function startFreshChromeTrial(driver: Driver, work: string, unit: string,
  failurePage: number = -1, pageIndex: number = 0, entryLayout: string = 'single'): Promise<void> {
  let mounted = false
  const probe = connectNextEReaderLabContextProbe()
  const epoch = probe.arm(work, (): void => { mounted = true })
  try {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator()
    await delegator.startAbility({
      bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
        readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true', readerLabVolumeKeys: 'false',
        readerLabFailPage: String(failurePage), readerLabPage: String(pageIndex),
        readerLabEntryLayout: entryLayout,
      },
    })
    for (let attempt = 0; attempt < 80; attempt++) {
      let privacyAgree = await driver.findComponent(ON.id('Paf.Permission.button_confirm').clickable())
      if (privacyAgree === null) privacyAgree = await driver.findComponent(ON.text('同意').clickable())
      if (privacyAgree !== null && await privacyAgree.isEnabled()) {
        await privacyAgree.click()
        await driver.delayMs(500)
      }
      if (mounted && await driver.findComponent(ON.id('rkit-trial-navigation')) !== null) {
        try {
          const ability = await delegator.getCurrentTopAbility()
          if (delegator.getAbilityState(ability) !== abilityDelegatorRegistry.AbilityLifecycleState.FOREGROUND) {
            await delegator.doAbilityForeground(ability)
          }
          if (delegator.getAbilityState(ability) === abilityDelegatorRegistry.AbilityLifecycleState.FOREGROUND) return
        } catch (_) {}
      }
      await driver.delayMs(250)
    }
    throw new Error('Fresh Reader trial mount did not appear')
  } finally {
    if (!mounted) probe.cancel(epoch)
  }
}

async function captureChrome(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/${CHROME_CAPTURE_PREFIX}${name}.json`
  const screen = `${cache}/${CHROME_CAPTURE_PREFIX}${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  expect(await driver.dumpLayout(layout)).assertTrue()
  expect(await driver.screenCap(screen)).assertTrue()
}

async function bestEffortCaptureChrome(driver: Driver, name: string): Promise<void> {
  try {
    await captureChrome(driver, name)
  } catch (_) {}
}


async function waitChromeImage(driver: Driver, owner: string): Promise<string> {
  for (let attempt = 0; attempt < 80; attempt++) {
    const images = await driver.findComponents(ON.type('Image').within(ON.id(owner)))
    if (images !== null && images.length === 1 &&
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
    if (images !== null && images.length === 1 &&
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

async function reloadOneExactSpreadSource(driver: Driver, capturePrefix: string): Promise<void> {
  const page = await chromePage(driver)
  const more = await waitChromeEnabled(driver, 'rkit-more')
  await more.click()
  await driver.delayMs(800)
  const reload = await waitChromeId(driver, 'rkit-reload-source-spread')
  await reload.click()
  const choices = await waitChromePattern(driver, '^rkit-reload-source-[0-9]+$', 2)
  expect(choices.length).assertEqual(2)
  const choiceId = await choices[0].getId()
  const choiceMatch = /^rkit-reload-source-([0-9]+)$/.exec(choiceId)
  expect(choiceMatch !== null).assertTrue()
  if (choiceMatch === null) throw new Error(`Unexpected reload choice id: ${choiceId}`)
  const targetSource = Number(choiceMatch[1])
  const parts = await driver.findComponents(
    ON.id('^rkit-part-[0-9]+-whole$', MatchPattern.REG_EXP).within(ON.id('rkit-image-viewport')),
  )
  expect(parts !== null).assertTrue()
  if (parts === null) throw new Error('Spread parts did not appear')
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
  await captureChrome(driver, `${capturePrefix}-choice`)
  await choices[0].click()
  const targetAfterId = await waitChromeImageGeneration(driver, targetOwner, targetBeforeId)
  expect(targetAfterId === targetBeforeId).assertFalse()
  expect(await waitChromeImage(driver, otherOwner)).assertEqual(otherBeforeId)
  const settledImages = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
  expect(settledImages !== null).assertTrue()
  if (settledImages === null) throw new Error('Spread images did not settle')
  expect(settledImages.length).assertEqual(2)
  expect(await chromePage(driver)).assertEqual(page)
  await captureChrome(driver, `${capturePrefix}-finished`)
}

/** This UI sequence runs only under an explicit named device protocol. */
export default function readerChromeTest(): void {
  readerHostSettingsTest()
  readerHostTranslationActionsTest()
  readerManualReloadTest()
  readerLifecycleRecoveryTest()
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
      clearChromeCaptures(['reload-source-menu', 'reload-source-finished', 'enabled-timeout'])
      await bestEffortCloseChromeTrial(driver)
      let bodyPassed = false
      try {
        await startFreshChromeTrial(driver, work, unit)
        const beforeId = await waitChromeImage(driver, 'rkit-image-viewport')
        expect(await chromePage(driver)).assertEqual(1)
        const more = await waitChromeEnabled(driver, 'rkit-more')
        await more.click()
        await driver.delayMs(800)
        await captureChrome(driver, 'reload-source-menu')
        const reload = await waitChromeId(driver, 'rkit-reload-source')
        await reload.click()
        const afterId = await waitChromeImageGeneration(driver, 'rkit-image-viewport', beforeId)
        expect(afterId === beforeId).assertFalse()
        expect(await chromePage(driver)).assertEqual(1)
        await captureChrome(driver, 'reload-source-finished')
        bodyPassed = true
      } finally {
        if (bodyPassed) await closeChromeTrial(driver)
        else await bestEffortCloseChromeTrial(driver)
      }
    })

    it('reloadsOneExactSpreadSource', 0, async (): Promise<void> => {
      const driver = Driver.create()
      clearChromeCaptures(['reload-spread-choice', 'reload-spread-finished'])
      await bestEffortCloseChromeTrial(driver)
      let bodyPassed = false
      try {
        await startFreshChromeTrial(driver, work, unit, -1, 1)
        await waitChromeImage(driver, 'rkit-image-viewport')
        await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
        await driver.delayMs(800)
        await reloadOneExactSpreadSource(driver, 'reload-spread')
        bodyPassed = true
      } finally {
        if (bodyPassed) await closeChromeTrial(driver)
        else await bestEffortCloseChromeTrial(driver)
      }
    })
  })
}

/** One real host chain proves body recovery and that both host departure paths allow a fresh Reader mount. */
function readerLifecycleRecoveryTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderLifecycleRecoveryTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderLifecycleRecoveryTrial', (): void => {
    it('retriesReloadsBackgroundClosesAndReopensFreshSessions', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      clearChromeCaptures(['lifecycle-failed', 'lifecycle-retried', 'lifecycle-reloaded',
        'lifecycle-spread-choice', 'lifecycle-spread-finished',
        'lifecycle-background-closed', 'lifecycle-reopened', 'lifecycle-explicit-closed',
        'lifecycle-reopened-again', 'lifecycle-final-closed', 'lifecycle-exception', 'enabled-timeout'])
      await bestEffortCloseChromeTrial(driver)
      let bodyPassed = false
      try {
        await startFreshChromeTrial(driver, work, unit, 1, 1)
        await waitChromeId(driver, 'rkit-failure-page-2')
        expect(await chromePage(driver)).assertEqual(2)
        await captureChrome(driver, 'lifecycle-failed')
        await (await waitChromeEnabled(driver, 'rkit-retry-page-2')).click()
        const retriedId = await waitChromeImage(driver, 'rkit-image-viewport')
        expect(await chromePage(driver)).assertEqual(2)
        await captureChrome(driver, 'lifecycle-retried')

        await (await waitChromeEnabled(driver, 'rkit-more')).click()
        await (await waitChromeId(driver, 'rkit-reload-source')).click()
        const reloadedId = await waitChromeImageGeneration(driver, 'rkit-image-viewport', retriedId)
        expect(reloadedId === retriedId).assertFalse()
        expect(await chromePage(driver)).assertEqual(2)
        await captureChrome(driver, 'lifecycle-reloaded')

        await (await waitChromeEnabled(driver, 'rkit-toggle-spread')).click()
        await driver.delayMs(800)
        await reloadOneExactSpreadSource(driver, 'lifecycle-spread')

        const ability = await delegator.getCurrentTopAbility()
        await delegator.doAbilityBackground(ability)
        let backgrounded = false
        for (let attempt = 0; attempt < 40; attempt++) {
          if (delegator.getAbilityState(ability) === abilityDelegatorRegistry.AbilityLifecycleState.BACKGROUND) {
            backgrounded = true
            break
          }
          await driver.delayMs(250)
        }
        expect(backgrounded).assertTrue()
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
        await waitChromeGone(driver)
        await captureChrome(driver, 'lifecycle-background-closed')

        await startFreshChromeTrial(driver, work, unit)
        await waitChromeImage(driver, 'rkit-image-viewport')
        expect(await chromePage(driver)).assertEqual(1)
        await captureChrome(driver, 'lifecycle-reopened')
        await closeChromeTrial(driver)
        await captureChrome(driver, 'lifecycle-explicit-closed')

        await startFreshChromeTrial(driver, work, unit)
        await waitChromeImage(driver, 'rkit-image-viewport')
        expect(await chromePage(driver)).assertEqual(1)
        await captureChrome(driver, 'lifecycle-reopened-again')
        await closeChromeTrial(driver)
        await captureChrome(driver, 'lifecycle-final-closed')
        bodyPassed = true
      } catch (error) {
        await bestEffortCaptureChrome(driver, 'lifecycle-exception')
        throw error as Error
      } finally {
        if (bodyPassed) await closeChromeTrial(driver)
        else await bestEffortCloseChromeTrial(driver)
      }
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
