import { SimpleTag } from './SimpleTag'

/**
 * Tags grouped by namespace on the gallery detail page (eros_fe TagGroup), e.g.
 * namespace 'female' → [exhibitionism, huge breasts, ...]. Each tag's localized display
 * is filled by TagTranslationService later; M2 shows the raw EH tag.
 */
export class TagGroup {
  namespace: string = ''
  tags: SimpleTag[] = []

  constructor(namespace: string = '', tags: SimpleTag[] = []) {
    this.namespace = namespace
    this.tags = tags
  }

  copy(): TagGroup {
    return new TagGroup(this.namespace, this.tags.map((t: SimpleTag) => t.copy()))
  }
}
