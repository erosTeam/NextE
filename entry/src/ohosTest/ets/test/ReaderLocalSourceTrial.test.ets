import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { relationalStore } from '@kit.ArkData'
import {
  AppStrings,
  connectDownloadQueue,
  connectGalleryReadProgress,
  connectNextEReaderBackendSelection,
  DownloadGalleryTask,
  DownloadGalleryTaskStatus,
  DownloadImageSeed,
  GalleryReadProgressSettings,
  NextEReaderBackend,
  ReadProgressEntry,
} from 'shared'

const FIXTURE_GID: string = '9876543210123'
const FIXTURE_TOKEN: string = 'reader-local-source-fixture'

function writeFixture(path: string, bytes: Uint8Array): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
  try {
    const written = fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
    if (written !== bytes.byteLength) throw new Error('local_reader_fixture_write_incomplete')
  } finally {
    fileIo.closeSync(file)
  }
}

async function fixtureTask(paths: string[]): Promise<DownloadGalleryTask> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
  const rawNames: string[] = ['comic_translation_live_eval_page_01.jpg', 'comic_translation_live_eval_page_02.jpg']
  const seeds: DownloadImageSeed[] = []
  for (let index: number = 0; index < rawNames.length; index++) {
    const bytes = await context.resourceManager.getRawFileContent(rawNames[index])
    const path = `${context.cacheDir}/rkit-local-source-${index + 1}.jpg`
    writeFixture(path, bytes)
    paths.push(path)
    const seed = new DownloadImageSeed()
    seed.page = index + 1
    seed.imgkey = `local-${index + 1}`
    seed.imagePageUrl = `download://reader-local-source/${index + 1}`
    seed.filePath = path
    seed.bytesWritten = bytes.byteLength
    seed.downloadedAt = Date.now()
    seeds.push(seed)
  }
  const task = new DownloadGalleryTask()
  task.gid = FIXTURE_GID
  task.token = FIXTURE_TOKEN
  task.title = 'Shared Reader local source fixture'
  task.pageCount = seeds.length
  task.queuedAt = Date.now()
  task.imageSeeds = seeds
  task.status = DownloadGalleryTaskStatus.COMPLETE
  task.syncProgressCounts()
  return task
}

async function capture(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  expect(await driver.screenCap(`${cache}/rkit-local-source-${name}.png`)).assertTrue()
}

async function waitLocalReader(driver: Driver): Promise<void> {
  for (let attempt: number = 0; attempt < 60; attempt++) {
    const page = await driver.findComponent(ON.id('rkit-chrome-page'))
    const image = await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport')))
    const loading = await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport')))
    if (page !== null && (await page.getText()).trim() === '1 / 2' && image !== null && loading === null) return
    await driver.delayMs(250)
  }
  throw new Error('shared_local_reader_not_ready')
}

async function waitId(driver: Driver, id: string, attempts: number = 80): Promise<Component> {
  for (let attempt: number = 0; attempt < attempts; attempt++) {
    const component = await driver.findComponent(ON.id(id))
    if (component !== null) return component
    await driver.delayMs(250)
  }
  throw new Error(`reader_backend_rehearsal_component_unavailable:${id}`)
}

async function entryContext(driver: Driver): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  for (let attempt: number = 0; attempt < 80; attempt++) {
    try {
      const ability = await delegator.getCurrentTopAbility()
      if (ability.context.abilityInfo.name === 'EntryAbility') return ability.context
    } catch (_) {}
    await driver.delayMs(100)
  }
  throw new Error('reader_backend_rehearsal_entry_context_unavailable')
}

export async function selectBackend(driver: Driver, backend: NextEReaderBackend): Promise<void> {
  await (await waitId(driver, 'nexte-reader-backend-rehearsal-row')).click()
  const label = AppStrings.get(backend === NextEReaderBackend.SHARED
    ? 'settings_reader_backend_shared'
    : 'settings_reader_backend_legacy')
  const option = await driver.findComponent(ON.text(label))
  if (option === null) throw new Error(`reader_backend_rehearsal_option_unavailable:${backend}`)
  await option.click()
  for (let attempt: number = 0; attempt < 40; attempt++) {
    if (connectNextEReaderBackendSelection().current() === backend) {
      // The menu commits state before its dismiss animation completes. Let the
      // popup leave the tree so the following Back targets ReaderSettings.
      await driver.delayMs(500)
      return
    }
    await driver.delayMs(100)
  }
  throw new Error(`reader_backend_rehearsal_selection_failed:${backend}`)
}

