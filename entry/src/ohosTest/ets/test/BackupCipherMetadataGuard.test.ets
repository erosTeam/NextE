import { describe, expect, it } from '@ohos/hypium'
import { BackupService } from 'shared'

interface FixtureCipherMeta {
  cipher: string
  kdf: string
  iterations: number
  keySize: number
  salt: string
  iv: string
}

interface FixtureEncryptedContainer {
  magic: string
  appId: string
  encrypted: boolean
  cipherMeta: FixtureCipherMeta
  ciphertext: string
}

function encryptedContainer(iterations: number, keySize: number): string {
  const cipherMeta: FixtureCipherMeta = {
    cipher: 'AES-256-GCM',
    kdf: 'PBKDF2-SHA256',
    iterations: iterations,
    keySize: keySize,
    salt: 'fixture-salt',
    iv: 'fixture-iv',
  }
  const container: FixtureEncryptedContainer = {
    magic: 'NEXTE_BACKUP',
    appId: 'com.erosteam.nexte',
    encrypted: true,
    cipherMeta: cipherMeta,
    ciphertext: 'fixture-ciphertext',
  }
  return JSON.stringify(container)
}

export default function backupCipherMetadataGuardTest(): void {
  describe('Backup cipher metadata guard', () => {
    it('rejects caller-selected KDF work before starting decrypt', 0, async (done: Function) => {
      const result = await BackupService.decryptAndPreview(
        encryptedContainer(210001, 32),
        'fixture-password',
      )
      expect(result.ok).assertEqual(false)
      expect(result.code).assertEqual('malformed')
      done()
    })
  })
}
