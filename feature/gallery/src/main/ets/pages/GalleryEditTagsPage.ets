import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhApiService,
  EhApiPhpService,
  GalleryEditTagsParams,
  TagGroup,
  SimpleTag,
  EhConstants,
  EhErrorText,
  EhCookieStore,
  SecondaryListScaffold,
  GroupedListSection,
  AppModalScaffold,
  AppStrings,
  DiagnosticLogger,
  TagGalleryResult,
  immersiveTitleBar,
  connectSiteMode,
} from 'shared'

/**
 * Protected tag vote entry. Detail tag chips remain tap-to-search; this page owns EH taggallery writes
 * and requires an explicit confirmation before submitting the non-idempotent vote.
 */
@ComponentV2
export struct GalleryEditTagsPage {
  @Local params: GalleryEditTagsParams = new GalleryEditTagsParams();
  @Local tagGroupsData: TagGroup[] = [];
  @Local loading: boolean = false;
  @Local errorMessage: string = '';
  @Local apiuid: string = '';
  @Local apikey: string = '';
  @Local actionSheetShown: boolean = false;
  @Local selectedNamespace: string = '';
  @Local selectedTagText: string = '';
  @Local selectedTagDisplay: string = '';
  @Local selectedTagVote: number = 0;
  @Local submittingTagKey: string = '';
  private scroller: Scroller = new Scroller();

