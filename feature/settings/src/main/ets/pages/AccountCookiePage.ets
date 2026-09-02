import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  CookieJarEntry,
  CookieJarSettings,
  EhConstants,
  EhCookieStore,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  ListRowDivider,
  DiagnosticLogger,
  immersiveTitleBarAction,
  immersiveTitleBarWithActions,
  AuthState,
  connectAuth,
} from 'shared'

@ComponentV2
export struct AccountCookiePage {
  @Local auth: AuthState = connectAuth();
  @Local cookieEntries: CookieJarEntry[] = [];
  @Local refreshingIgneous: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private reload(): void {
    this.cookieEntries = EhCookieStore.getInstance().entries()
  }

  @Monitor('auth.memberId', 'auth.cookieCount')
  private onActiveCookieJarChanged(): void {
    this.reload()
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private cookieText(): string {
    return CookieJarSettings.formatEntries(this.cookieEntries)
  }

  private exStatusText(): ResourceStr {
    if (this.auth.hasIgneous) {
      return $r('app.string.account_cookie_ex_available')
    }
    return $r('app.string.account_cookie_ex_locked')
  }

  private refreshIgneous(): void {
    if (this.refreshingIgneous) {
      return
    }
    const requestMember: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
    this.refreshingIgneous = true
    this.toast($r('app.string.site_ex_checking'))
    CookieJarSettings.refreshIgneous(this.ctx())
      .then((ok: boolean) => {
        if (EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID) !== requestMember) {
          return
        }
        this.reload()
        this.toast(ok ? $r('app.string.site_ex_unlocked') : $r('app.string.site_ex_no_access'))
      })
      .finally(() => {
        this.refreshingIgneous = false
      })
  }

  private copyCookie(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.cookieText())
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.toast($r('app.string.account_cookie_copied'))
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_copy_failed', (error as Error).message)
      this.toast($r('app.string.account_cookie_copy_failed'))
    }
  }

  private exportCookie(): void {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.ctx())
      const saveOptions = new picker.DocumentSaveOptions()
      saveOptions.newFileNames = ['NextE-cookie.txt']
      documentPicker
        .save(saveOptions)
        .then((uris: string[]) => {
          if (!uris || uris.length === 0) {
            return
          }
          AccountCookiePage.writeText(uris[0], this.cookieText())
          DiagnosticLogger.info('auth', 'cookie_exported', `count=${this.cookieEntries.length}`)
          this.toast($r('app.string.account_cookie_exported'))
        })
        .catch((error: Error) => {
          DiagnosticLogger.warn('auth', 'cookie_export_failed', error.message)
          this.toast($r('app.string.account_cookie_export_failed'))
        })
    } catch (error) {
      DiagnosticLogger.warn('auth', 'cookie_export_failed', (error as Error).message)
      this.toast($r('app.string.account_cookie_export_failed'))
    }
  }

  private static writeText(uri: string, raw: string): void {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(
        uri,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      )
      fileIo.writeSync(file.fd, raw)
    } finally {
      if (file) {
        fileIo.closeSync(file)
      }
    }
  }

  private cookieTitleBar(): Record<string, Object> {
    return immersiveTitleBarWithActions(AppStrings.get('account_cookie_title'), [
      immersiveTitleBarAction(
        AppStrings.get('account_cookie_copy'),
        $r('sys.symbol.doc_text_on_doc_text'),
        this.cookieEntries.length > 0,
        () => {
          this.copyCookie()
        },
      ),
      immersiveTitleBarAction(
        AppStrings.get('account_cookie_export'),
        $r('sys.symbol.square_and_arrow_down'),
        this.cookieEntries.length > 0,
        () => {
          this.exportCookie()
        },
      ),
    ], 2)
  }

  @Builder
  private CookieEntryRow(entry: CookieJarEntry) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(entry.name)
        .fontSize(ThemeConstants.FONT_SIZE_LIST_ITEM)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(entry.value)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_MD)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.account_cookie_summary'),
              subtitle: this.exStatusText(),
              leadingIcon: $r('sys.symbol.key'),
              trailingText: `${this.cookieEntries.length}`,
              showChevron: false,
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.settings_refresh_igneous'),
              leadingIcon: $r('sys.symbol.arrow_clockwise'),
              trailingText: this.refreshingIgneous ? $r('app.string.common_loading') : '',
              showChevron: false,
              action: () => {
                this.refreshIgneous()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            if (this.cookieEntries.length <= 0) {
              ConciseListRow({
                title: $r('app.string.account_cookie_empty'),
                leadingIcon: $r('sys.symbol.exclamationmark_circle'),
                showChevron: false,
              })
            } else {
              ForEach(
                this.cookieEntries,
                (entry: CookieJarEntry, index: number) => {
                  this.CookieEntryRow(entry)
                  if (index < this.cookieEntries.length - 1) {
                    ListRowDivider()
                  }
                },
                (entry: CookieJarEntry) => entry.name,
              )
            }
          }
        }
      }
    }
    .titleBar(this.cookieTitleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
