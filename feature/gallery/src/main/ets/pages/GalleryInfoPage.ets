import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhConstants,
  EhGallery,
  GalleryInfoParams,
  SecondaryListScaffold,
  GroupedListSection,
  ConciseListRow,
  AppStrings,
  immersiveTitleBar,
} from 'shared'

/**
 * Full read-only gallery metadata page. eros_fe exposes this from the detail info bar as
 * `GalleryInfoPage`; NextE keeps the same information set but renders it as native HDS rows.
 */
@ComponentV2
export struct GalleryInfoPage {
  @Local params: GalleryInfoParams = new GalleryInfoParams();
  private scroller: Scroller = new Scroller();

  private gallery(): EhGallery {
    return this.params.gallery
  }

  private galleryUrl(): string {
    const g: EhGallery = this.gallery()
    if (g.url.length > 0) {
      return g.url
    }
    if (g.gid.length === 0 || g.token.length === 0) {
      return ''
    }
    const base: string = this.params.isEx ? EhConstants.EX_BASE_URL : EhConstants.EH_BASE_URL
    return `${base}/g/${g.gid}/${g.token}/`
  }

  private titleText(): string {
    if (this.params.title.length > 0) {
      return this.params.title
    }
    if (this.gallery().title().length > 0) {
      return this.gallery().title()
    }
    return AppStrings.get('detail_info')
  }

  private favoritedText(): string {
    return this.gallery().favcat.length > 0 ? AppStrings.get('common_yes') : AppStrings.get('common_no')
  }

  private ratingText(): string {
    const g: EhGallery = this.gallery()
    if (g.rating <= 0) {
      return ''
    }
    return g.rating.toFixed(2)
  }

  @Builder
  private infoRow(label: ResourceStr, value: string) {
    ConciseListRow({
      title: label,
      subtitle: value,
      showChevron: false,
    })
  }

  @Builder
  private divider() {
    Divider()
      .color($r('sys.color.comp_divider'))
      .margin({ left: ThemeConstants.LIST_ROW_TEXT_INDENT })
  }

  @Builder
  private InfoSection() {
    GroupedListSection() {
      this.infoRow($r('app.string.detail_info_gid'), this.gallery().gid)
      this.divider()
      this.infoRow($r('app.string.detail_info_token'), this.gallery().token)
      this.divider()
      this.infoRow($r('app.string.detail_info_url'), this.galleryUrl())
      this.divider()
      this.infoRow($r('app.string.detail_info_title'), this.gallery().englishTitle)
      this.divider()
      this.infoRow($r('app.string.detail_info_jpn_title'), this.gallery().japaneseTitle)
      this.divider()
      this.infoRow($r('app.string.detail_info_thumb'), this.gallery().thumbUrl)
      this.divider()
      this.infoRow($r('app.string.detail_info_category'), this.gallery().category)
      this.divider()
      this.infoRow($r('app.string.detail_info_uploader'), this.gallery().uploader)
      this.divider()
      this.infoRow($r('app.string.detail_info_posted'), this.gallery().postTime)
      this.divider()
      this.infoRow($r('app.string.detail_info_language'), this.gallery().language)
      this.divider()
      this.infoRow($r('app.string.detail_info_pages'), this.gallery().fileCount)
      this.divider()
      this.infoRow($r('app.string.detail_info_size'), this.gallery().fileSizeText)
      this.divider()
      this.infoRow($r('app.string.detail_info_visible'), this.gallery().visible)
      this.divider()
      this.infoRow($r('app.string.detail_info_parent'), this.gallery().parentTitle)
      this.divider()
      this.infoRow($r('app.string.detail_info_favorite_count'), this.gallery().favoritedCount)
      this.divider()
      this.infoRow($r('app.string.detail_info_favorited'), this.favoritedText())
      this.divider()
      this.infoRow($r('app.string.detail_info_favorite'), this.gallery().favTitle)
      this.divider()
      this.infoRow($r('app.string.detail_info_rating_count'), this.gallery().ratingCount)
      this.divider()
      this.infoRow($r('app.string.detail_info_rating'), this.ratingText())
      this.divider()
      this.infoRow($r('app.string.detail_info_rating_fallback'), this.gallery().ratingFallBack.toFixed(2))
      this.divider()
      this.infoRow($r('app.string.detail_info_torrents'), this.gallery().torrentCount)
      this.divider()
      this.infoRow($r('app.string.detail_info_archiver'), this.gallery().archiverLink)
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        ListItem() {
          this.InfoSection()
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('detail_info')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryInfoParams
      if (p !== undefined) {
        this.params = p
      }
    })
  }
}
