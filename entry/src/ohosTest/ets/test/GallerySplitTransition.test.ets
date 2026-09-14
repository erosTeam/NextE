import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, ON, MatchPattern } from '@kit.TestKit'
import { window } from '@kit.ArkUI'
import { fileIo } from '@kit.CoreFileKit'
import {
  connectGalleryDetailTransition, connectGalleryDetailTransitionSettings, connectListMode,
  connectNavStack, connectTabletLayout, GalleryDetailParams, GalleryDetailTransitionPhase,
  ListMode, TABLET_LAYOUT_LANDSCAPE_ONLY,
} from 'shared'

const SOURCE_PATTERN: string = '^gallery-list-primary-[0-9]+-waterfall-[0-9]+$'

async function capture(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  for (const suffix of ['json', 'png']) {
    const path = `${cache}/gallery-split-${name}.${suffix}`
    if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    expect(suffix === 'json' ? await driver.dumpLayout(path) : await driver.screenCap(path)).assertTrue()
  }
}

async function waitSplit(driver: Driver, mainWindow: window.Window, split: boolean): Promise<void> {
  for (let i = 0; i < 50; i++) {
    const rect = mainWindow.getWindowProperties().windowRect
    if (connectNavStack().isSplitMode === split &&
      (split ? rect.width > rect.height : rect.height > rect.width)) {
      // HDS publishes its physical mode before the retained card's next render finishes.
      await driver.delayMs(600)
      return
    }
    await driver.delayMs(200)
  }
  throw new Error(`Physical ${split ? 'landscape Split' : 'portrait Stack'} did not settle`)
}

async function card(driver: Driver, source: string): Promise<Component> {
  const matches = await driver.findComponents(ON.id(source).type('FlowItem'))
  if (matches.length !== 1) throw new Error(`Expected one real Home FlowItem: ${source}, got ${matches.length}`)
  return matches[0]
}

async function assertCard(driver: Driver, source: string): Promise<void> {
  await card(driver, source)
  const cover = await driver.findComponent(ON.id(`${source}-cover`))
  if (cover === null) throw new Error(`Source cover missing: ${source}`)
  const rect = await cover.getBounds()
  const root = await (await driver.findComponent(ON.id('nexte-root-navigation'))).getBounds()
  expect(rect.right > rect.left && rect.bottom > rect.top).assertTrue()
  expect(rect.left >= root.left && rect.right <= root.right &&
    rect.top >= root.top && rect.bottom <= root.bottom).assertTrue()
  const images = await driver.findComponents(ON.type('Image').within(ON.id(`${source}-cover`)))
  const labels = await driver.findComponents(ON.type('Text').within(ON.id(source)))
  expect(images.length > 0 && labels.length > 0).assertTrue()
  // These are native tree assertions; the named screenshot still needs pixel/visibility review.
}

function topGalleryId(): string {
  const stack = connectNavStack().stack
  const names = stack.getAllPathName()
  if (names.length !== 1 || names[0] !== 'GalleryDetail') return ''
  const params = stack.getParamByIndex(0) as GalleryDetailParams
  return params.gid
}

async function openCard(driver: Driver, source: string): Promise<void> {
  await (await card(driver, source)).click()
  const state = connectGalleryDetailTransition()
  for (let i = 0; i < 50; i++) {
    if (state.phase === GalleryDetailTransitionPhase.OPEN && state.sourceComponentId === source &&
      state.routeDestinationId.length > 0 && topGalleryId() === state.galleryId) return
    await driver.delayMs(200)
  }
  throw new Error(`Card did not settle with its route-owned transition: ${source}`)
}

async function waitReturned(driver: Driver, source: string): Promise<void> {
  for (let i = 0; i < 50; i++) {
    if (connectNavStack().stack.getAllPathName().length === 0 &&
      !connectGalleryDetailTransition().eligible) {
      await assertCard(driver, source)
      return
    }
    await driver.delayMs(200)
  }
  throw new Error(`Back did not restore the Home source: ${source}`)
}

async function findSources(driver: Driver): Promise<string[]> {
  // The leased discovery must establish real, loaded Home with a global/waterfall profile override.
  // Pick the first fully visible row from current bounds, never device-specific coordinates.
  for (let i = 0; i < 40; i++) {
    const root = await driver.findComponent(ON.id('nexte-root-navigation'))
    if (root !== null) {
      const bounds = await root.getBounds()
      const candidates = await driver.findComponents(ON.id(SOURCE_PATTERN, MatchPattern.REG_EXP).type('FlowItem'))
      const sources: string[] = []
      let rowTop: number = -1
      for (const candidate of candidates) {
        const rect = await candidate.getBounds()
        if (rect.right <= rect.left || rect.bottom <= rect.top || rect.top < bounds.top ||
          rect.bottom > bounds.bottom || rect.left < bounds.left || rect.right > bounds.right) continue
        if (rowTop < 0 || rect.top < rowTop - 1) {
          sources.length = 0
          rowTop = rect.top
        }
        if (Math.abs(rect.top - rowTop) <= 1) sources.push(await candidate.getId())
      }
      if (sources.length >= 2) return [sources[0], sources[1]]
    }
    await driver.delayMs(300)
  }
  throw new Error('Home requires two loaded, fully visible waterfall cards in the first visible row')
}

