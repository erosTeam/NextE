import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppModalScaffold,
  AppColorPicker,
  ThemeConstants,
  EhMytags,
  EhUsertag,
  EhMytagSet,
  EhTagSuggestion,
  EhConstants,
  EhApiPhpService,
  EhApiService,
  connectSiteMode,
  UserTagStore,
  UserTagSignal,
  connectUserTagSignal,
  TagTranslationService,
  DiagnosticLogger,
  PageLoadingState,
  PageErrorState,
  CardEmptyState,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  MyTagsPageParams,
  connectNavStack,
  immersiveTitleBarOpts,
} from 'shared'

const MYTAGS_SHEET_EDIT: string = 'edit'
const MYTAGS_SHEET_ADD: string = 'add'
const MYTAGS_SHEET_TAGSET: string = 'tagset'

/**
 * My Tags (mytags) — the user's watched / hidden / color-flagged tags. Routed page off Settings.
 * Renders each tag as a management row: status icon, full tag name / translation, and EH color /
 * weight badge. This follows eros_fe's mytags list semantics instead of a gallery tag-chip wall.
 * Loads via EhApiService.getMyTags (requires login). Existing usertag rows can be edited through
 * EH's protected /api.php setusertag method, deleted through the classic /mytags mass action, or a
 * new tag can be added through /mytags usertag_action=add. Tagset management remains separate.
 */
@ComponentV2
export struct MyTagsPage {
  @Local params: MyTagsPageParams = new MyTagsPageParams();
  @Local mytags: EhMytags = new EhMytags();
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local myTagsSheetShown: boolean = false;
  @Local myTagsSheetKind: string = '';
  @Local editSubmitting: boolean = false;
  @Local editError: string = '';
  @Local editTagId: string = '';
  @Local editTagTitle: string = '';
  @Local editTagDisplay: string = '';
  @Local editTagTranslate: string = '';
  @Local editWatched: boolean = false;
  @Local editHidden: boolean = false;
  @Local editDefaultColor: boolean = true;
  @Local editColor: string = '';
  @Local editWeight: string = '';
  @Local addSubmitting: boolean = false;
  @Local addSuggesting: boolean = false;
  @Local addError: string = '';
  @Local addTagQuery: string = '';
  @Local addTagName: string = '';
  @Local addTagTranslate: string = '';
  @Local addWatched: boolean = false;
  @Local addHidden: boolean = false;
  @Local addDefaultColor: boolean = true;
  @Local addColor: string = '';
  @Local addWeight: string = '10';
  @Local addSuggestions: EhTagSuggestion[] = [];
  @Local addSuggestEpoch: number = 0;
  @Local addSuppressNextSuggest: boolean = false;
  @Local tagsetSubmitting: boolean = false;
  @Local tagsetError: string = '';
  @Local tagsetAction: string = '';
  @Local tagsetName: string = '';
  @Local showingTagsetList: boolean = true;
  @Local tagSig: UserTagSignal = connectUserTagSignal();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private openMyTagsSheet(kind: string): void {
    this.myTagsSheetKind = kind
    this.myTagsSheetShown = true
  }

  private closeMyTagsSheet(): void {
    this.myTagsSheetShown = false
  }

  private myTagsSheetDetents(): [string | number | Resource] {
    if (this.myTagsSheetKind === MYTAGS_SHEET_TAGSET) {
      return [SheetSize.MEDIUM]
    }
    return [SheetSize.LARGE]
  }

  private async load(tagset: string = ''): Promise<void> {
    this.loading = true
    this.error = ''
    try {
      this.mytags = await EhApiService.getInstance().getMyTags(connectSiteMode().isEx, tagset)
      this.showingTagsetList = tagset.length === 0 && this.mytags.tagSets.length > 1
      this.publishUserTags()
    } catch (err) {
      const e = err as Error
      this.error = e.message
      DiagnosticLogger.warn('mytags', 'load_failed', e.message)
    }
    this.loading = false
  }

  private async reloadCurrentTagset(): Promise<void> {
    await this.load(this.mytags.currentTagset)
  }

  private publishUserTags(): void {
    UserTagStore.getInstance().setTags(this.mytags.tags)
    this.tagSig.version = this.tagSig.version + 1
  }

  private selectTagset(id: string): void {
    if (!this.loading && id.length > 0) {
      this.stack.pushPathByName('MyTags', new MyTagsPageParams(id))
    }
  }

