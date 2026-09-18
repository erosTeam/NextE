import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON, PointerMatrix, Rect } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import { window } from '@kit.ArkUI'

class SpreadReachImage {
  id: string
  bounds: Rect
  constructor(id: string, bounds: Rect) { this.id = id; this.bounds = bounds }
}

async function captureSpread(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  const layout = `${cache}/rkit-spread-${name}.json`
  const screen = `${cache}/rkit-spread-${name}.png`
  if (fileIo.accessSync(layout)) fileIo.unlinkSync(layout)
  if (fileIo.accessSync(screen)) fileIo.unlinkSync(screen)
  if (typeof driver.dumpLayout === 'function') expect(await driver.dumpLayout(layout)).assertTrue()
  else {
    const result = await delegator.executeShellCommand(`uitest dumpLayout -p /data/local/tmp/rkit-spread-${name}.json`, 15)
    expect(result.exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(screen)).assertTrue()
}

async function spreadPage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}

async function spreadImage(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) return
    await driver.delayMs(400)
  }
  expect(false).assertTrue()
}

async function spreadSwipe(driver: Driver, vertical: boolean, forward: boolean): Promise<void> {
  const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
  const x = Math.round((bounds.left + bounds.right) / 2)
  const y = Math.round((bounds.top + bounds.bottom) / 2)
  const extent = vertical ? bounds.bottom - bounds.top : bounds.right - bounds.left
  // Cross half the native page even at a non-fling velocity; the initial 46% slow
  // trajectory could legitimately settle on the same page and was not a paging acceptance.
  const offset = Math.round(extent * 0.31) * (forward ? 1 : -1)
  await driver.swipe(vertical ? x : x + offset, vertical ? y + offset : y,
    vertical ? x : x - offset, vertical ? y - offset : y, 700)
  await driver.delayMs(700)
}


async function spreadImageBounds(driver: Driver, source: number): Promise<Rect> {
  const part = await driver.findComponent(ON.id(`rkit-part-${source}-whole`).within(ON.id('rkit-image-viewport')))
  expect(part !== null).assertTrue()
  const p = await part.getBounds()
  const images = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
  const matches: Rect[] = []
  for (const image of images) {
    const bounds = await image.getBounds()
    if (bounds.right > bounds.left && bounds.bottom > bounds.top &&
      bounds.left >= p.left - 2 && bounds.top >= p.top - 2 &&
      bounds.right <= p.right + 2 && bounds.bottom <= p.bottom + 2) matches.push(bounds)
  }
  expect(matches.length).assertEqual(1)
  return matches[0]
}

async function spreadBounds(driver: Driver, source: number, label: string): Promise<void> {
  const part = await driver.findComponent(ON.id(`rkit-part-${source}-whole`).within(ON.id('rkit-image-viewport')))
  const p = await part.getBounds(), i = await spreadImageBounds(driver, source)
  console.info(`[ReaderSpreadLayoutTest] ${label} source=${source} part=${p.left},${p.top},${p.right},${p.bottom} image=${i.left},${i.top},${i.right},${i.bottom}`)
}

async function spreadPair(driver: Driver, source: number, label: string): Promise<void> {
  await spreadImage(driver)
  expect(await spreadPage(driver)).assertEqual(source + 1)
  await spreadBounds(driver, source, label)
  await spreadBounds(driver, source + 1, label)
  await captureSpread(driver, label)
}

async function spreadToggle(driver: Driver): Promise<void> {
  await (await driver.findComponent(ON.id('rkit-reading-mode'))).click()
  for (let attempt = 0; attempt < 30; attempt++) {
    if (await driver.findComponent(ON.id('rkit-spread-layout')) !== null) break
    await driver.delayMs(100)
  }
  expect(await driver.findComponent(ON.id('rkit-spread-layout')) !== null).assertTrue()
  await (await driver.findComponent(ON.id('rkit-spread-layout'))).click()
  await driver.delayMs(700)
}

