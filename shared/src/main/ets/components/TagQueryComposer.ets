import { common } from '@kit.AbilityKit'
import { ThemeConstants } from '../theme/ThemeConstants'
import { AppSearchField } from './AppSearchField'
import { ConciseListRow } from './ConciseListRow'
import { SettingsCheckedMenuItem } from './SettingsCheckedMenuItem'
import { EhTagSuggestion } from '../model/EhTagSuggestion'
import { TagTranslationService } from '../services/TagTranslationService'
import { connectTagTranslationSettings } from '../state/TagTranslationSettingsState'
import { connectSiteMode } from '../state/SiteModeState'
import { EhApiPhpService } from '../network/EhApiPhpService'
import { EhConstants } from '../constants/EhConstants'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { AppStrings } from '../i18n/AppStrings'

const SUGGEST_DELAY_MS: number = 450
const LOCAL_LIMIT: number = 30
const MAX_SUGGESTIONS: number = 12

/** A term's relation to the query: AND = space (default), OR = '~' prefix (EH native), NOT = '-' prefix. */
export enum TagRelation {
  AND = 0,
  OR = 1,
  NOT = 2,
}

/** One token of the composed EH query: a tag (namespace+text) or free text, with its AND/OR/NOT relation. */
export class QueryTag {
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
export class TagRowItem {
  tag: QueryTag
  index: number
  displayName: string

  constructor(tag: QueryTag, index: number, displayName: string) {
    this.tag = tag
    this.index = index
    this.displayName = displayName
  }
}

/** Parse / serialize an EH query string ⇄ QueryTag[] (space = AND, '~' = OR, '-' = NOT). Static so the page
 * that renders the tag rows (in its own List, for swipe) shares the exact round-trip the composer adds with. */
export class TagQuery {
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

  static parseToken(raw: string): QueryTag {
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
        return new QueryTag(ns.toLowerCase(), TagQuery.unwrap(tok.substring(colon + 1)), rel)
      }
    }
    return new QueryTag('', TagQuery.unwrap(tok), rel)
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
      const tag: QueryTag = TagQuery.parseToken(t)
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
      const s: string = TagQuery.tokenOf(t)
      if (s.length > 0) {
        parts.push(s)
      }
    })
    return parts.join(' ')
  }

  static keyOf(t: QueryTag): string {
    return `${t.namespace}:${t.text}`
  }
}

/**
 * The "add tags" control: a keyboard-stable search field that suggests tags (local translation DB + EH
 * /api.php tagsuggest); tapping a suggestion (or submitting free text) appends a tag to the query string.
 * It does NOT render the added tags — the host page renders those as swipe-deletable rows in its own List
 * (a ListItemGroup) using TagQuery.parse + the exported TagRow, so the rows get native swipe-to-delete and a
 * tight group. Relations map to EH native operators, so `query` flows through f_search unchanged.
 */
@ComponentV2
export struct TagQueryComposer {
  @Param query: string = '';
  @Event onQueryChange: (value: string) => void = () => {};
  @Local private addText: string = '';
  @Local private suggestions: EhTagSuggestion[] = [];
  @Local private suggestionCount: number = 0;
  private timer: number = -1;
  private epoch: number = 0;

  aboutToDisappear(): void {
    this.clearSuggest()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private tags(): QueryTag[] {
    return TagQuery.parse(this.query)
  }

  private commit(tags: QueryTag[]): void {
    this.onQueryChange(TagQuery.serialize(tags))
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
    const tag: QueryTag = TagQuery.parseToken(text)
    const tags: QueryTag[] = this.tags()
    if (!this.alreadyHas(tags, tag.namespace, tag.text)) {
      tags.push(tag)
      this.commit(tags)
    }
    this.addText = ''
    this.clearSuggest()
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
      if (this.epoch !== myEpoch) {
        return
      }
      if (local.length > 0) {
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

  private suggestionTitle(s: EhTagSuggestion): string {
    return s.displayName.length > 0 ?
      `${this.suggestionNamespaceLabel(s.namespace)}:${s.displayName}` :
      EhConstants.exactTagSearchQuery(s.namespace, s.text)
  }

  private suggestionNamespaceLabel(namespace: string): string {
    const ns: string = EhConstants.expandNamespace(namespace)
    if (ns === 'artist') return AppStrings.get('tag_ns_artist')
    if (ns === 'female') return AppStrings.get('tag_ns_female')
    if (ns === 'male') return AppStrings.get('tag_ns_male')
    if (ns === 'parody') return AppStrings.get('tag_ns_parody')
    if (ns === 'character') return AppStrings.get('tag_ns_character')
    if (ns === 'group') return AppStrings.get('tag_ns_group')
    if (ns === 'language') return AppStrings.get('tag_ns_language')
    if (ns === 'reclass') return AppStrings.get('tag_ns_reclass')
    if (ns === 'cosplayer') return AppStrings.get('tag_ns_cosplayer')
    if (ns === 'misc') return AppStrings.get('tag_ns_misc')
    if (ns === 'mixed') return AppStrings.get('tag_ns_mixed')
    if (ns === 'location') return AppStrings.get('tag_ns_location')
    if (ns === 'other') return AppStrings.get('tag_ns_other')
    if (ns === 'uploader') return AppStrings.get('tag_ns_uploader')
    if (ns === 'temp') return AppStrings.get('tag_ns_temp')
    return ns
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  build() {
    Column() {
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
        ForEach(
          this.suggestions,
          (s: EhTagSuggestion) => {
            this.rowDivider()
            ConciseListRow({
              title: this.suggestionTitle(s),
              subtitle: s.label(),
              leadingIcon: $r('sys.symbol.magnifyingglass'),
              showChevron: false,
              action: () => {
                this.addFromSuggestion(s)
              },
            })
          },
          (s: EhTagSuggestion, index: number) =>
            `suggestion_${index}_${s.namespace}_${s.text}_${s.displayName}`.replace(/[^A-Za-z0-9_]/g, '_'),
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * One added-tag row — a standard ConciseListRow (title = translated name, subtitle = raw EH token) with a
 * visible relation selector (包含/任一/排除, the standard arrowtriangle dropdown). Deletion is the host List's
 * swipeAction, so the row has no × of its own. Exported so the host page can wrap it in a swipeable ListItem.
 */
@ComponentV2
export struct TagRow {
  @Param tag: QueryTag = new QueryTag('', '', TagRelation.AND);
  @Param index: number = -1;
  @Param displayName: string = '';
  @Event onSetRelation: (index: number, relation: number) => void = () => {};
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
    Column() {
      ConciseListRow({
        title: this.title(),
        subtitle: this.subtitle(),
        showChevron: false,
        suffixBuilderParam: () => {
          this.Suffix()
        },
      })
    }
    .bindMenu(this.menuShown, this.RelationMenu, {
      placement: Placement.BottomRight,
      onDisappear: () => {
        this.menuShown = false
      },
    })
  }

  @Builder
  private Suffix() {
    // Relation dropdown — same label+arrowtriangle look as ConciseListRow's own trailingDropdown.
    Row({ space: ThemeConstants.SPACE_XS }) {
      Text(this.relLabel())
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor(this.relColor())
      SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
        .fontSize(ThemeConstants.FONT_SIZE_TITLE)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.menuShown = true
    })
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
