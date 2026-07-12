import { GalleryDetailParams } from '../model/RouteParams'

const GALLERY_DETAIL_ROUTE_NAME: string = 'GalleryDetail'

function readGalleryDetailParams(value: Object | null | undefined): GalleryDetailParams | null {
  if (value === null || value === undefined) {
    return null
  }
  const params: GalleryDetailParams = value as GalleryDetailParams
  if (typeof params.gid !== 'string' || typeof params.token !== 'string') {
    return null
  }
  return params
}

function paramsForGalleryDetailPath(path: NavPathInfo | 'navBar'): GalleryDetailParams | null {
  if (typeof path === 'string' || path.name !== GALLERY_DETAIL_ROUTE_NAME) {
    return null
  }
  return readGalleryDetailParams(path.param as Object | null | undefined)
}

export function isSameGalleryDetail(
  left: GalleryDetailParams | null,
  right: GalleryDetailParams | null,
): boolean {
  return left !== null &&
    right !== null &&
    left.gid.length > 0 &&
    left.token.length > 0 &&
    left.gid === right.gid &&
    left.token === right.token
}

/**
 * Primary-pane list selection keeps exactly one peer GalleryDetail in the secondary stack. This is
 * deliberately separate from a normal detail push: parent-gallery and search-detail navigation retain
 * their real back history, while re-selecting the visible peer is a no-op.
 */
export function selectGalleryDetailFromPeerList(stack: NavPathStack, params: GalleryDetailParams): void {
  const pathNames: string[] = stack.getAllPathName()
  const topIndex: number = pathNames.length - 1
  if (topIndex >= 0 && pathNames[topIndex] === GALLERY_DETAIL_ROUTE_NAME) {
    const current: GalleryDetailParams | null = readGalleryDetailParams(
      stack.getParamByIndex(topIndex) as Object | null | undefined,
    )
    if (isSameGalleryDetail(current, params)) {
      return
    }
    stack.replacePathByName(GALLERY_DETAIL_ROUTE_NAME, params, true)
    return
  }
  stack.pushPathByName(GALLERY_DETAIL_ROUTE_NAME, params)
}

/**
 * Covers ordinary direct GalleryDetail pushes, such as search, history, deep links, and any future
 * non-peer entry. API 22's interception callback runs before a destination is created, so popping the
 * just-pushed duplicate leaves the already-visible detail mounted.
 */
export function installGalleryDetailDuplicateInterception(
  stack: NavPathStack,
  onSecondaryStackSettled?: (pathStack: NavPathStack | null) => void,
): void {
  stack.setInterception({
    // Navigation owns the real stack and visual transition. Refresh the secondary-branch entry only
    // after its destination settles, never from a list click or the pre-create duplicate guard below.
    didShow: (_from, to, _operation, _animated) => {
      onSecondaryStackSettled?.(typeof to === 'string' ? null : to.pathStack)
    },
    interception: (
      from: NavPathInfo | 'navBar',
      to: NavPathInfo | 'navBar',
      pathStack: NavPathStack,
      operation: NavigationOperation,
      _animated: boolean,
    ): void => {
      if (operation !== NavigationOperation.PUSH) {
        return
      }
      if (!isSameGalleryDetail(paramsForGalleryDetailPath(from), paramsForGalleryDetailPath(to))) {
        return
      }
      // The duplicate is the just-pushed top item. Suppress a second destination and its reload.
      pathStack.pop(false)
    },
  })
}
