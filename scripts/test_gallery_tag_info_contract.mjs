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
const routeParams = read('shared/src/main/ets/model/RouteParams.ets')
const mytagsPage = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
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
    /export class TagTranslationInfo[\s\S]*name: string[\s\S]*intro: string[\s\S]*links: string/.test(tagService),
  'TagTranslationService must expose local tag name/intro/links lookup',
)
ok(
  /LongPressGesture\(\{ repeat: false, duration: 500 \}\)[\s\S]*this\.openTagInfo\(tg\.namespace, t\)/.test(tagsCard) &&
    /triggerLongPressHaptic\(\)[\s\S]*vibrator\.startVibration/.test(tagsCard) &&
    /AppModalScaffold\(\{[\s\S]*tag_info_title/.test(tagsCard) &&
    /TagTranslationService\.lookupTagInfo/.test(tagsCard),
  'GalleryTagsCard must open a tag-info sheet on long press and read local translation info',
)
ok(
  /EhApiPhpService\.tagGallery\([\s\S]*this\.gallery\.apikey[\s\S]*this\.gallery\.apiuid[\s\S]*tagKey[\s\S]*vote/.test(tagsCard) &&
    /onTagVoteChanged\(this\.selectedNamespace, this\.selectedTagText, nextVote\)/.test(tagsCard) &&
    /applyTagVote\(namespace: string, tagText: string, vote: number\)/.test(detailVm) &&
    /onTagVoteChanged:[\s\S]*this\.vm\.applyTagVote\(namespace, tagText, vote\)/.test(detailPage),
  'tag-info voting must use taggallery and repaint the detail tag vote color locally',
)
ok(
  /const existing: EhUsertag \| undefined = UserTagStore\.getInstance\(\)\.lookup\(this\.selectedNamespace, this\.selectedTagText\)/.test(tagsCard) &&
    /existing !== undefined && existing\.tagId\.length > 0[\s\S]*this\.openEditUserTag\(existing\)/.test(tagsCard) &&
    /this\.editSheetShown = true/.test(tagsCard) &&
    !/this\.tagInfoShown = false[\s\S]*connectNavStack\(\)\.stack\.pushPathByName\('MyTags'/.test(tagsCard) &&
    /new MyTagsPageParams\('', tagKey\)/.test(tagsCard) &&
    /targetTag: string = ''/.test(routeParams) &&
    /openTargetTagAfterLoad\(epoch\)/.test(mytagsPage),
  'Manage My Tag must edit an already-loaded usertag in a stacked sheet and only route to MyTags as fallback',
)
ok(
  /private EditUserTagSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*mytags_edit_title[\s\S]*mytags_save/.test(tagsCard) &&
    /EhApiPhpService\.setUserTag\([\s\S]*this\.gallery\.apikey[\s\S]*this\.gallery\.apiuid[\s\S]*this\.editTagId/.test(tagsCard) &&
    /private TagInfoSheet\(\)[\s\S]*this\.TagInfoHeader\(\)[\s\S]*this\.TagInfoBody\(\)[\s\S]*\.bindSheet\(\$\$this\.editSheetShown, this\.EditUserTagSheet\(\)/.test(tagsCard),
  'stacked tag edit sheet must be bound inside the tag-info sheet and save through setUserTag',
)
ok(
  /findLoadedTag\(targetTag\)[\s\S]*this\.openEditTag\(loaded\)/.test(mytagsPage) &&
    /for \(let i = 0; i < rootMytags\.tagSets\.length; i\+\+\)[\s\S]*getMyTags\(connectSiteMode\(\)\.isEx, tagsetId\)[\s\S]*this\.openEditTag/.test(mytagsPage) &&
    /this\.openAddTargetTag\(targetTag\)/.test(mytagsPage),
  'MyTags target mode must edit an already-added tag directly and only prefill add when absent',
)

for (const src of resources) {
  for (const key of ['tag_info_title', 'tag_info_intro', 'tag_info_links', 'tag_info_empty', 'tag_info_manage_mytag']) {
    ok(src.includes(`"name": "${key}"`), `missing i18n key ${key}`)
  }
}

if (failures > 0) {
  console.error(`\n✗ gallery tag info contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ gallery tag info contract passed')
