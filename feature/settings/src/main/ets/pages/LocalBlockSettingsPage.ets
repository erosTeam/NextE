import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppModalScaffold,
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE,
  LOCAL_BLOCK_COMMENT_DISPLAY_HIDE,
  LOCAL_BLOCK_TYPE_COMMENT,
  LOCAL_BLOCK_TYPE_COMMENTATOR,
  LOCAL_BLOCK_TYPE_TITLE,
  LOCAL_BLOCK_TYPE_UPLOADER,
  LocalBlockRule,
  LocalBlockSettings,
  LocalBlockState,
  SecondaryListScaffold,
  SettingsCheckedMenuItem,
  ThemeConstants,
  ListRowDivider,
  connectLocalBlock,
  immersiveTitleBarAction,
  immersiveTitleBarWithActions,
  appSheetOptions,
} from 'shared'

@ComponentV2
export struct LocalBlockSettingsPage {
  @Local block: LocalBlockState = connectLocalBlock();
  @Local ruleSheetShown: boolean = false;
  @Local newRuleSheetShown: boolean = false;
  @Local editingRuleId: string = '';
  @Local draftType: string = LOCAL_BLOCK_TYPE_TITLE;
  @Local draftText: string = '';
  @Local draftEnabled: boolean = true;
  @Local draftRegex: boolean = false;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private ruleCount(type: string): number {
    return this.block.rules.filter((rule: LocalBlockRule) => rule.blockType === type).length
  }

  private rulesForType(type: string): LocalBlockRule[] {
    return this.block.rules.filter((rule: LocalBlockRule) => rule.blockType === type)
  }

  private totalRules(): number {
    return this.block.rules.length
  }

  private scoreThresholdText(): string {
    return `${this.block.scoreFilteringThreshold}`
  }

  private commentDisplayText(mode: string): ResourceStr {
    return LocalBlockSettings.normalizeCommentDisplayMode(mode) === LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE
      ? $r('app.string.local_block_comment_display_collapse')
      : $r('app.string.local_block_comment_display_hide')
  }

  private typeText(type: string): ResourceStr {
    switch (LocalBlockSettings.normalizeType(type)) {
      case LOCAL_BLOCK_TYPE_UPLOADER:
        return $r('app.string.local_block_type_uploader')
      case LOCAL_BLOCK_TYPE_COMMENTATOR:
        return $r('app.string.local_block_type_commentator')
      case LOCAL_BLOCK_TYPE_COMMENT:
        return $r('app.string.local_block_type_comment')
      default:
        return $r('app.string.local_block_type_title')
    }
  }

  private typeIcon(type: string): Resource {
    switch (LocalBlockSettings.normalizeType(type)) {
      case LOCAL_BLOCK_TYPE_UPLOADER:
        return $r('sys.symbol.person')
      case LOCAL_BLOCK_TYPE_COMMENTATOR:
        return $r('sys.symbol.person_2')
      case LOCAL_BLOCK_TYPE_COMMENT:
        return $r('sys.symbol.text_bubble_left_2')
      default:
        return $r('sys.symbol.textformat')
    }
  }

  private openNewRule(): void {
    this.ruleSheetShown = false
    this.editingRuleId = ''
    this.draftType = LocalBlockSettings.normalizeType(this.draftType)
    this.draftText = ''
    this.draftEnabled = true
    this.draftRegex = false
    this.newRuleSheetShown = true
  }

  private openEditRule(rule: LocalBlockRule): void {
    this.newRuleSheetShown = false
    this.editingRuleId = rule.id
    this.draftType = LocalBlockSettings.normalizeType(rule.blockType)
    this.draftText = rule.ruleText
    this.draftEnabled = rule.enabled
    this.draftRegex = rule.enableRegex
    this.ruleSheetShown = true
  }

  private closeRuleSheet(): void {
    this.ruleSheetShown = false
    this.newRuleSheetShown = false
  }

  private isEditRuleSheetHost(rule: LocalBlockRule): boolean {
    return this.ruleSheetShown && this.editingRuleId === rule.id
  }

  private editRuleSheetOptions(rule: LocalBlockRule): SheetOptions {
    return appSheetOptions({
      detents: [SheetSize.LARGE],
      showClose: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_SCROLL,
      onDisappear: () => {
        if (this.isEditRuleSheetHost(rule)) {
          this.closeRuleSheet()
        }
      },
    })
  }

