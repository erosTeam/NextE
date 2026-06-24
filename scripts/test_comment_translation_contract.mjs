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
const commentActionState = read('shared/src/main/ets/state/GalleryCommentActionState.ets')
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
  /@ObservedV2[\s\S]*export class GalleryCommentActionState/.test(commentActionState) &&
    /@Trace version: number = 0/.test(commentActionState) &&
    /requestTranslate\(scopeId: string, commentId: string, sourceText: string\): void[\s\S]*GALLERY_COMMENT_ACTION_TRANSLATE/.test(commentActionState) &&
    /requestAutoTranslate\(scopeId: string, commentId: string, sourceText: string\): void[\s\S]*GALLERY_COMMENT_ACTION_AUTO_TRANSLATE/.test(commentActionState) &&
    /connectGalleryCommentAction/.test(shared),
  'comment card actions must use a V2 command bus instead of parent callback this-binding',
)
ok(
    /ForEach\(\s*this\.visibleComments\(\)/.test(commentsPage) &&
    /comments: \[comment\]/.test(commentsPage) &&
    /useSingleComment: true/.test(commentsPage) &&
    /singleComment: comment/.test(commentsPage) &&
    /private sourceComments\(\): EhGalleryComment\[\] \{[\s\S]*this\.useSingleComment[\s\S]*return \[this\.singleComment\]/.test(commentsCard) &&
    /showHeader: false/.test(commentsPage) &&
    /actionScope: this\.params\.gid/.test(commentsPage) &&
    /@Monitor\('commentAction\.version'\)[\s\S]*private onCommentAction\(\): void/.test(commentsPage) &&
    /this\.commentAction\.action === GALLERY_COMMENT_ACTION_TRANSLATE[\s\S]*this\.translateComment\(comment, this\.commentAction\.sourceText, false\)/.test(commentsPage) &&
    /this\.commentAction\.action === GALLERY_COMMENT_ACTION_TOGGLE_TRANSLATION[\s\S]*this\.toggleCommentTranslation\(comment\)/.test(commentsPage) &&
    /this\.commentAction\.action === GALLERY_COMMENT_ACTION_AUTO_TRANSLATE[\s\S]*this\.autoTranslateComment\(comment, this\.commentAction\.sourceText\)/.test(commentsPage) &&
    /commentListItemKey[\s\S]*return c\.commentId/.test(commentsPage) &&
    !/return `\$\{c\.commentId\}:\$\{c\.vote\}:\$\{c\.score\}:\$\{c\.translationShown\}:\$\{c\.translationLoading\}:\$\{c\.translationText\.length\}`/.test(commentsPage) &&
    !/comments: this\.visibleComments\(\)/.test(commentsPage),
  'full comments page must render separate ListItems and handle card commands in page context',
)
ok(
  /@ObservedV2[\s\S]*export class EhGalleryComment/.test(commentModel) &&
    /@Trace translationText: string = ''/.test(commentModel) &&
    /@Trace translationShown: boolean = false/.test(commentModel) &&
    /@Trace translationLoading: boolean = false/.test(commentModel) &&
    /@Trace translationAutoStarted: boolean = false/.test(commentModel) &&
    /applyCommentTranslationState/.test(commentsPage) &&
    /animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}/.test(commentsPage) &&
    /onCommentRenderStateChanged\(\): void[\s\S]*animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}/.test(commentsCard) &&
    /private toggleOrTranslate\(c: EhGalleryComment\): void[\s\S]*animateTo\(\{ duration: ThemeConstants\.ANIM_DURATION, curve: Curve\.EaseOut \}[\s\S]*this\.liveTranslationShown = !this\.liveTranslationShown/.test(commentsCard) &&
    /private beginTranslationLoading\(c: EhGalleryComment\): void[\s\S]*this\.liveTranslationShown = true[\s\S]*this\.liveTranslationLoading = true[\s\S]*c\.translationShown = true[\s\S]*c\.translationLoading = true/.test(commentsCard) &&
    /private toggleOrTranslate\(c: EhGalleryComment\): void[\s\S]*this\.beginTranslationLoading\(c\)[\s\S]*this\.publishTranslate\(c, sourceText\)/.test(commentsCard) &&
    /current\.translationText = translated/.test(commentsPage) &&
    /current\.translationShown = shown/.test(commentsPage) &&
    !/private applyCommentTranslationState[\s\S]*this\.comments = nextComments/.test(commentsPage) &&
    /commentRowKey[\s\S]*return c\.commentId/.test(commentsCard) &&
    !/return `\$\{c\.commentId\}:\$\{c\.vote\}:\$\{c\.score\}:\$\{c\.translationShown\}:\$\{c\.translationLoading\}:\$\{c\.translationText\.length\}`/.test(commentsCard) &&
    /CommentBody\(c: EhGalleryComment\)[\s\S]*Column\(\{ space: ThemeConstants\.SPACE_XS \}\)[\s\S]*this\.CommentText\(this\.activeCommentBodyText/.test(commentsCard) &&
    !/translatedComments/.test(commentsCard),
  'comment translation row state must repaint through observed field mutation while row keys stay stable',
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
    /TranslationAction\(c: EhGalleryComment\)[\s\S]*this\.useSingleComment && this\.liveTranslationShown && this\.liveTranslationText\.length > 0[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(commentsCard) &&
    /TranslationAction\(c: EhGalleryComment\)[\s\S]*!this\.useSingleComment && c\.translationShown && c\.translationText\.length > 0[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(commentsCard) &&
    /FooterAction\(icon: Resource, color: ResourceColor, disabled: boolean, action: \(\) => void/.test(commentsCard) &&
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
  /commentTextSegments\(text: string\): CommentTextSegment\[\]/.test(commentsCard) &&
    /Span\(seg\.text\)/.test(commentsCard) &&
    /firstCommentUrl\(text: string\): string/.test(commentsCard) &&
    /TapGesture\(\{ count: 1 \}\)/.test(commentsCard) &&
    /const url: string = this\.firstCommentUrl\(text\)[\s\S]*this\.openCommentUrl\(url\)/.test(commentsCard) &&
    !/enableDataDetector\(true\)/.test(commentsCard) &&
    /commentContainsLink\(c: EhGalleryComment\): boolean/.test(commentsCard) &&
    /this\.canOpenFullComments\(\) && !this\.commentContainsLink\(c\)/.test(commentsCard) &&
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
