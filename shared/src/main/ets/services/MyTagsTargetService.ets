import { EhConstants } from '../constants/EhConstants'
import { EhMytags, EhMytagSet, EhUsertag } from '../model/EhMytags'
import { EhApiService } from '../network/EhApiService'
import { UserTagContextService, UserTagRequestContext } from './UserTagContextService'

export class MyTagsTargetResolveResult {
  targetTag: string = ''
  found: boolean = false
  tag: EhUsertag | null = null
  mytags: EhMytags = new EhMytags()
  tagsets: EhMytagSet[] = []
  tagsetId: string = ''
}

export class MyTagsTargetService {
  static normalizeFullTag(fullTag: string): string {
    const tag: string = EhConstants.canonicalTagText(fullTag).toLowerCase().trim()
    const idx: number = tag.indexOf(':')
    if (idx <= 0) {
      return tag
    }
    const namespace: string = EhConstants.expandNamespace(tag.substring(0, idx))
    const key: string = tag.substring(idx + 1).trim()
    return namespace.length > 0 && key.length > 0 ? `${namespace}:${key}` : tag
  }

  static findLoadedTag(mytags: EhMytags, fullTag: string): EhUsertag | undefined {
    const target: string = MyTagsTargetService.normalizeFullTag(fullTag)
    if (target.length === 0) {
      return undefined
    }
    return mytags.tags.find((t: EhUsertag) => {
      return MyTagsTargetService.normalizeFullTag(t.tag) === target
    })
  }

  static async resolve(request: UserTagRequestContext, fullTag: string): Promise<MyTagsTargetResolveResult | null> {
    const result: MyTagsTargetResolveResult = new MyTagsTargetResolveResult()
    result.targetTag = MyTagsTargetService.normalizeFullTag(fullTag)
    if (result.targetTag.length === 0) {
      return result
    }
    if (!UserTagContextService.isCurrentAuthenticated(request)) {
      return null
    }

    const root: EhMytags = await EhApiService.getInstance().getMyTags(request.isEx, '')
    if (!UserTagContextService.isCurrentAuthenticated(request)) {
      return null
    }
    result.mytags = root
    result.tagsets = root.tagSets
    result.tagsetId = MyTagsTargetService.defaultTagset(root)

    const rootTag: EhUsertag | undefined = MyTagsTargetService.findLoadedTag(root, result.targetTag)
    if (rootTag !== undefined) {
      result.found = true
      result.tag = rootTag
      return result
    }

    for (let i = 0; i < root.tagSets.length; i++) {
      if (!UserTagContextService.isCurrentAuthenticated(request)) {
        return null
      }
      const tagset: EhMytagSet = root.tagSets[i]
      if (tagset.tagsetId.length === 0 || tagset.tagsetId === root.currentTagset) {
        continue
      }
      const scoped: EhMytags = await EhApiService.getInstance().getMyTags(request.isEx, tagset.tagsetId)
      if (!UserTagContextService.isCurrentAuthenticated(request)) {
        return null
      }
      const scopedTag: EhUsertag | undefined = MyTagsTargetService.findLoadedTag(scoped, result.targetTag)
      if (scopedTag !== undefined) {
        result.found = true
        result.tag = scopedTag
        result.mytags = scoped
        result.tagsetId = MyTagsTargetService.defaultTagset(scoped, tagset.tagsetId)
        return result
      }
    }
    return UserTagContextService.isCurrentAuthenticated(request) ? result : null
  }

  private static defaultTagset(mytags: EhMytags, fallback: string = ''): string {
    if (mytags.currentTagset.length > 0) {
      return mytags.currentTagset
    }
    if (fallback.length > 0) {
      return fallback
    }
    if (mytags.tagSets.length > 0) {
      return mytags.tagSets[0].tagsetId
    }
    return ''
  }
}
