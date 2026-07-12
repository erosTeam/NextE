export function appSheetOptions(options: SheetOptions): SheetOptions {
  // A Sheet may resolve to POPUP on a wide window; POPUP otherwise defaults to a pass-through,
  // unmasked panel. App sheets are modal unless a concrete caller explicitly opts out with `true`.
  if (options.enableOutsideInteractive === undefined) {
    options.enableOutsideInteractive = false
  }
  options.enableFloatingDragBar = true
  return options
}
