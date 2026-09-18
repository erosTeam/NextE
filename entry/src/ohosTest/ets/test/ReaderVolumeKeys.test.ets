import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON, PointerMatrix } from '@kit.TestKit'
import { KeyCode } from '@kit.InputKit'
import { audio } from '@kit.AudioKit'
import { fileIo } from '@kit.CoreFileKit'
import { preferences } from '@kit.ArkData'
import { ReadModeSettings, StorageKeys, connectReadMode } from 'shared'

async function captureVolume(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  const layout = `${cache}/rkit-volume-${name}.json`
  const screen = `${cache}/rkit-volume-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  if (typeof driver.dumpLayout === 'function') {
    expect(await driver.dumpLayout(layout)).assertTrue()
  } else {
    // Driver.dumpLayout starts at API 26; older devices retain the uitest CLI.
    const result = await abilityDelegatorRegistry.getAbilityDelegator().executeShellCommand(
      `uitest dumpLayout -p /data/local/tmp/rkit-volume-${name}.json`, 15)
    expect(result.exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(screen)).assertTrue()
}
async function volumePage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}
async function volumeKey(driver: Driver, key: number, page: number): Promise<void> {
  await driver.triggerKey(key)
  await driver.delayMs(650)
  const actual = await volumePage(driver)
  if (actual !== page) await captureVolume(driver, 'exception')
  expect(actual).assertEqual(page)
}
async function volumeImage(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(500)
  }
  expect(false).assertTrue()
}


async function volumeReleaseTrial(work: string, unit: string): Promise<void> {
  const driver = Driver.create()
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const manager = audio.getAudioManager().getVolumeManager()
  const usage = audio.StreamUsage.STREAM_USAGE_MUSIC
  const baseline = manager.getVolumeByStream(usage)
  await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
    parameters: { readerLabWork: work, readerLabUnit: unit,
      readerLabChrome: 'true', readerLabVolumeKeys: 'true' } })
  await driver.delayMs(1800); await volumeImage(driver)
  await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 2)
  expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
  await (await driver.findComponent(ON.id('rkit-close'))).click()
  await driver.delayMs(700)
  expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
  await captureVolume(driver, 'release-host')
  const increase = baseline < manager.getMaxVolumeByStream(usage)
  const key = increase ? KeyCode.KEYCODE_VOLUME_UP : KeyCode.KEYCODE_VOLUME_DOWN
  const inverse = increase ? KeyCode.KEYCODE_VOLUME_DOWN : KeyCode.KEYCODE_VOLUME_UP
  try {
    await driver.triggerKey(key); await driver.delayMs(500)
    const changed = manager.getVolumeByStream(usage)
    console.info(`[ReaderVolumeRelease] before=${baseline} after=${changed} increase=${increase}`)
    await captureVolume(driver, 'release-system')
    expect(changed).assertEqual(baseline + (increase ? 1 : -1))
  } finally {
    if (manager.getVolumeByStream(usage) !== baseline) {
      await driver.triggerKey(inverse); await driver.delayMs(500)
    }
    console.info(`[ReaderVolumeRelease] restored=${manager.getVolumeByStream(usage)} expected=${baseline}`)
    expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
    await driver.delayMs(2200)
    await captureVolume(driver, 'release-restored')
  }
}

/** System key injection through Driver, not a claim of human physical-key input. */
async function volumePreferenceTrial(work: string, unit: string): Promise<void> {
  const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
  await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
  // Await the existing startup publication before snapshotting or changing this preference.
  for (let attempt = 0; attempt < 30 && !connectReadMode().volumeKeyTurnReady; attempt++) {
    await driver.delayMs(500)
  }
  expect(connectReadMode().volumeKeyTurnReady).assertTrue()
  const context = (await delegator.getCurrentTopAbility()).context
  const store = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
  const originalPresent = store.hasSync(StorageKeys.READING_VOLUME_KEY)
  const original = store.getSync(StorageKeys.READING_VOLUME_KEY, false) as boolean
  const originalLive = connectReadMode().volumeKeyTurn
  const originalReady = connectReadMode().volumeKeyTurnReady
  const manager = audio.getAudioManager().getVolumeManager()
  const usage = audio.StreamUsage.STREAM_USAGE_MUSIC
  const baseline = manager.getVolumeByStream(usage)
  console.info(`[ReaderVolumePreference] baseline preference=${original} volume=${baseline}`)
  try {
    for (let caseIndex = 0; caseIndex < 4; caseIndex++) {
      const preference = caseIndex < 2
      const explicit = caseIndex % 2 === 1
      const enabled = explicit ? !preference : preference
      await ReadModeSettings.setVolumeKeyTurn(context, preference)
      expect(store.getSync(StorageKeys.READING_VOLUME_KEY, false) as boolean).assertEqual(preference)
      if (explicit) {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1',
            readerLabChrome: 'true', readerLabVolumeKeys: enabled ? 'true' : 'false' } })
      } else {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '1', readerLabChrome: 'true' } })
      }
      await driver.delayMs(1800); await volumeImage(driver)
      const status = await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()
      expect(Number(status.split('/')[1].trim()) >= 3).assertTrue()
      expect(await volumePage(driver)).assertEqual(2)
      if (enabled) {
        await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 3)
        expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
        await volumeKey(driver, KeyCode.KEYCODE_VOLUME_UP, 2)
        expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
      } else {
        const increase = baseline < manager.getMaxVolumeByStream(usage)
        try {
          await volumeKey(driver, increase ? KeyCode.KEYCODE_VOLUME_UP : KeyCode.KEYCODE_VOLUME_DOWN, 2)
          expect(manager.getVolumeByStream(usage)).assertEqual(baseline + (increase ? 1 : -1))
        } finally {
          if (manager.getVolumeByStream(usage) !== baseline) {
            await driver.triggerKey(increase ? KeyCode.KEYCODE_VOLUME_DOWN : KeyCode.KEYCODE_VOLUME_UP)
            await driver.delayMs(500)
          }
        }
        expect(await volumePage(driver)).assertEqual(2)
        expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
      }
      await captureVolume(driver, `preference-${caseIndex}-endpoint`)
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      // Same release proof as volumeReleaseTrial: the next system key changes music volume.
      const increase = baseline < manager.getMaxVolumeByStream(usage)
      try {
        await driver.triggerKey(increase ? KeyCode.KEYCODE_VOLUME_UP : KeyCode.KEYCODE_VOLUME_DOWN)
        await driver.delayMs(500)
        expect(manager.getVolumeByStream(usage)).assertEqual(baseline + (increase ? 1 : -1))
      } finally {
        if (manager.getVolumeByStream(usage) !== baseline) {
          await driver.triggerKey(increase ? KeyCode.KEYCODE_VOLUME_DOWN : KeyCode.KEYCODE_VOLUME_UP)
          await driver.delayMs(500)
        }
      }
      expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
      console.info(`[ReaderVolumePreference] case=${caseIndex} preference=${preference} explicit=${explicit} enabled=${enabled} release=passed`)
    }
  } catch (error) {
    console.error(`[ReaderVolumePreference] failure=${(error as Error).message}`)
    try {
      await captureVolume(driver, 'preference-exception')
    } catch (captureError) {
      console.error(`[ReaderVolumePreference] capture_failure=${(captureError as Error).message}`)
    }
    throw error as Error
  } finally {
    let trialExited = false
    try {
      const close = await driver.findComponent(ON.id('rkit-close'))
      if (close !== null) { await close.click(); await driver.delayMs(700) }
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      trialExited = true
    } finally {
      try {
        await ReadModeSettings.setVolumeKeyTurn(context, original)
        expect(store.getSync(StorageKeys.READING_VOLUME_KEY, false) as boolean).assertEqual(original)
        if (!originalPresent) { store.deleteSync(StorageKeys.READING_VOLUME_KEY); store.flushSync() }
        expect(store.hasSync(StorageKeys.READING_VOLUME_KEY)).assertEqual(originalPresent)
      } finally {
        connectReadMode().volumeKeyTurn = originalLive
        connectReadMode().volumeKeyTurnReady = originalReady
        // Do not inject compensation into an unconfirmed reader route.
        if (trialExited) {
          for (let attempt = 0; attempt < 3 && manager.getVolumeByStream(usage) !== baseline; attempt++) {
            await driver.triggerKey(manager.getVolumeByStream(usage) < baseline ?
              KeyCode.KEYCODE_VOLUME_UP : KeyCode.KEYCODE_VOLUME_DOWN)
            await driver.delayMs(500)
          }
          expect(manager.getVolumeByStream(usage)).assertEqual(baseline)
        } else {
          console.error('[ReaderVolumePreference] trial_exit_unconfirmed volume_recovery_pending')
        }
        expect(connectReadMode().volumeKeyTurn).assertEqual(originalLive)
        expect(connectReadMode().volumeKeyTurnReady).assertEqual(originalReady)
        if (trialExited) console.info(`[ReaderVolumePreference] restored preference=${store.getSync(StorageKeys.READING_VOLUME_KEY, false) as boolean} volume=${manager.getVolumeByStream(usage)} originalPreference=${original} originalPresent=${originalPresent} originalLive=${originalLive} originalReady=${originalReady} originalVolume=${baseline}`)
      }
    }
  }
}

export default function readerVolumeKeysTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] === 'ReaderVolumePreferenceTrial' && typeof work === 'string' && work.length > 0) {
    describe('ReaderVolumePreferenceTrial', (): void => {
      it('preferenceAndExplicitOverrideRespectSystemVolumeAndRestore', 0, async (): Promise<void> => {
        await volumePreferenceTrial(work, typeof unit === 'string' ? unit : '')
      })
    })
    return
  }
  if (args['-s class'] === 'ReaderVolumeReleaseTrial' && typeof work === 'string' && work.length > 0) {
    describe('ReaderVolumeReleaseTrial', (): void => {
      it('closeReturnsRealSystemVolumeAndRestoresBaseline', 0, async (): Promise<void> => {
        await volumeReleaseTrial(work, typeof unit === 'string' ? unit : '')
      })
    })
    return
  }
  if (args['-s class'] !== 'ReaderVolumeKeysTrial' || typeof work !== 'string' || work.length === 0) return
  describe('ReaderVolumeKeysTrial', (): void => {
    it('logicalKeysRespectZoomMenuAndRouteLifecycle', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabChrome: 'true', readerLabVolumeKeys: 'true', readerLabEntryDirection: 'ltr',
          readerLabEntryLayout: 'single' } })
      await driver.delayMs(1800); await volumeImage(driver)
      expect(await volumePage(driver)).assertEqual(1)
      await captureVolume(driver, 'baseline')
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 2)
      await volumeImage(driver); await captureVolume(driver, 'next')
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 2)
      await (await driver.findComponent(ON.text('右→左'))).click()
      await driver.delayMs(600)
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 3)
      await volumeImage(driver); await captureVolume(driver, 'rtl-next')
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_UP, 2)
      await volumeImage(driver)
      const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
      const x = Math.round((viewport.left + viewport.right) / 2)
      const y = Math.round((viewport.top + viewport.bottom) / 2)
      const original = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      await driver.doubleClick(x, y); await driver.delayMs(500)
      const zoomed = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      expect(zoomed.right - zoomed.left > original.right - original.left ||
        zoomed.bottom - zoomed.top > original.bottom - original.top).assertTrue()
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 2)
      await captureVolume(driver, 'zoom-blocked')
      // Double-tap cycles fit -> 2x -> native -> fit; it is not a universal reset.
      const points = PointerMatrix.create(2, 12)
      for (let step = 0; step < 12; step++) {
        const distance = (viewport.right - viewport.left) * (0.36 - 0.29 * step / 11)
        points.setPoint(0, step, { x: Math.round(x - distance), y })
        points.setPoint(1, step, { x: Math.round(x + distance), y })
      }
      expect(await driver.injectMultiPointerAction(points, 600)).assertTrue()
      await driver.delayMs(500)
      const reset = await (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))).getBounds()
      expect(Math.abs(reset.right - reset.left - (original.right - original.left)) <= 2).assertTrue()
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 3)
      await volumeImage(driver); await captureVolume(driver, 'reset-next')
      await (await driver.findComponent(ON.id('rkit-runtime-settings'))).click()
      await (await driver.findComponent(ON.text('连续'))).click()
      await driver.delayMs(1000)
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, 4)
      await captureVolume(driver, 'continuous-next')
      // NextE closes the shared reader route when the app backgrounds (its own
      // ReaderLifecycleRecoveryTrial and ReaderInformationBackgroundTrial assert that), so returning
      // to reading requires a fresh explicit entry; volume-key turning must re-arm on that new route.
      const ability = await delegator.getCurrentTopAbility()
      try {
        await delegator.doAbilityBackground(ability); await driver.delayMs(500)
        expect(delegator.getAbilityState(ability)).assertEqual(abilityDelegatorRegistry.AbilityLifecycleState.BACKGROUND)
        await captureVolume(driver, 'background')
      } finally {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      }
      // NextE retires the shared reader route on background (asserted by ReaderLifecycleRecoveryTrial
      // and ReaderInformationBackgroundTrial); the plain relaunch must show no live reader chrome.
      let retired = false
      for (let attempt = 0; attempt < 40; attempt++) {
        if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null) { retired = true; break }
        await driver.delayMs(250)
      }
      expect(retired).assertTrue()
      await captureVolume(driver, 'background-retired')
      // A fresh explicit entry re-arms volume-key turning on the new route.
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
          readerLabChrome: 'true', readerLabVolumeKeys: 'true', readerLabEntryDirection: 'ltr',
          readerLabEntryLayout: 'single' } })
      await driver.delayMs(1800); await volumeImage(driver)
      const reentered = await volumePage(driver)
      // Assert the transition, not a fixed page: the fresh route may resume a stored position.
      await volumeKey(driver, KeyCode.KEYCODE_VOLUME_DOWN, reentered + 1)
      await volumeImage(driver); await captureVolume(driver, 'reentered-next')
      await (await driver.findComponent(ON.id('rkit-close'))).click()
      await driver.delayMs(700)
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      await captureVolume(driver, 'closed')
    })
  })
}
