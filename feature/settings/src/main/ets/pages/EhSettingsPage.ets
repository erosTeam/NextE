import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import {
  AppStrings,
  AuthState,
  ConciseListRow,
  CookieJarSettings,
  ClipboardLinkSettings,
  ClipboardLinkBuildFlag,
  ClipboardLinkSettingsState,
  CommentTranslationSettingsState,
  EhConstants,
  EhCookieStore,
  GroupedListSection,
  LlmSourceProfilesState,
  LocalBlockState,
  SecondaryListScaffold,
  SiteModeSettings,
  SiteModeState,
  SiteModeRequestFence,
  TagTranslationSettingsState,
  ThemeConstants,
  ToplistFilterSettings,
  ToplistFilterState,
  connectAuth,
  connectClipboardLinkSettings,
  connectCommentTranslationSettings,
  connectLocalBlock,
  connectLlmSourceProfiles,
  connectNavStack,
  NavStackHolder,
  connectSiteMode,
  connectTagTranslationSettings,
  connectToplistFilter,
  immersiveTitleBar,
} from 'shared'

/**
 * EH settings page grounded in eros_fe EhSettingPage. This lane only groups the EH account/site
 * actions NextE already owns; website settings, cloud sync, link handlers, and favorite write
 * behavior remain separate feature lanes.
 */
@ComponentV2
export struct EhSettingsPage {
  @Local siteMode: SiteModeState = connectSiteMode();
  @Local auth: AuthState = connectAuth();
  @Local toplistFilter: ToplistFilterState = connectToplistFilter();
  @Local clipboardLink: ClipboardLinkSettingsState = connectClipboardLinkSettings();
  @Local commentTranslation: CommentTranslationSettingsState = connectCommentTranslationSettings();
  @Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings();
  @Local llmSources: LlmSourceProfilesState = connectLlmSourceProfiles();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  @Local localBlock: LocalBlockState = connectLocalBlock();
  @Local switchingSite: boolean = false;
  @Local siteMenuShown: boolean = false;
  @Local clipboardSaving: boolean = false;
  // Keep the latest explicit site choice separate from the in-flight access check. A delayed
  // uconfig response may unlock Ex only while the same account still wants ExHentai.
  private desiredSiteIsEx: boolean = false;
  private scroller: Scroller = new Scroller();
  private stack: NavPathStack = connectNavStack().stack;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private siteLabel(): string {
    return this.siteMode.isEx ? 'ExHentai' : 'E-Hentai'
  }

  private enabledText(enabled: boolean): Resource {
    return enabled ? $r('app.string.common_on') : $r('app.string.common_off')
  }

