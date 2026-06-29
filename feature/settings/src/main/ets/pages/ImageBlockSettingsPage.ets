import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { HdsNavDestination } from '@kit.UIDesignKit'
import {
  AppModalScaffold,
  AppStrings,
  appSheetOptions,
  ConciseListRow,
  GroupedListSection,
  ImageBlockContributionBatch,
  ImageBlockContributionService,
  ImageBlockFeed,
  IMAGE_BLOCK_MAX_THRESHOLD,
  IMAGE_BLOCK_SOURCE_LOCAL,
  IMAGE_BLOCK_SOURCE_SUBSCRIPTION,
  ImageBlockRepository,
  ImageBlockRule,
  ImageBlockWhitelistItem,
  ImageBlockSubscriptionService,
  ImageBlockSubscriptionUpdateResult,
  SecondaryListScaffold,
  ThemeConstants,
  immersiveTitleBar,
  publishImageBlockRulesChanged,
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
  @Local whitelistItems: ImageBlockWhitelistItem[] = [];
  @Local updating: boolean = false;
  @Local deletingLocalRuleId: string = '';
  @Local deletingWhitelistHash: string = '';
  @Local ruleSheetShown: boolean = false;
  @Local feedRulesSheetShown: boolean = false;
  @Local selectedRule: ImageBlockRule = new ImageBlockRule();
  @Local selectedFeedTitle: string = '';
  @Local selectedFeedId: string = '';
  @Local feedRules: ImageBlockRule[] = [];
  @Local loadingFeedRules: boolean = false;
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
    if (feed.id === 'zh-scanlator-ads') {
      return AppStrings.get('image_block_default_provider_title')
    }
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
    return this.ruleCountText(this.totalRules())
  }

  private ruleCountText(count: number): string {
    return AppStrings.get('image_block_rule_count_format').replace('%d', `${count}`)
  }

  private imageCountText(count: number): string {
    return AppStrings.get('image_block_image_count_format').replace('%d', `${count}`)
  }

  private feedSubtitle(feed: ImageBlockFeed): string {
    const state: string = feed.enabled
      ? AppStrings.get('image_block_feed_enabled_hint')
      : AppStrings.get('image_block_feed_disabled_hint')
    return `${state} · ${this.ruleCountText(feed.count)}`
  }

  private localRuleSubtitle(rule: ImageBlockRule): string {
    const parts: string[] = []
    if (rule.sourceUrl.length > 0) {
      parts.push(this.readableSource(rule.sourceUrl))
    } else {
      parts.push(AppStrings.get('image_block_rule_missing_source'))
    }
    if (rule.sourcePage > 0) {
      parts.push(this.sourcePageText(rule.sourcePage))
    }
    return parts.join(AppStrings.get('image_block_inline_separator'))
  }

  private subscriptionRuleSubtitle(rule: ImageBlockRule): string {
    const parts: string[] = [AppStrings.get('image_block_subscription_rule_summary')]
    const source: string = this.localRuleSubtitle(rule)
    if (source.length > 0) {
      parts.push(source)
    }
    return parts.join(AppStrings.get('image_block_inline_separator'))
  }

  private ruleSubmitStatus(rule: ImageBlockRule): string {
    if (rule.sourceUrl.length > 0 && rule.sourcePage > 0) {
      return AppStrings.get('image_block_rule_submit_ready')
    }
    return AppStrings.get('image_block_rule_submit_blocked')
  }

  private localRuleTitle(rule: ImageBlockRule): string {
    return this.readableRuleLabel(rule.label)
  }

  private readableRuleLabel(label: string): string {
    if (label === 'scanlator-ad' || label === 'local' || label.endsWith('-ad') || label.indexOf('-') >= 0) {
      return AppStrings.get('image_block_rule_blocked_image')
    }
    return label.length > 0 ? label : AppStrings.get('image_block_local_rule_title')
  }

  private sourcePageText(page: number): string {
    return AppStrings.get('image_block_source_page_format').replace('%s', `${page}`)
  }

  private readableSource(sourceUrl: string): string {
    let out: string = sourceUrl.trim()
    if (out.startsWith('https://')) {
      out = out.substring(8)
    } else if (out.startsWith('http://')) {
      out = out.substring(7)
    }
    if (out.startsWith('e-hentai.org/')) {
      out = out.substring('e-hentai.org/'.length)
    } else if (out.startsWith('exhentai.org/')) {
      out = out.substring('exhentai.org/'.length)
    }
    if (out.endsWith('/')) {
      out = out.substring(0, out.length - 1)
    }
    if (out.startsWith('g/')) {
      const rest: string = out.substring(2)
      const slash: number = rest.indexOf('/')
      const galleryId: string = slash >= 0 ? rest.substring(0, slash) : rest
      if (galleryId.length > 0) {
        const tokenPart: string = slash >= 0 ? rest.substring(slash + 1) : ''
        const tokenEnd: number = tokenPart.indexOf('/')
        const galleryToken: string = tokenEnd >= 0 ? tokenPart.substring(0, tokenEnd) : tokenPart
        if (galleryToken.length > 0) {
          return AppStrings.get('image_block_source_gallery_token_format')
            .replace('%s', galleryId)
            .replace('%s', galleryToken)
        }
        return AppStrings.get('image_block_source_gallery_format').replace('%s', galleryId)
      }
    }
    if (out.length > 56) {
      return `${out.substring(0, 53)}...`
    }
    return out
  }

  private ruleKindText(rule: ImageBlockRule): string {
    if (rule.sourceType === IMAGE_BLOCK_SOURCE_SUBSCRIPTION) {
      return this.selectedFeedTitle.length > 0
        ? this.selectedFeedTitle
        : AppStrings.get('image_block_subscription_rule_summary')
    }
    return AppStrings.get('image_block_local_rule_summary')
  }

  private imageUri(path: string): string {
    if (path.startsWith('file://')) {
      return path
    }
    return path.length > 0 ? `file://${path}` : ''
  }

  private contributionDraftTrailing(): string {
    if (this.contributionTotalCount <= 0) {
      return AppStrings.get('image_block_contribution_none_ready')
    }
    return AppStrings.get('image_block_contribution_ready_count')
      .replace('%d', `${this.contributionReadyCount}`)
  }

  private contributionReasonCountText(reason: string, count: number): string {
    return AppStrings.get('image_block_contribution_reason_count_format')
      .replace('%d', `${count}`)
      .replace('%s', reason)
  }

  private contributionSkipReasonText(): string {
    const parts: string[] = []
    if (this.contributionMissingSourceCount > 0) {
      parts.push(this.contributionReasonCountText(
        AppStrings.get('image_block_contribution_missing_source'),
        this.contributionMissingSourceCount,
      ))
    }
    if (this.contributionDuplicateCount > 0) {
      parts.push(this.contributionReasonCountText(
        AppStrings.get('image_block_contribution_duplicate'),
        this.contributionDuplicateCount,
      ))
    }
    if (this.contributionInvalidCount > 0) {
      parts.push(this.contributionReasonCountText(
        AppStrings.get('image_block_contribution_invalid'),
        this.contributionInvalidCount,
      ))
    }
    return parts.join(AppStrings.get('image_block_contribution_reason_separator'))
  }

  private contributionDraftSubtitle(): string {
    const hint: string = AppStrings.get('image_block_contribution_draft_hint')
    if (this.contributionSkippedCount <= 0) {
      return hint
    }
    const labelSeparator: string = AppStrings.get('image_block_label_separator')
    const reasons: string = this.contributionSkipReasonText()
    if (reasons.length <= 0) {
      return `${AppStrings.get('image_block_contribution_skipped')}${labelSeparator}${this.contributionReasonCountText(
        AppStrings.get('image_block_contribution_unavailable'),
        this.contributionSkippedCount,
      )}`
    }
    return `${AppStrings.get('image_block_contribution_skipped')}${labelSeparator}${reasons}`
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
    ImageBlockRepository.loadWhitelistItems(this.ctx())
      .then((items: ImageBlockWhitelistItem[]) => {
        this.whitelistItems = items
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_load_failed')}: ${error.message}`)
      })
  }

  private openLocalRuleSheet(rule: ImageBlockRule): void {
    this.selectedRule = rule.copy()
    this.ruleSheetShown = true
  }

  private openSubscriptionRuleSheet(rule: ImageBlockRule): void {
    this.selectedRule = rule.copy()
    this.ruleSheetShown = true
  }

  private closeRuleSheet(): void {
    this.ruleSheetShown = false
  }

  private openFeedRules(feed: ImageBlockFeed): void {
    this.selectedFeedId = feed.id
    this.selectedFeedTitle = this.feedTitle(feed)
    this.feedRules = []
    this.feedRulesSheetShown = true
    this.reloadFeedRules()
  }

  private closeFeedRulesSheet(): void {
    this.feedRulesSheetShown = false
  }

  private reloadFeedRules(): void {
    if (this.selectedFeedId.length === 0 || this.loadingFeedRules) {
      return
    }
    this.loadingFeedRules = true
    ImageBlockRepository.loadSubscriptionRules(this.ctx(), this.selectedFeedId)
      .then((rules: ImageBlockRule[]) => {
        this.feedRules = rules
        this.syncSelectedRuleFrom(rules)
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_load_failed')}: ${error.message}`)
      })
      .finally(() => {
        this.loadingFeedRules = false
      })
  }

  private syncSelectedRuleFrom(rules: ImageBlockRule[]): void {
    if (!this.ruleSheetShown || this.selectedRule.id.length === 0) {
      return
    }
    for (let i: number = 0; i < rules.length; i++) {
      if (rules[i].id === this.selectedRule.id) {
        this.selectedRule = rules[i].copy()
        return
      }
    }
  }

  private selectedRuleIsLocal(): boolean {
    return this.selectedRule.sourceType === IMAGE_BLOCK_SOURCE_LOCAL
  }

  private ruleSourceText(rule: ImageBlockRule): string {
    if (rule.sourceType === IMAGE_BLOCK_SOURCE_SUBSCRIPTION) {
      const source: string = this.localRuleSubtitle(rule)
      const feedTitle: string = this.selectedFeedTitle.length > 0
        ? this.selectedFeedTitle
        : AppStrings.get('image_block_source_subscription')
      if (source.length > 0) {
        return `${feedTitle}${AppStrings.get('image_block_inline_separator')}${source}`
      }
      return feedTitle
    }
    return this.localRuleSubtitle(rule)
  }

  private setSelectedRuleEnabled(enabled: boolean): void {
    const rule: ImageBlockRule = this.selectedRule.copy()
    if (rule.id.length === 0) {
      return
    }
    rule.enabled = enabled
    this.selectedRule = rule
    const task: Promise<void> = rule.sourceType === IMAGE_BLOCK_SOURCE_LOCAL
      ? ImageBlockRepository.setLocalRuleEnabled(this.ctx(), rule.id, enabled)
      : ImageBlockRepository.setRuleEnabledOverride(this.ctx(), rule.id, rule.hash, rule.sourceType, enabled)
    task
      .then(() => {
        this.afterRuleChanged()
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
  }

  private clampRuleThreshold(value: number): number {
    return Math.max(0, Math.min(IMAGE_BLOCK_MAX_THRESHOLD, Math.round(value)))
  }

  private previewSelectedRuleThreshold(value: number): void {
    const nextThreshold: number = this.clampRuleThreshold(value)
    if (nextThreshold === this.selectedRule.threshold) {
      return
    }
    const rule: ImageBlockRule = this.selectedRule.copy()
    rule.threshold = nextThreshold
    this.selectedRule = rule
  }

  private commitSelectedRuleThreshold(value: number): void {
    const rule: ImageBlockRule = this.selectedRule.copy()
    if (rule.id.length === 0) {
      return
    }
    const nextThreshold: number = this.clampRuleThreshold(value)
    rule.threshold = nextThreshold
    this.selectedRule = rule
    const task: Promise<void> = rule.sourceType === IMAGE_BLOCK_SOURCE_LOCAL
      ? ImageBlockRepository.setLocalRuleThreshold(this.ctx(), rule.id, nextThreshold)
      : ImageBlockRepository.setRuleThresholdOverride(this.ctx(), rule.id, rule.hash, rule.sourceType, nextThreshold)
    task
      .then(() => {
        this.afterRuleChanged()
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
  }

  private afterRuleChanged(): void {
    this.reloadLocalRules()
    this.reloadFeedRules()
    publishImageBlockRulesChanged('settings-rule-change')
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
        this.reloadFeedRules()
        publishImageBlockRulesChanged('settings-subscription-update')
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
        if (this.selectedRule.id === ruleId) {
          this.closeRuleSheet()
        }
        publishImageBlockRulesChanged('settings-local-rule-delete')
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
        publishImageBlockRulesChanged('settings-feed-enabled')
      })
      .catch((error: Error) => {
        this.toast(`${AppStrings.get('image_block_update_failed')}: ${error.message}`)
      })
  }

  private setLocalRuleThreshold(rule: ImageBlockRule, threshold: number): void {
    ImageBlockRepository.setLocalRuleThreshold(this.ctx(), rule.id, threshold)
      .then(() => {
        this.reloadLocalRules()
        publishImageBlockRulesChanged('settings-local-threshold')
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
  private FeedEnabledSwitch(feed: ImageBlockFeed) {
    Toggle({ type: ToggleType.Switch, isOn: feed.enabled })
      .selectedColor(ThemeConstants.BRAND_PRIMARY)
      .onChange((value: boolean) => {
        this.setFeedEnabled(feed.id, value)
      })
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
  private PreviewImage(path: string, icon: Resource) {
    Stack() {
      if (path.length > 0) {
        Image(this.imageUri(path))
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        SymbolGlyph(icon)
          .fontSize(30)
          .fontColor([$r('sys.color.font_secondary')])
      }
    }
    .width(88)
    .height(116)
    .borderRadius(ThemeConstants.THUMB_RADIUS)
    .clip(true)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  private StatusPill(text: string, isGood: boolean) {
    Text(text)
      .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
      .fontColor(isGood ? $r('sys.color.ohos_id_color_emphasize') : $r('sys.color.font_secondary'))
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(ThemeConstants.CHIP_RADIUS)
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM, top: 2, bottom: 2 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private WhitelistCard(item: ImageBlockWhitelistItem) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.PreviewImage(item.previewPath, $r('sys.symbol.eye'))
      Column({ space: ThemeConstants.SPACE_SM }) {
        Row() {
          Text($r('app.string.image_block_whitelist_hash_title'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          this.WhitelistDeleteSuffix(item.hash)
        }
        this.StatusPill(AppStrings.get('image_block_whitelist_status'), true)
        Text($r('app.string.image_block_whitelist_row_hint'))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${AppStrings.get('image_block_rule_fingerprint')} ${item.hash}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_SM,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .opacity(this.deletingWhitelistHash === item.hash ? 0.45 : 1.0)
  }

  @Builder
  private LocalRuleRow(rule: ImageBlockRule) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.PreviewImage(rule.previewPath, $r('sys.symbol.eye_slash'))
      Column({ space: ThemeConstants.SPACE_SM }) {
        Text(this.localRuleTitle(rule))
          .fontSize(ThemeConstants.FONT_SIZE_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: ThemeConstants.SPACE_XS }) {
          this.StatusPill(
            rule.enabled
              ? AppStrings.get('image_block_provider_enabled')
              : AppStrings.get('image_block_provider_disabled'),
            rule.enabled,
          )
          this.StatusPill(this.ruleSubmitStatus(rule), rule.sourceUrl.length > 0 && rule.sourcePage > 0)
        }
        Text(this.localRuleSubtitle(rule))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${AppStrings.get('image_block_rule_fingerprint')} ${rule.hash}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
        Text(`${AppStrings.get('image_block_rule_threshold')} ${rule.threshold}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_SM,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .opacity(this.deletingLocalRuleId === rule.id ? 0.45 : 1.0)
    .onClick(() => {
      this.openLocalRuleSheet(rule)
    })
  }

  @Builder
  private SubscriptionRuleRow(rule: ImageBlockRule) {
    Row({ space: ThemeConstants.SPACE_MD }) {
      this.PreviewImage(rule.previewPath, $r('sys.symbol.cloud'))
      Column({ space: ThemeConstants.SPACE_SM }) {
        Row({ space: ThemeConstants.SPACE_SM }) {
          Text(this.readableRuleLabel(rule.label))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
            .selectedColor(ThemeConstants.BRAND_PRIMARY)
            .onChange((value: boolean) => {
              this.selectedRule = rule.copy()
              this.setSelectedRuleEnabled(value)
            })
        }
        .alignItems(VerticalAlign.Center)
        Row({ space: ThemeConstants.SPACE_XS }) {
          this.StatusPill(AppStrings.get('image_block_subscription_rule_summary'), true)
          this.StatusPill(
            rule.enabled
              ? AppStrings.get('image_block_provider_enabled')
              : AppStrings.get('image_block_provider_disabled'),
            rule.enabled,
          )
        }
        Text(this.subscriptionRuleSubtitle(rule))
          .fontSize(ThemeConstants.FONT_SIZE_BODY)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${AppStrings.get('image_block_rule_threshold')} ${rule.threshold}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
        Text(`${AppStrings.get('image_block_rule_fingerprint')} ${rule.hash}`)
          .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: ThemeConstants.SPACE_MD,
      right: ThemeConstants.SPACE_SM,
      top: ThemeConstants.SPACE_MD,
      bottom: ThemeConstants.SPACE_MD,
    })
    .onClick(() => {
      this.openSubscriptionRuleSheet(rule)
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
                    subtitleMaxLines: 2,
                    leadingIcon: $r('sys.symbol.cloud'),
                    showChevron: false,
                    suffixBuilderParam: () => {
                      this.FeedEnabledSwitch(feed)
                    },
                    action: () => {
                      this.openFeedRules(feed)
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
              leadingIcon: $r('sys.symbol.eye_slash'),
              trailingText: this.ruleCountText(this.localRuleCount),
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
                (rule: ImageBlockRule) => `${rule.id}:${rule.sourceUrl}:${rule.sourcePage}:${rule.threshold}:${rule.previewPath}:${rule.enabled ? '1' : '0'}`,
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
              trailingText: this.imageCountText(this.whitelistItems.length),
              showChevron: false,
            })
            if (this.whitelistItems.length > 0) {
              this.rowDivider()
              ForEach(
                this.whitelistItems,
                (item: ImageBlockWhitelistItem, index: number) => {
                  this.WhitelistCard(item)
                  if (index < this.whitelistItems.length - 1) {
                    this.rowDivider()
                  }
                },
                (item: ImageBlockWhitelistItem) => item.hash,
              )
            }
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('image_block_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .bindSheet($$this.feedRulesSheetShown, this.FeedRulesSheet(), appSheetOptions({
      detents: [SheetSize.LARGE],
      showClose: false,
    }))
    .bindSheet($$this.ruleSheetShown, this.RuleSheet(), appSheetOptions({
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      showClose: false,
    }))
  }

  @Builder
  private ThresholdSliderRow() {
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        Column({ space: ThemeConstants.SPACE_SM }) {
          Row({ space: ThemeConstants.SPACE_MD }) {
            SymbolGlyph($r('sys.symbol.list_number'))
              .fontSize(ThemeConstants.FONT_SIZE_TITLE)
              .fontColor([$r('sys.color.font_secondary')])
            Text($r('app.string.image_block_rule_threshold'))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
            Text(`${this.selectedRule.threshold}/${IMAGE_BLOCK_MAX_THRESHOLD}`)
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)
          Slider({
            value: this.selectedRule.threshold,
            min: 0,
            max: IMAGE_BLOCK_MAX_THRESHOLD,
            step: 1,
            style: SliderStyle.InSet,
          })
            .width('100%')
            .selectedColor(ThemeConstants.BRAND_PRIMARY)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.commitSelectedRuleThreshold(value)
              } else {
                this.previewSelectedRuleThreshold(value)
              }
            })
          Row() {
            Text($r('app.string.image_block_threshold_strict'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)
            Text($r('app.string.image_block_threshold_loose'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
          }
        }
        .width('100%')
        .padding(ThemeConstants.SPACE_MD)
      }
    }
  }

  @Builder
  private RuleEnabledRow() {
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        Row({ space: ThemeConstants.SPACE_MD }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(ThemeConstants.FONT_SIZE_TITLE)
            .fontColor([$r('sys.color.font_secondary')])
          Text($r('app.string.image_block_rule_enabled'))
            .fontSize(ThemeConstants.FONT_SIZE_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.selectedRule.enabled })
            .selectedColor(ThemeConstants.BRAND_PRIMARY)
            .onChange((value: boolean) => {
              this.setSelectedRuleEnabled(value)
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(ThemeConstants.SPACE_MD)
      }
    }
  }

  @Builder
  private RuleHeader(rule: ImageBlockRule) {
    ListItem() {
      GroupedListSection({ inset: 0 }) {
        Row({ space: ThemeConstants.SPACE_MD }) {
          this.PreviewImage(
            rule.previewPath,
            rule.sourceType === IMAGE_BLOCK_SOURCE_SUBSCRIPTION ? $r('sys.symbol.cloud') : $r('sys.symbol.eye_slash'),
          )
          Column({ space: ThemeConstants.SPACE_SM }) {
            Text(this.readableRuleLabel(rule.label))
              .fontSize(ThemeConstants.FONT_SIZE_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.ruleKindText(rule))
              .fontSize(ThemeConstants.FONT_SIZE_BODY)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(ThemeConstants.SPACE_MD)
      }
    }
  }

  @Builder
  private RuleSheet() {
    AppModalScaffold({
      title: $r('app.string.image_block_rule_settings'),
      showConfirmAction: false,
      showSecondaryAction: this.selectedRuleIsLocal(),
      secondaryText: $r('app.string.common_delete'),
      secondaryIcon: $r('sys.symbol.trash'),
      closeAction: () => {
        this.closeRuleSheet()
      },
      secondaryAction: () => {
        this.confirmDeleteLocalRule(this.selectedRule)
      },
    }) {
      this.RuleHeader(this.selectedRule)
      this.RuleEnabledRow()
      this.ThresholdSliderRow()
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          ConciseListRow({
            title: $r('app.string.image_block_rule_source'),
            subtitle: this.ruleSourceText(this.selectedRule),
            subtitleMaxLines: 3,
            leadingIcon: this.selectedRule.sourceType === IMAGE_BLOCK_SOURCE_SUBSCRIPTION
              ? $r('sys.symbol.cloud')
              : $r('sys.symbol.eye_slash'),
            showChevron: false,
          })
          this.rowDivider()
          ConciseListRow({
            title: $r('app.string.image_block_rule_fingerprint'),
            subtitle: this.selectedRule.hash,
            subtitleMaxLines: 3,
            leadingIcon: $r('sys.symbol.doc_plaintext'),
            showChevron: false,
          })
        }
      }
    }
  }

  @Builder
  private FeedRulesSheet() {
    AppModalScaffold({
      title: this.selectedFeedTitle,
      showConfirmAction: false,
      closeAction: () => {
        this.closeFeedRulesSheet()
      },
    }) {
      ListItem() {
        GroupedListSection({ inset: 0 }) {
          ConciseListRow({
            title: $r('app.string.image_block_subscription_rules'),
            subtitle: this.loadingFeedRules
              ? $r('app.string.image_block_updating')
              : this.ruleCountText(this.feedRules.length),
            leadingIcon: $r('sys.symbol.cloud'),
            showChevron: false,
          })
        }
      }
      if (this.feedRules.length > 0) {
        ListItem() {
          GroupedListSection({ inset: 0 }) {
            ForEach(
              this.feedRules,
              (rule: ImageBlockRule, index: number) => {
                this.SubscriptionRuleRow(rule)
                if (index < this.feedRules.length - 1) {
                  this.rowDivider()
                }
              },
              (rule: ImageBlockRule) => `${rule.id}:${rule.sourceUrl}:${rule.sourcePage}:${rule.threshold}:${rule.previewPath}:${rule.enabled ? '1' : '0'}`,
            )
          }
        }
      }
    }
  }
}
