import { BusinessError, pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { ClipboardLinkSettings } from '../settings/ClipboardLinkSettings'
import { connectClipboardLinkSettings } from '../state/ClipboardLinkSettingsState'
import { EhUrlRouter } from '../utils/EhUrlRouter'

/** Foreground-only clipboard probe. It never logs or persists clipboard content. */
export class ClipboardLinkService {
  static async probe(context: common.UIAbilityContext): Promise<string> {
    const state = connectClipboardLinkSettings()
    if (!state.enabled) {
      return ''
    }
    const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
    try {
      if (!await systemPasteboard.hasData()) {
        return ''
      }
      const changeCount: number = systemPasteboard.getChangeCount()
      if (changeCount === state.lastChangeCount) {
        return ''
      }
      const hasSupportedText: boolean =
        systemPasteboard.hasDataType(pasteboard.MIMETYPE_TEXT_PLAIN) ||
        systemPasteboard.hasDataType(pasteboard.MIMETYPE_TEXT_URI) ||
        systemPasteboard.hasDataType(pasteboard.MIMETYPE_TEXT_HTML)
      if (!hasSupportedText) {
        await ClipboardLinkSettings.markChangeCount(context, changeCount)
        return ''
      }
      const patterns: pasteboard.Pattern[] = await systemPasteboard.detectPatterns([pasteboard.Pattern.URL])
      if (patterns.indexOf(pasteboard.Pattern.URL) < 0) {
        await ClipboardLinkSettings.markChangeCount(context, changeCount)
        return ''
      }
      const data: pasteboard.PasteData = await systemPasteboard.getData()
      const url: string = await ClipboardLinkService.extractUrl(data)
      await ClipboardLinkSettings.markChangeCount(context, changeCount)
      if (url.length > 0) {
        const kind: string = EhUrlRouter.parseGallery(url) !== null ? 'gallery' : 'image-page'
        DiagnosticLogger.info('clipboard', 'candidate_found', `kind=${kind} changeCount=${changeCount}`)
      }
      return url
    } catch (error) {
      const businessError: BusinessError = error as BusinessError
      if (businessError.code === 201) {
        DiagnosticLogger.warn('clipboard', 'read_permission_missing', 'code=201')
        await ClipboardLinkSettings.disableAfterPermissionFailure(context)
        return ''
      }
      DiagnosticLogger.warn(
        'clipboard',
        'probe_failed',
        `code=${businessError.code ?? 0} message=${businessError.message}`,
      )
      return ''
    }
  }

  private static async extractUrl(data: pasteboard.PasteData): Promise<string> {
    const recordCount: number = data.getRecordCount()
    for (let i: number = 0; i < recordCount; i++) {
      const record: pasteboard.PasteDataRecord = data.getRecord(i)
      const candidates: string[] = [
        record.plainText ?? '',
        record.uri ?? '',
        record.htmlText ?? '',
        record.toPlainText() ?? '',
      ]
      for (let j: number = 0; j < candidates.length; j++) {
        const url: string | null = EhUrlRouter.extractFirstHandleableUrl(candidates[j])
        if (url !== null) {
          return url
        }
      }
      const entryTypes: string[] = record.getValidTypes([
        pasteboard.MIMETYPE_TEXT_PLAIN,
        pasteboard.MIMETYPE_TEXT_URI,
        pasteboard.MIMETYPE_TEXT_HTML,
      ])
      for (let j: number = 0; j < entryTypes.length; j++) {
        const value: pasteboard.ValueType = await record.getData(entryTypes[j])
        const text: string = ClipboardLinkService.textFromEntryValue(value)
        if (text.length === 0) {
          continue
        }
        const url: string | null = EhUrlRouter.extractFirstHandleableUrl(text)
        if (url !== null) {
          return url
        }
      }
    }
    return ''
  }

  private static textFromEntryValue(value: pasteboard.ValueType): string {
    if (typeof value === 'string') {
      return value
    }
    if (value instanceof ArrayBuffer) {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
      return decoder.decodeToString(new Uint8Array(value))
    }
    return ''
  }
}
