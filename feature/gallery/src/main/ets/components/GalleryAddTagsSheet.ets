import { common } from '@kit.AbilityKit'
import {
  AppModalScaffold,
  ConciseListRow,
  DiagnosticLogger,
  EhApiPhpService,
  EhApiService,
  EhConstants,
  EhCookieStore,
  EhErrorText,
  EhTagSuggestion,
  TagTranslationService,
  TagTranslationSettingsState,
  ThemeConstants,
  connectTagTranslationSettings,
} from 'shared'

const ADD_TAGS_FIELD_ID: string = 'gallery-add-tags-input'
const SUGGEST_DELAY_MS: number = 450
const LOCAL_SUGGEST_LIMIT: number = 30
const MAX_SUGGESTIONS: number = 12

/**
 * Contextual gallery tag submission. Existing gallery tags stay visible behind this sheet; tag voting
 * and My Tags settings remain owned by the tag-information sheet.
 */
@ComponentV2
export struct GalleryAddTagsSheet {
  @Param gid: string = ''
  @Param token: string = ''
  @Param isEx: boolean = false
  @Param allowSubmit: boolean = false
  @Event closeAction?: () => void
  @Event submittedAction?: () => void
  @Local draft: string = ''
  @Local suggestions: EhTagSuggestion[] = []
  @Local suggestionLoading: boolean = false
  @Local apiuid: string = ''
  @Local apikey: string = ''
  @Local loadingCredentials: boolean = false
  @Local submitting: boolean = false
  @Local errorMessage: string = ''
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings()
  private suggestTimer: number = -1
  private suggestEpoch: number = 0

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private tagCount(): number {
    const values: string[] = this.draft.split(/[;,\n]/)
    let count: number = 0
    values.forEach((value: string) => {
      if (value.trim().length > 0) {
        count = count + 1
      }
    })
    return count
  }

  private canSubmit(): boolean {
    return this.allowSubmit &&
      EhCookieStore.getInstance().isLogin() &&
      this.apikey.length > 0 &&
      this.apiuid.length > 0 &&
      this.gid.length > 0 &&
      this.token.length > 0 &&
      this.draft.trim().length > 0 &&
      !this.submitting
  }

