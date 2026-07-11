import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { BackupChecksum } from './BackupChecksum'
import { BackupCrypto, BackupSealResult } from './BackupCrypto'
import { BackupLocalDataAdapter } from './BackupLocalDataAdapter'
import { BackupPreferencesAdapter } from './BackupPreferencesAdapter'
import {
  BackupAppMetadata,
  BackupCipherMeta,
  BackupData,
  BackupEncryptedEnvelope,
  BackupEnvelopeV1,
  BackupExportOptions,
  BackupLocalDataSection,
  BackupParseResult,
  BackupPreview,
  BackupRestoreResult,
  BackupSectionName,
  BackupSettingsValue,
} from './BackupTypes'
import {
  BACKUP_APP_ID,
  BACKUP_MAGIC,
  BACKUP_MIN_SUPPORTED_SCHEMA_VERSION,
  BACKUP_SCHEMA_VERSION,
  MAX_BACKUP_BYTES,
} from './BackupTypes'

type SettingsMap = Record<string, BackupSettingsValue>

/**
 * Orchestrates settings backup/restore (ported from V2Next, simplified for NextE's single store).
 * Plaintext export = the non-secret store keys. Encrypted export = plaintext + the secret keys, sealed
 * under a password (AES-256-GCM). Import recognizes an encrypted file without the password and asks for
 * one; a wrong password fails GCM auth and surfaces as 'bad_password'.
 */
export class BackupService {
  static async serializeBackup(
    context: common.UIAbilityContext,
    metadata: BackupAppMetadata,
    options: BackupExportOptions,
  ): Promise<string> {
    const envelope: BackupEnvelopeV1 = await BackupService.buildEnvelope(context, metadata, options)
    if (options.includeSecrets) {
      const sealed: BackupSealResult = BackupCrypto.seal(JSON.stringify(envelope), options.password)
      const container: BackupEncryptedEnvelope = {
        magic: BACKUP_MAGIC,
        appId: BACKUP_APP_ID,
        schemaVersion: envelope.schemaVersion,
        minSupportedSchemaVersion: envelope.minSupportedSchemaVersion,
        encrypted: true,
        createdAt: envelope.createdAt,
        appVersion: envelope.appVersion,
        appVersionCode: envelope.appVersionCode,
        cipherMeta: sealed.cipherMeta,
        ciphertext: sealed.ciphertext,
      }
      return JSON.stringify(container, null, 2)
    }
    return JSON.stringify(envelope, null, 2)
  }

  private static async buildEnvelope(
    context: common.UIAbilityContext,
    metadata: BackupAppMetadata,
    options: BackupExportOptions,
  ): Promise<BackupEnvelopeV1> {
    const prefs: SettingsMap = await BackupPreferencesAdapter.exportPreferences(context)
    const localData: BackupLocalDataSection = await BackupLocalDataAdapter.exportSection(context)
    const sections: BackupSectionName[] = ['preferences', 'localData']
    const data: BackupData = { preferences: prefs, localData: localData }
    const envelope: BackupEnvelopeV1 = {
      magic: BACKUP_MAGIC,
      appId: BACKUP_APP_ID,
      schemaVersion: BACKUP_SCHEMA_VERSION,
      minSupportedSchemaVersion: BACKUP_MIN_SUPPORTED_SCHEMA_VERSION,
      createdAt: new Date().toISOString(),
      appVersion: metadata.appVersion,
      appVersionCode: metadata.appVersionCode,
      sections: sections,
      counts: {
        preferences: BackupPreferencesAdapter.count(prefs),
        localData: {
          readProgress: localData.readProgress.length,
          viewedHistory: localData.viewedHistory.length,
          localFavorites: localData.localFavorites.length,
          searchHistory: localData.searchHistory.length,
          localBlockRules: localData.localBlock.rules.length,
          imageBlockRules: localData.imageBlock.rules.length,
          customProfiles: localData.customProfiles.profiles.length,
        },
      },
      data: data,
    }
    if (options.includeSecrets) {
      const secrets: SettingsMap = await BackupPreferencesAdapter.exportSecrets(context)
      data.secrets = secrets
      envelope.sections = ['preferences', 'localData', 'secrets']
      envelope.counts.secrets = BackupPreferencesAdapter.count(secrets)
    }
    return await BackupChecksum.signEnvelope(envelope)
  }

  // Parse a raw file. A recognized encrypted container returns ok=false + encrypted=true +
  // 'password_required' so the caller prompts for a password.
  static async parseAndPreview(raw: string): Promise<BackupParseResult> {
    return BackupService.parseEnvelope(raw, false)
  }

  static async decryptAndPreview(raw: string, password: string): Promise<BackupParseResult> {
    if (BackupService.isTooLarge(raw)) {
      return { ok: false, code: 'too_large', message: 'backup file is too large' }
    }
    let container: BackupEncryptedEnvelope
    try {
      container = JSON.parse(raw) as BackupEncryptedEnvelope
    } catch (_error) {
      return { ok: false, code: 'not_json', message: 'not a valid JSON file' }
    }
    if (
      !container ||
      container.magic !== BACKUP_MAGIC ||
      container.appId !== BACKUP_APP_ID ||
      container.encrypted !== true
    ) {
      return { ok: false, code: 'foreign_backup', message: 'not a NextE backup' }
    }
    const meta: BackupCipherMeta | undefined = container.cipherMeta
    if (
      meta === undefined ||
      meta === null ||
      typeof meta !== 'object' ||
      Array.isArray(meta) ||
      typeof container.ciphertext !== 'string' ||
      container.ciphertext.length === 0 ||
      !BackupCrypto.isSupportedMeta(meta)
    ) {
      return { ok: false, code: 'malformed', message: 'backup is malformed' }
    }
    let plaintext: string
    try {
      plaintext = BackupCrypto.open(container.ciphertext, password, meta)
    } catch (_error) {
      return { ok: false, code: 'bad_password', message: 'wrong password or damaged backup' }
    }
    return BackupService.parseEnvelope(plaintext, true)
  }

