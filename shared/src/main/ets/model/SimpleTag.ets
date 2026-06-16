/**
 * A lightweight gallery tag as shown on the list/detail surface (eros_fe SimpleTag).
 * `text` is the raw EH tag, `translat` the localized display (filled by TagTranslationService).
 * `color`/`backgroundColor` are the user's OWN per-tag color (from the usertag store) — list chips
 * are neutral by default and only take color when these are set; tags are NOT colored by namespace.
 * Hand-written field-by-field (ArkTS bans destructuring/spread on the eros_fe Dart source).
 */
export class SimpleTag {
  text: string = ''
  translat: string = ''
  namespace: string = '' // EH tag namespace (female/parody/artist…) — drives the list-chip color
  color: string = ''
  backgroundColor: string = ''
  // The logged-in user's vote on THIS tag for THIS gallery (eros_fe GalleryTag.vote): EH marks the
  // tag <a> with class "tup" (+1) / "tdn" (-1); 0 when not voted. Read-only display signal only.
  vote: number = 0

  constructor(text: string = '', translat: string = '', namespace: string = '') {
    this.text = text
    this.translat = translat
    this.namespace = namespace
  }

  /** Localized text if available, else the raw EH tag. */
  display(): string {
    return this.translat.length > 0 ? this.translat : this.text
  }

  copy(): SimpleTag {
    const t: SimpleTag = new SimpleTag(this.text, this.translat, this.namespace)
    t.color = this.color
    t.backgroundColor = this.backgroundColor
    t.vote = this.vote
    return t
  }
}
