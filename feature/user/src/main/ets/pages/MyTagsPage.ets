import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  ThemeConstants,
  EhMytags,
  EhUsertag,
  EhMytagSet,
  EhApiService,
  connectSiteMode,
  DiagnosticLogger,
  PageLoadingState,
  PageErrorState,
  CardEmptyState,
  SecondaryListScaffold,
  GroupedListSection,
  immersiveTitleBar,
} from 'shared'

/**
 * My Tags (mytags) — the user's watched / hidden / color-flagged tags. Routed page off Settings.
 * Renders each tag as a chip in its own EH color (hidden tags dimmed); a watched tag gets a ring.
 * Loads via EhApiService.getMyTags (requires login). v1 is read-only; edits (apiuid/apikey) later.
 */
@ComponentV2
export struct MyTagsPage {
  @Local mytags: EhMytags = new EhMytags();
  @Local loading: boolean = true;
  @Local error: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load()
  }

  private async load(tagset: string = ''): Promise<void> {
    this.loading = true
    this.error = ''
    try {
      this.mytags = await EhApiService.getInstance().getMyTags(connectSiteMode().isEx, tagset)
    } catch (err) {
      const e = err as Error
      this.error = e.message
      DiagnosticLogger.warn('mytags', 'load_failed', e.message)
    }
    this.loading = false
  }

  private selectTagset(id: string): void {
    if (id !== this.mytags.currentTagset && !this.loading) {
      this.load(id)
    }
  }

  /** Distinct tag namespaces, in first-seen order, for grouped display. */
  private namespaces(): string[] {
    const seen: string[] = []
    this.mytags.tags.forEach((t: EhUsertag) => {
      const ns: string = t.namespace()
      if (!seen.includes(ns)) {
        seen.push(ns)
      }
    })
    return seen
  }

  private tagsIn(ns: string): EhUsertag[] {
    return this.mytags.tags.filter((t: EhUsertag) => t.namespace() === ns)
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({ scroller: this.scroller }) {
        if (this.loading) {
          ListItem() {
            PageLoadingState({ expand: false })
          }
        } else if (this.error.length > 0) {
          ListItem() {
            PageErrorState({
              message: this.error,
              expand: false,
              retryAction: () => {
                this.load()
              },
            })
          }
        } else if (this.mytags.tags.length === 0) {
          ListItem() {
            CardEmptyState({ message: $r('app.string.common_no_content'), expand: false })
          }
        } else {
          if (this.mytags.tagSets.length > 1) {
            ListItem() {
              this.TagsetBar()
            }
          }
          ListItem() {
            GroupedListSection({ inset: ThemeConstants.SPACE_MD }) {
              Column({ space: ThemeConstants.SPACE_MD }) {
                ForEach(
                  this.namespaces(),
                  (ns: string) => {
                    this.NamespaceGroup(ns)
                  },
                  (ns: string) => ns,
                )
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar($r('app.string.settings_mytags')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  // Two-level My Tags: a chip row to switch between the user's tag sets (mytags ?tagset=N).
  @Builder
  TagsetBar() {
    Scroll() {
      Row({ space: ThemeConstants.SPACE_SM }) {
        ForEach(
          this.mytags.tagSets,
          (s: EhMytagSet) => {
            Text(`${s.name} (${s.count})`)
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor(
                this.mytags.currentTagset === s.tagsetId
                  ? ThemeConstants.TEXT_ON_BRAND
                  : $r('sys.color.font_primary'),
              )
              .backgroundColor(
                this.mytags.currentTagset === s.tagsetId
                  ? ThemeConstants.BRAND_PRIMARY
                  : $r('app.color.card_background'),
              )
              .borderRadius(ThemeConstants.RADIUS_ROUND)
              .padding({
                left: ThemeConstants.SPACE_MD,
                right: ThemeConstants.SPACE_MD,
                top: ThemeConstants.SPACE_XS,
                bottom: ThemeConstants.SPACE_XS,
              })
              .maxLines(1)
              .onClick(() => {
                this.selectTagset(s.tagsetId)
              })
          },
          (s: EhMytagSet) => s.tagsetId,
        )
      }
      .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  // One namespace section: a header + that namespace's tag chips.
  @Builder
  NamespaceGroup(ns: string) {
    Column({ space: ThemeConstants.SPACE_XS }) {
      Text(ns)
        .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_emphasize'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(
          this.tagsIn(ns),
          (t: EhUsertag) => {
            this.TagChip(t)
          },
          (t: EhUsertag) => t.tagId,
        )
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TagChip(t: EhUsertag) {
    // Grouped by namespace, so the chip shows just the short tag (display), not the full ns:tag.
    Text(t.display.length > 0 ? t.display : t.tag)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      // EH-supplied text color (readable on its own fill); only force white when EH gave none.
      .fontColor(t.textColor.length > 0 ? t.textColor : ThemeConstants.TEXT_ON_BRAND)
      .backgroundColor(
        t.fillColor.length > 0
          ? t.fillColor
          : t.color.length > 0
            ? t.color
            : ThemeConstants.BRAND_PRIMARY,
      )
      .borderRadius(ThemeConstants.RADIUS_SM)
      .borderWidth(t.watched ? 2 : 0)
      .borderColor(Color.White)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM, top: 3, bottom: 3 })
      .margin({ right: ThemeConstants.SPACE_XS, bottom: ThemeConstants.SPACE_XS })
      .opacity(t.hidden ? 0.45 : 1)
  }
}
