import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, MatchPattern, ON } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { connectNextEReaderLabContextProbe } from 'reader'
import { ReadMode, ReadColumnMode, ReadSpreadLayout, connectReadMode, connectGalleryReadProgress, connectSyncSettings,
  ReaderTrialEntryRelay, ReaderTrialEntryProbe, ReaderTrialEntrySite } from 'shared'

const DETAIL_OWNER: string = 'gallery-detail-pane'

class ActualTop { windowId: number = -1; id: string = ''; top: number = 0 }
class HostHolder { context: common.UIAbilityContext | null = null }
class PolicyCase {
  continuous: boolean = false
  vertical: boolean = false
  rtl: boolean = false
  spread: boolean = false
  split: boolean = false
  even: boolean = false
}
const SOURCE_PATTERN: string = '^reader-thumb-gallery-detail-[0-9]+-page-2$'

async function waitId(driver: Driver, id: string): Promise<Component> {
  for (let i = 0; i < 80; i++) {
    const found = await driver.findComponent(ON.id(id))
    if (found !== null) return found
    await driver.delayMs(250)
  }
  throw new Error('Missing endpoint: ' + id)
}
async function closeTrial(driver: Driver): Promise<void> {
  if (await driver.findComponent(ON.id('rkit-vertical-paged')) !== null) await driver.pressBack()
  const close = await driver.findComponent(ON.id('rkit-close'))
  if (close !== null) await close.click()
  else if (await driver.findComponent(ON.id('rkit-trial-navigation')) !== null ||
    await driver.findComponent(ON.id('rkit-entry-source-pending')) !== null ||
    await driver.findComponent(ON.id('rkit-phase')) !== null) await driver.pressBack()
  for (let i = 0; i < 40; i++) {
    if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
      await driver.findComponent(ON.id('rkit-chrome-page')) === null &&
      await driver.findComponent(ON.id('rkit-entry-source-pending')) === null &&
      await driver.findComponent(ON.id('rkit-phase')) === null) return
    await driver.delayMs(200)
  }
  throw new Error('Trial exit not confirmed')
}
async function capture(driver: Driver, name: string): Promise<void> {
  const d = abilityDelegatorRegistry.getAbilityDelegator(), cache = d.getAppContext().cacheDir
  // Host receives and independently parses the styled raw dump; no cross-sandbox file read.
  const result = await d.executeShellCommand('uitest dumpLayout -p /data/local/tmp/rkit-thumbnail-policy-' + name + '.json -a', 15)
  console.info('[ThumbnailPolicy] capture=' + name + ' exit=' + result.exitCode + ' result=' + result.stdResult)
  expect(result.exitCode).assertEqual(0)
  expect(await driver.screenCap(cache + '/rkit-thumbnail-policy-' + name + '.png')).assertTrue()
}
async function actualTop(driver: Driver, id: string): Promise<ActualTop> {
  await waitId(driver, id)
  expect((await driver.findComponents(ON.id(id))).length).assertEqual(1)
  const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  const win = await window.getLastWindow(ability.context)
  for (let i = 0; i < 40; i++) {
    const rect = win.getUIContext().getComponentUtils().getRectangleById(id)
    if (rect.size.width > 0 && rect.size.height > 0 && Number.isFinite(rect.windowOffset.y)) {
      const value = new ActualTop()
      const props = win.getWindowProperties()
      value.windowId = props.id; value.id = id; value.top = rect.windowOffset.y
      console.info('[ThumbnailPolicy] actualRect window=' + value.windowId + ' type=' + props.type +
        ' windowRect=' + JSON.stringify(props.windowRect) + ' id=' + id + ' rect=' + JSON.stringify(rect))
      return value
    }
    await driver.delayMs(100)
  }
  throw new Error('Actual component layout unavailable: ' + id)
}
async function findSource(driver: Driver): Promise<Component> {
  const pane = await waitId(driver, DETAIL_OWNER)
  const pb = await pane.getBounds()
  const lists = await driver.findComponents(ON.type('List').within(ON.id(DETAIL_OWNER)))
  const owners: Component[] = []
  for (const list of lists) {
    const b = await list.getBounds()
    if (b.left === pb.left && b.right === pb.right && b.top === pb.top && b.bottom === pb.bottom) owners.push(list)
  }
  if (owners.length !== 1) throw new Error('Detail metadata owner is not unique')
  const selector = ON.id(SOURCE_PATTERN, MatchPattern.REG_EXP).within(ON.id(DETAIL_OWNER))
  const source = await owners[0].scrollSearch(selector, true)
  if (source === null) throw new Error('Actual Detail source2 thumbnail missing')
  const matches = await driver.findComponents(selector)
  expect(matches.length).assertEqual(1)
  const id = await source.getId()
  expect(new RegExp(SOURCE_PATTERN).test(id)).assertTrue()
  return await driver.findComponent(ON.id(id))
}
async function page(driver: Driver): Promise<number> {
  return Number((await (await waitId(driver, 'rkit-chrome-page')).getText()).split('/')[0].trim())
}
async function bodyReady(driver: Driver, id: string): Promise<void> {
  for (let i = 0; i < 80; i++) {
    const images = await driver.findComponents(ON.type('Image').within(ON.id(id)))
    if (images.length > 0 &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(id))) === null &&
      await driver.findComponent(ON.id('^rkit-failure-page-[0-9]+$', MatchPattern.REG_EXP).within(ON.id(id))) === null &&
      await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
      await driver.findComponent(ON.id('rkit-entry-source-pending')) === null) return
    await driver.delayMs(250)
  }
  throw new Error('Real source body did not complete handoff')
}
async function exercise(driver: Driver, label: string, policy: PolicyCase,
  stable: () => Promise<void>): Promise<void> {
  const source = await findSource(driver), sourceId = await source.getId(), before = await source.getBounds()
  await sourceReady(driver, sourceId)
  await stable()
  await capture(driver, label + '-source')
  console.info('[ThumbnailPolicy] click=' + Date.now() + ' source=' + sourceId + ' bounds=' + JSON.stringify(before))
  await (await driver.findComponent(ON.id(sourceId))).click()
  await waitId(driver, policy.continuous ? 'rkit-continuous-list' : 'rkit-native-pager')
  await bodyReady(driver, policy.continuous ? 'rkit-continuous-page-2' : 'rkit-image-viewport')
  expect(await page(driver)).assertEqual(3)
  const total = Number((await (await waitId(driver, 'rkit-chrome-page')).getText()).split('/')[1].trim())
  expect(total >= 6).assertTrue()
  if (!policy.continuous) {
    const a = await (await waitId(driver, 'rkit-part-2-whole')).getBounds()
    if (policy.spread) {
      const other = policy.even ? 1 : 3
      const b = await (await waitId(driver, 'rkit-part-' + other + '-whole')).getBounds()
      expect(a.left < b.left).assertEqual(policy.even ? policy.rtl : !policy.rtl)
      if (policy.split) {
        // Part rectangles are slots, not image pixels. This only checks inherited SPLIT topology.
        const viewport = await (await waitId(driver, 'rkit-image-viewport')).getBounds()
        expect(Math.abs((a.right - a.left) * 2 - (viewport.right - viewport.left)) <= 3).assertTrue()
      }
      await bodyReady(driver, 'rkit-part-' + other + '-whole')
    } else {
      expect(await driver.findComponent(ON.id('rkit-part-1-whole').within(ON.id('rkit-image-viewport')))).assertNull()
      expect(await driver.findComponent(ON.id('rkit-part-3-whole').within(ON.id('rkit-image-viewport')))).assertNull()
    }
  }
  await stable()
  verifyHandoff(sourceId)
  await capture(driver, label + '-settled')
  let initialTop: ActualTop | null = null
  if (policy.continuous) {
    initialTop = await actualTop(driver, 'rkit-continuous-page-2')
    const listTop = await actualTop(driver, 'rkit-continuous-list')
    expect(initialTop.windowId).assertEqual(listTop.windowId)
    expect(Math.abs(initialTop.top - listTop.top) <= 2).assertTrue()
  }
  const b = await (await waitId(driver, policy.continuous ? 'rkit-continuous-list' : 'rkit-image-viewport')).getBounds()
  const x = Math.round((b.left + b.right) / 2), y = Math.round((b.top + b.bottom) / 2)
  const vertical = policy.continuous || policy.vertical
  const offset = Math.round((vertical ? b.bottom - b.top : b.right - b.left) * (policy.continuous ? 0.17 : 0.31))
  const sign = policy.rtl && !vertical ? -1 : 1
  await driver.swipe(vertical ? x : x + offset * sign, vertical ? y + offset : y,
    vertical ? x : x - offset * sign, vertical ? y - offset : y, 700)
  await driver.delayMs(900)
  await stable()
  await capture(driver, label + '-gesture')
  if (policy.continuous && initialTop !== null) {
    const moved = await actualTop(driver, 'rkit-continuous-page-2')
    expect(moved.windowId).assertEqual(initialTop.windowId)
    expect(moved.id).assertEqual(initialTop.id)
    expect(Math.abs(moved.top - initialTop.top) > 2).assertTrue()
  }
  else expect(await page(driver)).assertEqual(policy.spread ? (policy.even ? 4 : 5) : 4)
  await closeTrial(driver)
  await stable()
  const returned = await waitId(driver, sourceId), after = await returned.getBounds()
  expect(after.left).assertEqual(before.left); expect(after.top).assertEqual(before.top)
  expect(after.right).assertEqual(before.right); expect(after.bottom).assertEqual(before.bottom)
  expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
  await capture(driver, label + '-closed')
}

