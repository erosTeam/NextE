import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { relationalStore } from '@kit.ArkData'
import { connectNextEReaderLabContextProbe } from 'reader'
import { connectGalleryReadProgress, connectSyncSettings, GalleryReadProgressSettings } from 'shared'

const RECOVERY_FILE: string = 'rkit-progress-recovery.json'

class ProgressContextHolder {
  context: common.UIAbilityContext | null = null
}

class ProgressRow {
  present: boolean = false
  page: number | null = null
  column: string | null = null
  updated: number | null = null
  deleted: number | null = null
}

class ProgressRecovery {
  work: string = ''
  row: ProgressRow = new ProgressRow()
}

function recoveryPath(context: common.UIAbilityContext): string {
  return `${context.cacheDir}/${RECOVERY_FILE}`
}

function writeRecovery(context: common.UIAbilityContext, recovery: ProgressRecovery): void {
  const file = fileIo.openSync(recoveryPath(context),
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
  try { fileIo.writeSync(file.fd, JSON.stringify(recovery)) } finally { fileIo.closeSync(file) }
}

function readRecovery(context: common.UIAbilityContext): ProgressRecovery {
  return JSON.parse(fileIo.readTextSync(recoveryPath(context))) as ProgressRecovery
}

function removeRecovery(context: common.UIAbilityContext): void {
  const path = recoveryPath(context)
  if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
}

async function readProgressRow(store: relationalStore.RdbStore, work: string): Promise<ProgressRow> {
  const row = new ProgressRow()
  const rows = await store.querySql(
    'SELECT page_index,column_mode,updated_at,deleted_at FROM gallery_read_progress WHERE scope_key=? AND gid=?',
    ['global', work])
  try {
    if (rows.goToFirstRow()) {
      row.present = true
      row.page = rows.isColumnNull(0) ? null : rows.getLong(0)
      row.column = rows.isColumnNull(1) ? null : rows.getString(1)
      row.updated = rows.isColumnNull(2) ? null : rows.getLong(2)
      row.deleted = rows.isColumnNull(3) ? null : rows.getLong(3)
      expect(rows.goToNextRow()).assertFalse()
    }
    return row
  } finally { rows.close() }
}

async function writeProgressRow(store: relationalStore.RdbStore, work: string, row: ProgressRow): Promise<void> {
  if (!row.present) {
    await store.executeSql('DELETE FROM gallery_read_progress WHERE scope_key=? AND gid=?', ['global', work])
    return
  }
  await store.executeSql(
    'INSERT INTO gallery_read_progress (scope_key,gid,page_index,column_mode,updated_at,deleted_at) VALUES (?,?,?,?,?,?) ' +
    'ON CONFLICT(scope_key,gid) DO UPDATE SET page_index=excluded.page_index,column_mode=excluded.column_mode,' +
    'updated_at=excluded.updated_at,deleted_at=excluded.deleted_at',
    ['global', work, row.page, row.column, row.updated, row.deleted])
}

async function waitCanonicalRestore(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 60 && connectGalleryReadProgress().restoreResult !== 'applied'; attempt++) {
    await driver.delayMs(250)
  }
  expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
}

async function obtainHostContext(driver: Driver, work: string, unit: string): Promise<common.UIAbilityContext> {
  const holder = new ProgressContextHolder()
  const probe = connectNextEReaderLabContextProbe()
  const epoch = probe.arm(work, (context: common.UIAbilityContext): void => { holder.context = context })
  try {
    await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
      bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
        readerLabWork: work, readerLabUnit: unit, readerLabPage: '0', readerLabVolumeKeys: 'false',
      },
    })
    for (let attempt = 0; attempt < 60 && holder.context === null; attempt++) await driver.delayMs(250)
    expect(holder.context !== null).assertTrue()
    for (let attempt = 0; attempt < 60; attempt++) {
      if (await driver.findComponent(ON.id('rkit-phase')) !== null) break
      await driver.delayMs(250)
    }
    expect(await driver.findComponent(ON.id('rkit-phase')) !== null).assertTrue()
  } finally {
    probe.cancel(epoch)
    await driver.pressBack()
    for (let attempt = 0; attempt < 40; attempt++) {
      if (await driver.findComponent(ON.id('rkit-phase')) === null) break
      await driver.delayMs(250)
    }
    expect(await driver.findComponent(ON.id('rkit-phase'))).assertNull()
  }
  if (holder.context === null) throw new Error('No actual Reader host context received')
  expect(holder.context.databaseDir.endsWith('/entry')).assertTrue()
  await waitCanonicalRestore(driver)
  return holder.context
}

async function waitSyncIdle(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 80; attempt++) {
    const live = connectSyncSettings()
    if (!live.webdavSyncing && !live.huaweiCloudSyncing) return
    await driver.delayMs(250)
  }
  const live = connectSyncSettings()
  // Enabled providers are user state, not a reason to mutate or reject the reader test. Only an
  // in-flight merge would make this short exact-row snapshot non-comparable.
  expect(!live.webdavSyncing && !live.huaweiCloudSyncing).assertTrue()
}

