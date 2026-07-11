import { common } from '@kit.AbilityKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import {
  BackupService,
  BackupAppMetadata,
  BackupEnvelopeV1,
  BackupExportOptions,
  BackupParseResult,
  BACKUP_FILE_SUFFIX,
  MAX_BACKUP_BYTES,
} from 'shared'

export interface BackupImportSelection {
  raw: string
  parseResult: BackupParseResult
}

/** Bridges the backup service to the system file picker (save/select) + fd-based file I/O. */
export class BackupFilePickerCoordinator {
  static async exportBackup(
    context: common.UIAbilityContext,
    metadata: BackupAppMetadata,
    options: BackupExportOptions,
    stamp: string,
  ): Promise<string> {
    const raw: string = await BackupService.serializeBackup(context, metadata, options)
    const documentPicker = new picker.DocumentViewPicker(context)
    const saveOptions = new picker.DocumentSaveOptions()
    saveOptions.newFileNames = [`NextE-backup-${stamp}${BACKUP_FILE_SUFFIX}`]
    const uris: string[] = await documentPicker.save(saveOptions)
    if (!uris || uris.length === 0) {
      throw new Error('save cancelled')
    }
    BackupFilePickerCoordinator.writeText(uris[0], raw)
    return uris[0]
  }

  static async selectImport(context: common.UIAbilityContext): Promise<BackupImportSelection> {
    const documentPicker = new picker.DocumentViewPicker(context)
    const selectOptions = new picker.DocumentSelectOptions()
    selectOptions.fileSuffixFilters = ['NextE backup|.json']
    selectOptions.maxSelectNumber = 1
    const uris: string[] = await documentPicker.select(selectOptions)
    if (!uris || uris.length === 0) {
      throw new Error('open cancelled')
    }
    const raw: string = BackupFilePickerCoordinator.readText(uris[0])
    return { raw: raw, parseResult: await BackupService.parseAndPreview(raw) }
  }

  static async decryptSelected(raw: string, password: string): Promise<BackupParseResult> {
    return BackupService.decryptAndPreview(raw, password)
  }

  static async restoreSelected(
    context: common.UIAbilityContext,
    envelope: BackupEnvelopeV1,
  ): Promise<void> {
    const result = await BackupService.restoreBackup(context, envelope)
    if (!result.ok) {
      throw new Error(result.message)
    }
  }

  private static writeText(uri: string, raw: string): void {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        uri,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      fileIo.writeSync(file.fd, raw)
    } finally {
      if (file) {
        fileIo.closeSync(file)
      }
    }
  }

  // The picker returns a file:// uri; open it to a fd and read bytes (readTextSync(path) fails on uris).
  private static readText(uri: string): string {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const size: number = fileIo.statSync(file.fd).size
      if (size < 0 || size > MAX_BACKUP_BYTES) {
        throw new Error('backup file is too large')
      }
      const buffer = new ArrayBuffer(size)
      const bytesRead: number = fileIo.readSync(file.fd, buffer)
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(new Uint8Array(buffer, 0, bytesRead))
    } finally {
      if (file) {
        fileIo.closeSync(file)
      }
    }
  }
}
