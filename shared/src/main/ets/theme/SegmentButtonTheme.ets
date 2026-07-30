import { ColorMetrics } from '@kit.ArkUI'

/**
 * Theme-aware system colors for SegmentButtonV2.
 *
 * SegmentButtonV2 color params are read-only and can otherwise keep the resource values resolved when a
 * retained or ComponentContent-hosted control was mounted. Callers pass ThemeDisplayState.effectiveDark so
 * their build depends on the current theme, while these helpers preserve the platform's native color tokens.
 */
export class SegmentButtonTheme {
  // `_effectiveDark` is intentionally evaluated by every caller: that @Trace read invalidates the host
  // build, then this fresh ColorMetrics instance makes SegmentButtonV2 accept the newly resolved resource.
  private static tracked(color: ResourceColor, _effectiveDark: boolean): ColorMetrics {
    return ColorMetrics.resourceColor(color)
  }

  static tabButtonBackground(effectiveDark: boolean): ColorMetrics {
    return SegmentButtonTheme.tracked(
      $r('sys.color.segment_button_v2_tab_button_background'),
      effectiveDark,
    )
  }

  static tabSelectedItemBackground(effectiveDark: boolean): ColorMetrics {
    return SegmentButtonTheme.tracked(
      $r('sys.color.segment_button_v2_tab_selected_item_background'),
      effectiveDark,
    )
  }

  static itemFont(effectiveDark: boolean): ColorMetrics {
    return SegmentButtonTheme.tracked($r('sys.color.font_secondary'), effectiveDark)
  }

  static tabSelectedItemFont(effectiveDark: boolean): ColorMetrics {
    return SegmentButtonTheme.tracked($r('sys.color.font_primary'), effectiveDark)
  }

  static multiItemBackground(effectiveDark: boolean): ColorMetrics {
    return SegmentButtonTheme.tracked(
      $r('sys.color.segment_button_v2_multi_capsule_button_background'),
      effectiveDark,
    )
  }
}