  private tagLabel(t: EhUsertag): string {
    return t.display.length > 0 ? t.display : t.tag
  }

  private tagTitle(t: EhUsertag): string {
    return t.tag.length > 0 ? t.tag : this.tagLabel(t)
  }

  private tagSubtitle(t: EhUsertag): string {
    if (t.translate.length === 0 || t.translate === t.tag || t.translate === this.tagLabel(t)) {
      return ''
    }
    return t.translate
  }

  private tagFillColor(t: EhUsertag): ResourceColor {
    if (t.colorCode.length > 0) {
      return t.colorCode
    }
    if (t.fillColor.length > 0) {
      return t.fillColor
    }
    if (t.color.length > 0) {
      return t.color
    }
    return $r('sys.color.ohos_id_color_button_normal')
  }

  private tagTextColor(t: EhUsertag): ResourceColor {
    if (t.textColor.length > 0) {
      return t.textColor
    }
    return $r('sys.color.font_primary')
  }

  private tagBorderColor(t: EhUsertag): ResourceColor {
    if (t.color.length > 0) {
      return t.color
    }
    return $r('sys.color.ohos_id_color_list_separator')
  }

  private tagWeightLabel(t: EhUsertag): string {
    if (t.tagWeight.length > 0) {
      return t.tagWeight
    }
    return `${t.weight}`
  }

  private openEditTag(t: EhUsertag): void {
    this.editTagId = t.tagId
    this.editTagTitle = t.tag
    this.editTagDisplay = this.tagLabel(t)
    this.editTagTranslate = this.tagSubtitle(t)
    this.editWatched = t.watched
    this.editHidden = t.hidden
    this.editDefaultColor = t.defaultColor
    this.editColor = t.defaultColor ? '' : (t.colorCode.length > 0 ? t.colorCode : t.color)
    this.editWeight = t.tagWeight.length > 0 ? t.tagWeight : `${t.weight}`
    this.editError = ''
    this.openMyTagsSheet(MYTAGS_SHEET_EDIT)
  }

  private openAddTag(): void {
    this.addSubmitting = false
    this.addSuggesting = false
    this.addError = ''
    this.addTagQuery = ''
    this.addTagName = ''
    this.addTagTranslate = ''
    this.addWatched = false
    this.addHidden = false
    this.addDefaultColor = true
    this.addColor = ''
    this.addWeight = '10'
    this.addSuggestions = []
    this.addSuggestEpoch = this.addSuggestEpoch + 1
    this.addSuppressNextSuggest = false
    this.openMyTagsSheet(MYTAGS_SHEET_ADD)
  }

  private normalizedEditColor(): string {
    if (this.editDefaultColor) {
      return ''
    }
    const c: string = this.editColor.trim()
    if (c.length === 0) {
      return ''
    }
    return c.startsWith('#') ? c : `#${c}`
  }

  private normalizedAddColor(): string {
    if (this.addDefaultColor) {
      return ''
    }
    const c: string = this.addColor.trim()
    if (c.length === 0) {
      return ''
    }
    return c.startsWith('#') ? c : `#${c}`
  }

  private canSubmitEdit(): boolean {
    return this.editTagId.length > 0 &&
      this.mytags.apikey.length > 0 &&
      this.mytags.apiuid.length > 0 &&
      !this.editSubmitting
  }

  private addTagLabel(): string {
    const selected: string = this.addTagName.trim()
    return selected.length > 0 ? selected : this.addTagQuery.trim()
  }

  private hasExistingTag(label: string): boolean {
    const normalized: string = label.trim().toLowerCase()
    if (normalized.length === 0) {
      return false
    }
    return this.mytags.tags.some((t: EhUsertag) => t.tag.toLowerCase() === normalized)
  }

  private canSubmitAdd(): boolean {
    const tagName: string = this.addTagLabel()
    return tagName.length > 0 && !this.hasExistingTag(tagName) && !this.addSubmitting
  }

  private currentTagset(): EhMytagSet {
    const found: EhMytagSet | undefined =
      this.mytags.tagSets.find((s: EhMytagSet) => s.tagsetId === this.mytags.currentTagset)
    return found === undefined ? new EhMytagSet() : found
  }

  private currentTagsetName(): string {
    const current: EhMytagSet = this.currentTagset()
    return current.name.length > 0 ? current.name : this.mytags.currentTagset
  }

