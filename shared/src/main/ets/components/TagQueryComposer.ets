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

/** A term's relation to the query: AND = space (default), OR = '~' prefix (EH native tilde), NOT = '-'. */
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

/** A tag paired with its index in the full parsed list, so a zoned chip can mutate the right term. */
class IndexedTag {
  tag: QueryTag
  index: number

  constructor(tag: QueryTag, index: number) {
    this.tag = tag
    this.index = index
  }
}

/**
 * Graphical EH-query composer — a stronger take on eros_fe's flat AND-only tag list. The user searches
 * tags (local translation DB + EH /api.php tagsuggest, same pipeline as the search page), taps a suggestion
 * to add a CHIP, then taps a chip to set its relation 包含(且,AND) / 任一(或,OR) / 排除(否,NOT) via a menu —
 * never typing EH operators. Chips render in three zones; the set serialises to the canonical EH query
 * string using EH's native operators (space = AND, '~' = OR, '-' = NOT), so the single `query` string the
 * parent owns flows unchanged through f_search. Built on AppSearchField (keyboard-stable) so typing never
 * flaps the IME; chips contain no TextInput so relation edits never re-mount a field.
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
      tags.push(new QueryTag(s.namespace.toLowerCase(), s.text, TagRelation.AND))
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

  private zoneItems(relation: number): IndexedTag[] {
    const out: IndexedTag[] = []
    this.tags().forEach((t: QueryTag, i: number) => {
      if (t.relation === relation) {
        out.push(new IndexedTag(t, i))
      }
    })
    return out
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
      Column({ space: ThemeConstants.SPACE_SM }) {
        Text($r('app.string.tag_compose_legend'))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.zoneItems(TagRelation.AND).length > 0) {
          this.Zone($r('app.string.tag_compose_zone_include'), TagRelation.AND)
        }
        if (this.zoneItems(TagRelation.OR).length > 0) {
          this.Zone($r('app.string.tag_compose_zone_or'), TagRelation.OR)
        }
        if (this.zoneItems(TagRelation.NOT).length > 0) {
          this.Zone($r('app.string.tag_compose_zone_exclude'), TagRelation.NOT)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private Zone(caption: ResourceStr, relation: number) {
    // All three relation zones share one layout (caption + chip flow); the caption is the only
    // differentiator, so they stay visually consistent (no zone gets a special container).
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(caption)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor($r('sys.color.font_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.zoneItems(relation),
          (it: IndexedTag) => {
            TagChip({
              tag: it.tag,
              index: it.index,
              onSetRelation: (index: number, rel: number) => {
                this.setRelation(index, rel)
              },
              onRemove: (index: number) => {
                this.removeTag(index)
              },
            })
          },
          (it: IndexedTag) => `${it.tag.relation}:${it.tag.namespace}:${it.tag.text}:${it.index}`,
        )
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** One tag chip: namespace-colored, shows include/exclude state, tap opens a relation menu (且/或/否 + 移除). */
@ComponentV2
struct TagChip {
  @Param tag: QueryTag = new QueryTag('', '', TagRelation.AND);
  @Param index: number = -1;
  @Event onSetRelation: (index: number, relation: number) => void = () => {};
  @Event onRemove: (index: number) => void = () => {};
  @Local private menuShown: boolean = false;

  private label(): string {
    const v: string = this.tag.text
    return this.tag.namespace.length > 0
      ? `${EhConstants.expandNamespace(this.tag.namespace)}:${v}`
      : v
  }

  private isNot(): boolean {
    return this.tag.relation === TagRelation.NOT
  }

  build() {
    // Search-page chip grammar: ONE neutral pill, namespace shown by a small leading color dot (not a
    // flooded background). Exclude is signalled ONLY by red (a red '−' + red text), never strikethrough or
    // dimming (which read as "deleted/disabled", not "excluded").
    Row({ space: ThemeConstants.SPACE_XS }) {
      if (this.isNot()) {
        Text('−')
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Red)
      } else if (this.tag.namespace.length > 0) {
        Circle({ width: 8, height: 8 })
          .fill(EhConstants.tagNamespaceColor(this.tag.namespace))
      }
      Text(this.label())
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontColor(this.isNot() ? Color.Red : $r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(14)
        .fontColor([this.isNot() ? Color.Red : $r('sys.color.font_secondary')])
        .onClick(() => {
          this.onRemove(this.index)
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
    .backgroundColor(this.isNot() ? '#14FF3B30' : $r('sys.color.ohos_id_color_button_normal'))
    .constraintSize({ maxWidth: '90%' })
    .onClick(() => {
      this.menuShown = true
    })
    .bindMenu(this.menuShown, this.RelationMenu, {
      placement: Placement.Bottom,
      onDisappear: () => {
        this.menuShown = false
      },
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
      SettingsCheckedMenuItem({
        label: $r('app.string.tag_compose_remove'),
        selected: false,
        selectAction: () => {
          this.onRemove(this.index)
          this.menuShown = false
        },
      })
    }
    .backgroundColor($r('app.color.card_background'))
  }
}
