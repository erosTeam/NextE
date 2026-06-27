import { common } from '@kit.AbilityKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { AppStrings } from '../i18n/AppStrings'
import { AppSearchField } from './AppSearchField'
import { SettingsCheckedMenuItem } from './SettingsCheckedMenuItem'
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

/** A term's relation to the query: AND = space (default), OR = '~' prefix (EH native), NOT = '-' prefix. */
enum TagRelation {
  AND = 0,
  OR = 1,
  NOT = 2,
}

/** One token of the composed EH query: a tag (namespace+text) or free text, with its AND/OR/NOT relation. */
class QueryTag {
  namespace: string = ''
  text: string = ''
  relation: number = TagRelation.AND

  constructor(namespace: string, text: string, relation: number) {
    this.namespace = namespace
    this.text = text
    this.relation = relation
  }
}

/** A tag paired with its index in the full parsed list + its resolved translation, for one list row. */
class TagRowItem {
  tag: QueryTag
  index: number
  displayName: string

  constructor(tag: QueryTag, index: number, displayName: string) {
    this.tag = tag
    this.index = index
    this.displayName = displayName
  }
}

/**
 * Graphical EH-query composer. The user searches tags (local translation DB + EH /api.php tagsuggest, same
 * pipeline as the search page) and taps a suggestion to add it; added tags show as readable ROWS — translated
 * name + raw EH token + a visible 包含/任一/排除 relation selector + remove — NOT tiny chips. Relations map to
 * EH's native operators (space = AND, '~' = OR, '-' = NOT), so the single `query` string the parent owns flows
 * unchanged through f_search. Built from AppSearchField (keyboard-stable) + ConciseListRow (so row height,
 * padding, alignment match every other settings list). Reloaded tags get their translation re-resolved.
 */
@ComponentV2
export struct TagQueryComposer {
  @Param query: string = '';
  @Event onQueryChange: (value: string) => void = () => {};
  @Local private addText: string = '';
  @Local private suggestions: EhTagSuggestion[] = [];
  @Local private suggestionCount: number = 0;
  // ns:text -> translated display name (filled on add from a suggestion, and async on (re)load).
  @Local private trans: Map<string, string> = new Map<string, string>();
  private timer: number = -1;
  private epoch: number = 0;

  aboutToAppear(): void {
    this.ensureTranslations()
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
  }

