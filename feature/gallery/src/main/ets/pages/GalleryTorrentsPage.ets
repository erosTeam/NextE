import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  ThemeConstants,
  EhConstants,
  EhApiService,
  EhGalleryTorrent,
  EhGalleryTorrentList,
  GalleryTorrentsParams,
  SecondaryListScaffold,
  GroupedListSection,
  PageErrorState,
  CardEmptyState,
  ShareUtil,
  AppStrings,
  immersiveTitleBar,
} from 'shared'

/** Read-only torrent list for a gallery. Mirrors eros_fe's torrent dialog as a pushed native page. */
@ComponentV2
export struct GalleryTorrentsPage {
  @Local params: GalleryTorrentsParams = new GalleryTorrentsParams();
  @Local loading: boolean = false;
  @Local error: string = '';
  @Local torrentToken: string = '';
  @Local torrents: EhGalleryTorrent[] = [];
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private title(): string {
    if (this.params.torrentCount.length > 0) {
      return AppStrings.get('detail_torrents').replace('%s', this.params.torrentCount)
    }
    return AppStrings.get('gallery_torrents')
  }

  private async load(): Promise<void> {
    if (this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      const result: EhGalleryTorrentList =
        await EhApiService.getInstance().getGalleryTorrents(
          this.params.gid,
          this.params.token,
          this.params.isEx,
        )
      this.torrentToken = result.torrentToken
      this.torrents = result.torrents
    } catch (e) {
      const err = e as Error
      this.error = err.message.length > 0 ? err.message : AppStrings.get('common_load_failed')
    }
    this.loading = false
  }

  private torrentUrl(torrent: EhGalleryTorrent): string {
    if (this.torrentToken.length === 0 || torrent.hash.length === 0) {
      return ''
    }
    return `${EhConstants.torrentBaseUrl(this.params.isEx)}/${this.torrentToken}/${torrent.hash}.torrent`
  }

  private magnetUrl(torrent: EhGalleryTorrent): string {
    if (torrent.hash.length === 0) {
      return ''
    }
    return `magnet:?xt=urn:btih:${torrent.hash}`
  }

  private shareTorrent(torrent: EhGalleryTorrent): void {
    ShareUtil.shareUrl(this.ctx(), this.torrentUrl(torrent), torrent.name)
  }

  private shareMagnet(torrent: EhGalleryTorrent): void {
    ShareUtil.shareUrl(this.ctx(), this.magnetUrl(torrent), torrent.name)
  }

  @Builder
  private metric(icon: Resource, value: string) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      SymbolGlyph(icon)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(value)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
  }

  @Builder
  private TorrentCard(torrent: EhGalleryTorrent) {
    GroupedListSection() {
      Column({ space: ThemeConstants.SPACE_SM }) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.metric($r('sys.symbol.arrow_up'), torrent.seeds)
          this.metric($r('sys.symbol.arrow_down'), torrent.peers)
          this.metric($r('sys.symbol.checkmark_circle'), torrent.downloads)
          this.metric($r('sys.symbol.doc_plaintext'), torrent.sizeText)
        }
        .width('100%')

        Text(torrent.name)
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: ThemeConstants.SPACE_SM }) {
          if (torrent.posted.length > 0) {
            Text(torrent.posted)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (torrent.uploader.length > 0) {
            Text(torrent.uploader)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')

        Row({ space: ThemeConstants.SPACE_SM }) {
          Button($r('app.string.gallery_torrent_share_file'))
            .height(ThemeConstants.ACTION_HEIGHT)
            .layoutWeight(1)
            .enabled(this.torrentUrl(torrent).length > 0)
            .onClick(() => {
              this.shareTorrent(torrent)
            })
          Button($r('app.string.gallery_torrent_share_magnet'))
            .height(ThemeConstants.ACTION_HEIGHT)
            .layoutWeight(1)
            .enabled(this.magnetUrl(torrent).length > 0)
            .onClick(() => {
              this.shareMagnet(torrent)
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        if (this.loading) {
          ListItem() {
            Row() {
              LoadingProgress()
                .width(ThemeConstants.LOADING_SIZE)
                .height(ThemeConstants.LOADING_SIZE)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding(ThemeConstants.SPACE_MD)
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
        } else if (this.torrents.length === 0) {
          ListItem() {
            CardEmptyState({ message: $r('app.string.gallery_torrents_empty') })
          }
        } else {
          ForEach(this.torrents, (torrent: EhGalleryTorrent) => {
            ListItem() {
              this.TorrentCard(torrent)
            }
          }, (torrent: EhGalleryTorrent) => torrent.hash)
        }
      }
    }
    .titleBar(immersiveTitleBar(this.title()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryTorrentsParams
      if (p !== undefined) {
        this.params = p
        this.load()
      }
    })
  }
}
