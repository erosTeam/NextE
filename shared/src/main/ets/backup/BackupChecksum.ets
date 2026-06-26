import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { BackupCounts, BackupData, BackupEnvelopeV1, BackupSectionName } from './BackupTypes'
import { BACKUP_CHECKSUM_ALGORITHM } from './BackupTypes'

interface BackupChecksumPayload {
  magic: string
  appId: string
  schemaVersion: number
  minSupportedSchemaVersion: number
  createdAt: string
  appVersion: string
  appVersionCode: number
  sections: BackupSectionName[]
  counts: BackupCounts
  data: BackupData
}

/** SHA-256 over a canonical (key-sorted) JSON of the envelope payload, ported from V2Next. */
export class BackupChecksum {
  static canonicalEnvelope(envelope: BackupEnvelopeV1): string {
    const payload: BackupChecksumPayload = {
      magic: envelope.magic,
      appId: envelope.appId,
      schemaVersion: envelope.schemaVersion,
      minSupportedSchemaVersion: envelope.minSupportedSchemaVersion,
      createdAt: envelope.createdAt,
      appVersion: envelope.appVersion,
      appVersionCode: envelope.appVersionCode,
      sections: envelope.sections,
      counts: envelope.counts,
      data: envelope.data,
    }
    return BackupChecksum.stringifyCanonical(payload)
  }

  static async hashText(text: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256')
    const bytes = new util.TextEncoder().encodeInto(text)
    md.updateSync({ data: bytes })
    const digest = md.digestSync()
    return BackupChecksum.toHex(digest.data)
  }

  static async signEnvelope(envelope: BackupEnvelopeV1): Promise<BackupEnvelopeV1> {
    const value = await BackupChecksum.hashText(BackupChecksum.canonicalEnvelope(envelope))
    envelope.checksum = { algorithm: BACKUP_CHECKSUM_ALGORITHM, value: value }
    return envelope
  }

  static async verifyEnvelope(envelope: BackupEnvelopeV1): Promise<boolean> {
    if (!envelope.checksum) {
      return true
    }
    if (envelope.checksum.algorithm !== BACKUP_CHECKSUM_ALGORITHM) {
      return false
    }
    const value = await BackupChecksum.hashText(BackupChecksum.canonicalEnvelope(envelope))
    return value === envelope.checksum.value
  }

  private static stringifyCanonical(value: Object | string | number | boolean | null): string {
    if (value === null || typeof value !== 'object') {
      return JSON.stringify(value)
    }
    if (Array.isArray(value)) {
      return (
        '[' +
        value
          .map((item: Object | string | number | boolean | null) =>
            BackupChecksum.stringifyCanonical(item),
          )
          .join(',') +
        ']'
      )
    }
    const record = value as Record<string, Object | string | number | boolean | null>
    const keys = Object.keys(record).sort()
    const parts: string[] = []
    keys.forEach((key: string) => {
      const next = record[key]
      if (next !== undefined) {
        parts.push(JSON.stringify(key) + ':' + BackupChecksum.stringifyCanonical(next))
      }
    })
    return '{' + parts.join(',') + '}'
  }

  private static toHex(bytes: Uint8Array): string {
    const parts: string[] = []
    for (let i = 0; i < bytes.length; i++) {
      parts.push(bytes[i].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }
}