  @Monitor('query')
  onQueryChanged(): void {
    this.ensureTranslations()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // ── query string ⇄ tags ──────────────────────────────────────────────────
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
    let rel: number = TagRelation.AND
    if (tok.startsWith('-')) {
      rel = TagRelation.NOT
      tok = tok.substring(1)
    } else if (tok.startsWith('~')) {
      rel = TagRelation.OR
      tok = tok.substring(1)
    }
    const colon: number = tok.indexOf(':')
    if (colon > 0) {
      const ns: string = tok.substring(0, colon)
      if (/^[a-zA-Z]+$/.test(ns)) {
        return new QueryTag(ns.toLowerCase(), TagQueryComposer.unwrap(tok.substring(colon + 1)), rel)
      }
    }
    return new QueryTag('', TagQueryComposer.unwrap(tok), rel)
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
    if (t.relation === TagRelation.NOT) {
      return `-${core}`
    }
    if (t.relation === TagRelation.OR) {
      return `~${core}`
    }
    return core
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

  private static keyOf(t: QueryTag): string {
    return `${t.namespace}:${t.text}`
  }

  /** Canonical EH token for a tag, WITHOUT the relation prefix (shown as the row subtitle). */
  private tokenText(t: QueryTag): string {
    if (t.namespace.length > 0) {
      return EhConstants.exactTagSearchQuery(t.namespace, t.text)
    }
    return t.text
  }

  private rowItems(): TagRowItem[] {
    const out: TagRowItem[] = []
    this.tags().forEach((t: QueryTag, i: number) => {
      const name: string | undefined = this.trans.get(TagQueryComposer.keyOf(t))
      out.push(new TagRowItem(t, i, name !== undefined ? name : ''))
    })
    return out
  }

  // ── translation resolution (so reloaded tags show their translated name too) ──
  private async ensureTranslations(): Promise<void> {
    if (!connectTagTranslationSettings().enabled) {
      return
    }
    const tags: QueryTag[] = this.tags()
    let changed: boolean = false
    const next: Map<string, string> = new Map<string, string>()
    this.trans.forEach((v: string, k: string) => next.set(k, v))
    for (let i = 0; i < tags.length; i++) {
      const t: QueryTag = tags[i]
      if (t.namespace.length === 0) {
        continue
      }
      const key: string = TagQueryComposer.keyOf(t)
      if (next.has(key)) {
        continue
      }
      try {
        const name: string = await TagTranslationService.translateFullTagAsync(this.ctx(), `${t.namespace}:${t.text}`)
        // translateFullTagAsync falls back to the input when there's no translation; only keep a real one.
        if (name.length > 0 && name !== `${t.namespace}:${t.text}` && name !== t.text) {
          next.set(key, name)
          changed = true
        }
      } catch (err) {
        DiagnosticLogger.warn('tagcompose', 'translate_failed', (err as Error).message)
      }
    }
    if (changed) {
      this.trans = next
    }
  }

  // ── mutations ─────────────────────────────────────────────────────────────
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
    const ns: string = s.namespace.toLowerCase()
    const tags: QueryTag[] = this.tags()
    if (!this.alreadyHas(tags, ns, s.text)) {
      if (s.displayName.length > 0) {
        const next: Map<string, string> = new Map<string, string>()
        this.trans.forEach((v: string, k: string) => next.set(k, v))
        next.set(`${ns}:${s.text}`, s.displayName)
        this.trans = next
      }
      tags.push(new QueryTag(ns, s.text, TagRelation.AND))
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
    const tag: QueryTag = TagQueryComposer.parseToken(text)
    const tags: QueryTag[] = this.tags()
    if (!this.alreadyHas(tags, tag.namespace, tag.text)) {
      tags.push(tag)
      this.commit(tags)
    }
    this.addText = ''
    this.clearSuggest()
  }

  private setRelation(index: number, relation: number): void {
    const tags: QueryTag[] = this.tags()
    if (index >= 0 && index < tags.length) {
      tags[index].relation = relation
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

  // ── tag suggestions (local DB then EH api, debounced) ─────────────────────
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

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
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
      } else if (this.query.trim().length > 0) {
        this.TagList()
      } else {
        Text($r('app.string.tag_compose_empty_hint'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ top: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
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
              Text(s.displayName.length > 0 ? `${EhConstants.expandNamespace(s.namespace)}:${s.displayName}` : s.label())
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
          .height(56)
          .alignItems(VerticalAlign.Center)
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
  private TagList() {
    Column() {
      ForEach(
        this.rowItems(),
        (it: TagRowItem, idx: number) => {
          if (idx > 0) {
            this.rowDivider()
          }
          TagRow({
            tag: it.tag,
            index: it.index,
            displayName: it.displayName,
            onSetRelation: (index: number, rel: number) => {
              this.setRelation(index, rel)
            },
            onRemove: (index: number) => {
              this.removeTag(index)
            },
          })
        },
        (it: TagRowItem) => `${it.tag.relation}:${it.tag.namespace}:${it.tag.text}:${it.displayName}`,
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * One added-tag row: namespace color dot + translated name (raw token as the subtitle) + a visible relation
 * selector (包含/任一/排除 dropdown) + remove. A readable full-width row, not a tiny chip; spacing inherits
 * the app row metrics. The relation is set right here (no hidden tap-to-menu on a small pill).
 */
@ComponentV2
struct TagRow {
  @Param tag: QueryTag = new QueryTag('', '', TagRelation.AND);
  @Param index: number = -1;
  @Param displayName: string = '';
  @Event onSetRelation: (index: number, relation: number) => void = () => {};
  @Event onRemove: (index: number) => void = () => {};
  @Local private menuShown: boolean = false;

  private title(): string {
    if (this.displayName.length > 0) {
      return this.displayName
    }
    return this.tag.namespace.length > 0
      ? `${EhConstants.expandNamespace(this.tag.namespace)}:${this.tag.text}`
      : this.tag.text
  }

  private subtitle(): string {
    return this.tag.namespace.length > 0
      ? EhConstants.exactTagSearchQuery(this.tag.namespace, this.tag.text)
      : ''
  }

  private relLabel(): ResourceStr {
    if (this.tag.relation === TagRelation.OR) {
      return $r('app.string.tag_compose_rel_or')
    }
    if (this.tag.relation === TagRelation.NOT) {
      return $r('app.string.tag_compose_rel_not')
    }
    return $r('app.string.tag_compose_rel_and')
  }

  private relColor(): ResourceColor {
    if (this.tag.relation === TagRelation.OR) {
      return ThemeConstants.BRAND_PRIMARY
    }
    if (this.tag.relation === TagRelation.NOT) {
      return Color.Red
    }
    return $r('sys.color.font_secondary')
  }

  build() {
    Row({ space: ThemeConstants.SPACE_SM }) {
      Column({ space: 2 }) {
        Text(this.title())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle().length > 0) {
          Text(this.subtitle())
            .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // Relation selector — bare label + chevron, matching the other dropdown rows (列表类型 / 最低评分 / 显示模式).
      Row({ space: ThemeConstants.SPACE_XS }) {
        Text(this.relLabel())
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor(this.relColor())
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([this.relColor()])
      }
      .onClick(() => {
        this.menuShown = true
      })
      .bindMenu(this.menuShown, this.RelationMenu, {
        placement: Placement.Bottom,
        onDisappear: () => {
          this.menuShown = false
        },
      })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
        .margin({ left: ThemeConstants.SPACE_XS })
        .onClick(() => {
          this.onRemove(this.index)
        })
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private RelationMenu() {
    Menu() {
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_compose_rel_and'),
        selected: this.tag.relation === TagRelation.AND,
        selectAction: () => {
          this.onSetRelation(this.index, TagRelation.AND)
          this.menuShown = false
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_compose_rel_or'),
        selected: this.tag.relation === TagRelation.OR,
        selectAction: () => {
          this.onSetRelation(this.index, TagRelation.OR)
          this.menuShown = false
        },
      })
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_compose_rel_not'),
        selected: this.tag.relation === TagRelation.NOT,
        selectAction: () => {
          this.onSetRelation(this.index, TagRelation.NOT)
          this.menuShown = false
        },
      })
    }
    .backgroundColor($r('app.color.card_background'))
  }
}
