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
  PageErrorState,
  CardEmptyState,
  ShareUtil,
  AppStrings,
  immersiveTitleBar,
  AppModalScaffold,
  DiagnosticLogger,
} from 'shared'

/** Read-only torrent list for a gallery. Mirrors eros_fe's torrent dialog; detail opens it as a sheet. */
@ComponentV2
export struct GalleryTorrentsContent {
  @Param params: GalleryTorrentsParams = new GalleryTorrentsParams();
  @Param modal: boolean = false;
  @Event closeAction?: () => void;
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local torrentToken: string = '';
  @Local torrents: EhGalleryTorrent[] = [];
  @Local loadedKey: string = '';
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

  private paramsKey(): string {
    return `${this.params.gid}|${this.params.token}|${this.params.isEx ? '1' : '0'}`
  }

  aboutToAppear(): void {
    this.loadIfNeeded()
  }

  private async loadIfNeeded(): Promise<void> {
    const key: string = this.paramsKey()
    if (key === this.loadedKey || this.params.gid.length === 0 || this.params.token.length === 0) {
      return
    }
    this.loadedKey = key
    await this.load()
  }

  private async load(): Promise<void> {
    if (this.params.gid.length === 0 || this.params.token.length === 0) {
      this.loading = false
      return
    }
    this.loading = true
    this.error = ''
    DiagnosticLogger.info(
      'gallery',
      'torrents_load_start',
      `gid=${this.params.gid} tokenHash=${DiagnosticLogger.ownerHash(this.params.token)} isEx=${this.params.isEx}`,
    )
    try {
      const result: EhGalleryTorrentList =
        await EhApiService.getInstance().getGalleryTorrents(
          this.params.gid,
          this.params.token,
          this.params.isEx,
        )
      this.torrentToken = result.torrentToken
      this.torrents = result.torrents
      DiagnosticLogger.info(
        'gallery',
        'torrents_load_done',
        `gid=${this.params.gid} count=${this.torrents.length} tokenHash=${DiagnosticLogger.ownerHash(this.torrentToken)}`,
      )
    } catch (e) {
      const err = e as Error
      this.error = err.message.length > 0 ? err.message : AppStrings.get('common_load_failed')
      DiagnosticLogger.warn(
        'gallery',
        'torrents_load_failed',
        `gid=${this.params.gid} error=${err.message}`,
      )
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

  private safeKeyPart(value: string): string {
    const safe: string = value.replace(/[^A-Za-z0-9_]/g, '_')
    return safe.length > 0 ? safe : 'empty'
  }

  private torrentRowKey(torrent: EhGalleryTorrent): string {
    return `torrent_${this.safeKeyPart(torrent.hash)}_${this.safeKeyPart(torrent.name)}`
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
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private MagnetAction(torrent: EhGalleryTorrent) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.share'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width(ThemeConstants.BUTTON_HEIGHT)
    .height(ThemeConstants.BUTTON_HEIGHT)
    .backgroundColor(Color.Transparent)
    .enabled(this.magnetUrl(torrent).length > 0)
    .onClick(() => {
      this.shareMagnet(torrent)
    })
  }

  @Builder
  private TorrentItem(torrent: EhGalleryTorrent) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        Row({ space: ThemeConstants.SPACE_MD }) {
          this.metric($r('sys.symbol.arrow_up'), torrent.seeds)
          this.metric($r('sys.symbol.arrow_down'), torrent.peers)
          this.metric($r('sys.symbol.checkmark_circle'), torrent.downloads)
          this.metric($r('sys.symbol.doc_plaintext'), torrent.sizeText)
        }
        .width('100%')

        Column({ space: ThemeConstants.SPACE_XS }) {
          Text(torrent.name)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor(
              this.torrentUrl(torrent).length > 0
                ? ThemeConstants.TEXT_LINK
                : $r('sys.color.font_primary'),
            )
            .lineHeight(ThemeConstants.LINE_HEIGHT_BODY)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              if (this.torrentUrl(torrent).length > 0) {
                this.shareTorrent(torrent)
              }
            })

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
        }
        .width('100%')
      }
      .layoutWeight(1)

      this.MagnetAction(torrent)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: ThemeConstants.SPACE_LG,
      right: ThemeConstants.SPACE_MD,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private Content() {
    if (this.loading) {
      ListItem() {
        Row() {
          LoadingProgress()
            .width(ThemeConstants.LOADING_SIZE)
            .height(ThemeConstants.LOADING_SIZE)
            .color(ThemeConstants.BRAND_PRIMARY)
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
          this.TorrentItem(torrent)
        }
      }, (torrent: EhGalleryTorrent) => this.torrentRowKey(torrent))
    }
  }

  build() {
    if (this.modal) {
      AppModalScaffold({
        title: this.title(),
        showConfirmAction: false,
        closeAction: () => {
          if (this.closeAction) {
            this.closeAction()
          }
        },
      }) {
        this.Content()
      }
    } else {
      SecondaryListScaffold({
        scroller: this.scroller,
        listSpace: ThemeConstants.SPACE_MD,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        this.Content()
      }
    }
  }
}

@ComponentV2
export struct GalleryTorrentsPage {
  @Local params: GalleryTorrentsParams = new GalleryTorrentsParams();

  private title(): string {
    if (this.params.torrentCount.length > 0) {
      return AppStrings.get('detail_torrents').replace('%s', this.params.torrentCount)
    }
    return AppStrings.get('gallery_torrents')
  }

  build() {
    HdsNavDestination() {
      if (this.params.gid.length > 0) {
        GalleryTorrentsContent({ params: this.params })
      }
    }
    .titleBar(immersiveTitleBar(this.title()))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      const p = context.pathInfo.param as GalleryTorrentsParams
      if (p !== undefined) {
        this.params = p
      }
    })
  }
}
