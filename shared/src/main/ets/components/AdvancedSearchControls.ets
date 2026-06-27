import { ThemeConstants } from '../theme/ThemeConstants'
import { AppStrings } from '../i18n/AppStrings'
import { SearchFilterState } from '../state/SearchFilterState'
import { ConciseListRow } from './ConciseListRow'
import { SettingsCheckedMenuItem } from './SettingsCheckedMenuItem'

const RATINGS: number[] = [0, 2, 3, 4, 5]
const PAGE_INPUT_WIDTH: number = 84
const PAGE_INPUT_HEIGHT: number = 36

/** One min-rating choice for the dropdown. */
class RatingOption {
  value: number
  label: string

  constructor(value: number, label: string) {
    this.value = value
    this.label = label
  }
}

/**
 * EH advanced-search controls: the master 高级选项 switch, and — when on — min-rating, page range, and the
 * five eros_fe toggles (torrent / expunged / disable language|uploader|tag filters). Built ENTIRELY from the
 * app-standard ConciseListRow (switch rows, a dropdown row, a row with an input suffix) + rowDivider, so row
 * height, padding, left-alignment and switch styling all match every other settings list by construction —
 * no hand-rolled spacing. Reads/writes the SearchFilterState advanced fields; shared by the search filter
 * sheet and the custom-tab editor. `onChanged` lets the host react.
 */
@ComponentV2
export struct AdvancedSearchControls {
  @Param filter: SearchFilterState = new SearchFilterState();
  @Event onChanged?: () => void;
  @Local private ratingMenuShown: boolean = false;

  private changed(): void {
    if (this.onChanged) {
      this.onChanged()
    }
  }

  private ratingLabel(): string {
    return this.filter.minRating > 0 ? `${this.filter.minRating}★` : AppStrings.get('filter_any')
  }

  private ratingOptions(): RatingOption[] {
    return RATINGS.map((r: number) => new RatingOption(r, r > 0 ? `${r}★` : AppStrings.get('filter_any')))
  }

  private setRating(value: number): void {
    if (this.filter.minRating !== value) {
      this.filter.minRating = value
      this.changed()
    }
  }

  private setPagesFrom(value: number): void {
    if (this.filter.pagesFrom !== value) {
      this.filter.pagesFrom = value
      this.changed()
    }
  }

  private setPagesTo(value: number): void {
    if (this.filter.pagesTo !== value) {
      this.filter.pagesTo = value
      this.changed()
    }
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    Column() {
      ConciseListRow({
        title: $r('app.string.filter_advanced'),
        hasSwitch: true,
        checked: this.filter.advancedEnabled,
        switchAction: (value: boolean) => {
          if (this.filter.advancedEnabled !== value) {
            this.filter.advancedEnabled = value
            this.changed()
          }
        },
      })
      if (this.filter.advancedEnabled) {
        this.rowDivider()
        Column() {
          ConciseListRow({
            title: $r('app.string.filter_rating'),
            trailingText: this.ratingLabel(),
            trailingDropdown: true,
            action: () => {
              this.ratingMenuShown = true
            },
          })
        }
        .bindMenu(this.ratingMenuShown, this.RatingMenu, {
          placement: Placement.BottomRight,
          onDisappear: () => {
            this.ratingMenuShown = false
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_pages'),
          showChevron: false,
          suffixPaddingRight: ThemeConstants.SPACE_MD,
          suffixBuilderParam: () => {
            this.PageSuffix()
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_require_torrent'),
          hasSwitch: true,
          checked: this.filter.requireTorrent,
          switchAction: (value: boolean) => {
            this.filter.requireTorrent = value
            this.changed()
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_show_expunged'),
          hasSwitch: true,
          checked: this.filter.showExpunged,
          switchAction: (value: boolean) => {
            this.filter.showExpunged = value
            this.changed()
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_disable_lang'),
          hasSwitch: true,
          checked: this.filter.disableLanguageFilter,
          switchAction: (value: boolean) => {
            this.filter.disableLanguageFilter = value
            this.changed()
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_disable_uploader'),
          hasSwitch: true,
          checked: this.filter.disableUploaderFilter,
          switchAction: (value: boolean) => {
            this.filter.disableUploaderFilter = value
            this.changed()
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.filter_disable_tag'),
          hasSwitch: true,
          checked: this.filter.disableTagFilter,
          switchAction: (value: boolean) => {
            this.filter.disableTagFilter = value
            this.changed()
          },
        })
      }
    }
    .width('100%')
  }

  @Builder
  private RatingMenu() {
    Menu() {
      ForEach(
        this.ratingOptions(),
        (opt: RatingOption) => {
          SettingsCheckedMenuItem({
            label: opt.label,
            selected: opt.value === this.filter.minRating,
            selectAction: () => {
              this.setRating(opt.value)
              this.ratingMenuShown = false
            },
          })
        },
        (opt: RatingOption) => `${opt.value}`,
      )
    }
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private PageSuffix() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      this.PageInput(this.filter.pagesFrom, (v: number) => {
        this.setPagesFrom(v)
      })
      Text('-')
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_tertiary'))
      this.PageInput(this.filter.pagesTo, (v: number) => {
        this.setPagesTo(v)
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private PageInput(value: number, onChange: (v: number) => void) {
    TextInput({ text: value > 0 ? `${value}` : '', placeholder: $r('app.string.filter_any') })
      .type(InputType.Number)
      .textAlign(TextAlign.Center)
      .width(PAGE_INPUT_WIDTH)
      .height(PAGE_INPUT_HEIGHT)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .borderRadius(ThemeConstants.RADIUS_MD)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_primary'))
      .placeholderColor($r('sys.color.font_tertiary'))
      .onChange((v: string) => {
        const n: number = Number.parseInt(v, 10)
        onChange(Number.isNaN(n) ? 0 : n)
      })
  }
}