  private canManageCurrentTagset(): boolean {
    return this.mytags.currentTagset.length > 0 && !this.loading && !this.tagsetSubmitting
  }

  private openCreateTagset(): void {
    this.tagsetAction = 'create'
    this.tagsetName = ''
    this.tagsetError = ''
    this.tagsetSubmitting = false
    this.openMyTagsSheet(MYTAGS_SHEET_TAGSET)
  }

  private openRenameTagset(): void {
    if (!this.canManageCurrentTagset()) {
      return
    }
    this.tagsetAction = 'rename'
    this.tagsetName = this.currentTagsetName()
    this.tagsetError = ''
    this.tagsetSubmitting = false
    this.openMyTagsSheet(MYTAGS_SHEET_TAGSET)
  }

  private canSubmitTagset(): boolean {
    if (this.tagsetSubmitting) {
      return false
    }
    const name: string = this.tagsetName.trim()
    if (this.tagsetAction === 'create') {
      return name.length > 0
    }
    if (this.tagsetAction === 'rename') {
      return this.canManageCurrentTagset() && name.length > 0 && name !== this.currentTagsetName()
    }
    return false
  }

  private tagsetSheetTitle(): ResourceStr {
    if (this.tagsetAction === 'rename') {
      return $r('app.string.mytags_tagset_rename_title')
    }
    return $r('app.string.mytags_tagset_create_title')
  }

  private tagsetConfirmText(): ResourceStr {
    if (this.tagsetAction === 'rename') {
      return $r('app.string.mytags_tagset_rename')
    }
    return $r('app.string.mytags_tagset_create')
  }

