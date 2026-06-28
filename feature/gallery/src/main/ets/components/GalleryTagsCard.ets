import { common, Want } from '@kit.AbilityKit'
import { vibrator } from '@kit.SensorServiceKit'
import {
  ThemeConstants,
  EhGallery,
  TagGroup,
  SimpleTag,
  EhUsertag,
  EhMytags,
  EhMytagSet,
  EhConstants,
  GroupedListSection,
  ConciseListRow,
  AppModalScaffold,
  AppColorPicker,
  UserTagStore,
  UserTagSignal,
  connectUserTagSignal,
  TagTranslationSettingsState,
  connectTagTranslationSettings,
  TagTranslationService,
  TagTranslationInfo,
  MyTagsTargetService,
  MyTagsTargetResolveResult,
  EhApiService,
  EhApiPhpService,
  TagGalleryResult,
  EhErrorText,
  AppStrings,
  DiagnosticLogger,
  connectSiteMode,
  connectSearchAction,
  appSheetOptions,
} from 'shared'

const HAPTIC_HD_INTENSITY: number = 80
const HAPTIC_FALLBACK_DURATION: number = 30
const TAG_INFO_ACTION_SIZE: number = 32
const TAG_INFO_IMAGE_FALLBACK_RATIO: number = 3 / 4
const TAG_INFO_IMAGE_MIN_RATIO: number = 0.42
const TAG_INFO_IMAGE_MAX_RATIO: number = 1.8
const TAG_INFO_MANAGE_EPOCH_START: number = 0
const TAG_INFO_MANAGE_EDIT: string = 'edit'
const TAG_INFO_MANAGE_TAGSET: string = 'tagset'
const TAG_INFO_MANAGE_ADD: string = 'add'

class TagInfoLinkItem {
  label: string = ''
  url: string = ''
}

class TagInfoImageLoadEvent {
  width?: number
  height?: number
}

@ComponentV2
struct TagInfoIntroImage {
  @Param url: string = '';
  @Local loadedAspectRatio: number = 0;

