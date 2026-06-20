#!/usr/bin/env node
/**
 * Contract: remote EH favorite is an in-detail sheet with a real protected submit path.
 *
 * Grounding:
 * - eros_fe submits /gallerypopups.php?gid=<gid>&t=<token>&act=addfav with form fields
 *   favcat, update=1, favnote.
 * - eros_fe's favorite selector rows show one user favorite-folder name with a colored heart and count;
 *   NextE must not render a technical "slot N" subtitle or tiny metadata as the primary affordance.
 * - NextE must not navigate to a separate favorite page; the detail menu opens a sheet with
 *   left cancel, right check/submit, note input, favcat slots, and an optional remove row.
 * - Automation may validate the sheet/cancel path without actually submitting a non-idempotent EH write.
 *
 * Run: node scripts/test_gallery_remote_favorite_sheet_contract.mjs
 */
import { existsSync, readFileSync } from 'node:fs'
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
const api = read('shared/src/main/ets/network/EhApiService.ets')
const http = read('shared/src/main/ets/network/EhHttpClient.ets')
const parser = read('shared/src/main/ets/parser/EhGalleryFavoriteParser.ets')
const modal = read('shared/src/main/ets/components/AppModalScaffold.ets')
const remoteDetail = detail
  .split('private openRemoteFavorite(): void {')[1]
  .split('build() {')[0]

ok(!existsSync(join(ROOT, 'feature/gallery/src/main/ets/pages/GalleryRemoteFavoritePage.ets')),
  'remote favorite is not a separate page file')
ok(!/GalleryRemoteFavoriteParams|GalleryRemoteFavoritePage|name === 'GalleryRemoteFavorite'/.test(route + sharedIndex + galleryIndex + entry),
  'remote favorite no longer registers a separate route')
