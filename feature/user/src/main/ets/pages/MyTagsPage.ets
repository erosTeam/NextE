import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppModalScaffold,
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
  immersiveTitleBarOpts,
} from 'shared'

/**
 * My Tags (mytags) — the user's watched / hidden / color-flagged tags. Routed page off Settings.
 * Renders each tag as a chip in its own EH color (hidden tags dimmed); a watched tag gets a ring.
 * Loads via EhApiService.getMyTags (requires login). Existing usertag rows can be edited through
 * EH's protected /api.php setusertag method, deleted through the classic /mytags mass action, or a
 * new tag can be added through /mytags usertag_action=add. Tagset management remains separate.
 */
@ComponentV2
export struct MyTagsPage {
  @Local mytags: EhMytags = new EhMytags();
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local editSheetShown: boolean = false;
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
  @Local addSheetShown: boolean = false;
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
  @Local tagSig: UserTagSignal = connectUserTagSignal();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load()
  }

  private async load(tagset: string = ''): Promise<void> {
    this.loading = true
    this.error = ''
    try {
      this.mytags = await EhApiService.getInstance().getMyTags(connectSiteMode().isEx, tagset)
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
    if (id !== this.mytags.currentTagset && !this.loading) {
      this.load(id)
    }
  }

  /** Distinct tag namespaces, in first-seen order, for grouped display. */
  private namespaces(): string[] {
    const seen: string[] = []
    this.mytags.tags.forEach((t: EhUsertag) => {
      const ns: string = t.namespace()
      if (!seen.includes(ns)) {
        seen.push(ns)
      }
    })
    return seen
  }

  private tagsIn(ns: string): EhUsertag[] {
    return this.mytags.tags.filter((t: EhUsertag) => t.namespace() === ns)
  }

  private tagLabel(t: EhUsertag): string {
    return t.display.length > 0 ? t.display : t.tag
  }

  private tagSubtitle(t: EhUsertag): string {
    const label: string = this.tagLabel(t)
    if (t.translate.length === 0 || t.translate === label || t.translate === t.tag) {
      return ''
    }
    return t.translate
  }

  private openEditTag(t: EhUsertag): void {
    this.editTagId = t.tagId
    this.editTagTitle = t.tag
    this.editTagDisplay = this.tagLabel(t)
    this.editTagTranslate = this.tagSubtitle(t)
    this.editWatched = t.watched
    this.editHidden = t.hidden
    this.editDefaultColor = t.defaultColor
    this.editColor = t.defaultColor ? '' : (t.color.length > 0 ? t.color : t.fillColor)
    this.editWeight = t.tagWeight.length > 0 ? t.tagWeight : `${t.weight}`
    this.editError = ''
    this.editSheetShown = true
  }

  private openAddTag(): void {
    this.addSheetShown = true
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
      this.editSheetShown = false
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
      this.addSheetShown = false
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
      this.editSheetShown = false
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
    const title: Record<string, Object> = { 'mainTitle': $r('app.string.settings_mytags') }
    const addInner: Record<string, Object> = {
      'label': $r('app.string.mytags_add'),
      'icon': $r('sys.symbol.plus'),
      'isEnabled': !this.loading,
      'action': () => {
        this.openAddTag()
      },
    }
    const items: Record<string, Object>[] = [{ 'content': addInner }]
    const menu: Record<string, Object> = { 'value': items, 'maxCount': 1 }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({ scroller: this.scroller }) {
        if (this.loading) {
          ListItem() {
            PageLoadingState({ expand: false })
          }
        } else if (this.error.length > 0) {
          ListItem() {
            PageErrorState({
              message: this.error,
              expand: false,
              retryAction: () => {
                this.load()
              },
            })
          }
        } else if (this.mytags.tags.length === 0) {
          ListItem() {
            CardEmptyState({ message: $r('app.string.common_no_content'), expand: false })
          }
        } else {
          if (this.mytags.tagSets.length > 1) {
            ListItem() {
              this.TagsetBar()
            }
          }
          ListItem() {
            GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
              Column({ space: ThemeConstants.SPACE_MD }) {
                ForEach(
                  this.namespaces(),
                  (ns: string) => {
                    this.NamespaceGroup(ns)
                  },
                  (ns: string) => ns,
                )
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
        }
      }
    }
    .titleBar(this.myTagsTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.editSheetShown, this.EditTagSheet(), {
      detents: [SheetSize.LARGE],
      showClose: false,
    })
    .bindSheet($$this.addSheetShown, this.AddTagSheet(), {
      detents: [SheetSize.LARGE],
      showClose: false,
    })
  }

  // Two-level My Tags: a chip row to switch between the user's tag sets (mytags ?tagset=N).
  @Builder
  TagsetBar() {
    Scroll() {
      Row({ space: ThemeConstants.SPACE_SM }) {
        ForEach(
          this.mytags.tagSets,
          (s: EhMytagSet) => {
            Text(`${s.name} (${s.count})`)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(
                this.mytags.currentTagset === s.tagsetId
                  ? ThemeConstants.TEXT_ON_BRAND
                  : $r('sys.color.font_primary'),
              )
              .backgroundColor(
                this.mytags.currentTagset === s.tagsetId
                  ? ThemeConstants.BRAND_PRIMARY
                  : $r('app.color.card_background'),
              )
              .borderRadius(ThemeConstants.RADIUS_ROUND)
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
                top: ThemeConstants.SPACE_XS,
                bottom: ThemeConstants.SPACE_XS,
              })
              .maxLines(1)
              .onClick(() => {
                this.selectTagset(s.tagsetId)
              })
          },
          (s: EhMytagSet) => s.tagsetId,
        )
      }
      .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  // One namespace section: a header + that namespace's tag chips.
  @Builder
  NamespaceGroup(ns: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(ns)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_emphasize'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.tagsIn(ns),
          (t: EhUsertag) => {
            this.TagChip(t)
          },
          (t: EhUsertag) => t.tagId,
        )
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TagChip(t: EhUsertag) {
    // Grouped by namespace, so the chip shows just the short tag (display), not the full ns:tag.
    Column({ space: 1 }) {
      Text(this.tagLabel(t))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(t.textColor.length > 0 ? t.textColor : ThemeConstants.TEXT_ON_BRAND)
        .maxLines(1)
      if (this.tagSubtitle(t).length > 0) {
        Text(this.tagSubtitle(t))
          .fontSize(ThemeConstants.FONT_SIZE_TINY)
          .fontColor(t.textColor.length > 0 ? t.textColor : ThemeConstants.TEXT_ON_BRAND)
          .maxLines(1)
      }
    }
    // EH-supplied text color is readable on its own fill; only force white when EH gave none.
    .backgroundColor(
      t.fillColor.length > 0
        ? t.fillColor
        : t.color.length > 0
          ? t.color
          : ThemeConstants.BRAND_PRIMARY,
    )
    .borderRadius(ThemeConstants.RADIUS_SM)
    .borderWidth(t.watched ? 2 : 0)
    .borderColor(Color.White)
    .padding({
      left: ThemeConstants.SPACE_SM,
      right: ThemeConstants.SPACE_SM,
      top: ThemeConstants.SPACE_XS,
      bottom: ThemeConstants.SPACE_XS,
    })
    .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
    .opacity(t.hidden ? 0.45 : 1)
    .onClick(() => {
      this.openEditTag(t)
    })
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
        this.editSheetShown = false
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
              .type(InputType.Number)
              .onChange((value: string) => {
                this.editWeight = value
              })
          }
          .width('100%')
          this.DraftSwitchRow($r('app.string.mytags_default_color'), this.editDefaultColor, this.editSubmitting, (value: boolean) => {
            this.editDefaultColor = value
          })
          if (!this.editDefaultColor) {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text($r('app.string.mytags_color'))
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
              Row({ space: ThemeConstants.SPACE_MD }) {
                TextInput({ text: this.editColor, placeholder: '#3377FF' })
                  .height(48)
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
                  .enabled(!this.editSubmitting)
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.editColor = value
                  })
                Column()
                  .width(48)
                  .height(48)
                  .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
                  .backgroundColor(this.normalizedEditColor().length > 0 ? this.normalizedEditColor() : ThemeConstants.BRAND_PRIMARY)
              }
              .width('100%')
            }
            .width('100%')
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
        this.addSheetShown = false
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
              .type(InputType.Number)
              .onChange((value: string) => {
                this.addWeight = value
              })
          }
          .width('100%')
          this.DraftSwitchRow($r('app.string.mytags_default_color'), this.addDefaultColor, this.addSubmitting, (value: boolean) => {
            this.addDefaultColor = value
          })
          if (!this.addDefaultColor) {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text($r('app.string.mytags_color'))
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
              Row({ space: ThemeConstants.SPACE_MD }) {
                TextInput({ text: this.addColor, placeholder: '#3377FF' })
                  .height(48)
                  .fontSize(ThemeConstants.FONT_SIZE_BODY)
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
                  .enabled(!this.addSubmitting)
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.addColor = value
                  })
                Column()
                  .width(48)
                  .height(48)
                  .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
                  .backgroundColor(this.normalizedAddColor().length > 0 ? this.normalizedAddColor() : ThemeConstants.BRAND_PRIMARY)
              }
              .width('100%')
            }
            .width('100%')
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
