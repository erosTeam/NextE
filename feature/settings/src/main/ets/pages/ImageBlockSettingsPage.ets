import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  ImageBlockContributionBatch,
  ImageBlockContributionService,
  ImageBlockFeed,
  ImageBlockRepository,
  ImageBlockRule,
  ImageBlockSubscriptionService,
  ImageBlockSubscriptionUpdateResult,
  SecondaryListScaffold,
  ThemeConstants,
  immersiveTitleBar,
} from 'shared'

@ComponentV2
export struct ImageBlockSettingsPage {
  @Local feeds: ImageBlockFeed[] = [];
  @Local localRuleCount: number = 0;
  @Local localRules: ImageBlockRule[] = [];
  @Local contributionTotalCount: number = 0;
  @Local contributionReadyCount: number = 0;
  @Local contributionSkippedCount: number = 0;
  @Local contributionMissingSourceCount: number = 0;
  @Local contributionDuplicateCount: number = 0;
  @Local contributionInvalidCount: number = 0;
  @Local whitelistHashes: string[] = [];
  @Local updating: boolean = false;
  @Local deletingLocalRuleId: string = '';
  @Local deletingWhitelistHash: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reloadFeeds()
    this.reloadLocalRules()
    this.reloadWhitelist()
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private feedTitle(feed: ImageBlockFeed): string {
    return feed.title.length > 0 ? feed.title : feed.id
  }

  private totalRules(): number {
    let count: number = 0
    for (let i: number = 0; i < this.feeds.length; i++) {
      count += this.feeds[i].count
    }
    return count
  }

  private enabledFeeds(): number {
    let count: number = 0
    for (let i: number = 0; i < this.feeds.length; i++) {
      if (this.feeds[i].enabled) {
        count++
      }
    }
    return count
  }

  private statusText(): string {
    if (this.updating) {
      return AppStrings.get('image_block_updating')
    }
    if (this.feeds.length <= 0) {
      return AppStrings.get('image_block_no_subscriptions')
    }
    return `${this.enabledFeeds()}/${this.feeds.length} / ${this.totalRules()}`
  }

  private feedSubtitle(feed: ImageBlockFeed): string {
    return `${feed.count} ${AppStrings.get('image_block_rules')} / ${feed.url}`
  }

  private shortHash(hash: string): string {
    return hash.length > 8
      ? `${hash.substring(0, 4)}...${hash.substring(hash.length - 4)}`
      : hash
  }

  private localRuleSubtitle(rule: ImageBlockRule): string {
    const source: string = rule.sourceUrl.length > 0
      ? ` / ${rule.sourceUrl}`
      : ''
    return `pHash ${this.shortHash(rule.hash)} / T${rule.threshold}${source}`
  }

  private localRuleTitle(rule: ImageBlockRule): string {
    const label: string = rule.label.length > 0 ? rule.label : AppStrings.get('image_block_local_rule_title')
    if (rule.sourcePage > 0) {
      return `${label} / P${rule.sourcePage}`
    }
    return label
  }

  private contributionDraftTrailing(): string {
    if (this.contributionTotalCount <= 0) {
      return '0'
    }
    return `${this.contributionReadyCount}/${this.contributionTotalCount}`
  }

  private contributionSkipReasonText(): string {
    const parts: string[] = []
    if (this.contributionMissingSourceCount > 0) {
      parts.push(`${this.contributionMissingSourceCount} ${AppStrings.get('image_block_contribution_missing_source')}`)
    }
    if (this.contributionDuplicateCount > 0) {
      parts.push(`${this.contributionDuplicateCount} ${AppStrings.get('image_block_contribution_duplicate')}`)
    }
    if (this.contributionInvalidCount > 0) {
      parts.push(`${this.contributionInvalidCount} ${AppStrings.get('image_block_contribution_invalid')}`)
    }
    return parts.join(' / ')
  }

  private contributionDraftSubtitle(): string {
    const hint: string = AppStrings.get('image_block_contribution_draft_hint')
    if (this.contributionSkippedCount <= 0) {
      return hint
    }
    const reasons: string = this.contributionSkipReasonText()
    if (reasons.length <= 0) {
      return `${hint} ${AppStrings.get('image_block_contribution_skipped')} ${this.contributionSkippedCount}`
    }
    return `${hint} ${AppStrings.get('image_block_contribution_skipped')} ${this.contributionSkippedCount}: ${reasons}`
  }

  private reloadFeeds(): void {
    ImageBlockRepository.loadSubscriptions(this.ctx())
      .then((feeds: ImageBlockFeed[]) => {
        this.feeds = feeds
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_load_failed')}: ${error.message}`)
      })
  }

