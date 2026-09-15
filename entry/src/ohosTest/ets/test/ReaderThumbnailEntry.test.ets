import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, MatchPattern, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { AppStrings, connectNavStack, connectReadMode, connectReaderThumbnailTransition, GalleryDetailParams, connectReaderOverlayNavigation,
  ReadMode, ReadColumnMode, ReadSpreadLayout, ReadModeSettings, StorageKeys, ReaderParams,
  ReaderTrialEntryProbe, ReaderTrialEntryRelay, ReaderTrialEntrySite,
  connectNextEReaderBackendSelection, NextEReaderBackend } from 'shared'
import { connectNextEReaderLabContextProbe } from 'reader'
import { leaveBackendSettings, openBackendSettings, selectBackend }
  from './ReaderLocalSourceTrial.test'

const FIRST_THUMBNAIL: string = '^reader-thumb-gallery-detail-[0-9]+-page-0$'
const FIRST_GRID_THUMBNAIL: string = '^reader-thumb-all-thumbnails-[0-9]+-page-0$'
const captureNames: string[] = ['source', 'reader', 'closed', 'exception', 'rotated', 'late', 'restored']

class ReaderInterpolationInspectorNode {
  $type: string = ''
  $attrs: Record<string, string | number> = {}
  $children: ReaderInterpolationInspectorNode[] = []
}

class ReaderInterpolationEvidence {
  expected: string = ''
  imageValues: string[] = []
  imageCount: number = 0
}

function clearEntryCaptures(names: string[] = captureNames): void {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  for (const name of names) {
    for (const extension of ['json', 'png']) {
      const path = `${cache}/rkit-entry-${name}.${extension}`
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    }
  }
}

async function captureEntry(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  if (typeof driver.dumpLayout === 'function') {
    expect(await driver.dumpLayout(`${cache}/rkit-entry-${name}.json`)).assertTrue()
  } else {
    const result = await delegator.executeShellCommand(
      `uitest dumpLayout -p /data/local/tmp/rkit-entry-${name}.json -a`, 15)
    expect(result.exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(`${cache}/rkit-entry-${name}.png`)).assertTrue()
}

async function findFirstDetailThumbnail(driver: Driver): Promise<Component> {
  let owner: Component | null = null
  for (let attempt = 0; attempt < 40; attempt++) {
    const pane = await driver.findComponent(ON.id('gallery-detail-pane'))
    if (pane !== null) {
      const paneBounds = await pane.getBounds()
      const lists = await driver.findComponents(ON.type('List').within(ON.id('gallery-detail-pane')))
      const owners: Component[] = []
      // PullRefreshListScaffold fills this real metadata pane. The nested horizontal
      // thumbnail List does not; do not scroll an arbitrary first List or guess a point.
      for (const list of lists) {
        const bounds = await list.getBounds()
        if (bounds.left === paneBounds.left && bounds.right === paneBounds.right &&
          bounds.top === paneBounds.top && bounds.bottom === paneBounds.bottom) owners.push(list)
      }
      if (owners.length > 1) throw new Error('Ambiguous Detail metadata List; no coordinate fallback')
      if (owners.length === 1) { owner = owners[0]; break }
    }
    await driver.delayMs(300)
  }
  if (owner === null) throw new Error('Current Detail metadata List is unavailable')
  const selector = ON.id(FIRST_THUMBNAIL, MatchPattern.REG_EXP).within(ON.id('gallery-detail-pane'))
  const source = await owner.scrollSearch(selector, true)
  if (source === null) throw new Error('Detail P1 thumbnail was not found by semantic scrollSearch')
  expect((await driver.findComponents(selector)).length).assertEqual(1)
  const sourceId = await source.getId()
  expect(new RegExp(FIRST_THUMBNAIL).test(sourceId)).assertTrue()
  return await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane')))
}

async function waitSnapshotReady(driver: Driver, site: ReaderTrialEntrySite, sourceId: string): Promise<void> {
  for (let attempt = 0; attempt < 60; attempt++) {
    expect(ReaderTrialEntryRelay.currentSite()).assertEqual(site)
    if (ReaderTrialEntryRelay.isSnapshotReady(site, sourceId)) return
    await driver.delayMs(250)
  }
  throw new Error('The live Detail P1 image never became snapshot-ready; do not screenshot its placeholder')
}

async function completedPart(driver: Driver, pageIndex: number): Promise<boolean> {
  // UiTest rejects a relational By nested inside another within(). First locate
  // the part in the selected viewport, then use its unique raw id for children.
  const owner = ON.id(`rkit-part-${pageIndex}-whole`)
  const part = await driver.findComponent(ON.id(`rkit-part-${pageIndex}-whole`).within(ON.id('rkit-image-viewport')))
  if (part === null || await driver.findComponent(ON.type('LoadingProgress').within(owner)) !== null ||
    await driver.findComponent(ON.id(`rkit-failure-page-${pageIndex + 1}`).within(owner)) !== null) return false
  const image = await driver.findComponent(ON.type('Image').within(owner))
  if (image === null) return false
  const bounds = await image.getBounds()
  const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
  return bounds.right > bounds.left && bounds.bottom > bounds.top &&
    bounds.left >= viewport.left - 1 && bounds.right <= viewport.right + 1 &&
    bounds.top >= viewport.top - 1 && bounds.bottom <= viewport.bottom + 1
}

async function waitSnapshotSpread(driver: Driver, baselineEpoch: number, site: ReaderTrialEntrySite,
  work: string, sourceId: string, direction: string = 'ltr'): Promise<number> {
  let epoch: number = 0
  for (let attempt = 0; attempt < 60; attempt++) {
    const facts = ReaderTrialEntryProbe.read()
    if (facts.epoch > baselineEpoch) {
      if (epoch === 0) epoch = facts.epoch
      expect(facts.epoch).assertEqual(epoch)
      expect(facts.site).assertEqual(site)
      expect(facts.galleryId).assertEqual(work)
      expect(facts.pageIndex).assertEqual(0)
      expect(facts.sourceComponentId).assertEqual(sourceId)
      expect(facts.snapshotReady).assertTrue()
      expect(facts.closed).assertFalse()
      if (facts.snapshotCaptured && facts.movingObserved && facts.phase === 'finished' &&
        await completedPart(driver, 0) && await completedPart(driver, 1) &&
        await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null &&
        await driver.findComponent(ON.id('^rkit-failure-page-[0-9]+$', MatchPattern.REG_EXP)
          .within(ON.id('rkit-image-viewport'))) === null &&
        await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
        await driver.findComponent(ON.id('rkit-entry-source-pending')) === null) {
        const page = await driver.findComponent(ON.id('rkit-chrome-page'))
        expect(page !== null).assertTrue()
        // ReaderChrome labels the source anchor, not a spread range.
        expect(/^1\s*\/\s*[1-9]\d*$/.test((await page.getText()).trim())).assertTrue()
        expect(await driver.findComponent(ON.id('rkit-close')) !== null).assertTrue()
        expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
        const first = await (await driver.findComponent(ON.id('rkit-part-0-whole')
          .within(ON.id('rkit-image-viewport')))).getBounds()
        const second = await (await driver.findComponent(ON.id('rkit-part-1-whole')
          .within(ON.id('rkit-image-viewport')))).getBounds()
        expect(direction === 'rtl' ? second.right <= first.left + 1 : first.right <= second.left + 1).assertTrue()
        await abilityDelegatorRegistry.getAbilityDelegator().print(`ReaderEntryProbe verified: ${JSON.stringify(facts)}`)
        return epoch
      }
    }
    await driver.delayMs(300)
  }
  throw new Error(`No same-epoch snapshot handoff to completed P1/P2 spread: ${JSON.stringify(ReaderTrialEntryProbe.read())}`)
}

async function waitSnapshotContinuous(driver: Driver, baselineEpoch: number, site: ReaderTrialEntrySite,
  work: string, sourceId: string): Promise<number> {
  let epoch: number = 0
  for (let attempt = 0; attempt < 80; attempt++) {
    const facts = ReaderTrialEntryProbe.read()
    if (facts.epoch > baselineEpoch) {
      if (epoch === 0) epoch = facts.epoch
      expect(facts.epoch).assertEqual(epoch)
      expect(facts.site).assertEqual(site)
      expect(facts.galleryId).assertEqual(work)
      expect(facts.pageIndex).assertEqual(0)
      expect(facts.sourceComponentId).assertEqual(sourceId)
      if (facts.snapshotCaptured && facts.snapshotReady && facts.movingObserved && facts.phase === 'finished' &&
        await driver.findComponent(ON.id('rkit-continuous-list')) !== null &&
        await driver.findComponent(ON.type('Image').within(ON.id('rkit-continuous-page-0'))) !== null &&
        await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-continuous-page-0'))) === null &&
        await driver.findComponent(ON.id('rkit-failure-page-1').within(ON.id('rkit-continuous-page-0'))) === null &&
        await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
        await driver.findComponent(ON.id('rkit-entry-source-pending')) === null) return epoch
    }
    await driver.delayMs(250)
  }
  throw new Error(`No same-epoch snapshot handoff to completed continuous P1: ${JSON.stringify(ReaderTrialEntryProbe.read())}`)
}

async function assertContinuousViewport(driver: Driver, label: string, pageIndex: number = 0): Promise<void> {
  const size = await driver.getDisplaySize()
  const list = await (await driver.findComponent(ON.id('rkit-continuous-list'))).getBounds()
  const pageId = `rkit-continuous-page-${pageIndex}`
  const page = await (await driver.findComponent(ON.id(pageId))).getBounds()
  const image = await (await driver.findComponent(ON.type('Image').within(ON.id(pageId)))).getBounds()
  expect(list.right - list.left >= size.x - 2).assertTrue()
  expect(list.bottom > list.top && page.bottom > page.top && image.bottom > image.top).assertTrue()
  console.info(`[ReaderContinuousReflow] ${label} display=${size.x}x${size.y} list=${JSON.stringify(list)} ` +
    `page=${JSON.stringify(page)} image=${JSON.stringify(image)}`)
}

function collectInterpolationValues(node: ReaderInterpolationInspectorNode, evidence: ReaderInterpolationEvidence,
  depth: number): void {
  if (depth > 24 || evidence.imageCount > 8) throw new Error('Interpolation Inspector subtree exceeds diagnostic bound')
  if (node.$type === 'Image') {
    evidence.imageCount++
    for (const key of ['interpolation', 'imageInterpolation']) {
      const value = node.$attrs?.[key]
      if (typeof value === 'string' &&
        ['low', 'medium', 'high', 'Low', 'Medium', 'High',
          'ImageInterpolation.Low', 'ImageInterpolation.Medium', 'ImageInterpolation.High'].includes(value)) {
        evidence.imageValues.push(value)
      }
    }
  }
  if (Array.isArray(node.$children)) {
    for (const child of node.$children) collectInterpolationValues(child, evidence, depth + 1)
  }
}

function interpolationMatches(value: string, expected: string): boolean {
  return value.replace('ImageInterpolation.', '').toLowerCase() === expected
}

async function sampleContinuousInterpolation(driver: Driver, expected: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  for (let attempt = 0; attempt < 60; attempt++) {
    const image = await driver.findComponent(ON.type('Image').within(ON.id('rkit-continuous-page-0')))
    if (image !== null && await driver.findComponent(ON.type('LoadingProgress')
      .within(ON.id('rkit-continuous-page-0'))) === null) {
      const ability = await delegator.getCurrentTopAbility()
      const mainWindow = await window.getLastWindow(ability.context)
      const tree = JSON.parse(mainWindow.getUIContext()
        .getFilteredInspectorTreeById('rkit-continuous-page-0', 0)) as ReaderInterpolationInspectorNode
      const evidence = new ReaderInterpolationEvidence()
      evidence.expected = expected
      collectInterpolationValues(tree, evidence, 0)
      if (evidence.imageCount > 0 && evidence.imageValues.length === evidence.imageCount &&
        evidence.imageValues.every((value: string): boolean => interpolationMatches(value, expected))) {
        const cache = delegator.getAppContext().cacheDir
        const path = `${cache}/rkit-entry-continuous-interpolation-${expected}.json`
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try { fileIo.writeSync(file.fd, JSON.stringify(evidence)) } finally { fileIo.closeSync(file) }
        expect(await driver.screenCap(`${cache}/rkit-entry-continuous-interpolation-${expected}.png`)).assertTrue()
        await delegator.print(`ReaderContinuousInterpolation evidence=${JSON.stringify(evidence)}`)
        return
      }
    }
    await driver.delayMs(250)
  }
  throw new Error(`Continuous Image interpolation did not become ${expected}`)
}

function readerThumbnailContinuousInterpolationTrial(work: string, unit: string): void {
  describe('ReaderThumbnailContinuousInterpolationTrial', (): void => {
    it('realContinuousImageReceivesLowAndHighEnumsWithoutPersistedDrift', 0, async (): Promise<void> => {
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      let context: common.UIAbilityContext | null = null
      let originalQuality: string = ''
      let epoch: number = 0
      let sourceId: string = ''
      let restored: boolean = false
      try {
        await delegator.startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'continuous', readerLabEntryDirection: 'ltr' },
        })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        context = (await delegator.getCurrentTopAbility()).context
        originalQuality = connectReadMode().imageScalingQuality
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotContinuous(driver, baselineEpoch, site, work, sourceId)

        await ReadModeSettings.setImageScalingQuality(context, 'low')
        expect(connectReadMode().imageScalingQuality).assertEqual('low')
        await sampleContinuousInterpolation(driver, 'low')
        await ReadModeSettings.setImageScalingQuality(context, 'high')
        expect(connectReadMode().imageScalingQuality).assertEqual('high')
        await sampleContinuousInterpolation(driver, 'high')

        await ReadModeSettings.setImageScalingQuality(context, originalQuality)
        restored = true
        expect(connectReadMode().imageScalingQuality).assertEqual(originalQuality)
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitClosed(driver, epoch, sourceId)
        await delegator.print(`ReaderContinuousInterpolation restored=${originalQuality} same_epoch=${epoch}`)
      } catch (error) {
        try { await captureEntry(driver, 'continuous-interpolation-exception') } catch (_) {}
        throw error as Error
      } finally {
        if (!restored && context !== null && originalQuality.length > 0) {
          try { await ReadModeSettings.setImageScalingQuality(context, originalQuality) } catch (_) {}
        }
        try {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
        } catch (_) {}
      }
    })
  })
}

