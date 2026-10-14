import {
  ActionHandEdgeState,
  connectActionHandEdge,
  ThemeConstants,
} from 'shared'

/** Owns FAB measurements and motion without invalidating the gallery detail body. */
@ComponentV2
export struct GalleryActionFabRail {
  @Param availableWidth: number = 0;
  @Param usesHdsMaterial: boolean = true;
  @BuilderParam readButtonContent: () => void
  @BuilderParam favoriteButtonContent: () => void
  @Local actionEdge: ActionHandEdgeState = connectActionHandEdge();
  @Local edgeProgress: number = connectActionHandEdge().edge === 'left' ? 1 : 0;
  @Local readWidth: number = 0;
  @Local favoriteWidth: number = 0;
  @Local layoutReady: boolean = false;
  @Local shouldAnimate: boolean = false;
  @Local moving: boolean = false;
  private movementRevision: number = 0;

  @Monitor('actionEdge.edge')
  private moveToEdge(): void {
    const target: number = this.actionEdge.edge === 'left' ? 1 : 0
    this.shouldAnimate = this.layoutReady
    this.movementRevision++
    this.moving = this.shouldAnimate
    this.edgeProgress = target
  }

  @Monitor('usesHdsMaterial')
  private resetMeasurements(): void {
    this.edgeProgress = this.actionEdge.edge === 'left' ? 1 : 0
    this.readWidth = 0
    this.favoriteWidth = 0
    this.layoutReady = false
    this.shouldAnimate = false
    this.movementRevision++
    this.moving = false
  }

  @Monitor('availableWidth')
  private updateLayoutReady(): void {
    this.layoutReady = this.availableWidth > 0 && this.readWidth > 0 && this.favoriteWidth > 0
  }

  private activityInset(): number {
    return this.usesHdsMaterial ? ThemeConstants.SPACE_LG : 0
  }

  private railInset(): number {
    return this.usesHdsMaterial ? 0 : ThemeConstants.SPACE_LG
  }

  private outerHeight(): number {
    return ThemeConstants.BUTTON_HEIGHT + this.activityInset() * 2
  }

  private groupX(): number {
    const inner: number = this.availableWidth - this.railInset() * 2
    const width: number = this.readWidth + this.favoriteWidth + ThemeConstants.SPACE_SM -
      this.activityInset() * 2
    return Math.max(0, inner - width) * (1 - this.edgeProgress)
  }

  private readX(): number {
    return this.groupX() +
      (this.favoriteWidth - this.activityInset() * 2 + ThemeConstants.SPACE_SM) *
      (1 - this.edgeProgress)
  }

  private favoriteX(): number {
    return this.groupX() +
      (this.readWidth - this.activityInset() * 2 + ThemeConstants.SPACE_SM) * this.edgeProgress
  }

  private movementAnimation(): AnimateParam {
    const revision: number = this.movementRevision
    return {
      duration: this.shouldAnimate ? ThemeConstants.ANIM_DURATION : 0,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        if (this.movementRevision === revision) {
          this.moving = false
        }
      },
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() { this.readButtonContent() }
        .height(this.outerHeight())
        // Read covers Favorite only during the swap. At rest, its HDS activity
        // padding must not swallow the neighboring circle's edge taps.
        .zIndex(this.moving ? 1 : 0)
        .translate({ x: this.readX() })
        .animation(this.movementAnimation())
        .opacity(this.layoutReady ? 1 : 0)
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.readWidth = area.width as number
          this.updateLayoutReady()
        })
      Row() { this.favoriteButtonContent() }
        .height(this.outerHeight())
        .translate({ x: this.favoriteX() })
        .animation(this.movementAnimation())
        .opacity(this.layoutReady ? 1 : 0)
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.favoriteWidth = area.width as number
          this.updateLayoutReady()
        })
    }
    .width('100%')
    .height(this.outerHeight())
    .padding({ left: this.railInset(), right: this.railInset() })
    .hitTestBehavior(HitTestMode.Transparent)
    .clip(false)
    .position({ left: 0, bottom: this.railInset() })
  }
}

/** The related action strip follows the same edge, with its own scroll and layout state. */
@ComponentV2
export struct GalleryActionStripRail {
  @BuilderParam content: () => void
  @Local actionEdge: ActionHandEdgeState = connectActionHandEdge();
  @Local viewportWidth: number = 0;
  @Local contentWidth: number = 0;
  @Local layoutReady: boolean = false;
  @Local shouldAnimate: boolean = false;
  private scroller: Scroller = new Scroller();

  @Monitor('actionEdge.edge')
  private onEdgeChanged(): void {
    this.shouldAnimate = this.layoutReady
    this.scrollToEdge()
  }

  private visualX(): number {
    if (this.actionEdge.edge === 'left' || this.contentWidth >= this.viewportWidth) {
      return 0
    }
    return Math.max(0, this.viewportWidth - this.contentWidth)
  }

  private railMinWidth(): Length {
    return this.viewportWidth > 0 ? this.viewportWidth : '100%'
  }

  private updateLayoutReady(): void {
    this.layoutReady = this.viewportWidth > 0 && this.contentWidth > 0
  }

  private scrollToEdge(): void {
    try {
      this.scroller.scrollEdge(this.actionEdge.edge === 'left' ? Edge.Start : Edge.End)
    } catch (_error) {
    }
  }

  build() {
    Scroll(this.scroller) {
      Row() {
        Row({ space: ThemeConstants.SPACE_XS }) {
          this.content()
        }
        .alignItems(VerticalAlign.Center)
        .translate({ x: this.visualX() })
        .animation({ duration: this.shouldAnimate ? ThemeConstants.ANIM_DURATION : 0, curve: Curve.EaseOut })
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.contentWidth = area.width as number
          this.updateLayoutReady()
        })
      }
      // Keep overflow scrollable while short strips align to the selected hand edge.
      .constraintSize({ minWidth: this.railMinWidth() })
      .justifyContent(FlexAlign.Start)
    }
    .scrollable(ScrollDirection.Horizontal)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_ONLY,
      scrollBackward: NestedScrollMode.SELF_ONLY,
    })
    .scrollBar(BarState.Off)
    .width('100%')
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.viewportWidth = area.width as number
      this.updateLayoutReady()
    })
    .onAppear(() => { this.scrollToEdge() })
  }
}