  private reloadLocalRules(): void {
    ImageBlockRepository.loadLocalRules(this.ctx())
      .then((rules: ImageBlockRule[]) => {
        this.localRules = rules
        this.localRuleCount = rules.length
        const batch: ImageBlockContributionBatch = ImageBlockContributionService.buildSubmissionBatchFromRules(rules)
        this.contributionTotalCount = batch.totalCount
        this.contributionReadyCount = batch.includedCount
        this.contributionSkippedCount = batch.skippedCount()
        this.contributionMissingSourceCount = batch.skippedMissingSourceCount
        this.contributionDuplicateCount = batch.skippedDuplicateHashCount
        this.contributionInvalidCount = batch.skippedInvalidCount
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_load_failed')}: ${error.message}`)
      })
  }

  private reloadWhitelist(): void {
    ImageBlockRepository.loadWhitelist(this.ctx())
      .then((hashes: string[]) => {
        this.whitelistHashes = hashes
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_load_failed')}: ${error.message}`)
      })
  }

  private updateDefault(): void {
    if (this.updating) {
      return
    }
    this.updating = true
    this.toast($r('app.string.image_block_update_started'))
    ImageBlockSubscriptionService.updateDefault(this.ctx())
      .then((result: ImageBlockSubscriptionUpdateResult) => {
        this.reloadFeeds()
        this.reloadLocalRules()
        this.reloadWhitelist()
        this.toast(`${AppStrings.get('image_block_update_finished')} ${result.updatedFeedCount}/${result.feedCount}, ${result.updatedRuleCount}`)
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.updating = false
      })
  }

