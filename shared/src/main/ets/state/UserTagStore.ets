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

  static getInstance(): UserTagStore {
    if (UserTagStore.instance === null) {
      UserTagStore.instance = new UserTagStore()
    }
    return UserTagStore.instance
  }

  setTags(tags: EhUsertag[]): void {
    const m: Map<string, EhUsertag> = new Map()
    tags.forEach((t: EhUsertag) => {
      const key: string = EhConstants.canonicalTagText(t.tag).toLowerCase().trim()
      if (key.length === 0) {
        return
      }
      UserTagStore.setAlias(m, key, t)
      const idx: number = key.indexOf(':')
      if (idx >= 0) {
        const ns: string = key.substring(0, idx).trim()
        const plain: string = key.substring(idx + 1).trim()
        if (plain.length > 0) {
          UserTagStore.setAlias(m, `${EhConstants.expandNamespace(ns)}:${plain}`, t)
          UserTagStore.setAlias(m, `${EhConstants.compactNamespace(ns)}:${plain}`, t)
          // Plain-tag fallback (no namespace), like eros_fe getColorCode's second lookup.
          UserTagStore.setAlias(m, plain, t)
        }
      }
    })
    this.index = m
  }

  /** Look up a list tag by namespace + text (eros_fe: try "ns:tag" first, then plain "tag"). */
  lookup(namespace: string, tag: string): EhUsertag | undefined {
    const t: string = EhConstants.canonicalTagText(tag).toLowerCase().trim()
    const ns: string = namespace.toLowerCase().trim()
    if (ns.length > 0) {
      const fullNs: string = EhConstants.expandNamespace(ns)
      const shortNs: string = EhConstants.compactNamespace(ns)
      const keys: string[] = [`${ns}:${t}`, `${fullNs}:${t}`, `${shortNs}:${t}`]
      for (let i = 0; i < keys.length; i++) {
        const found: EhUsertag | undefined = this.index.get(keys[i])
        if (found !== undefined) {
          return found
        }
      }
    }
    return this.index.get(t)
  }

  private static setAlias(index: Map<string, EhUsertag>, key: string, tag: EhUsertag): void {
    if (key.length > 0 && !index.has(key)) {
      index.set(key, tag)
    }
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