function readerThumbnailContinuousReflowTrial(work: string, unit: string): void {
  describe('ReaderThumbnailContinuousReflowTrial', (): void => {
    it('realContinuousReaderSurvivesZoomPanAndRotation', 0, async (): Promise<void> => {
      const names = ['continuous-zoomed-portrait', 'continuous-landscape',
        'continuous-returned-portrait', 'continuous-post-rotation-pan', 'continuous-exception']
      clearEntryCaptures(names)
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      let epoch: number = 0
      let sourceId: string = ''
      try {
        await delegator.startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'continuous', readerLabEntryDirection: 'ltr' },
        })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const ability = await delegator.getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotContinuous(driver, baselineEpoch, site, work, sourceId)
        await assertContinuousViewport(driver, 'portrait-before-zoom')
        const page = await (await driver.findComponent(ON.id('rkit-continuous-page-0'))).getBounds()
        const x = Math.round((page.left + page.right) / 2), y = Math.round((page.top + page.bottom) / 2)
        await driver.doubleClick(x, y); await driver.delayMs(400)
        await driver.swipe(x, y, x + 200, y, 600); await driver.delayMs(500)
        await assertContinuousViewport(driver, 'zoomed-portrait')
        await captureEntry(driver, 'continuous-zoomed-portrait')

        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
        for (let attempt = 0; attempt < 50; attempt++) {
          const size = await driver.getDisplaySize()
          if (size.x > size.y && await driver.findComponent(ON.id('rkit-continuous-list')) !== null &&
            await driver.findComponent(ON.type('Image').within(ON.id('rkit-continuous-page-0'))) !== null) break
          if (attempt === 49) throw new Error('Full-screen continuous reader disappeared in landscape')
          await driver.delayMs(200)
        }
        await assertContinuousViewport(driver, 'landscape')
        await captureEntry(driver, 'continuous-landscape')

        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        for (let attempt = 0; attempt < 50; attempt++) {
          const size = await driver.getDisplaySize()
          if (size.y > size.x && await driver.findComponent(ON.id('rkit-continuous-list')) !== null) break
          if (attempt === 49) throw new Error('Full-screen continuous reader did not return to portrait')
          await driver.delayMs(200)
        }
        await assertContinuousViewport(driver, 'returned-portrait')
        await captureEntry(driver, 'continuous-returned-portrait')
        await driver.swipe(x, y, x - 200, y, 600); await driver.delayMs(500)
        await assertContinuousViewport(driver, 'post-rotation-pan')
        await captureEntry(driver, 'continuous-post-rotation-pan')
        expect(ReaderTrialEntryProbe.read().epoch).assertEqual(epoch)
        expect(ReaderTrialEntryProbe.read().phase).assertEqual('finished')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitClosed(driver, epoch, sourceId)
      } catch (error) {
        try { await captureEntry(driver, 'continuous-exception') } catch (_) {}
        throw error as Error
      } finally {
        if (mainWindow !== null && originalOrientation !== null) {
          try { await mainWindow.setPreferredOrientation(originalOrientation) } catch (_) {}
        }
      }
    })
  })
}

function readerThumbnailContinuousBoundaryRotationTrial(work: string, unit: string): void {
  describe('ReaderThumbnailContinuousBoundaryRotationTrial', (): void => {
    it('realContinuousBoundarySurvivesTabletRotation', 0, async (): Promise<void> => {
      const names = ['continuous-boundary-portrait', 'continuous-boundary-landscape',
        'continuous-boundary-returned', 'continuous-boundary-exception']
      clearEntryCaptures(names)
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      let epoch: number = 0
      let sourceId: string = ''
      try {
        await delegator.startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'continuous', readerLabEntryDirection: 'ltr' },
        })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const ability = await delegator.getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        const sourceOrientation = await driver.getDisplaySize()
        expect(sourceOrientation.y > sourceOrientation.x).assertTrue()
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotContinuous(driver, baselineEpoch, site, work, sourceId)

        const list = await (await driver.findComponent(ON.id('rkit-continuous-list'))).getBounds()
        const x = Math.round((list.left + list.right) / 2)
        const fromY = Math.round(list.top + (list.bottom - list.top) * 0.72)
        const toY = Math.round(list.top + (list.bottom - list.top) * 0.42)
        let currentPage = 1
        for (let attempt = 0; attempt < 18 && currentPage === 1; attempt++) {
          await driver.swipe(x, fromY, x, toY, 900)
          await driver.delayMs(180)
          const counter = await driver.findComponent(ON.id('rkit-chrome-page'))
          if (counter !== null) currentPage = Number((await counter.getText()).split('/')[0].trim())
        }
        expect(currentPage).assertEqual(2)
        expect(await driver.findComponent(
          ON.type('Image').within(ON.id('rkit-continuous-page-1'))) !== null).assertTrue()
        await captureEntry(driver, 'continuous-boundary-portrait')

        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
        for (let attempt = 0; attempt < 50; attempt++) {
          const size = await driver.getDisplaySize()
          const counter = await driver.findComponent(ON.id('rkit-chrome-page'))
          const page = counter === null ? 0 : Number((await counter.getText()).split('/')[0].trim())
          if (size.x > size.y && page === 2 && await driver.findComponent(
            ON.type('Image').within(ON.id('rkit-continuous-page-1'))) !== null) break
          if (attempt === 49) throw new Error('Continuous P2 boundary did not survive landscape reflow')
          await driver.delayMs(200)
        }
        await assertContinuousViewport(driver, 'boundary-landscape', 1)
        await captureEntry(driver, 'continuous-boundary-landscape')

        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        for (let attempt = 0; attempt < 50; attempt++) {
          const size = await driver.getDisplaySize()
          const counter = await driver.findComponent(ON.id('rkit-chrome-page'))
          const page = counter === null ? 0 : Number((await counter.getText()).split('/')[0].trim())
          if (size.y > size.x && page === 2 && await driver.findComponent(
            ON.type('Image').within(ON.id('rkit-continuous-page-1'))) !== null) break
          if (attempt === 49) throw new Error('Continuous P2 boundary did not survive portrait restoration')
          await driver.delayMs(200)
        }
        await captureEntry(driver, 'continuous-boundary-returned')
        expect(ReaderTrialEntryProbe.read().epoch).assertEqual(epoch)
        expect(ReaderTrialEntryProbe.read().phase).assertEqual('finished')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitClosed(driver, epoch, sourceId)
      } catch (error) {
        try { await captureEntry(driver, 'continuous-boundary-exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          const close = await driver.findComponent(ON.id('rkit-close'))
          if (close !== null) await close.click()
        } catch (_) {}
        if (mainWindow !== null && originalOrientation !== null) {
          try { await mainWindow.setPreferredOrientation(originalOrientation) } catch (_) {}
        }
      }
    })
  })
}

async function waitClosed(driver: Driver, epoch: number, sourceId: string): Promise<void> {
  for (let attempt = 0; attempt < 30; attempt++) {
    const facts = ReaderTrialEntryProbe.read()
    expect(facts.epoch).assertEqual(epoch)
    expect(facts.sourceComponentId).assertEqual(sourceId)
    if (facts.closed && await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
      await driver.findComponent(ON.id('rkit-entry-source-pending')) === null &&
      await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
      await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane'))) !== null) {
      expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
      expect(await driver.findComponent(ON.id('rkit-chrome-page'))).assertNull()
      await abilityDelegatorRegistry.getAbilityDelegator().print(`ReaderEntryProbe closed: ${JSON.stringify(facts)}`)
      return
    }
    await driver.delayMs(200)
  }
  throw new Error('The same entry did not close back to its retained Detail source')
}

function isAllThumbnailsRoute(): boolean {
  const paths = connectNavStack().stack.getAllPathName()
  return paths.length > 0 && paths[paths.length - 1] === 'AllThumbnails'
}