  // Selecting a site from the dropdown (not a tap-to-cycle toggle). E-Hentai is always allowed;
  // ExHentai requires login + a real igneous, fetched on demand the first time (eros_fe getExIgneous).
  private selectSite(toEx: boolean): void {
    this.siteMenuShown = false
    this.desiredSiteIsEx = toEx
    const ctx: common.UIAbilityContext = this.ctx()
    if (!toEx) {
      SiteModeSettings.setEx(ctx, false)
      return
    }
    if (this.siteMode.isEx) {
      return
    }
    if (!this.auth.isLogin) {
      this.toast($r('app.string.site_ex_locked'))
      return
    }
    if (this.auth.hasIgneous) {
      SiteModeSettings.setEx(ctx, true)
      return
    }
    if (this.switchingSite) {
      return
    }
    const requestMember: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
    const requestPassHash: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_PASS_HASH)
    this.switchingSite = true
    this.toast($r('app.string.site_ex_checking'))
    CookieJarSettings.refreshIgneous(ctx)
      .then((ok: boolean) => {
        const activeMember: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_MEMBER_ID)
        const activePassHash: string = EhCookieStore.getInstance().get(EhConstants.COOKIE_PASS_HASH)
        if (!SiteModeRequestFence.canApplyExUnlock(
          this.desiredSiteIsEx,
          requestMember,
          requestPassHash,
          activeMember,
          activePassHash,
        )) {
          return
        }
        if (ok) {
          SiteModeSettings.setEx(ctx, true)
          this.toast($r('app.string.site_ex_unlocked'))
        } else {
          this.toast($r('app.string.site_ex_no_access'))
        }
      })
      .finally(() => {
        this.switchingSite = false
      })
  }

  @Builder
  SiteMenu() {
    Menu() {
      MenuItem({
        content: 'E-Hentai',
        symbolEndIcon: !this.siteMode.isEx
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          this.selectSite(false)
        })
      MenuItem({
        content: 'ExHentai',
        symbolEndIcon: this.siteMode.isEx
          ? new SymbolGlyphModifier($r('sys.symbol.checkmark'))
          : undefined,
      })
        .onClick(() => {
          this.selectSite(true)
        })
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private setToplistHiddenFilter(value: boolean): void {
    ToplistFilterSettings.save(this.ctx(), value)
  }

  private setClipboardLinkEnabled(value: boolean): void {
    if (this.clipboardSaving) {
      return
    }
    this.clipboardSaving = true
    ClipboardLinkSettings.setEnabled(this.ctx(), value)
      .then((applied: boolean) => {
        if (value && !applied) {
          this.toast($r('app.string.clipboard_link_permission_denied'))
        }
      })
      .finally(() => {
        this.clipboardSaving = false
      })
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'EhSettings'
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            Column() {
              ConciseListRow({
                title: $r('app.string.settings_site'),
                leadingIcon: $r('sys.symbol.house'),
                trailingText: this.siteLabel(),
                trailingDropdown: true,
                action: () => {
                  this.siteMenuShown = true
                },
              })
            }
            .bindMenu(this.siteMenuShown, this.SiteMenu, {
              placement: Placement.BottomRight,
              onDisappear: () => {
                this.siteMenuShown = false
              },
            })
          }
        }
        if (ClipboardLinkBuildFlag.CLIPBOARD_LINK_BUILD_ENABLED) {
          ListItem() {
            GroupedListSection() {
              ConciseListRow({
                title: $r('app.string.clipboard_link_detection'),
                subtitle: $r('app.string.clipboard_link_detection_hint'),
                leadingIcon: $r('sys.symbol.text_clipboard'),
                hasSwitch: true,
                checked: this.clipboardLink.enabled,
                switchAction: (value: boolean) => {
                  this.setClipboardLinkEnabled(value)
                },
              })
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.eh_settings_toplist_hidden_filter'),
              subtitle: $r('app.string.eh_settings_toplist_hidden_filter_hint'),
              leadingIcon: $r('sys.symbol.doc_text_badge_nosign'),
              hasSwitch: true,
              checked: this.toplistFilter.applyHiddenUserTags,
              switchAction: (value: boolean) => {
                this.setToplistHiddenFilter(value)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.local_block_title'),
              subtitle: $r('app.string.local_block_hint'),
              leadingIcon: $r('sys.symbol.nosign'),
              trailingText: `${this.localBlock.rules.length}`,
              action: () => {
                this.stack.pushPathByName('LocalBlockSettings', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.image_block_title'),
              subtitle: $r('app.string.image_block_hint'),
              leadingIcon: $r('sys.symbol.picture_slash'),
              action: () => {
                this.stack.pushPathByName('ImageBlockSettings', null)
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.comment_translation_settings_title'),
              subtitle: $r('app.string.comment_translation_settings_hint'),
              leadingIcon: $r('sys.symbol.translate'),
              trailingText: this.enabledText(this.commentTranslation.enabled),
              action: () => {
                this.stack.pushPathByName('CommentTranslationSettings', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.comic_translation_settings_title'),
              subtitle: $r('app.string.comic_translation_settings_hint'),
              leadingIcon: $r('sys.symbol.picture'),
              action: () => {
                this.stack.pushPathByName('ComicTranslationSettings', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.tag_translation_title'),
              subtitle:
                this.tagTranslation.version.length > 0
                  ? this.tagTranslation.version
                  : $r('app.string.tag_translation_not_installed'),
              leadingIcon: $r('sys.symbol.textformat'),
              trailingText: this.enabledText(this.tagTranslation.enabled),
              action: () => {
                this.stack.pushPathByName('TagTranslationSettings', null)
              },
            })
            this.rowDivider()
            ConciseListRow({
              title: $r('app.string.llm_sources_title'),
              subtitle: $r('app.string.llm_sources_hint'),
              leadingIcon: $r('sys.symbol.cloud'),
              action: () => {
                this.stack.pushPathByName('LlmSourceManager', null)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_eh')))
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDestination(this.stack)
    })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }
}
