import { common } from '@kit.AbilityKit'
import { AppStrings } from '../i18n/AppStrings'
import { ThemeConstants } from '../theme/ThemeConstants'
import { EhSpriteThumbnail } from './EhSpriteThumbnail'
import { EhGalleryImage } from '../model/EhGalleryImage'
import {
  IMAGE_BLOCK_SOURCE_LOCAL,
  ImageBlockDecision,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { ImageBlockRepository } from '../storage/ImageBlockRepository'
import { ImageBlockRuntimeService } from '../services/ImageBlockRuntimeService'
import { publishImageBlockRulesChanged } from '../state/ImageBlockRuntimeState'

// Tile image-frame aspect (height = width * aspect). A FIXED portrait frame so every tile — and thus
// every page number below it — sits at the same height regardless of each thumb's true aspect or a
// misdetected source dimension. EH manga previews are mostly portrait, so this fits the common case
// snugly while flat/wide thumbs letterbox (centered) inside the stable frame instead of shrinking the
// row and dragging the label baseline around.
const FRAME_ASPECT: number = 1.4

/**
 * One responsive preview-grid tile (detail inline GRID + the all-thumbnails page share it). The image
 * is CONTAINED + centered inside a fixed-size frame (no crop — the smaller of width-fit / height-fit is
 * chosen so the whole thumb shows, letterboxed over BG_SUB), and the page number sits at a fixed
 * position below the frame. So a flat/wide thumb, or a thumb whose sprite dimensions were misdetected,
 * never pulls the number or the row baseline — the tile geometry is constant.
 */
@ComponentV2
export struct PreviewThumbTile {
  @Require @Param image: EhGalleryImage;
  @Event onTap: () => void = () => {};
  @Local measuredWidth: number = 0;
  @Local menuShown: boolean = false;
  @Local busy: boolean = false;
  @Local imageBlockRevision: number = 0;
  @Local imageBlocked: boolean = false;
  @Local blockDecision: ImageBlockDecision = new ImageBlockDecision();

  private tileWidth(): number {
    return this.measuredWidth > 0 ? this.measuredWidth : ThemeConstants.PREVIEW_THUMB_MIN_W
  }

  private frameHeight(): number {
    return this.tileWidth() * FRAME_ASPECT
  }

  // Thumb true aspect (height / width); 0 when sprite dimensions are missing/misdetected.
  private thumbAspect(): number {
    return this.image.thumbWidth > 0 && this.image.thumbHeight > 0
      ? this.image.thumbHeight / this.image.thumbWidth
      : 0
  }

  // Contain: a thumb taller than the frame is fit by HEIGHT (its width then ≤ frame width); anything
  // else is fit by WIDTH (its height then ≤ frame height). Either way it fits inside the fixed frame.
  private fitByHeight(): boolean {
    const a: number = this.thumbAspect()
    return a > 0 && a > FRAME_ASPECT
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private addBlockRule(): void {
    if (this.busy) {
      return
    }
    const previousBlocked: boolean = this.imageBlocked
    const previousDecision: ImageBlockDecision = this.blockDecision
    this.busy = true
    this.imageBlocked = true
    ImageBlockRuntimeService.addLocalRuleForThumbnail(
      this.ctx(),
      this.image.thumbUrl,
      this.image.thumbWidth,
      this.image.thumbHeight,
      this.image.thumbOffsetX,
      this.image.spriteWidth,
      this.image.spriteHeight,
      this.image.sUrl,
      this.image.page,
    )
      .then((rule: ImageBlockRule) => {
        const decision: ImageBlockDecision = new ImageBlockDecision()
        decision.blocked = true
        decision.hash = rule.hash
        decision.ruleId = rule.id
        decision.sourceType = rule.sourceType
        decision.label = rule.label
        decision.threshold = rule.threshold
        decision.distance = 0
        this.imageBlocked = true
        this.blockDecision = decision
        this.imageBlockRevision++
        publishImageBlockRulesChanged('thumbnail-add')
        this.toast($r('app.string.image_block_thumb_blocked'))
      })
      .catch((error: Error) => {
        this.imageBlocked = previousBlocked
        this.blockDecision = previousDecision
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.busy = false
      })
  }

  private unblockMatchedRule(): void {
    if (this.busy) {
      return
    }
    const decision: ImageBlockDecision = this.blockDecision
    if (decision.hash.length === 0) {
      return
    }
    this.busy = true
    const task: Promise<void | string> = decision.sourceType === IMAGE_BLOCK_SOURCE_LOCAL
      ? ImageBlockRepository.removeLocalRule(this.ctx(), decision.ruleId)
      : ImageBlockRepository.ignoreRule(this.ctx(), decision.ruleId, decision.hash, decision.sourceType)
    task
      .then(() => {
        this.imageBlocked = false
        this.blockDecision = new ImageBlockDecision()
        this.imageBlockRevision++
        publishImageBlockRulesChanged('thumbnail-unblock-rule')
        this.toast($r('app.string.image_block_thumb_allowed'))
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.busy = false
      })
  }

  @Builder
  private ThumbMenu() {
    Menu() {
      if (this.imageBlocked) {
        MenuItem({ content: $r('app.string.image_block_thumb_allow') })
          .enabled(!this.busy)
          .onClick(() => {
            this.unblockMatchedRule()
            this.menuShown = false
          })
      } else {
        MenuItem({ content: $r('app.string.image_block_thumb_add') })
          .enabled(!this.busy)
          .onClick(() => {
            this.addBlockRule()
            this.menuShown = false
          })
      }
    }
  }

  build() {
    Column({ space: ThemeConstants.SPACE_XS }) {
      // Transparent layout slot: constant width × height only reserves alignment for the page number.
      // The visible sprite/image keeps its real aspect and owns the rounded clip; the slot must not render
      // as a grey letterbox container after the real thumbnail is loaded.
      Stack() {
        if (this.fitByHeight()) {
          EhSpriteThumbnail({
            url: this.image.thumbUrl,
            thumbWidth: this.image.thumbWidth,
            thumbHeight: this.image.thumbHeight,
            offsetX: this.image.thumbOffsetX,
            spriteWidth: this.image.spriteWidth,
            spriteHeight: this.image.spriteHeight,
            fitHeight: true,
            displayHeight: this.frameHeight(),
            enableImageBlock: true,
            forceImageBlocked: this.imageBlocked,
            imageBlockRevision: this.imageBlockRevision,
            onImageBlockStateChange: (blocked: boolean) => {
              this.imageBlocked = blocked
            },
            onImageBlockDecisionChange: (decision: ImageBlockDecision) => {
              this.blockDecision = decision
            },
            // Radius lives on the SPRITE/IMAGE itself (EhSpriteThumbnail clips its sprite to this radius),
            // not on a decorative outer layer — so the visible thumb has real rounded corners even when it
            // fills the frame. Matches the frame's THUMB_RADIUS so the silhouette is one consistent rounded rect.
            radius: ThemeConstants.THUMB_RADIUS,
          })
        } else {
          EhSpriteThumbnail({
            url: this.image.thumbUrl,
            thumbWidth: this.image.thumbWidth,
            thumbHeight: this.image.thumbHeight,
            offsetX: this.image.thumbOffsetX,
            spriteWidth: this.image.spriteWidth,
            spriteHeight: this.image.spriteHeight,
            displayWidth: this.tileWidth(),
            enableImageBlock: true,
            forceImageBlocked: this.imageBlocked,
            imageBlockRevision: this.imageBlockRevision,
            onImageBlockStateChange: (blocked: boolean) => {
              this.imageBlocked = blocked
            },
            onImageBlockDecisionChange: (decision: ImageBlockDecision) => {
              this.blockDecision = decision
            },
            radius: ThemeConstants.THUMB_RADIUS,
          })
        }
      }
      .width('100%')
      .height(this.frameHeight())
      .clip(true)
      .alignContent(Alignment.Center)
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            this.menuShown = true
          }),
      )
      .bindMenu(this.menuShown, this.ThumbMenu, {
        placement: Placement.Bottom,
        onDisappear: () => {
          this.menuShown = false
        },
      })

      // Page number — fixed position below the fixed frame, identical for every tile.
      Text(`${this.image.page}`)
        .fontSize(ThemeConstants.FONT_SIZE_TINY)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const parsed: number = Number.parseFloat(`${newValue.width}`)
      if (parsed > 0) {
        this.measuredWidth = parsed
      }
    })
    .onClick(() => {
      this.onTap()
    })
  }
}