  private requestDraftFocus(): void {
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(ADD_TAGS_FIELD_ID)
    }, 160)
  }

  private async loadCredentials(): Promise<void> {
    if (this.loadingCredentials || this.gid.length === 0 || this.token.length === 0) {
      return
    }
    this.loadingCredentials = true
    this.errorMessage = ''
    try {
      const result = await EhApiService.getInstance().getGalleryDetail(this.gid, this.token, this.isEx)
      this.apiuid = result.gallery.apiuid
      this.apikey = result.gallery.apikey
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'tag_add_detail_load_failed', (err as Error).message)
    } finally {
      this.loadingCredentials = false
    }
  }

  private activeToken(value: string): string {
    const comma: number = value.lastIndexOf(',')
    const semicolon: number = value.lastIndexOf(';')
    const lineBreak: number = value.lastIndexOf('\n')
    const start: number = Math.max(comma, Math.max(semicolon, lineBreak)) + 1
    return value.substring(start).trim()
  }

  private activeTokenStart(value: string): number {
    const comma: number = value.lastIndexOf(',')
    const semicolon: number = value.lastIndexOf(';')
    const lineBreak: number = value.lastIndexOf('\n')
    return Math.max(comma, Math.max(semicolon, lineBreak)) + 1
  }

  private formatSuggestion(suggestion: EhTagSuggestion): string {
    const namespace: string = EhConstants.compactNamespace(suggestion.namespace)
    const text: string = suggestion.text.trim()
    if (namespace.length === 0 || text.length === 0) {
      return ''
    }
    const body: string = text.indexOf(' ') >= 0 ? `"${text}"$` : `${text}$`
    return `${namespace}:${body}`
  }

  private suggestionTitle(suggestion: EhTagSuggestion): string {
    if (suggestion.displayName.length > 0) {
      return suggestion.displayName
    }
    return `${EhConstants.expandNamespace(suggestion.namespace)}:${suggestion.text}`
  }

  private onDraftChange(value: string): void {
    this.draft = value
    this.errorMessage = ''
    this.scheduleSuggest(value)
  }

  private clearSuggestions(): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    this.suggestEpoch = this.suggestEpoch + 1
    this.suggestions = []
    this.suggestionLoading = false
  }

  private scheduleSuggest(value: string): void {
    if (this.suggestTimer >= 0) {
      clearTimeout(this.suggestTimer)
      this.suggestTimer = -1
    }
    const token: string = this.activeToken(value)
    this.suggestEpoch = this.suggestEpoch + 1
    const epoch: number = this.suggestEpoch
    if (token.length === 0 || token.indexOf('$') >= 0) {
      this.suggestions = []
      this.suggestionLoading = false
      return
    }
    this.suggestTimer = setTimeout(() => {
      this.loadSuggestions(token, epoch)
    }, SUGGEST_DELAY_MS)
  }

  private async loadSuggestions(token: string, epoch: number): Promise<void> {
    this.suggestionLoading = true
    try {
      let local: EhTagSuggestion[] = []
      if (this.tagTranslation.enabled) {
        local = await TagTranslationService.searchSuggestions(this.ctx(), token, LOCAL_SUGGEST_LIMIT)
      }
      if (epoch === this.suggestEpoch && local.length > 0) {
        this.suggestions = local.slice(0, MAX_SUGGESTIONS)
        return
      }
      const remote: EhTagSuggestion[] = await EhApiPhpService.tagSuggest(
        EhConstants.baseUrl(this.isEx),
        token,
      )
      if (epoch === this.suggestEpoch) {
        this.suggestions = remote.slice(0, MAX_SUGGESTIONS)
      }
    } catch (err) {
      if (epoch === this.suggestEpoch) {
        this.suggestions = []
      }
      DiagnosticLogger.warn('gallery', 'tag_add_suggest_failed', (err as Error).message)
    } finally {
      if (epoch === this.suggestEpoch) {
        this.suggestionLoading = false
      }
    }
  }

  private selectSuggestion(suggestion: EhTagSuggestion): void {
    const formatted: string = this.formatSuggestion(suggestion)
    if (formatted.length === 0) {
      return
    }
    const start: number = this.activeTokenStart(this.draft)
    const prefix: string = this.draft.substring(0, start)
    const needsSpace: boolean = prefix.length > 0 && !/[\s\n]$/.test(prefix)
    this.draft = `${prefix}${needsSpace ? ' ' : ''}${formatted}, `
    this.clearSuggestions()
    TagTranslationService.touchSuggestion(this.ctx(), suggestion).then(() => {})
    this.requestDraftFocus()
  }

  private confirmSubmit(): void {
    if (!this.canSubmit()) {
      return
    }
    const tags: string = this.draft.trim()
    this.getUIContext().showAlertDialog({
      title: $r('app.string.detail_add_tags'),
      message: tags,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_ok'),
        action: () => {
          this.submitTags(tags)
        },
      },
    })
  }

  private async submitTags(tags: string): Promise<void> {
    if (this.submitting || !this.canSubmit()) {
      return
    }
    this.submitting = true
    this.errorMessage = ''
    const count: number = this.tagCount()
    try {
      await EhApiPhpService.addGalleryTags(
        EhConstants.baseUrl(this.isEx),
        this.apikey,
        this.apiuid,
        this.gid,
        this.token,
        tags,
      )
      DiagnosticLogger.info('gallery', 'tag_add_success', `gid=${this.gid} count=${count}`)
      if (this.submittedAction) {
        this.submittedAction()
      }
    } catch (err) {
      this.errorMessage = EhErrorText.forUser(err)
      DiagnosticLogger.warn('gallery', 'tag_add_failed', (err as Error).message)
    } finally {
      this.submitting = false
    }
  }

  @Builder
  private SuggestionRow(suggestion: EhTagSuggestion) {
    ConciseListRow({
      title: this.suggestionTitle(suggestion),
      subtitle: this.formatSuggestion(suggestion),
      leadingIcon: $r('sys.symbol.magnifyingglass'),
      showChevron: false,
      action: () => {
        this.selectSuggestion(suggestion)
      },
    })
  }

  build() {
    AppModalScaffold({
      title: $r('app.string.detail_add_tags'),
      contentBackgroundColor: $r('sys.color.ohos_id_color_sub_background'),
      confirmText: $r('app.string.detail_add_tags'),
      confirmEnabled: this.canSubmit(),
      confirmLoading: this.submitting,
      closeAction: () => {
        if (this.closeAction) {
          this.closeAction()
        }
      },
      confirmAction: () => {
        this.confirmSubmit()
      },
    }) {
      ListItem() {
        TextArea({
          text: this.draft,
          placeholder: $r('app.string.detail_add_tags_placeholder'),
        })
          .id(ADD_TAGS_FIELD_ID)
          .width('100%')
          .maxLines(4)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(ThemeConstants.LIST_ROW_RADIUS)
          .enabled(!this.submitting)
          .onChange((value: string) => {
            this.onDraftChange(value)
          })
      }
      if (this.suggestionLoading || this.suggestions.length > 0) {
        ListItem() {
          Column({ space: ThemeConstants.SPACE_XS }) {
            if (this.suggestionLoading) {
              LoadingProgress()
                .width(ThemeConstants.LOADING_SIZE)
                .height(ThemeConstants.LOADING_SIZE)
                .color(ThemeConstants.BRAND_PRIMARY)
            }
            ForEach(
              this.suggestions,
              (suggestion: EhTagSuggestion) => {
                this.SuggestionRow(suggestion)
              },
              (suggestion: EhTagSuggestion, index: number) =>
                `suggestion_${index}_${suggestion.namespace}_${suggestion.text}`.replace(/[^A-Za-z0-9_]/g, '_'),
            )
          }
          .width('100%')
        }
      }
      if (
        !this.loadingCredentials &&
        this.draft.trim().length > 0 &&
        !this.canSubmit() &&
        this.errorMessage.length === 0
      ) {
        ListItem() {
          Text($r('app.string.detail_add_tags_unavailable'))
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      }
      if (this.errorMessage.length > 0) {
        ListItem() {
          Text(this.errorMessage)
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor(Color.Red)
            .width('100%')
        }
      }
    }
  }

  aboutToAppear(): void {
    this.loadCredentials().then(() => {})
    this.requestDraftFocus()
  }

  aboutToDisappear(): void {
    this.clearSuggestions()
  }
}
