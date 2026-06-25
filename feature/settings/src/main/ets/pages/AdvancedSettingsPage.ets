import { common } from '@kit.AbilityKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  ConciseListRow,
  DiagnosticLogger,
  DiagnosticsExportFile,
  DiagnosticsFileExport,
  DiagnosticsLogFileInfo,
  DiagnosticsLogFileSink,
  DiagnosticsSettings,
  DiagnosticsState,
  GroupedListSection,
  SecondaryListScaffold,
  ThemeConstants,
  connectDiagnostics,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct AdvancedSettingsPage {
  @Local private diagnostics: DiagnosticsState = connectDiagnostics();
  @Local private logCount: number = 0;
  @Local private logFiles: DiagnosticsLogFileInfo[] = [];
  @Local private levelMenuShown: boolean = false;
  private scroller: Scroller = new Scroller();
  private shareController?: systemShare.ShareController;

  aboutToAppear(): void {
    this.refreshLogState()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private refreshLogState(): void {
    this.logCount = DiagnosticsSettings.count()
    this.logFiles = DiagnosticsLogFileSink.listRetainedLogFiles()
  }

  private writeMarker(): void {
    DiagnosticLogger.info('diagnostics', 'manual_marker', `ts=${Date.now()}`)
    this.refreshLogState()
    this.toast($r('app.string.advanced_marker_written'))
  }

  private updateDiagnosticsEnabled(enabled: boolean): void {
    const snapshot = DiagnosticsSettings.current()
    snapshot.enabled = enabled
    DiagnosticsSettings.save(this.ctx(), snapshot)
  }

  private updateMinLevel(level: string): void {
    this.levelMenuShown = false
    const snapshot = DiagnosticsSettings.current()
    snapshot.minLevel = DiagnosticsSettings.normalizeLevel(level)
    DiagnosticsSettings.save(this.ctx(), snapshot)
  }

  private exportCurrentLog(): void {
    try {
      const file: DiagnosticsExportFile = DiagnosticsFileExport.create(this.ctx())
      DiagnosticLogger.info('diagnostics', 'export_current_log', `file=${file.fileName} bytes=${file.text.length}`)
      this.shareFile(file.fileName, file.uri, file.text)
      this.refreshLogState()
    } catch (error) {
      DiagnosticLogger.warn('diagnostics', 'export_current_log_failed', (error as Error).message)
      this.toast($r('app.string.diagnostics_export_failed'))
    }
  }

  private shareLogFile(file: DiagnosticsLogFileInfo): void {
    DiagnosticLogger.info('diagnostics', 'share_log_file', `file=${file.fileName} current=${file.isCurrent}`)
    this.shareFile(file.fileName, file.uri, DiagnosticsLogFileSink.readLogFileText(file.fileName))
  }

  private shareFile(fileName: string, uri: string, fallbackText: string): void {
    try {
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.FILE,
        title: fileName,
        description: 'Redacted NextE diagnostics log',
        uri: uri,
      }
      const data: systemShare.SharedData = new systemShare.SharedData(record)
      this.shareController = new systemShare.ShareController(data)
      this.shareController
        .show(this.ctx(), {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT,
        })
        .then(() => {
          DiagnosticLogger.info('diagnostics', 'share_log_file_success', `file=${fileName}`)
        })
        .catch((error: Error) => {
          DiagnosticLogger.warn('diagnostics', 'share_log_file_failed', `${fileName}: ${error.message}`)
          this.copyTextWithToast(fallbackText)
        })
    } catch (error) {
      DiagnosticLogger.warn('diagnostics', 'share_log_file_failed', `${fileName}: ${(error as Error).message}`)
      this.copyTextWithToast(fallbackText)
    }
  }

  private copyTextWithToast(text: string): void {
    try {
      const fallback = text.length > 0 ? text : DiagnosticsSettings.exportText()
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, fallback)
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.toast($r('app.string.diagnostics_copied'))
    } catch (error) {
      DiagnosticLogger.warn('diagnostics', 'copy_log_failed', (error as Error).message)
      this.toast($r('app.string.diagnostics_share_failed'))
    }
  }

  private clearDiagnosticsText(): void {
    DiagnosticsSettings.clearLogs()
    this.refreshLogState()
    this.toast($r('app.string.diagnostics_boot_records_cleared'))
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private levelLabel(level: string): string {
    if (level === DiagnosticsSettings.LEVEL_DEBUG) {
      return 'Debug'
    }
    if (level === DiagnosticsSettings.LEVEL_WARN) {
      return 'Warn'
    }
    if (level === DiagnosticsSettings.LEVEL_ERROR) {
      return 'Error'
    }
    return 'Info'
  }

  private retainedLogSubtitle(): ResourceStr {
    if (this.logFiles.length <= 0) {
      return $r('app.string.no_local_log_files')
    }
    return $r('app.string.retained_local_log_files_count_arg', `${this.logFiles.length}`)
  }

  private logFileTitle(file: DiagnosticsLogFileInfo): ResourceStr {
    const timestamp = this.formatLogTimestamp(file.createdAtMs)
    if (file.isCurrent) {
      return $r('app.string.current_log_with_time', timestamp)
    }
    return $r('app.string.startup_log_with_time', timestamp)
  }

  private formatLogTimestamp(value: number): string {
    if (value <= 0) {
      return AppStrings.get('unknown_time')
    }
    const date = new Date(value)
    const year = date.getFullYear().toString().padStart(4, '0')
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hour = date.getHours().toString().padStart(2, '0')
    const minute = date.getMinutes().toString().padStart(2, '0')
    return `${year}-${month}-${day} ${hour}:${minute}`
  }

  private formatFileSize(sizeBytes: number): string {
    if (sizeBytes < 1024) {
      return `${Math.max(0, sizeBytes)} B`
    }
    if (sizeBytes < 1024 * 1024) {
      return `${Math.round(sizeBytes / 102.4) / 10} KB`
    }
    return `${Math.round(sizeBytes / 1024 / 102.4) / 10} MB`
  }

  @Builder
  private LevelMenu() {
    Menu() {
      this.LevelMenuItem(DiagnosticsSettings.LEVEL_DEBUG)
      this.LevelMenuItem(DiagnosticsSettings.LEVEL_INFO)
      this.LevelMenuItem(DiagnosticsSettings.LEVEL_WARN)
      this.LevelMenuItem(DiagnosticsSettings.LEVEL_ERROR)
    }
  }

  @Builder
  private LevelMenuItem(level: string) {
    MenuItem({
      content: this.levelLabel(level),
      symbolEndIcon: this.diagnostics.minLevel === level
        ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
        : undefined,
    })
      .onClick(() => {
        this.updateMinLevel(level)
      })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private DiagnosticsSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.diagnostics_enabled'),
        subtitle: $r('app.string.diagnostics_enabled_hint'),
        leadingIcon: $r('sys.symbol.doc_plaintext'),
        hasSwitch: true,
        checked: this.diagnostics.enabled,
        switchAction: (value: boolean) => {
          this.updateDiagnosticsEnabled(value)
        },
      })
      this.rowDivider()
      Column() {
        ConciseListRow({
          title: $r('app.string.diagnostics_min_level'),
          subtitle: $r('app.string.diagnostics_min_level_hint'),
          leadingIcon: $r('sys.symbol.textformat'),
          trailingText: this.levelLabel(this.diagnostics.minLevel),
          trailingDropdown: true,
          action: () => {
            this.levelMenuShown = true
          },
        })
      }
      .bindMenu(this.levelMenuShown, this.LevelMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => {
          this.levelMenuShown = false
        },
      })
    }
  }

  @Builder
  private ActionsSection() {
    GroupedListSection() {
      ConciseListRow({
        title: $r('app.string.diagnostics_current_launch_recent_count', `${this.logCount}`),
        subtitle: this.retainedLogSubtitle(),
        leadingIcon: $r('sys.symbol.arrow_clockwise'),
        showChevron: false,
        action: () => {
          this.refreshLogState()
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.diagnostics_export_current'),
        subtitle: $r('app.string.diagnostics_export_current_hint'),
        leadingIcon: $r('sys.symbol.share'),
        showChevron: false,
        action: () => {
          this.exportCurrentLog()
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.advanced_write_marker'),
        subtitle: $r('app.string.advanced_diagnostics_hint'),
        leadingIcon: $r('sys.symbol.square_and_pencil'),
        showChevron: false,
        action: () => {
          this.writeMarker()
        },
      })
      this.rowDivider()
      ConciseListRow({
        title: $r('app.string.clear_boot_records'),
        leadingIcon: $r('sys.symbol.trash'),
        destructive: true,
        showChevron: false,
        action: () => {
          this.clearDiagnosticsText()
        },
      })
    }
  }

  @Builder
  private LogFilesSection() {
    GroupedListSection() {
      if (this.logFiles.length <= 0) {
        ConciseListRow({
          title: $r('app.string.no_log_files'),
          subtitle: $r('app.string.reopen_keeps_logs'),
          leadingIcon: $r('sys.symbol.folder'),
          showChevron: false,
          action: () => {
            this.refreshLogState()
          },
        })
      } else {
        ForEach(this.logFiles, (file: DiagnosticsLogFileInfo, index: number) => {
          ConciseListRow({
            title: this.logFileTitle(file),
            subtitle: $r('app.string.diagnostics_log_file_share_hint', this.formatFileSize(file.sizeBytes)),
            leadingIcon: $r('sys.symbol.doc_plaintext'),
            showChevron: false,
            action: () => {
              this.shareLogFile(file)
            },
          })
          if (index < this.logFiles.length - 1) {
            this.rowDivider()
          }
        }, (file: DiagnosticsLogFileInfo) => file.fileName)
      }
    }
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          this.DiagnosticsSection()
        }
        ListItem() {
          this.ActionsSection()
        }
        ListItem() {
          this.LogFilesSection()
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('advanced_diagnostics')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
