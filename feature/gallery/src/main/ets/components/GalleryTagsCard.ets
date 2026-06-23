import { common } from '@kit.AbilityKit'
import { vibrator } from '@kit.SensorServiceKit'
import {
  ThemeConstants,
  EhGallery,
  TagGroup,
  SimpleTag,
  EhUsertag,
  EhConstants,
  GroupedListSection,
  AppModalScaffold,
  AppColorPicker,
  UserTagStore,
  UserTagSignal,
  connectUserTagSignal,
  TagTranslationSettingsState,
  connectTagTranslationSettings,
  TagTranslationService,
  TagTranslationInfo,
  EhApiPhpService,
  TagGalleryResult,
  EhErrorText,
  DiagnosticLogger,
  MyTagsPageParams,
  connectNavStack,
  connectSiteMode,
  connectSearchAction,
} from 'shared'

const HAPTIC_HD_INTENSITY: number = 80
const HAPTIC_FALLBACK_DURATION: number = 30
const TAG_INFO_ACTION_HEIGHT: number = 64

/**
 * Detail-page tag groups (namespace label + wrapped chips), one row per namespace. Shares
 * the GroupedListSection card chrome with the header/preview cards.
 *
 * eros_fe TagGroupItem: the NAMESPACE label is namespace-colored (tagColorTagType), while each MEMBER
 * chip takes the user's own per-tag color (getColorCode), neutral grey when uncolored — never namespace.
 */
@ComponentV2
export struct GalleryTagsCard {
  @Require @Param gallery: EhGallery;
  @Event onTagVoteChanged: (namespace: string, tagText: string, vote: number) => void =
    (_namespace: string, _tagText: string, _vote: number) => {};
  // Reactive bump from the usertag loader; read in the chip key so chips re-color on a late My Tags load.
  private tagSig: UserTagSignal = connectUserTagSignal();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local tagInfoShown: boolean = false;
  @Local selectedNamespace: string = '';
  @Local selectedTagText: string = '';
  @Local selectedTagDisplay: string = '';
  @Local selectedTagVote: number = 0;
  @Local infoLoading: boolean = false;
  @Local infoError: string = '';
  @Local infoName: string = '';
  @Local infoIntro: string = '';
  @Local infoLinks: string = '';
  @Local infoEpoch: number = 0;
  @Local submittingTagKey: string = '';
  @Local editSheetShown: boolean = false;
  @Local editSubmitting: boolean = false;
  @Local editError: string = '';
  @Local editTagId: string = '';
  @Local editTagTitle: string = '';
  @Local editTagDisplay: string = '';
  @Local editWatched: boolean = false;
  @Local editHidden: boolean = false;
  @Local editDefaultColor: boolean = true;
  @Local editColor: string = '';
  @Local editWeight: string = '';
  private editSourceTag: EhUsertag | null = null;

