import { describe, expect, it } from '@ohos/hypium'
import { BackupService } from 'shared'

function localData(
  readProgress: string,
  viewedHistory: string,
  localFavorites: string,
  searchHistory: string,
  localBlock: string,
  customProfiles: string,
  includeImageBlock: boolean,
  imageBlock: string,
): string {
  const imageBlockPart: string = includeImageBlock ? `,"imageBlock":${imageBlock}` : ''
  return `{"readProgress":${readProgress},"viewedHistory":${viewedHistory},` +
    `"localFavorites":${localFavorites},"searchHistory":${searchHistory},` +
    `"localBlock":${localBlock},"customProfiles":${customProfiles}${imageBlockPart}}`
}

function validLocalData(includeImageBlock: boolean): string {
  return localData(
    '[{"g":"gallery-1","i":3,"t":5}]',
    '[]',
    '[]',
    '["safe query"]',
    '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
    '{"selectedUuid":"","profiles":[]}',
    includeImageBlock,
    '{"rules":[]}',
  )
}

function envelopeWithLocalData(localDataJson: string, declaresLocalData: boolean): string {
  const sections: string = declaresLocalData ? '["preferences","localData"]' : '["preferences"]'
  return `{"magic":"NEXTE_BACKUP","appId":"com.erosteam.nexte","schemaVersion":1,` +
    `"minSupportedSchemaVersion":1,"createdAt":"2026-07-12T00:00:00.000Z",` +
    `"appVersion":"test","appVersionCode":1,"sections":${sections},` +
    `"counts":{"preferences":0},"data":{"preferences":{},"localData":${localDataJson}}}`
}

function envelopeWithoutLocalDataButSection(): string {
  return '{"magic":"NEXTE_BACKUP","appId":"com.erosteam.nexte","schemaVersion":1,' +
    '"minSupportedSchemaVersion":1,"createdAt":"2026-07-12T00:00:00.000Z",' +
    '"appVersion":"test","appVersionCode":1,"sections":["preferences","localData"],' +
    '"counts":{"preferences":0},"data":{"preferences":{}}}'
}

async function parseOk(raw: string): Promise<boolean> {
  const result = await BackupService.parseAndPreview(raw)
  return result.ok
}

async function parseMalformed(raw: string): Promise<boolean> {
  const result = await BackupService.parseAndPreview(raw)
  return !result.ok && result.code === 'malformed'
}

export default function backupLocalDataStructureGuardTest(): void {
  describe('Backup local-data structure guard', () => {
    it('accepts the original local-data shape without newer optional fields', 0, async (done: Function) => {
      expect(await parseOk(envelopeWithLocalData(validLocalData(false), true))).assertEqual(true)
      done()
    })

    it('accepts explicit empty replacement snapshots and the current image-block section', 0, async (done: Function) => {
      const emptySnapshot: string = localData(
        '[]',
        '[]',
        '[]',
        '[]',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
        '{"selectedUuid":"","profiles":[]}',
        true,
        '{"rules":[]}',
      )
      expect(await parseOk(envelopeWithLocalData(emptySnapshot, true))).assertEqual(true)
      done()
    })

    it('rejects a missing or wrongly typed authoritative dataset before preview', 0, async (done: Function) => {
      const missingReadProgress: string =
        '{"viewedHistory":[],"localFavorites":[],"searchHistory":[],"localBlock":' +
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]},' +
        '"customProfiles":{"selectedUuid":"","profiles":[]}}'
      const wrongSearchHistory: string = localData(
        '[]',
        '[]',
        '[]',
        '{}',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
        '{"selectedUuid":"","profiles":[]}',
        false,
        '',
      )
      const wrongProgressEntry: string = localData(
        '[{"g":1,"i":3,"t":5}]',
        '[]',
        '[]',
        '[]',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
        '{"selectedUuid":"","profiles":[]}',
        false,
        '',
      )
      expect(await parseMalformed(envelopeWithLocalData(missingReadProgress, true))).assertEqual(true)
      expect(await parseMalformed(envelopeWithLocalData(wrongSearchHistory, true))).assertEqual(true)
      expect(await parseMalformed(envelopeWithLocalData(wrongProgressEntry, true))).assertEqual(true)
      done()
    })

    it('rejects malformed nested sections and section-data topology mismatches', 0, async (done: Function) => {
      const malformedLocalBlock: string = localData(
        '[]',
        '[]',
        '[]',
        '[]',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":{}}',
        '{"selectedUuid":"","profiles":[]}',
        false,
        '',
      )
      const malformedCustomProfiles: string = localData(
        '[]',
        '[]',
        '[]',
        '[]',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
        '{"selectedUuid":"","profiles":[{"uuid":7}]}',
        false,
        '',
      )
      const malformedImageBlock: string = localData(
        '[]',
        '[]',
        '[]',
        '[]',
        '{"filterCommentsByScore":false,"scoreFilteringThreshold":0,"commentDisplayMode":"all","rules":[]}',
        '{"selectedUuid":"","profiles":[]}',
        true,
        '{}',
      )
      expect(await parseMalformed(envelopeWithLocalData(malformedLocalBlock, true))).assertEqual(true)
      expect(await parseMalformed(envelopeWithLocalData(malformedCustomProfiles, true))).assertEqual(true)
      expect(await parseMalformed(envelopeWithLocalData(malformedImageBlock, true))).assertEqual(true)
      expect(await parseMalformed(envelopeWithLocalData(validLocalData(false), false))).assertEqual(true)
      expect(await parseMalformed(envelopeWithoutLocalDataButSection())).assertEqual(true)
      done()
    })
  })
}
