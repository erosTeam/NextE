import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import { AppStrings } from '../i18n/AppStrings'
import { AppColorFavoritesSettings } from '../settings/AppColorFavoritesSettings'
import { AppColorFavoritesState, connectAppColorFavorites } from '../state/AppColorFavoritesState'
import { ThemeConstants } from '../theme/ThemeConstants'

const COLOR_PICKER_MODE_GRID: number = 0
const COLOR_PICKER_MODE_SLIDERS: number = 1
const COLOR_PICKER_GRID_HUES: number[] = [190, 210, 235, 270, 315, 355, 25, 38, 50, 75, 125, 180]
const COLOR_PICKER_GRID_ROWS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
const COLOR_FAVORITE_SLOTS: number[] = [
  0, 1, 2, 3, 4, 5, 6, 7, 8,
  9, 10, 11, 12, 13, 14, 15, 16, 17,
  18, 19, 20, 21, 22, 23, 24, 25, 26,
  27, 28, 29, 30, 31, 32, 33, 34, 35,
]
const COLOR_FAVORITE_ADD_ICON_SIZE: number = 20
const FAVORITE_SELECTION_STROKE: number = 3

@ComponentV2
export struct AppColorPicker {
  @Param title: ResourceStr = ''
  @Param color: string = ''
  @Param disabled: boolean = false
  @Event colorChange?: (color: string) => void
  @Local private mode: number = COLOR_PICKER_MODE_GRID
  @Local private modeItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }]);
  @Local private draftHue: number = 210;
  @Local private draftSaturation: number = 80;
  @Local private draftBrightness: number = 100;
  @Local private draftHex: string = '#3377FF';
  @Local private lastEmittedColor: string = '';
  @Local private shrinkingFavoriteIndex: number = -1;
  @Local private colorFavorites: AppColorFavoritesState = connectAppColorFavorites();

  aboutToAppear(): void {
    this.syncModeLabels()
    this.syncDraftFromExternalColor()
  }

  @Monitor('color')
  onExternalColorChange(): void {
    const incoming: string = this.normalizedColorFor(this.color)
    if (incoming.length > 0 && incoming.toUpperCase() === this.lastEmittedColor.toUpperCase()) {
      return
    }
    if (incoming.length > 0 && incoming.toUpperCase() === this.draftColor().toUpperCase()) {
      return
    }
    this.syncDraftFromExternalColor()
  }

  build() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Row({ space: ThemeConstants.SPACE_MD }) {
        Text(this.title)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.draftColor())
          .borderWidth(1)
          .borderColor($r('sys.color.ohos_id_color_list_separator'))
      }
      .width('100%')

      TabSegmentButtonV2({
        items: this.modeItems,
        selectedIndex: this.mode,
        enableStateAnimation: true,
        onItemClicked: (index: number) => {
          this.mode = index
        },
        itemPadding: {
          top: LengthMetrics.vp(6),
          bottom: LengthMetrics.vp(6),
          start: LengthMetrics.vp(8),
          end: LengthMetrics.vp(8),
        },
      })
        .width('100%')

      if (this.mode === COLOR_PICKER_MODE_GRID) {
        this.ColorGrid()
      } else {
        this.HsbSliders()
      }

      Row({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.color_picker_hex'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
        TextInput({ text: this.draftHex, placeholder: '#3377FF' })
          .layoutWeight(1)
          .height(44)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .enabled(!this.disabled)
          .onChange((value: string) => {
            this.handleHexInput(value)
          })
      }
      .width('100%')

      this.ColorFavorites()
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private ColorGrid() {
    Grid() {
      ForEach(
        COLOR_PICKER_GRID_ROWS,
        (row: number) => {
          GridItem() {
            this.ColorCell(this.grayForGridRow(row))
          }
          ForEach(
            COLOR_PICKER_GRID_HUES,
            (hue: number) => {
              GridItem() {
                this.ColorCell(this.hsbToHex(hue, this.saturationForGridRow(row), this.brightnessForGridRow(row)))
              }
            },
            (hue: number) => `color_${row}_${hue}`,
          )
        },
        (row: number) => `${row}`,
      )
    }
    .columnsTemplate('repeat(13, 1fr)')
    .rowsTemplate('repeat(10, 1fr)')
    .rowsGap(0)
    .columnsGap(0)
    .width('100%')
    .aspectRatio(13 / 10)
    .clip(true)
  }

  @Builder
  private ColorCell(color: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        // ponytail: fractional Grid tracks can expose 1px seams; overlap cells, switch to Canvas only if ArkUI still leaks.
        .width('102%')
        .height('102%')
        .backgroundColor(color)
      if (this.isCurrentColor(color)) {
        Column()
          .width(24)
          .height(24)
          .borderRadius(6)
          .borderWidth(3)
          .borderColor(Color.White)
          .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .enabled(!this.disabled)
    .onClick(() => {
      if (!this.disabled) {
        this.selectColor(color)
      }
    })
  }

  @Builder
  private ColorFavorites() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      Text($r('app.string.color_picker_favorites'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      Grid() {
        ForEach(
          COLOR_FAVORITE_SLOTS,
          (index: number) => {
            GridItem() {
              this.FavoriteCell(index)
            }
          },
          (index: number) => `${index}`,
        )
      }
      .columnsTemplate('repeat(9, 1fr)')
      .rowsTemplate('repeat(4, 1fr)')
      .rowsGap(8)
      .columnsGap(8)
      .width('100%')
      .aspectRatio(9 / 4)
    }
    .width('100%')
  }

  @Builder
  private FavoriteCell(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (index < this.colorFavorites.colors.length) {
        Column() {
          Column()
            .width('100%')
            .aspectRatio(1)
            .borderRadius(this.favoriteColorBlockRadius(index))
            .backgroundColor(this.colorFavorites.colors[index])
            .borderWidth(this.favoriteColorBorderWidth(index))
            .borderColor($r('sys.color.ohos_id_color_list_separator'))
        }
        .width('100%')
        .aspectRatio(1)
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
        .padding(this.favoriteSelectionGap(index))
        .borderWidth(this.favoriteSelectionBorderWidth(index))
        .borderColor(ThemeConstants.BRAND_PRIMARY)
      } else if (index === this.colorFavorites.colors.length) {
        Column()
          .width('100%')
          .aspectRatio(1)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .borderWidth(1)
          .borderColor($r('sys.color.ohos_id_color_list_separator'))
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(COLOR_FAVORITE_ADD_ICON_SIZE)
          .fontColor([$r('sys.color.font_secondary')])
      } else {
        Column()
          .width('100%')
          .aspectRatio(1)
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
          .borderWidth(1)
          .borderColor($r('sys.color.ohos_id_color_list_separator'))
      }
    }
    .width('100%')
    .height('100%')
    .enabled(!this.disabled)
    .onClick(() => {
      if (this.disabled) {
        return
      }
      if (index < this.colorFavorites.colors.length) {
        this.selectFavoriteColor(index)
      } else if (index === this.colorFavorites.colors.length) {
        this.addFavoriteColor()
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          if (!this.disabled && index < this.colorFavorites.colors.length) {
            this.removeFavoriteColor(index)
          }
        }),
    )
  }

  @Builder
  private HsbSliders() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      this.HueSlider()
      this.SaturationSlider()
      this.BrightnessSlider()
    }
    .width('100%')
  }

  @Builder
  private HueSlider() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Row({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.color_picker_hue'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(`${Math.round(this.draftHue)}`)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      Slider({ value: this.draftHue, min: 0, max: 360, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .enabled(!this.disabled)
        .trackColor(this.hueGradient())
        .selectedColor(Color.Transparent)
        .onChange((v: number, mode: SliderChangeMode) => {
          this.draftHue = v
          this.commitDraftColor()
        })
    }
    .width('100%')
  }

  @Builder
  private SaturationSlider() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Row({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.color_picker_saturation'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(`${Math.round(this.draftSaturation)}`)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      Slider({ value: this.draftSaturation, min: 0, max: 100, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .enabled(!this.disabled)
        .trackColor(this.saturationGradient())
        .selectedColor(Color.Transparent)
        .onChange((v: number, mode: SliderChangeMode) => {
          this.draftSaturation = v
          this.commitDraftColor()
        })
    }
    .width('100%')
  }

  @Builder
  private BrightnessSlider() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Row({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.color_picker_brightness'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(`${Math.round(this.draftBrightness)}`)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      Slider({ value: this.draftBrightness, min: 0, max: 100, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .enabled(!this.disabled)
        .trackColor(this.brightnessGradient())
        .selectedColor(Color.Transparent)
        .onChange((v: number, mode: SliderChangeMode) => {
          this.draftBrightness = v
          this.commitDraftColor()
        })
    }
    .width('100%')
  }

  private syncModeLabels(): void {
    this.modeItems[0].text = AppStrings.get('color_picker_grid')
    this.modeItems[1].text = AppStrings.get('color_picker_sliders')
  }

  private emitColor(color: string): void {
    this.lastEmittedColor = this.normalizedColorFor(color)
    if (this.colorChange) {
      this.colorChange(color)
    }
  }

  private commitDraftColor(): void {
    const color: string = this.draftColor()
    this.draftHex = color
    this.emitColor(color)
  }

  private selectColor(color: string): void {
    const normalized: string = this.normalizedColorFor(color)
    if (normalized.length > 0) {
      this.syncDraftFromHex(normalized)
      this.draftHex = normalized
      this.emitColor(normalized)
    }
  }

  private selectFavoriteColor(index: number): void {
    const color: string = this.colorFavorites.colors[index]
    if (this.isCurrentColor(color)) {
      return
    }
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.shrinkingFavoriteIndex = index
    })
    setTimeout(() => {
      if (this.shrinkingFavoriteIndex === index) {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
          this.shrinkingFavoriteIndex = -1
          this.selectColor(color)
        })
      }
    }, 130)
  }

  private favoriteSelectionBorderWidth(index: number): number {
    return this.isCurrentColor(this.colorFavorites.colors[index]) ? FAVORITE_SELECTION_STROKE : 0
  }

  private favoriteSelectionGap(index: number): number {
    return this.isCurrentColor(this.colorFavorites.colors[index]) || this.shrinkingFavoriteIndex === index ?
    FAVORITE_SELECTION_STROKE : 0
  }

  private favoriteColorBlockRadius(index: number): number {
    return this.isCurrentColor(this.colorFavorites.colors[index]) || this.shrinkingFavoriteIndex === index ? 4 : 8
  }

  private favoriteColorBorderWidth(index: number): number {
    return this.isCurrentColor(this.colorFavorites.colors[index]) || this.shrinkingFavoriteIndex === index ? 0 : 1
  }

  private addFavoriteColor(): void {
    const color: string = this.draftColor()
    const next: string[] = []
    let exists: boolean = false
    this.colorFavorites.colors.forEach((c: string) => {
      if (c.toUpperCase() === color.toUpperCase()) {
        exists = true
      }
      if (next.length < COLOR_FAVORITE_SLOTS.length) {
        next.push(c)
      }
    })
    if (!exists && next.length < COLOR_FAVORITE_SLOTS.length) {
      next.push(color)
    }
    this.colorFavorites.colors = next
    this.persistFavorites(next)
  }

  private removeFavoriteColor(index: number): void {
    const next: string[] = []
    this.colorFavorites.colors.forEach((c: string, i: number) => {
      if (i !== index && next.length < COLOR_FAVORITE_SLOTS.length) {
        next.push(c)
      }
    })
    this.colorFavorites.colors = next
    this.persistFavorites(next)
  }

  private persistFavorites(colors: string[]): void {
    AppColorFavoritesSettings.persist(this.ctx(), colors)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private handleHexInput(value: string): void {
    if (value === this.draftHex) {
      return
    }
    this.draftHex = value
    const normalized: string = this.normalizedStrictHexFor(value)
    if (normalized.length === 0) {
      return
    }
    this.syncDraftFromHex(normalized)
    this.draftHex = normalized
    this.emitColor(normalized)
  }

  private normalizedColorFor(color: string): string {
    const c: string = color.trim()
    if (c.length === 0) {
      return ''
    }
    const normalized: string = c.startsWith('#') ? c : `#${c}`
    const digits: string = this.hexDigitsFor(normalized)
    return digits.length === 6 ? `#${digits}` : ''
  }

  private normalizedStrictHexFor(color: string): string {
    let c: string = color.trim()
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length !== 6) {
      return ''
    }
    return this.isHex(c) ? `#${c.toUpperCase()}` : ''
  }

  private isCurrentColor(color: string): boolean {
    const current: string = this.normalizedColorFor(this.draftHex)
    const target: string = this.normalizedColorFor(color)
    if (current.length > 0 && target.length > 0) {
      return current.toUpperCase() === target.toUpperCase()
    }
    return this.draftColor().toUpperCase() === target.toUpperCase()
  }

  private hexDigitsFor(color: string): string {
    let c: string = color.trim()
    if (c.startsWith('#')) {
      c = c.substring(1)
    }
    if (c.length === 3) {
      c = `${c.substring(0, 1)}${c.substring(0, 1)}${c.substring(1, 2)}${c.substring(1, 2)}${c.substring(2, 3)}${c.substring(2, 3)}`
    }
    if (c.length !== 6 || !this.isHex(c)) {
      return ''
    }
    return c.toUpperCase()
  }

  private isHex(value: string): boolean {
    for (let i: number = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i)
      const digit: boolean = code >= 48 && code <= 57
      const upper: boolean = code >= 65 && code <= 70
      const lower: boolean = code >= 97 && code <= 102
      if (!digit && !upper && !lower) {
        return false
      }
    }
    return true
  }

  private saturationForGridRow(row: number): number {
    if (row <= 0) {
      return 15
    }
    if (row === 1) {
      return 25
    }
    if (row === 2) {
      return 42
    }
    if (row === 3) {
      return 60
    }
    if (row === 4) {
      return 80
    }
    return 100
  }

  private brightnessForGridRow(row: number): number {
    if (row <= 5) {
      return 100
    }
    if (row === 6) {
      return 90
    }
    if (row === 7) {
      return 78
    }
    if (row === 8) {
      return 66
    }
    return 54
  }

  private grayForGridRow(row: number): string {
    let brightness: number = 10
    if (row <= 0) {
      brightness = 95
    } else if (row === 1) {
      brightness = 90
    } else if (row === 2) {
      brightness = 85
    } else if (row === 3) {
      brightness = 80
    } else if (row === 4) {
      brightness = 70
    } else if (row === 5) {
      brightness = 60
    } else if (row === 6) {
      brightness = 50
    } else if (row === 7) {
      brightness = 30
    } else if (row === 8) {
      brightness = 20
    }
    const v: number = Math.round(brightness / 100 * 255)
    return `#${this.byteToHex(v)}${this.byteToHex(v)}${this.byteToHex(v)}`
  }

  private hueGradient(): LinearGradient {
    return new LinearGradient([
      { color: this.hsbToHex(0, 100, 100), offset: 0 },
      { color: this.hsbToHex(60, 100, 100), offset: 0.17 },
      { color: this.hsbToHex(120, 100, 100), offset: 0.33 },
      { color: this.hsbToHex(180, 100, 100), offset: 0.5 },
      { color: this.hsbToHex(240, 100, 100), offset: 0.67 },
      { color: this.hsbToHex(300, 100, 100), offset: 0.83 },
      { color: this.hsbToHex(360, 100, 100), offset: 1 },
    ])
  }

  private saturationGradient(): LinearGradient {
    return new LinearGradient([
      { color: this.hsbToHex(this.draftHue, 0, this.draftBrightness), offset: 0 },
      { color: this.hsbToHex(this.draftHue, 100, this.draftBrightness), offset: 1 },
    ])
  }

  private brightnessGradient(): LinearGradient {
    return new LinearGradient([
      { color: this.hsbToHex(this.draftHue, this.draftSaturation, 0), offset: 0 },
      { color: this.hsbToHex(this.draftHue, this.draftSaturation, 100), offset: 1 },
    ])
  }

  private syncDraftFromExternalColor(): void {
    const normalized: string = this.normalizedColorFor(this.color)
    if (normalized.length > 0) {
      this.syncDraftFromHex(normalized)
      this.draftHex = normalized
    }
  }

  private syncDraftFromHex(color: string): void {
    const digits: string = this.hexDigitsFor(color)
    if (digits.length !== 6) {
      return
    }
    const c0: number = Number.parseInt(digits.substring(0, 2), 16) / 255
    const c1: number = Number.parseInt(digits.substring(2, 4), 16) / 255
    const c2: number = Number.parseInt(digits.substring(4, 6), 16) / 255
    const max: number = Math.max(c0, Math.max(c1, c2))
    const min: number = Math.min(c0, Math.min(c1, c2))
    const delta: number = max - min
    if (delta > 0) {
      let hue: number = 0
      if (max === c0) {
        hue = 60 * ((c1 - c2) / delta)
      } else if (max === c1) {
        hue = 60 * (((c2 - c0) / delta) + 2)
      } else {
        hue = 60 * (((c0 - c1) / delta) + 4)
      }
      this.draftHue = hue < 0 ? hue + 360 : hue
      this.draftSaturation = ((max - min) / max) * 100
    } else {
      this.draftSaturation = 0
    }
    this.draftBrightness = max * 100
  }

  private draftColor(): string {
    return this.hsbToHex(this.draftHue, this.draftSaturation, this.draftBrightness)
  }

  private hsbToHex(hue: number, saturation: number, brightness: number): string {
    const h: number = ((hue % 360) + 360) % 360
    const s: number = Math.max(0, Math.min(100, saturation)) / 100
    const v: number = Math.max(0, Math.min(100, brightness)) / 100
    const chroma: number = v * s
    const x: number = chroma * (1 - Math.abs(((h / 60) % 2) - 1))
    const m: number = v - chroma
    let c0: number = 0
    let c1: number = 0
    let c2: number = 0
    if (h < 60) {
      c0 = chroma
      c1 = x
    } else if (h < 120) {
      c0 = x
      c1 = chroma
    } else if (h < 180) {
      c1 = chroma
      c2 = x
    } else if (h < 240) {
      c1 = x
      c2 = chroma
    } else if (h < 300) {
      c0 = x
      c2 = chroma
    } else {
      c0 = chroma
      c2 = x
    }
    return `#${this.byteToHex((c0 + m) * 255)}${this.byteToHex((c1 + m) * 255)}${this.byteToHex((c2 + m) * 255)}`
  }

  private byteToHex(value: number): string {
    const digits: string = '0123456789ABCDEF'
    const v: number = Math.max(0, Math.min(255, Math.round(value)))
    const hi: number = Math.floor(v / 16)
    const lo: number = v - hi * 16
    return `${digits.substring(hi, hi + 1)}${digits.substring(lo, lo + 1)}`
  }
}
