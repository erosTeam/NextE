import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  CacheStat,
  CachedImageFileService,
  CommentTranslationService,
  ConciseListRow,
  EhPageCacheService,
  GroupedListSection,
  SecondaryListScaffold,
  TagTranslationService,
  ThemeConstants,
  connectNavStack,
  immersiveTitleBar,
} from 'shared'

/**
 * Storage & cache page. Every cache (EH page cache, reader image files, comment translations, tag
 * translations) is a row in a grouped card showing its item count + byte size, with an EXPLICIT trailing
 * "clear" button (the only destructive affordance — disabled when the cache is empty), so the action is
 * discoverable and can't be triggered by an accidental row tap. A total-usage header sits on top and the
 * clear-all action lives in its own separated destructive card. Stats re-read after any clear.
 */
@ComponentV2
export struct CacheSettingsPage {
  @Local pageStat: CacheStat = new CacheStat();
  @Local imageStat: CacheStat = new CacheStat();
  @Local commentStat: CacheStat = new CacheStat();
  @Local tagStat: CacheStat = new CacheStat();
  @Local clearing: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

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

  private statFor(key: string): CacheStat {
    if (key === 'page') {
      return this.pageStat
    }
    if (key === 'image') {
      return this.imageStat
    }
    if (key === 'comment') {
      return this.commentStat
    }
    return this.tagStat
  }

  private clearFor(key: string): Promise<void> {
    if (key === 'page') {
      return EhPageCacheService.clearAll(this.ctx())
    }
    if (key === 'image') {
      return CachedImageFileService.clear(this.ctx())
    }
    if (key === 'comment') {
      return CommentTranslationService.clear(this.ctx())
    }
    return TagTranslationService.clearTranslations(this.ctx())
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

  private totalBytes(): number {
    return this.pageStat.bytes + this.imageStat.bytes + this.commentStat.bytes + this.tagStat.bytes
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
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          Column({ space: ThemeConstants.SPACE_MD }) {
            // Total usage header.
            Row({ space: ThemeConstants.SPACE_XS }) {
              Text($r('app.string.cache_total'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.formatBytes(this.totalBytes()))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_secondary'))
            }
            .width('100%')
            .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
            GroupedListSection() {
              this.CacheRow('page', $r('app.string.cache_page'), $r('sys.symbol.doc_text'))
              this.rowDivider()
              this.CacheRow('image', $r('app.string.cache_image'), $r('sys.symbol.picture'))
              this.rowDivider()
              this.CacheRow(
                'comment',
                $r('app.string.cache_comment_translation'),
                $r('sys.symbol.translate'),
              )
              this.rowDivider()
              this.CacheRow(
                'tag',
                $r('app.string.cache_tag_translation'),
                $r('sys.symbol.textformat'),
              )
            }
            // Clear-all stays with the cache items (it's a cache action), in its own separated destructive card.
            GroupedListSection() {
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
            // Backup & restore (merged from the top-level settings list) sits below the cache controls.
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.settings_backup'),
                leadingIcon: $r('sys.symbol.cloud_and_arrow_up'),
                action: () => {
                  this.stack.pushPathByName('BackupSettings', null)
                },
              })
            }
          }.width('100%')
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_cache')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  CacheRow(key: string, title: ResourceStr, icon: Resource) {
    ConciseListRow({
      title: title,
      subtitle: this.summary(this.statFor(key)),
      leadingIcon: icon,
      showChevron: false,
      suffixPaddingRight: 0,
      suffixBuilderParam: () => {
        this.ClearSuffix(key)
      },
    })
  }

  // Explicit per-cache clear control (the ONLY way a single cache is cleared). Disabled while a clear is
  // running or when that cache is already empty.
  @Builder
  ClearSuffix(key: string) {
    Button($r('app.string.common_clear'))
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor(Color.Transparent)
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor(
        this.statFor(key).count > 0 && !this.clearing ? Color.Red : $r('sys.color.font_tertiary'),
      )
      .enabled(this.statFor(key).count > 0 && !this.clearing)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_MD })
      .onClick(() => {
        this.confirmThenClear($r('app.string.cache_clear_confirm'), () => {
          this.runClear(this.clearFor(key))
        })
      })
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