async function openFirstGridThumbnail(driver: Driver): Promise<Component> {
  const detailSource = await findFirstDetailThumbnail(driver)
  const detailSourceId = await detailSource.getId()
  // The real preview header precedes P1 in this metadata pane. Comments has its
  // own identical View all label before Preview; do not choose the first match.
  const previewTitle = AppStrings.get('gallery_preview')
  const viewAllTitle = AppStrings.get('detail_view_all')
  const header = ON.text(viewAllTitle).isAfter(ON.text(previewTitle))
    .isBefore(ON.id(detailSourceId)).within(ON.id('gallery-detail-pane'))
  const entries = await driver.findComponents(header)
  if (entries.length !== 1) throw new Error('The real Preview header View all entry is unavailable or ambiguous')
  const preview = await driver.findComponent(ON.text(previewTitle).within(ON.id('gallery-detail-pane')))
  expect(preview !== null).assertTrue()
  const titleBounds = await preview.getBounds()
  const entryBounds = await entries[0].getBounds()
  const paneBounds = await (await driver.findComponent(ON.id('gallery-detail-pane'))).getBounds()
  // Confirm the measured sibling labels belong to the existing centered header
  // row and are visible. Click the semantic label, never a guessed coordinate.
  expect(Math.abs((titleBounds.top + titleBounds.bottom) / 2 -
    (entryBounds.top + entryBounds.bottom) / 2) <= 2).assertTrue()
  expect(entryBounds.left >= titleBounds.right && entryBounds.right <= paneBounds.right &&
    entryBounds.top >= paneBounds.top && entryBounds.bottom <= paneBounds.bottom).assertTrue()
  await entries[0].click()
  for (let attempt = 0; attempt < 40; attempt++) {
    if (isAllThumbnailsRoute()) {
      const sources = await driver.findComponents(ON.id(FIRST_GRID_THUMBNAIL, MatchPattern.REG_EXP)
        .within(ON.type('Grid')))
      if (sources.length > 1) throw new Error('Ambiguous standalone AllThumbnails P1 source')
      if (sources.length === 1) return sources[0]
    }
    await driver.delayMs(300)
  }
  throw new Error('Preview View all did not open the standalone AllThumbnails Grid P1 source')
}

async function waitGridClosed(driver: Driver, epoch: number, sourceId: string): Promise<void> {
  for (let attempt = 0; attempt < 30; attempt++) {
    const facts = ReaderTrialEntryProbe.read()
    expect(facts.epoch).assertEqual(epoch)
    expect(facts.sourceComponentId).assertEqual(sourceId)
    if (facts.closed && isAllThumbnailsRoute() &&
      await driver.findComponent(ON.id('rkit-trial-navigation')) === null &&
      await driver.findComponent(ON.id('rkit-entry-source-pending')) === null &&
      await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
      await driver.findComponent(ON.id(sourceId).within(ON.type('Grid'))) !== null) {
      expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
      expect(await driver.findComponent(ON.id('rkit-chrome-page'))).assertNull()
      await abilityDelegatorRegistry.getAbilityDelegator().print(`ReaderEntryProbe Grid closed: ${JSON.stringify(ReaderTrialEntryProbe.read())}`)
      return
    }
    await driver.delayMs(200)
  }
  throw new Error('The same entry did not close back to its retained standalone AllThumbnails Grid source')
}

function readerThumbnailGridEntryTrial(work: string, unit: string, direction: string): void {
  describe('ReaderThumbnailGridEntryTrial', (): void => {
    it('realAllThumbnailsSnapshotHandsOffToSpreadAndClosesToSameGridSource', 0, async (): Promise<void> => {
      clearEntryCaptures()
      const driver = Driver.create()
      try {
        await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: direction },
        })
        const source = await openFirstGridThumbnail(driver)
        const sourceId = await source.getId()
        expect(new RegExp(FIRST_GRID_THUMBNAIL).test(sourceId)).assertTrue()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        expect(isAllThumbnailsRoute()).assertTrue()
        const liveSource = await driver.findComponent(ON.id(sourceId).within(ON.type('Grid')))
        const before = await liveSource.getBounds()
        const rootBefore = await (await driver.findComponent(ON.id('nexte-root-navigation'))).getBounds()
        expect(before.right > before.left && before.bottom > before.top &&
          before.left >= rootBefore.left && before.right <= rootBefore.right &&
          before.top >= rootBefore.top && before.bottom <= rootBefore.bottom).assertTrue()
        await captureEntry(driver, 'source')
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        expect(ReaderTrialEntryRelay.isSnapshotReady(site, sourceId)).assertTrue()
        await liveSource.click()
        const epoch = await waitSnapshotSpread(driver, baselineEpoch, site, work, sourceId, direction)
        await captureEntry(driver, 'reader')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitGridClosed(driver, epoch, sourceId)
        const after = await (await driver.findComponent(ON.id(sourceId).within(ON.type('Grid')))).getBounds()
        const rootAfter = await (await driver.findComponent(ON.id('nexte-root-navigation'))).getBounds()
        expect(Math.abs(before.left - after.left) <= 1 && Math.abs(before.right - after.right) <= 1 &&
          Math.abs(before.top - after.top) <= 1 && Math.abs(before.bottom - after.bottom) <= 1).assertTrue()
        expect(rootAfter.left).assertEqual(rootBefore.left)
        expect(rootAfter.right).assertEqual(rootBefore.right)
        expect(rootAfter.top).assertEqual(rootBefore.top)
        expect(rootAfter.bottom).assertEqual(rootBefore.bottom)
        await captureEntry(driver, 'closed')
      } catch (error) {
        await captureEntry(driver, 'exception')
        throw error as Error
      }
    })
  })
}

class EntryRotationObservation {
  requestedEpoch: number = 0
  requestedPhase: string = ''
  resizePhase: string = ''
  cancelled: boolean = false
  stopped: boolean = false
  events: string[] = []
}

async function rotateDuringEntry(mainWindow: window.Window, baselineEpoch: number,
  observation: EntryRotationObservation, triggerPhase: string = 'moving'): Promise<void> {
  const deadline = Date.now() + 15000
  while (!observation.stopped && Date.now() < deadline) {
    const facts = ReaderTrialEntryProbe.read()
    if (facts.epoch > baselineEpoch && facts.phase === triggerPhase) {
      observation.requestedEpoch = facts.epoch
      observation.requestedPhase = facts.phase
      observation.events.push(`${Date.now()} rotate_requested epoch=${facts.epoch} phase=${facts.phase}`)
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
      observation.events.push(`${Date.now()} orientation_settled phase=${ReaderTrialEntryProbe.read().phase}`)
      return
    }
    // In-process probe polling, not concurrent UiTest calls or a product animation delay.
    await new Promise<void>((resolve): void => { setTimeout(resolve, 8) })
  }
  throw new Error(`Did not observe ${triggerPhase} before requesting rotation`)
}

function readerThumbnailMovingRotationTrial(work: string, unit: string, settled: boolean = false,
  navigateAfterRotation: boolean = false): void {
  const className = navigateAfterRotation ? 'ReaderThumbnailSettledRotationNavigationTrial' :
    settled ? 'ReaderThumbnailSettledRotationTrial' : 'ReaderThumbnailMovingRotationTrial'
  describe(className, (): void => {
    it(navigateAfterRotation ? 'realViewportRotationRetainsPhysicalSpreadNavigation' :
      'realViewportRotationPreservesReadingAndRetiresPendingPreview', 0, async (): Promise<void> => {
      clearEntryCaptures(navigateAfterRotation ? captureNames.concat(['navigated', 'returned']) : captureNames)
      const driver = Driver.create()
      const observation = new EntryRotationObservation()
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      let rotation: Promise<void> | null = null
      let failed: boolean = false
      const resized = (size: window.Size): void => {
        const facts = ReaderTrialEntryProbe.read()
        observation.events.push(`${Date.now()} resized ${size.width}x${size.height} epoch=${facts.epoch} phase=${facts.phase}`)
        if (observation.requestedEpoch === facts.epoch && size.width > size.height &&
          observation.resizePhase.length === 0) observation.resizePhase = facts.phase
      }
      try {
        await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: 'rtl' },
        })
        const source = await findFirstDetailThumbnail(driver)
        const sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        mainWindow.on('windowSizeChange', resized)
        await captureEntry(driver, 'source')
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        if (settled) {
          await (await driver.findComponent(ON.id(sourceId))).click()
          await waitSnapshotSpread(driver, baselineEpoch, site, work, sourceId, 'rtl')
        }
        rotation = rotateDuringEntry(mainWindow, baselineEpoch, observation, settled ? 'finished' : 'moving')
        // Attach rejection handling immediately while the semantic click is in flight.
        const rotationResult = rotation.then((): string => '', (error: Error): string => error.message)
        if (!settled) await (await driver.findComponent(ON.id(sourceId))).click()
        const rotationError = await rotationResult
        if (rotationError.length > 0) throw new Error(rotationError)
        const deadline = Date.now() + 10000
        while (Date.now() < deadline) {
          const facts = ReaderTrialEntryProbe.read()
          expect(facts.epoch).assertEqual(observation.requestedEpoch)
          if (settled && facts.phase === 'finished' && observation.resizePhase === 'finished') break
          if (facts.phase === 'cancelled') { observation.cancelled = true; break }
          if (!settled && facts.phase === 'finished') throw new Error('Entry finished before observed cancellation; mid-flight coverage absent')
          await driver.delayMs(20)
        }
        expect(observation.cancelled).assertEqual(!settled)
        expect(observation.resizePhase).assertEqual(settled ? 'finished' : 'moving')
        for (let attempt = 0; attempt < 40; attempt++) {
          const size = await driver.getDisplaySize()
          if (size.x > size.y && await completedPart(driver, 0) && await completedPart(driver, 1)) break
          if (attempt === 39) throw new Error('Rotated reader did not recover both real images')
          await driver.delayMs(200)
        }
        await captureEntry(driver, 'rotated')
        if (navigateAfterRotation) {
          const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
          const inset = Math.round((viewport.right - viewport.left) * 0.12)
          const y = Math.round((viewport.top + viewport.bottom) / 2)
          // The entry is explicitly RTL. A physical left-to-right gesture advances
          // the logical spread; the reverse gesture must return to the same anchor.
          await driver.swipe(viewport.left + inset, y, viewport.right - inset, y, 700)
          for (let attempt = 0; attempt < 40; attempt++) {
            const page = Number((await (await driver.findComponent(ON.id('rkit-chrome-page')))
              .getText()).split('/')[0].trim())
            if (page === 3 && await completedPart(driver, 2) && await completedPart(driver, 3)) break
            if (attempt === 39) throw new Error('Physical RTL turn after landscape reflow did not reach P3/P4')
            await driver.delayMs(200)
          }
          await captureEntry(driver, 'navigated')
          await driver.swipe(viewport.right - inset, y, viewport.left + inset, y, 700)
          for (let attempt = 0; attempt < 40; attempt++) {
            const page = Number((await (await driver.findComponent(ON.id('rkit-chrome-page')))
              .getText()).split('/')[0].trim())
            if (page === 1 && await completedPart(driver, 0) && await completedPart(driver, 1)) break
            if (attempt === 39) throw new Error('Physical reverse turn after landscape reflow did not return to P1/P2')
            await driver.delayMs(200)
          }
          await captureEntry(driver, 'returned')
        }
        // Covers the original 280ms movement and 140ms reveal completion callbacks.
        await driver.delayMs(1000)
        expect(ReaderTrialEntryProbe.read().epoch).assertEqual(observation.requestedEpoch)
        expect(ReaderTrialEntryProbe.read().phase).assertEqual(settled ? 'finished' : 'cancelled')
        expect(ReaderTrialEntryProbe.read().closed).assertFalse()
        expect(await driver.findComponent(ON.id('rkit-entry-preview-image'))).assertNull()
        expect(await driver.findComponent(ON.id('rkit-entry-source-pending'))).assertNull()
        expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
        expect(/^1\s*\/\s*[1-9]\d*$/.test((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).trim())).assertTrue()
        await captureEntry(driver, 'late')
        await mainWindow.setPreferredOrientation(originalOrientation)
        for (let attempt = 0; attempt < 40; attempt++) {
          const size = await driver.getDisplaySize()
          if (size.y > size.x && await completedPart(driver, 0) && await completedPart(driver, 1)) break
          if (attempt === 39) throw new Error('Reader did not return to portrait')
          await driver.delayMs(200)
        }
        await captureEntry(driver, 'restored')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitClosed(driver, observation.requestedEpoch, sourceId)
        await captureEntry(driver, 'closed')
      } catch (error) {
        failed = true
        try { await captureEntry(driver, 'exception') } catch (captureError) {
          observation.events.push(`exception_capture_failed ${String(captureError)}`)
        }
        throw error as Error
      } finally {
        observation.stopped = true
        if (rotation !== null) { try { await rotation } catch (_) {} }
        const cleanupErrors: string[] = []
        if (mainWindow !== null) {
          try { mainWindow.off('windowSizeChange', resized) } catch (error) {
            cleanupErrors.push(`listener_cleanup_failed ${String(error)}`)
          }
          try {
            if (originalOrientation !== null) await mainWindow.setPreferredOrientation(originalOrientation)
          } catch (error) {
            cleanupErrors.push(`orientation_restore_failed ${String(error)}`)
          }
        }
        for (const cleanupError of cleanupErrors) observation.events.push(cleanupError)
        try {
          await abilityDelegatorRegistry.getAbilityDelegator().print(`ReaderMovingRotation: ${JSON.stringify(observation)}`)
        } catch (error) {
          cleanupErrors.push(`observation_print_failed ${String(error)}`)
          console.error(`ReaderMovingRotation: ${JSON.stringify(observation)}; ${cleanupErrors.join('; ')}`)
        }
        if (!failed && cleanupErrors.length > 0) throw new Error(cleanupErrors.join('; '))
      }
    })
  })
}

