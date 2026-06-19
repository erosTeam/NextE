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
 * - Use HarmonyOS SaveButton for short-term media-library authorization.
 * - Resolve the current reader image through the same /s/ -> full-image chain when needed.
 * - Save by downloading to app sandbox and committing through MediaLibraryKit.
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

ok(/SaveButton\(\{[\s\S]*SaveIconStyle\.LINES[\s\S]*ButtonType\.Circle/.test(reader),
  'Reader uses a compact HarmonyOS SaveButton instead of a plain placeholder button')
ok(/SaveButtonOnClickResult\.SUCCESS/.test(reader) && /this\.saveCurrentImage\(\)/.test(reader),
  'SaveButton authorization success calls saveCurrentImage')
ok(/private saveCurrentImage\(\): void/.test(reader), 'Reader owns a current-image save action')
ok(/image\.originImageUrl\.length > 0 \? image\.originImageUrl : image\.imageUrl/.test(reader),
  'save action prefers originImageUrl before imageUrl')
ok(/ImageResolveService\.getInstance\(\)\s*\.\s*resolve\(image\)/.test(reader),
  'save action resolves an unresolved current image before saving')
ok(/ImageSaveUtil\.saveNetworkImageToGallery\(this\.hostContext\(\), url, title\)/.test(reader),
  'Reader delegates the media write to ImageSaveUtil')
ok(/reader_save_success/.test(reader) && /reader_save_failed/.test(reader),
  'Reader surfaces save success and failure feedback')

ok(/import \{ fileUri \} from '@kit\.CoreFileKit'/.test(saver),
  'ImageSaveUtil converts sandbox paths with fileUri')
ok(/import \{ photoAccessHelper \} from '@kit\.MediaLibraryKit'/.test(saver),
  'ImageSaveUtil uses MediaLibraryKit')
ok(/EhHttpClient\.getInstance\(\)\.downloadBinaryToFile\(url, filePath\)/.test(saver),
  'ImageSaveUtil downloads the selected image into app sandbox')
ok(/fileUri\.getUriFromPath\(filePath\)/.test(saver),
  'ImageSaveUtil converts the sandbox file path to a file URI')
ok(/MediaAssetChangeRequest\.createImageAssetRequest\(context, uri\)/.test(saver),
  'ImageSaveUtil creates an image asset request from the sandbox URI')
ok(/helper\.applyChanges\(request\)/.test(saver),
  'ImageSaveUtil commits the image asset to the media library')
ok(/export \{ ImageSaveUtil \} from '\.\/utils\/ImageSaveUtil'/.test(sharedIndex),
  'shared module exports ImageSaveUtil')

if (failures > 0) {
  console.error(`\n✗ reader save-current-image contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ reader save-current-image contract: 14 assertions passed')
