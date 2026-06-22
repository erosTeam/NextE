/**
 * Generic retained-subtab item — the shared key/label model for EVERY subtab surface (Home source,
 * Toplist period, Favorites favcat, and future custom subtabs). The retained-subtab host renders one
 * retained page per `key`; the shared SubTabBar renders `label` (+ optional `count`) and its sliding
 * indicator. A surface builds its ordered TabItem[] (hardcoded, derived, or — for custom tabs — from a
 * dynamic source); the host and the bar both consume the SAME key model so they never drift.
 */
export class TabItem {
  // Stable identity — the Swiper page key and the selection-bus value. Must be unique + order-stable.
  key: string = ''
  // Display label for the selector bar.
  label: ResourceStr = ''
  // Optional trailing total (>=0 shows it, e.g. favcat counts; -1 hides it).
  count: number = -1
  // Optional selected/indicator accent color. Empty keeps the shared brand color.
  selectedColor: string = ''

  constructor(key: string, label: ResourceStr, count: number = -1, selectedColor: string = '') {
    this.key = key
    this.label = label
    this.count = count
    this.selectedColor = selectedColor
  }
}
