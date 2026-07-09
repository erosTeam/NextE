import { HdsNavDestination } from '@kit.UIDesignKit'
import { common, bundleManager } from '@kit.AbilityKit'
import {
  AppModalScaffold,
  AppStrings,
  BackupAppMetadata,
  BackupParseResult,
  BackupPreview,
  BackupService,
  CacheStat,
  CommentTranslationService,
  ConciseListRow,
  EhPageCacheService,
  GroupedListSection,
  ImagePipelineService,
  SecondaryListScaffold,
  TagTranslationService,
  ThemeConstants,
  appSheetOptions,
  connectNavStack,
  connectSafeMode,
  immersiveTitleBar,
  SafeModeState,
} from 'shared'
import {
  BackupFilePickerCoordinator,
  BackupImportSelection,
} from '../model/BackupFilePickerCoordinator'

/**
 * Storage page. Every cache (EH page cache, reader image files, comment translations, tag translations) is a
 * row in a grouped card showing item count + byte size with an explicit per-row clear button; clear-all sits
 * at the end of that same card. Sync is a top-level storage action; backup & restore is inlined here
 * (no separate sub-page): export dumps the settings store to a file (optionally including the sensitive
 * login/account/API bundle, which then requires a password and is AES-256-GCM encrypted); import reads a
 * file, prompts for the password if encrypted, and re-hydrates settings without a restart.
 */
