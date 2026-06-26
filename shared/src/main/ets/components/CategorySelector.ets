import { ThemeConstants } from '../theme/ThemeConstants'
import { EhConstants } from '../constants/EhConstants'
import { SearchFilterState } from '../state/SearchFilterState'

/** One EH category and its f_cats bit. */
interface CatItem {
  name: string
  bit: number
}

const ALL_CATS: number = 1023
const CATS: CatItem[] = [
  { name: 'Misc', bit: 1 },
  { name: 'Doujinshi', bit: 2 },
  { name: 'Manga', bit: 4 },
  { name: 'Artist CG', bit: 8 },
  { name: 'Game CG', bit: 16 },
  { name: 'Western', bit: 512 },
  { name: 'Non-H', bit: 256 },
  { name: 'Image Set', bit: 32 },
  { name: 'Cosplay', bit: 64 },
  { name: 'Asian Porn', bit: 128 },
]
const CAT_ROWS: CatItem[][] = [
  [CATS[0], CATS[1]],
  [CATS[2], CATS[3]],
  [CATS[4], CATS[5]],
  [CATS[6], CATS[7]],
  [CATS[8], CATS[9]],
]

/**
 * EH category include-filter grid (5×2 colored toggles). Reads/writes `filter.selectedCats` (INCLUDE
 * bitmask; 0 = all). Tap toggles a category; long-press solos it (or inverts if it's the only one).
 * Extracted from SearchFilterSheet so the search sheet AND the custom-tab editor share one grid.
 * `onChanged` lets the host react (the search sheet bumps applySeq; the editor passes nothing).
 */
@ComponentV2
export struct CategorySelector {
  @Param filter: SearchFilterState = new SearchFilterState();
  @Event onChanged?: () => void;

  private visibleCatMask(): number {
    return this.filter.selectedCats === 0 ? ALL_CATS : this.filter.selectedCats
  }

  private normalizeCats(cats: number): number {
    return cats === ALL_CATS ? 0 : cats
  }

  private isCatSelected(c: CatItem): boolean {
    return (this.visibleCatMask() & c.bit) !== 0
  }

  private toggleCategory(c: CatItem): void {
    const next: number = this.visibleCatMask() ^ c.bit
    this.filter.selectedCats = this.normalizeCats(next)
    if (this.onChanged) {
      this.onChanged()
    }
  }

  private soloOrInvertCategory(c: CatItem): void {
    const current: number = this.visibleCatMask()
    const selected: boolean = (current & c.bit) !== 0
    this.filter.selectedCats = selected ? c.bit : this.normalizeCats(ALL_CATS ^ c.bit)
    if (this.onChanged) {
      this.onChanged()
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      ForEach(
        CAT_ROWS,
        (row: CatItem[]) => {
          Row({ space: ThemeConstants.SPACE_XS }) {
            ForEach(
              row,
              (c: CatItem) => {
                CategoryButton({
                  label: c.name,
                  selected: this.isCatSelected(c),
                  color: EhConstants.categoryColor(c.name),
                  onTap: () => {
                    this.toggleCategory(c)
                  },
                  onLongPress: () => {
                    this.soloOrInvertCategory(c)
                  },
                })
                  .layoutWeight(1)
              },
              (c: CatItem) => c.name,
            )
          }
          .width('100%')
        },
        (row: CatItem[]) => row[0].name,
      )
    }
    .width('100%')
  }
}

@ComponentV2
struct CategoryButton {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param color: ResourceColor = ThemeConstants.BRAND_PRIMARY;
  @Event onTap: () => void = () => {};
  @Event onLongPress: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected ? ThemeConstants.TEXT_ON_BRAND : $r('sys.color.font_primary'))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height(42)
      .width('100%')
      .backgroundColor(this.selected ? this.color : $r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(ThemeConstants.RADIUS_MD)
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
      })
      .onClick(() => {
        this.onTap()
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            this.onLongPress()
          }),
      )
  }
}
