import { describe, expect, it } from '@ohos/hypium'
import {
  CustomProfile,
  PROFILE_TYPE_FAVORITE,
  PROFILE_TYPE_GALLERY,
  SyncCustomProfileRecord,
  SyncEnvelopeV1,
  SyncLocalDataAdapter,
} from 'shared'

function profileRecord(
  uuid: string,
  lastEditTime: number,
  displayMode: string,
  hidden: boolean,
  positionIndex: number,
  deletedAt: number = 0,
): SyncCustomProfileRecord {
  const record: SyncCustomProfileRecord = new SyncCustomProfileRecord()
  record.scopeKey = 'global'
  record.uuid = uuid
  record.listType = PROFILE_TYPE_GALLERY
  record.lastEditTime = lastEditTime
  record.displayMode = displayMode
  record.hidden = hidden
  record.positionIndex = positionIndex
  record.deletedAt = deletedAt
  return record
}

export default function customProfileSyncSemanticsTest(): void {
  describe('Custom profile sync semantics', () => {
    it('keeps presentation-only changes out of the gallery request revision', 0, (done: Function) => {
      const profile: CustomProfile = new CustomProfile()
      profile.listType = PROFILE_TYPE_GALLERY
      profile.searchText = 'artist:test'
      const before: string = profile.contentRevision()

      profile.name = 'Renamed'
      profile.displayMode = 'waterfall'
      profile.hidden = true
      profile.lastEditTime = 999
      expect(profile.contentRevision()).assertEqual(before)

      profile.searchText = 'artist:next'
      expect(profile.contentRevision() === before).assertEqual(false)

      profile.listType = PROFILE_TYPE_FAVORITE
      profile.favcat = '2'
      const favorite: string = profile.contentRevision()
      profile.favcat = '3'
      expect(profile.contentRevision() === favorite).assertEqual(false)
      done()
    })

    it('keeps newer profile presentation rows and tombstones during WebDAV merge', 0, (done: Function) => {
      const local: SyncEnvelopeV1 = new SyncEnvelopeV1()
      local.datasets.customProfiles = [profileRecord('profile-a', 200, 'waterfall', true, 3)]

      const staleRemote: SyncEnvelopeV1 = new SyncEnvelopeV1()
      staleRemote.datasets.customProfiles = [profileRecord('profile-a', 100, 'grid', false, 0)]
      let merged: SyncEnvelopeV1 = SyncLocalDataAdapter.mergeEnvelopes(local, staleRemote)
      expect(merged.datasets.customProfiles.length).assertEqual(1)
      expect(merged.datasets.customProfiles[0].displayMode).assertEqual('waterfall')
      expect(merged.datasets.customProfiles[0].hidden).assertEqual(true)
      expect(merged.datasets.customProfiles[0].positionIndex).assertEqual(3)

      const tombstoneRemote: SyncEnvelopeV1 = new SyncEnvelopeV1()
      tombstoneRemote.datasets.customProfiles = [profileRecord('profile-a', 100, '', false, 0, 300)]
      merged = SyncLocalDataAdapter.mergeEnvelopes(local, tombstoneRemote)
      expect(merged.datasets.customProfiles[0].deletedAt).assertEqual(300)

      // A tombstone generated for a row that already has a future edit clock must advance past that
      // clock; otherwise an older active record can win the next cross-device merge and resurrect it.
      const futureClockTombstone: SyncEnvelopeV1 = new SyncEnvelopeV1()
      futureClockTombstone.datasets.customProfiles = [
        profileRecord('profile-future', 900, '', false, 0, 901),
      ]
      const staleActive: SyncEnvelopeV1 = new SyncEnvelopeV1()
      staleActive.datasets.customProfiles = [
        profileRecord('profile-future', 900, 'grid', false, 0),
      ]
      merged = SyncLocalDataAdapter.mergeEnvelopes(futureClockTombstone, staleActive)
      expect(merged.datasets.customProfiles[0].deletedAt).assertEqual(901)
      done()
    })
  })
}
