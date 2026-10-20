import {
  ActionHandEdgeState,
  connectActionHandEdge,
  connectFabLayoutStyle,
  connectLayoutSafeArea,
  FabLayoutStyleSettings,
  FabLayoutStyleState,
  LayoutSafeAreaState,
  ThemeConstants,
} from 'shared'
import { GalleryActionFabRail } from './GalleryActionRail'
import { GalleryVerticalReadButton, VERTICAL_READ_WIDTH, verticalReadHeight } from './GalleryVerticalReadButton'

/** Measures the action viewport without publishing height or animation state into the detail page. */
@ComponentV2
export struct GalleryDetailActionRail {
  @Param usesHdsMaterial: boolean = true;
  @BuilderParam readButtonContent: () => void
  @BuilderParam favoriteButtonContent: () => void
  @Param readLabel: Resource = $r('app.string.detail_read');
  @Event onRead: () => void = () => {};
  @Local layoutStyle: FabLayoutStyleState = connectFabLayoutStyle();
  @Local layout: LayoutSafeAreaState = connectLayoutSafeArea();
  @Local paneWidth: number = 0;
  @Local paneHeight: number = 0;
  @Local paneY: number = 0;

  private topLimit(): number {
    return Math.max(0, this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT - this.paneY) +
      ThemeConstants.SPACE_MD
  }

  private bottomLimit(): number {
    const windowHeight: number = this.getUIContext().px2vp(this.layout.mainWindowHeightPx)
    const overlap: number = windowHeight > 0
      ? Math.max(0, this.paneY + this.paneHeight - (windowHeight - this.layout.bottomAvoidHeight))
      : this.layout.bottomAvoidHeight
    return this.paneHeight - overlap - ThemeConstants.SPACE_MD
  }

  private usesCenteredLayout(): boolean {
    return FabLayoutStyleSettings.isCentered(this.layoutStyle.style) &&
      this.bottomLimit() - this.topLimit() >=
        verticalReadHeight(this.getUIContext(), this.readLabel) + ThemeConstants.SPACE_SM +
          ThemeConstants.BUTTON_HEIGHT &&
      this.paneWidth >= VERTICAL_READ_WIDTH + ThemeConstants.SPACE_LG * 2
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.usesCenteredLayout()) {
        GalleryCenteredActionRail({
          availableWidth: this.paneWidth,
          topLimit: this.topLimit(),
          bottomLimit: this.bottomLimit(),
          usesHdsMaterial: this.usesHdsMaterial,
          readLabel: this.readLabel,
          onRead: () => { this.onRead() },
          favoriteButtonContent: () => { this.favoriteButtonContent() },
        })
      } else {
        GalleryActionFabRail({
          availableWidth: this.paneWidth,
          usesHdsMaterial: this.usesHdsMaterial,
          readButtonContent: () => { this.readButtonContent() },
          favoriteButtonContent: () => { this.favoriteButtonContent() },
        })
      }
    }
    .width('100%')
    .height('100%')
    .clip(this.usesCenteredLayout())
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_oldArea: Area, area: Area) => {
      this.paneWidth = area.width as number
      this.paneHeight = area.height as number
      this.paneY = area.globalPosition.y as number
    })
  }
}

/** Independent Read and Favorite buttons share only positioning and a queued offscreen flight. */
@ComponentV2
struct GalleryCenteredActionRail {
  @Param availableWidth: number = 0;
  @Param topLimit: number = 0;
  @Param bottomLimit: number = 0;
  @Param usesHdsMaterial: boolean = true;
  @Param readLabel: Resource = $r('app.string.detail_read');
  @Event onRead: () => void = () => {};
  @BuilderParam favoriteButtonContent: () => void
  @Local actionEdge: ActionHandEdgeState = connectActionHandEdge();
  @Local visibleEdge: string = connectActionHandEdge().edge;
  @Local flightOffset: number = 0;
  @Local readWidth: number = 0;
  @Local readHeight: number = 0;
  @Local favoriteWidth: number = 0;
  @Local favoriteHeight: number = 0;
  private moving: boolean = false;
  private revision: number = 0;
  private disposed: boolean = false;

  private activityInset(): number {
    return this.usesHdsMaterial ? ThemeConstants.SPACE_LG : 0
  }

  private groupWidth(): number {
    return Math.max(this.readWidth, this.favoriteWidth)
  }

