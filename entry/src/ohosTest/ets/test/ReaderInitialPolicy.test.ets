import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit'
import { relationalStore, preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { connectNextEReaderLabContextProbe } from 'reader'
import { ReadModeSettings, GalleryReadProgressSettings, ReadMode, ReadColumnMode, ReadSpreadLayout,
  StorageKeys, connectReadMode, connectGalleryReadProgress, connectSyncSettings } from 'shared'

class InitialContextHolder {
  context: common.UIAbilityContext | null = null
}

class InitialPreference {
  key: string
  present: boolean
  value: preferences.ValueType
  constructor(store: preferences.Preferences, key: string) {
    this.key = key
    this.present = store.hasSync(key)
    this.value = store.getSync(key, '')
  }
}

class InitialProgressRow {
  present: boolean = false
  page: number | null = null
  column: string | null = null
  updated: number | null = null
  deleted: number | null = null
}

async function initialRow(store: relationalStore.RdbStore, work: string): Promise<InitialProgressRow> {
  const row = new InitialProgressRow()
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

async function initialWriteRow(store: relationalStore.RdbStore, work: string,
  row: InitialProgressRow): Promise<void> {
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

function initialSyncGate(store: preferences.Preferences): void {
  // Match canonical default semantics without exposing the URL or restoring sync configuration.
  const url = store.getSync(StorageKeys.SYNC_WEBDAV_URL, '')
  expect(typeof url).assertEqual('string')
  const webdav = store.getSync(StorageKeys.SYNC_WEBDAV_ENABLED, (url as string).trim().length > 0)
  const cloud = store.getSync(StorageKeys.SYNC_HUAWEI_CLOUD_ENABLED, false)
  const live = connectSyncSettings()
  console.info(`[ReaderInitialPolicyTest] sync_gate durableWebdav=${webdav === true} durableCloud=${cloud === true} liveWebdav=${live.webdavEnabled} liveCloud=${live.huaweiCloudEnabled} webdavBusy=${live.webdavSyncing} cloudBusy=${live.huaweiCloudSyncing}`)
  expect(webdav === false && cloud === false && !live.webdavEnabled && !live.huaweiCloudEnabled &&
    !live.webdavSyncing && !live.huaweiCloudSyncing).assertTrue()
}

async function initialCapture(driver: Driver, name: string): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const cache = delegator.getAppContext().cacheDir
  if (typeof driver.dumpLayout === 'function') expect(await driver.dumpLayout(`${cache}/rkit-initial-${name}.json`)).assertTrue()
  else expect((await delegator.executeShellCommand(`uitest dumpLayout -p /data/local/tmp/rkit-initial-${name}.json`, 15)).exitCode).assertEqual(0)
  expect(await driver.screenCap(`${cache}/rkit-initial-${name}.png`)).assertTrue()
}

async function initialRestoreMode(context: common.UIAbilityContext, originalLiveColumn: string): Promise<void> {
  try {
    await ReadModeSettings.restore(context)
  } finally {
    // Production ReaderPage owns this transient global column; the Lab policy uses the gallery owner.
    connectReadMode().columnMode = originalLiveColumn
  }
}

async function initialWait(driver: Driver, id: string): Promise<void> {
  for (let attempt = 0; attempt < 60; attempt++) {
    if (await driver.findComponent(ON.id(id)) !== null) return
    await driver.delayMs(250)
  }
  expect(await driver.findComponent(ON.id(id)) !== null).assertTrue()
}

async function initialClose(driver: Driver): Promise<void> {
  if (await driver.findComponent(ON.id('rkit-vertical-paged')) !== null) {
    await driver.pressBack(); await driver.delayMs(300)
  }
  const close = await driver.findComponent(ON.id('rkit-close'))
  if (close !== null) await close.click()
  await driver.delayMs(600)
  expect(await driver.findComponent(ON.id('rkit-chrome-page'))).assertNull()
}

async function initialPage(driver: Driver): Promise<number> {
  return Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[0].trim())
}

async function initialBody(driver: Driver, container: string): Promise<void> {
  for (let attempt = 0; attempt < 60; attempt++) {
    if (await driver.findComponent(ON.type('Image').within(ON.id(container))) !== null &&
      await driver.findComponent(ON.type('LoadingProgress').within(ON.id(container))) === null) return
    await driver.delayMs(300)
  }
  expect(false).assertTrue()
}

/** Initialized canonical handoff, not a cold-start migration or thumbnail-entry acceptance. */
export default function readerInitialPolicyTest(): void {
  readerInitialPolicyReadOnlyTest()
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  const selectedCase = args['-s readerInitialCase']
  if (args['-s class'] !== 'ReaderInitialPolicyTrial' || typeof work !== 'string' || typeof unit !== 'string') return
  describe('ReaderInitialPolicyTrial', (): void => {
    it('savedPolicyBeforeFirstSurfaceAndExplicitOverride', 0, async (): Promise<void> => {
      expect(work.length > 0 && unit.length > 0).assertTrue()
      expect(selectedCase === undefined || selectedCase === '3').assertTrue()
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const holder = new InitialContextHolder()
      const probe = connectNextEReaderLabContextProbe()
      const epoch = probe.arm(work, (received: common.UIAbilityContext): void => { holder.context = received })
      try {
        // Diagnostic entry does not require initialized reader policy. No fixture has been written.
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabPage: '2', readerLabVolumeKeys: 'false' } })
        for (let attempt = 0; attempt < 60 && holder.context === null; attempt++) await driver.delayMs(250)
        expect(holder.context !== null).assertTrue()
        if (holder.context === null) throw new Error('No actual Lab context received')
        console.info(`[ReaderInitialPolicyTest] actualHostDir=${holder.context.databaseDir}`)
        expect(holder.context.databaseDir.endsWith('/entry')).assertTrue()
        await initialWait(driver, 'rkit-phase')
      } finally {
        probe.cancel(epoch)
        await driver.pressBack()
        await driver.delayMs(600)
        expect(await driver.findComponent(ON.id('rkit-phase'))).assertNull()
      }
      const context = holder.context
      if (context === null) throw new Error('No actual Lab context received')
      const prefs = await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      initialSyncGate(prefs)
      const legacy = prefs.getSync(StorageKeys.READING_PROGRESS, '')
      expect(legacy === '').assertTrue()
      for (let attempt = 0; attempt < 60 &&
        (connectReadMode().restoreResult !== 'applied' || connectGalleryReadProgress().restoreResult !== 'applied'); attempt++) {
        await driver.delayMs(250)
      }
      expect(connectReadMode().restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      // Drain ordinary pending writes before establishing the exact fixture baseline; no sync is enabled.
      await GalleryReadProgressSettings.flushForSync(context)
      initialSyncGate(prefs)
      const saved: InitialPreference[] = []
      for (const key of [StorageKeys.READING_DIRECTION, StorageKeys.READING_DOUBLE_PAGE, StorageKeys.READING_SPREAD_LAYOUT]) {
        const item = new InitialPreference(prefs, key)
        expect(!item.present || typeof item.value === 'string' || typeof item.value === 'number' ||
          typeof item.value === 'boolean').assertTrue()
        saved.push(item)
      }
      const originalMode = connectReadMode().mode
      const originalLiveColumn = connectReadMode().columnMode
      const originalDouble = connectReadMode().doublePageEnabled
      const originalSpread = connectReadMode().spreadLayoutMode
      const originalEntry = JSON.stringify(connectGalleryReadProgress().getEntry(work))
      const originalColumn = connectGalleryReadProgress().getColumnMode(work)
      const store = await relationalStore.getRdbStore(context,
        { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3 })
      const originalRow = await initialRow(store, work)
      // Read actual durable settings through the canonical readers, not hand-written normalization.
      await initialRestoreMode(context, originalLiveColumn)
      await GalleryReadProgressSettings.restore(context)
      expect(connectReadMode().restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      expect(connectReadMode().mode).assertEqual(originalMode)
      expect(connectReadMode().doublePageEnabled).assertEqual(originalDouble)
      expect(connectReadMode().spreadLayoutMode).assertEqual(originalSpread)
      expect(JSON.stringify(connectGalleryReadProgress().getEntry(work))).assertEqual(originalEntry)
      expect(connectGalleryReadProgress().getColumnMode(work)).assertEqual(originalColumn)
      console.info(`[ReaderInitialPolicyTest] baseline mode=${originalMode} double=${originalDouble} spread=${originalSpread} column=${originalColumn} rowPresent=${originalRow.present}`)
      let primaryFailure = false
      try {
        for (let index = selectedCase === '3' ? 3 : 0; index < (selectedCase === '3' ? 4 : 6); index++) {
          initialSyncGate(prefs)
          const mode = index === 1 ? ReadMode.TOP_TO_BOTTOM : index === 2 ? ReadMode.VERTICAL :
            index === 3 || index === 5 ? ReadMode.RTL : ReadMode.LTR
          const doublePage = index !== 0
          const spread = index === 3 || index === 5 ? ReadSpreadLayout.SPLIT : ReadSpreadLayout.JOINED
          const column = index === 3 ? ReadColumnMode.EVEN_LEFT : ReadColumnMode.ODD_LEFT
          await ReadModeSettings.setMode(context, mode)
          await ReadModeSettings.setDoublePageEnabled(context, doublePage)
          await ReadModeSettings.setSpreadLayoutMode(context, spread)
          const fixture = new InitialProgressRow()
          fixture.present = true
          fixture.page = originalRow.present ? originalRow.page : 0
          fixture.updated = originalRow.present ? originalRow.updated : 0
          fixture.deleted = 0
          fixture.column = column
          await initialWriteRow(store, work, fixture)
          await initialRestoreMode(context, originalLiveColumn)
          await GalleryReadProgressSettings.restore(context)
          expect(connectReadMode().restoreResult).assertEqual('applied')
          expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
          expect(connectReadMode().mode).assertEqual(mode)
          expect(connectReadMode().doublePageEnabled).assertEqual(doublePage)
          expect(connectReadMode().spreadLayoutMode).assertEqual(spread)
          expect(connectGalleryReadProgress().getColumnMode(work)).assertEqual(column)
          expect(prefs.getSync(StorageKeys.READING_DIRECTION, '')).assertEqual(mode)
          expect(prefs.getSync(StorageKeys.READING_DOUBLE_PAGE, '')).assertEqual(doublePage)
          expect(prefs.getSync(StorageKeys.READING_SPREAD_LAYOUT, '')).assertEqual(spread)
          expect(JSON.stringify(await initialRow(store, work))).assertEqual(JSON.stringify(fixture))
          console.info(`[ReaderInitialPolicyTest] saved_column gallery=${work} databaseDir=${context.databaseDir} column=${column}`)
          if (index === 5) {
            await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
              readerLabWork: work, readerLabUnit: unit, readerLabPage: '2', readerLabChrome: 'true', readerLabVolumeKeys: 'false',
              readerLabEntryLayout: 'single', readerLabEntryDirection: 'ltr' } })
          } else {
            await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
              readerLabWork: work, readerLabUnit: unit, readerLabPage: '2', readerLabChrome: 'true', readerLabVolumeKeys: 'false' } })
          }
          await initialWait(driver, 'rkit-chrome-page')
          const initial = await initialPage(driver)
          console.info(`[ReaderInitialPolicyTest] case=${index} initialPage=${initial} sourceIndex=2`)
          expect(initial).assertEqual(3)
          const total = Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[1].trim())
          expect(total >= 6).assertTrue()
          if (index === 2) {
            await initialWait(driver, 'rkit-continuous-list')
            await initialWait(driver, 'rkit-continuous-page-2')
            expect(await driver.findComponent(ON.id('rkit-native-pager'))).assertNull()
          } else {
            await initialWait(driver, 'rkit-native-pager')
            await initialWait(driver, 'rkit-part-2-whole')
            if (index === 3 || index === 4) {
              const other = index === 3 ? 1 : 3
              await initialWait(driver, `rkit-part-${other}-whole`)
              const a = await (await driver.findComponent(ON.id('rkit-part-2-whole').within(ON.id('rkit-image-viewport')))).getBounds()
              const b = await (await driver.findComponent(ON.id(`rkit-part-${other}-whole`).within(ON.id('rkit-image-viewport')))).getBounds()
              expect(a.left < b.left).assertTrue()
              const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
              if (index === 3) expect(Math.abs((a.right - a.left) * 2 - (viewport.right - viewport.left)) < 3).assertTrue()
              console.info(`[ReaderInitialPolicyTest] case=${index} part2=${a.left},${a.top},${a.right},${a.bottom} other=${other}:${b.left},${b.top},${b.right},${b.bottom}`)
            } else {
              expect(await driver.findComponent(ON.id('rkit-part-1-whole').within(ON.id('rkit-image-viewport')))).assertNull()
              expect(await driver.findComponent(ON.id('rkit-part-3-whole').within(ON.id('rkit-image-viewport')))).assertNull()
            }
          }
          await initialBody(driver, index === 2 ? 'rkit-continuous-page-2' : 'rkit-image-viewport')
          await initialCapture(driver, `case-${index}-initial`)
          if (index !== 2) {
            const b = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
            const x = Math.round((b.left + b.right) / 2), y = Math.round((b.top + b.bottom) / 2)
            const vertical = index === 1, rtl = index === 3
            const offset = Math.round((vertical ? b.bottom - b.top : b.right - b.left) * 0.31) * (rtl ? -1 : 1)
            await driver.swipe(vertical ? x : x + offset, vertical ? y + offset : y,
              vertical ? x : x - offset, vertical ? y - offset : y, 700)
            await driver.delayMs(700)
            const after = await initialPage(driver)
            console.info(`[ReaderInitialPolicyTest] case=${index} afterSwipePage=${after}`)
            expect(after).assertEqual(index === 3 ? 4 : index === 4 ? 5 : 4)
            await initialCapture(driver, `case-${index}-after`)
          }
          await initialClose(driver)
        }
      } catch (error) {
        primaryFailure = true
        console.error(`[ReaderInitialPolicyTest] failure=${(error as Error).message}`)
        try { await initialCapture(driver, 'exception') } catch (_) {}
        throw error as Error
      } finally {
        let restored = true
        let restoredPreferences = 0
        let restoredRow = false
        try { await initialClose(driver) } catch (error) {
          restored = false
          console.error(`[ReaderInitialPolicyTest] close_failure=${(error as Error).message}`)
        }
        // All declared durable fields are restored even if closing or another restoration fails.
        for (const item of saved) {
          try {
            if (item.present) prefs.putSync(item.key, item.value)
            else prefs.deleteSync(item.key)
            prefs.flushSync()
            expect(prefs.hasSync(item.key)).assertEqual(item.present)
            if (item.present) {
              const value = prefs.getSync(item.key, '')
              expect(typeof value).assertEqual(typeof item.value)
              expect(JSON.stringify(value)).assertEqual(JSON.stringify(item.value))
            }
            restoredPreferences++
          } catch (error) {
            restored = false
            console.error(`[ReaderInitialPolicyTest] preference_restore_failed key=${item.key}`)
          }
        }
        try {
          await initialWriteRow(store, work, originalRow)
          expect(JSON.stringify(await initialRow(store, work))).assertEqual(JSON.stringify(originalRow))
          restoredRow = true
        } catch (error) {
          restored = false
          console.error('[ReaderInitialPolicyTest] target_row_restore_failed')
        }
        try {
          await initialRestoreMode(context, originalLiveColumn)
          await GalleryReadProgressSettings.restore(context)
          expect(connectReadMode().restoreResult).assertEqual('applied')
          expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
          expect(connectReadMode().mode).assertEqual(originalMode)
          expect(connectReadMode().doublePageEnabled).assertEqual(originalDouble)
          expect(connectReadMode().spreadLayoutMode).assertEqual(originalSpread)
          expect(connectReadMode().columnMode).assertEqual(originalLiveColumn)
          expect(JSON.stringify(connectGalleryReadProgress().getEntry(work))).assertEqual(originalEntry)
          expect(connectGalleryReadProgress().getColumnMode(work)).assertEqual(originalColumn)
          expect(prefs.getSync(StorageKeys.READING_PROGRESS, '') === legacy).assertTrue()
        } catch (error) {
          restored = false
          console.error('[ReaderInitialPolicyTest] canonical_restore_failed')
        }
        console.info(`[ReaderInitialPolicyTest] restored=${restored} exactPreferences=${restoredPreferences} exactTargetRow=${restoredRow} mode=${connectReadMode().mode} double=${connectReadMode().doublePageEnabled} spread=${connectReadMode().spreadLayoutMode}`)
        if (!primaryFailure) expect(restored).assertTrue()
      }
    })
  })
}

