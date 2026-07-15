export enum ReaderTapZoneLayout {
  RIGHT_LEFT = 'rightLeft',
  L_SHAPED = 'lShaped',
  KINDLE = 'kindle',
  EDGE = 'edge',
}

export enum ReaderTapZoneInvert {
  NONE = 'none',
  HORIZONTAL = 'horizontal',
  VERTICAL = 'vertical',
  BOTH = 'both',
}

export enum ReaderTapZoneAction {
  MENU = 'menu',
  PREVIOUS = 'previous',
  NEXT = 'next',
  LEFT = 'left',
  RIGHT = 'right',
}

export class ReaderTapZoneRegion {
  key: string
  left: number
  top: number
  right: number
  bottom: number
  action: string

  constructor(
    key: string,
    left: number,
    top: number,
    right: number,
    bottom: number,
    action: string,
  ) {
    this.key = key
    this.left = left
    this.top = top
    this.right = right
    this.bottom = bottom
    this.action = action
  }
}

/** Mihon's normalized tap-zone geometry, shared by hit testing and the one-shot reader preview. */
export class ReaderTapZoneResolver {
  static normalizeLayout(layout: string): string {
    if (layout === ReaderTapZoneLayout.L_SHAPED ||
      layout === ReaderTapZoneLayout.KINDLE ||
      layout === ReaderTapZoneLayout.EDGE ||
      layout === ReaderTapZoneLayout.RIGHT_LEFT) {
      return layout
    }
    return ReaderTapZoneLayout.RIGHT_LEFT
  }

  static normalizeInvert(invert: string): string {
    if (invert === ReaderTapZoneInvert.HORIZONTAL ||
      invert === ReaderTapZoneInvert.VERTICAL ||
      invert === ReaderTapZoneInvert.BOTH ||
      invert === ReaderTapZoneInvert.NONE) {
      return invert
    }
    return ReaderTapZoneInvert.NONE
  }

  static regions(layout: string, invert: string): ReaderTapZoneRegion[] {
    const base: ReaderTapZoneRegion[] = ReaderTapZoneResolver.baseRegions(
      ReaderTapZoneResolver.normalizeLayout(layout),
    )
    const normalizedInvert: string = ReaderTapZoneResolver.normalizeInvert(invert)
    if (normalizedInvert === ReaderTapZoneInvert.NONE) {
      return base
    }
    const out: ReaderTapZoneRegion[] = []
    for (let i: number = 0; i < base.length; i++) {
      out.push(ReaderTapZoneResolver.invertRegion(base[i], normalizedInvert))
    }
    return out
  }

  static resolve(
    layout: string,
    invert: string,
    x: number,
    y: number,
    width: number,
    height: number,
  ): string {
    if (width <= 0 || height <= 0) {
      return ReaderTapZoneAction.MENU
    }
    const nx: number = ReaderTapZoneResolver.clamp01(x / width)
    const ny: number = ReaderTapZoneResolver.clamp01(y / height)
    const regions: ReaderTapZoneRegion[] = ReaderTapZoneResolver.regions(layout, invert)
    for (let i: number = 0; i < regions.length; i++) {
      if (ReaderTapZoneResolver.contains(regions[i], nx, ny)) {
        return regions[i].action
      }
    }
    return ReaderTapZoneAction.MENU
  }

  private static baseRegions(layout: string): ReaderTapZoneRegion[] {
    const oneThird: number = 1 / 3
    const twoThirds: number = 2 / 3
    if (layout === ReaderTapZoneLayout.L_SHAPED) {
      return [
        new ReaderTapZoneRegion('l-prev-top', 0, 0, 1, oneThird, ReaderTapZoneAction.PREVIOUS),
        new ReaderTapZoneRegion('l-prev-left', 0, oneThird, oneThird, twoThirds, ReaderTapZoneAction.PREVIOUS),
        new ReaderTapZoneRegion('l-menu', oneThird, oneThird, twoThirds, twoThirds, ReaderTapZoneAction.MENU),
        new ReaderTapZoneRegion('l-next-right', twoThirds, oneThird, 1, twoThirds, ReaderTapZoneAction.NEXT),
        new ReaderTapZoneRegion('l-next-bottom', 0, twoThirds, 1, 1, ReaderTapZoneAction.NEXT),
      ]
    }
    if (layout === ReaderTapZoneLayout.KINDLE) {
      return [
        new ReaderTapZoneRegion('kindle-menu', 0, 0, 1, oneThird, ReaderTapZoneAction.MENU),
        new ReaderTapZoneRegion('kindle-prev', 0, oneThird, oneThird, 1, ReaderTapZoneAction.PREVIOUS),
        new ReaderTapZoneRegion('kindle-next', oneThird, oneThird, 1, 1, ReaderTapZoneAction.NEXT),
      ]
    }
    if (layout === ReaderTapZoneLayout.EDGE) {
      return [
        new ReaderTapZoneRegion('edge-next-left', 0, 0, oneThird, 1, ReaderTapZoneAction.NEXT),
        new ReaderTapZoneRegion('edge-menu', oneThird, 0, twoThirds, twoThirds, ReaderTapZoneAction.MENU),
        new ReaderTapZoneRegion('edge-prev', oneThird, twoThirds, twoThirds, 1, ReaderTapZoneAction.PREVIOUS),
        new ReaderTapZoneRegion('edge-next-right', twoThirds, 0, 1, 1, ReaderTapZoneAction.NEXT),
      ]
    }
    return [
      new ReaderTapZoneRegion('right-left-left', 0, 0, oneThird, 1, ReaderTapZoneAction.LEFT),
      new ReaderTapZoneRegion('right-left-menu', oneThird, 0, twoThirds, 1, ReaderTapZoneAction.MENU),
      new ReaderTapZoneRegion('right-left-right', twoThirds, 0, 1, 1, ReaderTapZoneAction.RIGHT),
    ]
  }

  private static invertRegion(region: ReaderTapZoneRegion, invert: string): ReaderTapZoneRegion {
    const horizontal: boolean = invert === ReaderTapZoneInvert.HORIZONTAL || invert === ReaderTapZoneInvert.BOTH
    const vertical: boolean = invert === ReaderTapZoneInvert.VERTICAL || invert === ReaderTapZoneInvert.BOTH
    const left: number = horizontal ? 1 - region.right : region.left
    const right: number = horizontal ? 1 - region.left : region.right
    const top: number = vertical ? 1 - region.bottom : region.top
    const bottom: number = vertical ? 1 - region.top : region.bottom
    // Inversion changes geometry without changing the action. Include it in the identity so ArkUI
    // rebuilds preview children instead of reusing the previous positions for the same base region.
    return new ReaderTapZoneRegion(`${region.key}-${invert}`, left, top, right, bottom, region.action)
  }

  private static contains(region: ReaderTapZoneRegion, x: number, y: number): boolean {
    const withinX: boolean = x >= region.left && (x < region.right || region.right === 1)
    const withinY: boolean = y >= region.top && (y < region.bottom || region.bottom === 1)
    return withinX && withinY
  }

  private static clamp01(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 1) {
      return 1
    }
    return value
  }
}