ok(/remoteFavoriteSheetShown/.test(detail) && /\.bindSheet\(\$\$this\.remoteFavoriteSheetShown,\s*this\.RemoteFavoriteSheet\(\)/.test(detail),
  'detail hosts remote favorite in a bindSheet')
ok(/AppModalScaffold\(\{[\s\S]*title:\s*\$r\('app\.string\.detail_remote_favorite'\)[\s\S]*confirmAction/.test(detail),
  'favorite chooser uses the shared HDS modal scaffold for title actions')
ok(!/RemoteFavoriteSheetTitle|title:\s*this\.RemoteFavoriteSheetTitle/.test(detail),
  'favorite chooser does not hand-roll a business-page sheet title')
ok(/showClose:\s*false/.test(detail) && !/title:\s*\{ title:/.test(detail),
  'bindSheet only hosts the modal; title semantics live in AppModalScaffold')
ok(!/Button\(\{ type: ButtonType\.Normal \}\)[\s\S]*detail_remote_favorite_save/.test(remoteDetail),
  'sheet content does not duplicate confirm as a bottom button')
ok(/HdsNavigationTitleMode\.MODAL/.test(modal) && /HdsNavigation/.test(modal),
  'AppModalScaffold renders an HDS modal navigation shell')
ok(/closeIcon:\s*Resource\s*=\s*\$r\('sys\.symbol\.xmark'\)/.test(modal) &&
  /confirmIcon:\s*Resource\s*=\s*\$r\('sys\.symbol\.checkmark'\)/.test(modal) &&
  /subIcon:\s*\{[\s\S]*icon:\s*this\.closeIcon/.test(modal) &&
  /menu:\s*\{[\s\S]*icon:\s*this\.confirmIcon/.test(modal),
  'AppModalScaffold supplies left cancel and right confirm actions')
ok(/IconStyleMode\.SMALL/.test(modal) && /confirmEnabled/.test(modal) && /confirmLoading/.test(modal),
  'AppModalScaffold uses HDS small title actions with enabled/loading state')
ok(/TextArea\(\{[\s\S]*placeholder:\s*\$r\('app\.string\.detail_remote_favorite_note_placeholder'\)/.test(detail),
  'sheet contains a favorite-note input')
ok(/getGalleryFavoriteInfo/.test(detail) && /this\.remoteFavoriteSlots\s*=\s*info\.favcats/.test(detail),
  'sheet refreshes real user favorite folder names from the gallery favorite popup')
ok(!/connectFavSelection\(\)|this\.favSelection\.favList|FavcatListSettings/.test(detail),
  'detail sheet does not seed fake or stale favorite-folder names from favorites tab cache')
ok(/remoteFavoriteSelectedCat\s*=\s*fav\.favId/.test(detail) && /remoteFavoriteSelectedCat\s*=\s*'favdel'/.test(detail),
  'sheet can choose a favcat slot or remove existing remote favorite')
ok(/'label':\s*\$r\('app\.string\.detail_favorite'\)/.test(detail) &&
  !/'label':\s*this\.localFavoriteLabel\(\)/.test(detail) &&
  !/const remoteFavoriteInner/.test(detail),
  'detail exposes one HDS Favorite action instead of split local and EH favorite menu entries')
ok(!/detailMenu\(\):[\s\S]*detail_favorite[\s\S]*IconStyleMode\.SMALL/.test(detail),
  'detail title-bar favorite keeps the default HDS action size and only changes icon color')
ok(/favoriteTitleBarIcon\(\):\s*Resource\s*\|\s*SymbolGlyphModifier/.test(detail) &&
  /this\.vm\.gallery\.favcat\.length > 0[\s\S]*SymbolGlyphModifier\(\$r\('sys\.symbol\.heart_fill'\)\)[\s\S]*EhConstants\.favCatColor\(this\.vm\.gallery\.favcat\)/.test(detail),
  'title-bar favorite icon uses the remote favcat color when gallery is in EH favorites')
ok(/this\.isLocalFavorite\(\)[\s\S]*ThemeConstants\.BRAND_PRIMARY/.test(detail),
  'title-bar favorite icon falls back to local favorite color only when no remote favcat is present')
ok(!/FavoriteTitleBarColorOverlay|TITLE_BAR_FAVORITE_OVERLAY|stackBuilder[\s\S]*favorite/i.test(detail),
  'detail does not draw a second custom favorite glyph over the HDS title action')
ok(!/menuStyle\s*:\s*\{[\s\S]*iconColor\s*:\s*EhConstants\.favCatColor/.test(detail),
  'remote favcat color is not applied as global menuStyle iconColor, which would tint share/refresh/overflow')
ok(/SymbolGlyph\(\$r\('sys\.symbol\.heart_fill'\)\)[\s\S]*\.fontSize\(24\)[\s\S]*EhConstants\.favCatColor\(fav\.favId\)/.test(detail),
  'favorite folder rows use a prominent colored favcat heart')
ok(/Text\(fav\.favTitle\)[\s\S]*\.fontSize\(ThemeConstants\.FONT_SIZE_HEADING\)/.test(detail),
  'favorite folder rows show the user folder name as readable primary text')
ok(!/detail_remote_favorite_slot/.test(remoteDetail),
  'favorite folder rows do not show technical slot-number subtitles')
ok(!/Favorites \$\{value\}|Favorites 0|Fav0/.test(detail + parser),
  'parser/detail must not manufacture fake Favorites N folder names')
ok(/submitRemoteFavorite/.test(detail) && /EhApiService\.getInstance\(\)\.updateGalleryFavorite/.test(detail),
  'right check calls the real protected favorite submit path')
ok(/await this\.vm\.refresh\(\)/.test(detail) && /detail_remote_favorite_saved/.test(detail),
  'successful submit refreshes visible detail state and reports success')
ok(!/暂不提交|not submit changes yet|read-only|readonly/i.test(remoteDetail),
  'detail implementation does not present this feature as unsupported')

ok(/postFormUrlEncoded/.test(http) && /application\/x-www-form-urlencoded/.test(http),
  'HTTP client supports form-url-encoded POSTs')
ok(/updateGalleryFavorite/.test(api) && /gallerypopups\.php/.test(api) && /act=addfav/.test(api),
  'API service targets EH favorite popup endpoint')
ok(/getGalleryFavoriteInfo/.test(api) && /EhGalleryFavoriteParser\.parse/.test(api) && /act=addfav/.test(api),
  'API service reads the authoritative gallery favorite popup before rendering folders')
ok(/class EhGalleryFavoriteParser/.test(parser) && /RE_TEXTAREA/.test(parser) && /new Favcat\(value, title, 0\)/.test(parser),
  'favorite popup parser extracts real favcat titles and note text')
ok(/formPair\('favcat'/.test(api) && /formPair\('update', '1'\)/.test(api) && /formPair\('favnote'/.test(api),
  'API service sends favcat, update=1, and favnote form fields')
ok(/update\.favcat\.length > 0 \? update\.favcat : 'favdel'/.test(api),
  'empty/remove state maps to EH favdel')

const locales = ['base', 'en_US', 'zh_CN', 'ja_JP'].map((locale) =>
  read(`entry/src/main/resources/${locale}/element/string.json`))
for (const key of [
  'detail_favorite',
  'detail_remote_favorite',
  'detail_remote_favorite_current_slot',
  'detail_remote_favorite_none',
  'detail_remote_favorite_note_placeholder',
  'detail_remote_favorite_loading_slots',
  'detail_remote_favorite_no_slots',
  'detail_remote_favorite_remove',
  'detail_remote_favorite_saved',
]) {
  ok(locales.every((content) => content.includes(`"name": "${key}"`)),
    `i18n key present in all locales: ${key}`)
}

if (failures > 0) {
  console.error(`gallery remote favorite sheet contract failed: ${failures} issue(s)`)
  process.exit(1)
}

console.log(`✓ gallery remote favorite sheet contract: ${passed} assertions passed`)
