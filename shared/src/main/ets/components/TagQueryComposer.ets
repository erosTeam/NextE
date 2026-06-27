import { common } from '@kit.AbilityKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { AppStrings } from '../i18n/AppStrings'
import { AppSearchField } from './AppSearchField'
import { EhTagSuggestion } from '../model/EhTagSuggestion'
import { TagTranslationService } from '../services/TagTranslationService'
import { connectTagTranslationSettings } from '../state/TagTranslationSettingsState'
import { connectSiteMode } from '../state/SiteModeState'
import { EhApiPhpService } from '../network/EhApiPhpService'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

const SUGGEST_DELAY_MS: number = 450
const LOCAL_LIMIT: number = 30
const MAX_SUGGESTIONS: number = 12

/** One token of the composed EH query: a tag (namespace+text) or free text, included (AND) or excluded (NOT). */
class QueryTag {
  namespace: string = ''
  text: string = ''
  exclude: boolean = false

  constructor(namespace: string, text: string, exclude: boolean) {
    this.namespace = namespace
    this.text = text
    this.exclude = exclude
  }
}

/**
 * Graphical EH-query composer (a stronger take on eros_fe's flat tag list). The user searches tags
 * (local translation DB + EH /api.php tagsuggest, same pipeline as the search page), taps a suggestion to
 * add it as a CHIP, and taps a chip to flip its relation include(AND) ⇄ exclude(NOT, EH '-' prefix); ✕
 * removes it. The chip set serialises to/parses from the canonical EH query string (space = AND), so the
 * single source of truth stays the `query` string the parent owns. Built on AppSearchField (keyboard-stable
 * mirror pattern) so typing never flaps the IME, and chips are derived from `query` each render.
 */
@ComponentV2
export struct TagQueryComposer {
  @Param query: string = '';
  @Event onQueryChange: (value: string) => void = () => {};
  // Transient "add a tag" field text — NOT part of the query until a suggestion/free-text is committed.
  @Local private addText: string = '';
  @Local private suggestions: EhTagSuggestion[] = [];
  @Local private suggestionCount: number = 0;
  private timer: number = -1;
  private epoch: number = 0;

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // ── query string ⇄ chips ────────────────────────────────────────────────
  private tags(): QueryTag[] {
    return TagQueryComposer.parse(this.query)
  }