  private confirmDeleteLocalRule(rule: ImageBlockRule): void {
    this.getUIContext().showAlertDialog({
      message: `${AppStrings.get('image_block_local_rule_delete_confirm')} ${rule.hash}`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteLocalRule(rule.id)
        },
      },
      })
  }

  private confirmDeleteWhitelistHash(hash: string): void {
    this.getUIContext().showAlertDialog({
      message: `${AppStrings.get('image_block_whitelist_delete_confirm')} ${hash}`,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.common_delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteWhitelistHash(hash)
        },
      },
      })
  }

  private copyContributionDraft(): void {
    try {
      const batch: ImageBlockContributionBatch =
        ImageBlockContributionService.buildSubmissionBatchFromRules(this.localRules)
      if (batch.includedCount <= 0 || batch.jsonl.length === 0) {
        this.toast($r('app.string.image_block_contribution_empty'))
        return
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, batch.jsonl)
      pasteboard.getSystemPasteboard().setDataSync(data)
      this.toast(`${AppStrings.get('image_block_contribution_copied')} ${batch.includedCount}/${batch.totalCount}`)
    } catch (error) {
      this.toast(`${AppStrings.get('image_block_contribution_failed')}: ${(error as Error).message}`)
    }
  }

  private deleteLocalRule(ruleId: string): void {
    if (ruleId.length === 0 || this.deletingLocalRuleId.length > 0) {
      return
    }
    this.deletingLocalRuleId = ruleId
    ImageBlockRepository.removeLocalRule(this.ctx(), ruleId)
      .then(() => {
        this.reloadLocalRules()
        this.toast($r('app.string.image_block_local_rule_deleted'))
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_local_rule_delete_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.deletingLocalRuleId = ''
      })
  }

  private deleteWhitelistHash(hash: string): void {
    if (hash.length === 0 || this.deletingWhitelistHash.length > 0) {
      return
    }
    this.deletingWhitelistHash = hash
    ImageBlockRepository.removeWhitelistHash(this.ctx(), hash)
      .then(() => {
        this.reloadWhitelist()
        this.toast($r('app.string.image_block_whitelist_deleted'))
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_whitelist_delete_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.deletingWhitelistHash = ''
      })
  }

  private setFeedEnabled(feedId: string, enabled: boolean): void {
    ImageBlockRepository.setSubscriptionEnabled(this.ctx(), feedId, enabled)
      .then(() => {
        this.reloadFeeds()
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
  }

  @Builder
  private rowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.ohos_id_color_list_separator'))
      .margin({ left: ThemeConstants.SPACE_MD })
  }

  @Builder
  private WhitelistDeleteSuffix(hash: string) {
    Button() {
      if (this.deletingWhitelistHash === hash) {
        LoadingProgress()
          .width(20)
          .height(20)
      } else {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.Red])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(Color.Transparent)
    .width(48)
    .height(40)
    .enabled(this.deletingWhitelistHash.length === 0)
    .onClick(() => {
      this.confirmDeleteWhitelistHash(hash)
    })
  }

  @Builder
  private WhitelistRow(hash: string) {
    ConciseListRow({
      title: $r('app.string.image_block_whitelist_hash_title'),
      subtitle: `pHash ${this.shortHash(hash)}`,
      leadingIcon: $r('sys.symbol.eye'),
      showChevron: false,
      isEnabled: this.deletingWhitelistHash !== hash,
      suffixPaddingRight: 0,
      suffixBuilderParam: () => {
        this.WhitelistDeleteSuffix(hash)
      },
    })
  }

  @Builder
  private LocalRuleDeleteSuffix(rule: ImageBlockRule) {
    Button() {
      if (this.deletingLocalRuleId === rule.id) {
        LoadingProgress()
          .width(20)
          .height(20)
      } else {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontColor([Color.Red])
      }
    }
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(Color.Transparent)
    .width(48)
    .height(40)
    .enabled(this.deletingLocalRuleId.length === 0)
    .onClick(() => {
      this.confirmDeleteLocalRule(rule)
    })
  }

  @Builder
  private LocalRuleRow(rule: ImageBlockRule) {
    ConciseListRow({
      title: this.localRuleTitle(rule),
      subtitle: this.localRuleSubtitle(rule),
      subtitleMaxLines: 2,
      leadingIcon: $r('sys.symbol.eye_slash'),
      showChevron: false,
      isEnabled: this.deletingLocalRuleId !== rule.id,
      suffixPaddingRight: 0,
      suffixBuilderParam: () => {
        this.LocalRuleDeleteSuffix(rule)
      },
    })
  }

  @Builder
  private ContributionDraftRow() {
    ConciseListRow({
      title: $r('app.string.image_block_contribution_draft'),
      subtitle: this.contributionDraftSubtitle(),
      leadingIcon: $r('sys.symbol.doc_plaintext'),
      trailingText: this.contributionDraftTrailing(),
      showChevron: false,
      isEnabled: this.contributionReadyCount > 0,
      action: () => {
        this.copyContributionDraft()
      },
    })
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
            ConciseListRow({
              title: $r('app.string.image_block_update_default'),
              subtitle: $r('app.string.image_block_update_default_hint'),
              leadingIcon: $r('sys.symbol.arrow_clockwise'),
              trailingText: this.statusText(),
              showChevron: false,
              isEnabled: !this.updating,
              action: () => {
                this.updateDefault()
              },
            })
          }
        }
        if (this.feeds.length > 0) {
          ListItem() {
            GroupedListSection() {
              ForEach(
                this.feeds,
                (feed: ImageBlockFeed, index: number) => {
                  ConciseListRow({
                    title: this.feedTitle(feed),
                    subtitle: this.feedSubtitle(feed),
                    subtitleMaxLines: 1,
                    leadingIcon: $r('sys.symbol.cloud'),
                    showChevron: false,
                    hasSwitch: true,
                    checked: feed.enabled,
                    switchAction: (value: boolean) => {
                      this.setFeedEnabled(feed.id, value)
                    },
                  })
                  if (index < this.feeds.length - 1) {
                    this.rowDivider()
                  }
                },
                (feed: ImageBlockFeed) => `${feed.id}:${feed.count}:${feed.enabled ? '1' : '0'}:${feed.sha256}`,
              )
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.image_block_local_rules'),
              subtitle: $r('app.string.image_block_local_rules_hint'),
              leadingIcon: $r('sys.symbol.eye_slash'),
              trailingText: `${this.localRuleCount}`,
              showChevron: false,
            })
            if (this.localRules.length > 0) {
              this.rowDivider()
              this.ContributionDraftRow()
              this.rowDivider()
              ForEach(
                this.localRules,
                (rule: ImageBlockRule, index: number) => {
                  this.LocalRuleRow(rule)
                  if (index < this.localRules.length - 1) {
                    this.rowDivider()
                  }
                },
                (rule: ImageBlockRule) => `${rule.id}:${rule.sourceUrl}:${rule.sourcePage}`,
              )
            }
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.image_block_whitelist'),
              subtitle: $r('app.string.image_block_whitelist_hint'),
              leadingIcon: $r('sys.symbol.eye'),
              trailingText: `${this.whitelistHashes.length}`,
              showChevron: false,
            })
            if (this.whitelistHashes.length > 0) {
              this.rowDivider()
              ForEach(
                this.whitelistHashes,
                (hash: string, index: number) => {
                  this.WhitelistRow(hash)
                  if (index < this.whitelistHashes.length - 1) {
                    this.rowDivider()
                  }
                },
                (hash: string) => hash,
              )
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('image_block_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