function assertProductionRotationSettings(): void {
  const mode = connectReadMode()
  expect(mode.mode).assertEqual(ReadMode.RTL)
  expect(mode.doublePageEnabled).assertTrue()
  expect(mode.spreadLayoutMode).assertEqual(ReadSpreadLayout.JOINED)
  expect(mode.cropBordersPaged).assertFalse()
  expect(mode.superResolutionEnabled).assertFalse()
}

class ProductionLayoutBounds {
  left: number
  top: number
  right: number
  bottom: number
  constructor(x: number, y: number, width: number, height: number) {
    this.left = x; this.top = y; this.right = x + width; this.bottom = y + height
  }
}

class ProductionSpreadBudget {
  deadline: number = Date.now() + 15000
  first: boolean = true
  lastCondition: string = ''
  reports: number = 0
  check(): void {
    if (Date.now() >= this.deadline) throw new Error(`Production spread 15s budget exhausted; last=${this.lastCondition}`)
  }
  async report(condition: string): Promise<void> {
    if (condition !== this.lastCondition && this.reports < 12) {
      await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} spread_condition ${condition}`)
      this.reports += 1
    }
    this.lastCondition = condition
  }
}

async function productionQuery<T>(budget: ProductionSpreadBudget, label: string, query: () => Promise<T>): Promise<T> {
  budget.check()
  if (budget.first) await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} query_begin ${label}`)
  const value = await query()
  if (budget.first) await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} query_end ${label}`)
  // This deadline cannot cancel an in-flight UiTest call; never start a competing call.
  budget.check()
  return value
}

async function waitProductionSpread(driver: Driver, landscape: boolean): Promise<void> {
  const budget = new ProductionSpreadBudget()
  const ability = await productionQuery(budget, 'top_ability', () =>
    abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility())
  const mainWindow = await productionQuery(budget, 'main_window', () => window.getLastWindow(ability.context))
  const componentUtils = mainWindow.getUIContext().getComponentUtils()
  while (Date.now() < budget.deadline) {
    const surface = await productionQuery(budget, 'surface', () => driver.findComponent(ON.id('reader_key_surface')))
    const first = await productionQuery(budget, 'page1', () => driver.findComponents(ON.id(
      '^reader-thumb-reader-surface-[0-9]+-route-[0-9]+-page-1$', MatchPattern.REG_EXP).within(ON.id('reader_key_surface'))))
    let condition = `surface=${surface !== null} page1=${first.length}`
    if (surface !== null && first.length === 1) {
      const firstId = await productionQuery(budget, 'page1_id', () => first[0].getId())
      const secondId = firstId.replace(/-page-1$/, '-page-2')
      const second = await productionQuery(budget, 'page2', () => driver.findComponent(ON.id(secondId)
        .within(ON.id('reader_key_surface'))))
      const transition = connectReaderThumbnailTransition()
      condition += ` page2=${second !== null} phase=${transition.phase} proxy=${transition.readerOpeningProxyVisible()}`
      let contentReady = false
      if (second !== null && transition.opened() && !transition.readerOpeningProxyVisible()) {
        const loading = await productionQuery(budget, 'loading', () => driver.findComponent(
          ON.type('LoadingProgress').within(ON.id('reader_key_surface'))))
        const firstType = await productionQuery(budget, 'page1_type', () => first[0].getType())
        const secondType = await productionQuery(budget, 'page2_type', () => second.getType())
        const firstImage = firstType === 'Image' || await productionQuery(budget, 'page1_image', () =>
          driver.findComponent(ON.type('Image').within(ON.id(firstId)))) !== null
        const secondImage = secondType === 'Image' || await productionQuery(budget, 'page2_image', () =>
          driver.findComponent(ON.type('Image').within(ON.id(secondId)))) !== null
        contentReady = loading === null && firstImage && secondImage
        condition += ` loading=${loading !== null} types=${firstType}/${secondType} images=${firstImage}/${secondImage}`
      }
      if (second !== null && contentReady) {
        const uiViewport = await productionQuery(budget, 'viewport_bounds', () => surface.getBounds())
        const uiOne = await productionQuery(budget, 'page1_bounds', () => first[0].getBounds())
        const uiTwo = await productionQuery(budget, 'page2_bounds', () => second.getBounds())
        // Use the same window-space layout measurements as the production transition coordinator.
        // UiTest may clip a visible surface's bounds when system chrome appears.
        const viewportLayout = componentUtils.getRectangleById('reader_key_surface')
        const oneLayout = componentUtils.getRectangleById(firstId)
        const twoLayout = componentUtils.getRectangleById(secondId)
        const viewport = new ProductionLayoutBounds(viewportLayout.windowOffset.x, viewportLayout.windowOffset.y,
          viewportLayout.size.width, viewportLayout.size.height)
        const one = new ProductionLayoutBounds(oneLayout.windowOffset.x, oneLayout.windowOffset.y,
          oneLayout.size.width, oneLayout.size.height)
        const two = new ProductionLayoutBounds(twoLayout.windowOffset.x, twoLayout.windowOffset.y,
          twoLayout.size.width, twoLayout.size.height)
        const width = viewport.right - viewport.left
        const height = viewport.bottom - viewport.top
        // A fresh production route starts at scale 1. Require the actual joined fit too:
        // P2 is left of P1, both share a height, and their centered union fits one viewport axis.
        const fit = width > 0 && height > 0 && (landscape ? width > height : height > width) &&
          one.right > one.left && one.bottom > one.top && two.right > two.left && two.bottom > two.top &&
          Math.abs(two.right - one.left) <= 2 && Math.abs(one.top - two.top) <= 2 &&
          Math.abs(one.bottom - two.bottom) <= 2 &&
          two.left >= viewport.left - 2 && one.right <= viewport.right + 2 &&
          one.top >= viewport.top - 2 && one.bottom <= viewport.bottom + 2 &&
          Math.abs((two.left + one.right) - (viewport.left + viewport.right)) <= 4 &&
          Math.abs((one.top + one.bottom) - (viewport.top + viewport.bottom)) <= 4 &&
          (Math.abs(one.right - two.left - width) <= 2 || Math.abs(one.bottom - one.top - height) <= 2)
        condition += ` landscape=${landscape} viewport=${JSON.stringify(viewport)} p1=${JSON.stringify(one)} p2=${JSON.stringify(two)}` +
          ` uiViewport=${JSON.stringify(uiViewport)} uiP1=${JSON.stringify(uiOne)} uiP2=${JSON.stringify(uiTwo)} fit=${fit}`
        if (fit) {
          await budget.report(condition)
          assertProductionRotationSettings()
          expect(connectReadMode().columnMode).assertEqual(ReadColumnMode.ODD_LEFT)
          return
        }
      }
    }
    await budget.report(condition)
    budget.first = false
    await productionQuery(budget, 'poll_delay', () => driver.delayMs(250))
  }
  throw new Error('Production P1/P2 did not reach the visible RTL joined fit without loading; no trial fallback')
}

function readerProductionCropTrial(work: string, unit: string, layout: string = 'single'): void {
  describe(layout === 'zoom' ? 'ReaderProductionCropZoomTrial' : layout === 'spread' ? 'ReaderProductionCropSpreadTrial' :
    layout === 'continuous' ? 'ReaderProductionCropContinuousTrial' : 'ReaderProductionCropTrial', (): void => {
    it('currentProductionP5CropReferenceAndSettingsRestoration', 0, async (): Promise<void> => {
      clearEntryCaptures(['reader', 'baseline', 'changed', 'returned', 'closed', 'exception'])
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      for (let i = 0; i < 40; i++) {
        if (await driver.findComponent(ON.id('nexte-root-navigation')) !== null) break
        await driver.delayMs(250)
      }
      const ability = await delegator.getCurrentTopAbility(), context = ability.context
      const setting = connectReadMode()
      const mode = setting.mode, doublePage = setting.doublePageEnabled, crop = setting.cropBordersPaged
      const continuousCrop = setting.cropBordersContinuous
      expect(setting.superResolutionEnabled).assertFalse()
      try {
        await ReadModeSettings.setMode(context, layout === 'continuous' ? ReadMode.VERTICAL : ReadMode.LTR)
        await ReadModeSettings.setDoublePageEnabled(context, layout === 'spread')
        await ReadModeSettings.setCropBordersPaged(context, layout !== 'zoom')
        if (layout === 'continuous') await ReadModeSettings.setCropBordersContinuous(context, true)
        const params = new ReaderParams(work, unit, 4, 46)
        params.initialChromeVisible = true
        connectReaderOverlayNavigation().open(params, false)
        let ready = false
        for (let i = 0; i < 80; i++) {
          const page = await driver.findComponent(ON.id('^reader-thumb-reader-surface-[0-9]+-route-[0-9]+-page-5$', MatchPattern.REG_EXP))
          if (page !== null &&
            await driver.findComponent(ON.type('LoadingProgress').within(ON.id('reader_key_surface'))) === null) {
            ready = true; break
          }
          await driver.delayMs(250)
        }
        expect(ready).assertTrue()
        const chrome = ON.type('Slider').within(ON.id('reader_key_surface'))
        if (await driver.findComponent(chrome) === null) {
          const bounds = await (await driver.findComponent(ON.id('reader_key_surface'))).getBounds()
          await driver.click(Math.round((bounds.left + bounds.right) / 2), Math.round((bounds.top + bounds.bottom) / 2))
        }
        for (let i = 0; i < 30; i++) {
          if (await driver.findComponent(chrome) !== null) break
          await driver.delayMs(200)
        }
        expect(await driver.findComponent(chrome) !== null).assertTrue()
        await captureEntry(driver, 'reader')
        if (layout === 'zoom') {
          const bounds = await (await driver.findComponent(ON.id('reader_key_surface'))).getBounds()
          await driver.doubleClick(Math.round(bounds.left + (bounds.right - bounds.left) * 0.45),
            Math.round(bounds.top + (bounds.bottom - bounds.top) * 0.45))
          await driver.delayMs(600); await captureEntry(driver, 'baseline')
          await ReadModeSettings.setCropBordersPaged(context, true)
          await driver.delayMs(1500); await captureEntry(driver, 'changed')
          await ReadModeSettings.setCropBordersPaged(context, false)
          await driver.delayMs(600); await captureEntry(driver, 'returned')
        }
        await driver.pressBack(); await driver.delayMs(800)
        await captureEntry(driver, 'closed')
      } catch (error) {
        await captureEntry(driver, 'exception')
        throw error as Error
      } finally {
        const errors: string[] = []
        try { await ReadModeSettings.setMode(context, mode) } catch (error) { errors.push(String(error)) }
        try { await ReadModeSettings.setDoublePageEnabled(context, doublePage) } catch (error) { errors.push(String(error)) }
        try { await ReadModeSettings.setCropBordersPaged(context, crop) } catch (error) { errors.push(String(error)) }
        if (layout === 'continuous') {
          try { await ReadModeSettings.setCropBordersContinuous(context, continuousCrop) } catch (error) { errors.push(String(error)) }
        }
        const store = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS), live = connectReadMode()
        const restored = live.mode === mode && live.doublePageEnabled === doublePage && live.cropBordersPaged === crop &&
          store.getSync(StorageKeys.READING_DIRECTION, '') === mode &&
          store.getSync(StorageKeys.READING_DOUBLE_PAGE, !doublePage) === doublePage &&
          store.getSync(StorageKeys.READING_CROP_BORDERS_PAGED, !crop) === crop &&
          (layout !== 'continuous' || (live.cropBordersContinuous === continuousCrop &&
            store.getSync(StorageKeys.READING_CROP_BORDERS_CONTINUOUS, !continuousCrop) === continuousCrop))
        await delegator.print(`ReaderProductionCrop restored=${restored} mode=${mode} double=${doublePage} crop=${crop} errors=${errors.length}`)
        expect(restored && errors.length === 0).assertTrue()
      }
    })
  })
}

function readerProductionSettledRotationTrial(work: string, unit: string, originalMenuOnly: boolean = false): void {
  describe(originalMenuOnly ? 'ReaderProductionOriginalMenuTrial' : 'ReaderProductionSettledRotationTrial', (): void => {
    it(originalMenuOnly ? 'productionOriginalMenuRetainsVisualSourceSides' : 'realProductionJoinedSpreadRotatesAfterOpeningHasSettled', 0, async (): Promise<void> => {
      clearEntryCaptures(originalMenuOnly ? captureNames.concat(['original-menu']) : captureNames)
      const driver = Driver.create()
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      let settingsContext: common.UIAbilityContext | null = null
      let originalMode: string = ''
      let originalDoublePage: boolean = false
      let originalSpreadLayout: string = ''
      let settingsSaved: boolean = false
      let failed: boolean = false
      const events: string[] = []
      let landscapeObserved: boolean = false
      const resized = (size: window.Size): void => {
        events.push(`${Date.now()} resized ${size.width}x${size.height}`)
        if (size.width > size.height) landscapeObserved = true
      }
      try {
        await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
        })
        for (let attempt = 0; attempt < 40; attempt++) {
          if (await driver.findComponent(ON.id('nexte-root-navigation')) !== null) break
          if (attempt === 39) throw new Error('Normal NextE root was not ready')
          await driver.delayMs(250)
        }
        // The first root mounts only after SettingsBootstrap.loadForFirstContent completes.
        // Save all authorized fields before the first setter, including partial-setup failures.
        const settingsAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
        settingsContext = settingsAbility.context
        const currentMode = connectReadMode()
        expect(currentMode.cropBordersPaged).assertFalse()
        expect(currentMode.superResolutionEnabled).assertFalse()
        originalMode = currentMode.mode
        originalDoublePage = currentMode.doublePageEnabled
        originalSpreadLayout = currentMode.spreadLayoutMode
        settingsSaved = true
        events.push(`settings_saved mode=${originalMode} doublePage=${originalDoublePage} spread=${originalSpreadLayout}`)
        await ReadModeSettings.setMode(settingsContext, ReadMode.RTL)
        await ReadModeSettings.setDoublePageEnabled(settingsContext, true)
        await ReadModeSettings.setSpreadLayoutMode(settingsContext, ReadSpreadLayout.JOINED)
        assertProductionRotationSettings()
        const configured = await preferences.getPreferences(settingsContext, StorageKeys.STORE_SETTINGS)
        expect(configured.getSync(StorageKeys.READING_DIRECTION, '') as string).assertEqual(ReadMode.RTL)
        expect(configured.getSync(StorageKeys.READING_DOUBLE_PAGE, false) as boolean).assertTrue()
        expect(configured.getSync(StorageKeys.READING_SPREAD_LAYOUT, '') as string).assertEqual(ReadSpreadLayout.JOINED)
        events.push('settings_temporary RTL joined doublePage; production comparison only, not migration')
        expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
        connectNavStack().stack.pushPathByName('GalleryDetail', new GalleryDetailParams(work, unit))
        const firstSource = await findFirstDetailThumbnail(driver)
        const source = originalMenuOnly ? await driver.findComponent(ON.id((await firstSource.getId()).replace('-page-0', '-page-1'))
          .within(ON.id('gallery-detail-pane'))) : firstSource
        if (source === null) throw new Error('Production P2 thumbnail not available')
        const sourceId = await source.getId()
        await captureEntry(driver, 'source')
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} source_click_begin`)
        await source.click()
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} source_click_end spread_before_chrome_begin`)
        await waitProductionSpread(driver, false)
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} spread_before_chrome_end`)
        expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
        // Actual 135 dump exposes the chrome Slider but exports empty descriptions for its Buttons.
        // ReaderPage only mounts this Slider while showChrome is true; do not guess a More label.
        const chrome = ON.type('Slider').within(ON.id('reader_key_surface'))
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_query_begin`)
        if (await driver.findComponent(chrome) === null) {
          await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_query_end absent center_bounds_begin`)
          const surface = await (await driver.findComponent(ON.id('reader_key_surface'))).getBounds()
          await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_tap_begin bounds=${JSON.stringify(surface)}`)
          await driver.click(Math.round((surface.left + surface.right) / 2), Math.round((surface.top + surface.bottom) / 2))
          await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_tap_end`)
        } else {
          await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_query_end present`)
        }
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_visible_wait_begin`)
        for (let attempt = 0; attempt < 30; attempt++) {
          if (await driver.findComponent(chrome) !== null) break
          if (attempt === 29) throw new Error('Single measured Reader-center tap did not expose production chrome')
          await driver.delayMs(200)
        }
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} chrome_visible spread_after_chrome_begin`)
        await waitProductionSpread(driver, false)
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} spread_after_chrome_end reader_capture_begin`)
        await captureEntry(driver, 'reader')
        await abilityDelegatorRegistry.getAbilityDelegator().print(`[ReaderProductionStage] ${Date.now()} reader_capture_end`)
        if (originalMenuOnly) {
          // Production ReaderBottomToolbar source order is save, original, clock, thumbnails.
          // Resolve that row from the live Slider and Button bounds; never reuse screen coordinates.
          const sliderBounds = await (await driver.findComponent(chrome)).getBounds()
          const buttons = await driver.findComponents(ON.type('Button').within(ON.id('reader_key_surface')))
          let first: Component | null = null, second: Component | null = null
          let firstLeft: number = Number.MAX_VALUE, secondLeft: number = Number.MAX_VALUE, count: number = 0
          for (const button of buttons) {
            const bounds = await button.getBounds()
            if (bounds.top < sliderBounds.bottom || bounds.bottom <= bounds.top || bounds.right <= bounds.left) continue
            count += 1
            if (bounds.left < firstLeft) { second = first; secondLeft = firstLeft; first = button; firstLeft = bounds.left }
            else if (bounds.left < secondLeft) { second = button; secondLeft = bounds.left }
          }
          if (count < 6 || second === null || !await second.isEnabled()) throw new Error('Production original toolbar action unavailable')
          await second.click()
          let shown = false
          for (let attempt = 0; attempt < 30; attempt++) {
            if (await driver.findComponent(ON.type('Menu')) !== null) { shown = true; break }
            await driver.delayMs(100)
          }
          expect(shown).assertTrue()
          await captureEntry(driver, 'original-menu')
          await driver.pressBack(); await driver.delayMs(400)
        } else {
        const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        mainWindow.on('windowSizeChange', resized)
        events.push(`${Date.now()} rotate_requested production_settled`)
        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
        await waitProductionSpread(driver, true)
        expect(landscapeObserved).assertTrue()
        await captureEntry(driver, 'rotated')
        await driver.delayMs(1000)
        await waitProductionSpread(driver, true)
        await captureEntry(driver, 'late')
        await mainWindow.setPreferredOrientation(originalOrientation)
        await waitProductionSpread(driver, false)
        await captureEntry(driver, 'restored')
        }
        await driver.pressBack()
        for (let attempt = 0; attempt < 40; attempt++) {
          if (await driver.findComponent(ON.id('reader_key_surface')) === null &&
            await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane'))) !== null) break
          if (attempt === 39) throw new Error('Production Reader did not close to its retained Detail source')
          await driver.delayMs(250)
        }
        await captureEntry(driver, 'closed')
      } catch (error) {
        failed = true
        try { await captureEntry(driver, 'exception') } catch (captureError) {
          events.push(`exception_capture_failed ${String(captureError)}`)
        }
        throw error as Error
      } finally {
        const cleanupErrors: string[] = []
        if (mainWindow !== null) {
          try { mainWindow.off('windowSizeChange', resized) } catch (error) {
            cleanupErrors.push(`listener_cleanup_failed ${String(error)}`)
          }
          try {
            if (originalOrientation !== null) await mainWindow.setPreferredOrientation(originalOrientation)
          } catch (error) { cleanupErrors.push(`orientation_restore_failed ${String(error)}`) }
        }
        if (settingsSaved && settingsContext !== null) {
          // Restore independently: one failure must not skip either remaining field.
          try { await ReadModeSettings.setMode(settingsContext, originalMode) } catch (error) {
            cleanupErrors.push(`mode_restore_failed ${String(error)}`)
          }
          try { await ReadModeSettings.setDoublePageEnabled(settingsContext, originalDoublePage) } catch (error) {
            cleanupErrors.push(`double_page_restore_failed ${String(error)}`)
          }
          try { await ReadModeSettings.setSpreadLayoutMode(settingsContext, originalSpreadLayout) } catch (error) {
            cleanupErrors.push(`spread_layout_restore_failed ${String(error)}`)
          }
          try {
            const restored = await preferences.getPreferences(settingsContext, StorageKeys.STORE_SETTINGS)
            const live = connectReadMode()
            const modeRestored = live.mode === originalMode &&
              restored.getSync(StorageKeys.READING_DIRECTION, '') === originalMode
            const doubleRestored = live.doublePageEnabled === originalDoublePage &&
              restored.getSync(StorageKeys.READING_DOUBLE_PAGE, !originalDoublePage) === originalDoublePage
            const spreadRestored = live.spreadLayoutMode === originalSpreadLayout &&
              restored.getSync(StorageKeys.READING_SPREAD_LAYOUT, '') === originalSpreadLayout
            events.push(`settings_restored mode=${modeRestored} doublePage=${doubleRestored} spread=${spreadRestored}`)
            if (!modeRestored || !doubleRestored || !spreadRestored) {
              cleanupErrors.push('settings_restore_readback_mismatch')
            }
          } catch (error) { cleanupErrors.push(`settings_restore_readback_failed ${String(error)}`) }
        }
        try {
          await abilityDelegatorRegistry.getAbilityDelegator().print(
            `ReaderProductionRotation: ${JSON.stringify(events)} cleanup=${cleanupErrors.join('; ')}`)
        } catch (error) { cleanupErrors.push(`observation_print_failed ${String(error)}`) }
        if (!failed && cleanupErrors.length > 0) throw new Error(cleanupErrors.join('; '))
      }
    })
  })
}

