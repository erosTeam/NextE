import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit'
import { window } from '@kit.ArkUI'
import { connectReadMode, connectGalleryReadProgress, connectSiteMode, ReadMode } from 'shared'

async function waitId(d: Driver, id: string): Promise<Component> {
  for (let i = 0; i < 60; i++) {
    const c = await d.findComponent(ON.id(id))
    if (c !== null) return c
    await d.delayMs(250)
  }
  throw new Error('pageNumber missing:' + id)
}
async function capture(d: Driver, name: string): Promise<void> {
  const a = abilityDelegatorRegistry.getAbilityDelegator()
  expect((await a.executeShellCommand('uitest dumpLayout -p /data/local/tmp/rkit-page-number-' + name + '.json -a', 15)).exitCode).assertEqual(0)
  expect(await d.screenCap(a.getAppContext().cacheDir + '/rkit-page-number-' + name + '.png')).assertTrue()
  console.info('[ReaderPageNumberTest] capture=' + name)
}
async function body(d: Driver, index: number): Promise<void> {
  for (let i = 0; i < 60; i++) {
    const image = await d.findComponent(ON.type('Image').within(ON.id('rkit-part-' + index + '-whole')))
    if (image !== null && await d.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-part-' + index + '-whole'))) === null) {
      const b = await image.getBounds()
      if (b.right > b.left && b.bottom > b.top) {
        console.info('[ReaderPageNumberTest] source=' + index + ' bounds=' + JSON.stringify(b))
        return
      }
    }
    await d.delayMs(250)
  }
  throw new Error('pageNumber body unavailable:' + index)
}
async function center(d: Driver): Promise<void> {
  await waitId(d, 'rkit-image-viewport')
  const a = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  const w = await window.getLastWindow(a.context)
  const r = w.getUIContext().getComponentUtils().getRectangleById('rkit-image-viewport')
  expect(r.size.width > 0 && r.size.height > 0).assertTrue()
  console.info('[ReaderPageNumberTest] window=' + w.getWindowProperties().id + ' rect=' + JSON.stringify(r))
  await d.click(Math.round(r.windowOffset.x + r.size.width / 2), Math.round(r.windowOffset.y + r.size.height / 2))
  await d.delayMs(700)
}
async function closeTrial(d: Driver): Promise<void> {
  if (await d.findComponent(ON.id('rkit-trial-navigation')) === null &&
    await d.findComponent(ON.id('rkit-phase')) === null &&
    await d.findComponent(ON.id('rkit-reading-surface')) === null) return
  let close = await d.findComponent(ON.id('rkit-close'))
  if (close === null) { await center(d); close = await d.findComponent(ON.id('rkit-close')) }
  if (close !== null) await close.click()
  else await d.pressBack()
  for (let i = 0; i < 60; i++) {
    if (await d.findComponent(ON.id('rkit-trial-navigation')) === null &&
      await d.findComponent(ON.id('rkit-phase')) === null &&
      await d.findComponent(ON.id('rkit-reading-surface')) === null) return
    await d.delayMs(250)
  }
  throw new Error('pageNumber trial exit unconfirmed')
}
async function assertHost(): Promise<void> {
  const a = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  expect(a.context.abilityInfo.name).assertEqual('EntryAbility')
  expect(a.context.applicationInfo.name).assertEqual('com.erosteam.nexte')
  const w = await window.getLastWindow(a.context)
  const r = w.getUIContext().getComponentUtils().getRectangleById('nexte-root-navigation')
  expect(r.size.width > 0 && r.size.height > 0).assertTrue()
  console.info('[ReaderPageNumberTest] exitHost=NextE window=' + w.getWindowProperties().id + ' root=' + JSON.stringify(r))
}
async function launch(d: Driver): Promise<void> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
    parameters: { readerLabWork: '4175844', readerLabUnit: '37d7c39ec2', readerLabSite: 'eh', readerLabPage: '2', readerLabChrome: 'true', readerLabVolumeKeys: 'false' } })
  await waitId(d, 'rkit-close'); await body(d, 2)
}