function initialReadOnlySignature(work: string): string {
  const state = connectReadMode()
  return JSON.stringify([state.mode, state.doublePageEnabled, state.spreadLayoutMode,
    connectGalleryReadProgress().getColumnMode(work), JSON.stringify(connectGalleryReadProgress().getEntry(work))])
}

function initialReadOnlyStable(work: string, baseline: string): void {
  if (initialReadOnlySignature(work) !== baseline) {
    throw new Error('non_comparable: canonical policy or target gallery changed during observation; no values restored')
  }
}

/** Observe the current configuration without fixture writes, flushing, hydration calls, or sync changes. */
function readerInitialPolicyReadOnlyTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  const work = args['-s readerLabWork']
  const unit = args['-s readerLabUnit']
  if (args['-s class'] !== 'ReaderInitialPolicyReadOnlyTrial' || typeof work !== 'string' || typeof unit !== 'string') return
  describe('ReaderInitialPolicyReadOnlyTrial', (): void => {
    it('currentCanonicalPolicyReadOnly', 0, async (): Promise<void> => {
      const driver = Driver.create(), delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const holder = new InitialContextHolder()
      const probe = connectNextEReaderLabContextProbe()
      const epoch = probe.arm(work, (received: common.UIAbilityContext): void => { holder.context = received })
      try {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabPage: '2', readerLabVolumeKeys: 'false' } })
        for (let attempt = 0; attempt < 60 && holder.context === null; attempt++) await driver.delayMs(250)
        if (holder.context === null) throw new Error('No actual Lab context received')
        expect(holder.context.databaseDir.endsWith('/entry')).assertTrue()
        console.info(`[ReaderInitialPolicyReadOnlyTest] actualHostDir=${holder.context.databaseDir}`)
        await initialWait(driver, 'rkit-phase')
      } finally {
        probe.cancel(epoch)
        await driver.pressBack()
        await driver.delayMs(600)
        expect(await driver.findComponent(ON.id('rkit-phase'))).assertNull()
      }
      for (let attempt = 0; attempt < 60 &&
        (connectReadMode().restoreResult !== 'applied' || connectGalleryReadProgress().restoreResult !== 'applied' ||
        connectSyncSettings().webdavSyncing || connectSyncSettings().huaweiCloudSyncing); attempt++) {
        await driver.delayMs(250)
      }
      expect(connectReadMode().restoreResult).assertEqual('applied')
      expect(connectGalleryReadProgress().restoreResult).assertEqual('applied')
      console.info(`[ReaderInitialPolicyReadOnlyTest] webdavBusy=${connectSyncSettings().webdavSyncing} cloudBusy=${connectSyncSettings().huaweiCloudSyncing}`)
      const mode = connectReadMode().mode
      const doublePage = connectReadMode().doublePageEnabled
      const split = connectReadMode().spreadLayoutMode === ReadSpreadLayout.SPLIT
      const even = connectGalleryReadProgress().getColumnMode(work) === ReadColumnMode.EVEN_LEFT
      const continuous = mode === ReadMode.VERTICAL
      const vertical = mode === ReadMode.TOP_TO_BOTTOM
      const rtl = mode === ReadMode.RTL
      expect(mode === ReadMode.LTR || rtl || vertical || continuous).assertTrue()
      const spread = !continuous && !vertical && doublePage
      const baseline = initialReadOnlySignature(work)
      console.info(`[ReaderInitialPolicyReadOnlyTest] mode=${mode} double=${doublePage} split=${split} even=${even} sourceIndex=2`)
      let primaryFailure = false
      try {
        await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility', parameters: {
          readerLabWork: work, readerLabUnit: unit, readerLabPage: '2', readerLabChrome: 'true', readerLabVolumeKeys: 'false' } })
        await initialWait(driver, 'rkit-chrome-page')
        const container = continuous ? 'rkit-continuous-page-2' : 'rkit-image-viewport'
        await initialWait(driver, continuous ? 'rkit-continuous-list' : 'rkit-native-pager')
        await initialBody(driver, container)
        initialReadOnlyStable(work, baseline)
        expect(await initialPage(driver)).assertEqual(3)
        const total = Number((await (await driver.findComponent(ON.id('rkit-chrome-page'))).getText()).split('/')[1].trim())
        expect(total >= 6).assertTrue()
        if (!continuous) {
          const part2 = await driver.findComponent(ON.id('rkit-part-2-whole').within(ON.id('rkit-image-viewport')))
          expect(part2 !== null).assertTrue()
          if (spread) {
            const other = even ? 1 : 3
            const partOther = await driver.findComponent(ON.id(`rkit-part-${other}-whole`).within(ON.id('rkit-image-viewport')))
            expect(partOther !== null).assertTrue()
            const a = await part2.getBounds(), b = await partOther.getBounds()
            expect(a.left < b.left).assertEqual(even ? rtl : !rtl)
            const viewport = await (await driver.findComponent(ON.id('rkit-image-viewport'))).getBounds()
            if (split) expect(Math.abs((a.right - a.left) * 2 - (viewport.right - viewport.left)) < 3).assertTrue()
          } else {
            expect(await driver.findComponent(ON.id('rkit-part-1-whole').within(ON.id('rkit-image-viewport')))).assertNull()
            expect(await driver.findComponent(ON.id('rkit-part-3-whole').within(ON.id('rkit-image-viewport')))).assertNull()
          }
        }
        await initialCapture(driver, 'readonly-initial')
        const initialRowTop = continuous ?
          (await (await driver.findComponent(ON.id('rkit-continuous-page-2'))).getBounds()).top : 0
        const bounds = await (await driver.findComponent(ON.id(continuous ? 'rkit-continuous-list' : 'rkit-image-viewport'))).getBounds()
        const x = Math.round((bounds.left + bounds.right) / 2), y = Math.round((bounds.top + bounds.bottom) / 2)
        const yAxis = continuous || vertical
        const offset = Math.round((yAxis ? bounds.bottom - bounds.top : bounds.right - bounds.left) * 0.31) * (rtl ? -1 : 1)
        await driver.swipe(yAxis ? x : x + offset, yAxis ? y + offset : y,
          yAxis ? x : x - offset, yAxis ? y - offset : y, 700)
        await driver.delayMs(700)
        initialReadOnlyStable(work, baseline)
        const after = await initialPage(driver)
        console.info(`[ReaderInitialPolicyReadOnlyTest] afterSwipePage=${after} currentCanonicalUnchanged=true`)
        if (continuous) {
          const sourceRow = await driver.findComponent(ON.id('rkit-continuous-page-2'))
          const rowMoved = sourceRow !== null && Math.abs((await sourceRow.getBounds()).top - initialRowTop) > 2
          // A long page may remain selected: actual row displacement or a later visible anchor proves scrolling.
          expect(rowMoved || after > 3).assertTrue()
          console.info(`[ReaderInitialPolicyReadOnlyTest] continuousRowMoved=${rowMoved} afterPage=${after}`)
        } else expect(after).assertEqual(spread ? (even ? 4 : 5) : 4)
        await initialCapture(driver, 'readonly-after')
      } catch (error) {
        primaryFailure = true
        console.error(`[ReaderInitialPolicyReadOnlyTest] failure=${(error as Error).message}`)
        try { await initialCapture(driver, 'readonly-exception') } catch (_) {}
        throw error as Error
      } finally {
        try {
          await initialClose(driver)
          initialReadOnlyStable(work, baseline)
          await initialCapture(driver, 'readonly-exit')
          console.info('[ReaderInitialPolicyReadOnlyTest] exited=true fixtureWrites=0 canonicalUnchanged=true')
        } catch (error) {
          console.error(`[ReaderInitialPolicyReadOnlyTest] cleanup_failure=${(error as Error).message}`)
          if (!primaryFailure) throw error as Error
        }
      }
    })
  })
}
