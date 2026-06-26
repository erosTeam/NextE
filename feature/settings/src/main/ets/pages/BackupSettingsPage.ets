import { HdsNavDestination } from '@kit.UIDesignKit'
import { common, bundleManager } from '@kit.AbilityKit'
import {
  AppStrings,
  BackupAppMetadata,
  BackupParseResult,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'
import {
  BackupFilePickerCoordinator,
  BackupImportSelection,
} from '../model/BackupFilePickerCoordinator'

/**
 * Backup & restore page. Export dumps the settings store to a file; an optional "include sensitive data"
 * toggle adds the login cookie bundle, saved accounts and the LLM API key, which then REQUIRES a password
 * and is AES-256-GCM encrypted. Import reads a file, prompts for the password if it is encrypted, and
 * re-hydrates settings without a restart. Secrets never travel in a plaintext file.
 */
@ComponentV2
export struct BackupSettingsPage {
  @Local includeSecrets: boolean = false;
  @Local exportPwd: string = '';
  @Local exportPwd2: string = '';
  @Local exportSheetShown: boolean = false;
  @Local importPwdSheetShown: boolean = false;
  @Local importPwd: string = '';
  @Local busy: boolean = false;
  private appVersion: string = '';
  private appVersionCode: number = 0;
  private pendingImportRaw: string = '';
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  aboutToAppear(): void {
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

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private metadata(): BackupAppMetadata {
    return { appVersion: this.appVersion, appVersionCode: this.appVersionCode }
  }

  private timeStamp(): string {
    const d: Date = new Date()
    const p = (n: number): string => (n < 10 ? `0${n}` : `${n}`)
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(d.getMinutes())}`
  }

  // ── Export ──
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

  // ── Import ──
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
          this.toast($r('app.string.backup_import_invalid'))
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
              : $r('app.string.backup_import_invalid'),
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
    this.getUIContext().showAlertDialog({
      title: $r('app.string.backup_restore_confirm_title'),
      message: $r('app.string.backup_restore_confirm_message'),
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
              Text($r('app.string.backup_hint'))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
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
            }.width('100%')
          }
        }
        // Each sheet binds to its OWN 1x1 host (V2Next pattern): chaining two .bindSheet() on one element
        // makes the second shadow the first, and the show flag must be a $$ two-way binding to open.
        this.ExportSheetHost()
        this.ImportSheetHost()
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_backup')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  ExportSheetHost() {
    Blank()
      .width(1)
      .height(1)
      .bindSheet($$this.exportSheetShown, this.ExportSheet(), {
        height: SheetSize.FIT_CONTENT,
        onDisappear: () => {
          this.exportSheetShown = false
        },
      })
  }

  @Builder
  ImportSheetHost() {
    Blank()
      .width(1)
      .height(1)
      .bindSheet($$this.importPwdSheetShown, this.ImportPasswordSheet(), {
        height: SheetSize.FIT_CONTENT,
        onDisappear: () => {
          this.importPwdSheetShown = false
        },
      })
  }

  @Builder
  ExportSheet() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text($r('app.string.backup_export'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Row({ space: ThemeConstants.SPACE_SM }) {
        Column({ space: ThemeConstants.SPACE_XS }) {
          Text($r('app.string.backup_include_secrets'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
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
        TextInput({ placeholder: $r('app.string.backup_password') })
          .type(InputType.Password)
          .onChange((value: string) => {
            this.exportPwd = value
          })
        TextInput({ placeholder: $r('app.string.backup_password_repeat') })
          .type(InputType.Password)
          .onChange((value: string) => {
            this.exportPwd2 = value
          })
      }
      Button($r('app.string.backup_export'))
        .width('100%')
        .enabled(!this.busy)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .onClick(() => {
          this.confirmExport()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_LG)
  }

  @Builder
  ImportPasswordSheet() {
    Column({ space: ThemeConstants.SPACE_MD }) {
      Text($r('app.string.backup_encrypted_title'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
      Text($r('app.string.backup_encrypted_hint'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextInput({ placeholder: $r('app.string.backup_password') })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.importPwd = value
        })
      Button($r('app.string.backup_import'))
        .width('100%')
        .enabled(!this.busy)
        .backgroundColor(ThemeConstants.BRAND_PRIMARY)
        .onClick(() => {
          this.confirmDecryptImport()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ThemeConstants.SPACE_LG)
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }
}
