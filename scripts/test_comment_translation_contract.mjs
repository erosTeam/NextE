#!/usr/bin/env node
import fs from 'node:fs'

function read(path) {
  return fs.readFileSync(path, 'utf8')
}

let failed = 0
function ok(condition, message) {
  if (!condition) {
    failed++
    console.error(`✗ ${message}`)
  }
}

const store = read('shared/src/main/ets/storage/LocalDataStore.ets')
const service = read('shared/src/main/ets/services/CommentTranslationService.ets')
const settingsState = read('shared/src/main/ets/state/CommentTranslationSettingsState.ets')
const settings = read('shared/src/main/ets/settings/CommentTranslationSettings.ets')
const commentsCard = read('feature/gallery/src/main/ets/components/GalleryCommentsCard.ets')
const commentsPage = read('feature/gallery/src/main/ets/pages/GalleryCommentsPage.ets')
const commentModel = read('shared/src/main/ets/model/EhGalleryComment.ets')
const settingsPage = read('feature/settings/src/main/ets/pages/TranslationSettingsPage.ets')
const rootSettings = read('feature/settings/src/main/ets/pages/SettingsPage.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const bootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const shared = read('shared/src/main/ets/Index.ets')
const keys = read('shared/src/main/ets/constants/StorageKeys.ets')
const validationStart = service.indexOf('static async validateConfiguredLlm')
const validationEnd = service.indexOf('private static async translateAndCache')
const validationBody = validationStart >= 0 && validationEnd > validationStart
  ? service.slice(validationStart, validationEnd)
  : ''
const footerStart = commentsCard.indexOf('// Time/actions footer')
const translationActionInFooter = commentsCard.indexOf('this.TranslationAction(c)', footerStart)
const timestampInFooter = commentsCard.indexOf('Text(c.postedTime)', footerStart)
const editActionInFooter = commentsCard.indexOf('this.EditAction(c)', footerStart)
const voteActionInFooter = commentsCard.indexOf('this.VoteAction(c', footerStart)
const replyActionInFooter = commentsCard.indexOf('this.ReplyAction(c)', footerStart)
const applyTranslationStart = commentsPage.indexOf('private applyCommentTranslationState')
const applyTranslationEnd = commentsPage.indexOf('private commentById', applyTranslationStart)
const applyTranslationBody = applyTranslationStart >= 0 && applyTranslationEnd > applyTranslationStart
  ? commentsPage.slice(applyTranslationStart, applyTranslationEnd)
  : ''

ok(
  /CREATE TABLE IF NOT EXISTS comment_translation_cache/.test(store) &&
    /PRIMARY KEY\(text_hash, target_lang\)/.test(store),
  'comment translations must be cached in RDB, keyed by source hash and target language',
)
ok(
  /SQL_SELECT_COMMENT_TRANSLATION/.test(service) &&
    /SQL_UPSERT_COMMENT_TRANSLATION/.test(service) &&
    !/Preferences/.test(service),
  'translation cache service must use RDB, not Preferences',
)
ok(
  /Authorization': `Bearer \$\{apiKey\}`/.test(service) &&
    /\/v1\/chat\/completions/.test(service) &&
    /translate\.googleapis\.com\/translate_a\/single/.test(service) &&
    /llm_failed_google_fallback/.test(service),
  'service must support user OpenAI-compatible LLM and Google fallback',
)
ok(
  /static async validateConfiguredLlm\(\): Promise<void>/.test(service) &&
    /callLlm/.test(validationBody) &&
    !/callGoogle/.test(validationBody),
  'LLM validation must hit the configured API directly without Google fallback',
)
ok(
  /static async fetchConfiguredLlmModels\(\): Promise<string\[]>/.test(service) &&
    /private static async fetchLlmModels\(baseUrl: string, apiKey: string\): Promise<string\[]>/.test(service) &&
    /\/v1\/models/.test(service) &&
    /Authorization': `Bearer \$\{apiKey\}`/.test(service) &&
    /out\.sort\(\)/.test(service),
  'LLM model fetch must use the configured OpenAI-compatible models endpoint',
)
ok(
  /@ObservedV2[\s\S]*CommentTranslationSettingsState/.test(settingsState) &&
    /@Trace enabled/.test(settingsState) &&
    /@Trace apiKey/.test(settingsState),
  'comment translation settings must be V2 state',
)
ok(
  /COMMENT_TRANSLATION_API_KEY/.test(keys) &&
    /API key is sensitive/i.test(settings) &&
    !(settings + service).split('\n').some((line) => /DiagnosticLogger\./.test(line) && /apiKey/.test(line)),
  'API key must have a storage key and must not be logged',
)
ok(
  /CommentTranslationSettings\.restore/.test(bootstrap) &&
    /CommentTranslationSettings/.test(shared),
  'settings must restore at startup and export through shared barrel',
)
ok(
  /TranslationSettingsPage/.test(entry) &&
    /pushPathByName\('TranslationSettings'/.test(rootSettings) &&
    /SecondaryListScaffold/.test(settingsPage) &&
    /TextInput/.test(settingsPage) &&
    /comment_translation_fetch_models/.test(settingsPage) &&
    /fetchConfiguredLlmModels/.test(settingsPage) &&
    /@Local modelDraft: string = ''/.test(settingsPage) &&
    /TextInput\(\{ text: \$\$this\.modelDraft/.test(settingsPage) &&
    /this\.settings\.model\.length === 0 \|\| models\.length === 1/.test(settingsPage) &&
    /this\.setModel\(models\[0\]\)/.test(settingsPage) &&
    /private setModel\(value: string\): void \{[\s\S]*this\.modelDraft = value/.test(settingsPage) &&
    /ModelMenu/.test(settingsPage) &&
    /this\.setModel\(model\)/.test(settingsPage) &&
    /comment_translation_validate_api/.test(settingsPage) &&
    /validateConfiguredLlm/.test(settingsPage),
  'translation settings page must be routed from Settings and use existing settings scaffolds, including model fetch',
)
ok(
  /TranslationAction/.test(commentsCard) &&
    /CommentTranslationService\.translate/.test(commentsPage) &&
    /this\.max <= 0/.test(commentsCard) &&
    /onTranslate/.test(commentsCard),
  'full comments card must expose a translate action wired to page-owned state',
)
ok(
    /ForEach\(\s*this\.visibleComments\(\)/.test(commentsPage) &&
    /comments: \[comment\]/.test(commentsPage) &&
    /referenceComments: this\.comments/.test(commentsPage) &&
    /renderVersion: this\.commentRenderVersion/.test(commentsPage) &&
    /@Local commentRenderVersion: number = 0/.test(commentsPage) &&
    /useSingleComment: true/.test(commentsPage) &&
    /singleComment: comment/.test(commentsPage) &&
    !/singleTranslationText: comment\.translationText/.test(commentsPage) &&
    !/singleTranslationShown: comment\.translationShown/.test(commentsPage) &&
    !/singleTranslationLoading: comment\.translationLoading/.test(commentsPage) &&
    /parentManagedActions: true/.test(commentsPage) &&
    /private sourceComments\(\): EhGalleryComment\[\] \{[\s\S]*this\.useSingleComment[\s\S]*return \[this\.singleComment\]/.test(commentsCard) &&
    /showHeader: false/.test(commentsPage) &&
    /onTranslate: \(selectedComment: EhGalleryComment, sourceText: string\) => \{[\s\S]*return this\.requestCommentTranslation\(selectedComment, sourceText, false\)/.test(commentsPage) &&
    /onTranslationResolved: \(selectedComment: EhGalleryComment, translated: string\) => \{[\s\S]*this\.applyResolvedCommentTranslation\(selectedComment, translated\)/.test(commentsPage) &&
    /onToggleTranslation: \(selectedComment: EhGalleryComment\) => \{[\s\S]*this\.toggleCommentTranslation\(selectedComment\)/.test(commentsPage) &&
    /onAutoTranslate: \(selectedComment: EhGalleryComment, sourceText: string\) => \{[\s\S]*this\.autoTranslateComment\(selectedComment, sourceText\)/.test(commentsPage) &&
    !/actionScope: this\.params\.gid/.test(commentsPage) &&
    !/requestRenderState\(/.test(commentsPage) &&
    !/@Monitor\('commentAction\.version'\)/.test(commentsPage) &&
    /\(comment: EhGalleryComment\) => comment\.commentId/.test(commentsPage) &&
    !/return `\$\{c\.commentId\}:\$\{c\.vote\}:\$\{c\.score\}:\$\{c\.translationShown\}:\$\{c\.translationLoading\}:\$\{c\.translationText\.length\}`/.test(commentsPage),
  'full comments page must render each row as an observed single-comment card and handle card commands in page context',
)
ok(
  /@ObservedV2[\s\S]*export class EhGalleryComment/.test(commentModel) &&
    /@Trace translationText: string = ''/.test(commentModel) &&
    /@Trace translationShown: boolean = false/.test(commentModel) &&
    /@Trace translationLoading: boolean = false/.test(commentModel) &&
    /@Trace translationAutoStarted: boolean = false/.test(commentModel) &&
    /applyCommentTranslationState/.test(commentsPage) &&
    /animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}/.test(commentsPage) &&
    !/onCommentRenderStateChanged/.test(commentsCard) &&
    !/GALLERY_COMMENT_ACTION_RENDER_STATE/.test(commentsCard) &&
    !/@Monitor\('commentAction\.version'\)/.test(commentsCard) &&
    !/@Param actionScope: string = ''/.test(commentsCard) &&
    !/@Param singleTranslationText/.test(commentsCard) &&
    !/@Param singleTranslationShown/.test(commentsCard) &&
    !/@Param singleTranslationLoading/.test(commentsCard) &&
    /private translationText\(c: EhGalleryComment\): string \{[\s\S]*this\.useSingleComment \? this\.singleComment\.translationText : c\.translationText/.test(commentsCard) &&
    /private isTranslationShown\(c: EhGalleryComment\): boolean \{[\s\S]*this\.useSingleComment \? this\.singleComment\.translationShown : c\.translationShown/.test(commentsCard) &&
    /private isTranslationLoading\(c: EhGalleryComment\): boolean \{[\s\S]*this\.useSingleComment \? this\.singleComment\.translationLoading : c\.translationLoading/.test(commentsCard) &&
    /this\.CommentRow\(this\.singleComment, true\)/.test(commentsCard) &&
    /this\.CommentRow\(c, index === this\.shown\(\)\.length - 1\)/.test(commentsCard) &&
    /CommentRow\(c: EhGalleryComment, isLast: boolean\)/.test(commentsCard) &&
    /CommentRow\(c: EhGalleryComment, isLast: boolean\) \{[\s\S]*if \(this\.canOpenFullComments\(\)\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.onMore\(\)/.test(commentsCard) &&
    /CommentRowContent\(c: EhGalleryComment\)/.test(commentsCard) &&
    !/CommentRow\([\s\S]*score: string/.test(commentsCard) &&
    !/CommentRow\([\s\S]*translationLoading: boolean/.test(commentsCard) &&
    /@Local localTranslationCommentId: string = ''/.test(commentsCard) &&
    /@Local localTranslationText: string = ''/.test(commentsCard) &&
    /@Local localTranslationShown: boolean = false/.test(commentsCard) &&
    /@Local localTranslationLoading: boolean = false/.test(commentsCard) &&
    /@Monitor\('renderVersion'\)[\s\S]*syncLocalTranslationState/.test(commentsCard) &&
    !/shouldAnimateTranslationResolve/.test(commentsCard) &&
    !/useSingleComment && this\.isTranslationShown\(c\) && this\.translationText\(c\)\.length > 0/.test(commentsCard) &&
    /private translationText\(c: EhGalleryComment\): string \{[\s\S]*this\.localTranslationCommentId === this\.renderState\.commentId[\s\S]*return this\.localTranslationText/.test(commentsCard) &&
    /private isTranslationShown\(c: EhGalleryComment\): boolean \{[\s\S]*this\.localTranslationCommentId === this\.renderState\.commentId[\s\S]*return this\.localTranslationShown/.test(commentsCard) &&
    /private isTranslationLoading\(c: EhGalleryComment\): boolean \{[\s\S]*this\.localTranslationCommentId === this\.renderState\.commentId[\s\S]*return this\.localTranslationLoading/.test(commentsCard) &&
    /private toggleOrTranslate\(c: EhGalleryComment\): void[\s\S]*if \(this\.translationText\(c\)\.length > 0\) \{[\s\S]*if \(this\.parentManagedActions\) \{[\s\S]*this\.ensureLocalTranslationState\(\)[\s\S]*this\.localTranslationShown = !this\.localTranslationShown[\s\S]*this\.localTranslationLoading = false[\s\S]*this\.publishToggleTranslation\(c\)[\s\S]*return[\s\S]*c\.translationShown = !c\.translationShown/.test(commentsCard) &&
    /private beginTranslationLoading\(c: EhGalleryComment\): void[\s\S]*if \(this\.parentManagedActions\) \{[\s\S]*this\.ensureLocalTranslationState\(\)[\s\S]*this\.localTranslationShown = true[\s\S]*this\.localTranslationLoading = true[\s\S]*return[\s\S]*c\.translationShown = true[\s\S]*c\.translationLoading = true/.test(commentsCard) &&
    !/this\.renderState\.translationShown = !this\.renderState\.translationShown/.test(commentsCard) &&
    !/this\.renderState\.translationLoading = true/.test(commentsCard) &&
    /private autoTranslateVisibleComments\(\): void \{[\s\S]*if \(this\.parentManagedActions\) \{[\s\S]*return[\s\S]*this\.translationSettings\.autoTranslate/.test(commentsCard) &&
    /private toggleOrTranslate\(c: EhGalleryComment\): void[\s\S]*this\.beginTranslationLoading\(c\)[\s\S]*this\.publishTranslate\(c, sourceText\)/.test(commentsCard) &&
    /current\.translationText = translated/.test(commentsPage) &&
    /current\.translationShown = shown/.test(commentsPage) &&
    !/this\.comments = nextComments/.test(applyTranslationBody) &&
    /updater\(current\)[\s\S]*comments\[i\] = current[\s\S]*this\.updateRenderState\(current\)[\s\S]*return current/.test(commentsPage) &&
    !/const next: EhGalleryComment = this\.cloneComment\(current\)[\s\S]*updater\(next\)/.test(commentsPage) &&
    /private updateRenderState\(comment: EhGalleryComment\): void \{[\s\S]*states\[i\]\.applyComment\(comment\)[\s\S]*this\.commentRenderStates = states/.test(commentsPage) &&
    /commentRowKey[\s\S]*return c\.commentId/.test(commentsCard) &&
    !/return `\$\{c\.commentId\}:\$\{c\.vote\}:\$\{c\.score\}:\$\{c\.translationShown\}:\$\{c\.translationLoading\}:\$\{c\.translationText\.length\}`/.test(commentsCard) &&
    /CommentBody\(c: EhGalleryComment\)[\s\S]*this\.parentManagedActions && this\.translationEnabled\(\)[\s\S]*this\.localTranslationShown && this\.localTranslationText\.length > 0/.test(commentsCard) &&
    /@Event onTranslate: \(comment: EhGalleryComment, sourceText: string\) => Promise<string>/.test(commentsCard) &&
    /@Event onTranslationResolved: \(comment: EhGalleryComment, translated: string\) => void/.test(commentsCard) &&
    /@Local commentBodyMeasuredHeight: number = 0/.test(commentsCard) &&
    /@Local commentBodyAnimatedHeight: number = 0/.test(commentsCard) &&
    /@Local commentBodyHeightLocked: boolean = false/.test(commentsCard) &&
    /@Local pendingTranslationText: string = ''/.test(commentsCard) &&
    /@Local pendingTranslationMeasure: boolean = false/.test(commentsCard) &&
    /private applyResolvedTranslation\(c: EhGalleryComment, translated: string\): void \{[\s\S]*this\.ensureLocalTranslationState\(\)[\s\S]*this\.pendingTranslationText = translated[\s\S]*this\.pendingTranslationMeasure = true/.test(commentsCard) &&
    /private updateCommentBodyHeight\(area: Area\): void \{[\s\S]*if \(this\.commentBodyHeightLocked\)[\s\S]*const height: number = area\.height as number[\s\S]*this\.commentBodyMeasuredHeight = height/.test(commentsCard) &&
    /private handlePendingTranslationArea\(c: EhGalleryComment, area: Area\): void \{[\s\S]*const nextHeight: number = area\.height as number[\s\S]*const startHeight: number = this\.commentBodyMeasuredHeight > 0 \? this\.commentBodyMeasuredHeight : nextHeight[\s\S]*this\.commentBodyHeightLocked = true[\s\S]*animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}[\s\S]*this\.localTranslationText = translated[\s\S]*this\.commentBodyAnimatedHeight = nextHeight[\s\S]*this\.commentBodyHeightLocked = false[\s\S]*this\.publishTranslationResolved\(c, translated\)/.test(commentsCard) &&
    /CommentBody\(c: EhGalleryComment\)[\s\S]*if \(this\.commentBodyHeightLocked\)[\s\S]*\.height\(this\.commentBodyAnimatedHeight\)[\s\S]*\.clip\(true\)/.test(commentsCard) &&
    /CommentBodyStackContent\(c: EhGalleryComment\)[\s\S]*\.onAreaChange\(\(_oldArea: Area, area: Area\) => \{[\s\S]*this\.updateCommentBodyHeight\(area\)[\s\S]*this\.pendingTranslationMeasure[\s\S]*this\.PendingTranslationBodyContent\(c, this\.pendingTranslationText\)[\s\S]*\.opacity\(0\)[\s\S]*\.hitTestBehavior\(HitTestMode\.None\)[\s\S]*this\.handlePendingTranslationArea\(c, area\)/.test(commentsCard) &&
    /private requestCommentTranslation\(comment: EhGalleryComment, sourceText: string, force: boolean\): Promise<string> \{[\s\S]*return CommentTranslationService\.translate\(this\.ctx\(\), sourceText, force\)[\s\S]*return ''/.test(commentsPage) &&
    /private applyResolvedCommentTranslation\(comment: EhGalleryComment, translated: string\): void \{[\s\S]*this\.applyCommentTranslationState\(comment\.commentId, translated, true, false, undefined\)/.test(commentsPage) &&
    !/commentBodyTransitionId/.test(commentsCard) &&
    !/geometryTransition/.test(commentsCard) &&
    /CommentPlainText\(text: string, color: ResourceColor\)/.test(commentsCard) &&
    /this\.CommentPlainText\(this\.localTranslationText, \$r\('sys\.color\.font_primary'\)\)/.test(commentsCard) &&
    !/TransitionEffect\.OPACITY/.test(commentsCard) &&
    /if \(this\.translationEnabled\(\) && this\.localTranslationShown && this\.localTranslationText\.length > 0\) \{[\s\S]*this\.CommentPlainText\(this\.localTranslationText/.test(commentsCard) &&
    !/translatedComments/.test(commentsCard),
  'comment translation row state must be read inside row builders rather than frozen as builder arguments',
)
ok(
  translationActionInFooter > footerStart &&
    translationActionInFooter > timestampInFooter &&
    editActionInFooter > translationActionInFooter &&
    voteActionInFooter > translationActionInFooter &&
    replyActionInFooter > translationActionInFooter,
  'translate action must be the leftmost item in the right-side comment action group',
)
ok(
    /Button\(\{ type: ButtonType\.Circle, stateEffect: true \}\)/.test(commentsCard) &&
    /LoadingProgress/.test(commentsCard) &&
    /\.enabled\(!disabled\)/.test(commentsCard) &&
    /\.opacity\(1\)/.test(commentsCard) &&
    /TranslationAction\(c: EhGalleryComment\)[\s\S]*if \(this\.isTranslationLoading\(c\)\) \{[\s\S]*LoadingProgress/.test(commentsCard + commentsCard.slice(commentsCard.indexOf('FooterAction'))) &&
    /TranslationAction\(c: EhGalleryComment\)[\s\S]*else if \(this\.isTranslationShown\(c\) && this\.translationText\(c\)\.length > 0\) \{[\s\S]*ThemeConstants\.BRAND_PRIMARY[\s\S]*false/.test(commentsCard) &&
    /FooterAction\(icon: Resource, color: ResourceColor, disabled: boolean, action: \(\) => void/.test(commentsCard) &&
    /\.onClick\(action\)/.test(commentsCard) &&
    /\.backgroundColor\(Color\.Transparent\)/.test(commentsCard),
  'comment footer actions must use system button feedback and loading disabled state',
)
ok(
  !/contentText\s*=.*translated/.test(commentsCard + commentsPage) &&
    !/c\.contentText\s*=/.test(commentsCard + commentsPage) &&
    !/next\.contentText\s*=.*translation/.test(commentsPage),
  'comment translation must not overwrite raw comment contentText',
)
ok(
    /commentTextSegments\(text: string, c: EhGalleryComment\): CommentTextSegment\[\]/.test(commentsCard) &&
    /commentTextSegmentKey\(seg: CommentTextSegment\): string \{[\s\S]*seg\.text[\s\S]*seg\.url[\s\S]*seg\.emphasized/.test(commentsCard) &&
    /\(seg: CommentTextSegment\) => this\.commentTextSegmentKey\(seg\)/.test(commentsCard) &&
    /Span\(seg\.text\)/.test(commentsCard) &&
    !/firstCommentUrl\(text: string\): string/.test(commentsCard) &&
    /if \(clamp\) \{[\s\S]*\.maxLines\(4\)[\s\S]*\} else \{[\s\S]*Span\(seg\.text\)[\s\S]*\.onClick\(\(\) => \{[\s\S]*this\.openCommentUrl\(seg\.url\)/.test(commentsCard) &&
    !/TapGesture\(\{ count: 1 \}\)[\s\S]*this\.openCommentUrl/.test(commentsCard) &&
    !/enableDataDetector\(true\)/.test(commentsCard) &&
    !/commentContainsLink\(c: EhGalleryComment\): boolean/.test(commentsCard) &&
    /if \(this\.canOpenFullComments\(\)\) \{[\s\S]*this\.onMore\(\)/.test(commentsCard) &&
    /EhUrlRouter\.toCurrentHost\(url, EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)\)/.test(commentsCard) &&
    /publishPendingEhUrl\(`\$\{Date\.now\(\)\}:\$\{currentUrl\}`\)/.test(commentsCard) &&
    /pushPathByName\('GalleryWeb', new GalleryWebParams\(currentUrl, currentUrl\)\)/.test(commentsCard),
  'comment URL links must be span-routed: EH gallery/image links go native, other links open WebView',
)
ok(
  /Status: active[\s\S]*comment translation/.test(read('docs/plans/active/ui-grounding.md')) ||
    /## Active: comment translation/.test(read('docs/plans/active/ui-grounding.md')),
  'UI grounding must include comment translation entry',
)

if (failed > 0) {
  console.error(`✗ comment translation contract: ${failed} failure(s)`)
  process.exit(1)
}
console.log('✓ comment translation contract: RDB cache, settings, LLM/Google fallback, and full-comment UI are wired')