@ComponentV2
export struct CacheSettingsPage {
  @Local pageStat: CacheStat = new CacheStat();
  @Local imageStat: CacheStat = new CacheStat();
  @Local commentStat: CacheStat = new CacheStat();
  @Local tagStat: CacheStat = new CacheStat();
  @Local clearing: boolean = false;
  // Backup state.
  @Local includeSecrets: boolean = false;
  @Local exportPwd: string = '';
  @Local exportPwd2: string = '';
  @Local exportSheetShown: boolean = false;
  @Local importPwdSheetShown: boolean = false;
  @Local importPwd: string = '';
  @Local busy: boolean = false;
  @Local safeMode: SafeModeState = connectSafeMode();
  private appVersion: string = '';
  private appVersionCode: number = 0;
  private pendingImportRaw: string = '';
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
    this.refreshAll()
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      )
      this.appVersion = info.versionName
      this.appVersionCode = info.versionCode
    } catch (_error) {
      this.appVersion = '0'
      this.appVersionCode = 0
    }
  }

  // ── Cache ───────────────────────────────────────────────────────────────
  private refreshAll(): void {
    EhPageCacheService.stat(this.ctx()).then((s: CacheStat) => {
      this.pageStat = s
    })
    ImagePipelineService.stat(this.ctx()).then((s: CacheStat) => {
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
      return this.clearImageCaches()
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

  private async clearEverything(): Promise<void> {
    await EhPageCacheService.clearAll(this.ctx())
    await this.clearImageCaches()
    await CommentTranslationService.clear(this.ctx())
    await TagTranslationService.clearTranslations(this.ctx())
  }

  private async clearImageCaches(): Promise<void> {
    await ImagePipelineService.clearCache(this.ctx())
  }

  // ── Backup ──────────────────────────────────────────────────────────────
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private metadata(): BackupAppMetadata {
    return { appVersion: this.appVersion, appVersionCode: this.appVersionCode }
  }

  private importFailureText(result: BackupParseResult): ResourceStr {
    if (result.code === 'too_large') {
      return $r('app.string.backup_import_too_large')
    }
    if (result.code === 'not_json') {
      return $r('app.string.backup_import_not_json')
    }
    if (result.code === 'foreign_backup') {
      return $r('app.string.backup_import_foreign')
    }
    if (result.code === 'unsupported_version') {
      return $r('app.string.backup_import_unsupported')
    }
    if (result.code === 'bad_checksum') {
      return $r('app.string.backup_import_bad_checksum')
    }
    if (result.code === 'malformed') {
      return $r('app.string.backup_import_malformed')
    }
    return $r('app.string.backup_import_invalid')
  }

  private localDataCount(preview: BackupPreview): number {
    const counts = preview.counts.localData
    if (counts === undefined) {
      return 0
    }
    return counts.readProgress + counts.viewedHistory + counts.localFavorites + counts.searchHistory +
      counts.localBlockRules + counts.imageBlockRules + counts.customProfiles
  }

  private restorePreviewMessage(preview: BackupPreview): string {
    const lines: string[] = [
      AppStrings.get('backup_restore_confirm_message'),
      '',
      `${AppStrings.get('backup_restore_preview_version')}: ${preview.appVersion} (${preview.appVersionCode})`,
      `${AppStrings.get('backup_restore_preview_type')}: ${preview.hasSecrets ?
        AppStrings.get('backup_restore_preview_encrypted') :
        AppStrings.get('backup_restore_preview_plain')}`,
      `${AppStrings.get('backup_restore_preview_preferences')}: ${preview.counts.preferences}`,
      `${AppStrings.get('backup_restore_preview_local_data')}: ${this.localDataCount(preview)}`,
    ]
    if (preview.hasSecrets) {
      const secretCount: number = preview.counts.secrets === undefined ? 0 : preview.counts.secrets
      lines.push(`${AppStrings.get('backup_restore_preview_secrets')}: ${secretCount}`)
    }
    return lines.join('\n')
  }

  private timeStamp(): string {
    const d: Date = new Date()
    const p = (n: number): string => (n < 10 ? `0${n}` : `${n}`)
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(d.getMinutes())}`
  }

  private openExport(): void {
    this.includeSecrets = false
    this.exportPwd = ''
    this.exportPwd2 = ''
    this.exportSheetShown = true
  }

  private confirmExport(): void {
    if (this.busy) {
      return
    }
    if (this.includeSecrets) {
      if (this.exportPwd.length === 0) {
        this.toast($r('app.string.backup_password_required'))
        return
      }
      if (this.exportPwd !== this.exportPwd2) {
        this.toast($r('app.string.backup_password_mismatch'))
        return
      }
    }
    this.busy = true
    BackupFilePickerCoordinator.exportBackup(
      this.ctx(),
      this.metadata(),
      { includeSecrets: this.includeSecrets, password: this.exportPwd },
      this.timeStamp(),
    )
      .then(() => {
        this.exportSheetShown = false
        this.exportPwd = ''
        this.exportPwd2 = ''
        this.toast($r('app.string.backup_export_done'))
      })
      .catch((error: Error) => {
        if (error.message !== 'save cancelled') {
          this.toast($r('app.string.backup_export_failed'))
        }
      })
      .finally(() => {
        this.busy = false
      })
  }

  private startImport(): void {
    if (this.busy) {
      return
    }
    this.busy = true
    BackupFilePickerCoordinator.selectImport(this.ctx())
      .then((selection: BackupImportSelection) => {
        const result: BackupParseResult = selection.parseResult
        if (result.encrypted === true) {
          this.pendingImportRaw = selection.raw
          this.importPwd = ''
          this.importPwdSheetShown = true
          return
        }
        if (!result.ok || result.envelope === undefined) {
          this.toast(this.importFailureText(result))
          return
        }
        this.confirmRestore(result)
      })
      .catch((error: Error) => {
        if (error.message !== 'open cancelled') {
          this.toast($r('app.string.backup_import_invalid'))
        }
      })
      .finally(() => {
        this.busy = false
      })
  }

  private confirmDecryptImport(): void {
    if (this.busy || this.importPwd.length === 0) {
      return
    }
    this.busy = true
    BackupFilePickerCoordinator.decryptSelected(this.pendingImportRaw, this.importPwd)
      .then((result: BackupParseResult) => {
        if (!result.ok || result.envelope === undefined) {
          this.toast(
            result.code === 'bad_password'
              ? $r('app.string.backup_bad_password')
              : this.importFailureText(result),
          )
          return
        }
        this.importPwdSheetShown = false
        this.importPwd = ''
        this.pendingImportRaw = ''
        this.confirmRestore(result)
      })
      .finally(() => {
        this.busy = false
      })
  }

  // Restore overwrites the current settings, so confirm first.
  private confirmRestore(result: BackupParseResult): void {
    const envelope = result.envelope
    if (envelope === undefined) {
      return
    }
    const preview: BackupPreview = BackupService.preview(envelope)
    this.getUIContext().showAlertDialog({
      title: $r('app.string.backup_restore_confirm_title'),
      message: this.restorePreviewMessage(preview),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.backup_restore_apply'),
        action: () => {
          this.busy = true
          BackupFilePickerCoordinator.restoreSelected(this.ctx(), envelope)
            .then(() => {
              this.toast($r('app.string.backup_import_done'))
            })
            .catch(() => {
              this.toast($r('app.string.backup_import_invalid'))
            })
            .finally(() => {
              this.busy = false
            })
        },
      },
    })
  }

  build() {
    HdsNavDestination() {
      // Stack at page root (NOT inside the List) hosts the sheets — bindSheet bound deep inside a List
      // ListItem never opens because the list virtualizes/clips its overlays.
      Stack() {
        SecondaryListScaffold({
          scroller: this.scroller,
          bottomPadding: ThemeConstants.SPACE_XL,
          alwaysEnableEdgeSpring: true,
        }) {
          ListItem() {
            Column({ space: ThemeConstants.SPACE_MD }) {
              if (!this.safeMode.restricted()) {
                GroupedListSection() {
                  ConciseListRow({
                    title: $r('app.string.settings_sync'),
                    subtitle: $r('app.string.settings_sync_hint'),
                    leadingIcon: $r('sys.symbol.cloud'),
                    action: () => {
                      connectNavStack().stack.pushPathByName('SyncSettings', null)
                    },
                  })
                }
              }
              // Backup & restore, inlined (export / import open their own sheets — no sub-page).
              GroupedListSection() {
                ConciseListRow({
                  title: $r('app.string.backup_export'),
                  subtitle: $r('app.string.backup_export_subtitle'),
                  leadingIcon: $r('sys.symbol.cloud_and_arrow_up'),
                  showChevron: false,
                  isEnabled: !this.busy,
                  action: () => {
                    this.openExport()
                  },
                })
                this.rowDivider()
                ConciseListRow({
                  title: $r('app.string.backup_import'),
                  subtitle: $r('app.string.backup_import_subtitle'),
                  leadingIcon: $r('sys.symbol.doc_plaintext'),
                  showChevron: false,
                  isEnabled: !this.busy,
                  action: () => {
                    this.startImport()
                  },
                })
              }
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
              // Caches + clear-all, all in one card (clear-all is a cache action).
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
            }.width('100%')
          }
        }
        this.ExportSheetHost()
        this.ImportSheetHost()
      }
      .width('100%')
      .height('100%')
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

  @Builder
  ExportSheetHost() {
    Blank()
      .width(1)
      .height(1)
      .bindSheet(
        $$this.exportSheetShown,
        this.ExportSheet(),
        appSheetOptions({ detents: [SheetSize.LARGE], showClose: false }),
      )
  }

  @Builder
  ImportSheetHost() {
    Blank()
      .width(1)
      .height(1)
      .bindSheet(
        $$this.importPwdSheetShown,
        this.ImportPasswordSheet(),
        appSheetOptions({ detents: [SheetSize.LARGE], showClose: false }),
      )
  }

  @Builder
  ExportSheet() {
    AppModalScaffold({
      title: $r('app.string.backup_export'),
      confirmIcon: $r('sys.symbol.cloud_and_arrow_up'),
      confirmText: $r('app.string.backup_export'),
      confirmEnabled: !this.busy,
      confirmLoading: this.busy,
      closeAction: () => {
        this.exportSheetShown = false
      },
      confirmAction: () => {
        this.confirmExport()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Row({ space: ThemeConstants.SPACE_SM }) {
            Column({ space: ThemeConstants.SPACE_XS }) {
              Text($r('app.string.backup_include_secrets'))
                .fontSize(ThemeConstants.FONT_SIZE_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .width('100%')
              Text($r('app.string.backup_include_secrets_hint'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.includeSecrets })
              .selectedColor(ThemeConstants.BRAND_PRIMARY)
              .onChange((value: boolean) => {
                this.includeSecrets = value
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          if (this.includeSecrets) {
            this.PasswordField(this.exportPwd, $r('app.string.backup_password'), (value: string) => {
              this.exportPwd = value
            })
            this.PasswordField(this.exportPwd2, $r('app.string.backup_password_repeat'), (value: string) => {
              this.exportPwd2 = value
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  ImportPasswordSheet() {
    AppModalScaffold({
      title: $r('app.string.backup_encrypted_title'),
      confirmIcon: $r('sys.symbol.doc_plaintext'),
      confirmText: $r('app.string.backup_import'),
      confirmEnabled: !this.busy && this.importPwd.length > 0,
      confirmLoading: this.busy,
      closeAction: () => {
        this.importPwdSheetShown = false
      },
      confirmAction: () => {
        this.confirmDecryptImport()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          Text($r('app.string.backup_encrypted_hint'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          this.PasswordField(this.importPwd, $r('app.string.backup_password'), (value: string) => {
            this.importPwd = value
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
      }
    }
  }

  @Builder
  PasswordField(text: string, placeholder: ResourceStr, onChange: (value: string) => void) {
    TextInput({ text: text, placeholder: placeholder })
      .type(InputType.Password)
      .width('100%')
      .onChange((value: string) => {
        onChange(value)
      })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }
}