async function openProgressReader(driver: Driver, work: string, unit: string): Promise<void> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
    bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
      readerLabWork: work, readerLabUnit: unit, readerLabChrome: 'true', readerLabProgressReadWrite: 'true',
      readerLabVolumeKeys: 'false', readerLabEntryLayout: 'single', readerLabEntryDirection: 'ltr',
    },
  })
  for (let attempt = 0; attempt < 80; attempt++) {
    if (await driver.findComponent(ON.id('rkit-chrome-page')) !== null &&
      await driver.findComponent(ON.type('Image').within(ON.id('rkit-image-viewport'))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id('rkit-image-viewport'))) === null) {
      await driver.delayMs(1000)
      return
    }
    await driver.delayMs(300)
  }
  expect(false).assertTrue()
}

async function currentPage(driver: Driver): Promise<number> {
  const text = await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()
  return Number(text.split('/')[0].trim())
}

async function closeProgressReader(driver: Driver): Promise<void> {
  const close = await driver.findComponent(ON.id('rkit-close'))
  if (close !== null) await close.click()
  await driver.delayMs(600)
  expect(await driver.findComponent(ON.id('rkit-chrome-page'))).assertNull()
}

async function captureProgress(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  if (typeof driver.dumpLayout === 'function') {
    expect(await driver.dumpLayout(`${cache}/rkit-progress-${name}.json`)).assertTrue()
  } else {
    expect((await delegator.executeShellCommand(
      `uitest dumpLayout -p /data/local/tmp/rkit-progress-${name}.json`, 15)).exitCode).assertEqual(0)
  }
  expect(await driver.screenCap(`${cache}/rkit-progress-${name}.png`)).assertTrue()
}

/** First independent process: navigate a presented shared page and leave only the target row for cold restore. */
function progressWriteTrial(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderSharedProgressWriteTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderSharedProgressWriteTrial', (): void => {
    it('presentedPageFlushesToNextEOwnedProgressStore', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const context = await obtainHostContext(driver, work, unit)
      await waitSyncIdle(driver)
      await GalleryReadProgressSettings.flushForSync(context)
      const store = await relationalStore.getRdbStore(context,
        { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3 })
      const recovery = new ProgressRecovery()
      recovery.work = work
      recovery.row = await readProgressRow(store, work)
      writeRecovery(context, recovery)
      let completed = false
      try {
        GalleryReadProgressSettings.setIndex(context, work, 0)
        await GalleryReadProgressSettings.flushForSync(context)
        await GalleryReadProgressSettings.restore(context)
        expect(connectGalleryReadProgress().getIndex(work)).assertEqual(0)
        await openProgressReader(driver, work, unit)
        expect(await currentPage(driver)).assertEqual(1)
        const bounds = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
        const x = Math.round((bounds.left + bounds.right) / 2)
        const y = Math.round((bounds.top + bounds.bottom) / 2)
        const offset = Math.round((bounds.right - bounds.left) * 0.31)
        await driver.swipe(x + offset, y, x - offset, y, 700)
        for (let attempt = 0; attempt < 40 && await currentPage(driver) !== 2; attempt++) await driver.delayMs(250)
        expect(await currentPage(driver)).assertEqual(2)
        await captureProgress(driver, 'write-page-2')
        await closeProgressReader(driver)
        await GalleryReadProgressSettings.flushForSync(context)
        const written = await readProgressRow(store, work)
        expect(written.present && written.page === 1 && written.deleted === 0).assertTrue()
        completed = true
        console.info(`[ReaderSharedProgressWriteTrial] durablePage=${written.page} recoveryRetained=true`)
      } finally {
        if (!completed) {
          try { await closeProgressReader(driver) } catch (_) {}
          await writeProgressRow(store, work, recovery.row)
          await GalleryReadProgressSettings.restore(context)
          removeRecovery(context)
        }
      }
    })
  })
}

/** Second independent process: consume the cold-restored row, then put the exact original row back. */
function progressRestoreTrial(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderSharedProgressRestoreTrial' || typeof work !== 'string' ||
    typeof unit !== 'string') return
  describe('ReaderSharedProgressRestoreTrial', (): void => {
    it('freshProcessRestoresDurablePageAndRestoresOriginalRow', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const context = await obtainHostContext(driver, work, unit)
      const recovery = readRecovery(context)
      expect(recovery.work).assertEqual(work)
      const store = await relationalStore.getRdbStore(context,
        { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3 })
      let primaryFailure = false
      try {
        await waitSyncIdle(driver)
        expect(connectGalleryReadProgress().getIndex(work)).assertEqual(1)
        await openProgressReader(driver, work, unit)
        expect(await currentPage(driver)).assertEqual(2)
        await captureProgress(driver, 'cold-restored-page-2')
        await closeProgressReader(driver)
      } catch (error) {
        primaryFailure = true
        throw error as Error
      } finally {
        try { await closeProgressReader(driver) } catch (_) {}
        await writeProgressRow(store, work, recovery.row)
        await GalleryReadProgressSettings.restore(context)
        expect(JSON.stringify(await readProgressRow(store, work))).assertEqual(JSON.stringify(recovery.row))
        removeRecovery(context)
        console.info('[ReaderSharedProgressRestoreTrial] originalRowRestored=true recoveryRemoved=true')
        if (!primaryFailure) expect(fileIo.accessSync(recoveryPath(context))).assertFalse()
      }
    })
  })
}

export default function readerProgressDurabilityTest(): void {
  progressWriteTrial()
  progressRestoreTrial()
}
