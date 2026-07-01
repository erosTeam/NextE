import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  SecondaryListScaffold,
  ThemeConstants,
  ListMode,
  ListModeState,
  ListModeSettings,
  connectListMode,
  immersiveTitleBar,
  clampColumnWidth,
  galleryWaterfallColumnCount,
} from 'shared'
import { common } from '@kit.AbilityKit'

/**
 * Dedicated grid-density page. The preview is full-bleed (the only horizontal inset is the gallery
 * list's own GALLERY_GRID_GAP) so its measured width equals the real list width — the column count it
 * shows is exactly what the gallery list renders. The slider is in COLUMN-COUNT units (intuitive, and
 * its default sits mid-range), but the stored value is a width so the count stays foldable-adaptive.
 */
@ComponentV2
export struct ColumnDensityPage {
  @Param targetMode: string = '';
  @Local listMode: ListModeState = connectListMode()
  @Local previewWidth: number = 0
  private scroller: Scroller = new Scroller()
  private previewCells: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private effectiveMode(): string {
    return this.targetMode.length > 0 ? this.targetMode : this.listMode.mode
  }

  private baseColumnWidth(): number {
    const mode: string = this.effectiveMode()
    if (mode === ListMode.GRID) {
      return ThemeConstants.GALLERY_GRID_MIN_W
    }
    if (mode === ListMode.WATERFALL) {
      return ThemeConstants.GALLERY_WATERFALL_MIN_W
    }
    if (mode === ListMode.THUMBNAIL_GRID) {
      return ThemeConstants.PREVIEW_THUMB_MIN_W
    }
    return ThemeConstants.GALLERY_COVER_WALL_MIN_W
  }

  private effectiveColumnWidth(): number {
    const override: number = this.listMode.overrideWidthFor(this.effectiveMode())
    return override > 0 ? override : this.baseColumnWidth()
  }

  private previewGap(): number {
    return this.effectiveMode() === ListMode.THUMBNAIL_GRID
      ? ThemeConstants.SPACE_SM
      : ThemeConstants.GALLERY_GRID_GAP
  }

  private previewHorizontalPadding(): number {
    return this.effectiveMode() === ListMode.THUMBNAIL_GRID
      ? ThemeConstants.SPACE_MD
      : ThemeConstants.GALLERY_GRID_GAP
  }

  private titleText(): string {
    return this.effectiveMode() === ListMode.THUMBNAIL_GRID
      ? AppStrings.get('settings_thumbnail_column_width')
      : AppStrings.get('settings_column_width')
  }

  private hintText(): ResourceStr {
    return this.effectiveMode() === ListMode.THUMBNAIL_GRID
      ? $r('app.string.settings_thumbnail_column_width_hint')
      : $r('app.string.settings_column_width_hint')
  }

  // Preview uses the same gap/padding family as the target grid so the visible density matches the
  // surface being configured.
  private currentColumns(): number {
    return galleryWaterfallColumnCount(
      this.previewWidth,
      this.effectiveColumnWidth(),
      this.previewGap(),
      this.previewHorizontalPadding(),
    )
  }

  private previewTemplate(): string {
    const count: number = this.currentColumns()
    const parts: string[] = []
    for (let i = 0; i < count; i++) {
      parts.push('1fr')
    }
    return parts.join(' ')
  }

  @Builder
  Preview() {
    Column() {
      if (this.effectiveMode() === ListMode.GRID || this.effectiveMode() === ListMode.THUMBNAIL_GRID) {
        Grid() {
          ForEach(
            this.previewCells,
            (cell: number) => {
              GridItem() {
                Column()
                  .width('100%')
                  .aspectRatio(0.72)
                  .borderRadius(ThemeConstants.GALLERY_GRID_CARD_RADIUS)
                  .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
              }
            },
            (cell: number) => cell.toString(),
          )
        }
        .columnsTemplate(this.previewTemplate())
        .columnsGap(this.previewGap())
        .rowsGap(this.previewGap())
        .enableScrollInteraction(false)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      } else {
        WaterFlow() {
          ForEach(
            this.previewCells,
            (cell: number) => {
              FlowItem() {
                Column()
                  .width('100%')
                  .aspectRatio(cell % 3 === 0 ? 0.6 : cell % 3 === 1 ? 0.85 : 0.72)
                  .borderRadius(ThemeConstants.RADIUS_CARD)
                  .backgroundColor(ThemeConstants.COVER_PLACEHOLDER)
              }
              .width('100%')
            },
            (cell: number) => cell.toString(),
          )
        }
        .columnsTemplate(this.previewTemplate())
        .columnsGap(this.previewGap())
        .rowsGap(this.previewGap())
        .enableScrollInteraction(false)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
    }
    // Full-bleed: only the list's own gap as inset, measured width == real gallery list width.
    .width('100%')
    .height(220)
    .padding({
      left: this.previewHorizontalPadding(),
      right: this.previewHorizontalPadding(),
    })
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const parsed: number = Number.parseFloat(`${newValue.width}`)
      this.previewWidth = parsed > 0 ? parsed : 0
    })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        horizontalPadding: 0,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          Column({ space: ThemeConstants.SPACE_MD }) {
            this.Preview()
            Column({ space: ThemeConstants.SPACE_SM }) {
              Text(this.hintText())
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')

              // Width slider (vp). Bigger width = bigger cards = fewer per row. Column count is never set.
              Slider({
                value: this.effectiveColumnWidth(),
                min: ThemeConstants.GALLERY_COL_MIN_W_FLOOR,
                max: ThemeConstants.GALLERY_COL_MIN_W_CEIL,
                step: 1,
                style: SliderStyle.InSet,
              })
                .width('100%')
                .selectedColor(ThemeConstants.BRAND_PRIMARY)
                .onChange((value: number, mode: SliderChangeMode) => {
                  const width: number = clampColumnWidth(value)
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    ListModeSettings.setColumnWidth(this.ctx(), this.effectiveMode(), width)
                  } else {
                    this.listMode.setWidthFor(this.effectiveMode(), width)
                  }
                })
            }
            .width('100%')
            .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
          }
          .width('100%')
        }
      }
    }
    .titleBar(immersiveTitleBar(this.titleText()))
  }
}