  private favoriteTop(): number {
    return this.readHeight + ThemeConstants.SPACE_SM - this.activityInset() * 2
  }

  private groupHeight(): number {
    return this.favoriteTop() + this.favoriteHeight
  }

  private ready(): boolean {
    return this.readWidth > 0 && this.readHeight > 0 && this.favoriteWidth > 0 &&
      this.favoriteHeight > 0 && this.availableWidth > 0
  }

  private restX(edge: string): number {
    return edge === 'left'
      ? ThemeConstants.SPACE_LG - this.activityInset()
      : this.availableWidth - ThemeConstants.SPACE_LG - this.groupWidth() + this.activityInset()
  }

  private outsideX(edge: string): number {
    return edge === 'left' ? -this.groupWidth() - ThemeConstants.SPACE_LG
      : this.availableWidth + ThemeConstants.SPACE_LG
  }

  private top(): number {
    const visibleHeight: number = this.groupHeight() - this.activityInset() * 2
    const travel: number = Math.max(0, this.bottomLimit - this.topLimit - visibleHeight)
    return this.topLimit + travel * 2 / 3 - this.activityInset()
  }

  @Monitor('actionEdge.edge')
  private moveToEdge(): void {
    if (!this.ready()) {
      this.visibleEdge = this.actionEdge.edge
      return
    }
    if (!this.moving && this.visibleEdge !== this.actionEdge.edge) {
      this.exitEdge()
    }
  }

  @Monitor('availableWidth', 'topLimit', 'bottomLimit')
  private settleAfterResize(): void {
    this.revision++
    this.moving = false
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.visibleEdge = this.actionEdge.edge
      this.flightOffset = 0
    })
  }

  @Monitor('usesHdsMaterial')
  private remeasureMaterial(): void {
    this.readWidth = 0
    this.readHeight = 0
    this.favoriteWidth = 0
    this.favoriteHeight = 0
    this.settleAfterResize()
  }

  aboutToDisappear(): void {
    this.disposed = true
    this.revision++
  }

  private exitEdge(): void {
    const revision: number = ++this.revision
    this.moving = true
    this.getUIContext().animateTo({
      duration: ThemeConstants.ANIM_DURATION * 0.4,
      curve: Curve.EaseIn,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        if (this.disposed || this.revision !== revision) return
        // Both endpoints are fully outside the clipped viewport. The hop has no visible screen path.
        this.getUIContext().animateTo({ duration: 0 }, () => {
          this.visibleEdge = this.actionEdge.edge
          this.flightOffset = this.outsideX(this.visibleEdge) - this.restX(this.visibleEdge)
        })
        this.enterEdge(revision)
      },
    }, () => {
      this.flightOffset = this.outsideX(this.visibleEdge) - this.restX(this.visibleEdge)
    })
  }

  private enterEdge(revision: number): void {
    this.getUIContext().animateTo({
      duration: ThemeConstants.ANIM_DURATION * 0.6,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        if (this.disposed || this.revision !== revision) return
        this.moving = false
        this.moveToEdge()
      },
    }, () => { this.flightOffset = 0 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        GalleryVerticalReadButton({
          label: this.readLabel,
          usesHdsMaterial: this.usesHdsMaterial,
          action: () => { this.onRead() },
        })
      }
        .height(verticalReadHeight(this.getUIContext(), this.readLabel) + this.activityInset() * 2)
        .position({ x: (this.groupWidth() - this.readWidth) / 2, y: 0 })
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.readWidth = area.width as number
          this.readHeight = area.height as number
        })
      Row() { this.favoriteButtonContent() }
        .height(ThemeConstants.BUTTON_HEIGHT + this.activityInset() * 2)
        .position({ x: (this.groupWidth() - this.favoriteWidth) / 2, y: this.favoriteTop() })
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.favoriteWidth = area.width as number
          this.favoriteHeight = area.height as number
        })
    }
    .width(this.ready() ? this.groupWidth() : VERTICAL_READ_WIDTH + this.activityInset() * 2)
    .height(this.ready() ? this.groupHeight() : verticalReadHeight(this.getUIContext(), this.readLabel) + ThemeConstants.SPACE_SM +
      ThemeConstants.BUTTON_HEIGHT + this.activityInset() * 2)
    .translate({ x: this.restX(this.visibleEdge) + this.flightOffset, y: this.top() })
    .opacity(this.ready() ? 1 : 0)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
