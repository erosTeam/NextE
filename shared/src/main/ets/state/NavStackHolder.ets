import { AppStorageV2 } from '@kit.ArkUI'
import { installGalleryDetailDuplicateInterception } from '../navigation/GalleryDetailNavigation'
import { GalleryDetailParams } from '../model/RouteParams'

const GALLERY_DETAIL_ROUTE_NAME: string = 'GalleryDetail'
const SETTINGS_ROOT_ROUTE_NAMES: string[] = [
  'Account',
  'EhSettings',
  'LayoutSettings',
  'ReaderSettings',
  'DownloadSettings',
  'SearchSettings',
  'History',
  'CacheSettings',
  'AdvancedSettings',
  'About',
]

/**
 * V2-safe holder for the app's single `NavPathStack` (pattern from V2Next).
 *
 * `stack` is never observed as reactive state — consumers use it purely as a method target
 * (pushPathByName / pop); `NavPathStack` self-manages the observation that Navigation binds to.
 * `isSplitMode` is separate, presentation-only state published by the root HDS container for
 * destination-level controls that need the resolved physical mode.
 */
@ObservedV2
export class NavStackHolder {
  @Trace stack: NavPathStack = new NavPathStack()
  @Trace isSplitMode: boolean = false
  // These identify the entry at index 0 of the secondary route branch, not its visible leaf. For
  // example, Gallery A -> Search -> Gallery B continues to select A in every list that can show it.
  // `NavPathStack` remains a command target; consumers render from this small V2 state below instead
  // of reading the stack in build().
  @Trace secondaryEntryGalleryGid: string = ''
  @Trace secondaryEntryGalleryToken: string = ''
  @Trace secondaryEntrySettingsRoute: string = ''

  constructor() {
    installGalleryDetailDuplicateInterception(this.stack, (pathStack: NavPathStack | null) => {
      this.syncSecondaryEntry(pathStack)
    })
  }

  setSplitMode(isSplitMode: boolean): void {
    if (this.isSplitMode === isSplitMode) {
      return
    }
    this.isSplitMode = isSplitMode
  }

  clearSecondaryEntry(): void {
    this.updateSecondaryEntry('', '', '')
  }

  isPrimaryPaneGallerySelected(gid: string, token: string): boolean {
    return this.isSplitMode &&
      gid.length > 0 &&
      token.length > 0 &&
      this.secondaryEntryGalleryGid === gid &&
      this.secondaryEntryGalleryToken === token
  }

  isSettingsRootSelected(name: string): boolean {
    return this.isSplitMode && this.secondaryEntrySettingsRoute === name
  }

  private syncSecondaryEntry(pathStack: NavPathStack | null): void {
    if (pathStack === null) {
      this.clearSecondaryEntry()
      return
    }

    const pathNames: string[] = pathStack.getAllPathName()
    let galleryGid: string = ''
    let galleryToken: string = ''
    let settingsRootRoute: string = ''
    const secondaryEntryName: string | undefined = pathNames[0]
    if (secondaryEntryName === GALLERY_DETAIL_ROUTE_NAME) {
      const params: GalleryDetailParams | null = this.galleryParamsAt(pathStack, 0)
      if (params !== null) {
        galleryGid = params.gid
        galleryToken = params.token
      }
    } else if (secondaryEntryName === 'AccountLogin' ||
      (secondaryEntryName !== undefined && SETTINGS_ROOT_ROUTE_NAMES.indexOf(secondaryEntryName) >= 0)) {
      settingsRootRoute = secondaryEntryName
    }

    this.updateSecondaryEntry(galleryGid, galleryToken, settingsRootRoute)
  }

  private galleryParamsAt(pathStack: NavPathStack, index: number): GalleryDetailParams | null {
    const value: Object | null | undefined = pathStack.getParamByIndex(index) as Object | null | undefined
    if (value === null || value === undefined) {
      return null
    }
    const params: GalleryDetailParams = value as GalleryDetailParams
    if (typeof params.gid !== 'string' || typeof params.token !== 'string') {
      return null
    }
    return params
  }

  private updateSecondaryEntry(gid: string, token: string, settingsRootRoute: string): void {
    if (this.secondaryEntryGalleryGid !== gid) {
      this.secondaryEntryGalleryGid = gid
    }
    if (this.secondaryEntryGalleryToken !== token) {
      this.secondaryEntryGalleryToken = token
    }
    if (this.secondaryEntrySettingsRoute !== settingsRootRoute) {
      this.secondaryEntrySettingsRoute = settingsRootRoute
    }
  }
}

const NAV_STACK_KEY: string = 'v2:navStack'

export function connectNavStack(): NavStackHolder {
  return AppStorageV2.connect(NavStackHolder, NAV_STACK_KEY, () => new NavStackHolder())!
}
