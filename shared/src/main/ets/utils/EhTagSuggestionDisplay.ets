import { EhConstants } from '../constants/EhConstants'
import { AppStrings } from '../i18n/AppStrings'
import { EhTagSuggestion } from '../model/EhTagSuggestion'

/** Shared presentation policy for tag suggestions across search and tag-editing surfaces. */
export class EhTagSuggestionDisplay {
  static namespaceLabel(namespace: string): string {
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

  /** Returns the localized namespace plus translated tag body, or an empty string without a translation. */
  static localizedTitle(suggestion: EhTagSuggestion): string {
    if (suggestion.displayName.length === 0) {
      return ''
    }
    return `${EhTagSuggestionDisplay.namespaceLabel(suggestion.namespace)}:${suggestion.displayName}`
  }
}
