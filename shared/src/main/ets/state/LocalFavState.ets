import { AppStorageV2 } from '@kit.ArkUI'
import { EhGallery } from '../model/EhGallery'

const LOCAL_FAV_V2_KEY: string = 'v2:localFavorites'

/** Local-only favorite galleries, mirroring eros_fe's synthetic `l` favcat slot. */
@ObservedV2
export class LocalFavState {
  @Trace items: EhGallery[] = []

  count(): number {
    return this.items.length
  }
}

export function connectLocalFav(): LocalFavState {
  return AppStorageV2.connect(LocalFavState, LOCAL_FAV_V2_KEY, () => new LocalFavState())!
}