  private newRuleSheetOptions(): SheetOptions {
    return appSheetOptions({
      detents: [SheetSize.LARGE],
      showClose: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_SCROLL,
      onDisappear: () => {
        if (this.newRuleSheetShown) {
          this.closeRuleSheet()
        }
      },
    })
  }

  private draftRegexValid(): boolean {
    if (!this.draftRegex || this.draftText.trim().length === 0) {
      return true
    }
    try {
      new RegExp(this.draftText.trim().replace(/\(\?i\)/g, ''))
      return true
    } catch (_error) {
      return false
    }
  }

  private canSaveDraft(): boolean {
    return this.draftText.trim().length > 0 && this.draftRegexValid()
  }

  private saveDraft(): void {
    if (!this.canSaveDraft()) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.local_block_regex_invalid'),
      })
      return
    }
    const rule: LocalBlockRule = new LocalBlockRule()
    rule.id = this.editingRuleId
    rule.blockType = this.draftType
    rule.ruleText = this.draftText
    rule.enabled = this.draftEnabled
    rule.enableRegex = this.draftRegex
    LocalBlockSettings.upsertRule(this.ctx(), rule)
    this.closeRuleSheet()
  }

  private deleteDraft(): void {
    if (this.editingRuleId.length === 0) {
      return
    }
    LocalBlockSettings.removeRule(this.ctx(), this.editingRuleId)
    this.closeRuleSheet()
  }

  private setScoreFilter(value: boolean): void {
    LocalBlockSettings.setScoreFilter(this.ctx(), value, this.block.scoreFilteringThreshold)
  }

  private changeThreshold(delta: number): void {
    LocalBlockSettings.setScoreFilter(
      this.ctx(),
      this.block.filterCommentsByScore,
      this.block.scoreFilteringThreshold + delta,
    )
  }

  private setCommentDisplayMode(mode: string): void {
    LocalBlockSettings.setCommentDisplayMode(this.ctx(), mode)
  }

  @Builder
  private TypeMenu(select: (action: () => void) => void) {
    Menu() {
      this.TypeMenuItem(LOCAL_BLOCK_TYPE_TITLE, select)
      this.TypeMenuItem(LOCAL_BLOCK_TYPE_UPLOADER, select)
      this.TypeMenuItem(LOCAL_BLOCK_TYPE_COMMENTATOR, select)
      this.TypeMenuItem(LOCAL_BLOCK_TYPE_COMMENT, select)
    }
  }

  @Builder
  private TypeMenuItem(type: string, select: (action: () => void) => void) {
    SettingsCheckedMenuItem({
      label: this.typeText(type),
      selected: this.draftType === type,
      selectAction: () => {
        select(() => {
          this.draftType = type
        })
      },
    })
  }

  @Builder
  private CommentDisplayMenu(select: (action: () => void) => void) {
    Menu() {
      this.CommentDisplayMenuItem(LOCAL_BLOCK_COMMENT_DISPLAY_HIDE, select)
      this.CommentDisplayMenuItem(LOCAL_BLOCK_COMMENT_DISPLAY_COLLAPSE, select)
    }
  }

  @Builder
  private CommentDisplayMenuItem(mode: string, select: (action: () => void) => void) {
    SettingsCheckedMenuItem({
      label: this.commentDisplayText(mode),
      selected: LocalBlockSettings.normalizeCommentDisplayMode(this.block.commentDisplayMode) === mode,
      selectAction: () => {
        select(() => {
          this.setCommentDisplayMode(mode)
        })
      },
    })
  }

  @Builder
  private RuleSection(type: string) {
    if (this.ruleCount(type) > 0) {
      ListItem() {
        GroupedListSection() {
          ConciseListRow({
            title: this.typeText(type),
            leadingIcon: this.typeIcon(type),
            trailingText: `${this.ruleCount(type)}`,
            showChevron: false,
          })
          ListRowDivider()
          ForEach(
            this.rulesForType(type),
            (rule: LocalBlockRule, index: number) => {
              ConciseListRow({
                title: rule.ruleText,
                subtitle: rule.enableRegex
                  ? $r('app.string.local_block_regex')
                  : $r('app.string.local_block_contains'),
                leadingIcon: rule.enabled ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'),
                hasSwitch: true,
                checked: rule.enabled,
                switchAction: (value: boolean) => {
                  LocalBlockSettings.setRuleEnabled(this.ctx(), rule.id, value)
                },
                action: () => {
                  this.openEditRule(rule)
                },
              }).bindSheet(
                this.isEditRuleSheetHost(rule),
                this.RuleSheet(),
                this.editRuleSheetOptions(rule),
              )
              if (index < this.ruleCount(type) - 1) {
                ListRowDivider()
              }
            },
            (rule: LocalBlockRule) => rule.id,
          )
        }
      }
    }
  }

  private titleBar(): Record<string, Object> {
    return immersiveTitleBarWithActions(AppStrings.get('local_block_title'), [
      immersiveTitleBarAction(AppStrings.get('local_block_add_rule'), $r('sys.symbol.plus'), true, () => {
        this.openNewRule()
      }),
    ], 1)
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
              title: $r('app.string.local_block_score_filter'),
              subtitle: $r('app.string.local_block_score_filter_hint'),
              leadingIcon: $r('sys.symbol.hand_thumbsdown'),
              hasSwitch: true,
              checked: this.block.filterCommentsByScore,
              switchAction: (value: boolean) => {
                this.setScoreFilter(value)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.local_block_score_threshold'),
              leadingIcon: $r('sys.symbol.list_number'),
              hasCounter: true,
              counterValue: this.scoreThresholdText(),
              counterDecreaseAction: () => {
                this.changeThreshold(-1)
              },
              counterIncreaseAction: () => {
                this.changeThreshold(1)
              },
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.local_block_comment_display'),
              subtitle: $r('app.string.local_block_comment_display_hint'),
              leadingIcon: $r('sys.symbol.text_bubble_left_2'),
              trailingText: this.commentDisplayText(this.block.commentDisplayMode),
              trailingDropdown: true,
              dropdownMenuEnabled: true,
              dropdownMenuBuilder: (select: (action: () => void) => void) => {
                this.CommentDisplayMenu(select)
              },
            })
          }
        }
        this.RuleSection(LOCAL_BLOCK_TYPE_TITLE)
        this.RuleSection(LOCAL_BLOCK_TYPE_UPLOADER)
        this.RuleSection(LOCAL_BLOCK_TYPE_COMMENTATOR)
        this.RuleSection(LOCAL_BLOCK_TYPE_COMMENT)
      }
    }
    .titleBar(this.titleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet(this.newRuleSheetShown, this.RuleSheet(), this.newRuleSheetOptions())
  }

  @Builder
  private RuleSheet() {
    AppModalScaffold({
      title: this.editingRuleId.length > 0
        ? $r('app.string.local_block_edit_rule')
        : $r('app.string.local_block_add_rule'),
      confirmText: $r('app.string.common_save'),
      confirmEnabled: this.canSaveDraft(),
      showSecondaryAction: this.editingRuleId.length > 0,
      secondaryText: $r('app.string.common_delete'),
      secondaryIcon: $r('sys.symbol.trash'),
      closeAction: () => {
        this.closeRuleSheet()
      },
      confirmAction: () => {
        this.saveDraft()
      },
      secondaryAction: () => {
        this.deleteDraft()
      },
    }) {
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          ConciseListRow({
            title: $r('app.string.local_block_rule_type'),
            leadingIcon: this.typeIcon(this.draftType),
            trailingText: this.typeText(this.draftType),
            trailingDropdown: true,
            dropdownMenuEnabled: true,
            dropdownMenuBuilder: (select: (action: () => void) => void) => {
              this.TypeMenu(select)
            },
          })
          ListRowDivider()
          ConciseListRow({
            title: $r('app.string.local_block_rule_enabled'),
            leadingIcon: $r('sys.symbol.checkmark_circle'),
            hasSwitch: true,
            checked: this.draftEnabled,
            switchAction: (value: boolean) => {
              this.draftEnabled = value
            },
          })
          ListRowDivider()
          ConciseListRow({
            title: $r('app.string.local_block_regex'),
            subtitle: $r('app.string.local_block_regex_hint'),
            leadingIcon: $r('sys.symbol.textformat'),
            hasSwitch: true,
            checked: this.draftRegex,
            switchAction: (value: boolean) => {
              this.draftRegex = value
            },
          })
        }
      }
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          Column({ space: ThemeConstants.SPACE_SM }) {
            Text($r('app.string.local_block_rule_text'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
            TextArea({
              text: this.draftText,
              placeholder: $r('app.string.local_block_rule_text_placeholder'),
            })
              .width('100%')
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => {
                this.draftText = value
              })
            if (!this.draftRegexValid()) {
              Text($r('app.string.local_block_regex_invalid'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor(Color.Red)
                .width('100%')
            }
          }
          .padding(ThemeConstants.SPACE_MD)
          .width('100%')
        }
      }
    }
  }
}
