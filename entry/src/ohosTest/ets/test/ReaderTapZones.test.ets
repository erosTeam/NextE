import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { window } from '@kit.ArkUI'
import { connectReadMode, connectGalleryReadProgress, connectSiteMode, ReadMode,
  ReaderTapZoneResolver } from 'shared'

function tapSignature(work: string): string {
  const state = connectReadMode()
  return JSON.stringify([state.mode, state.doublePageEnabled, state.spreadLayoutMode,
    state.tapZoneLayoutPaged, state.tapZoneInvertPaged, state.tapZoneLayoutContinuous,
    state.tapZoneInvertContinuous, connectSiteMode().isEx,
    connectGalleryReadProgress().getColumnMode(work), connectGalleryReadProgress().getEntry(work)])
}

async function tapWait(driver: Driver, id: string): Promise<void> {
  for (let n = 0; n < 60; n++) {
    if (await driver.findComponent(ON.id(id)) !== null) return
    await driver.delayMs(250)
  }
  throw new Error('tap_required_component_unavailable:' + id)
}

async function tapCapture(driver: Driver, name: string): Promise<void> {
  const d = abilityDelegatorRegistry.getAbilityDelegator()
  expect((await d.executeShellCommand('uitest dumpLayout -p /data/local/tmp/rkit-tap-' + name + '.json -a', 15)).exitCode).assertEqual(0)
  expect(await driver.screenCap(d.getAppContext().cacheDir + '/rkit-tap-' + name + '.png')).assertTrue()
}

async function tapBody(driver: Driver, sourceIndex: number): Promise<void> {
  for (let n = 0; n < 60; n++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id(`rkit-part-${sourceIndex}-whole`))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(`rkit-part-${sourceIndex}-whole`))) === null) return
    await driver.delayMs(250)
  }
  throw new Error('tap_original_body_unavailable')
}

/** Current saved paged policy only. No preferences, progress, hydration or sync writes. */
export default function readerTapZonesTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'ReaderTapZonesReadOnlyTrial') return
  describe('ReaderTapZonesReadOnlyTrial', (): void => {
    it('currentSavedZonesReadOnly', 0, async (): Promise<void> => {
      const work = args['-s readerLabWork'], unit = args['-s readerLabUnit']
      expect(work).assertEqual('4175844'); expect(unit).assertEqual('37d7c39ec2')
      const driver = Driver.create(), d = abilityDelegatorRegistry.getAbilityDelegator()
      // Native test discovery can precede EntryAbility bootstrap. Mount the normal host first.
      await d.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      for (let n = 0; n < 60 && (connectReadMode().restoreResult !== 'applied' ||
        connectGalleryReadProgress().restoreResult !== 'applied'); n++) await driver.delayMs(250)
      expect(connectSiteMode().isEx).assertFalse()
      const state = connectReadMode()
      expect(state.restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      if (state.mode === ReadMode.VERTICAL) throw new Error('OPEN: current mode is continuous; no fixture writes')
      expect(state.mode === ReadMode.LTR || state.mode === ReadMode.RTL || state.mode === ReadMode.TOP_TO_BOTTOM).assertTrue()
      const signature = tapSignature(work as string)
      let primaryFailure = false
      try {
        await d.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabSite: 'eh', readerLabPage: '2',
          readerLabChrome: 'true', readerLabVolumeKeys: 'false' } })
        await tapWait(driver, 'rkit-chrome-page'); await tapWait(driver, 'rkit-part-2-whole')
        expect(tapSignature(work as string)).assertEqual(signature)
        const win = await window.getLastWindow((await d.getCurrentTopAbility()).context)
        const windowId = win.getWindowProperties().id
        const utils = win.getUIContext().getComponentUtils()
        const regions = ReaderTapZoneResolver.regions(state.tapZoneLayoutPaged, state.tapZoneInvertPaged)
        const actions = ['menu', 'next', 'previous', 'menu']
        let previousPage = 3
        const initialPage = await driver.findComponent(ON.id('rkit-chrome-page'))
        expect(Number((await initialPage.getText()).split('/')[0].trim())).assertEqual(3)
        await tapBody(driver, 2)
        await tapCapture(driver, 'initial')
        for (let index = 0; index < actions.length; index++) {
          const wanted = actions[index]
          const region = regions.find(value => {
            const action = value.action === 'left' ? (state.mode === ReadMode.RTL ? 'next' : 'previous') :
              value.action === 'right' ? (state.mode === ReadMode.RTL ? 'previous' : 'next') : value.action
            return action === wanted && value.bottom > 0.25 && value.top < 0.75
          })
          if (region === undefined) throw new Error('OPEN: no unobscured current zone for ' + wanted)
          const rect = utils.getRectangleById('rkit-image-viewport')
          expect(rect.size.width > 0 && rect.size.height > 0).assertTrue()
          const x = (region.left + region.right) / 2
          const y = (Math.max(region.top, 0.25) + Math.min(region.bottom, 0.75)) / 2
          console.info(`[ReaderTapZones] work=${work} unit=${unit} site=eh window=${windowId} action=${wanted} x=${x} y=${y} rect=${JSON.stringify(rect)}`)
          await driver.click(Math.round(rect.windowOffset.x + rect.size.width * x),
            Math.round(rect.windowOffset.y + rect.size.height * y))
          await driver.delayMs(650)
          expect(tapSignature(work as string)).assertEqual(signature)
          expect((await window.getLastWindow((await d.getCurrentTopAbility()).context)).getWindowProperties().id).assertEqual(windowId)
          const pageLabel = await driver.findComponent(ON.id(index === 3 ? 'rkit-chrome-page' : 'rkit-persistent-page'))
          expect(pageLabel !== null).assertTrue()
          expect(await driver.findComponent(ON.id('rkit-close')) !== null).assertEqual(index === 3)
          const currentPage = Number((await pageLabel.getText()).split('/')[0].trim())
          if (wanted === 'next') expect(currentPage > previousPage).assertTrue()
          else if (wanted === 'previous') expect(currentPage).assertEqual(3)
          else expect(currentPage).assertEqual(previousPage)
          previousPage = currentPage
          await tapBody(driver, currentPage - 1)
          await tapCapture(driver, 'step-' + index)
        }
      } catch (error) {
        primaryFailure = true
        try { await tapCapture(driver, 'exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
          else await driver.pressBack()
          for (let n = 0; n < 60; n++) {
            if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
              await driver.findComponent(ON.id('rkit-phase')) === null &&
              await driver.findComponent(ON.id('rkit-reading-surface')) === null) break
            await driver.delayMs(250)
          }
          expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
          expect(await driver.findComponent(ON.id('rkit-phase'))).assertNull()
          expect(await driver.findComponent(ON.id('rkit-reading-surface'))).assertNull()
          const host = await d.getCurrentTopAbility()
          expect(host.context.abilityInfo.name).assertEqual('EntryAbility')
          expect(host.context.applicationInfo.name).assertEqual('com.erosteam.nexte')
          const hostWindow = await window.getLastWindow(host.context)
          expect(hostWindow.getWindowProperties().windowRect.width > 0).assertTrue()
          const root = hostWindow.getUIContext().getComponentUtils().getRectangleById('nexte-root-navigation')
          expect(root.size.width > 0 && root.size.height > 0).assertTrue()
          expect(tapSignature(work as string)).assertEqual(signature)
          await tapCapture(driver, 'exit')
        } catch (error) { if (!primaryFailure) throw error as Error }
      }
    })
  })
}
