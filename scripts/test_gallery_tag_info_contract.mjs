#!/usr/bin/env node
/**
 * Contract: long-pressing a detail tag opens local translation info, tag voting, and My Tags management.
 *
 * Run: node scripts/test_gallery_tag_info_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (rel) => readFileSync(join(ROOT, rel), 'utf8')

const tagsCard = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const detailPage = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const tagService = read('shared/src/main/ets/services/TagTranslationService.ets')
const tagSettingsState = read('shared/src/main/ets/state/TagTranslationSettingsState.ets')
const tagSettings = read('shared/src/main/ets/settings/TagTranslationSettings.ets')
const tagSettingsPage = read('feature/settings/src/main/ets/pages/TagTranslationSettingsPage.ets')
const routeParams = read('shared/src/main/ets/model/RouteParams.ets')
const mytagsPage = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const mytagsTargetService = read('shared/src/main/ets/services/MyTagsTargetService.ets')
const resources = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
].map(read)

let failures = 0

function ok(condition, message) {
  if (!condition) {
    failures++
    console.error(`✗ ${message}`)
  }
}

ok(
  /static async lookupTagInfo\(/.test(tagService) &&
    /SELECT name, intro, links FROM tag_translations/.test(tagService) &&
    /translateInlineCodeTags\(context, rawIntro\)/.test(tagService) &&
    /filterIntroImages\([\s\S]*introImageLevel/.test(tagService) &&
    !/markdownDisplayText/.test(tagService) &&
    /info\.intro = filteredIntro\.trim\(\)/.test(tagService) &&
    /info\.links = rawLinks\.trim\(\)/.test(tagService) &&
    /extractMarkdownImageUrls/.test(tagService) &&
    /export class TagTranslationInfo[\s\S]*name: string[\s\S]*intro: string[\s\S]*links: string[\s\S]*images: string\[\]/.test(tagService),
  'TagTranslationService must expose Markdown tag intro/links without flattening display text',
)
ok(
  /TAG_INTRO_IMAGE_DISABLE/.test(tagService) &&
    /TAG_INTRO_IMAGE_NON_H/.test(tagService) &&
    /TAG_INTRO_IMAGE_R18/.test(tagService) &&
    /TAG_INTRO_IMAGE_R18G/.test(tagService) &&
    /intro\.replace\(regAll, ''\)/.test(tagService) &&
    /intro\.replace\(regR18And18g, ''\)/.test(tagService) &&
    /\.replace\(regR18g, ''\)[\s\S]*\.replace\(regR18And18g/.test(tagService),
  'TagTranslationService must mirror eros_fe tag intro image levels',
)
ok(
  /LongPressGesture\(\{ repeat: false, duration: 500 \}\)[\s\S]*this\.openTagInfo\(tg\.namespace, t\)/.test(tagsCard) &&
    /triggerLongPressHaptic\(\)[\s\S]*vibrator\.startVibration/.test(tagsCard) &&
    /AppModalScaffold\(\{[\s\S]*tag_info_title/.test(tagsCard) &&
    /TagTranslationService\.lookupTagInfo\([\s\S]*this\.tagTranslation\.introImageLevel/.test(tagsCard) &&
    /this\.infoImages = info\.images/.test(tagsCard) &&
    /private InfoMarkdownText\([\s\S]*markdownBodyLines/.test(tagsCard) &&
    /private InfoLinks\([\s\S]*markdownLinks/.test(tagsCard) &&
    /struct TagInfoIntroImage[\s\S]*sourceAspectRatio\(\): number[\s\S]*\.aspectRatio\(this\.sourceAspectRatio\(\)\)/.test(tagsCard) &&
    !/onComplete\([\s\S]*TagInfoIntroImage/.test(tagsCard) &&
    /private InfoImages\(\)[\s\S]*Row\(\{ space: ThemeConstants\.SPACE_SM \}\)[\s\S]*this\.InfoImageColumn\(0\)[\s\S]*this\.InfoImageColumn\(1\)/.test(tagsCard) &&
    /private InfoImageColumn\(remainder: number\)[\s\S]*if \(index % 2 === remainder\)[\s\S]*TagInfoIntroImage\(\{ url: url \}\)/.test(tagsCard) &&
    /this\.InfoLinks\(\$r\('app\.string\.tag_info_links'\), this\.infoLinks\)[\s\S]*this\.InfoImages\(\)/.test(tagsCard) &&
    /private TagInfoActionButton\([\s\S]*Button\(\{ type: ButtonType\.Circle/.test(tagsCard) &&
    /this\.TagInfoActionButton\([\s\S]*hand_thumbsup[\s\S]*hand_thumbsdown[\s\S]*bookmark/.test(tagsCard) &&
    !/footerActionOneText[\s\S]*tag_vote_up_short/.test(tagsCard) &&
    /scrollSizeMode: ScrollSizeMode\.CONTINUOUS/.test(tagsCard),
  'GalleryTagsCard must open a tag-info sheet on long press and render Markdown-derived content blocks',
)
ok(
  /@Trace introImageLevel: string = TAG_INTRO_IMAGE_NON_H/.test(tagSettingsState) &&
    /setIntroImageLevel/.test(tagSettings) &&
    /TAG_TRANSLATION_INTRO_IMAGE_LEVEL/.test(tagSettings) &&
    /IntroImageMenu/.test(tagSettingsPage) &&
    /tag_translation_intro_image_level/.test(tagSettingsPage),
  'Tag translation settings must expose the eros_fe tag intro image level switch',
)
ok(
  /EhApiPhpService\.tagGallery\([\s\S]*this\.gallery\.apikey[\s\S]*this\.gallery\.apiuid[\s\S]*tagKey[\s\S]*vote/.test(tagsCard) &&
    /onTagVoteChanged\(this\.selectedNamespace, this\.selectedTagText, nextVote\)/.test(tagsCard) &&
    /applyTagVote\(namespace: string, tagText: string, vote: number\)/.test(detailVm) &&
    /onTagVoteChanged:[\s\S]*this\.vm\.applyTagVote\(namespace, tagText, vote\)/.test(detailPage),
  'tag-info voting must use taggallery and repaint the detail tag vote color locally',
)
ok(
  /MyTagsTargetService\.resolve\(connectSiteMode\(\)\.isEx, tagKey\)/.test(tagsCard) &&
    /result\.found && result\.tag !== null && result\.tag\.tagId\.length > 0[\s\S]*this\.openEditUserTag\(result\.tag, result\.mytags\)/.test(tagsCard) &&
    /result\.tagsets\.length <= 1[\s\S]*this\.openAddUserTag\(result\.targetTag, result\.tagsetId\)/.test(tagsCard) &&
    /this\.tagsetOptions = result\.tagsets/.test(tagsCard) &&
    /this\.editSheetShown = true/.test(tagsCard) &&
    /private TagsetSelectSheet\(\)[\s\S]*tag_info_select_tagset_title[\s\S]*this\.chooseTagsetForAdd\(tagset\.tagsetId\)/.test(tagsCard) &&
    /private AddUserTagSheet\(\)[\s\S]*mytags_add_title[\s\S]*this\.confirmSubmitAdd\(\)/.test(tagsCard) &&
    !/new MyTagsPageParams\('', tagKey\)/.test(tagsCard) &&
    /targetTag: string = ''/.test(routeParams) &&
    /openTargetTagAfterLoad\(epoch\)/.test(mytagsPage) &&
    /export class MyTagsTargetService/.test(mytagsTargetService) &&
    /static async resolve\(isEx: boolean, fullTag: string\)/.test(mytagsTargetService) &&
    /getMyTags\(isEx, ''\)/.test(mytagsTargetService) &&
    /for \(let i = 0; i < root\.tagSets\.length; i\+\+\)[\s\S]*getMyTags\(isEx, tagset\.tagsetId\)/.test(mytagsTargetService),
  'Manage My Tag must resolve target tag from real MyTags data and use stacked sheets instead of cache-driven routing',
)
ok(
  /private EditUserTagSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*mytags_edit_title[\s\S]*mytags_save/.test(tagsCard) &&
    /this\.MyTagTitleBlock\(this\.editTagDisplay, this\.editTagRaw\.length > 0 \? this\.editTagRaw : this\.editTagTitle\)/.test(tagsCard) &&
    /private currentInfoNameForFullTag\(fullTag: string\): string[\s\S]*this\.infoName\.trim\(\)[\s\S]*MyTagsTargetService\.normalizeFullTag\(this\.selectedTagKey\(\)\)[\s\S]*MyTagsTargetService\.normalizeFullTag\(fullTag\)/.test(tagsCard) &&
    /private openAddUserTag\(fullTag: string, tagset: string\): void \{[\s\S]*const infoName: string = this\.currentInfoNameForFullTag\(fullTag\)[\s\S]*this\.addTagDisplay = this\.localizedFullTagDisplay\(fullTag, infoName\)/.test(tagsCard) &&
    /private editTitleForUserTag\(t: EhUsertag\): string \{[\s\S]*const infoName: string = this\.currentInfoNameForFullTag\(t\.tag\)[\s\S]*return this\.localizedFullTagDisplay\(t\.tag, infoName\)/.test(tagsCard) &&
    /EhApiPhpService\.setUserTag\([\s\S]*this\.editApikey[\s\S]*this\.editApiuid[\s\S]*this\.editTagId/.test(tagsCard) &&
    /EhApiService\.getInstance\(\)\.addUserTag\([\s\S]*tagName: this\.addTagTitle[\s\S]*tagset: this\.addTagset/.test(tagsCard) &&
    /private ManageUserTagSheet\(\)[\s\S]*TAG_INFO_MANAGE_EDIT[\s\S]*this\.EditUserTagSheet\(\)[\s\S]*TAG_INFO_MANAGE_ADD[\s\S]*this\.AddUserTagSheet\(\)[\s\S]*TAG_INFO_MANAGE_TAGSET[\s\S]*this\.TagsetSelectSheet\(\)/.test(tagsCard) &&
    /private TagInfoManageActionButton\([\s\S]*this\.openMyTagsForSelectedTag\(\)[\s\S]*\.bindSheet\(\$\$this\.editSheetShown, this\.ManageUserTagSheet\(\)/.test(tagsCard) &&
    !/manageSheetDetents|detentSelection|tagsetSheetShown/.test(tagsCard),
  'stacked tag edit/add sheets must stay inside the tag-info sheet without dynamic height control',
)
ok(
  /ConciseListRow/.test(tagsCard) &&
    /private TagsetSelectSheet\(\)[\s\S]*GroupedListSection\(\)[\s\S]*ConciseListRow\(\{[\s\S]*title: tagset\.name[\s\S]*trailingText: `\$\{tagset\.count\}`[\s\S]*showChevron: true[\s\S]*this\.chooseTagsetForAdd\(tagset\.tagsetId\)/.test(tagsCard) &&
    /private TagsetRowDivider\(\)[\s\S]*ohos_id_color_list_separator/.test(tagsCard) &&
    !/Text\(`\$\{tagset\.name\} \(\$\{tagset\.count\}\)`\)/.test(tagsCard) &&
    !/private TagsetSelectSheet\(\)[\s\S]*SymbolGlyph\(\$r\('sys\.symbol\.chevron_right'\)\)/.test(tagsCard),
  'tagset selection sheet must reuse settings-style list rows instead of hand-rolled row text',
)
ok(
    /MyTagsTargetService\.resolve\(connectSiteMode\(\)\.isEx, targetTag\)/.test(mytagsPage) &&
    /resolved\.found && resolved\.tag !== null[\s\S]*this\.openEditTag/.test(mytagsPage) &&
    /MyTagsTargetService\.findLoadedTag\(this\.mytags, targetTag\)/.test(mytagsPage) &&
    /this\.openAddTargetTag\(resolved\.targetTag\.length > 0 \? resolved\.targetTag : targetTag\)/.test(mytagsPage),
  'MyTags target mode must share the same resolver as the detail tag-info manage flow',
)

for (const src of resources) {
  for (const key of [
    'tag_info_title',
    'tag_info_intro',
    'tag_info_links',
    'tag_info_empty',
    'tag_info_manage_mytag',
    'tag_info_select_tagset_title',
    'tag_translation_intro_image_level',
    'tag_translation_intro_image_disable',
    'tag_translation_intro_image_nonh',
    'tag_translation_intro_image_r18',
    'tag_translation_intro_image_r18g',
  ]) {
    ok(src.includes(`"name": "${key}"`), `missing i18n key ${key}`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery tag info contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ gallery tag info contract passed')
