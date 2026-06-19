import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhApiService,
  GalleryEditTagsParams,
  TagGroup,
  SimpleTag,
  EhConstants,
  EhErrorText,
  SecondaryListScaffold,
  GroupedListSection,
  AppStrings,
  immersiveTitleBar,
} from 'shared'

/**
 * Non-destructive tag editing entry. It exposes the entry point and current tags, but intentionally
 * contains no EH write submit until the protected tag-write flow is separately designed.
 */
@ComponentV2
export struct GalleryEditTagsPage {
  @Local params: GalleryEditTagsParams = new GalleryEditTagsParams();
  @Local tagGroupsData: TagGroup[] = [];
  @Local loading: boolean = false;
  @Local errorMessage: string = '';
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
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
    } finally {
      this.loading = false
    }
  }

  private titleText(): string {
    return this.params.title.length > 0 ? this.params.title : AppStrings.get('detail_edit_tags')
  }

  @Builder
  private notice() {
    GroupedListSection() {
      Column({ space: ThemeConstants.SPACE_XS }) {
        Text($r('app.string.detail_edit_tags_readonly_title'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        Text($r('app.string.detail_edit_tags_readonly_desc'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      .width('100%')
      .padding(ThemeConstants.SPACE_MD)
    }
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
                      .fontColor($r('sys.color.font_secondary'))
                      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
                      .borderRadius(ThemeConstants.CHIP_RADIUS)
                      .padding({
                        left: ThemeConstants.SPACE_SM,
                        right: ThemeConstants.SPACE_SM,
                        top: ThemeConstants.CHIP_PADDING_V,
                        bottom: ThemeConstants.CHIP_PADDING_V,
                      })
                      .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
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

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({ scroller: this.scroller }) {
        ListItem() {
          this.notice()
        }
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
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryEditTagsParams
      if (p !== undefined) {
        this.params = p
        this.loadTags()
      }
    })
  }
}
