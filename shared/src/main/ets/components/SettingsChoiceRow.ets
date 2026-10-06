import { ConciseListRow } from './ConciseListRow'
import { SettingsCheckedMenuItem } from './SettingsCheckedMenuItem'

export interface SettingsChoiceOption {
  value: string;
  label: ResourceStr;
}

/** A single choice owns both the row label and native menu checks. */
@ComponentV2
export struct SettingsChoiceRow {
  @Require @Param title: ResourceStr;
  @Require @Param value: string;
  @Require @Param options: SettingsChoiceOption[];
  @Param accessibilityId: string = '';
  @Event selectAction?: (value: string) => void;

  private valueLabel(): ResourceStr {
    const option = this.options.find((item: SettingsChoiceOption): boolean => item.value === this.value)
    return option?.label ?? ''
  }

  @Builder
  private ChoiceMenu(select: (action: () => void) => void) {
    Menu() {
      ForEach(this.options, (option: SettingsChoiceOption) => {
        SettingsCheckedMenuItem({
          label: option.label,
          selected: option.value === this.value,
          selectAction: (): void => {
            select((): void => this.selectAction?.(option.value))
          },
        })
      }, (option: SettingsChoiceOption): string => option.value)
    }
  }

  build() {
    ConciseListRow({
      title: this.title,
      trailingText: this.valueLabel(),
      trailingDropdown: true,
      dropdownMenuEnabled: true,
      dropdownMenuBuilder: (select: (action: () => void) => void): void => {
        this.ChoiceMenu(select)
      },
    })
    .id(this.accessibilityId)
  }
}
