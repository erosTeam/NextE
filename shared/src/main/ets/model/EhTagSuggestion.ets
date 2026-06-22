/** One EH tag suggestion, either EH /api.php tagsuggest or local tag-translation match. */
export class EhTagSuggestion {
  namespace: string = ''
  text: string = ''
  displayName: string = ''

  constructor(namespace: string = '', text: string = '', displayName: string = '') {
    this.namespace = namespace
    this.text = text
    this.displayName = displayName
  }

  label(): string {
    return this.namespace.length > 0 ? `${this.namespace}:${this.text}` : this.text
  }
}