/** Opt-in real Home trial, matching NextN's six named image states per mode. */
export default function gallerySplitTransitionTest(): void {
  if (abilityDelegatorRegistry.getArguments().parameters['-s class'] !== 'GallerySplitTransitionTrial') return
  describe('GallerySplitTransitionTrial', (): void => {
    it('retainsVisibleSourcesAcrossSplitBackReplacementAndStackReturn', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      await driver.delayMs(1500)
      const ability = await delegator.getCurrentTopAbility()
      const mainWindow = await window.getLastWindow(ability.context)
      const orientation = mainWindow.getPreferredOrientation()
      const tablet = connectTabletLayout(), presentation = connectListMode()
      const settings = connectGalleryDetailTransitionSettings()
      const originalTablet = tablet.mode, originalPresentation = presentation.mode, originalTransition = settings.mode
      let checkpoint = 'start'
      try {
        // Do not clear a pre-existing route/transition belonging to another scenario.
        expect(connectNavStack().stack.getAllPathName().length).assertEqual(0)
        expect(connectGalleryDetailTransition().eligible).assertFalse()
        expect(connectGalleryDetailTransition().suspendedDepth()).assertEqual(0)
        tablet.mode = TABLET_LAYOUT_LANDSCAPE_ONLY
        presentation.mode = ListMode.WATERFALL
        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        await waitSplit(driver, mainWindow, false)
        const sources = await findSources(driver)
        const a = sources[0], b = sources[1]
        const bGalleryId = b.substring(b.lastIndexOf('-') + 1)
        console.info(`[GallerySplitTrial] sources=${a},${b}`)
        for (const mode of ['coverExpand', 'seamless']) {
          settings.mode = mode
          checkpoint = `${mode}-source`
          await assertCard(driver, a); await assertCard(driver, b); await capture(driver, checkpoint)
          await openCard(driver, a)
          expect(connectGalleryDetailTransition().mode).assertEqual(mode)
          await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
          await waitSplit(driver, mainWindow, true)
          checkpoint = `${mode}-split`
          await assertCard(driver, a); await capture(driver, checkpoint)
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
          await waitSplit(driver, mainWindow, false)
          await driver.pressBack(); await waitReturned(driver, a)
          checkpoint = `${mode}-stack-return`; await capture(driver, checkpoint)
          await openCard(driver, a)
          await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
          await waitSplit(driver, mainWindow, true)
          await driver.pressBack(); await waitReturned(driver, a)
          checkpoint = `${mode}-split-back`; await capture(driver, checkpoint)
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
          await waitSplit(driver, mainWindow, false)
          await openCard(driver, a)
          await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
          await waitSplit(driver, mainWindow, true)
          await assertCard(driver, a); await assertCard(driver, b)
          checkpoint = `${mode}-replaced`
          await (await card(driver, b)).click()
          for (let i = 0; i < 50; i++) {
            if (topGalleryId() === bGalleryId && !connectGalleryDetailTransition().eligible &&
              connectNavStack().secondaryEntryGalleryGid === bGalleryId) break
            await driver.delayMs(200)
          }
          expect(topGalleryId()).assertEqual(bGalleryId)
          expect(connectNavStack().secondaryEntryGalleryGid).assertEqual(bGalleryId)
          expect(connectGalleryDetailTransition().eligible).assertFalse()
          expect(connectGalleryDetailTransition().suspendedDepth()).assertEqual(0)
          await assertCard(driver, a); await capture(driver, checkpoint)
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
          await waitSplit(driver, mainWindow, false)
          await driver.pressBack(); await waitReturned(driver, a)
          checkpoint = `${mode}-replacement-return`; await capture(driver, checkpoint)
          await openCard(driver, a)
          await driver.pressBack(); await waitReturned(driver, a)
          console.info(`[GallerySplitTrial] functional assertions passed mode=${mode}; screenshots need review`)
        }
      } catch (error) {
        console.error(`[GallerySplitTrial] failed checkpoint=${checkpoint} error=${error}`)
        try { await capture(driver, 'failure') } catch (captureError) {
          console.error(`[GallerySplitTrial] failure capture error=${captureError}`)
        }
        throw error as Error
      } finally {
        tablet.mode = originalTablet
        presentation.mode = originalPresentation
        settings.mode = originalTransition
        await mainWindow.setPreferredOrientation(orientation)
        console.info(`[GallerySplitTrial] restored preferences orientation=${orientation}`)
      }
    })
  })
}
