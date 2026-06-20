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
 *   left cancel, right check/submit, note input, and favcat slots.
 * - The sheet must distinguish current state from pending action. An unfavorited gallery must not
 *   auto-select folder 0 because that looks identical to a gallery already in folder 0.
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
const detailVm = read('feature/gallery/src/main/ets/viewmodel/GalleryDetailViewModel.ets')
const homeVm = read('feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets')
const homeBody = read('feature/home/src/main/ets/components/GalleryListBody.ets')
const searchVm = read('feature/search/src/main/ets/viewmodel/SearchViewModel.ets')
const searchPage = read('feature/search/src/main/ets/pages/GallerySearchPage.ets')
const favoritesVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
const favcatPage = read('feature/user/src/main/ets/components/FavcatPage.ets')
const mutationState = read('shared/src/main/ets/state/GalleryFavoriteMutationState.ets')
const api = read('shared/src/main/ets/network/EhApiService.ets')
const http = read('shared/src/main/ets/network/EhHttpClient.ets')
const parser = read('shared/src/main/ets/parser/EhGalleryFavoriteParser.ets')
const modal = read('shared/src/main/ets/components/AppModalScaffold.ets')
const remoteDetail = detail
  .split('private openRemoteFavorite(): void {')[1]
  .split('build() {')[0]
const localFavoriteRow = detail
  .split('@Builder\n  private LocalFavoriteRow() {')[1]
  .split('@Builder\n  private RemoteFavoriteSheet() {')[0]