  private async loadTags(): Promise<void> {
    if (this.loading || this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.loading = true
    this.errorMessage = ''
    try {
      const result = await EhApiService.getInstance().getGalleryDetail(
        this.params.gid,
        this.params.token,
        this.params.isEx,
      )
      this.tagGroupsData = result.gallery.tagGroups
      this.apiuid = result.gallery.apiuid
      this.apikey = result.gallery.apikey
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
    } finally {
      this.loading = false
    }
  }

  private titleText(): string {
    return this.params.title.length > 0 ? this.params.title : AppStrings.get('detail_edit_tags')
  }

  private canSubmitTagVote(): boolean {
    return EhCookieStore.getInstance().isLogin() &&
      this.apikey.length > 0 &&
      this.apiuid.length > 0 &&
      this.params.gid.length > 0 &&
      this.params.token.length > 0 &&
      this.submittingTagKey.length === 0
  }

  private selectedTagKey(): string {
    if (this.selectedNamespace.length === 0 || this.selectedTagText.length === 0) {
      return ''
    }
    return `${this.selectedNamespace}:${this.selectedTagText}`
  }

  private openTagActions(namespace: string, tag: SimpleTag): void {
    this.selectedNamespace = namespace
    this.selectedTagText = tag.text
    this.selectedTagDisplay = tag.display()
    this.selectedTagVote = tag.vote
    this.errorMessage = ''
    this.actionSheetShown = true
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
      this.showTagToast($r('app.string.tag_vote_unavailable'))
      return
    }
    this.getUIContext().showAlertDialog({
      title: this.voteActionText(vote),
      message: `${tagKey}`,
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
        this.apikey,
        this.apiuid,
        this.params.gid,
        this.params.token,
        tagKey,
        vote,
      )
      this.applyTagVoteResult(result, previousVote)
      this.actionSheetShown = false
      this.showTagToast(this.voteSuccessText(vote, previousVote))
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'tag_vote_failed', (err as Error).message)
      this.showTagToast($r('app.string.tag_vote_failed'))
    } finally {
      this.submittingTagKey = ''
    }
  }

  private applyTagVoteResult(result: TagGalleryResult, previousVote: number): void {
    const nextGroups: TagGroup[] = []
    this.tagGroupsData.forEach((group: TagGroup) => {
      const nextTags: SimpleTag[] = []
      group.tags.forEach((tag: SimpleTag) => {
        const nextTag: SimpleTag = tag.copy()
        const key: string = `${group.namespace}:${tag.text}`
        if (key === result.tagKey) {
          if ((previousVote > 0 && result.vote < 0) || (previousVote < 0 && result.vote > 0)) {
            nextTag.vote = 0
          } else {
            nextTag.vote = result.vote
          }
        }
        nextTags.push(nextTag)
      })
      nextGroups.push(new TagGroup(group.namespace, nextTags))
    })
    this.tagGroupsData = nextGroups
  }

  private showTagToast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().openToast({ message: message }).catch((_error: Error) => {
      // The tag vote result is already reflected or logged; toast failures are non-critical.
    })
  }

  private tagTextColor(tag: SimpleTag): ResourceColor {
    if (tag.vote > 0) {
      return $r('app.color.tag_vote_up')
    }
    if (tag.vote < 0) {
      return $r('app.color.tag_vote_down')
    }
    return $r('sys.color.font_secondary')
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

  @Builder
  private tagGroups() {
    GroupedListSection() {
      Column({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.gallery_tags'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        ForEach(
          this.tagGroupsData,
          (tg: TagGroup) => {
            Row({ space: ThemeConstants.SPACE_SM }) {
              Text(EhConstants.tagNamespaceLabel(tg.namespace))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_primary'))
                .backgroundColor(EhConstants.tagNamespaceColor(tg.namespace))
                .borderRadius(ThemeConstants.CHIP_RADIUS)
                .textAlign(TextAlign.Center)
                .padding({
                  left: ThemeConstants.SPACE_SM,
                  right: ThemeConstants.SPACE_SM,
                  top: ThemeConstants.CHIP_PADDING_V,
                  bottom: ThemeConstants.CHIP_PADDING_V,
                })
                .constraintSize({ minWidth: 44 })
                .flexShrink(0)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(
                  tg.tags,
                  (tag: SimpleTag) => {
                    Text(tag.display())
                      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                      .fontColor(this.tagTextColor(tag))
                      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
                      .borderRadius(ThemeConstants.CHIP_RADIUS)
                      .padding({
                        left: ThemeConstants.SPACE_SM,
                        right: ThemeConstants.SPACE_SM,
                        top: ThemeConstants.CHIP_PADDING_V,
                        bottom: ThemeConstants.CHIP_PADDING_V,
                      })
                      .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
                      .onClick(() => {
                        this.openTagActions(tg.namespace, tag)
                      })
                  },
                  (tag: SimpleTag) => `${tg.namespace}:${tag.text}`,
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
      .padding(ThemeConstants.SPACE_MD)
    }
  }

  @Builder
  private loadingOrError() {
    if (this.loading) {
      LoadingProgress()
        .width(ThemeConstants.LOADING_SIZE)
        .height(ThemeConstants.LOADING_SIZE)
        .margin({ top: ThemeConstants.SPACE_XL })
    } else if (this.errorMessage.length > 0) {
      GroupedListSection() {
        Text(this.errorMessage)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(ThemeConstants.SPACE_MD)
      }
    }
  }

  @Builder
  private TagVoteAction(label: ResourceStr, vote: number, destructive: boolean = false) {
    ListItem() {
      Row() {
        Text(label)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(destructive ? Color.Red : $r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(this.submittingTagKey.length > 0 ? $r('app.string.common_loading') : '')
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height(48)
      .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
      .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
      .backgroundColor($r('app.color.card_background'))
      .enabled(this.canSubmitTagVote())
      .onClick(() => {
        this.confirmTagVote(vote)
      })
    }
  }

  @Builder
  private TagActionSheet() {
    AppModalScaffold({
      title: $r('app.string.detail_edit_tags'),
      showConfirmAction: false,
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      closeAction: () => {
        this.actionSheetShown = false
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_SM }) {
          Text(this.selectedTagDisplay.length > 0 ? this.selectedTagDisplay : this.selectedTagKey())
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text(this.selectedTagKey())
            .fontSize(ThemeConstants.FONT_SIZE_META)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Text(this.tagVoteLabel())
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          if (!this.canSubmitTagVote()) {
            Text($r('app.string.tag_vote_unavailable'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor(Color.Red)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
      if (this.selectedTagVote === 0) {
        this.TagVoteAction($r('app.string.tag_vote_up'), 1)
        this.TagVoteAction($r('app.string.tag_vote_down'), -1)
      } else if (this.selectedTagVote > 0) {
        this.TagVoteAction($r('app.string.tag_vote_withdraw'), -1, true)
      } else {
        this.TagVoteAction($r('app.string.tag_vote_withdraw'), 1, true)
      }
      if (this.errorMessage.length > 0) {
        ListItem() {
          Text(this.errorMessage)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor(Color.Red)
            .width('100%')
        }
      }
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({ scroller: this.scroller }) {
        if (this.loading || this.errorMessage.length > 0) {
          ListItem() {
            this.loadingOrError()
          }
        }
        if (this.tagGroupsData.length > 0) {
          ListItem() {
            this.tagGroups()
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(this.titleText()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.actionSheetShown, this.TagActionSheet(), {
      detents: [SheetSize.MEDIUM],
      showClose: false,
    })
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryEditTagsParams
      if (p !== undefined) {
        this.params = p
        this.loadTags()
      }
    })
  }
}