async function exercise(d: Driver, enabled: boolean, rtl: boolean, name: string): Promise<void> {
  await launch(d)
  expect(Number((await (await waitId(d, 'rkit-chrome-page')).getText()).split('/')[0].trim())).assertEqual(3)
  await center(d)
  expect(await d.findComponent(ON.id('rkit-chrome-page'))).assertNull()
  expect(await d.findComponent(ON.id('rkit-persistent-page')) !== null).assertEqual(enabled)
  await body(d, 2); await capture(d, name + '-hidden')
  const a = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  const w = await window.getLastWindow(a.context)
  const r = w.getUIContext().getComponentUtils().getRectangleById('rkit-image-viewport')
  const left = Math.round(r.windowOffset.x + r.size.width * 0.19)
  const right = Math.round(r.windowOffset.x + r.size.width * 0.81)
  const y = Math.round(r.windowOffset.y + r.size.height * 0.5)
  await d.swipe(rtl ? left : right, y, rtl ? right : left, y, 700)
  await d.delayMs(700); await body(d, 3)
  expect(await d.findComponent(ON.id('rkit-persistent-page')) !== null).assertEqual(enabled)
  await capture(d, name + '-turned')
  await center(d)
  expect(Number((await (await waitId(d, 'rkit-chrome-page')).getText()).split('/')[0].trim())).assertEqual(4)
  await body(d, 3); await capture(d, name + '-chrome')
  await closeTrial(d)
}

function signature(): string {
  const s = connectReadMode()
  return JSON.stringify([s.showPageNumber, s.mode, s.doublePageEnabled, s.spreadLayoutMode,
    s.tapZoneLayoutPaged, s.tapZoneInvertPaged, connectSiteMode().isEx,
    connectGalleryReadProgress().getColumnMode('4175844'), connectGalleryReadProgress().getEntry('4175844')])
}
/** Read only current saved paged policy, preserving synchronization. */
export default function readerPageNumberTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'ReaderPageNumberReadOnlyTrial') return
  describe('ReaderPageNumberReadOnlyTrial', (): void => {
    it('currentSavedPageNumberReadOnly', 0, async (): Promise<void> => {
      expect(args['-s readerLabWork']).assertEqual('4175844')
      expect(args['-s readerLabUnit']).assertEqual('37d7c39ec2')
      const d = Driver.create(), a = abilityDelegatorRegistry.getAbilityDelegator()
      await a.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      for (let i = 0; i < 60 && (connectReadMode().restoreResult !== 'applied' ||
        connectGalleryReadProgress().restoreResult !== 'applied'); i++) await d.delayMs(250)
      const s = connectReadMode()
      expect(s.restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      expect(connectSiteMode().isEx).assertFalse()
      if (s.mode !== ReadMode.LTR && s.mode !== ReadMode.RTL) throw new Error('OPEN: current non-horizontal policy; no fixture writes')
      if (s.doublePageEnabled) throw new Error('OPEN: current double-page policy; no fixture writes')
      const original = signature()
      console.info('[ReaderPageNumberTest] readonly=true showPageNumber=' + s.showPageNumber + ' mode=' + s.mode)
      let failed = false
      try {
        await exercise(d, s.showPageNumber, s.mode === ReadMode.RTL, 'readonly')
        expect(signature()).assertEqual(original)
      } catch (error) {
        failed = true
        try { await capture(d, 'exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          await closeTrial(d)
          expect(signature()).assertEqual(original)
          console.info('[ReaderPageNumberTest] readonlySignatureUnchanged=true noSettingsOrSyncWrites=true')
          await assertHost()
          await capture(d, 'exit')
        } catch (error) { if (!failed) throw error as Error }
      }
    })
  })
}
