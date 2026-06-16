/**
 * Responsive grid column math (eros_fe SliverGridDelegateWithMaxCrossAxisExtent model). Columns are
 * DERIVED from the available pane width and a minimum comfortable column width + inter-column gap —
 * never a hardcoded count. A wider pane yields more columns, a narrower one fewer, always >= 1, so a
 * phone, a foldable, and a tablet each get an appropriately-sized thumbnail instead of a fixed grid
 * that is too narrow on big screens or too cramped on small ones.
 */
export class ResponsiveGrid {
  /** Number of columns of at least `minColumnWidth` that fit `availableWidth` (both in vp). */
  static columns(availableWidth: number, minColumnWidth: number, gap: number): number {
    if (availableWidth <= 0 || minColumnWidth <= 0) {
      return 1
    }
    // (n cols + (n-1) gaps) <= availableWidth  ⇒  n <= (availableWidth + gap) / (minColumnWidth + gap)
    const n: number = Math.floor((availableWidth + gap) / (minColumnWidth + gap))
    return n > 0 ? n : 1
  }

  /** Width (vp) of one column once `columns` share `availableWidth` minus the (columns-1) gaps. */
  static columnWidth(availableWidth: number, columns: number, gap: number): number {
    if (columns <= 0) {
      return availableWidth
    }
    return (availableWidth - (columns - 1) * gap) / columns
  }
}
