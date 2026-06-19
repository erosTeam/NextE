/** One EH tag suggestion returned by /api.php method=tagsuggest. */
export class EhTagSuggestion {
  namespace: string = ''
  text: string = ''

  constructor(namespace: string = '', text: string = '') {
    this.namespace = namespace
    this.text = text
  }

  label(): string {
    return this.namespace.length > 0 ? `${this.namespace}:${this.text}` : this.text
  }
}
