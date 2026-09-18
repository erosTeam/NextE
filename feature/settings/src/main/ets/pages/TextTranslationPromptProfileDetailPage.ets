import { common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { util } from '@kit.ArkTS'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  DiagnosticLogger,
  GroupedListSection,
  MAX_TEXT_TRANSLATION_CUSTOM_PROFILES,
  MAX_TEXT_TRANSLATION_PROMPT_NAME_CHARS,
  MAX_TEXT_TRANSLATION_STYLE_CHARS,
  SecondaryListScaffold,
  SectionHeader,
  SettingsTextField,
  TextTranslationPromptContract,
  TextTranslationPromptProfile,
  TextTranslationPromptProfileRepository,
  TextTranslationPromptProfilesState,
  ThemeConstants,
  ListRowDivider,
  ConciseListRow,
  connectTextTranslationPromptProfiles,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'

export class TextTranslationPromptProfileDetailParams {
  promptProfileId: string = ''
}

@ComponentV2
export struct TextTranslationPromptProfileDetailPage {
  @Local private profiles: TextTranslationPromptProfilesState =
    connectTextTranslationPromptProfiles();
  @Local private promptProfileId: string = '';
  @Local private builtIn: boolean = false;
  @Local private sourceIsCustom: boolean = false;
  @Local private titleKey: string = 'text_translation_prompt_detail_custom';
  @Local private primaryLabelKey: string = 'llm_source_save';
  @Local private nameDraft: string = '';
  @Local private styleDraft: string = '';
  @Local private loaded: boolean = false;
  @Local private saving: boolean = false;
  @Local private deleting: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET)
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private async load(params: TextTranslationPromptProfileDetailParams): Promise<void> {
    const rawId: string = params.promptProfileId
    if (rawId.length === 0) {
      this.promptProfileId = ''
      this.builtIn = false
      this.sourceIsCustom = false
      this.titleKey = 'text_translation_prompt_detail_new'
      this.primaryLabelKey = 'text_translation_prompt_create'
      this.nameDraft = ''
      this.styleDraft = ''
      this.loaded = true
      return
    }
    const found: TextTranslationPromptProfile | null = this.profiles.findById(rawId)
    if (found === null) {
      this.toast($r('app.string.llm_source_missing'))
      this.stack.pop()
      return
    }
    this.promptProfileId = found.promptProfileId
    this.builtIn = found.builtIn
    this.sourceIsCustom = !found.builtIn
    this.nameDraft = found.displayName
    this.styleDraft = found.styleInstructions
    if (found.builtIn) {
      this.titleKey = 'text_translation_prompt_detail_built_in'
      this.primaryLabelKey = 'text_translation_prompt_use'
    } else {
      this.titleKey = 'text_translation_prompt_detail_custom'
      this.primaryLabelKey = 'llm_source_save'
    }
    this.loaded = true
  }

  private dirtyForCustom(): boolean {
    const existing: TextTranslationPromptProfile | null = this.profiles.findById(this.promptProfileId)
    if (existing === null) {
      return this.nameDraft.trim().length > 0 || this.styleDraft.trim().length > 0
    }
    return this.nameDraft.trim() !== existing.displayName ||
      this.styleDraft.trim() !== existing.styleInstructions
  }

  private candidateFromDrafts(): TextTranslationPromptProfile | null {
    const name: string = this.nameDraft.trim()
    const style: string = this.styleDraft.trim()
    if (name.length === 0 || style.length === 0) {
      this.toast($r('app.string.text_translation_prompt_fields_required'))
      return null
    }
    if (name.length > MAX_TEXT_TRANSLATION_PROMPT_NAME_CHARS) {
      this.toast($r('app.string.text_translation_prompt_name_too_long'))
      return null
    }
    if (style.length > MAX_TEXT_TRANSLATION_STYLE_CHARS) {
      this.toast($r('app.string.text_translation_prompt_style_too_long'))
      return null
    }
    const value: TextTranslationPromptProfile = new TextTranslationPromptProfile()
    value.promptProfileId = this.promptProfileId
    value.displayName = name
    value.styleInstructions = TextTranslationPromptContract.normalizeLineEndings(style)
    value.builtIn = false
    if (this.promptProfileId.length === 0) {
      value.promptProfileId = util.generateRandomUUID(true)
      value.promptRevision = 1
      const now: number = Date.now()
      value.createdAt = now
      value.updatedAt = now
    } else {
      const existing: TextTranslationPromptProfile | null =
        this.profiles.findById(this.promptProfileId)
      if (existing !== null) {
        value.promptRevision = existing.promptRevision
        value.createdAt = existing.createdAt
        value.updatedAt = existing.updatedAt
      }
    }
    return value
  }

  private async save(): Promise<void> {
    if (this.builtIn) {
      this.useCurrentAsSelection()
      return
    }
    if (this.saving) {
      return
    }
    const candidate: TextTranslationPromptProfile | null = this.candidateFromDrafts()
    if (candidate === null) {
      return
    }
    this.saving = true
    try {
      await TextTranslationPromptProfileRepository.upsertCustom(this.ctx(), candidate)
      await TextTranslationPromptProfileRepository.select(this.ctx(), candidate.promptProfileId)
      this.toast($r('app.string.text_translation_prompt_saved'))
      this.stack.pop()
    } catch (error) {
      DiagnosticLogger.warn('text-translation-prompt', 'profile_save_failed', (error as Error).message)
      this.toast($r('app.string.text_translation_prompt_save_failed', (error as Error).message))
    } finally {
      this.saving = false
    }
  }

  private useCurrentAsSelection(): void {
    TextTranslationPromptProfileRepository.select(this.ctx(), this.promptProfileId)
      .then(() => {
        this.toast($r('app.string.text_translation_prompt_selected'))
        this.stack.pop()
      })
      .catch((error: Error) => {
        DiagnosticLogger.warn('text-translation-prompt', 'profile_select_failed', error.message)
        this.toast($r('app.string.text_translation_prompt_save_failed', error.message))
      })
  }

  private confirmDelete(): void {
    if (this.deleting || this.promptProfileId.length === 0) {
      return
    }
    const isCurrentSelection: boolean =
      this.profiles.selectedPromptProfileId === this.promptProfileId
    this.getUIContext().showAlertDialog({
      title: $r('app.string.common_delete'),
      message: isCurrentSelection
        ? $r('app.string.text_translation_prompt_delete_current_confirm')
        : $r('app.string.text_translation_prompt_delete_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        action: () => {
          this.deleteCustom()
        },
      },
    })
  }

  private deleteCustom(): void {
    this.deleting = true
    TextTranslationPromptProfileRepository.removeCustom(this.ctx(), this.promptProfileId)
      .then(() => {
        this.stack.pop()
      })
      .catch((error: Error) => {
        this.deleting = false
        DiagnosticLogger.warn('text-translation-prompt', 'profile_delete_failed', error.message)
        this.toast($r('app.string.text_translation_prompt_delete_failed', error.message))
      })
  }

  private copyAsCustom(): void {
    if (this.customCount() >= MAX_TEXT_TRANSLATION_CUSTOM_PROFILES) {
      this.toast($r('app.string.text_translation_prompt_limit_reached'))
      return
    }
    const source: TextTranslationPromptProfile | null = this.profiles.findById(this.promptProfileId)
    if (source === null) {
      this.toast($r('app.string.llm_source_missing'))
      this.stack.pop()
      return
    }
    const newId: string = util.generateRandomUUID(true)
    const copyName: string = source.displayName + ' ' + AppStrings.get('text_translation_prompt_copy_suffix')
    const draft: TextTranslationPromptProfile =
      TextTranslationPromptProfileRepository.copyAsCustom(source, newId, copyName, Date.now())
    this.promptProfileId = draft.promptProfileId
    this.builtIn = false
    this.sourceIsCustom = true
    this.titleKey = 'text_translation_prompt_detail_new'
    this.primaryLabelKey = 'text_translation_prompt_create'
    this.nameDraft = draft.displayName
    this.styleDraft = draft.styleInstructions
  }

  private cancelToBack(): boolean {
    if (this.builtIn || this.promptProfileId.length === 0) {
      return false
    }
    if (!this.dirtyForCustom()) {
      return false
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.text_translation_prompt_discard_changes'),
      message: $r('app.string.text_translation_prompt_discard_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.stack.pop()
        },
      },
    })
    return true
  }

  private customCount(): number {
    return this.profiles.customProfiles.length
  }

  private primaryButtonLabel(): ResourceStr {
    if (this.primaryLabelKey === 'text_translation_prompt_use') {
      return $r('app.string.text_translation_prompt_use')
    }
    if (this.primaryLabelKey === 'text_translation_prompt_create') {
      return $r('app.string.text_translation_prompt_create')
    }
    return $r('app.string.common_save')
  }

  @Builder
  private BuiltInView() {
    ListItem() {
      SectionHeader({ title: $r('app.string.text_translation_prompt_detail_built_in') })
    }
    .margin({ top: ThemeConstants.SPACE_XS })
    ListItem() {
      GroupedListSection() {
        ConciseListRow({
          leadingIcon: $r('sys.symbol.doc_plaintext'),
          title: $r('app.string.llm_source_name'),
          trailingText: this.nameDraft,
          showChevron: false,
        })
      }
    }
    ListItem() {
      SectionHeader({ title: $r('app.string.text_translation_prompt_style_label') })
    }
    .margin({ top: ThemeConstants.SPACE_MD })
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        Text(this.styleDraft)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .lineHeight(22)
          .width('100%')
          .padding(ThemeConstants.SPACE_LG)
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    ListItem() {
      GroupedListSection() {
        ConciseListRow({
          title: this.primaryButtonLabel(),
          leadingIcon: $r('sys.symbol.checkmark_circle'),
          showChevron: false,
          isEnabled: !this.saving,
          action: () => {
            this.useCurrentAsSelection()
          },
        })
        ListRowDivider()
        ConciseListRow({
          title: $r('app.string.text_translation_prompt_copy_as_custom'),
          subtitle: $r('app.string.text_translation_prompt_copy_as_custom_hint'),
          leadingIcon: $r('sys.symbol.square_and_pencil'),
          showChevron: false,
          action: () => {
            this.copyAsCustom()
          },
        })
      }
    }
    .margin({ top: ThemeConstants.SPACE_MD })
  }

  @Builder
  private CustomEditView() {
    ListItem() {
      SectionHeader({
        title: this.promptProfileId.length > 0
          ? $r('app.string.text_translation_prompt_detail_custom')
          : $r('app.string.text_translation_prompt_detail_new')
      })
    }
    .margin({ top: ThemeConstants.SPACE_XS })
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        SettingsTextField({
          label: $r('app.string.llm_source_name'),
          value: this.nameDraft,
          placeholder: $r('app.string.text_translation_prompt_name_placeholder'),
          onChange: (value: string) => {
            this.nameDraft = value
          },
        })
      }
    }
    ListItem() {
      SectionHeader({ title: $r('app.string.text_translation_prompt_style_label') })
    }
    .margin({ top: ThemeConstants.SPACE_MD })
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        Column({ space: ThemeConstants.SPACE_XS }) {
          TextArea({
            text: this.styleDraft,
            placeholder: $r('app.string.text_translation_prompt_style_placeholder'),
          })
            .width('100%')
            .height(180)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
            .padding(ThemeConstants.SPACE_SM)
            .onChange((value: string) => {
              this.styleDraft = value
            })
          Row() {
            Blank()
            Text(`${this.styleDraft.length} / ${MAX_TEXT_TRANSLATION_STYLE_CHARS}`)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ right: ThemeConstants.SPACE_XS, top: ThemeConstants.SPACE_XS })
        }
        .padding({
          left: ThemeConstants.SPACE_MD,
          right: ThemeConstants.SPACE_MD,
          top: ThemeConstants.SPACE_SM,
          bottom: ThemeConstants.SPACE_SM,
        })
        .width('100%')
      }
    }
    ListItem() {
      GroupedListSection() {
        ConciseListRow({
          title: this.primaryButtonLabel(),
          leadingIcon: $r('sys.symbol.checkmark_circle'),
          showChevron: false,
          isEnabled: !this.saving && !this.deleting,
          action: () => {
            this.save()
          },
        })
        if (this.sourceIsCustom && this.promptProfileId.length > 0) {
          ListRowDivider()
          ConciseListRow({
            title: $r('app.string.common_delete'),
            leadingIcon: $r('sys.symbol.trash'),
            destructive: true,
            showChevron: false,
            isEnabled: !this.saving && !this.deleting,
            action: () => {
              this.confirmDelete()
            },
          })
        }
      }
    }
    .margin({ top: ThemeConstants.SPACE_MD })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        if (this.loaded) {
          if (this.builtIn) {
            this.BuiltInView()
          } else {
            this.CustomEditView()
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get(this.titleKey)))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onBackPressed(() => {
      return this.cancelToBack()
    })
    .onReady((context: NavDestinationContext) => {
      const params: TextTranslationPromptProfileDetailParams | null =
        context.pathInfo.param as TextTranslationPromptProfileDetailParams | null
      if (params === null) {
        this.load(new TextTranslationPromptProfileDetailParams())
        return
      }
      this.load(params)
    })
  }
}