export async function leaveBackendSettings(driver: Driver): Promise<void> {
  for (let attempt: number = 0; attempt < 3; attempt++) {
    if (await driver.findComponent(ON.id('nexte-reader-backend-rehearsal-row')) === null) return
    await driver.pressBack()
    await driver.delayMs(500)
  }
  throw new Error('reader_backend_rehearsal_settings_did_not_close')
}

export async function openBackendSettings(driver: Driver): Promise<void> {
  await (await waitId(driver, 'nexte-root-tab-4')).click()
  await (await waitId(driver, 'nexte-settings-reader-row')).click()
  await waitId(driver, 'nexte-reader-backend-rehearsal-row')
}

async function openFixtureFromDownloads(driver: Driver): Promise<void> {
  await leaveBackendSettings(driver)
  await (await waitId(driver, 'nexte-root-tab-3')).click()
  await (await waitId(driver, `download-task-reader-${FIXTURE_GID}`, 120)).click()
}

async function closeSharedReader(driver: Driver): Promise<void> {
  let closeBtn: Component | null = null
  for (let attempt: number = 0; attempt < 10; attempt++) {
    closeBtn = await driver.findComponent(ON.id('rkit-close'))
    if (closeBtn !== null) break
    const surface = await driver.findComponent(ON.id('rkit-reading-surface'))
    if (surface !== null) {
      const bounds = await surface.getBounds()
      await driver.click(Math.round((bounds.left + bounds.right) / 2),
        Math.round((bounds.top + bounds.bottom) / 2))
    }
    await driver.delayMs(500)
  }
  if (closeBtn === null) {
    throw new Error('rkit_close_button_not_available_on_shared_reader')
  }
  await closeBtn.click()
  console.info('[ReaderProductionInAppBackendRehearsalTrial] rkit-close clicked explicitly')
  for (let attempt: number = 0; attempt < 80; attempt++) {
    if (await driver.findComponent(ON.id('reader-overlay-navigation')) === null) return
    await driver.delayMs(250)
  }
  throw new Error('shared_reader_did_not_return_to_downloads_after_close_click')
}

async function waitLegacyReader(driver: Driver): Promise<Component> {
  for (let attempt: number = 0; attempt < 120; attempt++) {
    const surface = await driver.findComponent(ON.id('reader_key_surface'))
    if (surface !== null && await driver.findComponent(ON.id('rkit-reading-surface')) === null) return surface
    await driver.delayMs(250)
  }
  throw new Error('legacy_reader_did_not_open_from_normal_download_entry')
}

async function progressStore(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
  return relationalStore.getRdbStore(context,
    { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3, autoCleanDirtyData: true })
}

async function restoreFixtureProgress(context: common.UIAbilityContext, original: ReadProgressEntry[]): Promise<void> {
  await GalleryReadProgressSettings.flushForSync(context)
  const database = await progressStore(context)
  await database.executeSql('DELETE FROM gallery_read_progress WHERE scope_key=? AND gid=?', ['global', FIXTURE_GID])
  connectGalleryReadProgress().replaceAll(original)
}

