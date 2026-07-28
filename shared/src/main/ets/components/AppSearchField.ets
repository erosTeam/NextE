import { deviceInfo } from '@kit.BasicServicesKit'
import { AppPrompt } from '../utils/AppPrompt'
import { ThemeConstants } from '../theme/ThemeConstants'
import { connectThemeDisplay, ThemeDisplayState } from '../state/AppearanceState'

let appSearchFieldSeq: number = 0

/**
 * Shared HDS-material search field (ported from V2Next). V2 two-way text: the parent owns the
 * value via `@Param text`, the field mirrors it into `@Local fieldText` and only pushes changes
 * out through `onTextChange` — build() reads `fieldText`, NEVER the external keyword, so typing
 * never re-mounts the field (which would flap the soft keyboard when hosted in a title-bar
 * ComponentContent). `useSystemMaterial` gives the translucent immersive look in the HDS title
 * bar and uses the API-26 native material's semantic automatic grade. `searchButtonText` renders
 * Search's built-in trailing button so a query can be run without the IME enter key.
 */
@ComponentV2
export struct AppSearchField {
  @Param text: string = '';
  @Local fieldText: string = '';
  @Param placeholder: ResourceStr = '';
  @Param autoFocus: boolean = false;
  @Param searchButtonText: string = '';
  @Param useSystemMaterial: boolean = false;
  @Event onTextChange?: (value: string) => void;
  @Event onSubmit?: (value: string) => void;
  // Search fields can live inside cached title-bar ComponentContent on API levels without system material.
  @Local themeDisplay: ThemeDisplayState = connectThemeDisplay();
  // Unique id so getFocusController().requestFocus can target this specific Search instance.
  private fieldId: string = `appSearchField-${appSearchFieldSeq++}`;

  aboutToAppear(): void {
    this.fieldText = this.text
    if (this.autoFocus) {
      this.requestSearchFocus()
    }
  }

  @Monitor('autoFocus')
  onAutoFocusChange(): void {
    if (this.autoFocus) {
      this.requestSearchFocus()
    }
  }

  @Monitor('text')
  onExternalTextChange(): void {
    if (this.text !== this.fieldText) {
      this.fieldText = this.text
    }
  }

  build() {
    if (this.useSystemMaterial && deviceInfo.apiAvailable('26.0.0')) {
      Search({ value: this.fieldText, placeholder: this.placeholder })
        .id(this.fieldId)
        .height(ThemeConstants.SEARCH_FIELD_HEIGHT)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .systemMaterial(AppPrompt.searchSystemMaterial())
        .searchButton(this.searchButtonText, { fontColor: ThemeConstants.BRAND_PRIMARY })
        .onChange((value: string) => {
          this.handleChange(value)
        })
        .onSubmit((value: string) => {
          this.handleSubmit(value)
        })
    } else {
      this.PlainSearchField()
    }
  }

  @Builder
  private PlainSearchField() {
    // Below API 26 (no component-level system material): a solid readable pill.
    Search({ value: this.fieldText, placeholder: this.placeholder })
      .id(this.fieldId)
      .width('100%')
      .height(ThemeConstants.SEARCH_FIELD_HEIGHT)
      .backgroundColor(this.themeTracked($r('app.color.card_background')))
      .searchButton(this.searchButtonText, { fontColor: ThemeConstants.BRAND_PRIMARY })
      .onChange((value: string) => {
        this.handleChange(value)
      })
      .onSubmit((value: string) => {
        this.handleSubmit(value)
      })
  }

  // The color is unchanged; the effectiveDark read registers a dependency so cached search fields repaint.
  private themeTracked(color: ResourceColor): ResourceColor {
    return this.themeDisplay.effectiveDark ? color : color
  }

  private handleChange(value: string): void {
    this.fieldText = value
    if (this.onTextChange) {
      this.onTextChange(value)
    }
  }

  private handleSubmit(value: string): void {
    if (this.onSubmit) {
      this.onSubmit(value)
    }
  }

  private requestSearchFocus(): void {
    // Deferred a frame so the Search is mounted before requesting focus.
    setTimeout(() => {
      this.getUIContext().getFocusController().requestFocus(this.fieldId)
    }, 80)
  }
}
