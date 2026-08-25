import { common } from '@kit.AbilityKit'
import { FrameCallback } from '@kit.ArkUI'
import {
  ThemeConstants,
  EhGalleryImage,
  EhSpriteThumbnail,
  PreviewThumbTile,
  GroupedListSection,
  ListMode,
  ListModeSettings,
  ListModeState,
  connectListMode,
  clampColumnWidth,
  galleryWaterfallColumnCount,
  connectReaderThumbnailTransition,
  ReaderThumbnailTransitionCoordinator,
  ReaderThumbnailTransitionState,
  EhConstants,
  ImagePipelineService,
  EH_IMAGE_PRIORITY_LOW,
  GalleryDetailTransitionPhase,
  GalleryDetailTransitionState,
  connectGalleryDetailTransition,
} from 'shared'

// Horizontal-mode row thumb height (eros_fe ThumbHorizontalList ~200 incl. labels): each thumb keeps
// its true aspect at this height so its width varies with no white-border padding.
const PREVIEW_H: number = 150
const PREVIEW_RENDER_BATCH_SIZE: number = 3

class GalleryPreviewRenderFrameCallback extends FrameCallback {
  private action: () => void

  constructor(action: () => void) {
    super()
    this.action = action
  }

  onFrame(_frameTimeInNano: number): void {}

  onIdle(_timeLeftInNano: number): void {
    this.action()
  }
}

/**
 * Detail-page preview section — eros_fe ThumbTile + GalleryBody dispatch, restored to its three modes
 * driven by the two thumbnail settings the parent passes in (both default false → GRID):
 *   - hidden=true     → NO inline previews; the tappable "查看全部 >" header AND a centered "more previews"
 *                       button both open all-thumbnails (eros_fe hidden-inline MorePreviewButton).
 *   - horizontal=true → a tappable "预览 (n) 查看全部 >" header that opens all-thumbnails, over a horizontal
 *                       scrolling row of fixed-height thumbs (eros_fe ThumbHorizontalList).
 *   - else (GRID)     → the SAME tappable "查看全部 >" header + an inline wrap-grid peek of the first preview
 *                       page + a centered "更多预览/没有更多预览" button below (eros_fe ThumbSliverGrid + MorePreviewButton).
 * The all-thumbnails page is reachable via the header in EVERY mode (and the button in grid/hidden);
 * onOpen(page0) opens the reader.
 */
@ComponentV2
export struct GalleryPreviewGrid {
  @Require @Param images: EhGalleryImage[];
  @Param total: number = 0;
  @Param hasMore: boolean = false;
  @Param horizontal: boolean = false;
  @Param hidden: boolean = false;
  @Param thumbnailReloadToken: number = 0;
  @Param transitionScope: string = '';
  @Local listMode: ListModeState = connectListMode();
  @Local readerTransition: ReaderThumbnailTransitionState = connectReaderThumbnailTransition();
  @Local galleryDetailTransition: GalleryDetailTransitionState = connectGalleryDetailTransition();
  @Local measuredWidth: number = 0;
  // Keep one visible row in the initial tree so a cached detail never paints an empty preview card.
  // Only the remaining tiles wait for the transition boundary and idle-frame batching.
  @Local renderedImageCount: number = PREVIEW_RENDER_BATCH_SIZE;
  @Event onOpen: (image: EhGalleryImage) => void = (_image: EhGalleryImage) => {};
  @Event onMore: (initialImagePage: number) => void = (_initialImagePage: number) => {};
  private pinchStartW: number = 0;
  private pinchStartCols: number = 0;
  private pinchCommitted: boolean = false;
  private preloadedSpriteUrls: string[] = [];
  private renderBatchScheduled: boolean = false;
  private renderBatchEpoch: number = 0;

  aboutToAppear(): void {
    this.preloadSpriteSheets()
    this.scheduleNextRenderBatch()
  }

  aboutToDisappear(): void {
    this.renderBatchEpoch += 1
    this.renderBatchScheduled = false
  }

  @Monitor('images')
  onPreviewImagesChanged(): void {
    this.preloadSpriteSheets()
    this.scheduleNextRenderBatch()
  }

  @Monitor('hidden')
  onPreviewVisibilityChanged(): void {
    this.preloadSpriteSheets()
    this.scheduleNextRenderBatch()
  }

  @Monitor('galleryDetailTransition.phase')
  onGalleryDetailTransitionPhaseChanged(): void {
    this.scheduleNextRenderBatch()
  }

