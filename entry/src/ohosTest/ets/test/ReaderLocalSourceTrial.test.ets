import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  connectDownloadQueue, DownloadGalleryTask, DownloadGalleryTaskStatus, DownloadImageSeed,
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

export default function readerLocalSourceTrialTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
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
