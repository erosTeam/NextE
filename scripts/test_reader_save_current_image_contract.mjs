#!/usr/bin/env node
/**
 * Contract: the reader has a real current-image save action, not a placeholder button.
 *
 * FE grounding:
 * - eros_fe Reader ControllerButtonBar exposes Save.
 * - tapSave resolves the current GalleryImage and saves either local file or network/original image
 *   into the photo album.
 *
 * NextE policy:
 * - Expose save as a neutral reader toolbar icon, not a primary filled control.
 * - Resolve the current reader image through the same /s/ -> full-image chain when needed.
 * - Save by downloading to app sandbox and invoking the system save-creation dialog.
 *
 * Run: node scripts/test_reader_save_current_image_contract.mjs
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
let failures = 0
const ok = (cond, msg) => {
  if (!cond) {
    console.error(`✗ ${msg}`)
    failures++
  }
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const saver = read('shared/src/main/ets/utils/ImageSaveUtil.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')
const thumbStripMatch = reader.match(/ReaderThumbStrip\(\) \{[\s\S]*?\n  \}/)
const thumbStrip = thumbStripMatch ? thumbStripMatch[0] : ''

ok(!/SaveButton\(/.test(reader),
  'Reader chrome does not expose SaveButton because it renders a primary filled control')
ok(/SymbolGlyph\(\$r\('sys\.symbol\.arrow_down_to_line'\)\)[\s\S]*this\.saveCurrentImage\(\)/.test(reader),
  'Reader save is a neutral toolbar icon that calls saveCurrentImage')
ok(/READER_CHROME_ACTION_SIZE: number = 44/.test(reader) &&
    /READER_CHROME_ICON_SIZE: number = 22/.test(reader),
  'Reader chrome actions use one consistent 44vp/22vp toolbar size')
ok(/Text\(`\$\{this\.sliderPreview >= 0 \? this\.sliderPreview : this\.sliderValue\}`\)/.test(reader) &&
    /Text\(`\$\{this\.vm\.totalPages\(\)\}`\)/.test(reader),
  'Reader slider keeps visible current and total page numbers')
ok(/toggleThumbStrip\(\): void[\s\S]*animateTo/.test(reader) &&
    /this\.showThumbStrip = !this\.showThumbStrip/.test(reader),
  'Reader thumbnail strip open/close is animated')
ok(/List\(\{ initialIndex: this\.vm\.currentIndex, scroller: this\.thumbScroller/.test(reader) &&
    /this\.thumbScroller\.scrollToIndex\(index, animated\)/.test(reader),
  'Reader thumbnail strip has a scroller that follows the current page')
ok(/this\.thumbPageIndexes\(\)/.test(reader) &&
    /const total: number = this\.vm\.totalPages\(\)/.test(reader),
  'Reader thumbnail strip is built from total page count, not only loaded images')
ok(!/ForEach\(\s*this\.vm\.images/.test(thumbStrip),
  'Reader thumbnail strip is not limited to the currently loaded image array')
ok(/private saveCurrentImage\(\): void/.test(reader), 'Reader owns a current-image save action')
ok(/image\.originImageUrl\.length > 0 \? image\.originImageUrl : image\.imageUrl/.test(reader),
  'save action prefers originImageUrl before imageUrl')
ok(/ImageResolveService\.getInstance\(\)\s*\.\s*resolve\(image\)/.test(reader),
  'save action resolves an unresolved current image before saving')
ok(/ImageSaveUtil\.saveNetworkImageToGallery\(this\.hostContext\(\), url, title\)/.test(reader),
  'Reader delegates the media write to ImageSaveUtil')
ok(/reader_save_success/.test(reader) && /reader_save_failed/.test(reader),
  'Reader surfaces save success and failure feedback')

ok(/import \{ fileIo \} from '@kit\.CoreFileKit'/.test(saver),
  'ImageSaveUtil uses fileIo to copy the selected image into the Photos destination URI')
ok(/import \{ photoAccessHelper \} from '@kit\.MediaLibraryKit'/.test(saver),
  'ImageSaveUtil uses MediaLibraryKit')
ok(/EhHttpClient\.getInstance\(\)\.downloadBinaryToFile\(url, filePath\)/.test(saver),
  'ImageSaveUtil downloads the selected image into app sandbox')
ok(/const srcFileUri: string = filePath/.test(saver),
  'ImageSaveUtil passes the sandbox file path to the system save dialog, matching the verified V2Next path')
ok(/PhotoCreationConfig/.test(saver) && /PhotoType\.IMAGE/.test(saver),
  'ImageSaveUtil creates image save metadata for the system save dialog')
ok(/helper\.showAssetsCreationDialog\(\[srcFileUri\], \[config\]\)/.test(saver),
  'ImageSaveUtil saves through the system photo creation dialog instead of a direct privileged write')
ok(/fileIo\.open\(filePath, fileIo\.OpenMode\.READ_ONLY\)/.test(saver) &&
    /fileIo\.open\(destUris\[0\], fileIo\.OpenMode\.WRITE_ONLY\)/.test(saver) &&
    /fileIo\.copyFile\(srcFile\.fd, destFile\.fd\)/.test(saver),
  'ImageSaveUtil copies the downloaded sandbox file into the destination URI returned by the dialog')
ok(/finally \{[\s\S]*ImageSaveUtil\.removeTempFile\(filePath\)[\s\S]*\}/.test(saver),
  'ImageSaveUtil removes the temporary downloaded file after save, cancel, or failure')
ok(!/helper\.applyChanges\(request\)/.test(saver),
  'ImageSaveUtil does not attempt direct media-library writes without a permission surface')
ok(/export \{ ImageSaveUtil \} from '\.\/utils\/ImageSaveUtil'/.test(sharedIndex),
  'shared module exports ImageSaveUtil')

if (failures > 0) {
  console.error(`\n✗ reader save-current-image contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader save-current-image contract: 22 assertions passed')
