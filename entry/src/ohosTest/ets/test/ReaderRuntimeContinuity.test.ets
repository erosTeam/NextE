/**
 * NextE runtime continuity across an install -r upgrade/rollback cycle.
 *
 * The existing upgrade/rollback evidence for NextE is three file-hash
 * checkpoints around `install -r`, which prove only that the checked durable
 * files were byte-identical between builds. They do not prove that re-reading
 * after an upgrade or a rollback lands on the same content identity, page,
 * settings and progress.
 *
 * Two orchestrated phases, one device-protocol manifest each:
 *   `NextERuntimeContinuityWriteTrial`   — read a real gallery to a page.
 *   `NextERuntimeContinuityVerifyTrial`  — read back after install -r.
 *
 * The expectation is re-derived from a cache record written by the first phase
 * instead of being hardcoded, and the durable facts are read from NextE's own
 * `gallery_read_progress` rows. Cold start deliberately stays Legacy, so each
 * phase selects Shared in-process through the real Reader settings row and
 * never rewrites the persisted default.
 */
import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Component, Driver, MatchPattern, ON } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { fileIo } from '@kit.CoreFileKit'
import {
  AppStrings,
  connectNextEReaderBackendSelection,
  NextEReaderBackend,
} from 'shared'
import { leaveBackendSettings, openBackendSettings, selectBackend } from './ReaderLocalSourceTrial.test'

const RECORD_FILE: string = 'nexte-reader-runtime-continuity.json'
const CAPTURE_PREFIX: string = 'nexte-runtime-continuity'

/** Durable facts a user would notice surviving an upgrade or a rollback. */
class ContinuityRecord {
  gid: string = ''
  pageIndex: number = -1
  pageCount: number = 0
  /** The `gallery_read_progress.page_index` read back after leaving the reader. */
  durablePageIndex: number = -1
  columnMode: string = ''
  writtenAt: number = 0
}

function recordPath(): string {
  return `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/${RECORD_FILE}`
}

