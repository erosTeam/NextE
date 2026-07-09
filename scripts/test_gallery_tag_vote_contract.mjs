#!/usr/bin/env node
/**
 * Contract: protected gallery tag writes keep their EH request boundaries.
 *
 * eros_fe reference:
 * - taginfo_controller.dart calls Api.tagGallery(apikey, apiuid, gid, token, "namespace:tag", vote).
 * - taginfo_dialog.dart exposes vote up/down when no vote and withdraw by submitting the opposite vote
 *   when the user already voted.
 *
 * Automated validation must stop at opening/canceling the confirmation dialog unless explicitly
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

ok('api submits multi-tag additions as an upvote without inferring one tag result',
  /static async addGalleryTags\([\s\S]*tags: string[\s\S]*Promise<void>/.test(api) &&
    /normalizedTags\.length === 0/.test(api) &&
    /req\.tags = normalizedTags[\s\S]*req\.vote = 1/.test(api))

const parser = read('shared/src/main/ets/parser/EhGalleryDetailParser.ets')
ok('detail parser preserves logged-in tag vote classes',
  /attrs\.includes\('class="tup"'\)[\s\S]*tag\.vote = 1[\s\S]*attrs\.includes\('class="tdn"'\)[\s\S]*tag\.vote = -1/.test(parser))

const detailTags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
ok('detail tag chips keep their tap-to-search action',
  /private searchTag\(ns: string, t: SimpleTag\): void/.test(detailTags) &&
    /connectSearchAction\(\)\.publishQuery/.test(detailTags))

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
