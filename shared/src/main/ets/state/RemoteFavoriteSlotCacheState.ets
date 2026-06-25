import { AppStorageV2 } from '@kit.ArkUI'
import { Favcat } from '../model/Favcat'

const REMOTE_FAVORITE_SLOT_CACHE_KEY: string = 'v2:remoteFavoriteSlotCache'

/**
 * Account-level cache for the EH favorite folder list used by gallery add/remove sheets.
 * It is written from the gallery favorite popup and restored from the persisted favcat snapshot, so new
 * gallery sheets can paint real folder names immediately without borrowing placeholder selector rows.
 */
@ObservedV2
export class RemoteFavoriteSlotCacheState {
  @Trace favcats: Favcat[] = []
  @Trace version: number = 0

  update(favcats: Favcat[]): void {
    const next: Favcat[] = []
    favcats.forEach((f: Favcat) => {
      next.push(new Favcat(f.favId, f.favTitle, f.totNum))
    })
    this.favcats = next
    this.version = this.version + 1
  }
}

export function connectRemoteFavoriteSlotCache(): RemoteFavoriteSlotCacheState {
  return AppStorageV2.connect(
    RemoteFavoriteSlotCacheState,
    REMOTE_FAVORITE_SLOT_CACHE_KEY,
    () => new RemoteFavoriteSlotCacheState(),
  )!
}
