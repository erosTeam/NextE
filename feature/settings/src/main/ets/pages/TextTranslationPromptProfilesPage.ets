import { common } from '@kit.AbilityKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
 GroupedListSection,
 SecondaryListScaffold,
  SectionHeader,
 TextTranslationPromptCatalog,
  TextTranslationPromptProfile,
  TextTranslationPromptProfilesState,
  ThemeConstants,
  ListRowDivider,
  connectTextTranslationPromptProfiles,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'
import { TextTranslationPromptProfileDetailParams } from './TextTranslationPromptProfileDetailPage'

/**
 * Selects the shared AI-translation prompt profile. Built-ins render read-only (tap opens the
 * read-only detail); custom entries and the "new" row open the editable detail. Selection and
 * creation publish only through the repository, so a failed write keeps the old selection and
 * state mirror. The page stays reachable regardless of the comment-translation and Google-only
 * settings, because the profile only takes effect on the AI (LLM) path.
 */
@ComponentV2
export struct TextTranslationPromptProfilesPage {
  @Local private profiles: TextTranslationPromptProfilesState =
    connectTextTranslationPromptProfiles();
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private profileDisplayName(promptProfileId: string): string {
    return this.profiles.findById(promptProfileId)?.displayName ?? ''
  }

  private openDetail(promptProfileId: string): void {
    const params: TextTranslationPromptProfileDetailParams = new TextTranslationPromptProfileDetailParams()
    params.promptProfileId = promptProfileId
    this.stack.pushPathByName('TextTranslationPromptProfileDetail', params)
  }

  private openNewCustom(): void {
    const params: TextTranslationPromptProfileDetailParams = new TextTranslationPromptProfileDetailParams()
    this.stack.pushPathByName('TextTranslationPromptProfileDetail', params)
  }

  @Builder
  private CheckSuffix(profile: TextTranslationPromptProfile) {
    if (this.profiles.selectedPromptProfileId === profile.promptProfileId) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(ThemeConstants.SYMBOL_SIZE_CONTROL)
        .fontColor([ThemeConstants.BRAND_PRIMARY])
        .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
    }
  }

  @Builder
  private ProfileRow(profile: TextTranslationPromptProfile) {
    ConciseListRow({
      title: this.profileDisplayName(profile.promptProfileId),
      leadingIcon: $r('sys.symbol.textformat'),
      showChevron: false,
      suffixPaddingRight: 0,
      suffixBuilderParam: () => {
        this.CheckSuffix(profile)
      },
      action: () => {
        this.openDetail(profile.promptProfileId)
      },
    })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
       ListItem() {
          SectionHeader({ title: $r('app.string.text_translation_prompt_builtin_group') })
        }
        .margin({ top: ThemeConstants.SPACE_XS })
        ListItem() {
          GroupedListSection() {
            ForEach(
              TextTranslationPromptCatalog.builtInProfiles(),
              (profile: TextTranslationPromptProfile, index: number) => {
                if (index > 0) {
                  ListRowDivider()
                }
                this.ProfileRow(profile)
              },
              (profile: TextTranslationPromptProfile) => profile.promptProfileId,
            )
          }
        }
        if (this.profiles.customProfiles.length > 0) {
          ListItem() {
            SectionHeader({ title: $r('app.string.text_translation_prompt_custom_group') })
          }
          .margin({ top: ThemeConstants.SPACE_MD })
          ListItem() {
            GroupedListSection() {
              ForEach(
                this.profiles.customProfiles,
                (profile: TextTranslationPromptProfile, index: number) => {
                  if (index > 0) {
                    ListRowDivider()
                  }
                  this.ProfileRow(profile.copy())
                },
                (profile: TextTranslationPromptProfile) => profile.promptProfileId,
              )
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.text_translation_prompt_new'),
              leadingIcon: $r('sys.symbol.plus'),
              showChevron: true,
              action: () => {
                this.openNewCustom()
              },
            })
          }
        }
        .margin({ top: ThemeConstants.SPACE_MD })
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('text_translation_prompt_profiles_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