function readerProductionSettingsRestoreTrial(cropRecovery: boolean = false): void {
  describe(cropRecovery ? 'ReaderProductionCropRestoreTrial' : 'ReaderProductionSettingsRestoreTrial', (): void => {
    it('restoresAuthorizedPreTrialReadingSettings', 0, async (): Promise<void> => {
      const driver = Driver.create()
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
      })
      for (let attempt = 0; attempt < 40; attempt++) {
        if (await driver.findComponent(ON.id('nexte-root-navigation')) !== null) break
        if (attempt === 39) throw new Error('Normal NextE root was not ready for settings restoration')
        await driver.delayMs(250)
      }
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
      const errors: string[] = []
      // Explicit recovery of the three original values verified in protocol 135.
      // Attempt every restoration even if one setter fails.
      try { await ReadModeSettings.setMode(ability.context, ReadMode.LTR) } catch (error) {
        errors.push(`mode_restore_failed ${String(error)}`)
      }
      try { await ReadModeSettings.setDoublePageEnabled(ability.context, true) } catch (error) {
        errors.push(`double_page_restore_failed ${String(error)}`)
      }
      try {
        if (cropRecovery) await ReadModeSettings.setCropBordersPaged(ability.context, false)
        else await ReadModeSettings.setSpreadLayoutMode(ability.context, ReadSpreadLayout.JOINED)
      } catch (error) {
        errors.push(`spread_layout_restore_failed ${String(error)}`)
      }
      const store = await preferences.getPreferences(ability.context, StorageKeys.STORE_SETTINGS)
      const live = connectReadMode()
      expect(live.mode).assertEqual(ReadMode.LTR)
      expect(live.doublePageEnabled).assertTrue()
      if (cropRecovery) expect(live.cropBordersPaged).assertFalse()
      else expect(live.spreadLayoutMode).assertEqual(ReadSpreadLayout.JOINED)
      expect(store.getSync(StorageKeys.READING_DIRECTION, '') as string).assertEqual(ReadMode.LTR)
      expect(store.getSync(StorageKeys.READING_DOUBLE_PAGE, false) as boolean).assertTrue()
      if (cropRecovery) expect(store.getSync(StorageKeys.READING_CROP_BORDERS_PAGED, true) as boolean).assertFalse()
      else expect(store.getSync(StorageKeys.READING_SPREAD_LAYOUT, '') as string).assertEqual(ReadSpreadLayout.JOINED)
      if (errors.length > 0) throw new Error(errors.join('; '))
      await abilityDelegatorRegistry.getAbilityDelegator().print(
        cropRecovery ? 'ReaderProductionCropRestore: verified memory_and_preferences mode=ltr doublePage=true crop=false' :
          'ReaderProductionSettingsRestore: verified memory_and_preferences mode=ltr doublePage=true spread=joined')
    })
  })
}

