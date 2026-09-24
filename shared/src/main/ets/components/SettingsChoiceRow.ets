import { ConciseListRow } from './ConciseListRow'
import { SettingsCheckedMenuItem } from './SettingsCheckedMenuItem'

export class SettingsChoiceOption {
  readonly value: string
  readonly label: ResourceStr

  constructor(value: string, label: ResourceStr) {
    this.value = value
    this.label = label
  }
}

/** One selected value owns both the row summary and native menu checkmarks. */
@ComponentV2
export struct SettingsChoiceRow {
  @Require @Param title: ResourceStr
  @Require @Param value: string
  @Require @Param options: SettingsChoiceOption[]
  @Event onSelect: (value: string) => void = (): void => {}

  private selectedLabel(): ResourceStr {
    return this.options.find((option: SettingsChoiceOption): boolean => option.value === this.value)?.label ?? ''
  }

  @Builder
  private ChoiceMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(this.options, (option: SettingsChoiceOption) => {
        SettingsCheckedMenuItem({
          label: option.label,
          selected: option.value === this.value,
          selectAction: (): void => {
            select((): void => this.onSelect(option.value))
          },
        })
      }, (option: SettingsChoiceOption): string => option.value)
    }
  }

  build() {
    ConciseListRow({
      title: this.title,
      trailingText: this.selectedLabel(),
      trailingDropdown: true,
      dropdownMenuEnabled: true,
      dropdownMenuBuilder: (select: (action: () => void) => void): void => {
        this.ChoiceMenu(select)
      },
    })
  }
}
