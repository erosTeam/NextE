#!/usr/bin/env node
/**
 * Contract for the Reader image-save storage boundary.
 *
 * Reader toolbar, slider, thumbnail-strip layout, animation, and copy require device-path validation.
 * This gate protects only current-page resolution, sandbox staging, the system save dialog, and cleanup.
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.cwd()
const read = (p) => readFileSync(join(ROOT, p), 'utf8')
const ok = (cond, msg) => {
  if (!cond) {
    throw new Error(msg)
  }
}

const reader = read('feature/reader/src/main/ets/pages/ReaderPage.ets')
const saver = read('shared/src/main/ets/utils/ImageSaveUtil.ets')
const sharedIndex = read('shared/src/main/ets/Index.ets')

ok(/private saveCurrentImage\(\): void \{\s*this\.saveImagesAtIndexes\(\[this\.vm\.currentIndex\]\)/.test(reader),
  'Reader save action targets the current page')
ok(/private async saveImagesSequential\(indexes: number\[\]\): Promise<void> \{[\s\S]*const alreadyResolvedUrl: string = this\.currentDisplayUrl\(image\)[\s\S]*this\.resolveCurrentDisplayUrl\(image\)[\s\S]*this\.saveImageUrl\(imageUrl, title\)/.test(reader),
  'Reader saves the displayed source or resolves it through the Reader image pipeline')
ok(/private saveImageUrl\(url: string, title: string\): Promise<void> \{[\s\S]*ImageSaveUtil\.saveNetworkImageToGallery\(this\.hostContext\(\), url, title\)/.test(reader),
  'Reader delegates media writes to ImageSaveUtil')

ok(/import \{ fileIo \} from '@kit\.CoreFileKit'/.test(saver),
  'ImageSaveUtil uses fileIo to copy the selected image into the Photos destination URI')
ok(/import \{ photoAccessHelper \} from '@kit\.MediaLibraryKit'/.test(saver),
  'ImageSaveUtil uses MediaLibraryKit')
ok(/EhHttpClient\.getInstance\(\)\.downloadBinaryToFile\(url, filePath\)/.test(saver),
  'ImageSaveUtil downloads the selected image into app sandbox')
ok(/const srcFileUri: string = filePath/.test(saver),
  'ImageSaveUtil passes the sandbox file path to the system save dialog')
ok(/PhotoCreationConfig/.test(saver) && /PhotoType\.IMAGE/.test(saver),
  'ImageSaveUtil creates image metadata for the system save dialog')
ok(/helper\.showAssetsCreationDialog\(\[srcFileUri\], \[config\]\)/.test(saver),
  'ImageSaveUtil uses the system photo-creation dialog instead of a direct privileged write')
ok(/fileIo\.open\(filePath, fileIo\.OpenMode\.READ_ONLY\)/.test(saver) &&
    /fileIo\.open\(destUris\[0\], fileIo\.OpenMode\.WRITE_ONLY\)/.test(saver) &&
    /fileIo\.copyFile\(srcFile\.fd, destFile\.fd\)/.test(saver),
  'ImageSaveUtil copies the sandbox file into the destination URI returned by the dialog')
ok(/finally \{[\s\S]*ImageSaveUtil\.removeTempFile\(filePath\)[\s\S]*\}/.test(saver),
  'ImageSaveUtil removes the temporary downloaded file after save, cancel, or failure')
ok(!/helper\.applyChanges\(request\)/.test(saver),
  'ImageSaveUtil does not attempt direct media-library writes without a permission surface')
ok(/export \{ ImageSaveUtil \} from '\.\/utils\/ImageSaveUtil'/.test(sharedIndex),
  'shared module exports ImageSaveUtil')

console.log('✓ Reader image-save contract: source resolution and system-save boundaries locked')
