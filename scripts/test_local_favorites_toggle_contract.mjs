#!/usr/bin/env node
/**
 * Contract for the detail-page local favorite toggle.
 *
 * FE grounding:
 * - eros_fe/lib/pages/gallery/view/gallery_favcat.dart renders a heart affordance on detail.
 * - eros_fe/lib/pages/gallery/controller/gallery_fav_controller.dart treats favcat `l` as a local
 *   favorite and toggles add/remove through FavController.
 * - eros_fe/lib/pages/controller/fav_controller.dart writes local favorites through LocalFavController
 *   instead of the network when the selected favcat is `l`.
 *
 * Run: node scripts/test_local_favorites_toggle_contract.mjs
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p) => readFileSync(join(ROOT, p), 'utf8')

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const localSettings = read('shared/src/main/ets/settings/LocalFavSettings.ets')
const ehConstants = read('shared/src/main/ets/constants/EhConstants.ets')
const feButton = read('../eros_fe/lib/pages/gallery/view/gallery_favcat.dart')
const feController = read('../eros_fe/lib/pages/gallery/controller/gallery_fav_controller.dart')
const feFav = read('../eros_fe/lib/pages/controller/fav_controller.dart')
const locales = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/ja_JP/element/string.json',
]

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('FE detail heart affordance exists',
  /class GalleryFavButton[\s\S]*FontAwesomeIcons\.heart[\s\S]*onTap: \(\) => _favController\.tapFav\(\)/.test(feButton))
ok('FE controller maps local favorite to favcat l',
  /localFav \? 'l' : ''/.test(feController) && /bool get isFav => favcat\.isNotEmpty \|\| localFav/.test(feController))
ok('FE local favorite selection bypasses network and writes LocalFavController',
  /if \(_favcat != 'l'\)[\s\S]*galleryAddFavorite[\s\S]*else[\s\S]*_localFavController\.addLocalFav/.test(feFav))
ok('FE local favorite removal bypasses network',
  /if \(favcat\.isNotEmpty && favcat != 'l'\)[\s\S]*galleryAddFavorite[\s\S]*else[\s\S]*_localFavController\.removeFavByGid/.test(feFav))

ok('LocalFavSettings exposes add remove contains helpers',
  /static async add\(context: common\.UIAbilityContext, gallery: EhGallery\): Promise<boolean>/.test(localSettings) &&
  /static async removeByGid\(context: common\.UIAbilityContext, gid: string\): Promise<boolean>/.test(localSettings) &&
  /static contains\(gid: string\): boolean/.test(localSettings))
ok('LocalFavSettings marks stored galleries as favcat l',
  /g\.favcat = 'l'/.test(localSettings) && /g\.favTitle = 'Local'/.test(localSettings))
ok('Local favcat has a semantic heart color',
  /if \(slot === 'l'\) \{[\s\S]*return '#23b26d'/.test(ehConstants))

ok('GalleryDetailPage imports local favorite state and settings',
  /LocalFavSettings/.test(detail) && /LocalFavState/.test(detail) && /connectLocalFav/.test(detail))
ok('GalleryDetailPage keeps local favorite state reactive',
  /@Local localFav: LocalFavState = connectLocalFav\(\)/.test(detail) &&
  /this\.localFav\.items\.some\(\(item: EhGallery\) => item\.gid === gid\)/.test(detail))
ok('GalleryDetailPage builds a safe local favorite snapshot from detail or route seed',
  /private currentGalleryForLocalFav\(\): EhGallery \{[\s\S]*this\.vm\.gallery\.copy\(\)[\s\S]*this\.params\.thumbUrl[\s\S]*this\.params\.fileCount/.test(detail))
ok('GalleryDetailPage toggles local favorite without remote favorite writes',
  /private async toggleLocalFavorite\(\): Promise<void> \{[\s\S]*LocalFavSettings\.removeByGid[\s\S]*LocalFavSettings\.add/.test(detail) &&
  !/toggleLocalFavorite[\s\S]*galleryAddFavorite/.test(detail))
ok('GalleryDetailPage exposes local favorite as a secondary title menu action before share',
  /private detailMenu\(\): Record<string, Object> \{[\s\S]*favoriteInner[\s\S]*this\.localFavoriteLabel\(\)[\s\S]*sys\.symbol\.heart[\s\S]*shareInner[\s\S]*const items: Record<string, Object>\[\] = \[\{ 'content': favoriteInner \}, \{ 'content': shareInner \}\][\s\S]*'maxCount': 2/.test(detail))
ok('GalleryDetailPage keeps the primary read FAB intact',
  /Button\(\{ type: ButtonType\.Capsule \}\)[\s\S]*this\.openReader\(this\.resumeIndex\(\)\)/.test(detail))

for (const file of locales) {
  const src = read(file)
  ok(`${file} has local favorite detail strings`,
    /"name": "detail_add_local_favorite"/.test(src) &&
    /"name": "detail_remove_local_favorite"/.test(src) &&
    /"name": "detail_local_favorite_added"/.test(src) &&
    /"name": "detail_local_favorite_removed"/.test(src))
}

console.log(`✓ local favorites toggle contract: ${passed} assertions passed`)