  private confirmSubmitEdit(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.mytags_save_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.mytags_save'),
        action: () => {
          this.submitEdit()
        },
      },
    })
  }

  private confirmDeleteTag(): void {
    if (this.editTagId.length === 0 || this.editSubmitting) {
      return
    }
    this.getUIContext().showAlertDialog({
      message: $r('app.string.mytags_delete_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.mytags_delete'),
        action: () => {
          this.deleteTag()
        },
      },
    })
  }

  private confirmSubmitAdd(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.mytags_add_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.mytags_add'),
        action: () => {
          this.submitAdd()
        },
      },
    })
  }

  private confirmSubmitTagset(): void {
    const message: ResourceStr =
      this.tagsetAction === 'rename'
        ? $r('app.string.mytags_tagset_rename_confirm')
        : $r('app.string.mytags_tagset_create_confirm')
    this.getUIContext().showAlertDialog({
      message,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: this.tagsetConfirmText(),
        action: () => {
          this.submitTagset()
        },
      },
    })
  }

  private confirmDeleteTagset(): void {
    if (!this.canManageCurrentTagset() || !this.mytags.canDelete) {
      return
    }
    this.getUIContext().showAlertDialog({
      message: $r('app.string.mytags_tagset_delete_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.mytags_tagset_delete'),
        action: () => {
          this.deleteCurrentTagset()
        },
      },
    })
  }

  private async submitEdit(): Promise<void> {
    if (!this.canSubmitEdit()) {
      return
    }
    this.editSubmitting = true
    this.editError = ''
    try {
      await EhApiPhpService.setUserTag(
        EhConstants.baseUrl(connectSiteMode().isEx),
        this.mytags.apikey,
        this.mytags.apiuid,
        this.editTagId,
        this.editWatched,
        this.editHidden,
        this.normalizedEditColor(),
        this.editWeight,
      )
      await this.reloadCurrentTagset()
      this.closeMyTagsSheet()
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.mytags_save_success'),
      })
    } catch (err) {
      const e = err as Error
      this.editError = e.message
      DiagnosticLogger.warn('mytags', 'save_failed', e.message)
    }
    this.editSubmitting = false
  }

  private async submitAdd(): Promise<void> {
    if (!this.canSubmitAdd()) {
      return
    }
    this.addSubmitting = true
    this.addError = ''
    try {
      await EhApiService.getInstance().addUserTag({
        isEx: connectSiteMode().isEx,
        tagName: this.addTagLabel(),
        tagset: this.mytags.currentTagset,
        color: this.normalizedAddColor(),
        weight: this.addWeight,
        watched: this.addWatched,
        hidden: this.addHidden,
      })
      await this.reloadCurrentTagset()
      this.closeMyTagsSheet()
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.mytags_add_success'),
      })
    } catch (err) {
      const e = err as Error
      this.addError = e.message
      DiagnosticLogger.warn('mytags', 'add_failed', e.message)
    }
    this.addSubmitting = false
  }

  private async deleteTag(): Promise<void> {
    if (this.editTagId.length === 0 || this.editSubmitting) {
      return
    }
    this.editSubmitting = true
    this.editError = ''
    try {
      await EhApiService.getInstance().deleteUserTags({
        isEx: connectSiteMode().isEx,
        tagIds: [this.editTagId],
        tagset: this.mytags.currentTagset,
      })
      await this.reloadCurrentTagset()
      this.closeMyTagsSheet()
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.mytags_delete_success'),
      })
    } catch (err) {
      const e = err as Error
      this.editError = e.message
      DiagnosticLogger.warn('mytags', 'delete_failed', e.message)
    }
    this.editSubmitting = false
  }

  private async submitTagset(): Promise<void> {
    if (!this.canSubmitTagset()) {
      return
    }
    this.tagsetSubmitting = true
    this.tagsetError = ''
    try {
      await EhApiService.getInstance().updateMyTagsTagset({
        isEx: connectSiteMode().isEx,
        action: this.tagsetAction,
        tagset: this.mytags.currentTagset,
        name: this.tagsetName,
      })
      await this.reloadCurrentTagset()
      this.closeMyTagsSheet()
      this.getUIContext().getPromptAction().showToast({
        message:
          this.tagsetAction === 'rename'
            ? $r('app.string.mytags_tagset_rename_success')
            : $r('app.string.mytags_tagset_create_success'),
      })
    } catch (err) {
      const e = err as Error
      this.tagsetError = e.message
      DiagnosticLogger.warn('mytags', 'tagset_save_failed', e.message)
    }
    this.tagsetSubmitting = false
  }

  private async deleteCurrentTagset(): Promise<void> {
    if (!this.canManageCurrentTagset() || !this.mytags.canDelete) {
      return
    }
    this.tagsetSubmitting = true
    this.tagsetError = ''
    try {
      await EhApiService.getInstance().updateMyTagsTagset({
        isEx: connectSiteMode().isEx,
        action: 'delete',
        tagset: this.mytags.currentTagset,
        name: '',
      })
      await this.load()
      this.closeMyTagsSheet()
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.mytags_tagset_delete_success'),
      })
    } catch (err) {
      const e = err as Error
      this.tagsetError = e.message
      DiagnosticLogger.warn('mytags', 'tagset_delete_failed', e.message)
    }
    this.tagsetSubmitting = false
  }

  private setAddTagQuery(value: string): void {
    this.addTagQuery = value
    this.addTagName = value.trim()
    this.addTagTranslate = TagTranslationService.translateFullTag(this.addTagName)
    this.addError = ''
    if (this.addSuppressNextSuggest) {
      this.addSuppressNextSuggest = false
      this.addSuggestions = []
      this.addSuggesting = false
      this.addSuggestEpoch = this.addSuggestEpoch + 1
      return
    }
    const epoch: number = this.addSuggestEpoch + 1
    this.addSuggestEpoch = epoch
    this.loadAddSuggestions(value, epoch)
  }

  private async loadAddSuggestions(value: string, epoch: number): Promise<void> {
    const q: string = value.trim()
    if (q.length < 2) {
      if (epoch === this.addSuggestEpoch) {
        this.addSuggestions = []
        this.addSuggesting = false
      }
      return
    }
    this.addSuggesting = true
    try {
      const suggestions: EhTagSuggestion[] = await EhApiPhpService.tagSuggest(
        EhConstants.baseUrl(connectSiteMode().isEx),
        q,
      )
      if (epoch === this.addSuggestEpoch) {
        this.addSuggestions = suggestions.filter((s: EhTagSuggestion) => !this.hasExistingTag(s.label()))
      }
    } catch (err) {
      const e = err as Error
      if (epoch === this.addSuggestEpoch) {
        this.addError = e.message
        this.addSuggestions = []
      }
      DiagnosticLogger.warn('mytags', 'suggest_failed', e.message)
    }
    if (epoch === this.addSuggestEpoch) {
      this.addSuggesting = false
    }
  }

  private selectAddSuggestion(s: EhTagSuggestion): void {
    const label: string = s.label()
    this.addTagQuery = label
    this.addTagName = label
    this.addTagTranslate = TagTranslationService.translateFullTag(label)
    this.addSuggestions = []
    this.addSuggesting = false
    this.addSuppressNextSuggest = true
    this.addSuggestEpoch = this.addSuggestEpoch + 1
  }

  private myTagsTitleBar(): Record<string, Object> {
    const title: Record<string, Object> = {
      'mainTitle': this.showingTagsetList ? $r('app.string.settings_mytags') : this.currentTagsetName(),
    }
    const addInner: Record<string, Object> = {
      'label': $r('app.string.mytags_add'),
      'icon': $r('sys.symbol.plus'),
      'isEnabled': !this.loading && !this.showingTagsetList,
      'action': () => {
        this.openAddTag()
      },
    }
    const createInner: Record<string, Object> = {
      'label': $r('app.string.mytags_tagset_create'),
      'icon': $r('sys.symbol.folder_badge_plus'),
      'isEnabled': !this.loading,
      'action': () => {
        this.openCreateTagset()
      },
    }
    const renameInner: Record<string, Object> = {
      'label': $r('app.string.mytags_tagset_rename'),
      'icon': $r('sys.symbol.square_and_pencil'),
      'isEnabled': this.canManageCurrentTagset(),
      'action': () => {
        this.openRenameTagset()
      },
    }
    const deleteInner: Record<string, Object> = {
      'label': $r('app.string.mytags_tagset_delete'),
      'icon': $r('sys.symbol.trash'),
      'isEnabled': !this.showingTagsetList && this.canManageCurrentTagset() && this.mytags.canDelete,
      'action': () => {
        this.confirmDeleteTagset()
      },
    }
    const items: Record<string, Object>[] = []
    if (this.showingTagsetList) {
      items.push({ 'content': createInner })
    } else {
      items.push({ 'content': addInner })
      items.push({ 'content': renameInner })
    }
    if (!this.showingTagsetList && this.mytags.canDelete) {
      items.push({ 'content': deleteInner })
    }
    const menu: Record<string, Object> = { 'value': items, 'maxCount': items.length }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  build() {
    HdsNavDestination() {
      if (this.loading) {
        PageLoadingState()
      } else if (this.error.length > 0) {
        PageErrorState({
          message: this.error,
          retryAction: () => {
            this.load()
          },
        })
      } else {
        SecondaryListScaffold({ scroller: this.scroller }) {
          if (this.showingTagsetList && this.mytags.tagSets.length > 1) {
            this.TagsetRows()
          } else if (this.mytags.tags.length === 0) {
            ListItem() {
              CardEmptyState({ message: $r('app.string.common_no_content'), expand: false })
            }
          } else {
            this.TagRowsGroup()
          }
        }
      }
    }
    .titleBar(this.myTagsTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.myTagsSheetShown, this.MyTagsSheet(), {
      detents: this.myTagsSheetDetents(),
      showClose: false,
    })
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param instanceof MyTagsPageParams) {
        this.params = context.pathInfo.param as MyTagsPageParams
      }
      this.load(this.params.tagsetId)
    })
  }

  @Builder
  private TagsetRows() {
    ListItem() {
      GroupedListSection() {
        ForEach(
          this.mytags.tagSets,
          (s: EhMytagSet, index: number) => {
            ConciseListRow({
              title: s.name,
              trailingText: `${s.count}`,
              trailingDropdown: false,
              showChevron: true,
              action: () => {
                this.selectTagset(s.tagsetId)
              },
            })
            if (index < this.mytags.tagSets.length - 1) {
              this.TagRowDivider()
            }
          },
          (s: EhMytagSet) => s.tagsetId,
        )
      }
    }
  }

  @Builder
  private TagRowsGroup() {
    ListItemGroup({ space: 0 }) {
      this.TagRows()
    }
    .width('100%')
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .clip(true)
    .padding(ThemeConstants.LIST_SECTION_INSET)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private TagRows() {
    ForEach(
      this.mytags.tags,
      (t: EhUsertag, index: number) => {
        ListItem() {
          Column() {
            this.TagRow(t)
            if (index < this.mytags.tags.length - 1) {
              this.TagRowDivider()
            }
          }
          .width('100%')
        }
      },
      (t: EhUsertag) => t.tagId.length > 0 ? t.tagId : t.tag,
    )
  }

  @Builder
  private TagRow(t: EhUsertag) {
    ConciseListRow({
      title: this.tagTitle(t),
      subtitle: this.tagSubtitle(t),
      showChevron: true,
      isEnabled: !this.loading,
      prefixBuilderParam: () => {
        this.TagStatusPrefix(t)
      },
      suffixBuilderParam: () => {
        this.TagWeightBadge(t)
      },
      suffixPaddingRight: ThemeConstants.SPACE_SM,
      action: () => {
        this.openEditTag(t)
      },
    })
  }

  @Builder
  private TagRowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private TagStatusPrefix(t: EhUsertag) {
    Row() {
      if (t.watched) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(24)
          .fontColor(['#2BAE85'])
      } else if (t.hidden) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(24)
          .fontColor(['#DE1C31'])
      } else {
        SymbolGlyph($r('sys.symbol.dot_circle'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width(34)
    .justifyContent(FlexAlign.Center)
    .padding({ left: ThemeConstants.SPACE_SM })
  }

  @Builder
  private TagWeightBadge(t: EhUsertag) {
    Text(this.tagWeightLabel(t))
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.tagTextColor(t))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minWidth: 36 })
      .padding({
        left: ThemeConstants.SPACE_SM,
        right: ThemeConstants.SPACE_SM,
        top: ThemeConstants.SPACE_XS,
        bottom: ThemeConstants.SPACE_XS,
      })
      .backgroundColor(this.tagFillColor(t))
      .borderRadius(ThemeConstants.RADIUS_ROUND)
      .borderWidth(0.5)
      .borderColor(this.tagBorderColor(t))
  }

  @Builder
  private DraftSwitchRow(title: ResourceStr, checked: boolean, disabled: boolean, onToggle: (value: boolean) => void) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      Text(title)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(ThemeConstants.BRAND_PRIMARY)
        .enabled(!disabled)
        .onChange((value: boolean) => {
          onToggle(value)
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      if (!disabled) {
        onToggle(!checked)
      }
    })
  }

  @Builder
  private MyTagsSheet() {
    if (this.myTagsSheetKind === MYTAGS_SHEET_EDIT) {
      this.EditTagSheet()
    } else if (this.myTagsSheetKind === MYTAGS_SHEET_ADD) {
      this.AddTagSheet()
    } else if (this.myTagsSheetKind === MYTAGS_SHEET_TAGSET) {
      this.TagsetSheet()
    }
  }

  @Builder
  private EditTagSheet() {
    AppModalScaffold({
      title: $r('app.string.mytags_edit_title'),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.mytags_save'),
      secondaryText: $r('app.string.mytags_delete'),
      secondaryIcon: $r('sys.symbol.trash'),
      showSecondaryAction: true,
      secondaryEnabled: this.editTagId.length > 0,
      confirmEnabled: this.canSubmitEdit(),
      confirmLoading: this.editSubmitting,
      closeAction: () => {
        this.closeMyTagsSheet()
      },
      secondaryAction: () => {
        this.confirmDeleteTag()
      },
      confirmAction: () => {
        this.confirmSubmitEdit()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text(this.editTagDisplay.length > 0 ? this.editTagDisplay : this.editTagTitle)
              .fontSize(ThemeConstants.FONT_SIZE_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.editTagTranslate.length > 0) {
              Text(this.editTagTranslate)
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            Text(this.editTagTitle)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          this.DraftSwitchRow($r('app.string.mytags_watch'), this.editWatched, this.editSubmitting, (value: boolean) => {
            this.editWatched = value
            if (value) {
              this.editHidden = false
            }
          })
          this.DraftSwitchRow($r('app.string.mytags_hide'), this.editHidden, this.editSubmitting, (value: boolean) => {
            this.editHidden = value
            if (value) {
              this.editWatched = false
            }
          })
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text($r('app.string.mytags_weight'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
            TextInput({ text: this.editWeight, placeholder: '10' })
              .width('100%')
              .height(48)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
              .enabled(!this.editSubmitting)
              .type(InputType.Normal)
              .onChange((value: string) => {
                this.editWeight = value
              })
          }
          .width('100%')
          this.DraftSwitchRow($r('app.string.mytags_default_color'), this.editDefaultColor, this.editSubmitting, (value: boolean) => {
            this.editDefaultColor = value
          })
          if (!this.editDefaultColor) {
            AppColorPicker({
              title: $r('app.string.mytags_color'),
              color: this.editColor,
              disabled: this.editSubmitting,
              colorChange: (value: string) => {
                this.editColor = value
              },
            })
          }
          if (this.editError.length > 0) {
            Text(this.editError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
      }
    }
  }

  @Builder
  private AddTagSheet() {
    AppModalScaffold({
      title: $r('app.string.mytags_add_title'),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.mytags_add'),
      confirmEnabled: this.canSubmitAdd(),
      confirmLoading: this.addSubmitting,
      closeAction: () => {
        this.closeMyTagsSheet()
      },
      confirmAction: () => {
        this.confirmSubmitAdd()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text($r('app.string.mytags_tag_name'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
            TextInput({ text: this.addTagQuery, placeholder: $r('app.string.mytags_tag_placeholder') })
              .width('100%')
              .height(48)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
              .enabled(!this.addSubmitting)
              .onChange((value: string) => {
                this.setAddTagQuery(value)
              })
            if (this.addTagTranslate.length > 0) {
              Text(this.addTagTranslate)
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
            if (this.hasExistingTag(this.addTagLabel())) {
              Text($r('app.string.mytags_add_existing'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
          }
          .width('100%')
          if (this.addSuggestions.length > 0 || this.addSuggesting) {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text(this.addSuggesting ? $r('app.string.mytags_suggest_loading') : $r('app.string.mytags_suggestions'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
              ForEach(
                this.addSuggestions,
                (s: EhTagSuggestion) => {
                  this.AddSuggestionRow(s)
                },
                (s: EhTagSuggestion) => s.label(),
              )
            }
            .width('100%')
          }
          this.DraftSwitchRow($r('app.string.mytags_watch'), this.addWatched, this.addSubmitting, (value: boolean) => {
            this.addWatched = value
            if (value) {
              this.addHidden = false
            }
          })
          this.DraftSwitchRow($r('app.string.mytags_hide'), this.addHidden, this.addSubmitting, (value: boolean) => {
            this.addHidden = value
            if (value) {
              this.addWatched = false
            }
          })
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text($r('app.string.mytags_weight'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
            TextInput({ text: this.addWeight, placeholder: '10' })
              .width('100%')
              .height(48)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
              .enabled(!this.addSubmitting)
              .type(InputType.Normal)
              .onChange((value: string) => {
                this.addWeight = value
              })
          }
          .width('100%')
          this.DraftSwitchRow($r('app.string.mytags_default_color'), this.addDefaultColor, this.addSubmitting, (value: boolean) => {
            this.addDefaultColor = value
          })
          if (!this.addDefaultColor) {
            AppColorPicker({
              title: $r('app.string.mytags_color'),
              color: this.addColor,
              disabled: this.addSubmitting,
              colorChange: (value: string) => {
                this.addColor = value
              },
            })
          }
          if (this.addError.length > 0) {
            Text(this.addError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
      }
    }
  }

  @Builder
  private TagsetSheet() {
    AppModalScaffold({
      title: this.tagsetSheetTitle(),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: this.tagsetConfirmText(),
      confirmEnabled: this.canSubmitTagset(),
      confirmLoading: this.tagsetSubmitting,
      closeAction: () => {
        this.closeMyTagsSheet()
      },
      confirmAction: () => {
        this.confirmSubmitTagset()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Column({ space: ThemeConstants.SPACE_XS }) {
            Text($r('app.string.mytags_tagset_name'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
            TextInput({ text: this.tagsetName, placeholder: $r('app.string.mytags_tagset_name_placeholder') })
              .width('100%')
              .height(48)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
              .enabled(!this.tagsetSubmitting)
              .onChange((value: string) => {
                this.tagsetName = value
                this.tagsetError = ''
              })
          }
          .width('100%')
          if (this.tagsetError.length > 0) {
            Text(this.tagsetError)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
      }
    }
  }

  @Builder
  private AddSuggestionRow(s: EhTagSuggestion) {
    Row({ space: ThemeConstants.SPACE_SM }) {
      Text(s.namespace.length > 0 ? s.namespace : 'tag')
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor(ThemeConstants.TEXT_ON_BRAND)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .borderRadius(ThemeConstants.RADIUS_SM)
        .padding({
          left: ThemeConstants.SPACE_XS,
          right: ThemeConstants.SPACE_XS,
          top: ThemeConstants.SPACE_XS,
          bottom: ThemeConstants.SPACE_XS,
        })
      Text(s.text)
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_SM,
      bottom: ThemeConstants.SPACE_SM,
    })
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.selectAddSuggestion(s)
    })
  }
}