export default function readerLocalSourceTrialTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] === 'ReaderProductionInAppBackendRehearsalTrial') {
    describe('ReaderProductionInAppBackendRehearsalTrial', (): void => {
      it('switchesNormalDownloadEntryAndRestoresLegacy', 0, async (): Promise<void> => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator()
        const driver = Driver.create()
        const queue = connectDownloadQueue()
        const originalTasks = queue.galleryTasks
        const originalProgress = connectGalleryReadProgress().snapshot()
        const paths: string[] = []
        let context: common.UIAbilityContext | null = null
        let queueWithFixture: string = ''
        try {
          await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
          context = await entryContext(driver)
          expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.LEGACY)
          const task = await fixtureTask(paths)

          await openBackendSettings(driver)
          await capture(driver, 'backend-legacy-setting')
          await selectBackend(driver, NextEReaderBackend.SHARED)
          await capture(driver, 'backend-shared-setting')
          // EntryAbility restores the persisted queue asynchronously during cold start.
          // Inject only after that startup work and the settings round-trip have settled,
          // otherwise the production restore can legitimately replace this test fixture.
          queue.replaceGalleryTasks(originalTasks.concat([task]))
          queueWithFixture = JSON.stringify(queue.galleryTasks)
          await openFixtureFromDownloads(driver)
          await waitLocalReader(driver)
          const sharedSurface = await waitId(driver, 'rkit-reading-surface')
          const sharedBounds = await sharedSurface.getBounds()
          await driver.click(Math.round((sharedBounds.left + sharedBounds.right) / 2),
            Math.round((sharedBounds.top + sharedBounds.bottom) / 2))
          expect(await driver.findComponent(ON.id('rkit-reading-surface')) !== null).assertTrue()
          await capture(driver, 'backend-shared-reader')
          await closeSharedReader(driver)
          await waitId(driver, 'nexte-download-queue-root')
          await capture(driver, 'backend-shared-return')

          await openBackendSettings(driver)
          expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.SHARED)
          await selectBackend(driver, NextEReaderBackend.LEGACY)
          await capture(driver, 'backend-legacy-restored-setting')
          await openFixtureFromDownloads(driver)
          const legacySurface = await waitLegacyReader(driver)
          const legacyBounds = await legacySurface.getBounds()
          await driver.click(Math.round((legacyBounds.left + legacyBounds.right) / 2),
            Math.round((legacyBounds.top + legacyBounds.bottom) / 2))
          expect(await driver.findComponent(ON.id('reader_key_surface')) !== null).assertTrue()
          await capture(driver, 'backend-legacy-reader')
          await driver.pressBack()
          for (let attempt: number = 0; attempt < 80; attempt++) {
            if (await driver.findComponent(ON.id('reader-overlay-navigation')) === null) break
            await driver.delayMs(250)
          }
          expect(await driver.findComponent(ON.id('reader-overlay-navigation'))).assertNull()
          await waitId(driver, 'nexte-download-queue-root')
          expect(JSON.stringify(queue.galleryTasks)).assertEqual(queueWithFixture)
          await capture(driver, 'backend-legacy-return')
          console.info('[ReaderProductionInAppBackendRehearsalTrial] initial=legacy sharedSelectedInApp=true ' +
            'sharedTouch=true sharedReturned=true legacySelectedInApp=true legacyTouch=true legacyReturned=true ' +
            'queueUnchanged=true')
        } catch (error) {
          try { await capture(driver, 'backend-exception') } catch (_) {}
          throw error as Error
        } finally {
          connectNextEReaderBackendSelection().selectForRehearsal(NextEReaderBackend.LEGACY, true)
          queue.replaceGalleryTasks(originalTasks)
          if (context !== null) await restoreFixtureProgress(context, originalProgress)
          for (const path of paths) {
            if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
          }
        }
      })
    })
    return
  }
  if (args['-s class'] !== 'ReaderLocalSourceTrial') return
  describe('ReaderLocalSourceTrial', (): void => {
    it('completeDownloadOpensSharedReaderWithoutNetworkAndRestoresQueue', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      const queue = connectDownloadQueue()
      const original = queue.galleryTasks
      const paths: string[] = []
      let accepted: boolean = false
      try {
        const task = await fixtureTask(paths)
        queue.replaceGalleryTasks(original.concat([task]))
        await delegator.startAbility({
          bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility',
          parameters: { readerLabWork: FIXTURE_GID, readerLabUnit: FIXTURE_TOKEN,
            readerLabPage: '0', readerLabChrome: 'true' },
        })
        await waitLocalReader(driver)
        await capture(driver, 'open')
        await (await driver.findComponent(ON.id('rkit-close'))).click()
        for (let attempt: number = 0; attempt < 30; attempt++) {
          if (await driver.findComponent(ON.id('rkit-trial-navigation')) === null) break
          await driver.delayMs(100)
        }
        expect(await driver.findComponent(ON.id('rkit-trial-navigation'))).assertNull()
        await capture(driver, 'closed')
        accepted = true
      } catch (error) {
        await capture(driver, 'exception')
        throw error as Error
      } finally {
        queue.replaceGalleryTasks(original)
        for (let index: number = 0; index < paths.length; index++) {
          if (fileIo.accessSync(paths[index])) fileIo.unlinkSync(paths[index])
        }
      }
      expect(accepted).assertTrue()
      await delegator.print('ReaderLocalSourceTrial source=galleryDownload pages=2 networkFallback=false queueRestored=true')
    })
  })
}
