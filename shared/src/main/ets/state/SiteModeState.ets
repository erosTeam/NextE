import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Reactive site mode: false = e-hentai (表站), true = exhentai (里站).
 * One boolean drives every host resolution (EhConstants.baseUrl/thumbHost). The settings
 * writer (SiteModeSettings, M3) is the single source that flips this mirror; ex requires
 * login + igneous, so the UI toggle is gated there.
 */
@ObservedV2
export class SiteModeState {
  @Trace isEx: boolean = false
}

const SITE_MODE_KEY: string = 'v2_siteMode'

export function connectSiteMode(): SiteModeState {
  return AppStorageV2.connect(SiteModeState, SITE_MODE_KEY, () => new SiteModeState())!
}
