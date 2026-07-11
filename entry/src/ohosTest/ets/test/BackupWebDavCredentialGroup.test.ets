import { describe, expect, it } from '@ohos/hypium'
import {
  BackupPreferencesAdapter,
  BackupWebDavCredentialGroup,
} from 'shared'

export default function backupWebDavCredentialGroupTest(): void {
  describe('Backup WebDAV credential group', () => {
    it('accepts a complete legacy encrypted credential tuple only as one group', 0, (done: Function) => {
      const group: BackupWebDavCredentialGroup | null =
        BackupPreferencesAdapter.resolveWebDavCredentialValues(
          'https://legacy.example/dav',
          'legacy-user',
          true,
          'legacy-password',
          true,
        )
      expect(group === null).assertEqual(false)
      if (group !== null) {
        expect(group.url).assertEqual('https://legacy.example/dav')
        expect(group.username).assertEqual('legacy-user')
        expect(group.enabled).assertEqual(true)
        expect(group.password).assertEqual('legacy-password')
      }
      done()
    })

    it('accepts a complete current encrypted credential tuple', 0, (done: Function) => {
      const group: BackupWebDavCredentialGroup | null =
        BackupPreferencesAdapter.resolveWebDavCredentialValues(
          'https://current.example/dav',
          'current-user',
          false,
          'current-password',
          true,
        )
      expect(group === null).assertEqual(false)
      if (group !== null) {
        expect(group.url).assertEqual('https://current.example/dav')
        expect(group.username).assertEqual('current-user')
        expect(group.enabled).assertEqual(false)
        expect(group.password).assertEqual('current-password')
      }
      done()
    })

    it('leaves plaintext and incomplete encrypted groups inert', 0, (done: Function) => {
      const plaintext: BackupWebDavCredentialGroup | null =
        BackupPreferencesAdapter.resolveWebDavCredentialValues(
          'https://legacy.example/dav',
          'legacy-user',
          true,
          'legacy-password',
          false,
        )
      const incomplete: BackupWebDavCredentialGroup | null =
        BackupPreferencesAdapter.resolveWebDavCredentialValues(
          'https://legacy.example/dav',
          'legacy-user',
          true,
          undefined,
          true,
        )
      expect(plaintext === null).assertEqual(true)
      expect(incomplete === null).assertEqual(true)
      done()
    })
  })
}