let snapshotEpoch: number = 0
let snapshotSite: ReaderTrialEntrySite = 'eh'
async function sourceReady(driver: Driver, sourceId: string): Promise<void> {
  const site = ReaderTrialEntryRelay.currentSite()
  for (let i = 0; i < 60; i++) {
    expect(ReaderTrialEntryRelay.currentSite()).assertEqual(site)
    if (ReaderTrialEntryRelay.isSnapshotReady(site, sourceId)) {
      snapshotSite = site
      snapshotEpoch = ReaderTrialEntryProbe.read().epoch
      return
    }
    await driver.delayMs(250)
  }
  throw new Error('Actual source2 sprite is not snapshot ready')
}
function verifyHandoff(sourceId: string): void {
  const facts = ReaderTrialEntryProbe.read()
  expect(facts.epoch > snapshotEpoch).assertTrue()
  expect(facts.site).assertEqual(snapshotSite)
  expect(ReaderTrialEntryRelay.currentSite()).assertEqual(snapshotSite)
  expect(facts.phase).assertEqual('finished')
  expect(facts.galleryId).assertEqual('4175844')
  expect(facts.pageIndex).assertEqual(2)
  expect(facts.sourceComponentId).assertEqual(sourceId)
  expect(facts.snapshotCaptured && facts.snapshotReady && facts.movingObserved && !facts.closed).assertTrue()
  console.info('[ThumbnailPolicy] handoff=' + JSON.stringify(facts))
}
function signature(): string {
  const s = connectReadMode(), p = connectGalleryReadProgress()
  return JSON.stringify([s.mode, s.doublePageEnabled, s.spreadLayoutMode,
    p.getColumnMode('4175844'), JSON.stringify(p.getEntry('4175844'))])
}
export default function readerThumbnailInitialPolicyTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'ReaderThumbnailInitialPolicyReadOnlyTrial') return
  describe('ReaderThumbnailInitialPolicyReadOnlyTrial', (): void => {
    it('currentCanonicalPolicyFromActualSpriteSource2', 0, async (): Promise<void> => {
      expect(args['-s readerLabWork']).assertEqual('4175844')
      expect(args['-s readerLabUnit']).assertEqual('37d7c39ec2')
      const driver = Driver.create(), d = abilityDelegatorRegistry.getAbilityDelegator()
      const holder = new HostHolder(), probe = connectNextEReaderLabContextProbe()
      const epoch = probe.arm('4175844', (ctx: common.UIAbilityContext): void => { holder.context = ctx })
      try {
        await d.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: '4175844', readerLabUnit: '37d7c39ec2', readerLabPage: '2', readerLabVolumeKeys: 'false' } })
        for (let i = 0; i < 60 && holder.context === null; i++) await driver.delayMs(250)
        if (holder.context === null) throw new Error('No actual entry Context')
        expect(holder.context.databaseDir.endsWith('/entry')).assertTrue()
        console.info('[ThumbnailPolicy] actualHostDir=' + holder.context.databaseDir)
        await waitId(driver, 'rkit-phase')
      } finally { probe.cancel(epoch); await closeTrial(driver) }
      for (let i = 0; i < 60 && (connectReadMode().restoreResult !== 'applied' ||
        connectGalleryReadProgress().restoreResult !== 'applied'); i++) await driver.delayMs(250)
      expect(connectReadMode().restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      const mode = connectReadMode().mode, policy = new PolicyCase()
      policy.continuous = mode === ReadMode.VERTICAL; policy.vertical = mode === ReadMode.TOP_TO_BOTTOM
      policy.rtl = mode === ReadMode.RTL
      expect(mode === ReadMode.LTR || policy.continuous || policy.vertical || policy.rtl).assertTrue()
      policy.spread = !policy.continuous && !policy.vertical && connectReadMode().doublePageEnabled
      policy.split = connectReadMode().spreadLayoutMode === ReadSpreadLayout.SPLIT
      policy.even = connectGalleryReadProgress().getColumnMode('4175844') === ReadColumnMode.EVEN_LEFT
      const baseline = signature()
      console.info('[ThumbnailPolicy] readonlyMode=' + mode + ' double=' + policy.spread +
        ' even=' + policy.even + ' webdavBusy=' + connectSyncSettings().webdavSyncing +
        ' cloudBusy=' + connectSyncSettings().huaweiCloudSyncing + ' fixtureWrites=0')
      const stable = async (): Promise<void> => {
        if (signature() !== baseline) throw new Error('non_comparable: canonical/target record changed externally; nothing restored')
      }
      let failed = false
      try {
        await d.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: '4175844', readerLabUnit: '37d7c39ec2', readerLabPage: '2', readerLabChrome: 'true',
          readerLabThumbnailEntry: 'true', readerLabVolumeKeys: 'false' } })
        await exercise(driver, 'readonly', policy, stable)
      } catch (error) {
        failed = true
        console.error('[ThumbnailPolicy] failure=' + (error as Error).message)
        try { await capture(driver, 'readonly-exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          await closeTrial(driver)
          await stable()
          console.info('[ThumbnailPolicy] closed=true fixtureWrites=0 signatureUnchanged=true')
        } catch (error) {
          console.error('[ThumbnailPolicy] cleanup_failure=' + (error as Error).message)
          if (!failed) throw error as Error
        }
      }
    })
  })
}