const favoriteTitleIcon = detail
  .split('private favoriteTitleBarIcon(): Resource | SymbolGlyphModifier {')[1]
  .split('private galleryUrl(): string {')[0]

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
ok(!/openRemoteFavorite\(\): void \{[\s\S]*this\.remoteFavoriteSlots\s*=\s*\[\]/.test(detail),
  'opening the sheet keeps the previous favcat list cached while refresh runs')
ok(!/detail_remote_favorite_loading_slots/.test(remoteDetail) && !/LoadingProgress\(\)[\s\S]*remoteFavoriteLoadingFavcats/.test(remoteDetail),
  'favorite-folder refresh never inserts a transient loading row into the sheet content')
ok(/RemoteFavoriteSlotCacheState/.test(detail) &&
  /connectRemoteFavoriteSlotCache/.test(detail) &&
  /this\.remoteFavoriteSlots\s*=\s*this\.copyFavcats\(this\.favoriteSlotCache\.favcats\)/.test(detail) &&
  /this\.favoriteSlotCache\.update\(info\.favcats\)/.test(detail),
  'favorite sheet uses an account-level real favcat cache across different galleries')
ok(/if \(this\.remoteFavoriteSlots\.length === 0 && this\.favoriteSlotCache\.favcats\.length > 0\)[\s\S]*this\.remoteFavoriteSheetShown = true/.test(remoteDetail),
  'cross-gallery sheet opens with cached real favcat slots before the background popup refresh')
ok(/catch \(e\) \{[\s\S]*this\.remoteFavoriteError = EhErrorText\.forUser\(e\)[\s\S]*\} finally/.test(remoteDetail) &&
  !/catch \(e\) \{[\s\S]*this\.remoteFavoriteSlots\s*=\s*\[\]/.test(remoteDetail),
  'favorite popup failure reports a stable error without clearing cached sheet content')
ok(/RemoteFavoriteSlotCacheState/.test(sharedIndex) &&
  /favcats: Favcat\[\]/.test(mutationState + read('shared/src/main/ets/state/RemoteFavoriteSlotCacheState.ets')),
  'remote favorite slot cache is exported as shared V2 state')
ok(!/connectFavSelection\(\)|this\.favSelection\.favList|FavcatListSettings/.test(detail),
  'detail sheet does not seed fake or stale favorite-folder names from favorites tab cache')
ok(!/remoteFavoriteSelectedCat\s*=\s*info\.favcats\.length > 0 \? info\.favcats\[0\]\.favId : ''/.test(detail) &&
  !/remoteFavoriteSelectedCat\s*=\s*info\.favcats\[0\]\.favId/.test(detail),
  'unfavorited galleries do not auto-select folder 0')
ok(/this\.vm\.gallery\.favcat\.length > 0 && info\.selectFavcat\.length > 0/.test(detail),
  'popup default selected favcat is ignored unless the detail is already in EH favorites')
ok(/currentStillExists/.test(detail) && /this\.remoteFavoriteSelectedCat\s*=\s*this\.vm\.gallery\.favcat/.test(detail),
  'already-favorited galleries preserve their current EH folder selection')
ok(/remoteFavoriteStatusText\(\): ResourceStr/.test(detail) &&
  /remoteFavoriteSelectedCat === 'favdel'/.test(detail) &&
  /detail_remote_favorite_will_remove/.test(detail) &&
  /this\.vm\.gallery\.favcat\.length === 0[\s\S]*detail_remote_favorite_will_add/.test(detail) &&
  /remoteFavoriteSelectedCat === this\.vm\.gallery\.favcat[\s\S]*detail_remote_favorite_current_slot/.test(detail) &&
  /detail_remote_favorite_will_move/.test(detail),
  'remote sheet separates current state from pending add/move/remove copy')
ok(/canSubmitRemoteFavorite\(\): boolean/.test(detail) &&
  /this\.remoteFavoriteSlots\.length === 0[\s\S]*return false/.test(detail) &&
  /return this\.remoteFavoriteSelectedCat\.length > 0 \|\| this\.vm\.gallery\.favcat\.length > 0/.test(detail),
  'unfavorited remote sheet keeps confirm disabled until the user chooses a slot')
ok(/remoteFavoriteSelectedCat\s*=\s*fav\.favId/.test(detail) &&
  /isCurrentRemoteFavoriteSlot\(fav\.favId\)[\s\S]*remoteFavoriteSelectedCat\s*=\s*'favdel'/.test(detail),
  'sheet can choose a favcat slot or remove by tapping the current slot again')
ok(!/SymbolGlyph\(\$r\('sys\.symbol\.heart_slash'\)\)/.test(detail) &&
  !/Text\(\$r\('app\.string\.detail_remote_favorite_remove'\)\)/.test(detail),
  'remote favorite removal is not a separate mismatched content row')
ok(/detail_remote_favorite_will_add/.test(detail) &&
  /detail_remote_favorite_will_move/.test(detail) &&
  /detail_remote_favorite_current_badge/.test(detail),
  'sheet copy distinguishes pending add, pending move, and current slot')
ok(!/Toggle\(\{ type: ToggleType\.Switch[\s\S]*localFavorite/.test(detail) &&
  /localFavoriteActionLabel/.test(detail) &&
  /this\.toggleLocalFavoriteWithSafety\(\)/.test(detail),
  'local favorite is an action row, not a switch that opens a confirm dialog')
ok(!/ThemeConstants\.BRAND_PRIMARY/.test(localFavoriteRow),
  'local favorite row does not use brand primary color that can be confused with EH favcat colors')
ok(/'label':\s*\$r\('app\.string\.detail_favorite'\)/.test(detail) &&
  !/'label':\s*this\.localFavoriteLabel\(\)/.test(detail) &&
  !/const remoteFavoriteInner/.test(detail),
  'detail exposes one HDS Favorite action instead of split local and EH favorite menu entries')
ok(!/detailMenu\(\):[\s\S]*detail_favorite[\s\S]*IconStyleMode\.SMALL/.test(detail),
  'detail title-bar favorite keeps the default HDS action size and only changes icon color')
ok(/favoriteTitleBarIcon\(\):\s*Resource\s*\|\s*SymbolGlyphModifier/.test(detail) &&
  /this\.vm\.gallery\.favcat\.length > 0[\s\S]*SymbolGlyphModifier\(\$r\('sys\.symbol\.heart_fill'\)\)[\s\S]*EhConstants\.favCatColor\(this\.vm\.gallery\.favcat\)/.test(detail),
  'title-bar favorite icon uses the remote favcat color when gallery is in EH favorites')
ok(/this\.isLocalFavorite\(\)[\s\S]*EhConstants\.favCatColor\('l'\)/.test(favoriteTitleIcon) &&
  /this\.isLocalFavorite\(\) \? EhConstants\.favCatColor\('l'\)/.test(localFavoriteRow) &&
  !/ThemeConstants\.BRAND_PRIMARY/.test(favoriteTitleIcon + localFavoriteRow),
  'title-bar/local favorite fallback uses the local favcat semantic color only when no remote favcat is present')
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
ok(/await this\.vm\.refresh\(\)/.test(detail) &&
  /this\.vm\.applyRemoteFavoriteState\(nextFavcat, nextFavTitle, nextFavNote\)/.test(detail) &&
  /detail_remote_favorite_saved/.test(detail),
  'successful submit refreshes and explicitly writes the new detail favorite state')
ok(/const nextFavcat:\s*string\s*=\s*favcat === 'favdel' \? '' : favcat/.test(detail) &&
  /this\.favoriteMutation\.publish\(this\.params\.gid, nextFavcat, nextFavTitle, nextFavNote\)/.test(detail),
  'remote favorite delete publishes an empty favcat mutation instead of leaving stale filled hearts')
ok(/const previousFavcat:\s*string\s*=\s*this\.vm\.gallery\.favcat/.test(detail) &&
  /this\.vm\.applyRemoteFavoriteState\(nextFavcat, nextFavTitle, nextFavNote\)[\s\S]*this\.remoteFavoriteSheetShown = false[\s\S]*try \{/.test(detail),
  'remote favorite submit optimistically closes the sheet and updates UI before waiting for the network')
ok(/catch \(e\) \{[\s\S]*this\.vm\.applyRemoteFavoriteState\(previousFavcat, previousFavTitle, previousFavNote\)[\s\S]*this\.favoriteMutation\.publish\(this\.params\.gid, previousFavcat, previousFavTitle, previousFavNote\)[\s\S]*openToast/.test(detail),
  'remote favorite submit failure rolls detail/list state back and reports the error by toast')
ok(/applyRemoteFavoriteState\(favcat: string, favTitle: string, favNote: string\)/.test(detailVm) &&
  /next\.favcat\s*=\s*favcat/.test(detailVm) &&
  /this\.gallery\s*=\s*next/.test(detailVm),
  'detail VM has explicit favorite-state replacement because EhGallery.merge cannot clear empty favcat')
ok(/GalleryFavoriteMutationState/.test(mutationState) &&
  /@Trace version: number/.test(mutationState) &&
  /publish\(gid: string, favcat: string, favTitle: string, favNote: string\)/.test(mutationState),
  'shared V2 favorite mutation bus carries gid and the post-write favcat state')
ok(/connectGalleryFavoriteMutation/.test(sharedIndex),
  'favorite mutation bus is exported from shared')
ok(/@Monitor\('favoriteMutation\.version'\)/.test(homeBody) &&
  /this\.vm\.applyFavoriteMutation\(/.test(homeBody) &&
  /applyFavoriteMutation\(gid: string, favcat: string, favTitle: string\)/.test(homeVm) &&
  /next\.favcat\s*=\s*favcat/.test(homeVm) &&
  /this\.dataSource\.setData\(nextRows\)/.test(homeVm),
  'home retained list cards update their favorite heart from the post-write mutation')
ok(/@Monitor\('favoriteMutation\.version'\)/.test(searchPage) &&
  /this\.vm\.applyFavoriteMutation\(/.test(searchPage) &&
  /applyFavoriteMutation\(gid: string, favcat: string, favTitle: string\)/.test(searchVm) &&
  /effectiveFavoriteScope\(\) && favcat\.length === 0/.test(searchVm),
  'search retained results update favorites and remove deleted rows from favorite-scope search')
ok(/@Monitor\('favoriteMutation\.version'\)/.test(favcatPage) &&
  /this\.vm\.applyFavoriteMutation\(/.test(favcatPage) &&
  /applyFavoriteMutation\(gid: string, favcat: string, favTitle: string\)/.test(favoritesVm) &&
  /favcat\.length > 0 && \(this\.favcat === 'a' \|\| this\.favcat === favcat\)/.test(favoritesVm),
  'favorites retained tabs update or remove rows when a remote favorite is moved/deleted')
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
  'detail_remote_favorite_will_remove',
  'detail_remote_favorite_will_add',
  'detail_remote_favorite_will_move',
  'detail_remote_favorite_current_badge',
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
