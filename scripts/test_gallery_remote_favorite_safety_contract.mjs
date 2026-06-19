#!/usr/bin/env node
/**
 * Contract: remote EH favorite management is discoverable but non-destructive in this lane.
 *
 * eros_fe's GalleryFavController/FavController can add, move, note, and delete favorites through
 * `/gallerypopups.php?act=addfav`. NextE must expose the user-visible entry and current state without
 * submitting the protected EH write until that flow is explicitly implemented and accepted.
 *
 * Run: node scripts/test_gallery_remote_favorite_safety_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
let passed = 0

function ok(cond, msg) {
  if (!cond) {
    failures += 1
    console.error(`✗ ${msg}`)
  } else {
    passed += 1
  }
}

const route = read('shared/src/main/ets/model/RouteParams.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const galleryIndex = read('feature/gallery/src/main/ets/Index.ets')
const entry = read('entry/src/main/ets/pages/Index.ets')
const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const page = read('feature/gallery/src/main/ets/pages/GalleryRemoteFavoritePage.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')

ok(/export class GalleryRemoteFavoriteParams/.test(route), 'route params exist for remote favorite page')
ok(/favcat: string/.test(route) && /favTitle: string/.test(route) && /favNote: string/.test(route),
  'route params carry current remote favorite state')
ok(/GalleryRemoteFavoriteParams/.test(sharedIndex), 'shared barrel exports remote favorite params')
ok(/export \{ GalleryRemoteFavoritePage \}/.test(galleryIndex), 'gallery barrel exports remote favorite page')
ok(/GalleryRemoteFavoritePage/.test(entry) && /name === 'GalleryRemoteFavorite'[\s\S]*GalleryRemoteFavoritePage\(\)/.test(entry),
  'entry registers GalleryRemoteFavorite route')

ok(/new GalleryRemoteFavoriteParams\([\s\S]*this\.vm\.gallery\.favcat[\s\S]*this\.vm\.gallery\.favTitle[\s\S]*this\.vm\.gallery\.favNote/.test(detail),
  'detail passes current remote favorite state to the route')
ok(/detail_remote_favorite/.test(detail) && /openRemoteFavorite\(\)/.test(detail),
  'detail menu exposes remote favorite entry')

ok(/Non-destructive remote EH favorite entry/.test(page), 'page documents non-destructive write boundary')
ok(/connectFavSelection\(\)/.test(page) && /this\.favSelection\.favList/.test(page),
  'page uses known favcat slots from shared favorites state')
ok(/detail_remote_favorite_current/.test(page) && /detail_remote_favorite_none/.test(page),
  'page shows current remote favorite state')
ok(/confirmRemoteWrite/.test(page) && /showAlertDialog/.test(page),
  'page gates all remote favorite write attempts behind a dialog')
ok(/detail_open_internal_web/.test(page) && /new GalleryWebParams\(this\.galleryUrl\(\), this\.titleText\(\)\)/.test(page),
  'page offers web handoff instead of submitting')
ok(!/gallerypopups\.php|addfav|postFavorite|galleryAddFavorite|method:\s*'POST'|method:\s*"POST"/.test(page),
  'remote favorite page does not submit EH favorite writes')
ok(!/gallerypopups\.php|addfav|postFavorite|galleryAddFavorite/.test(api),
  'EhApiService still has no favorite write endpoint in this lane')

const locales = ['base', 'en_US', 'zh_CN', 'ja_JP'].map((locale) =>
  read(`entry/src/main/resources/${locale}/element/string.json`))
for (const key of [
  'detail_remote_favorite',
  'detail_remote_favorite_current',
  'detail_remote_favorite_none',
  'detail_remote_favorite_readonly_desc',
  'detail_remote_favorite_protected_desc',
  'detail_remote_favorite_remove',
  'detail_remote_favorite_slot',
]) {
  ok(locales.every((content) => content.includes(`"name": "${key}"`)),
    `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery remote favorite safety contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log(`✓ gallery remote favorite safety contract: ${passed} assertions passed`)