function systemAreaSize(area: window.AvoidArea): number {
  return area.topRect.width * area.topRect.height + area.leftRect.width * area.leftRect.height +
    area.rightRect.width * area.rightRect.height + area.bottomRect.width * area.bottomRect.height
}

async function waitTrialChrome(driver: Driver, mainWindow: window.Window, shown: boolean, epoch: number): Promise<void> {
  const deadline = Date.now() + 10000
  while (Date.now() < deadline) {
    const close = await driver.findComponent(ON.id('rkit-close'))
    const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    const facts = ReaderTrialEntryProbe.read()
    expect(facts.epoch).assertEqual(epoch)
    expect(facts.closed).assertFalse()
    expect(facts.phase).assertEqual('finished')
    if ((close !== null) === shown && (systemAreaSize(area) > 0) === shown) {
      await abilityDelegatorRegistry.getAbilityDelegator().print(
        `ReaderThumbnailChrome: shown=${shown} systemArea=${JSON.stringify(area)} probe=${JSON.stringify(facts)}`)
      return
    }
    await driver.delayMs(200)
  }
  throw new Error(`Trial chrome/system-area state did not become shown=${shown}`)
}

async function toggleTrialChrome(driver: Driver): Promise<void> {
  const viewport = await driver.findComponent(ON.id('rkit-image-viewport'))
  expect(viewport !== null).assertTrue()
  const bounds = await viewport.getBounds()
  expect(bounds.right > bounds.left && bounds.bottom > bounds.top).assertTrue()
  await driver.click(Math.round((bounds.left + bounds.right) / 2), Math.round((bounds.top + bounds.bottom) / 2))
}

function readerThumbnailChromeTrial(work: string, unit: string): void {
  describe('ReaderThumbnailChromeTrial', (): void => {
    it('hostStatusAreaFollowsChromeAndRestoresAfterHiddenBack', 0, async (): Promise<void> => {
      clearEntryCaptures(['chrome-shown', 'chrome-hidden', 'chrome-reshown', 'closed', 'exception'])
      const driver = Driver.create()
      let mainWindow: window.Window | null = null
      let sourceId: string = ''
      let epoch: number = 0
      let failed: boolean = false
      try {
        await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: 'rtl' },
        })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        const beforeArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        await abilityDelegatorRegistry.getAbilityDelegator().print(
          `ReaderThumbnailChrome: source_systemArea=${JSON.stringify(beforeArea)}`)
        expect(systemAreaSize(beforeArea) > 0).assertTrue()
        const baseline = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotSpread(driver, baseline, site, work, sourceId, 'rtl')
        await waitTrialChrome(driver, mainWindow, true, epoch)
        await captureEntry(driver, 'chrome-shown')
        await toggleTrialChrome(driver)
        await waitTrialChrome(driver, mainWindow, false, epoch)
        await captureEntry(driver, 'chrome-hidden')
        await toggleTrialChrome(driver)
        await waitTrialChrome(driver, mainWindow, true, epoch)
        await captureEntry(driver, 'chrome-reshown')
        await toggleTrialChrome(driver)
        await waitTrialChrome(driver, mainWindow, false, epoch)
        await driver.pressBack()
        await waitClosed(driver, epoch, sourceId)
        const deadline = Date.now() + 10000
        while (systemAreaSize(mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)) === 0) {
          if (Date.now() >= deadline) throw new Error('System area did not restore after hidden-chrome Back')
          await driver.delayMs(200)
        }
        await captureEntry(driver, 'closed')
      } catch (error) {
        failed = true
        try { await captureEntry(driver, 'exception') } catch (_) {}
        try {
          if (await driver.findComponent(ON.id('rkit-trial-navigation')) !== null) {
            await driver.pressBack()
            if (epoch > 0 && sourceId.length > 0) await waitClosed(driver, epoch, sourceId)
          }
        } catch (cleanupError) {
          console.error(`ReaderThumbnailChrome cleanup_failed ${String(cleanupError)}`)
        }
        throw error as Error
      } finally {
        try {
          const area = mainWindow?.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
          await abilityDelegatorRegistry.getAbilityDelegator().print(
            `ReaderThumbnailChrome: final_systemArea=${JSON.stringify(area)} probe=${JSON.stringify(ReaderTrialEntryProbe.read())}`)
        } catch (error) { if (!failed) throw error as Error }
      }
    })
  })
}

function readerThumbnailAutoReadTrial(work: string, unit: string): void {
  describe('ReaderThumbnailAutoReadTrial', (): void => {
    it('optionalRtlReaderAdvancesStopsAndReturnsToSameDetail', 0, async (): Promise<void> => {
      clearEntryCaptures(['auto-start', 'auto-stopped', 'auto-closed', 'auto-exception'])
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      let sourceId: string = ''
      let epoch: number = 0
      try {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: 'rtl' } })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const baseline = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotSpread(driver, baseline, site, work, sourceId, 'rtl')
        const clock = await driver.findComponent(ON.id('rkit-auto-read'))
        if (clock === null) throw new Error('Auto-read clock unavailable')
        const rawSeconds = connectReadMode().autoPageSeconds
        const seconds = Number.isFinite(rawSeconds) ? Math.max(1, Math.min(60, Math.round(rawSeconds))) : 3
        await clock.click()
        await captureEntry(driver, 'auto-start')
        let advanced: boolean = false
        const advanceDeadline = Date.now() + seconds * 1000 + 30000
        while (Date.now() < advanceDeadline) {
          expect(ReaderTrialEntryProbe.read().epoch).assertEqual(epoch)
          const label = await driver.findComponent(ON.id('rkit-chrome-page'))
          if (label !== null) {
            const page = Number((await label.getText()).split('/')[0].trim())
            if (page >= 3 && await completedPart(driver, page - 1)) {
              advanced = true
              break
            }
          }
          await driver.delayMs(150)
        }
        expect(advanced).assertTrue()
        const stop = await driver.findComponent(ON.id('rkit-auto-read'))
        if (stop === null) throw new Error('Auto-read stop action unavailable')
        await stop.click()
        const stoppedLabel = await driver.findComponent(ON.id('rkit-chrome-page'))
        if (stoppedLabel === null) throw new Error('Reader page label unavailable after stop')
        const stoppedPage = await stoppedLabel.getText()
        const stableDeadline = Date.now() + seconds * 1000 + 1500
        while (Date.now() < stableDeadline) {
          const currentLabel = await driver.findComponent(ON.id('rkit-chrome-page'))
          if (currentLabel === null) throw new Error('Reader disappeared during stop verification')
          expect(await currentLabel.getText()).assertEqual(stoppedPage)
          expect(ReaderTrialEntryProbe.read().epoch).assertEqual(epoch)
          await driver.delayMs(200)
        }
        await captureEntry(driver, 'auto-stopped')
        await delegator.print(`ReaderThumbnailAutoRead advanced=true stopped_page=${stoppedPage} stable_ms=${seconds * 1000 + 1500} loading_retry_acceptance=false`)
        await driver.pressBack()
        await waitClosed(driver, epoch, sourceId)
        await captureEntry(driver, 'auto-closed')
      } catch (error) {
        try { await captureEntry(driver, 'auto-exception') } catch (_) {}
        try {
          if (await driver.findComponent(ON.id('rkit-trial-navigation')) !== null) {
            await driver.pressBack()
            if (epoch > 0 && sourceId.length > 0) await waitClosed(driver, epoch, sourceId)
          }
        } catch (cleanupError) { console.error(`ReaderThumbnailAutoRead cleanup_failed ${String(cleanupError)}`) }
        throw error as Error
      }
    })
  })
}