  private preloadSpriteSheets(): void {
    if (this.hidden) {
      return
    }
    // One preview page can contain many tiles backed by only a few sprite sheets. Warm each unique
    // sheet asynchronously while the detail transition runs; the tile nodes mount after Navigation
    // settles and reuse ImageKnife's memory/file cache instead of all decoding on the transition frame.
    this.images.forEach((image: EhGalleryImage) => {
      const url: string = EhConstants.cdnThumb(image.thumbUrl)
      if (url.length === 0 || this.preloadedSpriteUrls.includes(url)) {
        return
      }
      this.preloadedSpriteUrls.push(url)
      ImagePipelineService.preloadCover(url, EH_IMAGE_PRIORITY_LOW)
    })
  }

  private transitionAllowsTileRendering(): boolean {
    if (!this.galleryDetailTransition.eligible) {
      return true
    }
    return this.galleryDetailTransition.phase !== GalleryDetailTransitionPhase.PREPARING &&
      this.galleryDetailTransition.phase !== GalleryDetailTransitionPhase.OPENING
  }

  private scheduleNextRenderBatch(): void {
    if (
      this.hidden ||
      !this.transitionAllowsTileRendering() ||
      this.renderBatchScheduled ||
      this.renderedImageCount >= this.images.length
    ) {
      return
    }
    this.renderBatchScheduled = true
    const epoch: number = this.renderBatchEpoch
    this.getUIContext().postFrameCallback(new GalleryPreviewRenderFrameCallback((): void => {
      if (epoch !== this.renderBatchEpoch) {
        return
      }
      this.renderBatchScheduled = false
      if (!this.transitionAllowsTileRendering()) {
        return
      }
      this.renderedImageCount = Math.min(
        this.images.length,
        this.renderedImageCount + PREVIEW_RENDER_BATCH_SIZE,
      )
      this.scheduleNextRenderBatch()
    }))
  }

  private renderedImages(): EhGalleryImage[] {
    const out: EhGalleryImage[] = []
    const count: number = Math.min(this.renderedImageCount, this.images.length)
    for (let i: number = 0; i < count; i++) {
      out.push(this.images[i])
    }
    return out
  }

  private lastImagePage(): number {
    if (this.images.length === 0) {
      return 0
    }
    return this.images[this.images.length - 1].page
  }

  private horizontalThumbWidth(image: EhGalleryImage): number {
    if (image.thumbWidth > 0 && image.thumbHeight > 0) {
      return PREVIEW_H * image.thumbWidth / image.thumbHeight
    }
    return PREVIEW_H * 0.7
  }

  private transitionSourceId(image: EhGalleryImage): string {
    return ReaderThumbnailTransitionCoordinator.sourceId(this.transitionScope, image.page - 1)
  }

