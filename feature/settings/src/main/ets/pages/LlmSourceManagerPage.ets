import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL,
  LLM_SOURCE_TYPE_OPENAI_COMPATIBLE,
  LlmSourceProfile,
  LlmSourceProfileRepository,
  LlmSourceProfilesState,
  SecondaryListScaffold,
  ThemeConstants,
  connectLlmSourceProfiles,
  connectNavStack,
  generateLlmSourceProfileId,
  immersiveTitleBar,
} from 'shared'

export class LlmSourceDetailRouteParams {
  sourceProfileId: string = ''
}

@ComponentV2
export struct LlmSourceManagerPage {
  @Local private sources: LlmSourceProfilesState = connectLlmSourceProfiles();
  @Local private addMenuShown: boolean = false;
  @Local private creating: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private sourceTypeText(profile: LlmSourceProfile): ResourceStr {
    return profile.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
      ? $r('app.string.llm_source_type_codex')
      : $r('app.string.llm_source_type_api')
  }

  private referenceCount(sourceProfileId: string): number {
    let count: number = 0
    if (this.sources.commentBinding.sourceProfileId === sourceProfileId) {
      count++
    }
    if (this.sources.mangaBinding.sourceProfileId === sourceProfileId) {
      count++
    }
    return count
  }

  private openSource(sourceProfileId: string): void {
    const params: LlmSourceDetailRouteParams = new LlmSourceDetailRouteParams()
    params.sourceProfileId = sourceProfileId
    this.stack.pushPathByName('LlmSourceDetail', params)
  }

  private createSource(sourceType: string): void {
    if (this.creating) {
      return
    }
    this.addMenuShown = false
    this.creating = true
    const profile: LlmSourceProfile = new LlmSourceProfile()
    profile.sourceProfileId = generateLlmSourceProfileId()
    profile.sourceType = sourceType
    if (sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL) {
      profile.displayName = AppStrings.get('llm_source_type_codex')
      profile.capabilities.responses = true
      profile.capabilities.imageInput = true
      profile.capabilities.modelCatalog = true
      profile.capabilities.usage = true
    } else {
      profile.displayName = AppStrings.get('llm_source_type_api')
      profile.baseUrl = 'https://api.openai.com'
      profile.capabilities.chatCompletions = true
      profile.capabilities.responses = true
      profile.capabilities.imageInput = true
      profile.capabilities.modelCatalog = true
    }
    LlmSourceProfileRepository.upsert(this.ctx(), profile)
      .then(() => {
        this.openSource(profile.sourceProfileId)
      })
      .catch((error: Error) => {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.llm_source_create_failed', error.message),
        })
      })
      .finally(() => {
        this.creating = false
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
  private AddSourceMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.llm_source_type_api'),
      }).onClick(() => {
        this.createSource(LLM_SOURCE_TYPE_OPENAI_COMPATIBLE)
      })
      MenuItem({
        content: $r('app.string.llm_source_type_codex'),
      }).onClick(() => {
        this.createSource(LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL)
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
            if (this.sources.profiles.length === 0) {
              ConciseListRow({
                title: $r('app.string.llm_sources_empty'),
                subtitle: $r('app.string.llm_sources_empty_hint'),
                leadingIcon: $r('sys.symbol.cloud'),
                showChevron: false,
              })
            } else {
              ForEach(
                this.sources.profiles,
                (profile: LlmSourceProfile, index: number) => {
                  if (index > 0) {
                    this.rowDivider()
                  }
                  ConciseListRow({
                    title: profile.displayName,
                    subtitle: this.sourceTypeText(profile),
                    leadingIcon: profile.sourceType === LLM_SOURCE_TYPE_CODEX_OAUTH_EXPERIMENTAL
                      ? $r('sys.symbol.person')
                      : $r('sys.symbol.cloud'),
                    trailingText: this.referenceCount(profile.sourceProfileId) > 0
                      ? `${this.referenceCount(profile.sourceProfileId)}`
                      : '',
                    action: () => {
                      this.openSource(profile.sourceProfileId)
                    },
                  })
                },
                (profile: LlmSourceProfile) => profile.sourceProfileId,
              )
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            Column() {
              ConciseListRow({
                title: $r('app.string.llm_source_add'),
                subtitle: $r('app.string.llm_source_add_hint'),
                leadingIcon: $r('sys.symbol.plus'),
                trailingDropdown: true,
                isEnabled: !this.creating,
                action: () => {
                  this.addMenuShown = true
                },
              })
            }
            .bindMenu(this.addMenuShown, this.AddSourceMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.addMenuShown = false
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('llm_sources_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
