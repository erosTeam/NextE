import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { EhConstants } from '../constants/EhConstants'

/**
 * System share helpers (ShareKit `systemShare`). Shared by the detail page and the reader so the share
 * payload (a gallery's public /g/<gid>/<token>/ URL as a HYPERLINK + its title) is built one way.
 */
export class ShareUtil {
  /** Open the system share sheet for an arbitrary URL. */
  static shareUrl(
    context: common.UIAbilityContext,
    url: string,
    title: string,
  ): void {
    if (url.length === 0) {
      return
    }
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.HYPERLINK,
      content: url,
      title: title,
    }
    const data: systemShare.SharedData = new systemShare.SharedData(record)
    const controller: systemShare.ShareController = new systemShare.ShareController(data)
    controller
      .show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      })
      .catch(() => {})
  }

  /** Open the system share sheet for a gallery's public URL. No-op when gid/token are missing. */
  static shareGallery(
    context: common.UIAbilityContext,
    gid: string,
    token: string,
    isEx: boolean,
    title: string,
  ): void {
    if (gid.length === 0 || token.length === 0) {
      return
    }
    const url: string = `${EhConstants.baseUrl(isEx)}/g/${gid}/${token}/`
    ShareUtil.shareUrl(context, url, title)
  }
}