  private static unwrap(value: string): string {
    let v: string = value
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1)
    }
    if (v.endsWith('$')) {
      v = v.substring(0, v.length - 1)
    }
    return v
  }

  private static parseToken(raw: string): QueryTag {
    let tok: string = raw
    let exclude: boolean = false
    if (tok.startsWith('-')) {
      exclude = true
      tok = tok.substring(1)
    }
    const colon: number = tok.indexOf(':')
    if (colon > 0) {
      const ns: string = tok.substring(0, colon)
      if (/^[a-zA-Z]+$/.test(ns)) {
        return new QueryTag(ns.toLowerCase(), TagQueryComposer.unwrap(tok.substring(colon + 1)), exclude)
      }
    }
    return new QueryTag('', TagQueryComposer.unwrap(tok), exclude)
  }

  static parse(query: string): QueryTag[] {
    const out: QueryTag[] = []
    const tokens: string[] = []
    let cur: string = ''
    let inQuote: boolean = false
    for (let i = 0; i < query.length; i++) {
      const ch: string = query.charAt(i)
      if (ch === '"') {
        inQuote = !inQuote
        cur = cur + ch
      } else if (ch === ' ' && !inQuote) {
        if (cur.length > 0) {
          tokens.push(cur)
          cur = ''
        }
      } else {
        cur = cur + ch
      }
    }
    if (cur.length > 0) {
      tokens.push(cur)
    }
    tokens.forEach((t: string) => {
      const tag: QueryTag = TagQueryComposer.parseToken(t)
      if (tag.text.length > 0 || tag.namespace.length > 0) {
        out.push(tag)
      }
    })
    return out
  }

  private static tokenOf(t: QueryTag): string {
    let core: string = ''
    if (t.namespace.length > 0) {
      core = EhConstants.exactTagSearchQuery(t.namespace, t.text)
    } else if (t.text.length > 0) {
      core = t.text.indexOf(' ') >= 0 ? `"${t.text}"` : t.text
    }
    if (core.length === 0) {
      return ''
    }
    return t.exclude ? `-${core}` : core
  }

  static serialize(tags: QueryTag[]): string {
    const parts: string[] = []
    tags.forEach((t: QueryTag) => {
      const s: string = TagQueryComposer.tokenOf(t)
      if (s.length > 0) {
        parts.push(s)
      }
    })
    return parts.join(' ')
  }

  private commit(tags: QueryTag[]): void {
    this.onQueryChange(TagQueryComposer.serialize(tags))
  }

  private alreadyHas(tags: QueryTag[], ns: string, text: string): boolean {
    for (let i = 0; i < tags.length; i++) {
      if (tags[i].namespace === ns && tags[i].text === text) {
        return true
      }
    }
    return false
  }

  private addFromSuggestion(s: EhTagSuggestion): void {
    const tags: QueryTag[] = this.tags()
    if (!this.alreadyHas(tags, s.namespace.toLowerCase(), s.text)) {
      tags.push(new QueryTag(s.namespace.toLowerCase(), s.text, false))
      this.commit(tags)
    }
    this.addText = ''
    this.clearSuggest()
    TagTranslationService.touchSuggestion(this.ctx(), s).then(() => {})
  }

  private addFreeText(value: string): void {
    const text: string = value.trim()
    if (text.length === 0) {
      return
    }
    // Accept a typed "ns:value" too, so power users can add a fielded tag without picking a suggestion.
    const tag: QueryTag = TagQueryComposer.parseToken(text)
    const tags: QueryTag[] = this.tags()
    if (!this.alreadyHas(tags, tag.namespace, tag.text)) {
      tags.push(tag)
      this.commit(tags)
    }
    this.addText = ''
    this.clearSuggest()
  }

  private toggleExclude(index: number): void {
    const tags: QueryTag[] = this.tags()
    if (index >= 0 && index < tags.length) {
      tags[index].exclude = !tags[index].exclude
      this.commit(tags)
    }
  }

  private removeTag(index: number): void {
    const tags: QueryTag[] = this.tags()
    if (index >= 0 && index < tags.length) {
      tags.splice(index, 1)
      this.commit(tags)
    }
  }

  private chipLabel(t: QueryTag): string {
    const v: string = t.text
    // Expand to the full namespace so chips read the same before/after a round-trip (serialize compacts
    // it) and match the suggestion rows — the canonical EH token stays the short form in serialize().
    return t.namespace.length > 0 ? `${EhConstants.expandNamespace(t.namespace)}:${v}` : v
  }

  // ── tag suggestions (local DB then EH api, debounced — mirrors SearchViewModel) ──
  private lastToken(query: string): string {
    const parts: string[] = query.split(/[ ;"]/)
    return parts.length > 0 ? parts[parts.length - 1].trim() : ''
  }

  private clearSuggest(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
    this.epoch = this.epoch + 1
    this.suggestions = []
    this.suggestionCount = 0
  }

  private scheduleSuggest(query: string): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
    const token: string = this.lastToken(query)
    this.epoch = this.epoch + 1
    const myEpoch: number = this.epoch
    if (token.length === 0 || token.indexOf('$') >= 0) {
      this.suggestions = []
      this.suggestionCount = 0
      return
    }
    this.timer = setTimeout(() => {
      this.fetchSuggest(token, myEpoch)
    }, SUGGEST_DELAY_MS)
  }

  private async fetchSuggest(token: string, myEpoch: number): Promise<void> {
    try {
      let local: EhTagSuggestion[] = []
      try {
        if (connectTagTranslationSettings().enabled) {
          local = await TagTranslationService.searchSuggestions(this.ctx(), token, LOCAL_LIMIT)
        }
      } catch (localErr) {
        DiagnosticLogger.warn('tagcompose', 'local_suggest_failed', (localErr as Error).message)
      }
      if (this.epoch === myEpoch && local.length > 0) {
        this.suggestions = local.slice(0, MAX_SUGGESTIONS)
        this.suggestionCount = this.suggestions.length
        return
      }
      const rows: EhTagSuggestion[] = await EhApiPhpService.tagSuggest(
        EhConstants.baseUrl(connectSiteMode().isEx),
        token,
      )
      if (this.epoch === myEpoch) {
        this.suggestions = rows.slice(0, MAX_SUGGESTIONS)
        this.suggestionCount = this.suggestions.length
      }
    } catch (err) {
      if (this.epoch === myEpoch) {
        this.suggestions = []
        this.suggestionCount = 0
      }
      DiagnosticLogger.warn('tagcompose', 'suggest_failed', (err as Error).message)
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_SM }) {
      AppSearchField({
        text: this.addText,
        placeholder: $r('app.string.tag_compose_placeholder'),
        useSystemMaterial: false,
        onTextChange: (value: string) => {
          this.addText = value
          this.scheduleSuggest(value)
        },
        onSubmit: (value: string) => {
          this.addFreeText(value)
        },
      })

      if (this.suggestionCount > 0) {
        this.SuggestionList()
      } else {
        this.ChipArea()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SuggestionList() {
    Column() {
      ForEach(
        this.suggestions,
        (s: EhTagSuggestion) => {
          Row({ space: ThemeConstants.SPACE_MD }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(22)
              .fontColor([$r('sys.color.font_tertiary')])
            Column({ space: 2 }) {
              Text(s.displayName.length > 0 ? `${s.namespace}:${s.displayName}` : s.label())
                .fontSize(ThemeConstants.FONT_SIZE_BODY)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(s.label())
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
          .onClick(() => {
            this.addFromSuggestion(s)
          })
        },
        (s: EhTagSuggestion) => `${s.namespace}:${s.text}:${s.displayName}`,
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ChipArea() {
    if (this.query.trim().length === 0) {
      Text($r('app.string.tag_compose_empty_hint'))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ top: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.tags(),
          (t: QueryTag, index: number) => {
            this.Chip(t, index)
          },
          (t: QueryTag, index: number) => `${t.exclude ? '-' : ''}${t.namespace}:${t.text}:${index}`,
        )
      }
      .width('100%')
    }
  }

  @Builder
  private Chip(t: QueryTag, index: number) {
    Row({ space: ThemeConstants.SPACE_XS }) {
      if (t.exclude) {
        Text('−')
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Red)
      }
      Text(this.chipLabel(t))
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor($r('sys.color.font_primary'))
        .decoration({ type: t.exclude ? TextDecorationType.LineThrough : TextDecorationType.None })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_tertiary')])
        .onClick(() => {
          this.removeTag(index)
        })
    }
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_SM,
      top: ThemeConstants.SPACE_XS,
      bottom: ThemeConstants.SPACE_XS,
    })
    .margin({ right: ThemeConstants.SPACE_SM, bottom: ThemeConstants.SPACE_SM })
    .borderRadius(ThemeConstants.RADIUS_ROUND)
    .backgroundColor(this.chipBackground(t))
    .opacity(t.exclude ? 0.6 : 1)
    .constraintSize({ maxWidth: '90%' })
    .onClick(() => {
      this.toggleExclude(index)
    })
  }

  private chipBackground(t: QueryTag): ResourceColor {
    return t.namespace.length > 0
      ? EhConstants.tagNamespaceColor(t.namespace)
      : $r('app.color.card_background')
  }
}
