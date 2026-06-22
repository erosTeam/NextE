import { EhUsertag } from '../model/EhMytags'
import { SimpleTag } from '../model/SimpleTag'
import { EhConstants } from '../constants/EhConstants'

/**
 * Global in-memory store of the user's My Tags (loaded from getMyTags when logged in). It drives the
 * per-tag custom COLOR on gallery list cards (eros_fe TagController) and the tag HIDE flag.
 *
 * PLAIN singleton — NOT AppStorageV2/@ObservedV2 on purpose: this is a lookup CACHE read at list-parse
 * time, not reactive UI state. Putting a 38-entry Map of model objects into the V2 observation graph made
 * every `index.get()` recurse through the deep-proxy and overflowed the stack on enrichment. A plain
 * singleton (like EhCookieStore) sidesteps that entirely.
 *
 * Hard rule: list tags are NEUTRAL by default; a chip only takes color when the USER colored that exact
 * tag in "My Tags" — never by namespace. `index` keys by lowercased "ns:tag" + a plain-tag fallback,
 * mirroring eros_fe's getColorCode lookup.
 */
export class UserTagStore {
  private static instance: UserTagStore | null = null
  private index: Map<string, EhUsertag> = new Map()
  private inlineIndex: Map<string, EhUsertag> = new Map()

  static getInstance(): UserTagStore {
    if (UserTagStore.instance === null) {
      UserTagStore.instance = new UserTagStore()
    }
    return UserTagStore.instance
  }

  setTags(tags: EhUsertag[]): void {
    const m: Map<string, EhUsertag> = new Map()
    tags.forEach((t: EhUsertag) => {
      UserTagStore.indexTag(m, t, false)
    })
    this.index = m
  }

  /**
   * E-Hentai list rows carry the user's tag colours inline even when the detail page does not.
   * eros_fe feeds those SimpleTag colours into TagController.addAllSimpleTag(), then detail
   * getColorCode() can reuse them. Keep that as a separate fallback index so My Tags still owns
   * hide/watch state and wins when both sources know the tag.
   */
  ingestInlineTags(tags: SimpleTag[]): boolean {
    let changed: boolean = false
    tags.forEach((t: SimpleTag) => {
      if (t.backgroundColor.length === 0 && t.color.length === 0) {
        return
      }
      const tagText: string = EhConstants.canonicalTagText(t.text).trim()
      if (tagText.length === 0) {
        return
      }
      const u: EhUsertag = new EhUsertag()
      const ns: string = EhConstants.expandNamespace(t.namespace).trim()
      u.tag = ns.length > 0 ? `${ns}:${tagText}` : tagText
      u.fillColor = t.backgroundColor
      u.color = t.backgroundColor
      u.textColor = t.color
      u.defaultColor = t.backgroundColor.length === 0
      changed = UserTagStore.indexTag(this.inlineIndex, u, true) || changed
    })
    return changed
  }

  /** Look up a list tag by namespace + text (eros_fe: try "ns:tag" first, then plain "tag"). */
  lookup(namespace: string, tag: string): EhUsertag | undefined {
    const fromMyTags: EhUsertag | undefined = UserTagStore.lookupIn(this.index, namespace, tag)
    if (fromMyTags !== undefined) {
      return fromMyTags
    }
    return UserTagStore.lookupIn(this.inlineIndex, namespace, tag)
  }

  private static lookupIn(index: Map<string, EhUsertag>, namespace: string, tag: string): EhUsertag | undefined {
    const t: string = EhConstants.canonicalTagText(tag).toLowerCase().trim()
    const ns: string = namespace.toLowerCase().trim()
    if (ns.length > 0) {
      const fullNs: string = EhConstants.expandNamespace(ns)
      const shortNs: string = EhConstants.compactNamespace(ns)
      const keys: string[] = [`${ns}:${t}`, `${fullNs}:${t}`, `${shortNs}:${t}`]
      for (let i = 0; i < keys.length; i++) {
        const found: EhUsertag | undefined = index.get(keys[i])
        if (found !== undefined) {
          return found
        }
      }
    }
    return index.get(t)
  }

  private static indexTag(index: Map<string, EhUsertag>, tag: EhUsertag, overwriteColors: boolean): boolean {
    const key: string = EhConstants.canonicalTagText(tag.tag).toLowerCase().trim()
    if (key.length === 0) {
      return false
    }
    let changed: boolean = UserTagStore.setAlias(index, key, tag, overwriteColors)
    const idx: number = key.indexOf(':')
    if (idx >= 0) {
      const ns: string = key.substring(0, idx).trim()
      const plain: string = key.substring(idx + 1).trim()
      if (plain.length > 0) {
        changed = UserTagStore.setAlias(index, `${EhConstants.expandNamespace(ns)}:${plain}`, tag, overwriteColors) || changed
        changed = UserTagStore.setAlias(index, `${EhConstants.compactNamespace(ns)}:${plain}`, tag, overwriteColors) || changed
        // Plain-tag fallback (no namespace), like eros_fe getColorCode's second lookup.
        changed = UserTagStore.setAlias(index, plain, tag, overwriteColors) || changed
      }
    }
    return changed
  }

  private static setAlias(index: Map<string, EhUsertag>, key: string, tag: EhUsertag, overwriteColors: boolean): boolean {
    if (key.length === 0) {
      return false
    }
    const existing: EhUsertag | undefined = index.get(key)
    if (existing === undefined) {
      index.set(key, tag)
      return true
    }
    if (!overwriteColors) {
      return false
    }
    let changed: boolean = false
    if (tag.fillColor.length > 0 && existing.fillColor !== tag.fillColor) {
      existing.fillColor = tag.fillColor
      existing.color = tag.color
      changed = true
    }
    if (tag.textColor.length > 0 && existing.textColor !== tag.textColor) {
      existing.textColor = tag.textColor
      changed = true
    }
    return changed
  }

  isHidden(namespace: string, tag: string): boolean {
    const u: EhUsertag | undefined = this.lookup(namespace, tag)
    return u !== undefined && u.hidden
  }

  /** True when ANY of a gallery's tags is one the user marked "hide" (eros_fe TagController.needHide). */
  anyHidden(tags: SimpleTag[]): boolean {
    return tags.some((t: SimpleTag) => this.isHidden(t.namespace, t.text))
  }

  hasAny(): boolean {
    return this.index.size > 0
  }
}