  // Member chip background: the user's own fill color for this tag, else neutral grey. Never namespace.
  chipBg(t: SimpleTag, ns: string): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(ns, t.text)
    if (u !== undefined && u.fillColor.length > 0) {
      return u.fillColor
    }
    return $r('sys.color.ohos_id_color_sub_background')
  }

  // Member chip text color. The user's per-gallery tag VOTE wins first (eros_fe colors the tag text
  // green when upvoted / red when downvoted, ahead of any custom colour); then the user's own EH-chosen
  // tag text colour; then neutral secondary. Read-only — tapping a chip searches, it does not vote.
  chipText(t: SimpleTag, ns: string): ResourceColor {
    if (t.vote > 0) {
      return $r('app.color.tag_vote_up')
    }
    if (t.vote < 0) {
      return $r('app.color.tag_vote_down')
    }
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(ns, t.text)
    if (u !== undefined && u.textColor.length > 0) {
      return u.textColor
    }
    return $r('sys.color.font_secondary')
  }

  private searchTag(ns: string, t: SimpleTag): void {
    const query: string = EhConstants.exactTagSearchQuery(ns, t.text)
    if (query.length === 0) {
      return
    }
    connectSearchAction().publishQuery(query)
  }

  private tagLabel(t: SimpleTag): string {
    return this.tagTranslation.enabled ? t.display() : t.text
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private selectedTagKey(): string {
    if (this.selectedNamespace.length === 0 || this.selectedTagText.length === 0) {
      return ''
    }
    return `${this.selectedNamespace}:${this.selectedTagText}`
  }

  private triggerLongPressHaptic(): void {
    try {
      if (vibrator.isHdHapticSupported()) {
        vibrator.startVibration(
          {
            type: 'preset',
            effectId: 'haptic.effect.soft',
            count: 1,
            intensity: HAPTIC_HD_INTENSITY,
          },
          { usage: 'physicalFeedback' },
        )
      } else {
        vibrator.startVibration(
          {
            type: 'time',
            duration: HAPTIC_FALLBACK_DURATION,
          },
          { usage: 'physicalFeedback' },
        )
      }
    } catch (_error) {}
  }

  private openTagInfo(ns: string, t: SimpleTag): void {
    this.triggerLongPressHaptic()
    this.selectedNamespace = ns
    this.selectedTagText = t.text
    this.selectedTagDisplay = this.tagLabel(t)
    this.selectedTagVote = t.vote
    this.infoName = ''
    this.infoIntro = ''
    this.infoLinks = ''
    this.infoError = ''
    this.tagInfoShown = true
    const epoch: number = this.infoEpoch + 1
    this.infoEpoch = epoch
    this.loadTagInfo(epoch)
  }

  private async loadTagInfo(epoch: number): Promise<void> {
    this.infoLoading = true
    this.infoError = ''
    try {
      const info: TagTranslationInfo | null = await TagTranslationService.lookupTagInfo(
        this.ctx(),
        this.selectedNamespace,
        this.selectedTagText,
      )
      if (epoch !== this.infoEpoch) {
        return
      }
      if (info !== null) {
        this.infoName = info.name
        this.infoIntro = info.intro
        this.infoLinks = info.links
      }
    } catch (err) {
      if (epoch === this.infoEpoch) {
        this.infoError = EhErrorText.forUser(err)
      }
    } finally {
      if (epoch === this.infoEpoch) {
        this.infoLoading = false
      }
    }
  }

  private tagVoteLabel(): ResourceStr {
    if (this.selectedTagVote > 0) {
      return $r('app.string.tag_vote_current_up')
    }
    if (this.selectedTagVote < 0) {
      return $r('app.string.tag_vote_current_down')
    }
    return $r('app.string.tag_vote_current_none')
  }

  private tagVoteColor(): ResourceColor {
    if (this.selectedTagVote > 0) {
      return $r('app.color.tag_vote_up')
    }
    if (this.selectedTagVote < 0) {
      return $r('app.color.tag_vote_down')
    }
    return $r('sys.color.font_secondary')
  }

  private canSubmitTagVote(): boolean {
    return this.gallery.apikey.length > 0 &&
      this.gallery.apiuid.length > 0 &&
      this.gallery.gid.length > 0 &&
      this.gallery.token.length > 0 &&
      this.submittingTagKey.length === 0
  }

  private voteActionText(vote: number): ResourceStr {
    return vote > 0 ? $r('app.string.tag_vote_up') : $r('app.string.tag_vote_down')
  }

  private voteSuccessText(vote: number, previousVote: number): ResourceStr {
    if ((previousVote > 0 && vote < 0) || (previousVote < 0 && vote > 0)) {
      return $r('app.string.tag_vote_withdraw_success')
    }
    return vote > 0 ? $r('app.string.tag_vote_up_success') : $r('app.string.tag_vote_down_success')
  }

  private confirmTagVote(vote: number): void {
    const tagKey: string = this.selectedTagKey()
    if (tagKey.length === 0 || !this.canSubmitTagVote()) {
      this.showToast($r('app.string.tag_vote_unavailable'))
      return
    }
    this.getUIContext().showAlertDialog({
      title: this.voteActionText(vote),
      message: tagKey,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.submitTagVote(tagKey, vote, this.selectedTagVote)
        },
      },
    })
  }

  private async submitTagVote(tagKey: string, vote: number, previousVote: number): Promise<void> {
    if (this.submittingTagKey.length > 0) {
      return
    }
    this.submittingTagKey = tagKey
    try {
      const result: TagGalleryResult = await EhApiPhpService.tagGallery(
        EhConstants.baseUrl(connectSiteMode().isEx),
        this.gallery.apikey,
        this.gallery.apiuid,
        this.gallery.gid,
        this.gallery.token,
        tagKey,
        vote,
      )
      const nextVote: number =
        (previousVote > 0 && result.vote < 0) || (previousVote < 0 && result.vote > 0)
          ? 0
          : result.vote
      this.selectedTagVote = nextVote
      this.onTagVoteChanged(this.selectedNamespace, this.selectedTagText, nextVote)
      this.showToast(this.voteSuccessText(vote, previousVote))
    } catch (err) {
      this.infoError = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'tag_info_vote_failed', (err as Error).message)
      this.showToast($r('app.string.tag_vote_failed'))
    } finally {
      this.submittingTagKey = ''
    }
  }

  private showToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {})
  }

  private openMyTagsForSelectedTag(): void {
    const tagKey: string = this.selectedTagKey()
    if (tagKey.length === 0) {
      return
    }
    const existing: EhUsertag | undefined = UserTagStore.getInstance().lookup(this.selectedNamespace, this.selectedTagText)
    if (existing !== undefined && existing.tagId.length > 0) {
      this.openEditUserTag(existing)
      return
    }
    connectNavStack().stack.pushPathByName('MyTags', new MyTagsPageParams('', tagKey))
  }

  private openEditUserTag(t: EhUsertag): void {
    this.editSourceTag = t
    this.editSubmitting = false
    this.editError = ''
    this.editTagId = t.tagId
    this.editTagTitle = t.tag
    this.editTagDisplay = t.translate.length > 0 && this.tagTranslation.enabled ? t.translate : (t.display.length > 0 ? t.display : t.tag)
    this.editWatched = t.watched
    this.editHidden = t.hidden
    this.editDefaultColor = t.defaultColor
    this.editColor = t.defaultColor ? '' : (t.colorCode.length > 0 ? t.colorCode : t.color)
    this.editWeight = t.tagWeight.length > 0 ? t.tagWeight : `${t.weight}`
    this.editSheetShown = true
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

  private canSubmitEdit(): boolean {
    return this.editTagId.length > 0 &&
      this.gallery.apikey.length > 0 &&
      this.gallery.apiuid.length > 0 &&
      !this.editSubmitting
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

  private async submitEdit(): Promise<void> {
    if (!this.canSubmitEdit()) {
      return
    }
    this.editSubmitting = true
    this.editError = ''
    const color: string = this.normalizedEditColor()
    try {
      await EhApiPhpService.setUserTag(
        EhConstants.baseUrl(connectSiteMode().isEx),
        this.gallery.apikey,
        this.gallery.apiuid,
        this.editTagId,
        this.editWatched,
        this.editHidden,
        color,
        this.editWeight,
      )
      this.applyEditedUserTag(color)
      this.editSheetShown = false
      this.showToast($r('app.string.mytags_save_success'))
    } catch (err) {
      const e = err as Error
      this.editError = e.message
      DiagnosticLogger.warn('gallery', 'tag_info_mytag_save_failed', e.message)
    }
    this.editSubmitting = false
  }

  private applyEditedUserTag(color: string): void {
    const t: EhUsertag | null = this.editSourceTag
    if (t === null) {
      return
    }
    t.watched = this.editWatched
    t.hidden = this.editHidden
    t.defaultColor = this.editDefaultColor
    t.colorCode = color
    t.color = color
    t.fillColor = color
    t.tagWeight = this.editWeight
    const weight: number = Number.parseInt(this.editWeight, 10)
    if (!Number.isNaN(weight)) {
      t.weight = weight
    }
    this.tagSig.version = this.tagSig.version + 1
  }

  @Builder
  private InfoText(title: ResourceStr, body: string) {
    if (body.trim().length > 0) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_XS }) {
          Text(title)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text(body)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  private TagInfoHeader() {
    ListItem() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text(this.infoName.length > 0 ? this.infoName : this.selectedTagDisplay)
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        Row() {
          Text(this.selectedTagKey())
            .fontSize(ThemeConstants.FONT_SIZE_META)
            .fontColor($r('sys.color.font_secondary'))
          if (this.selectedTagVote !== 0) {
            Text(this.tagVoteLabel())
              .fontSize(ThemeConstants.FONT_SIZE_META)
              .fontColor(this.tagVoteColor())
              .padding({ left: ThemeConstants.SPACE_SM })
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
    }
  }

  @Builder
  private TagInfoBody() {
    if (this.infoLoading) {
      ListItem() {
        Text($r('app.string.common_loading'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
    } else if (this.infoError.length > 0) {
      ListItem() {
        Text(this.infoError)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor(Color.Red)
          .width('100%')
      }
    } else {
      this.InfoText($r('app.string.tag_info_intro'), this.infoIntro)
      this.InfoText($r('app.string.tag_info_links'), this.infoLinks)
      if (this.infoIntro.length === 0 && this.infoLinks.length === 0) {
        ListItem() {
          Text($r('app.string.tag_info_empty'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
    }
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
  private EditUserTagSheet() {
    AppModalScaffold({
      title: $r('app.string.mytags_edit_title'),
      includeKeyboardPadding: true,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.mytags_save'),
      confirmEnabled: this.canSubmitEdit(),
      confirmLoading: this.editSubmitting,
      closeAction: () => {
        this.editSheetShown = false
      },
      confirmAction: () => {
        this.confirmSubmitEdit()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Text(this.editTagDisplay.length > 0 ? this.editTagDisplay : this.editTagTitle)
            .fontSize(ThemeConstants.FONT_SIZE_HEADING)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  private TagInfoSheet() {
    Column() {
      AppModalScaffold({
        title: $r('app.string.tag_info_title'),
        showConfirmAction: false,
        closeInMenu: true,
        footerReserveHeight: TAG_INFO_ACTION_HEIGHT + ThemeConstants.SPACE_LG,
        showFooterActionOne: true,
        footerActionOneText: this.selectedTagVote === 0 ? $r('app.string.tag_vote_up_short') : $r('app.string.tag_vote_withdraw_short'),
        footerActionOneIcon: this.selectedTagVote === 0 ? $r('sys.symbol.hand_thumbsup') : $r('sys.symbol.arrow_counterclockwise'),
        footerActionOneColor: $r('sys.color.font_secondary'),
        footerActionOneEnabled: this.submittingTagKey.length === 0,
        showFooterActionTwo: this.selectedTagVote === 0,
        footerActionTwoText: $r('app.string.tag_vote_down_short'),
        footerActionTwoIcon: $r('sys.symbol.hand_thumbsdown'),
        footerActionTwoColor: $r('sys.color.font_secondary'),
        footerActionTwoEnabled: this.submittingTagKey.length === 0,
        showFooterActionThree: true,
        footerActionThreeText: $r('app.string.tag_info_manage_short'),
        footerActionThreeIcon: $r('sys.symbol.bookmark'),
        footerActionThreeColor: $r('sys.color.font_secondary'),
        footerActionThreeEnabled: this.submittingTagKey.length === 0,
        contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
        closeAction: () => {
          this.tagInfoShown = false
        },
        footerActionOne: () => {
          if (this.selectedTagVote === 0) {
            this.confirmTagVote(1)
          } else if (this.selectedTagVote > 0) {
            this.confirmTagVote(-1)
          } else {
            this.confirmTagVote(1)
          }
        },
        footerActionTwo: () => {
          this.confirmTagVote(-1)
        },
        footerActionThree: () => {
          this.openMyTagsForSelectedTag()
        },
      }) {
        this.TagInfoHeader()
        this.TagInfoBody()
      }
    }
    .bindSheet($$this.editSheetShown, this.EditUserTagSheet(), {
      detents: [SheetSize.LARGE],
      showClose: false,
    })
  }

  build() {
    Column() {
      GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
        Column({ space: ThemeConstants.SPACE_SM }) {
          // Section header (eros_fe MiniTitle "Tags") — the tags card was the only lower section missing
          // its title, breaking parity with eros_fe and with NextE's own Comments/Previews card chrome.
          Text($r('app.string.gallery_tags'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          ForEach(
            this.gallery.tagGroups,
            (tg: TagGroup) => {
              Row({ space: ThemeConstants.SPACE_SM }) {
                // The NAMESPACE HEADER carries the namespace color (eros_fe colors the type header,
                // not the members) and its LOCALIZED label (eros_fe translateTagType: 作者/女性/原作…),
                // not the raw English word; a fixed-width pill keeps rows aligned like a color legend.
                Text(EhConstants.tagNamespaceLabel(tg.namespace))
                  .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                  .lineHeight(ThemeConstants.CHIP_LINE_HEIGHT)
                  .fontColor($r('sys.color.font_primary'))
                  .backgroundColor(EhConstants.tagNamespaceColor(tg.namespace))
                  .borderRadius(ThemeConstants.CHIP_RADIUS)
                  .textAlign(TextAlign.Center)
                  .padding({ left: 6, right: 6, top: ThemeConstants.CHIP_PADDING_V, bottom: ThemeConstants.CHIP_PADDING_V })
                  .constraintSize({ minWidth: 44 })
                  .flexShrink(0)
                  .maxLines(1)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(
                    tg.tags,
                    (t: SimpleTag) => {
                      // Neutral grey unless the USER colored this exact tag (eros_fe getColorCode).
                      Text(this.tagLabel(t))
                        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                        .lineHeight(ThemeConstants.CHIP_LINE_HEIGHT)
                        .fontColor(this.chipText(t, tg.namespace))
                        .backgroundColor(this.chipBg(t, tg.namespace))
                        .borderRadius(ThemeConstants.CHIP_RADIUS)
                        .padding({ left: 8, right: 8, top: ThemeConstants.CHIP_PADDING_V, bottom: ThemeConstants.CHIP_PADDING_V })
                        .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
                        .onClick(() => {
                          this.searchTag(tg.namespace, t)
                        })
                        .gesture(
                          LongPressGesture({ repeat: false, duration: 500 })
                            .onAction(() => {
                              this.openTagInfo(tg.namespace, t)
                            }),
                        )
                    },
                    // version in the key subscribes the card + re-colors chips on a late My Tags load.
                    (t: SimpleTag) => `${this.tagSig.version}:${tg.namespace}:${t.text}`,
                  )
                }.layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            },
            (tg: TagGroup) => tg.namespace,
          )
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .bindSheet($$this.tagInfoShown, this.TagInfoSheet(), {
      detents: [SheetSize.LARGE],
      showClose: false,
    })
  }
}
