#!/usr/bin/env node
/**
 * Contract: gallery tag write entry supports protected EH tag voting.
 *
 * eros_fe reference:
 * - taginfo_controller.dart calls Api.tagGallery(apikey, apiuid, gid, token, "namespace:tag", vote).
 * - taginfo_dialog.dart exposes vote up/down when no vote and withdraw by submitting the opposite vote
 *   when the user already voted.
 *
 * NextE keeps detail-page tag chips as tap-to-search. The write surface is GalleryEditTagsPage and
 * automated validation must stop at opening/canceling the confirmation dialog unless explicitly
 * authorized for a real submit.
 */
import fs from 'fs'
import path from 'path'

const ROOT = path.resolve(new URL('..', import.meta.url).pathname)
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8')

let failures = 0
function ok(name, condition) {
  if (!condition) {
    console.error(`✗ ${name}`)
    failures += 1
  }
}

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
ok('api exposes taggallery request shape',
  /class TagGalleryRequest[\s\S]*method: string = 'taggallery'[\s\S]*apikey: string[\s\S]*apiuid: number[\s\S]*gid: number[\s\S]*token: string[\s\S]*tags: string[\s\S]*vote: number/.test(api))
ok('api validates taggallery auth, tag key, and vote before posting',
  /static async tagGallery\([\s\S]*apikey: string[\s\S]*apiuid: string[\s\S]*tagKey: string[\s\S]*vote: number/.test(api) &&
    /apikey\.length === 0[\s\S]*token\.length === 0[\s\S]*normalizedTag\.length === 0[\s\S]*Number\.isNaN\(apiuidNum\)[\s\S]*Number\.isNaN\(gidNum\)[\s\S]*vote !== 1 && vote !== -1/.test(api))
ok('api posts taggallery to api.php as JSON and surfaces EH error',
  /postJson\([\s\S]*`\$\{base\}\/api\.php`[\s\S]*JSON\.stringify\(req\)/.test(api) &&
    /req\.tags = normalizedTag/.test(api) &&
    /req\.vote = vote/.test(api) &&
    /obj\.error !== undefined && obj\.error\.length > 0/.test(api))

const barrel = read('shared/src/main/ets/Index.ets')
ok('TagGalleryResult is exported from shared barrel',
  /EhApiPhpService[\s\S]*GalleryRatingResult[\s\S]*CommentVoteResult[\s\S]*TagGalleryResult/.test(barrel))

const parser = read('shared/src/main/ets/parser/EhGalleryDetailParser.ets')
ok('detail parser preserves logged-in tag vote classes',
  /attrs\.includes\('class="tup"'\)[\s\S]*tag\.vote = 1[\s\S]*attrs\.includes\('class="tdn"'\)[\s\S]*tag\.vote = -1/.test(parser))

const editPage = read('feature/gallery/src/main/ets/pages/GalleryEditTagsPage.ets')
ok('edit tags page no longer exposes readonly unsupported notice',
  !/detail_edit_tags_readonly_title|detail_edit_tags_readonly_desc|Non-destructive tag editing entry/.test(editPage))
ok('edit tags page stores apikey apiuid from freshly loaded detail',
  /this\.apiuid = result\.gallery\.apiuid/.test(editPage) &&
    /this\.apikey = result\.gallery\.apikey/.test(editPage))
ok('edit tags page opens tag action sheet from tag chips',
  /private openTagActions\(namespace: string, tag: SimpleTag\): void/.test(editPage) &&
    /\.onClick\(\(\) => \{[\s\S]*this\.openTagActions\(tg\.namespace, tag\)/.test(editPage) &&
    /bindSheet\(\$\$this\.actionSheetShown, this\.TagActionSheet\(\)/.test(editPage))
ok('edit tags page confirms before submitting tag vote',
  /private confirmTagVote\(vote: number\): void[\s\S]*showAlertDialog\([\s\S]*message: `\$\{tagKey\}`[\s\S]*submitTagVote\(tagKey, vote, this\.selectedTagVote\)/.test(editPage))
ok('edit tags page submits taggallery with detail api metadata',
  /EhApiPhpService\.tagGallery\([\s\S]*EhConstants\.baseUrl\(connectSiteMode\(\)\.isEx\)[\s\S]*this\.apikey[\s\S]*this\.apiuid[\s\S]*this\.params\.gid[\s\S]*this\.params\.token[\s\S]*tagKey[\s\S]*vote/.test(editPage))
ok('edit tags page models withdraw as opposite vote and local state as neutral',
  /this\.TagVoteAction\(\$r\('app\.string\.tag_vote_withdraw'\), -1, true\)/.test(editPage) &&
    /this\.TagVoteAction\(\$r\('app\.string\.tag_vote_withdraw'\), 1, true\)/.test(editPage) &&
    /previousVote > 0 && result\.vote < 0[\s\S]*previousVote < 0 && result\.vote > 0[\s\S]*nextTag\.vote = 0/.test(editPage))

const detailTags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
ok('detail tag chips keep tap-to-search and do not call taggallery',
  /private searchTag\(ns: string, t: SimpleTag\): void/.test(detailTags) &&
    /connectSearchAction\(\)\.publishQuery/.test(detailTags) &&
    !/tagGallery|confirmTagVote|openTagActions/.test(detailTags))

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'tag_vote_up',
    'tag_vote_down',
    'tag_vote_withdraw',
    'tag_vote_current_none',
    'tag_vote_current_up',
    'tag_vote_current_down',
    'tag_vote_up_success',
    'tag_vote_down_success',
    'tag_vote_withdraw_success',
    'tag_vote_failed',
    'tag_vote_unavailable',
  ]) {
    ok(`${locale} has ${key}`, strings.includes(`"name": "${key}"`))
  }
}

if (failures === 0) {
  console.log('✓ gallery tag vote contract passed')
  process.exit(0)
}
console.error(`✗ gallery tag vote contract: ${failures} failure(s)`)
process.exit(1)
