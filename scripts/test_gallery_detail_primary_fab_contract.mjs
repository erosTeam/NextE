#!/usr/bin/env node
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

const detail = read('feature/gallery/src/main/ets/pages/GalleryDetailPage.ets')
const header = read('feature/gallery/src/main/ets/components/GalleryHeaderCard.ets')

ok(/private readFabLabel\(\): ResourceStr/.test(detail), 'GalleryDetailPage owns the read/resume label')
ok(/detail_read_resume/.test(detail), 'detail FAB preserves resume label')
ok(/detail_read/.test(detail), 'detail FAB preserves first-read label')
ok(/Button\(\{ type: ButtonType\.Capsule \}\)[\s\S]*this\.readFabLabel\(\)/.test(detail), 'detail page renders a capsule read FAB')
ok(/SymbolGlyph\(\$r\('sys\.symbol\.doc_plaintext'\)\)[\s\S]*fontColor\(\[ThemeConstants\.TEXT_ON_BRAND\]\)/.test(detail), 'detail FAB icon uses readable on-brand color')
ok(/Text\(this\.readFabLabel\(\)\)[\s\S]*fontColor\(ThemeConstants\.TEXT_ON_BRAND\)/.test(detail), 'detail FAB label uses readable on-brand color')
ok(/position\(\{\s*left:\s*0,\s*bottom:\s*ThemeConstants\.SPACE_LG\s*\}\)/.test(detail), 'read FAB uses a page-level bottom rail')
ok(/translate\(\{ x: this\.readFabVisualX\(\) \}\)/.test(detail), 'read FAB aligns to the resolved hand edge')
ok(/opacity\(this\.readFabLayoutReady \? 1 : 0\)/.test(detail), 'read FAB is hidden until its final measured position is known')
ok(/onClick\(\(\) => \{\s*this\.openReader\(this\.resumeIndex\(\)\)\s*\}\)/.test(detail), 'read FAB opens Reader at current resume index')
ok(/bottomPadding:\s*ThemeConstants\.SPACE_XXL\s*\+\s*ThemeConstants\.BUTTON_HEIGHT/.test(detail), 'detail list reserves space for the read FAB')

ok(!/@Event onRead/.test(header), 'GalleryHeaderCard no longer exposes a read event')
ok(!/readLabel\(\)/.test(header), 'GalleryHeaderCard no longer owns read label state')
ok(!/detail_read/.test(header), 'GalleryHeaderCard no longer renders read/resume strings')
ok(!/Button\(this\.readLabel\(\)\)/.test(header), 'GalleryHeaderCard no longer renders the read capsule')

if (failures > 0) {
  console.error(`\n✗ gallery detail primary FAB contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('\n✓ gallery detail primary FAB contract passed')
