import {
  ThemeConstants,
  EhGallery,
  TagGroup,
  SimpleTag,
  EhUsertag,
  EhConstants,
  GroupedListSection,
  UserTagStore,
  UserTagSignal,
  connectUserTagSignal,
} from 'shared'

/**
 * Detail-page tag groups (namespace label + wrapped chips), one row per namespace. Shares
 * the GroupedListSection card chrome with the header/preview cards.
 *
 * eros_fe TagGroupItem: the NAMESPACE label is namespace-colored (tagColorTagType), while each MEMBER
 * chip takes the user's own per-tag color (getColorCode), neutral grey when uncolored — never namespace.
 */
@ComponentV2
export struct GalleryTagsCard {
  @Require @Param gallery: EhGallery;
  // Reactive bump from the usertag loader; read in the chip key so chips re-color on a late My Tags load.
  private tagSig: UserTagSignal = connectUserTagSignal();

  // Member chip background: the user's own fill color for this tag, else neutral grey. Never namespace.
  chipBg(t: SimpleTag, ns: string): ResourceColor {
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(ns, t.text)
    if (u !== undefined && u.fillColor.length > 0) {
      return u.fillColor
    }
    return $r('sys.color.ohos_id_color_sub_background')
  }

  // Member chip text color. The user's per-gallery tag VOTE wins first (eros_fe colors the tag text
  // green when upvoted / red when downvoted, ahead of any custom colour); then the user's own EH-chosen
  // tag text colour; then neutral secondary. Read-only — tapping a chip searches, it does not vote.
  chipText(t: SimpleTag, ns: string): ResourceColor {
    if (t.vote > 0) {
      return $r('app.color.tag_vote_up')
    }
    if (t.vote < 0) {
      return $r('app.color.tag_vote_down')
    }
    const u: EhUsertag | undefined = UserTagStore.getInstance().lookup(ns, t.text)
    if (u !== undefined && u.textColor.length > 0) {
      return u.textColor
    }
    return $r('sys.color.font_secondary')
  }

  build() {
    GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
      Column({ space: ThemeConstants.SPACE_SM }) {
        // Section header (eros_fe MiniTitle "Tags") — the tags card was the only lower section missing
        // its title, breaking parity with eros_fe and with NextE's own Comments/Previews card chrome.
        Text($r('app.string.gallery_tags'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        ForEach(
          this.gallery.tagGroups,
          (tg: TagGroup) => {
            Row({ space: ThemeConstants.SPACE_SM }) {
              // The NAMESPACE HEADER carries the namespace color (eros_fe colors the type header,
              // not the members) and its LOCALIZED label (eros_fe translateTagType: 作者/女性/原作…),
              // not the raw English word; a fixed-width pill keeps rows aligned like a color legend.
              Text(EhConstants.tagNamespaceLabel(tg.namespace))
                .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                .lineHeight(ThemeConstants.CHIP_LINE_HEIGHT)
                .fontColor($r('sys.color.font_primary'))
                .backgroundColor(EhConstants.tagNamespaceColor(tg.namespace))
                .borderRadius(ThemeConstants.CHIP_RADIUS)
                .textAlign(TextAlign.Center)
                .padding({ left: 6, right: 6, top: ThemeConstants.CHIP_PADDING_V, bottom: ThemeConstants.CHIP_PADDING_V })
                .constraintSize({ minWidth: 44 })
                .flexShrink(0)
                .maxLines(1)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(
                  tg.tags,
                  (t: SimpleTag) => {
                    // Neutral grey unless the USER colored this exact tag (eros_fe getColorCode).
                    Text(t.display())
                      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
                      .lineHeight(ThemeConstants.CHIP_LINE_HEIGHT)
                      .fontColor(this.chipText(t, tg.namespace))
                      .backgroundColor(this.chipBg(t, tg.namespace))
                      .borderRadius(ThemeConstants.CHIP_RADIUS)
                      .padding({ left: 8, right: 8, top: ThemeConstants.CHIP_PADDING_V, bottom: ThemeConstants.CHIP_PADDING_V })
                      .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
                  },
                  // version in the key subscribes the card + re-colors chips on a late My Tags load.
                  (t: SimpleTag) => `${this.tagSig.version}:${tg.namespace}:${t.text}`,
                )
              }.layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          },
          (tg: TagGroup) => tg.namespace,
        )
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