function writeRecord(value: ContinuityRecord): void {
  const file = fileIo.openSync(recordPath(),
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
  try { fileIo.writeSync(file.fd, JSON.stringify(value)) } finally { fileIo.closeSync(file) }
}

function readRecord(): ContinuityRecord {
  if (!fileIo.accessSync(recordPath())) {
    throw new Error('NextE continuity record missing; the write phase did not complete')
  }
  return JSON.parse(fileIo.readTextSync(recordPath())) as ContinuityRecord
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
  throw new Error('EntryAbility context unavailable')
}

async function progressStore(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
  return relationalStore.getRdbStore(context,
    { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3, autoCleanDirtyData: true })
}

class ProgressFacts {
  present: boolean = false
  pageIndex: number = -1
  columnMode: string = ''
}

async function progressFacts(database: relationalStore.RdbStore, gid: string): Promise<ProgressFacts> {
  const facts = new ProgressFacts()
  const rows = await database.querySql(
    'SELECT page_index,column_mode FROM gallery_read_progress WHERE scope_key=? AND gid=? ' +
      'AND COALESCE(deleted_at,0)=0 LIMIT 1', ['global', gid])
  try {
    if (!rows.goToFirstRow()) return facts
    facts.present = true
    facts.pageIndex = rows.getLong(0)
    facts.columnMode = rows.isColumnNull(1) ? '' : rows.getString(1)
    return facts
  } finally { rows.close() }
}

async function waitId(driver: Driver, id: string, attempts: number = 120): Promise<Component> {
  for (let attempt: number = 0; attempt < attempts; attempt++) {
    const component = await driver.findComponent(ON.id(id))
    if (component !== null) return component
    await driver.delayMs(250)
  }
  throw new Error(`NextE continuity component unavailable: ${id}`)
}

async function capture(driver: Driver, name: string): Promise<void> {
  const cache = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir
  expect(await driver.screenCap(`${cache}/${CAPTURE_PREFIX}-${name}.png`)).assertTrue()
}

/** Shared page counter text is "N / M". */
function pageLabelIndex(text: string): number {
  const match = /^\s*([1-9][0-9]*)\s*\/\s*([1-9][0-9]*)\s*$/.exec(text)
  if (match === null) throw new Error(`Unexpected Shared page label: ${text}`)
  return Number(match[1]) - 1
}

async function sharedPageLabel(driver: Driver): Promise<string> {
  const passive = await driver.findComponent(ON.id('rkit-persistent-page'))
  if (passive !== null) {
    try {
      const value: string = (await passive.getText()).trim()
      if (/^[0-9]+\s*\/\s*[0-9]+$/.test(value)) return value
    } catch (_) {}
  }
  const page = await driver.findComponent(ON.id('rkit-chrome-page'))
  if (page !== null) {
    try {
      const value: string = (await page.getText()).trim()
      if (/^[0-9]+\s*\/\s*[0-9]+$/.test(value)) return value
    } catch (_) {}
  }
  throw new Error('Shared Reader exposed no readable page label')
}

async function sharedVisiblePage(driver: Driver): Promise<number> {
  for (let attempt: number = 0; attempt < 60; attempt++) {
    try { return pageLabelIndex(await sharedPageLabel(driver)) } catch (_) {}
    await driver.delayMs(400)
  }
  throw new Error('NextE Shared Reader page label unavailable')
}

async function showSharedChrome(driver: Driver): Promise<void> {
  if (await driver.findComponent(ON.id('rkit-chrome-page')) !== null) return
  const surface = await waitId(driver, 'rkit-reading-surface')
  const bounds = await surface.getBounds()
  await driver.click(Math.round((bounds.left + bounds.right) / 2), Math.round((bounds.top + bounds.bottom) / 2))
  await waitId(driver, 'rkit-chrome-page')
}

async function closeAnyReader(driver: Driver): Promise<void> {
  const close = await driver.findComponent(ON.id('rkit-close'))
  if (close !== null) await close.click()
  else if (await driver.findComponent(ON.id('reader-overlay-navigation')) !== null) await driver.pressBack()
  for (let attempt: number = 0; attempt < 80; attempt++) {
    if (await driver.findComponent(ON.id('reader-overlay-navigation')) === null) return
    await driver.delayMs(250)
  }
  throw new Error('NextE Reader did not close')
}

/**
 * Reach the History list. NextE keeps History as a Settings root row rather
 * than a tab, so the settings tab plus the localized History title is the real
 * user route; the row ids themselves carry a runtime-allocated scope prefix.
 */
async function openHistoryList(driver: Driver): Promise<void> {
  await (await waitId(driver, 'nexte-root-tab-4')).click()
  const row = await driver.findComponent(ON.text(AppStrings.get('tab_history')))
  if (row === null) throw new Error('NextE History settings row unavailable')
  await row.click()
}

/**
 * Enter the Reader from the Detail page's own Read action. The label is the
 * real visible affordance (button text plus its resume variant), so this stays
 * a user path rather than a debug overlay call.
 */
async function tapDetailReadAction(driver: Driver): Promise<void> {
  // The Read affordance renders as "阅读" or "继续 P3" from the app's own
  // strings. It only mounts once the Detail page has settled, so wait for the
  // Detail pane itself before looking for the label, and keep the failure
  // diagnosable instead of clicking an unrelated match.
  await waitId(driver, 'gallery-detail-pane', 160)
  for (let attempt: number = 0; attempt < 120; attempt++) {
    for (const pattern of ['^阅读$', '^继续 P[0-9]+$', '^Read$', '^Resume P[0-9]+$']) {
      const candidates = await driver.findComponents(ON.text(pattern, MatchPattern.REG_EXP)) ?? []
      if (candidates.length > 0) {
        const bounds = await candidates[0].getBounds()
        if (bounds.right > bounds.left && bounds.bottom > bounds.top) {
          await candidates[0].click()
          return
        }
      }
    }
    await driver.delayMs(250)
  }
  await capture(driver, 'exception-detail-read-action')
  throw new Error('NextE Detail Read action unavailable')
}

/** Open the newest History row and return its gallery id. */
async function openNewestHistoryDetail(driver: Driver): Promise<string> {
  await openHistoryList(driver)
  const pattern = '^gallery-list-history-[0-9]+-history-[0-9]+$'
  const selector = ON.id(pattern, MatchPattern.REG_EXP)
  for (let attempt: number = 0; attempt < 120; attempt++) {
    const rows = await driver.findComponents(selector) ?? []
    if (rows.length > 0) {
      const row = rows[0]
      const id: string = await row.getId()
      const gid: string = id.substring(id.lastIndexOf('-') + 1)
      await row.click()
      return gid
    }
    const owners = await driver.findComponents(ON.type('List')) ?? []
    for (const list of owners) {
      const found = await list.scrollSearch(selector, true)
      if (found !== null) {
        const id: string = await found.getId()
        const gid: string = id.substring(id.lastIndexOf('-') + 1)
        await found.click()
        return gid
      }
    }
    await driver.delayMs(250)
  }
  throw new Error('NextE History row unavailable')
}

export default function nextERuntimeContinuityTest(): void {
  const selectedClass = abilityDelegatorRegistry.getArguments().parameters['-s class']
  if (selectedClass !== 'NextERuntimeContinuityWriteTrial' &&
    selectedClass !== 'NextERuntimeContinuityVerifyTrial') return

  describe(selectedClass, (): void => {
    it('keepsDurableReadingStateAcrossInstallReplacement', 0, async (): Promise<void> => {
      const driver = Driver.create()
      const delegator = abilityDelegatorRegistry.getAbilityDelegator()
      const writing: boolean = selectedClass === 'NextERuntimeContinuityWriteTrial'
      const expected: ContinuityRecord = writing ? new ContinuityRecord() : readRecord()
      await delegator.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
      const context = await entryContext(driver)
      const database = await progressStore(context)

      // A cold start must still be Legacy: continuity may not be bought by
      // silently making Shared the persisted default.
      expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.LEGACY)

      await openBackendSettings(driver)
      await selectBackend(driver, NextEReaderBackend.SHARED)
      await leaveBackendSettings(driver)

      let gid: string = ''
      if (writing) {
        const target: number = 3
        gid = await openNewestHistoryDetail(driver)
        await tapDetailReadAction(driver)
        await waitId(driver, 'rkit-reading-surface', 240)
        const start: number = await sharedVisiblePage(driver)
        // The persisted mode decides paged vs continuous and LTR vs RTL. The
        // reader turns pages from its tap zones rather than swipe distances, so
        // tap a point outside the centered body and confirm the label moved.
        let current: number = start
        for (let turn: number = 0; turn < 48 && current !== target; turn++) {
          const viewport = await waitId(driver, 'rkit-image-viewport')
          const bounds = await viewport.getBounds()
          const midY = Math.round((bounds.top + bounds.bottom) / 2)
          const nearLeft = Math.round(bounds.left + (bounds.right - bounds.left) * 0.06)
          const nearRight = Math.round(bounds.right - (bounds.right - bounds.left) * 0.06)
          let after: number = current
          for (const x of [nearLeft, nearRight]) {
            await driver.click(x, midY)
            await driver.delayMs(700)
            try { after = await sharedVisiblePage(driver) } catch (_) {}
            if (after !== current) break
          }
          if (after === current) break
          current = after
        }
        if (current === start) {
          await capture(driver, `write-stuck-${start}`)
          throw new Error(`NextE Reader did not turn from page ${start}`)
        }
        await showSharedChrome(driver)
        const label: string = await sharedPageLabel(driver)
        const reached: number = pageLabelIndex(label)
        await capture(driver, `write-page-${reached}`)
        await closeAnyReader(driver)

        let facts = await progressFacts(database, gid)
        for (let attempt: number = 0; attempt < 80 && !facts.present; attempt++) {
          await driver.delayMs(250)
          facts = await progressFacts(database, gid)
        }
        expect(facts.present).assertTrue()
        expected.gid = gid
        expected.pageIndex = facts.pageIndex
        expected.pageCount = Number(label.split('/')[1].trim())
        expected.durablePageIndex = facts.pageIndex
        expected.columnMode = facts.columnMode
        expected.writtenAt = Date.now()
        writeRecord(expected)
        console.info(`[NextERuntimeContinuityWriteTrial] gid=${gid} durablePage=${facts.pageIndex} ` +
          `observed=${reached} column=${facts.columnMode}`)
        return
      }

      const facts = await progressFacts(database, expected.gid)
      expect(facts.present).assertTrue()
      expect(facts.pageIndex).assertEqual(expected.durablePageIndex)
      expect(facts.columnMode).assertEqual(expected.columnMode)
      await capture(driver, 'verify-durable-state')

      gid = expected.gid
      const pattern = `^gallery-list-history-[0-9]+-history-${gid}$`
      await openHistoryList(driver)
      let opened: boolean = false
      for (let attempt: number = 0; attempt < 120 && !opened; attempt++) {
        const row = await driver.findComponent(ON.id(pattern, MatchPattern.REG_EXP))
        if (row !== null) { await row.click(); opened = true; break }
        const lists = await driver.findComponents(ON.type('List')) ?? []
        for (const list of lists) {
          const found = await list.scrollSearch(ON.id(pattern, MatchPattern.REG_EXP), true)
          if (found !== null) { await found.click(); opened = true; break }
        }
        if (!opened) await driver.delayMs(250)
      }
      if (!opened) {
        await capture(driver, 'verify-history-missing')
        throw new Error(`NextE History row missing for gid ${gid}`)
      }
      await tapDetailReadAction(driver)
      await waitId(driver, 'rkit-reading-surface', 240)
      const resumed: number = await sharedVisiblePage(driver)
      expect(resumed).assertEqual(expected.pageIndex)
      await capture(driver, `verify-resumed-${resumed}`)
      await closeAnyReader(driver)

      // Closing the reader returns to the retained Detail page, which hides the
      // root tab bar; unwind to the root before opening Reader settings again.
      for (let attempt: number = 0; attempt < 12; attempt++) {
        if (await driver.findComponent(ON.id('nexte-root-tab-4')) !== null) break
        await driver.pressBack()
        await driver.delayMs(600)
      }
      // The rehearsal selector is process-local: closing the reader does not
      // reset it, and only a normal launch returns the process to Legacy (that
      // cold-start behavior is asserted at the top of this trial). Put it back
      // explicitly so this run cannot leak Shared into a later session.
      await openBackendSettings(driver)
      await selectBackend(driver, NextEReaderBackend.LEGACY)
      await leaveBackendSettings(driver)
      expect(connectNextEReaderBackendSelection().current()).assertEqual(NextEReaderBackend.LEGACY)
      console.info(`[NextERuntimeContinuityVerifyTrial] gid=${gid} resumed=${resumed} ` +
        `expected=${expected.pageIndex} coldStart=legacy reset=legacy`)
    })
  })
}
