import { EhConstants } from '../constants/EhConstants'

/**
 * Lightweight tag-translation lookup.
 *
 * eros_fe uses a local EhTagTranslation database and fills EhUsertag.translate before rendering the
 * My Tags subtitle. NextE does not have the full downloadable DB yet, so this service is the stable
 * entry point for that future database while providing a small built-in baseline for common EH tags.
 */
export class TagTranslationService {
  static translateFullTag(fullTag: string): string {
    const normalized: string = TagTranslationService.normalize(fullTag)
    switch (normalized) {
      case 'language:chinese':
        return '中文'
      case 'language:japanese':
        return '日文'
      case 'language:english':
        return '英文'
      case 'language:translated':
        return '已翻译'
      case 'female:big breasts':
        return '巨乳'
      case 'female:sole female':
        return '单女主'
      case 'female:paizuri':
        return '乳交'
      case 'female:group':
        return '群交'
      case 'male:sole male':
        return '单男主'
      case 'misc:full color':
        return '全彩'
      case 'misc:uncensored':
        return '无码'
      case 'other:multi-work series':
        return '多作品系列'
      default:
        return ''
    }
  }

  private static normalize(fullTag: string): string {
    const text: string = fullTag.trim().toLowerCase()
    const idx: number = text.indexOf(':')
    if (idx <= 0) {
      return `misc:${text}`
    }
    const ns: string = EhConstants.expandNamespace(text.substring(0, idx))
    const tag: string = text.substring(idx + 1).trim()
    return `${ns}:${tag}`
  }
}