  private static async parseEnvelope(
    raw: string,
    fromEncrypted: boolean,
  ): Promise<BackupParseResult> {
    if (BackupService.isTooLarge(raw)) {
      return { ok: false, code: 'too_large', message: 'backup file is too large' }
    }
    let parsed: Object
    try {
      parsed = JSON.parse(raw) as Object
    } catch (_error) {
      return { ok: false, code: 'not_json', message: 'not a valid JSON file' }
    }
    if (Array.isArray(parsed) || parsed === null || typeof parsed !== 'object') {
      return { ok: false, code: 'not_json', message: 'backup root must be an object' }
    }
    if (!fromEncrypted && BackupService.isEncryptedContainer(parsed)) {
      return {
        ok: false,
        encrypted: true,
        code: 'password_required',
        message: 'backup is encrypted',
      }
    }
    const envelope = parsed as BackupEnvelopeV1
    if (envelope.magic !== BACKUP_MAGIC || envelope.appId !== BACKUP_APP_ID) {
      return { ok: false, code: 'foreign_backup', message: 'not a NextE backup' }
    }
    if (
      envelope.schemaVersion > BACKUP_SCHEMA_VERSION ||
      envelope.minSupportedSchemaVersion > BACKUP_SCHEMA_VERSION
    ) {
      return { ok: false, code: 'unsupported_version', message: 'unsupported backup version' }
    }
    if (!Array.isArray(envelope.sections) || envelope.data === undefined) {
      return { ok: false, code: 'malformed', message: 'backup sections are malformed' }
    }
    // The 'secrets' section is valid ONLY inside a decrypted container; reject it in plaintext so
    // credentials can never ride in cleartext.
    if (!fromEncrypted && envelope.sections.indexOf('secrets') >= 0) {
      return { ok: false, code: 'malformed', message: 'unexpected encrypted section' }
    }
    const checksumOk: boolean = await BackupChecksum.verifyEnvelope(envelope)
    if (!checksumOk) {
      return { ok: false, code: 'bad_checksum', message: 'backup failed integrity check' }
    }
    return { ok: true, envelope: envelope, code: '', message: '' }
  }

  private static isTooLarge(raw: string): boolean {
    return new util.TextEncoder().encodeInto(raw).length > MAX_BACKUP_BYTES
  }

  private static isEncryptedContainer(value: Object): boolean {
    const container = value as BackupEncryptedEnvelope
    return (
      container.magic === BACKUP_MAGIC &&
      container.appId === BACKUP_APP_ID &&
      container.encrypted === true
    )
  }

  static preview(envelope: BackupEnvelopeV1): BackupPreview {
    return {
      createdAt: envelope.createdAt,
      appVersion: envelope.appVersion,
      appVersionCode: envelope.appVersionCode,
      sections: envelope.sections,
      counts: envelope.counts,
      hasSecrets: envelope.sections.indexOf('secrets') >= 0,
    }
  }

  static async restoreBackup(
    context: common.UIAbilityContext,
    envelope: BackupEnvelopeV1,
  ): Promise<BackupRestoreResult> {
    const fromEncrypted: boolean = envelope.sections.indexOf('secrets') >= 0
    const rollbackPreferences: SettingsMap = await BackupPreferencesAdapter.exportPreferences(context)
    const rollbackLocalData: BackupLocalDataSection = await BackupLocalDataAdapter.exportSection(context)
    const rollbackSecrets: SettingsMap = await BackupPreferencesAdapter.exportSecrets(context)
    let failedSection: BackupSectionName = 'preferences'
    try {
      if (envelope.data.preferences !== undefined) {
        failedSection = 'preferences'
        await BackupPreferencesAdapter.restore(context, envelope.data.preferences, false)
      }
      if (envelope.data.localData !== undefined) {
        failedSection = 'localData'
        await BackupLocalDataAdapter.restoreSection(context, envelope.data.localData)
      } else {
        // Old backups only carry reading.progress in Preferences; migrate that freshly restored key.
        failedSection = 'localData'
        await BackupLocalDataAdapter.restoreLegacyPreferences(context)
      }
      if (fromEncrypted && envelope.data.secrets !== undefined) {
        failedSection = 'secrets'
        await BackupPreferencesAdapter.restore(context, envelope.data.secrets, true)
      }
      // Re-hydrate live state from the freshly written store.
      await BackupPreferencesAdapter.reapply(context)
    } catch (error) {
      let message: string = (error as Error).message
      try {
        await BackupPreferencesAdapter.replace(context, rollbackPreferences, false)
        await BackupLocalDataAdapter.restoreSection(context, rollbackLocalData)
        await BackupPreferencesAdapter.replace(context, rollbackSecrets, true)
        await BackupPreferencesAdapter.reapply(context)
      } catch (rollbackError) {
        message = `${message}; rollback failed: ${(rollbackError as Error).message}`
      }
      return {
        ok: false,
        restoredSections: [],
        failedSections: [failedSection],
        message: message,
      }
    }
    return {
      ok: true,
      restoredSections: envelope.sections,
      failedSections: [],
      message: '',
    }
  }
}
