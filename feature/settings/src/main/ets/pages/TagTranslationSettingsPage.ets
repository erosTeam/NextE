import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  TAG_TRANSLATION_UPDATE_EVERY_START,
  TAG_TRANSLATION_UPDATE_MANUAL,
  TagTranslationSettings,
  TagTranslationSettingsState,
  ThemeConstants,
  connectTagTranslationSettings,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct TagTranslationSettingsPage {
  @Local tagSettings: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local updating: boolean = false;
  @Local modeMenuShown: boolean = false;
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
    this.modeMenuShown = false
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

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private UpdateModeMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.tag_translation_update_manual'),
        symbolEndIcon: this.tagSettings.updateMode === TAG_TRANSLATION_UPDATE_MANUAL
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setUpdateMode(TAG_TRANSLATION_UPDATE_MANUAL)
      })
      MenuItem({
        content: $r('app.string.tag_translation_update_every_start'),
        symbolEndIcon: this.tagSettings.updateMode === TAG_TRANSLATION_UPDATE_EVERY_START
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      }).onClick(() => {
        this.setUpdateMode(TAG_TRANSLATION_UPDATE_EVERY_START)
      })
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
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
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_database'),
              subtitle: this.versionText(),
              leadingIcon: $r('sys.symbol.externaldrive'),
              trailingText: this.statusText(),
              showChevron: false,
            })
            this.rowDivider()
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
            this.rowDivider()
            Column() {
              ConciseListRow({
                title: $r('app.string.tag_translation_update_mode'),
                leadingIcon: $r('sys.symbol.clock'),
                trailingText: this.updateModeText(),
                trailingDropdown: true,
                action: () => {
                  this.modeMenuShown = true
                },
              })
            }
            .bindMenu(this.modeMenuShown, this.UpdateModeMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.modeMenuShown = false
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
