import { hdsMaterial, HdsTabs, HdsTabsController, HdsTabsFloatingStyle } from '@kit.UIDesignKit'
import { ImmersiveMaterialSettings } from '../settings/ImmersiveMaterialSettings'
import {
  connectImmersiveMaterialSettings,
  ImmersiveMaterialSettingsState,
} from '../state/ImmersiveMaterialSettingsState'

/**
 * HDS floating-material capsule button.
 *
 * Ported from V2Next's HdsMiniBarButton, but keeps barWidth/barHeight independent so callers can
 * use a capsule instead of the original circular reply button. The activity box is part of the
 * component contract: it prevents HDS material/press animation clipping and must be measured by callers.
 */
@ComponentV2
export struct HdsCapsuleBarButton {
  @Param barWidth: number = 144;
  @Param barHeight: number = 46;
  @Param activityPadding: number = 16;
  @Param controller: HdsTabsController = new HdsTabsController();
  @Param maskColor: ResourceColor = Color.Transparent;
  @Param barBottomMargin: number = 16;
  @Param barPosition: BarPosition = BarPosition.End;
  @Param barOverlap: boolean = true;
  @Event onButtonClick?: () => void;
  private immersiveMaterial: ImmersiveMaterialSettingsState = connectImmersiveMaterialSettings();

  @BuilderParam buttonContent: () => void = this.defaultButtonBuilder;

  @Builder defaultButtonBuilder() {
    SymbolGlyph($r('sys.symbol.doc_plaintext'))
      .fontSize(18)
      .fontColor([$r('sys.color.brand')])
  }

  private activityWidth(): number {
    return this.barWidth + this.activityPadding * 2
  }

  private activityHeight(): number {
    return this.barHeight + this.activityPadding * 2
  }

  private currentMaterialType(): hdsMaterial.MaterialType {
    return ImmersiveMaterialSettings.effect(this.immersiveMaterial.level).materialType
  }

  private currentMaterialLevel(): hdsMaterial.MaterialLevel {
    return ImmersiveMaterialSettings.effect(this.immersiveMaterial.level).materialLevel
  }

  build() {
    Stack() {
      HdsTabs({ controller: this.controller }) {
        TabContent().tabBar(this.buttonContent())
      }
      .barWidth(this.barWidth)
      .barHeight(this.barHeight)
      .barOverlap(this.barOverlap)
      .barPosition(this.barPosition)
      .barFloatingStyle({
        gradientMask: {
          maskColor: this.maskColor,
        },
        barBottomMargin: this.barBottomMargin,
        systemMaterialEffect: {
          materialType: this.currentMaterialType(),
          materialLevel: this.currentMaterialLevel(),
        },
      } as HdsTabsFloatingStyle)
      .onTabBarClick(() => {
        if (this.onButtonClick) {
          this.onButtonClick()
        }
      })
      .width(this.activityWidth())
      .height(this.activityHeight())
      .clip(false)
    }
    .width(this.activityWidth())
    .height(this.activityHeight())
    .clip(false)
  }
}