function readerThumbnailSaveTrial(work: string, unit: string): void {
  describe('ReaderThumbnailSaveTrial', (): void => {
    it('realDetailRtlSpreadAllowsOneTwoImageSystemSaveAndReturnsToSource', 0, async (): Promise<void> => {
      clearEntryCaptures(['save-menu', 'save-dialog', 'save-saved-reader', 'save-closed', 'save-exception'])
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      let sourceId: string = ''
      let epoch: number = 0
      let dialogAttempted: boolean = false
      const dialogTitle = '允许“NextE”保存 2 张图片？'
      try {
        await delegator.print('ReaderThumbnailSave scope=P1-P2-system-allow album_file_readback_required=true')
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: 'rtl' } })
        const source = await findFirstDetailThumbnail(driver)
        sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const ability = await delegator.getCurrentTopAbility()
        const mainWindow = await window.getLastWindow(ability.context)
        const baseline = ReaderTrialEntryProbe.read().epoch
        await source.click()
        epoch = await waitSnapshotSpread(driver, baseline, site, work, sourceId, 'rtl')
        await waitTrialChrome(driver, mainWindow, true, epoch)
        const save = await driver.findComponent(ON.id('rkit-save-image'))
        if (save === null) throw new Error('Save image action unavailable')
        await save.click()
        let left: Component | null = null
        const menuDeadline = Date.now() + 5000
        while (Date.now() < menuDeadline && left === null) {
          left = await driver.findComponent(ON.id('rkit-save-left'))
          if (left === null) await driver.delayMs(100)
        }
        const right = await driver.findComponent(ON.id('rkit-save-right'))
        const both = await driver.findComponent(ON.id('rkit-save-both'))
        if (left === null || right === null || both === null) throw new Error('Save spread menu unavailable')
        expect(await left.getText()).assertEqual('左侧 · 第 2 页')
        expect(await right.getText()).assertEqual('右侧 · 第 1 页')
        await captureEntry(driver, 'save-menu')
        dialogAttempted = true
        await both.click()
        let allow: Component | null = null
        const dialogDeadline = Date.now() + 15000
        while (Date.now() < dialogDeadline) {
          allow = await driver.findComponent(ON.id('advanced_dialog_button_1').text('允许'))
          if (allow !== null && await driver.findComponent(ON.text(dialogTitle)) !== null) break
          allow = null
          await driver.delayMs(100)
        }
        if (allow === null) throw new Error('Expected NextE two-image save permission dialog unavailable')
        await captureEntry(driver, 'save-dialog')
        await allow.click()
        const dismissedDeadline = Date.now() + 15000
        let dismissed: boolean = false
        while (Date.now() < dismissedDeadline) {
          if (await driver.findComponent(ON.id('advanced_dialog_button_1').text('允许')) === null &&
            await driver.findComponent(ON.text(dialogTitle)) === null) {
            dismissed = true
            break
          }
          await driver.delayMs(100)
        }
        expect(dismissed).assertTrue()
        dialogAttempted = false
        expect(await waitSnapshotSpread(driver, baseline, site, work, sourceId, 'rtl')).assertEqual(epoch)
        await waitTrialChrome(driver, mainWindow, true, epoch)
        await captureEntry(driver, 'save-saved-reader')
        await delegator.print('ReaderThumbnailSave system_allow_completed=true source_pages=1,2 album_file_verified=false external_readback_required=true')
        await driver.pressBack()
        await waitClosed(driver, epoch, sourceId)
        await captureEntry(driver, 'save-closed')
      } catch (error) {
        try { await captureEntry(driver, 'save-exception') } catch (_) {}
        try {
          if (dialogAttempted && await driver.findComponent(ON.text(dialogTitle)) !== null) await driver.pressBack()
          if (await driver.findComponent(ON.id('rkit-save-left')) !== null) await driver.pressBack()
          if (await driver.findComponent(ON.id('rkit-trial-navigation')) !== null) {
            await driver.pressBack()
            if (epoch > 0 && sourceId.length > 0) await waitClosed(driver, epoch, sourceId)
          }
        } catch (cleanupError) { console.error(`ReaderThumbnailSave cleanup_failed ${String(cleanupError)}`) }
        throw error as Error
      }
    })
  })
}

async function waitSharedProductionSpread(driver: Driver): Promise<void> {
  for (let attempt: number = 0; attempt < 100; attempt++) {
    const surface = await driver.findComponent(ON.id('rkit-reading-surface'))
    if (surface !== null && await completedPart(driver, 0) && await completedPart(driver, 1) &&
      await driver.findComponent(ON.id('rkit-entry-preview-image')) === null &&
      await driver.findComponent(ON.id('rkit-entry-source-pending')) === null) {
      const first = await (await driver.findComponent(ON.id('rkit-part-0-whole')
        .within(ON.id('rkit-image-viewport')))).getBounds()
      const second = await (await driver.findComponent(ON.id('rkit-part-1-whole')
        .within(ON.id('rkit-image-viewport')))).getBounds()
      expect(second.right <= first.left + 1).assertTrue()
      expect(await driver.findComponent(ON.id('reader-overlay-navigation')) !== null).assertTrue()
      expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
      return
    }
    await driver.delayMs(250)
  }
  throw new Error('Production shared Reader did not settle to the RTL P1/P2 spread')
}

async function closeSharedProductionReader(driver: Driver): Promise<void> {
  let close = await driver.findComponent(ON.id('rkit-close'))
  if (close === null) {
    const surface = await (await driver.findComponent(ON.id('rkit-reading-surface'))).getBounds()
    await driver.click(Math.round((surface.left + surface.right) / 2),
      Math.round((surface.top + surface.bottom) / 2))
    for (let attempt: number = 0; attempt < 30 && close === null; attempt++) {
      await driver.delayMs(150)
      close = await driver.findComponent(ON.id('rkit-close'))
    }
  }
  if (close === null) throw new Error('Production shared Reader close action was unavailable')
  await close.click()
}

async function waitProductionGridClosed(driver: Driver, sourceId: string): Promise<Component> {
  for (let attempt: number = 0; attempt < 100; attempt++) {
    const returned = await driver.findComponent(ON.id(sourceId).within(ON.type('Grid')))
    if (returned !== null && isAllThumbnailsRoute() &&
      await driver.findComponent(ON.id('reader-overlay-navigation')) === null &&
      !connectReaderThumbnailTransition().active()) return returned
    await driver.delayMs(250)
  }
  throw new Error('Production shared Reader did not return to the same standalone AllThumbnails source')
}

/**
 * In-app variant: the backend is chosen through the existing Debug Settings
 * selector inside one process instead of a `nexte_reader_backend` Want, because
 * any ordinary launch resets the process selector to Legacy.
 */
async function selectBackendInAppThenOpenDetail(
  driver: Driver, work: string, unit: string, backend: NextEReaderBackend): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
  // A plain launch restores whatever route the previous case left behind, so the
  // selector row may not be reachable yet. Return to the retained root first.
  for (let attempt: number = 0; attempt < 80; attempt++) {
    if (await driver.findComponent(ON.id('nexte-root-tab-4')) !== null) break
    if (attempt === 20) connectNavStack().stack.clear(false)
    if (attempt === 79) throw new Error('Normal NextE root was not ready for the in-app entry rehearsal')
    await driver.delayMs(250)
  }
  expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.LEGACY)
  await openBackendSettings(driver)
  await selectBackend(driver, backend)
  await leaveBackendSettings(driver)
  expect(connectNextEReaderBackendSelection().current()).assertEqual(backend)
  const ability = await delegator.getCurrentTopAbility()
  connectNavStack().stack.pushPathByName('GalleryDetail', new GalleryDetailParams(work, unit))
  return ability.context
}

/** Original Debug-Want launch path, retained so both sources stay comparable. */
async function sharedBackendWantContext(
  delegator: object, driver: Driver): Promise<common.UIAbilityContext> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
    bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
    parameters: { nexte_reader_backend: 'shared' },
  })
  for (let attempt: number = 0; attempt < 60; attempt++) {
    if (await driver.findComponent(ON.id('nexte-root-navigation')) !== null) break
    if (attempt === 59) throw new Error('Normal NextE root was not ready')
    await driver.delayMs(250)
  }
  expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.SHARED)
  const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  return ability.context
}

