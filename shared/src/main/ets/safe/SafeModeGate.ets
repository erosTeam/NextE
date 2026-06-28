import {
  CustomProfile,
  PROFILE_DISPLAY_GLOBAL,
  PROFILE_TYPE_GALLERY,
} from '../model/CustomProfile'
import { connectSafeMode } from '../state/SafeModeState'

export const SAFE_MODE_PROFILE_UUID: string = 'safe-mode-noh'
export const SAFE_MODE_PROFILE_NAME: string = 'NoH'
const SAFE_MODE_NON_H_SELECTED_CATS: number = 256

export class SafeModeGate {
  static restricted(): boolean {
    return connectSafeMode().restricted()
  }

  static safeProfile(): CustomProfile {
    const profile: CustomProfile = new CustomProfile()
    profile.uuid = SAFE_MODE_PROFILE_UUID
    profile.name = SAFE_MODE_PROFILE_NAME
    profile.listType = PROFILE_TYPE_GALLERY
    profile.searchText = ''
    profile.selectedCats = SAFE_MODE_NON_H_SELECTED_CATS
    profile.displayMode = PROFILE_DISPLAY_GLOBAL
    profile.builtin = true
    return profile
  }

  static routeAllowed(name: string): boolean {
    if (!SafeModeGate.restricted()) {
      return true
    }
    if (name === 'Search' ||
      name === 'EhLogin' ||
      name === 'EhCookieImport' ||
      name === 'EhPasswordLogin' ||
      name === 'MyTags' ||
      name === 'History' ||
      name === 'FavoriteSelector' ||
      name === 'TabManager' ||
      name === 'TabEdit' ||
      name === 'GalleryArchiver' ||
      name === 'GalleryWeb' ||
      name === 'GalleryEditTags' ||
      name === 'GalleryComments' ||
      name === 'EhSettings' ||
      name === 'EhProfileSettings' ||
      name === 'Account' ||
      name === 'AccountLogin' ||
      name === 'DownloadSettings' ||
      name === 'LocalBlockSettings' ||
      name === 'TagTranslationSettings' ||
      name === 'TranslationSettings' ||
      name === 'SyncSettings' ||
      name === 'WebDavSyncSettings' ||
      name === 'SecuritySettings') {
      return false
    }
    return true
  }
}