  private imageSizeMatch(): RegExpExecArray | null {
    const reg: RegExp = /-\d+-(\d+)-(\d+)-[A-Za-z0-9]+(?:_(\d+)|_[A-Za-z]+)?\.[A-Za-z0-9]+(?:[?#].*)?$/
    return reg.exec(this.url)
  }

  private clampAspectRatio(ratio: number): number {
    return Math.min(TAG_INFO_IMAGE_MAX_RATIO, Math.max(TAG_INFO_IMAGE_MIN_RATIO, ratio))
  }

  private sourceAspectRatio(): number {
    if (this.loadedAspectRatio > 0) {
      return this.loadedAspectRatio
    }
    const match: RegExpExecArray | null = this.imageSizeMatch()
    if (match === null) {
      return TAG_INFO_IMAGE_FALLBACK_RATIO
    }
    const width: number = Number.parseInt(match[1], 10)
    const height: number = Number.parseInt(match[2], 10)
    if (width <= 0 || height <= 0) {
      return TAG_INFO_IMAGE_FALLBACK_RATIO
    }
    return this.clampAspectRatio(width / height)
  }

  private updateLoadedAspectRatio(event?: TagInfoImageLoadEvent): void {
    if (event === undefined || event.width === undefined || event.height === undefined) {
      return
    }
    if (event.width <= 0 || event.height <= 0) {
      return
    }
    this.loadedAspectRatio = this.clampAspectRatio(event.width / event.height)
  }

  build() {
    Image(this.url)
    .width('100%')
    .aspectRatio(this.sourceAspectRatio())
    .objectFit(ImageFit.Contain)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
    .clip(true)
    .onComplete((event?: TagInfoImageLoadEvent) => {
      this.updateLoadedAspectRatio(event)
    })
  }
}

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
  @Local infoImages: string[] = [];
  @Local infoEpoch: number = 0;
  @Local submittingTagKey: string = '';
  @Local editSheetShown: boolean = false;
  @Local editSubmitting: boolean = false;
  @Local editError: string = '';
  @Local editTagId: string = '';
  @Local editTagTitle: string = '';
  @Local editTagDisplay: string = '';
  @Local editTagRaw: string = '';
  @Local editApiuid: string = '';
  @Local editApikey: string = '';
  @Local editWatched: boolean = false;
  @Local editHidden: boolean = false;
  @Local editDefaultColor: boolean = true;
  @Local editColor: string = '';
  @Local editWeight: string = '';
  @Local manageSheetKind: string = '';
  @Local tagsetLoading: boolean = false;
  @Local tagsetError: string = '';
  @Local tagsetOptions: EhMytagSet[] = [];
  @Local tagsetResolveEpoch: number = TAG_INFO_MANAGE_EPOCH_START;
  @Local addSubmitting: boolean = false;
  @Local addError: string = '';
  @Local addTagset: string = '';
  @Local addTagTitle: string = '';
  @Local addTagDisplay: string = '';
  @Local addWatched: boolean = true;
  @Local addHidden: boolean = false;
  @Local addDefaultColor: boolean = true;
  @Local addColor: string = '';
  @Local addWeight: string = '10';
  private editSourceTag: EhUsertag | null = null;

  // Member chip background: the user's editable MyTags color, else EH preview fill, else neutral grey.
  // Never namespace.
  chipBg(t: SimpleTag, ns: string): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(ns, t.text)
    if (u !== undefined && u.colorCode.length > 0) {
      return u.colorCode
    }
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

  private tagGroupRenderKey(tg: TagGroup): string {
    let key: string = `${tg.namespace}`
    for (let i = 0; i < tg.tags.length; i++) {
      const tag: SimpleTag = tg.tags[i]
      // vote is part of the key so a vote change (applyTagVote rebuilds the tags) re-renders the chips.
      key = `${key}:${tag.text}:${tag.translat}:${tag.vote}`
    }
    return key
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
    this.infoImages = []
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
        this.tagTranslation.introImageLevel,
      )
      if (epoch !== this.infoEpoch) {
        return
      }
      if (info !== null) {
        this.infoName = info.name
        this.infoIntro = info.intro
        this.infoLinks = info.links
        this.infoImages = info.images
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

  // Active tint for a vote button: green when this is the user's current vote, red for down, else neutral.
  private voteButtonColor(direction: number): ResourceColor {
    if (direction > 0 && this.selectedTagVote > 0) {
      return $r('app.color.tag_vote_up')
    }
    if (direction < 0 && this.selectedTagVote < 0) {
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

  // Toast for the resulting state EH reports back (0 = the vote was withdrawn).
  private voteResultText(resultVote: number): ResourceStr {
    if (resultVote > 0) {
      return $r('app.string.tag_vote_up_success')
    }
    if (resultVote < 0) {
      return $r('app.string.tag_vote_down_success')
    }
    return $r('app.string.tag_vote_withdraw_success')
  }

  // `vote` is the value to send EH (the opposite of the current vote withdraws); `isWithdraw` only
  // drives the dialog wording so tapping an already-active button reads "撤回投票", not "反对/赞成标签".
  private confirmTagVote(vote: number, isWithdraw: boolean): void {
    const tagKey: string = this.selectedTagKey()
    if (tagKey.length === 0 || !this.canSubmitTagVote()) {
      this.showToast($r('app.string.tag_vote_unavailable'))
      return
    }
    this.getUIContext().showAlertDialog({
      title: isWithdraw ? $r('app.string.tag_vote_withdraw') : this.voteActionText(vote),
      message: tagKey,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.submitTagVote(tagKey, vote)
        },
      },
    })
  }

  private async submitTagVote(tagKey: string, vote: number): Promise<void> {
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
        this.selectedTagVote,
      )
      // result.vote is EH's actual resulting state (parsed from the tagpane), not what we sent.
      this.selectedTagVote = result.vote
      this.onTagVoteChanged(this.selectedNamespace, this.selectedTagText, result.vote)
      this.showToast(this.voteResultText(result.vote))
    } catch (err) {
      // infoError is the tag-intro area (TagInfoBody renders it INSTEAD of the 简介). A vote failure
      // must not wipe the intro — surface it as a toast. The usual rejection is EH locking a
      // well-established tag ("locked for further up/downvotes"); name that case so it doesn't read as
      // a generic app failure (which is why "votes always fail" on popular galleries).
      const msg: string = (err as Error).message
      DiagnosticLogger.warn('gallery', 'tag_info_vote_failed', msg)
      const locked: boolean = msg.indexOf('locked for further') >= 0
      this.showToast(locked ? $r('app.string.tag_vote_locked') : $r('app.string.tag_vote_failed'))
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
    const epoch: number = this.tagsetResolveEpoch + 1
    this.tagsetResolveEpoch = epoch
    this.tagsetLoading = true
    this.tagsetError = ''
    this.tagsetOptions = []
    this.editSheetShown = false
    MyTagsTargetService.resolve(connectSiteMode().isEx, tagKey).then((result: MyTagsTargetResolveResult) => {
      if (epoch !== this.tagsetResolveEpoch) {
        return
      }
      this.tagsetLoading = false
      if (result.found && result.tag !== null && result.tag.tagId.length > 0) {
        this.openEditUserTag(result.tag, result.mytags)
        return
      }
      if (result.tagsets.length <= 1) {
        this.openAddUserTag(result.targetTag, result.tagsetId)
        return
      }
      this.tagsetOptions = result.tagsets
      this.manageSheetKind = TAG_INFO_MANAGE_TAGSET
      this.editSheetShown = true
    }).catch((err: Error) => {
      if (epoch !== this.tagsetResolveEpoch) {
        return
      }
      this.tagsetLoading = false
      this.tagsetError = EhErrorText.forUser(err)
      this.manageSheetKind = TAG_INFO_MANAGE_TAGSET
      this.editSheetShown = true
    })
  }

  private openAddUserTag(fullTag: string, tagset: string): void {
    const infoName: string = this.currentInfoNameForFullTag(fullTag)
    this.addSubmitting = false
    this.addError = ''
    this.addTagset = tagset
    this.addTagTitle = fullTag
    this.addTagDisplay = this.localizedFullTagDisplay(fullTag, infoName)
    this.addWatched = true
    this.addHidden = false
    this.addDefaultColor = true
    this.addColor = ''
    this.addWeight = '10'
    this.manageSheetKind = TAG_INFO_MANAGE_ADD
    this.editSheetShown = true
    this.loadAddTagTranslation(fullTag).then(() => {})
  }

  private async loadAddTagTranslation(fullTag: string): Promise<void> {
    if (!this.tagTranslation.enabled) {
      return
    }
    const translated: string = await TagTranslationService.translateFullTagAsync(this.ctx(), fullTag)
    if (this.addTagTitle === fullTag && translated.length > 0) {
      const infoName: string = this.currentInfoNameForFullTag(fullTag)
      this.addTagDisplay = this.localizedFullTagDisplay(fullTag, infoName.length > 0 ? infoName : translated)
    }
  }

  private openEditUserTag(t: EhUsertag, mytags: EhMytags): void {
    this.editSourceTag = t
    this.editSubmitting = false
    this.editError = ''
    this.editTagId = t.tagId
    this.editTagTitle = t.tag
    this.editTagRaw = t.tag
    this.editApiuid = mytags.apiuid.length > 0 ? mytags.apiuid : this.gallery.apiuid
    this.editApikey = mytags.apikey.length > 0 ? mytags.apikey : this.gallery.apikey
    this.editTagDisplay = this.editTitleForUserTag(t)
    this.editWatched = t.watched
    this.editHidden = t.hidden
    this.editDefaultColor = t.defaultColor
    this.editColor = t.defaultColor ? '' : (t.colorCode.length > 0 ? t.colorCode : t.color)
    this.editWeight = t.tagWeight.length > 0 ? t.tagWeight : `${t.weight}`
    this.manageSheetKind = TAG_INFO_MANAGE_EDIT
    this.editSheetShown = true
    this.loadEditTagTranslation(t.tag).then(() => {})
  }

  private editTitleForUserTag(t: EhUsertag): string {
    const infoName: string = this.currentInfoNameForFullTag(t.tag)
    if (infoName.length > 0) {
      return this.localizedFullTagDisplay(t.tag, infoName)
    }
    if (this.tagTranslation.enabled && t.translate.length > 0 && t.translate !== t.tag && t.translate !== t.display) {
      return this.localizedFullTagDisplay(t.tag, t.translate)
    }
    return this.localizedFullTagDisplay(t.tag, '')
  }

  private async loadEditTagTranslation(fullTag: string): Promise<void> {
    if (!this.tagTranslation.enabled) {
      return
    }
    const translated: string = await TagTranslationService.translateFullTagAsync(this.ctx(), fullTag)
    if (this.editTagTitle === fullTag && translated.length > 0) {
      const infoName: string = this.currentInfoNameForFullTag(fullTag)
      this.editTagDisplay = this.localizedFullTagDisplay(fullTag, infoName.length > 0 ? infoName : translated)
    }
  }

  private currentInfoNameForFullTag(fullTag: string): string {
    const name: string = this.infoName.trim()
    if (name.length === 0) {
      return ''
    }
    const selected: string = MyTagsTargetService.normalizeFullTag(this.selectedTagKey())
    const target: string = MyTagsTargetService.normalizeFullTag(fullTag)
    return selected.length > 0 && selected === target ? name : ''
  }

  private localizedFullTagDisplay(fullTag: string, localized: string): string {
    const idx: number = fullTag.indexOf(':')
    const namespace: string = idx > 0 ? fullTag.substring(0, idx) : this.selectedNamespace
    const key: string = idx > 0 ? fullTag.substring(idx + 1) : fullTag
    const text: string = localized.trim().length > 0 ? localized.trim() : key
    const label: string = this.localizedNamespaceLabel(namespace)
    return label.length > 0 ? `${label}:${text}` : text
  }

  private localizedNamespaceLabel(namespace: string): string {
    switch (EhConstants.expandNamespace(namespace)) {
      case 'artist':
        return AppStrings.get('tag_ns_artist')
      case 'female':
        return AppStrings.get('tag_ns_female')
      case 'male':
        return AppStrings.get('tag_ns_male')
      case 'parody':
        return AppStrings.get('tag_ns_parody')
      case 'character':
        return AppStrings.get('tag_ns_character')
      case 'group':
        return AppStrings.get('tag_ns_group')
      case 'language':
        return AppStrings.get('tag_ns_language')
      case 'reclass':
        return AppStrings.get('tag_ns_reclass')
      case 'cosplayer':
        return AppStrings.get('tag_ns_cosplayer')
      case 'misc':
        return AppStrings.get('tag_ns_misc')
      case 'mixed':
        return AppStrings.get('tag_ns_mixed')
      case 'location':
        return AppStrings.get('tag_ns_location')
      case 'other':
        return AppStrings.get('tag_ns_other')
      case 'uploader':
        return AppStrings.get('tag_ns_uploader')
      case 'temp':
        return AppStrings.get('tag_ns_temp')
      default:
        return EhConstants.expandNamespace(namespace)
    }
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
      this.editApikey.length > 0 &&
      this.editApiuid.length > 0 &&
      !this.editSubmitting
  }

  private canSubmitAdd(): boolean {
    return this.addTagTitle.length > 0 && this.addTagset.length > 0 && !this.addSubmitting
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
        this.editApikey,
        this.editApiuid,
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

  private async submitAdd(): Promise<void> {
    if (!this.canSubmitAdd()) {
      return
    }
    this.addSubmitting = true
    this.addError = ''
    try {
      await EhApiService.getInstance().addUserTag({
        isEx: connectSiteMode().isEx,
        tagName: this.addTagTitle,
        tagset: this.addTagset,
        color: this.normalizedAddColor(),
        weight: this.addWeight,
        watched: this.addWatched,
        hidden: this.addHidden,
      })
      const refreshed: EhMytags = await EhApiService.getInstance().getMyTags(connectSiteMode().isEx, this.addTagset)
      UserTagStore.getInstance().setTags(refreshed.tags)
      this.tagSig.version = this.tagSig.version + 1
      this.editSheetShown = false
      this.showToast($r('app.string.mytags_add_success'))
    } catch (err) {
      const e = err as Error
      this.addError = e.message
      DiagnosticLogger.warn('gallery', 'tag_info_mytag_add_failed', e.message)
    }
    this.addSubmitting = false
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

  private chooseTagsetForAdd(tagsetId: string): void {
    const tagKey: string = MyTagsTargetService.normalizeFullTag(this.selectedTagKey())
    if (tagKey.length === 0 || tagsetId.length === 0) {
      return
    }
    this.openAddUserTag(tagKey, tagsetId)
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

  private markdownBodyLines(markdown: string): string[] {
    let text: string = markdown.replace(/\r\n/g, '\n')
    text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '')
    text = text.replace(/^#{1,6}\s*/gm, '')
    text = text.replace(/\*\*([^*]+)\*\*/g, '$1')
    text = text.replace(/__([^_]+)__/g, '$1')
    text = text.replace(/`([^`]+)`/g, '$1')
    text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1')
    text = text.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim()
    if (text.length === 0) {
      return []
    }
    return text.split('\n').map((line: string): string => line.trim()).filter((line: string): boolean => line.length > 0)
  }

  private markdownLinks(markdown: string): TagInfoLinkItem[] {
    const links: TagInfoLinkItem[] = []
    const reg: RegExp = /\[([^\]]+)\]\(([^)]+)\)/g
    let match: RegExpExecArray | null = reg.exec(markdown)
    while (match !== null) {
      const item: TagInfoLinkItem = new TagInfoLinkItem()
      item.label = match[1].trim()
      item.url = match[2].trim()
      if (item.label.length > 0 || item.url.length > 0) {
        links.push(item)
      }
      match = reg.exec(markdown)
    }
    if (links.length === 0 && markdown.trim().length > 0) {
      const item: TagInfoLinkItem = new TagInfoLinkItem()
      item.label = markdown.trim()
      links.push(item)
    }
    return links
  }

  private openTagInfoLink(url: string): void {
    if (url.length === 0) {
      return
    }
    const want: Want = { action: 'ohos.want.action.viewData', uri: url }
    this.ctx().startAbility(want).catch((_error: Error) => {
      this.getUIContext().getPromptAction().openToast({ message: url }).catch((_toastError: Error) => {})
    })
  }

  @Builder
  private InfoMarkdownText(title: ResourceStr, markdown: string) {
    if (this.markdownBodyLines(markdown).length > 0) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_XS }) {
          Text(title)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          ForEach(this.markdownBodyLines(markdown), (line: string) => {
            Text(line)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }, (line: string) => line)
        }
        .width('100%')
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  private InfoLinks(title: ResourceStr, markdown: string) {
    if (markdown.trim().length > 0) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_XS }) {
          Text(title)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          ForEach(this.markdownLinks(markdown), (item: TagInfoLinkItem) => {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text(item.label.length > 0 ? item.label : item.url)
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontColor(item.url.length > 0 ? ThemeConstants.TEXT_LINK : $r('sys.color.font_secondary'))
                .width('100%')
              if (item.url.length > 0 && item.url !== item.label) {
                Text(item.url)
                  .fontSize(ThemeConstants.FONT_SIZE_META)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.openTagInfoLink(item.url)
            })
          }, (item: TagInfoLinkItem) => `${item.label}:${item.url}`)
        }
        .width('100%')
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  private InfoImages() {
    if (this.infoImages.length > 0) {
      ListItem() {
        Row({ space: ThemeConstants.SPACE_SM }) {
          this.InfoImageColumn(0)
          this.InfoImageColumn(1)
        }
        .alignItems(VerticalAlign.Top)
        .width('100%')
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  private InfoImageColumn(remainder: number) {
    Column({ space: ThemeConstants.SPACE_SM }) {
      ForEach(this.infoImages, (url: string, index: number) => {
        if (index % 2 === remainder) {
          TagInfoIntroImage({ url: url })
        }
      }, (url: string, index: number) => `${index}:${url}`)
    }
    .layoutWeight(1)
  }

  @Builder
  private TagInfoHeader() {
    ListItem() {
      Row({ space: ThemeConstants.SPACE_MD }) {
        Column({ space: ThemeConstants.SPACE_XS }) {
          Text(this.infoName.length > 0 ? this.infoName : this.selectedTagDisplay)
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.selectedTagKey())
            .fontSize(ThemeConstants.FONT_SIZE_META)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
        .layoutWeight(1)

        Row({ space: ThemeConstants.SPACE_XS }) {
          // Single thumbs-up / thumbs-down toggles, tinted when this is the user's current vote; tapping
          // the active one withdraws. EH's returned state (parsed in submitTagVote) is the source of
          // truth, so the state needs no separate "已赞成/已反对" label.
          this.TagInfoActionButton(
            $r('sys.symbol.hand_thumbsup'),
            $r('app.string.tag_vote_up_short'),
            1,
            this.submittingTagKey.length === 0,
            () => {
              // EH model: re-sending the same direction is a no-op; the OPPOSITE withdraws to 0. So to
              // clear an existing upvote, send -1; otherwise send +1. isWithdraw drives the dialog wording.
              this.confirmTagVote(this.selectedTagVote > 0 ? -1 : 1, this.selectedTagVote > 0)
            },
          )
          this.TagInfoActionButton(
            $r('sys.symbol.hand_thumbsdown'),
            $r('app.string.tag_vote_down_short'),
            -1,
            this.submittingTagKey.length === 0,
            () => {
              this.confirmTagVote(this.selectedTagVote < 0 ? 1 : -1, this.selectedTagVote < 0)
            },
          )
          this.TagInfoManageActionButton(this.submittingTagKey.length === 0)
        }
        .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
    }
  }

  @Builder
  private TagInfoActionButton(
    icon: Resource,
    label: Resource,
    direction: number,
    enabled: boolean,
    action: () => void,
  ) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        // Read selectedTagVote INSIDE the builder — a @Builder value param wouldn't re-render the tint.
        .fontColor([this.voteButtonColor(direction)])
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .width(TAG_INFO_ACTION_SIZE)
    .height(TAG_INFO_ACTION_SIZE)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private TagInfoManageActionButton(enabled: boolean) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.bookmark'))
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .width(TAG_INFO_ACTION_SIZE)
    .height(TAG_INFO_ACTION_SIZE)
    .enabled(enabled)
    .accessibilityText($r('app.string.tag_info_manage_short'))
    .onClick(() => {
      this.openMyTagsForSelectedTag()
    })
    .bindSheet($$this.editSheetShown, this.ManageUserTagSheet(), appSheetOptions({
      showClose: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
    }))
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
      this.InfoMarkdownText($r('app.string.tag_info_intro'), this.infoIntro)
      this.InfoLinks($r('app.string.tag_info_links'), this.infoLinks)
      this.InfoImages()
      if (this.infoIntro.length === 0 && this.infoLinks.length === 0 && this.infoImages.length === 0) {
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
  private MyTagTitleBlock(title: string, raw: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(title.length > 0 ? title : raw)
        .fontSize(ThemeConstants.FONT_SIZE_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (raw.length > 0 && raw !== title) {
        Text(raw)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private TagsetSelectSheet() {
    AppModalScaffold({
      title: $r('app.string.tag_info_select_tagset_title'),
      showConfirmAction: false,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      closeAction: () => {
        this.editSheetShown = false
      },
    }) {
      if (this.tagsetLoading) {
        ListItem() {
          Text($r('app.string.common_loading'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      } else if (this.tagsetError.length > 0) {
        ListItem() {
          Text(this.tagsetError)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(Color.Red)
            .width('100%')
        }
      } else {
        ListItem() {
          GroupedListSection() {
            ForEach(this.tagsetOptions, (tagset: EhMytagSet, index: number) => {
              ConciseListRow({
                title: tagset.name,
                trailingText: `${tagset.count}`,
                trailingDropdown: false,
                showChevron: true,
                action: () => {
                  this.chooseTagsetForAdd(tagset.tagsetId)
                },
              })
              if (index < this.tagsetOptions.length - 1) {
                this.TagsetRowDivider()
              }
            }, (tagset: EhMytagSet) => tagset.tagsetId)
          }
        }
      }
    }
  }

  @Builder
  private TagsetRowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private EditUserTagSheet() {
    AppModalScaffold({
      title: $r('app.string.mytags_edit_title'),
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
          this.MyTagTitleBlock(this.editTagDisplay, this.editTagRaw.length > 0 ? this.editTagRaw : this.editTagTitle)
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
  private AddUserTagSheet() {
    AppModalScaffold({
      title: $r('app.string.mytags_add_title'),
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.mytags_add'),
      confirmEnabled: this.canSubmitAdd(),
      confirmLoading: this.addSubmitting,
      closeAction: () => {
        this.editSheetShown = false
      },
      confirmAction: () => {
        this.confirmSubmitAdd()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          this.MyTagTitleBlock(this.addTagDisplay, this.addTagTitle)
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
  private ManageUserTagSheet() {
    if (this.manageSheetKind === TAG_INFO_MANAGE_EDIT) {
      this.EditUserTagSheet()
    } else if (this.manageSheetKind === TAG_INFO_MANAGE_ADD) {
      this.AddUserTagSheet()
    } else if (this.manageSheetKind === TAG_INFO_MANAGE_TAGSET) {
      this.TagsetSelectSheet()
    }
  }

  @Builder
  private TagInfoSheet() {
    Column() {
      AppModalScaffold({
        title: $r('app.string.tag_info_title'),
        showConfirmAction: false,
        closeInMenu: true,
        contentHorizontalPadding: ThemeConstants.SPACE_LG,
        contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
        closeAction: () => {
          this.tagInfoShown = false
        },
      }) {
        this.TagInfoHeader()
        this.TagInfoBody()
      }
    }
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
                    (t: SimpleTag) =>
                      `${this.tagSig.version}:${tg.namespace}:${t.text}:${t.translat}:${t.vote}`,
                  )
                }.layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            },
            (tg: TagGroup) => this.tagGroupRenderKey(tg),
          )
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .bindSheet($$this.tagInfoShown, this.TagInfoSheet(), appSheetOptions({
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      showClose: false,
    }))
  }
}