  // Centered tappable entry into the all-thumbnails page (eros_fe MorePreviewButton). The label reflects
  // whether more pages remain, but the row always navigates.
  @Builder
  moreButton(initialImagePage: number) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(
        this.hasMore
          ? $r('app.string.detail_more_previews')
          : $r('app.string.detail_no_more_previews'),
      )
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_emphasize'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: ThemeConstants.SPACE_MD, bottom: ThemeConstants.SPACE_SM })
    .onClick(() => {
      this.onMore(initialImagePage)
    })
  }

  // Section header. `entry` = this header IS an all-thumbnails entry: show the visible "查看全部 >"
  // affordance and make the whole row tappable (→ onMore). All three modes pass entry=true so the header
  // is always a real, affordanced entry (no invisible tap target); GRID/HIDDEN also keep the button below.
  @Builder
  sectionHeader(entry: boolean) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text($r('app.string.gallery_preview'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(`(${this.total > 0 ? this.total : this.images.length})`)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Blank()
      if (entry) {
        Text($r('app.string.detail_view_all'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_emphasize'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (entry) {
        this.onMore(0)
      }
    })
  }

  // Horizontal scrolling row of fixed-height thumbs (each keeps true aspect).
  @Builder
  horizontalRow() {
    List({ space: ThemeConstants.SPACE_SM }) {
      ForEach(
        this.renderedImages(),
        (img: EhGalleryImage) => {
          ListItem() {
            Column({ space: 2 }) {
              Stack({ alignContent: Alignment.Center }) {
                Stack({ alignContent: Alignment.Center }) {
                  EhSpriteThumbnail({
                    url: img.thumbUrl,
                    thumbWidth: img.thumbWidth,
                    thumbHeight: img.thumbHeight,
                    offsetX: img.thumbOffsetX,
                    imageKey: img.imgkey,
                    spriteWidth: img.spriteWidth,
                    spriteHeight: img.spriteHeight,
                    fitHeight: true,
                    displayHeight: PREVIEW_H,
                    loadDuringDetailPush: true,
                    enableImageBlock: true,
                    reloadToken: this.thumbnailReloadToken,
                  })
                }
                .id(this.transitionSourceId(img))
                .width(this.horizontalThumbWidth(img))
                .height(PREVIEW_H)
                .borderRadius(ThemeConstants.THUMB_RADIUS)
                .clip(true)
                .visibility(
                  this.readerTransition.sourceHidden(this.transitionSourceId(img))
                    ? Visibility.Hidden
                    : Visibility.Visible,
                )
              }
              .width(this.horizontalThumbWidth(img))
              .height(PREVIEW_H)
              Text(`${img.page}`)
                .fontSize(ThemeConstants.FONT_SIZE_TINY)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onOpen(img)
            })
          }
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .listDirection(Axis.Horizontal)
    .height(PREVIEW_H + 22)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  // Inline grid peek of the first preview page. Responsive column count via columnsTemplate (a true Grid,
  // not a wrapping Flex) so tiles align in columns with uniform gap and the last row left-aligns naturally.
  private columnsTemplate(): string {
    return `repeat(auto-fit, ${this.effectiveMinWidth()}vp)`
  }

  private effectiveMinWidth(): number {
    const override: number = this.listMode.overrideWidthFor(ListMode.THUMBNAIL_GRID)
    return override > 0 ? override : ThemeConstants.PREVIEW_THUMB_MIN_W
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private currentColumns(): number {
    return galleryWaterfallColumnCount(
      this.measuredWidth,
      this.effectiveMinWidth(),
      ThemeConstants.SPACE_SM,
      0,
    )
  }

  private applyPinch(scale: number): void {
    if (this.pinchCommitted || this.measuredWidth <= 0) {
      return
    }
    const next: number = clampColumnWidth(this.pinchStartW * scale)
    this.listMode.setWidthFor(ListMode.THUMBNAIL_GRID, next)
    const cols: number = galleryWaterfallColumnCount(
      this.measuredWidth,
      next,
      ThemeConstants.SPACE_SM,
      0,
    )
    if (cols !== this.pinchStartCols) {
      this.pinchCommitted = true
      this.getUIContext()
        .getPromptAction()
        .showToast({
          message:
            cols > this.pinchStartCols
              ? $r('app.string.column_density_more')
              : $r('app.string.column_density_fewer'),
          duration: 800,
        })
    }
  }

  @Builder
  gridPeek() {
    Grid() {
      ForEach(
        this.renderedImages(),
        (img: EhGalleryImage) => {
          GridItem() {
            PreviewThumbTile({
              image: img,
              reloadToken: this.thumbnailReloadToken,
              loadDuringDetailPush: true,
              transitionSourceId: this.transitionSourceId(img),
              onTap: () => {
                this.onOpen(img)
              },
            })
          }
        },
        (img: EhGalleryImage) => `${img.page}`,
      )
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(ThemeConstants.SPACE_SM)
    .rowsGap(ThemeConstants.SPACE_SM)
    .width('100%')
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart(() => {
          this.pinchStartW = this.effectiveMinWidth()
          this.pinchStartCols = this.currentColumns()
          this.pinchCommitted = false
        })
        .onActionUpdate((event: GestureEvent) => {
          this.applyPinch(event.scale)
        })
        .onActionEnd(() => {
          ListModeSettings.setColumnWidth(this.ctx(), ListMode.THUMBNAIL_GRID, this.effectiveMinWidth())
          this.pinchCommitted = false
        }),
    )
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const parsed: number = Number.parseFloat(`${newValue.width}`)
      this.measuredWidth = parsed > 0 ? parsed : 0
    })
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        if (this.hidden) {
          // Hidden-inline: no previews — the tappable header AND the button below both open all-thumbnails
          // (eros_fe hideGalleryThumbnails still offers a MorePreviewButton).
          this.sectionHeader(true)
          this.moreButton(0)
        } else if (this.horizontal) {
          this.sectionHeader(true)
          this.horizontalRow()
        } else {
          // Default GRID: tappable header entry + inline first-page peek + the button below.
          this.sectionHeader(true)
          this.gridPeek()
          this.moreButton(this.lastImagePage())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