function readerProductionSharedThumbnailEntryTrial(work: string, unit: string, inAppBackend: boolean): void {
  describe(inAppBackend
    ? 'ReaderProductionInAppThumbnailEntryTrial'
    : 'ReaderProductionSharedThumbnailEntryTrial', (): void => {
    it('normalDetailThumbnailUsesSharedForwardAndReturnTransition', 0, async (): Promise<void> => {
      clearEntryCaptures(['production-shared-source', 'production-shared-reader',
        'production-shared-closed', 'production-shared-exception'])
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      let context: common.UIAbilityContext | null = null
      let originalMode: string = ''
      let originalDoublePage: boolean = false
      let originalSpreadLayout: string = ''
      let originalCrop: boolean = false
      let settingsSaved: boolean = false
      try {
        context = inAppBackend
          ? await selectBackendInAppThenOpenDetail(driver, work, unit, NextEReaderBackend.SHARED)
          : await sharedBackendWantContext(delegator, driver)
        const mode = connectReadMode()
        originalMode = mode.mode
        originalDoublePage = mode.doublePageEnabled
        originalSpreadLayout = mode.spreadLayoutMode
        originalCrop = mode.cropBordersPaged
        settingsSaved = true
        await ReadModeSettings.setMode(context, ReadMode.RTL)
        await ReadModeSettings.setDoublePageEnabled(context, true)
        await ReadModeSettings.setSpreadLayoutMode(context, ReadSpreadLayout.JOINED)
        await ReadModeSettings.setCropBordersPaged(context, false)
        if (!inAppBackend) connectNavStack().stack.pushPathByName('GalleryDetail', new GalleryDetailParams(work, unit))
        const source = await findFirstDetailThumbnail(driver)
        const sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const before = await source.getBounds()
        await captureEntry(driver, 'production-shared-source')
        await source.click()
        await waitSharedProductionSpread(driver)
        await captureEntry(driver, 'production-shared-reader')
        await closeSharedProductionReader(driver)
        for (let attempt: number = 0; attempt < 100; attempt++) {
          const returned = await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane')))
          if (returned !== null && await driver.findComponent(ON.id('reader-overlay-navigation')) === null &&
            !connectReaderThumbnailTransition().active()) {
            const after = await returned.getBounds()
            expect(Math.abs(before.left - after.left) <= 1 && Math.abs(before.right - after.right) <= 1 &&
              Math.abs(before.top - after.top) <= 1 && Math.abs(before.bottom - after.bottom) <= 1).assertTrue()
            await captureEntry(driver, 'production-shared-closed')
            console.info('[ReaderProductionSharedThumbnailEntryTrial] backend=shared normalDetail=true ' +
              'forwardSettled=true rtlSpread=true returnedToSameSource=true')
            return
          }
          await driver.delayMs(250)
        }
        throw new Error('Production shared Reader did not return to the same Detail thumbnail')
      } catch (error) {
        try { await captureEntry(driver, 'production-shared-exception') } catch (_) {}
        throw error as Error
      } finally {
        connectNextEReaderBackendSelection().selectForRehearsal(NextEReaderBackend.LEGACY, true)
        if (settingsSaved && context !== null) {
          await ReadModeSettings.setMode(context, originalMode)
          await ReadModeSettings.setDoublePageEnabled(context, originalDoublePage)
          await ReadModeSettings.setSpreadLayoutMode(context, originalSpreadLayout)
          await ReadModeSettings.setCropBordersPaged(context, originalCrop)
        }
      }
    })

    it('standaloneAllThumbnailsUsesSharedForwardAndReturnTransition', 0, async (): Promise<void> => {
      clearEntryCaptures(['production-shared-grid-source', 'production-shared-grid-reader',
        'production-shared-grid-closed', 'production-shared-grid-exception'])
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      let context: common.UIAbilityContext | null = null
      let originalMode: string = ''
      let originalDoublePage: boolean = false
      let originalSpreadLayout: string = ''
      let originalCrop: boolean = false
      let settingsSaved: boolean = false
      try {
        context = inAppBackend
          ? await selectBackendInAppThenOpenDetail(driver, work, unit, NextEReaderBackend.SHARED)
          : await sharedBackendWantContext(delegator, driver)
        if (!inAppBackend) {
          connectNavStack().stack.clear(false)
          await driver.delayMs(300)
        }
        const mode = connectReadMode()
        originalMode = mode.mode
        originalDoublePage = mode.doublePageEnabled
        originalSpreadLayout = mode.spreadLayoutMode
        originalCrop = mode.cropBordersPaged
        settingsSaved = true
        await ReadModeSettings.setMode(context, ReadMode.RTL)
        await ReadModeSettings.setDoublePageEnabled(context, true)
        await ReadModeSettings.setSpreadLayoutMode(context, ReadSpreadLayout.JOINED)
        await ReadModeSettings.setCropBordersPaged(context, false)
        if (!inAppBackend) connectNavStack().stack.pushPathByName('GalleryDetail', new GalleryDetailParams(work, unit))
        const source = await openFirstGridThumbnail(driver)
        const sourceId = await source.getId()
        expect(new RegExp(FIRST_GRID_THUMBNAIL).test(sourceId)).assertTrue()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const before = await source.getBounds()
        await captureEntry(driver, 'production-shared-grid-source')
        await source.click()
        await waitSharedProductionSpread(driver)
        await captureEntry(driver, 'production-shared-grid-reader')
        await closeSharedProductionReader(driver)
        const returned = await waitProductionGridClosed(driver, sourceId)
        const after = await returned.getBounds()
        expect(Math.abs(before.left - after.left) <= 1 && Math.abs(before.right - after.right) <= 1 &&
          Math.abs(before.top - after.top) <= 1 && Math.abs(before.bottom - after.bottom) <= 1).assertTrue()
        await captureEntry(driver, 'production-shared-grid-closed')
        console.info('[ReaderProductionSharedThumbnailEntryTrial] backend=shared standaloneAllThumbnails=true ' +
          'forwardSettled=true rtlSpread=true returnedToSameSource=true')
      } catch (error) {
        try { await captureEntry(driver, 'production-shared-grid-exception') } catch (_) {}
        throw error as Error
      } finally {
        connectNextEReaderBackendSelection().selectForRehearsal(NextEReaderBackend.LEGACY, true)
        if (settingsSaved && context !== null) {
          await ReadModeSettings.setMode(context, originalMode)
          await ReadModeSettings.setDoublePageEnabled(context, originalDoublePage)
          await ReadModeSettings.setSpreadLayoutMode(context, originalSpreadLayout)
          await ReadModeSettings.setCropBordersPaged(context, originalCrop)
        }
        connectNavStack().stack.clear(false)
      }
    })
  })
}

/** Only the explicitly selected real-device protocol may execute this source-entry sequence. */
export default function readerThumbnailEntryTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] === 'ReaderProductionSettingsRestoreTrial') {
    readerProductionSettingsRestoreTrial()
    return
  }
  if (args['-s class'] === 'ReaderProductionCropRestoreTrial') {
    readerProductionSettingsRestoreTrial(true)
    return
  }
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  const direction = args['-s readerLabEntryDirection'] === 'rtl' ? 'rtl' : 'ltr'
  if (args['-s class'] === 'ReaderProductionSharedThumbnailEntryTrial' && typeof work === 'string' &&
    work.length > 0 && typeof unit === 'string' && unit.length > 0) {
    readerProductionSharedThumbnailEntryTrial(work, unit, false)
    return
  }
  if (args['-s class'] === 'ReaderProductionInAppThumbnailEntryTrial' && typeof work === 'string' &&
    work.length > 0 && typeof unit === 'string' && unit.length > 0) {
    readerProductionSharedThumbnailEntryTrial(work, unit, true)
    return
  }
  if ((args['-s class'] === 'ReaderProductionCropTrial' || args['-s class'] === 'ReaderProductionCropSpreadTrial' ||
    args['-s class'] === 'ReaderProductionCropContinuousTrial' || args['-s class'] === 'ReaderProductionCropZoomTrial') && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerProductionCropTrial(work, unit, args['-s class'] === 'ReaderProductionCropSpreadTrial' ? 'spread' :
      args['-s class'] === 'ReaderProductionCropContinuousTrial' ? 'continuous' :
      args['-s class'] === 'ReaderProductionCropZoomTrial' ? 'zoom' : 'single')
    return
  }
  if (args['-s class'] === 'ReaderProductionOriginalMenuTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerProductionSettledRotationTrial(work, unit, true)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailContinuousReflowTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailContinuousReflowTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailContinuousBoundaryRotationTrial' &&
    typeof work === 'string' && work.length > 0 && typeof unit === 'string' && unit.length > 0) {
    readerThumbnailContinuousBoundaryRotationTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailContinuousInterpolationTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailContinuousInterpolationTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailAutoReadTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailAutoReadTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailSaveTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailSaveTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailChromeTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailChromeTrial(work, unit)
    return
  }
  if (args['-s class'] === 'ReaderProductionSettledRotationTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerProductionSettledRotationTrial(work, unit)
    return
  }
  if ((args['-s class'] === 'ReaderThumbnailMovingRotationTrial' || args['-s class'] === 'ReaderThumbnailSettledRotationTrial') &&
    typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailMovingRotationTrial(work, unit, args['-s class'] === 'ReaderThumbnailSettledRotationTrial')
    return
  }
  if (args['-s class'] === 'ReaderThumbnailSettledRotationNavigationTrial' &&
    typeof work === 'string' && work.length > 0 && typeof unit === 'string' && unit.length > 0) {
    readerThumbnailMovingRotationTrial(work, unit, true, true)
    return
  }
  if (args['-s class'] === 'ReaderThumbnailGridEntryTrial' && typeof work === 'string' && work.length > 0 &&
    typeof unit === 'string' && unit.length > 0) {
    readerThumbnailGridEntryTrial(work, unit, direction)
    return
  }
  if (args['-s class'] !== 'ReaderThumbnailEntryTrial' || typeof work !== 'string' || work.length === 0 ||
    typeof unit !== 'string' || unit.length === 0) return
  describe('ReaderThumbnailEntryTrial', (): void => {
    it('realDetailSnapshotHandsOffToSpreadAndClosesToSameSource', 0, async (): Promise<void> => {
      clearEntryCaptures()
      const driver = Driver.create()
      const sourceProbe = connectNextEReaderLabContextProbe()
      sourceProbe.resetSource(work)
      try {
        await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabChrome: 'true',
            readerLabThumbnailEntry: 'true', readerLabEntryLayout: 'spread', readerLabEntryDirection: direction },
        })
        const source = await findFirstDetailThumbnail(driver)
        const sourceId = await source.getId()
        const site = ReaderTrialEntryRelay.currentSite()
        await waitSnapshotReady(driver, site, sourceId)
        const liveSource = await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane')))
        const before = await liveSource.getBounds()
        const rootBefore = await (await driver.findComponent(ON.id('nexte-root-navigation'))).getBounds()
        expect(before.right > before.left && before.bottom > before.top &&
          before.left >= rootBefore.left && before.right <= rootBefore.right &&
          before.top >= rootBefore.top && before.bottom <= rootBefore.bottom).assertTrue()
        await captureEntry(driver, 'source')
        const baselineEpoch = ReaderTrialEntryProbe.read().epoch
        expect(ReaderTrialEntryRelay.isSnapshotReady(site, sourceId)).assertTrue()
        await liveSource.click()
        const epoch = await waitSnapshotSpread(driver, baselineEpoch, site, work, sourceId, direction)
        let sourceFacts = sourceProbe.readSource(work)
        for (let attempt: number = 0; attempt < 40 && sourceFacts.kind.length === 0; attempt++) {
          await driver.delayMs(100)
          sourceFacts = sourceProbe.readSource(work)
        }
        expect(sourceFacts.kind).assertEqual('hostEntry')
        expect(sourceFacts.index).assertEqual(0)
        expect(sourceFacts.fileCount > 0 && sourceFacts.seedCount > 0 && sourceFacts.exactImagePage).assertTrue()
        await abilityDelegatorRegistry.getAbilityDelegator().print(
          `ReaderThumbnailEntryTrial source=${sourceFacts.kind} index=${sourceFacts.index} ` +
          `pages=${sourceFacts.fileCount} seeds=${sourceFacts.seedCount} exactImagePage=${sourceFacts.exactImagePage}`,
        )
        await captureEntry(driver, 'reader')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        await waitClosed(driver, epoch, sourceId)
        const after = await (await driver.findComponent(ON.id(sourceId).within(ON.id('gallery-detail-pane')))).getBounds()
        const rootAfter = await (await driver.findComponent(ON.id('nexte-root-navigation'))).getBounds()
        expect(Math.abs(before.left - after.left) <= 1 && Math.abs(before.right - after.right) <= 1 &&
          Math.abs(before.top - after.top) <= 1 && Math.abs(before.bottom - after.bottom) <= 1).assertTrue()
        expect(rootAfter.left).assertEqual(rootBefore.left)
        expect(rootAfter.right).assertEqual(rootBefore.right)
        expect(rootAfter.top).assertEqual(rootBefore.top)
        expect(rootAfter.bottom).assertEqual(rootBefore.bottom)
        await captureEntry(driver, 'closed')
      } catch (error) {
        await captureEntry(driver, 'exception')
        throw error as Error
      }
    })
  })
}