/** Named real-input trial; unequal source ratios require separate original-metadata proof. */
export default function readerSpreadLayoutTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork'], unit = args['-s readerLabUnit']
  const requested = Number(args['-s readerLabPage'] ?? '0')
  const horizontalReach = args['-s class'] === 'ReaderSpreadHorizontalReachTrial'
  if ((!horizontalReach && args['-s class'] !== 'ReaderSpreadLayoutTrial') || typeof work !== 'string' || work.length === 0) return
  describe(horizontalReach ? 'ReaderSpreadHorizontalReachTrial' : 'ReaderSpreadLayoutTrial', (): void => {
    it('joinedSplitGestureRotationAndSingleton', 0, async (): Promise<void> => {
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const source = Number.isFinite(requested) ? Math.max(0, Math.floor(requested / 2) * 2) : 0
      let mainWindow: window.Window | null = null
      let originalOrientation: window.Orientation | null = null
      let primaryFailure = false
      try {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: work, readerLabUnit: typeof unit === 'string' ? unit : '',
            readerLabPage: String(source), readerLabChrome: 'true', readerLabVolumeKeys: 'false',
            // Start from single-page: this case toggles spread itself. A device that persists a spread
            // layout would otherwise open two panes and fail on trial geometry, not product behavior
            // (the same Debug-only launch-parameter pin the RTL direction case uses).
            readerLabEntryLayout: 'single',
            // This trial asserts LTR geometry (slider right edge = last page; "forward" swipe = next).
            // Pin direction so an RTL-persisted device cannot reverse the slider/gesture axis and
            // fail on trial geometry rather than product behavior. Debug-only Want; never persisted.
            readerLabEntryDirection: 'ltr' } })
        await driver.delayMs(1800)
        const ability = await delegator.getCurrentTopAbility()
        mainWindow = await window.getLastWindow(ability.context)
        originalOrientation = mainWindow.getPreferredOrientation()
        await spreadImage(driver)
        const total = Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[1].trim())
        expect(total >= 3 && source + 1 < total).assertTrue()
        await (await driver.findComponent(ON.id('rkit-toggle-spread'))).click()
        await driver.delayMs(700)
        await spreadPair(driver, source, 'joined')
        await spreadToggle(driver)
        await spreadPair(driver, source, 'split')
        const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
        const x = Math.round((viewport.left + viewport.right) / 2)
        const y = Math.round((viewport.top + viewport.bottom) / 2)
        const firstImage = await spreadImageBounds(driver, source)
        const secondImage = await spreadImageBounds(driver, source + 1)
        const unionWidth = Math.max(firstImage.right, secondImage.right) - Math.min(firstImage.left, secondImage.left)
        const unionHeight = Math.max(firstImage.bottom, secondImage.bottom) - Math.min(firstImage.top, secondImage.top)
        const verticalPan = unionHeight * 2 > viewport.bottom - viewport.top
        const horizontalPan = unionWidth * 2 > viewport.right - viewport.left
        console.info(`[ReaderSpreadLayoutTest] pan_sample vertical=${verticalPan} horizontal=${horizontalPan} union=${unionWidth},${unionHeight}`)
        expect(verticalPan || horizontalPan).assertTrue()
        await driver.doubleClick(x, y); await driver.delayMs(500)
        await captureSpread(driver, 'zoom-before-pan')
        if (horizontalReach) {
          const beforeImages = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
          const before: SpreadReachImage[] = []
          for (const image of beforeImages) {
            const id = await image.getId()
            expect(id.length > 0 && before.every((item: SpreadReachImage): boolean => item.id !== id)).assertTrue()
            before.push(new SpreadReachImage(id, await image.getBounds()))
          }
          expect(before.length >= 2).assertTrue()
          console.info('[ReaderSpreadLayoutTest] horizontal_reach_2x_begin')
          await spreadSwipe(driver, false, true)
          expect(await spreadPage(driver)).assertEqual(source + 1)
          await captureSpread(driver, 'zoom-horizontal-after')
          let moved = false
          const leftImages: SpreadReachImage[] = []
          const afterImages = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
          expect(afterImages !== null && afterImages.length > 0).assertTrue()
          for (const image of afterImages) {
            const id = await image.getId()
            const original = before.find((item: SpreadReachImage): boolean => item.id === id)
            if (original === undefined) continue
            expect(leftImages.every((item: SpreadReachImage): boolean => item.id !== id)).assertTrue()
            const current = await image.getBounds()
            leftImages.push(new SpreadReachImage(original.id, current))
            const dxLeft = current.left - original.bounds.left
            const dxRight = current.right - original.bounds.right
            console.info(`[ReaderSpreadLayoutTest] horizontal_image id=${original.id} dxLeft=${dxLeft} dxRight=${dxRight}`)
            if (Math.abs(dxLeft) > 2 || Math.abs(dxRight) > 2) moved = true
          }
          expect(moved).assertTrue()
          await spreadSwipe(driver, false, false)
          expect(await spreadPage(driver)).assertEqual(source + 1)
          await captureSpread(driver, 'zoom-horizontal-reverse')
          let reversed = false
          const reverseImages = await driver.findComponents(ON.type('Image').within(ON.id('rkit-image-viewport')))
          expect(reverseImages !== null && reverseImages.length > 0).assertTrue()
          for (const leftImage of leftImages) {
            const original = before.find((item: SpreadReachImage): boolean => item.id === leftImage.id)
            expect(original !== undefined).assertTrue()
            if (original === undefined) continue
            let current: Rect | null = null
            for (const image of reverseImages) {
              if (await image.getId() === leftImage.id) {
                expect(current === null).assertTrue()
                current = await image.getBounds()
              }
            }
            if (current === null) continue
            const outwardLeft = leftImage.bounds.left - original.bounds.left
            const outwardRight = leftImage.bounds.right - original.bounds.right
            const returnLeft = current.left - leftImage.bounds.left
            const returnRight = current.right - leftImage.bounds.right
            console.info(`[ReaderSpreadLayoutTest] horizontal_reverse id=${leftImage.id} dxLeft=${returnLeft} dxRight=${returnRight}`)
            if ((Math.abs(outwardLeft) > 2 && Math.abs(returnLeft) > 2 && outwardLeft * returnLeft < 0) ||
              (Math.abs(outwardRight) > 2 && Math.abs(returnRight) > 2 && outwardRight * returnRight < 0)) reversed = true
          }
          expect(reversed).assertTrue()
          console.info('[ReaderSpreadLayoutTest] horizontal_reach_image_displacement_passed_original_pixel_review_pending')
          return
        }
        await spreadSwipe(driver, verticalPan, true)
        expect(await spreadPage(driver)).assertEqual(source + 1)
        await captureSpread(driver, 'zoom-after-pan')
        console.info('[ReaderSpreadLayoutTest] zoom_requires_same_pid_transform_and_original_pixels')
        // Set pinchAdjusted before the established one-double-tap fit recovery.
        const points = PointerMatrix.create(2, 12)
        for (let step = 0; step < 12; step++) {
          const offset = Math.round((viewport.right - viewport.left) * (0.16 + 0.04 * step / 11))
          points.setPoint(0, step, { x: x - offset, y })
          points.setPoint(1, step, { x: x + offset, y })
        }
        expect(await driver.injectMultiPointerAction(points, 600)).assertTrue()
        await driver.delayMs(400)
        await driver.doubleClick(x, y); await driver.delayMs(500)
        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
        await driver.delayMs(1400)
        const landscape = await driver.getDisplaySize()
        expect(landscape.x > landscape.y).assertTrue()
        await spreadPair(driver, source, 'split-landscape')
        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        await driver.delayMs(1400)
        const portrait = await driver.getDisplaySize()
        expect(portrait.y > portrait.x).assertTrue()
        await spreadPair(driver, source, 'split-portrait-return')
        await spreadToggle(driver)
        await spreadPair(driver, source, 'joined-return')
        // With even total, a cover singleton shifts parity so the last page is also alone.
        if (total % 2 === 0) {
          await (await driver.findComponent(ON.id('rkit-reading-mode'))).click()
          await (await driver.findComponent(ON.text('封面：单'))).click()
          await driver.delayMs(600)
        }
        const slider = await (await driver.findComponent(ON.id('rkit-source-slider'))).getBounds()
        await driver.click(slider.right - 2, Math.round((slider.top + slider.bottom) / 2))
        await driver.delayMs(900); await spreadImage(driver)
        expect(await spreadPage(driver)).assertEqual(total)
        await spreadBounds(driver, total - 1, 'singleton-joined')
        expect(await driver.findComponent(ON.id(`rkit-part-${total - 2}-whole`).within(ON.id('rkit-image-viewport')))).assertNull()
        await captureSpread(driver, 'singleton-joined')
        await spreadToggle(driver)
        expect(await spreadPage(driver)).assertEqual(total)
        await spreadBounds(driver, total - 1, 'singleton-split')
        await captureSpread(driver, 'singleton-split')
      } catch (error) {
        primaryFailure = true
        console.error(`[ReaderSpreadLayoutTest] failure=${(error as Error).message}`)
        try { await captureSpread(driver, 'exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          try {
            if (mainWindow !== null && originalOrientation !== null) {
              await mainWindow.setPreferredOrientation(originalOrientation)
              expect(mainWindow.getPreferredOrientation()).assertEqual(originalOrientation)
              console.info(`[ReaderSpreadLayoutTest] restored_orientation=${originalOrientation}`)
            }
          } finally {
            if (await driver.findComponent(ON.id('rkit-vertical-paged')) !== null) {
              await driver.pressBack()
              await driver.delayMs(300)
            }
            const close = await driver.findComponent(ON.id('rkit-close'))
            if (close !== null) await close.click()
            else if (await driver.findComponent(ON.id('rkit-native-pager')) !== null) await driver.pressBack()
            await driver.delayMs(700)
            expect(await driver.findComponent(ON.id('rkit-native-pager'))).assertNull()
            await captureSpread(driver, 'closed')
          }
        } catch (cleanupError) {
          console.error(`[ReaderSpreadLayoutTest] cleanup_failure=${(cleanupError as Error).message}`)
          if (!primaryFailure) throw cleanupError as Error
        }
      }
    })
  })
}
