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
  @Local listMode: ListModeState = connectListMode()
  @Local previewWidth: number = 0
  private scroller: Scroller = new Scroller()
  private previewCells: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private baseColumnWidth(): number {
    if (this.listMode.mode === ListMode.GRID) {
      return ThemeConstants.GALLERY_GRID_MIN_W
    }
    if (this.listMode.mode === ListMode.WATERFALL) {
      return ThemeConstants.GALLERY_WATERFALL_MIN_W
    }
    return ThemeConstants.GALLERY_COVER_WALL_MIN_W
  }

  private effectiveColumnWidth(): number {
    const override: number = this.listMode.overrideWidthFor(this.listMode.mode)
    return override > 0 ? override : this.baseColumnWidth()
  }

  // gap == horizontalPadding == GALLERY_GRID_GAP here, matching the gallery list scaffolds exactly.
  private currentColumns(): number {
    return galleryWaterfallColumnCount(
      this.previewWidth,
      this.effectiveColumnWidth(),
      ThemeConstants.GALLERY_GRID_GAP,
      ThemeConstants.GALLERY_GRID_GAP,
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
      if (this.listMode.mode === ListMode.GRID) {
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
        .columnsGap(ThemeConstants.GALLERY_GRID_GAP)
        .rowsGap(ThemeConstants.GALLERY_GRID_GAP)
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
        .columnsGap(ThemeConstants.GALLERY_GRID_GAP)
        .rowsGap(ThemeConstants.GALLERY_GRID_GAP)
        .enableScrollInteraction(false)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
      }
    }
    // Full-bleed: only the list's own gap as inset, measured width == real gallery list width.
    .width('100%')
    .height(220)
    .padding({ left: ThemeConstants.GALLERY_GRID_GAP, right: ThemeConstants.GALLERY_GRID_GAP })
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
              Text($r('app.string.settings_column_width_hint'))
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
                    ListModeSettings.setColumnWidth(this.ctx(), this.listMode.mode, width)
                  } else {
                    this.listMode.setWidthFor(this.listMode.mode, width)
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
    .titleBar(immersiveTitleBar(AppStrings.get('settings_column_width')))
  }
}
