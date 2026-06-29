import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  ThemeConstants,
  AppStrings,
  connectNavStack,
  connectLayoutSafeArea,
  LayoutSafeAreaState,
  immersiveTitleBarOpts,
  connectCustomProfiles,
  CustomProfilesState,
  CustomProfile,
  CustomProfilesSettings,
  PROFILE_TYPE_POPULAR,
  PROFILE_TYPE_WATCHED,
  PROFILE_TYPE_TOPLIST,
  PROFILE_TYPE_FAVORITE,
} from 'shared'

/**
 * Manage the home sub-tabs: long-press a row to drag-reorder (List.onMove), toggle a tab's visibility,
 * or swipe a custom tab left to delete (built-ins are hide-only). Mirrors AccountPage's swipe/list chrome
 * but uses a raw List (not SecondaryListScaffold) so onMove can attach to the single profile ForEach.
 * Row tap (open the editor) is wired in Phase 4.
 */
@ComponentV2
export struct TabManagerPage {
  @Local profiles: CustomProfilesState = connectCustomProfiles();
  private layout: LayoutSafeAreaState = connectLayoutSafeArea();
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Title bar with a top-right '+' that opens the editor in create mode (empty uuid param).
  private titleBar(): Record<string, Object> {
    const item: Record<string, Object> = {
      'label': AppStrings.get('tabs_create_title'),
      'icon': $r('sys.symbol.plus'),
      'isEnabled': true,
      'action': (): void => {
        this.stack.pushPathByName('TabEdit', '')
      },
    }
    const itemWrap: Record<string, Object> = { 'content': item }
    const menu: Record<string, Object> = { 'value': [itemWrap], 'maxCount': 1 }
    const title: Record<string, Object> = { 'mainTitle': AppStrings.get('tabs_manage_title') }
    const content: Record<string, Object> = { 'title': title, 'menu': menu }
    return immersiveTitleBarOpts(content)
  }

  private typeKey(listType: string): string {
    if (listType === PROFILE_TYPE_POPULAR) {
      return 'tab_type_popular'
    }
    if (listType === PROFILE_TYPE_WATCHED) {
      return 'tab_type_watched'
    }
    if (listType === PROFILE_TYPE_TOPLIST) {
      return 'tab_type_toplist'
    }
    if (listType === PROFILE_TYPE_FAVORITE) {
      return 'tab_type_favorite'
    }
    return 'tab_type_gallery'
  }

  private typeIcon(p: CustomProfile): Resource {
    if (p.listType === PROFILE_TYPE_POPULAR) {
      return $r('sys.symbol.star')
    }
    if (p.listType === PROFILE_TYPE_WATCHED) {
      return $r('sys.symbol.bookmark')
    }
    if (p.listType === PROFILE_TYPE_TOPLIST) {
      return $r('sys.symbol.list_number')
    }
    if (p.listType === PROFILE_TYPE_FAVORITE) {
      return $r('sys.symbol.heart_fill')
    }
    // Gallery type: the builtin home keeps the grid icon; a custom (non-default) search group uses `more`
    // so it's visually distinct from the default home tab.
    return p.builtin ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.more')
  }

  private summary(p: CustomProfile): string {
    const base: string = AppStrings.get(this.typeKey(p.listType))
    const s: string = p.searchText.trim()
    return s.length > 0 ? `${base} · ${s}` : base
  }

  private confirmDelete(p: CustomProfile): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tab_delete_confirm_title'),
      message: $r('app.string.tab_delete_confirm_message'),
      primaryButton: { value: $r('app.string.common_cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: Color.Red,
        action: () => {
          CustomProfilesSettings.remove(this.ctx(), p.uuid)
        },
      },
    })
  }

  @Builder
  private DeleteAction(p: CustomProfile) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.White])
      }
      .width(48)
      .height(40)
      .backgroundColor(Color.Red)
      .onClick(() => {
        this.confirmDelete(p)
      })
    }
    .height('100%')
    .padding({ left: ThemeConstants.SPACE_MD, right: ThemeConstants.SPACE_MD })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ProfileRow(p: CustomProfile) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      SymbolGlyph(this.typeIcon(p))
        .fontSize(22)
        .fontColor([$r('sys.color.font_secondary')])
      Column({ space: 2 }) {
        Row({ space: ThemeConstants.SPACE_SM }) {
          Text(p.name)
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (p.builtin) {
            Text($r('app.string.tab_builtin_badge'))
              .fontSize(ThemeConstants.FONT_SIZE_TINY)
              .fontColor($r('sys.color.font_tertiary'))
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .borderRadius(ThemeConstants.RADIUS_SM)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          }
        }
        Text(this.summary(p))
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: !p.hidden })
        .selectedColor(ThemeConstants.BRAND_PRIMARY)
        .onChange((on: boolean) => {
          CustomProfilesSettings.setHidden(this.ctx(), p.uuid, !on)
        })
    }
    .width('100%')
    .padding(ThemeConstants.SPACE_MD)
    .borderRadius(ThemeConstants.RADIUS_CARD)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Center)
    .opacity(p.hidden ? 0.45 : 1)
  }

  build() {
    HdsNavDestination() {
      List({ space: ThemeConstants.SPACE_SM, scroller: this.scroller }) {
        ForEach(
          this.profiles.profiles,
          (p: CustomProfile) => {
            ListItem() {
              this.ProfileRow(p)
            }
            .swipeAction({
              end: p.builtin
                ? undefined
                : () => {
                    this.DeleteAction(p)
                  },
            })
            .onClick(() => {
              this.stack.pushPathByName('TabEdit', p.uuid)
            })
          },
          (p: CustomProfile, index: number) =>
            `profile_${index}_${p.uuid}_${p.name}_${p.hidden}_${p.listType}`.replace(/[^A-Za-z0-9_]/g, '_'),
        )
          .onMove((from: number, to: number) => {
            CustomProfilesSettings.reorder(this.ctx(), from, to)
          })
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
      .padding({
        top: this.layout.topAvoidHeight + ThemeConstants.TITLE_BAR_HEIGHT + ThemeConstants.SPACE_SM,
        left: ThemeConstants.SPACE_MD,
        right: ThemeConstants.SPACE_MD,
        bottom: this.layout.bottomAvoidHeight + ThemeConstants.SPACE_XL,
      })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar(this.titleBar())
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
