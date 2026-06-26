import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  CacheStat,
  CachedImageFileService,
  CommentTranslationService,
  ConciseListRow,
  EhPageCacheService,
  SecondaryListScaffold,
  TagTranslationService,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'

/**
 * Storage & cache page: per-category count + byte size for every cache the app keeps (EH page cache,
 * reader image files, comment translations, tag translations), each clearable on its own, plus a
 * clear-all row. Stats are read on appear and re-read after any clear.
 */
@ComponentV2
export struct CacheSettingsPage {
  @Local pageStat: CacheStat = new CacheStat();
  @Local imageStat: CacheStat = new CacheStat();
  @Local commentStat: CacheStat = new CacheStat();
  @Local tagStat: CacheStat = new CacheStat();
  @Local clearing: boolean = false;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.refreshAll()
  }

  private refreshAll(): void {
    EhPageCacheService.stat(this.ctx()).then((s: CacheStat) => {
      this.pageStat = s
    })
    CachedImageFileService.stat(this.ctx()).then((s: CacheStat) => {
      this.imageStat = s
    })
    CommentTranslationService.stat(this.ctx()).then((s: CacheStat) => {
      this.commentStat = s
    })
    TagTranslationService.statCache(this.ctx()).then((s: CacheStat) => {
      this.tagStat = s
    })
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    const kb: number = bytes / 1024
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`
    }
    const mb: number = kb / 1024
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`
    }
    return `${(mb / 1024).toFixed(2)} GB`
  }

  private summary(stat: CacheStat): string {
    return `${stat.count} ${AppStrings.get('cache_items_unit')} · ${this.formatBytes(stat.bytes)}`
  }

  private confirmThenClear(message: Resource, clear: () => void): void {
    this.getUIContext().showAlertDialog({
      message: message,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_clear'),
        fontColor: Color.Red,
        action: clear,
      },
    })
  }

  private runClear(work: Promise<void>): void {
    if (this.clearing) {
      return
    }
    this.clearing = true
    work
      .then(() => {
        this.getUIContext()
          .getPromptAction()
          .showToast({ message: $r('app.string.cache_cleared') })
      })
      .finally(() => {
        this.clearing = false
        this.refreshAll()
      })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
      }) {
        ConciseListRow({
          title: $r('app.string.cache_page'),
          subtitle: this.summary(this.pageStat),
          leadingIcon: $r('sys.symbol.doc_text'),
          showChevron: false,
          isEnabled: !this.clearing,
          action: () => {
            this.confirmThenClear($r('app.string.cache_clear_confirm'), () => {
              this.runClear(EhPageCacheService.clearAll(this.ctx()))
            })
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.cache_image'),
          subtitle: this.summary(this.imageStat),
          leadingIcon: $r('sys.symbol.picture'),
          showChevron: false,
          isEnabled: !this.clearing,
          action: () => {
            this.confirmThenClear($r('app.string.cache_clear_confirm'), () => {
              this.runClear(CachedImageFileService.clear(this.ctx()))
            })
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.cache_comment_translation'),
          subtitle: this.summary(this.commentStat),
          leadingIcon: $r('sys.symbol.translate'),
          showChevron: false,
          isEnabled: !this.clearing,
          action: () => {
            this.confirmThenClear($r('app.string.cache_clear_confirm'), () => {
              this.runClear(CommentTranslationService.clear(this.ctx()))
            })
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.cache_tag_translation'),
          subtitle: this.summary(this.tagStat),
          leadingIcon: $r('sys.symbol.textformat'),
          showChevron: false,
          isEnabled: !this.clearing,
          action: () => {
            this.confirmThenClear($r('app.string.cache_clear_confirm'), () => {
              this.runClear(TagTranslationService.clearTranslations(this.ctx()))
            })
          },
        })
        this.rowDivider()
        ConciseListRow({
          title: $r('app.string.cache_clear_all'),
          leadingIcon: $r('sys.symbol.trash'),
          destructive: true,
          showChevron: false,
          isEnabled: !this.clearing,
          action: () => {
            this.confirmThenClear($r('app.string.cache_clear_all_confirm'), () => {
              this.runClear(this.clearEverything())
            })
          },
        })
      }
    }.titleBar(immersiveTitleBar(AppStrings.get('settings_cache')))
  }

  private async clearEverything(): Promise<void> {
    await EhPageCacheService.clearAll(this.ctx())
    await CachedImageFileService.clear(this.ctx())
    await CommentTranslationService.clear(this.ctx())
    await TagTranslationService.clearTranslations(this.ctx())
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }
}
