#!/usr/bin/env node
/**
 * Contract: My Tags existing-row edits are a real, bounded write loop.
 *
 * Scope: edit an existing usertag's watch/hide/weight/color through /api.php `setusertag`.
 * Out of scope: new tag creation and tagset create/rename/delete. Usertag deletion is a separate lane.
 *
 * Run: node scripts/test_mytags_setusertag_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
let failures = 0

function read(rel) {
  return readFileSync(join(ROOT, rel), 'utf8')
}

function ok(condition, message) {
  if (!condition) {
    failures += 1
    console.error(`✗ ${message}`)
  } else {
    console.log(`✓ ${message}`)
  }
}

const api = read('shared/src/main/ets/network/EhApiPhpService.ets')
const barrel = read('shared/src/main/ets/Index.ets')
const page = read('feature/user/src/main/ets/pages/MyTagsPage.ets')
const detailTags = read('feature/gallery/src/main/ets/components/GalleryTagsCard.ets')
const colorPicker = read('shared/src/main/ets/components/AppColorPicker.ets')
const colorFavoritesState = read('shared/src/main/ets/state/AppColorFavoritesState.ets')
const colorFavoritesSettings = read('shared/src/main/ets/settings/AppColorFavoritesSettings.ets')
const storageKeys = read('shared/src/main/ets/constants/StorageKeys.ets')
const settingsBootstrap = read('shared/src/main/ets/settings/SettingsBootstrap.ets')
const colorCellBody = colorPicker.substring(
  colorPicker.indexOf('private ColorCell(color: string)'),
  colorPicker.indexOf('private ColorFavorites()'),
)

const grounding = [
  'eros_fe: lib/pages/setting/mytags/eh_usertag_page.dart taps an existing row and lib/pages/setting/mytags/eh_usertag_edit_dialog.dart edits watch/hide/weight/color with flex_color_picker ColorPicker',
  'eros_fe: lib/network/api.dart Api.setUserTag posts /api.php method=setusertag with apiuid/apikey/tagid/tagwatch/taghide/tagcolor/tagweight',
  'primary information: current My Tags grouped chips plus the selected tag identity in the edit sheet',
  'primary action: save an existing tag edit; secondary actions are cancel and draft toggles; no new/tagset management in this lane',
  'Harmony expression: AppModalScaffold HDS modal with draft rows, switch-like toggles, text inputs, native confirmation, and non-destructive validation by cancelling',
]

ok(grounding.length === 5, 'MyTags setusertag lane has five-line grounding')
ok(grounding[0].includes('eh_usertag_page.dart') && grounding[1].includes('method=setusertag'),
  'grounding names concrete eros_fe UI and API files')

ok(/class SetUserTagRequest[\s\S]*method: string = 'setusertag'/.test(api),
  'EhApiPhpService defines a setusertag request')
ok(/tagwatch: number = 0[\s\S]*taghide: number = 0[\s\S]*tagcolor: string = ''[\s\S]*tagweight: string = ''/.test(api),
  'setusertag request carries watch/hide/color/weight fields')
ok(/static async setUserTag\([\s\S]*apikey: string,[\s\S]*apiuid: string,[\s\S]*tagId: string,[\s\S]*watched: boolean,[\s\S]*hidden: boolean,[\s\S]*color: string,[\s\S]*weight: string/.test(api),
  'EhApiPhpService exposes setUserTag with typed existing-tag fields')
ok(/req\.tagwatch = watched \? 1 : 0[\s\S]*req\.taghide = hidden \? 1 : 0[\s\S]*req\.tagcolor = normalizedColor[\s\S]*req\.tagweight = normalizedWeight/.test(api),
  'setUserTag serializes EH-compatible values')
ok(/postJson\([\s\S]*api\.php[\s\S]*JSON\.stringify\(req\)/.test(api),
  'setUserTag posts JSON to /api.php')
ok(/SetUserTagResult/.test(barrel), 'shared barrel exports SetUserTagResult')

ok(/AppModalScaffold/.test(page) && /EditTagSheet\(\)[\s\S]*AppModalScaffold\(\{[\s\S]*title: \$r\('app\.string\.mytags_edit_title'\)/.test(page),
  'MyTagsPage uses AppModalScaffold for existing-tag edits')
ok(/@Local myTagsSheetShown: boolean = false/.test(page) &&
  /@Local myTagsSheetKind: string = ''/.test(page) &&
  /bindSheet\(\$\$this\.myTagsSheetShown, this\.MyTagsSheet\(\)/.test(page) &&
  (page.match(/\.bindSheet\(/g) || []).length === 1,
  'MyTags sheets use one bindSheet host so edit/add/tagset bindings cannot close each other')
ok(/TagRow\(t: EhUsertag\)[\s\S]*ConciseListRow\(\{[\s\S]*action: \(\) => \{[\s\S]*this\.openEditTag\(t\)/.test(page),
  'tapping an existing My Tag management row opens the edit sheet')
ok(/export \{ AppColorPicker \} from '\.\/components\/AppColorPicker'/.test(barrel),
  'shared barrel exports the reusable AppColorPicker')
ok(/TabSegmentButtonV2/.test(colorPicker) &&
  /color_picker_grid[\s\S]*color_picker_sliders/.test(colorPicker) &&
  /COLOR_PICKER_MODE_GRID[\s\S]*COLOR_PICKER_MODE_SLIDERS/.test(colorPicker),
  'AppColorPicker exposes Grid and Sliders modes')
ok(/COLOR_PICKER_GRID_HUES[\s\S]*COLOR_PICKER_GRID_ROWS[\s\S]*Grid\(\)[\s\S]*columnsTemplate\('repeat\(13, 1fr\)'[\s\S]*rowsTemplate\('repeat\(10, 1fr\)'[\s\S]*aspectRatio\(13 \/ 10\)/.test(colorPicker) &&
  /saturationForGridRow[\s\S]*return 15[\s\S]*return 25[\s\S]*return 42[\s\S]*return 60[\s\S]*return 80[\s\S]*return 100/.test(colorPicker) &&
  /brightnessForGridRow[\s\S]*if \(row <= 5\)[\s\S]*return 100[\s\S]*return 90[\s\S]*return 78[\s\S]*return 66[\s\S]*return 54/.test(colorPicker) &&
  /grayForGridRow[\s\S]*brightness = 95[\s\S]*brightness = 90[\s\S]*brightness = 85[\s\S]*brightness = 80[\s\S]*brightness = 70[\s\S]*brightness = 60[\s\S]*brightness = 50[\s\S]*brightness = 30[\s\S]*brightness = 20[\s\S]*brightness \/ 100 \* 255/.test(colorPicker),
  'AppColorPicker grid mode uses an official-style HSB grid: gray column white-to-black and color rows light-to-dark')
ok(/@ObservedV2[\s\S]*class AppColorFavoritesState[\s\S]*@Trace colors: string\[\] = DEFAULT_APP_COLOR_FAVORITES[\s\S]*connectAppColorFavorites[\s\S]*AppStorageV2\.connect/.test(colorFavoritesState) &&
  /DEFAULT_APP_COLOR_FAVORITES: string\[\] = \[[\s\S]*'#F44336'[\s\S]*'#E91E63'[\s\S]*'#9C27B0'[\s\S]*'#673AB7'[\s\S]*'#3F51B5'[\s\S]*'#2196F3'[\s\S]*'#03A9F4'[\s\S]*'#00BCD4'[\s\S]*'#009688'[\s\S]*'#4CAF50'[\s\S]*'#8BC34A'[\s\S]*'#CDDC39'[\s\S]*'#FFEB3B'[\s\S]*'#FFC107'[\s\S]*'#FF9800'[\s\S]*'#FF5722'[\s\S]*'#795548'[\s\S]*'#607D8B'[\s\S]*'#9E9E9E'/.test(colorFavoritesState) &&
  /const COLOR_FAVORITE_ADD_ICON_SIZE: number = 20/.test(colorPicker) &&
  /@Local private colorFavorites: AppColorFavoritesState = connectAppColorFavorites\(\)/.test(colorPicker) &&
  /ColorFavorites\(\)[\s\S]*color_picker_favorites[\s\S]*this\.FavoriteCell\(index\)[\s\S]*columnsTemplate\('repeat\(9, 1fr\)'[\s\S]*rowsTemplate\('repeat\(4, 1fr\)'[\s\S]*aspectRatio\(9 \/ 4\)/.test(colorPicker) &&
  /FavoriteCell\(index: number\)[\s\S]*\.width\('100%'\)[\s\S]*\.aspectRatio\(1\)[\s\S]*this\.selectFavoriteColor\(index\)[\s\S]*this\.addFavoriteColor\(\)/.test(colorPicker) &&
  /Column\(\)[\s\S]*\.backgroundColor\(\$r\('app\.color\.card_background'\)\)[\s\S]*SymbolGlyph\(\$r\('sys\.symbol\.plus'\)\)[\s\S]*\.fontSize\(COLOR_FAVORITE_ADD_ICON_SIZE\)/.test(colorPicker) &&
  /addFavoriteColor\(\)[\s\S]*const color: string = this\.draftColor\(\)[\s\S]*const next: string\[\] = \[\][\s\S]*let exists: boolean = false[\s\S]*next\.push\(c\)[\s\S]*next\.push\(color\)[\s\S]*this\.colorFavorites\.colors = next[\s\S]*this\.persistFavorites\(next\)/.test(colorPicker) &&
  /LongPressGesture\(\{ repeat: false, duration: 500 \}\)[\s\S]*this\.removeFavoriteColor\(index\)/.test(colorPicker) &&
  /removeFavoriteColor\(index: number\)[\s\S]*if \(i !== index[\s\S]*next\.push\(c\)[\s\S]*this\.colorFavorites\.colors = next[\s\S]*this\.persistFavorites\(next\)/.test(colorPicker) &&
  !/Text\('\+'\)/.test(colorPicker) &&
  !/COLOR_FAVORITE_SELECTED_INNER_SIZE/.test(colorPicker) &&
  !/\.width\(this\.isCurrentColor\(this\.colorFavorites\.colors\[index\]\) \? '70%' : '100%'\)/.test(colorPicker) &&
  !/const next: string\[\] = \[color\]/.test(colorPicker),
  'AppColorPicker exposes a bounded 9x4 square favorites grid, system add glyph, append, long-press removal, and persistence hook')
ok(/APP_COLOR_FAVORITES: string = 'app\.colorFavorites'/.test(storageKeys) &&
  /AppColorFavoritesSettings\.restore\(context\)/.test(settingsBootstrap) &&
  /StorageKeys\.APP_COLOR_FAVORITES/.test(colorFavoritesSettings) &&
  /static async restore\(context: common\.UIAbilityContext\)/.test(colorFavoritesSettings) &&
  /static async persist\(context: common\.UIAbilityContext, colors: string\[\]\)/.test(colorFavoritesSettings) &&
  /MAX_APP_COLOR_FAVORITES: number = 36/.test(colorFavoritesSettings) &&
  /connectAppColorFavorites\(\)\.colors = colors/.test(colorFavoritesSettings) &&
  /return next/.test(colorFavoritesSettings) &&
  !/return next\.length > 0 \? next : DEFAULT_APP_COLOR_FAVORITES/.test(colorFavoritesSettings),
  'AppColorPicker favorites restore at startup and persist up to 36 colors through Preferences')
ok(/private ColorCell\(color: string\)[\s\S]*\.width\('100%'\)[\s\S]*\.height\('100%'\)[\s\S]*\.onClick/.test(colorCellBody) &&
  !/\.aspectRatio\(1\)/.test(colorCellBody),
  'AppColorPicker color-grid cells fill their grid tracks without white divider seams')
ok(/TextInput\(\{ text: this\.draftHex[\s\S]*\.backgroundColor\(\$r\('sys\.color\.ohos_id_color_button_normal'\)\)/.test(colorPicker) &&
  !/TextInput\(\{ text: this\.draftHex[\s\S]{0,260}\.backgroundColor\(\$r\('app\.color\.card_background'\)\)/.test(colorPicker),
  'AppColorPicker hex field has a visible input background distinct from the card surface')
ok(/HsbSliders\(\)[\s\S]*color_picker_hue[\s\S]*color_picker_saturation[\s\S]*color_picker_brightness/.test(colorPicker) &&
  /hueGradient\(\)[\s\S]*saturationGradient\(\)[\s\S]*brightnessGradient\(\)/.test(colorPicker) &&
  /@Local private draftHue: number[\s\S]*@Local private draftSaturation: number[\s\S]*@Local private draftBrightness: number/.test(colorPicker) &&
  /@Local private draftHex: string/.test(colorPicker) &&
  /HsbSliders\(\)[\s\S]*this\.HueSlider\(\)[\s\S]*this\.SaturationSlider\(\)[\s\S]*this\.BrightnessSlider\(\)/.test(colorPicker) &&
  /HueSlider\(\)[\s\S]*Text\(`\$\{Math\.round\(this\.draftHue\)\}`\)[\s\S]*Slider\(\{ value: this\.draftHue, min: 0, max: 360[\s\S]*\.trackColor\(this\.hueGradient\(\)\)[\s\S]*this\.draftHue = v[\s\S]*this\.commitDraftColor\(\)/.test(colorPicker) &&
  /SaturationSlider\(\)[\s\S]*Text\(`\$\{Math\.round\(this\.draftSaturation\)\}`\)[\s\S]*Slider\(\{ value: this\.draftSaturation, min: 0, max: 100[\s\S]*\.trackColor\(this\.saturationGradient\(\)\)[\s\S]*this\.draftSaturation = v[\s\S]*this\.commitDraftColor\(\)/.test(colorPicker) &&
  /BrightnessSlider\(\)[\s\S]*Text\(`\$\{Math\.round\(this\.draftBrightness\)\}`\)[\s\S]*Slider\(\{ value: this\.draftBrightness, min: 0, max: 100[\s\S]*\.trackColor\(this\.brightnessGradient\(\)\)[\s\S]*this\.draftBrightness = v[\s\S]*this\.commitDraftColor\(\)/.test(colorPicker) &&
  /\.selectedColor\(Color\.Transparent\)/.test(colorPicker) &&
  /new LinearGradient\(\[[\s\S]*offset: 0[\s\S]*offset: 1[\s\S]*\]\)/.test(colorPicker) &&
  !/axisValue\(|axisGradient\(|setAxis\(|HsbSlider\(/.test(colorPicker),
  'AppColorPicker slider mode uses HSB, not RGB')
ok(!/HsbSlider\(label: ResourceStr, value: number/.test(colorPicker) &&
  !/HsbSlider\(label: ResourceStr,[^\)]*gradient:/.test(colorPicker),
  'AppColorPicker sliders do not pass stale value or gradient snapshots into the builder')
ok(/TextInput\(\{ text: this\.draftHex[\s\S]*\.onChange\(\(value: string\) => \{[\s\S]*this\.handleHexInput\(value\)/.test(colorPicker) &&
  /handleHexInput\(value: string\)[\s\S]*if \(value === this\.draftHex\) \{[\s\S]*return[\s\S]*normalizedStrictHexFor\(value\)[\s\S]*this\.syncDraftFromHex\(normalized\)[\s\S]*this\.draftHex = normalized[\s\S]*this\.emitColor\(normalized\)/.test(colorPicker),
  'AppColorPicker hex input updates the same local HSB draft as grid and slider changes')
ok(/normalizedStrictHexFor\(color: string\)[\s\S]*if \(c\.startsWith\('#'\)\) \{[\s\S]*c = c\.substring\(1\)[\s\S]*c\.length !== 6[\s\S]*this\.isHex\(c\) \? `#\$\{c\.toUpperCase\(\)\}` : ''/.test(colorPicker),
  'manual hex input applies complete RRGGBB values with or without #')
ok(/incoming\.length > 0 && incoming\.toUpperCase\(\) === this\.draftColor\(\)\.toUpperCase\(\)/.test(colorPicker),
  'AppColorPicker does not re-parse its own draft color back through RGB/hex')
ok(/commitDraftColor\(\): void[\s\S]*const color: string = this\.draftColor\(\)[\s\S]*this\.draftHex = color[\s\S]*this\.emitColor\(color\)/.test(colorPicker),
  'slider changes write hex display from HSB draft without re-parsing it')
ok(/if \(delta > 0\) \{[\s\S]*this\.draftHue = hue < 0 \? hue \+ 360 : hue[\s\S]*this\.draftSaturation = \(\(max - min\) \/ max\) \* 100[\s\S]*\}[\s\S]*this\.draftBrightness = max \* 100/.test(colorPicker) &&
  !/max === 0 \? 0 : \(\(max - min\) \/ max\) \* 100/.test(colorPicker),
  'AppColorPicker imports colored hex through HSB without the old max-zero shortcut')
ok(/if \(delta > 0\) \{[\s\S]*this\.draftSaturation = \(\(max - min\) \/ max\) \* 100[\s\S]*\} else \{[\s\S]*this\.draftSaturation = 0[\s\S]*\}[\s\S]*this\.draftBrightness = max \* 100/.test(colorPicker),
  'AppColorPicker imports gray hex colors as saturation 0 instead of keeping the previous color')
ok(!/mytags_color_hue|mytags_color_saturation|mytags_color_value/.test(colorPicker) &&
  !/color_picker_red|color_picker_green|color_picker_blue|RGB/.test(colorPicker),
  'AppColorPicker does not expose RGB controls')
ok(/EditTagSheet\(\)[\s\S]*AppColorPicker\(\{[\s\S]*title: \$r\('app\.string\.mytags_color'\)[\s\S]*color: this\.editColor[\s\S]*this\.editColor = value/.test(page) &&
  /AddTagSheet\(\)[\s\S]*AppColorPicker\(\{[\s\S]*title: \$r\('app\.string\.mytags_color'\)[\s\S]*color: this\.addColor[\s\S]*this\.addColor = value/.test(page),
  'existing-tag and new-tag sheets share the reusable AppColorPicker')
ok(/openEditTag\(t: EhUsertag\)[\s\S]*this\.editColor = t\.defaultColor \? '' : \(t\.colorCode\.length > 0 \? t\.colorCode : t\.color\)/.test(page),
  'existing-tag edit sheet seeds from EhUsertag.colorCode instead of preview border color')
ok(/private tagFillColor\(t: EhUsertag\): ResourceColor[\s\S]*if \(t\.colorCode\.length > 0\) \{[\s\S]*return t\.colorCode/.test(page),
  'MyTags list badge fill uses the same editable colorCode as eros_fe when available')
ok(!/DraftColorPicker|ColorAxisSlider|MYTAGS_COLOR_CHOICES|MYTAGS_COLOR_TARGET/.test(page),
  'MyTagsPage does not keep a page-local color picker implementation')
ok(/editWatched = value[\s\S]*if \(value\) \{[\s\S]*this\.editHidden = false/.test(page) &&
  /editHidden = value[\s\S]*if \(value\) \{[\s\S]*this\.editWatched = false/.test(page),
  'watch and hide draft switches stay mutually exclusive')
ok(/confirmSubmitEdit\(\): void[\s\S]*showAlertDialog[\s\S]*mytags_save_confirm[\s\S]*common_cancel[\s\S]*this\.submitEdit\(\)/.test(page),
  'saving an edit is gated by a native confirmation dialog')
ok(/EhApiPhpService\.setUserTag\([\s\S]*this\.mytags\.apikey[\s\S]*this\.mytags\.apiuid[\s\S]*this\.editTagId[\s\S]*this\.editWatched[\s\S]*this\.editHidden[\s\S]*this\.normalizedEditColor\(\)[\s\S]*this\.editWeight/.test(page),
  'MyTagsPage submits the current draft through setUserTag')
ok(/openEditUserTag\(t: EhUsertag, mytags: EhMytags\): void[\s\S]*this\.editResolvedTags = mytags\.tags[\s\S]*this\.editApiuid = mytags\.apiuid[\s\S]*this\.editApikey = mytags\.apikey/.test(detailTags) &&
  /confirmSubmitEdit\(\): void[\s\S]*const request: UserTagRequestContext \| null = this\.myTagsRequest[\s\S]*this\.submitEdit\(request\)/.test(detailTags) &&
  /submitEdit\(request: UserTagRequestContext\): Promise<void>[\s\S]*EhConstants\.baseUrl\(request\.isEx\)[\s\S]*if \(!this\.isCurrentMyTagsRequest\(request\)\) \{\s*return[\s\S]*this\.applyEditedUserTag\(color\)[\s\S]*UserTagContextService\.publishMyTags\(request, this\.editResolvedTags\)/.test(detailTags) &&
  /canSubmitEdit\(\): boolean[\s\S]*this\.isCurrentMyTagsRequest\(request\)[\s\S]*this\.editResolvedTags\.length > 0/.test(detailTags) &&
  /discardMyTagsManagement\(\): void[\s\S]*this\.editApiuid = ''[\s\S]*this\.editApikey = ''/.test(detailTags),
  'detail-page existing-tag edits retain only resolved credentials and publish through the sheet-session fence')
ok(/TextInput\(\{ text: this\.editWeight[\s\S]*\.type\(InputType\.Normal\)[\s\S]*this\.editWeight = value/.test(page) &&
  /TextInput\(\{ text: this\.addWeight[\s\S]*\.type\(InputType\.Normal\)[\s\S]*this\.addWeight = value/.test(page) &&
  !/TextInput\(\{ text: this\.editWeight[\s\S]*\.type\(InputType\.Number\)/.test(page) &&
  !/TextInput\(\{ text: this\.addWeight[\s\S]*\.type\(InputType\.Number\)/.test(page),
  'MyTags weight inputs preserve signed EH weights instead of using unsigned numeric input')
ok(/await this\.reloadCurrentTagset\(\)/.test(page) &&
  /private publishUserTags\(request: UserTagRequestContext\): void\s*\{\s*UserTagContextService\.publishMyTags\(request, this\.mytags\.tags\)/.test(page),
  'successful save refreshes MyTags and republishes shared colors through the active request fence')
ok(!/actionNewUserTag|actionCreatTagSet|actionRenameTagSet|actionDeleteTagSet/.test(page),
  'this lane does not mix in new/tagset management')
ok(/if \(this\.showingTagsetList\) \{[\s\S]*items\.push\(\{ 'content': createInner \}\)[\s\S]*\} else \{[\s\S]*items\.push\(\{ 'content': addInner \}\)[\s\S]*items\.push\(\{ 'content': renameInner \}\)[\s\S]*\}/.test(page),
  'tagset create action is only in tagset-list menu, not tagset detail menu')

for (const locale of ['base', 'en_US', 'zh_CN', 'ja_JP']) {
  const strings = read(`entry/src/main/resources/${locale}/element/string.json`)
  for (const key of [
    'mytags_edit_title',
    'mytags_watch',
    'mytags_hide',
    'mytags_weight',
    'mytags_default_color',
    'mytags_color',
    'color_picker_grid',
    'color_picker_sliders',
    'color_picker_hue',
    'color_picker_saturation',
    'color_picker_brightness',
    'color_picker_hex',
    'color_picker_favorites',
    'mytags_save',
    'mytags_save_confirm',
    'mytags_save_success',
  ]) {
    ok(strings.includes(`"name": "${key}"`), `${locale}: ${key} string exists`)
  }
}

if (failures > 0) {
  console.error(`\n✗ mytags setusertag contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ mytags setusertag contract passed')
