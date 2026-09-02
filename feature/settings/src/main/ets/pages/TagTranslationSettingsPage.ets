import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  SettingsCheckedMenuItem,
  TAG_INTRO_IMAGE_DISABLE,
  TAG_INTRO_IMAGE_NON_H,
  TAG_INTRO_IMAGE_R18,
  TAG_INTRO_IMAGE_R18G,
  TAG_TRANSLATION_UPDATE_EVERY_START,
  TAG_TRANSLATION_UPDATE_MANUAL,
  TagTranslationSettings,
  TagTranslationService,
  TagTranslationSettingsState,
  ThemeConstants,
  ListRowDivider,
  connectTagTranslationSettings,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct TagTranslationSettingsPage {
  @Local tagSettings: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local updating: boolean = false;
  @Local removing: boolean = false;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private statusText(): string {
    if (this.updating) {
      return AppStrings.get('tag_translation_updating')
    }
    if (this.tagSettings.rowCount <= 0) {
      return AppStrings.get('tag_translation_not_installed')
    }
    return `${this.tagSettings.rowCount}`
  }

  private versionText(): string {
    return this.tagSettings.version.length > 0
      ? this.tagSettings.version
      : AppStrings.get('tag_translation_no_version')
  }

  private updateModeText(): Resource {
    return this.tagSettings.updateMode === TAG_TRANSLATION_UPDATE_EVERY_START
      ? $r('app.string.tag_translation_update_every_start')
      : $r('app.string.tag_translation_update_manual')
  }

  private introImageLevelText(): Resource {
    switch (this.tagSettings.introImageLevel) {
      case TAG_INTRO_IMAGE_DISABLE:
        return $r('app.string.tag_translation_intro_image_disable')
      case TAG_INTRO_IMAGE_R18:
        return $r('app.string.tag_translation_intro_image_r18')
      case TAG_INTRO_IMAGE_R18G:
        return $r('app.string.tag_translation_intro_image_r18g')
      default:
        return $r('app.string.tag_translation_intro_image_nonh')
    }
  }

  private setEnabled(value: boolean): void {
    TagTranslationSettings.setEnabled(this.ctx(), value).then(() => {
      if (value && this.tagSettings.rowCount <= 0) {
        this.updateNow()
      }
    })
  }

  private setUseCdn(value: boolean): void {
    TagTranslationSettings.setUseCdn(this.ctx(), value)
  }

  private setUpdateMode(mode: string): void {
    TagTranslationSettings.setUpdateMode(this.ctx(), mode)
  }

  private setIntroImageLevel(level: string): void {
    TagTranslationSettings.setIntroImageLevel(this.ctx(), level)
  }

  private updateNow(): void {
    if (this.updating) {
      return
    }
    this.updating = true
    this.getUIContext().getPromptAction().showToast({
      message: $r('app.string.tag_translation_update_started'),
    })
    TagTranslationSettings.updateNow(this.ctx())
      .then((count: number) => {
        this.getUIContext().getPromptAction().showToast({
          message: `${AppStrings.get('tag_translation_update_finished')} ${count}`,
        })
      })
      .catch((error: Error) => {
        this.getUIContext().getPromptAction().showToast({
          message: `${AppStrings.get('tag_translation_update_failed')}: ${error.message}`,
        })
      })
      .finally(() => {
        this.updating = false
      })
  }

  private removeDatabase(): void {
    if (this.updating || this.removing) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tag_translation_remove_confirm_title'),
      message: $r('app.string.tag_translation_remove_confirm_message'),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.common_remove'),
        fontColor: Color.Red,
        action: () => {
          this.confirmRemoveDatabase()
        },
      },
    })
  }

  private confirmRemoveDatabase(): void {
    if (this.updating || this.removing) {
      return
    }
    this.removing = true
    TagTranslationService.clearTranslations(this.ctx())
      .then(() => {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.tag_translation_remove_done'),
        })
        TagTranslationSettings.refreshStatus(this.ctx())
      })
      .catch((error: Error) => {
        this.getUIContext().getPromptAction().showToast({
          message: `${AppStrings.get('tag_translation_remove_failed')}: ${error.message}`,
        })
      })
      .finally(() => {
        this.removing = false
      })
  }

  @Builder
  private UpdateModeMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_update_manual'),
        selected: this.tagSettings.updateMode === TAG_TRANSLATION_UPDATE_MANUAL,
        selectAction: () => {
          select(() => {
            this.setUpdateMode(TAG_TRANSLATION_UPDATE_MANUAL)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_update_every_start'),
        selected: this.tagSettings.updateMode === TAG_TRANSLATION_UPDATE_EVERY_START,
        selectAction: () => {
          select(() => {
            this.setUpdateMode(TAG_TRANSLATION_UPDATE_EVERY_START)
          })
        },
      })
    }
  }

  @Builder
  private IntroImageMenu(select: (action: () => void) => void) {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_intro_image_disable'),
        selected: this.tagSettings.introImageLevel === TAG_INTRO_IMAGE_DISABLE,
        selectAction: () => {
          select(() => {
            this.setIntroImageLevel(TAG_INTRO_IMAGE_DISABLE)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_intro_image_nonh'),
        selected: this.tagSettings.introImageLevel === TAG_INTRO_IMAGE_NON_H,
        selectAction: () => {
          select(() => {
            this.setIntroImageLevel(TAG_INTRO_IMAGE_NON_H)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_intro_image_r18'),
        selected: this.tagSettings.introImageLevel === TAG_INTRO_IMAGE_R18,
        selectAction: () => {
          select(() => {
            this.setIntroImageLevel(TAG_INTRO_IMAGE_R18)
          })
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_translation_intro_image_r18g'),
        selected: this.tagSettings.introImageLevel === TAG_INTRO_IMAGE_R18G,
        selectAction: () => {
          select(() => {
            this.setIntroImageLevel(TAG_INTRO_IMAGE_R18G)
          })
        },
      })
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.tag_translation_enable'),
              subtitle: $r('app.string.tag_translation_enable_hint'),
              leadingIcon: $r('sys.symbol.textformat'),
              hasSwitch: true,
              checked: this.tagSettings.enabled,
              switchAction: (value: boolean) => {
                this.setEnabled(value)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_database'),
              subtitle: this.versionText(),
              leadingIcon: $r('sys.symbol.externaldrive'),
              trailingText: this.statusText(),
              showChevron: false,
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_update_now'),
              subtitle: $r('app.string.tag_translation_update_now_hint'),
              leadingIcon: $r('sys.symbol.arrow_clockwise'),
              trailingText: this.updating ? $r('app.string.tag_translation_updating') : '',
              showChevron: false,
              isEnabled: !this.updating,
              action: () => {
                this.updateNow()
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_remove'),
              subtitle: $r('app.string.tag_translation_remove_hint'),
              leadingIcon: $r('sys.symbol.trash'),
              destructive: true,
              showChevron: false,
              isEnabled: !this.updating && !this.removing,
              action: () => {
                this.removeDatabase()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.tag_translation_cdn'),
              subtitle: $r('app.string.tag_translation_cdn_hint'),
              leadingIcon: $r('sys.symbol.cloud'),
              hasSwitch: true,
              checked: this.tagSettings.useCdn,
              switchAction: (value: boolean) => {
                this.setUseCdn(value)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_update_mode'),
              leadingIcon: $r('sys.symbol.clock'),
              trailingText: this.updateModeText(),
              trailingDropdown: true,
              dropdownMenuEnabled: true,
              dropdownMenuBuilder: (select: (action: () => void) => void) => {
                this.UpdateModeMenu(select)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_intro_image_level'),
              subtitle: $r('app.string.tag_translation_intro_image_level_hint'),
              leadingIcon: $r('sys.symbol.textformat'),
              trailingText: this.introImageLevelText(),
              trailingDropdown: true,
              dropdownMenuEnabled: true,
              dropdownMenuBuilder: (select: (action: () => void) => void) => {
                this.IntroImageMenu(select)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('tag_translation_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady(() => {
      TagTranslationSettings.refreshStatus(this.ctx())
    })
  }
}
