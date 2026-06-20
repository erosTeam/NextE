import { deviceInfo } from '@kit.BasicServicesKit'
import { uiMaterial } from '@kit.ArkUI'

let appSearchFieldSeq: number = 0

/**
 * Shared HDS-material search field (ported from V2Next). V2 two-way text: the parent owns the
 * value via `@Param text`, the field mirrors it into `@Local fieldText` and only pushes changes
 * out through `onTextChange` — build() reads `fieldText`, NEVER the external keyword, so typing
 * never re-mounts the field (which would flap the soft keyboard when hosted in a title-bar
 * ComponentContent). `useSystemMaterial` gives the translucent immersive look in the HDS title
 * bar (V2Next routed this through user settings; NextE pins ULTRA_THIN). `searchButtonText`
 * renders Search's built-in trailing button so a query can be run without the IME enter key.
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
        .height(40)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .systemMaterial(this.searchMaterial())
        .searchButton(this.searchButtonText)
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
      .height(40)
      .backgroundColor($r('app.color.card_background'))
      .searchButton(this.searchButtonText)
      .onChange((value: string) => {
        this.handleChange(value)
      })
      .onSubmit((value: string) => {
        this.handleSubmit(value)
      })
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

  private searchMaterial(): uiMaterial.Material | undefined {
    if (!deviceInfo.apiAvailable('26.0.0')) {
      return undefined
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
    })
  }
}
