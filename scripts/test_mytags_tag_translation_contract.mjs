#!/usr/bin/env node
/**
 * Contract: My Tags management UI uses the local tag-translation database for
 * display and add-tag candidates, while EH writes still submit raw namespace:key.
 */
import assert from 'node:assert'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const page = readFileSync(join(ROOT, 'feature/user/src/main/ets/pages/MyTagsPage.ets'), 'utf8')

let passed = 0
const ok = (name, cond) => {
  assert.ok(cond, name)
  passed++
}

ok('MyTagsPage observes the global tag translation setting',
  /TagTranslationSettingsState/.test(page) &&
  /connectTagTranslationSettings/.test(page) &&
  /@Local tagTranslation: TagTranslationSettingsState = connectTagTranslationSettings\(\)/.test(page) &&
  /@Monitor\('tagTranslation\.enabled'\)[\s\S]*onTagTranslationChange\(\)/.test(page))
ok('loaded MyTags rows are retranslated through the RDB-backed async service',
  /if \(this\.tagTranslation\.enabled\) \{[\s\S]*await this\.translateLoadedMyTags\(epoch\)/.test(page) &&
  /translateLoadedMyTags\(epoch: number\): Promise<void>[\s\S]*TagTranslationService\.translateFullTagAsync\(this\.ctx\(\), copy\.tag\)/.test(page) &&
  /this\.mytags = this\.copyMytagsWithTags\(source, tags\)/.test(page))
ok('MyTags display uses localized title only when the setting is enabled',
  /localizedTagLabel\(t: EhUsertag\): string[\s\S]*if \(!this\.tagTranslation\.enabled\) \{[\s\S]*return ''/.test(page) &&
  /tagTitle\(t: EhUsertag\): string[\s\S]*const localized: string = this\.localizedTagLabel\(t\)[\s\S]*return this\.localizedFullTagDisplay\(t\.tag, localized\)[\s\S]*return t\.tag/.test(page) &&
  /tagSubtitle\(t: EhUsertag\): string[\s\S]*const localized: string = this\.localizedTagLabel\(t\)[\s\S]*return t\.tag/.test(page) &&
  /localizedFullTagDisplay\(fullTag: string, localized: string\): string[\s\S]*const label: string = this\.localizedNamespaceLabel\(namespace\)[\s\S]*return label\.length > 0 \? `\$\{label\}:\$\{text\}` : text/.test(page) &&
  /localizedNamespaceLabel\(namespace: string\): string[\s\S]*case 'artist':[\s\S]*AppStrings\.get\('tag_ns_artist'\)[\s\S]*case 'female':[\s\S]*AppStrings\.get\('tag_ns_female'\)/.test(page) &&
  !/localizedFullTagDisplay\(fullTag: string, localized: string\): string[\s\S]*EhConstants\.localizedTagDisplay/.test(page))
ok('existing-tag edit sheet shows localized namespaced label but keeps raw tag identity',
  /openEditTag\(t: EhUsertag\)[\s\S]*this\.editTagTitle = t\.tag[\s\S]*this\.editTagDisplay = this\.tagTitle\(t\)[\s\S]*this\.editTagTranslate = this\.tagSubtitle\(t\)/.test(page) &&
  /EditTagSheet\(\)[\s\S]*Text\(this\.editTagDisplay\.length > 0 \? this\.editTagDisplay : this\.editTagTitle\)[\s\S]*if \(this\.editTagTranslate\.length > 0\) \{[\s\S]*Text\(this\.editTagTranslate\)/.test(page) &&
  !/Text\(this\.editTagTitle\)\s*\.fontSize\(ThemeConstants\.FONT_SIZE_CAPTION\)/.test(page))
ok('add-tag input and suggestions prefer local translations before EH tagsuggest',
  /loadAddTagTranslation\(this\.addTagName, epoch\)/.test(page) &&
  /loadAddTagTranslation\(value: string, epoch: number\): Promise<void>[\s\S]*TagTranslationService\.translateFullTagAsync\(this\.ctx\(\), tag\)[\s\S]*this\.addTagTranslate = this\.localizedFullTagDisplay\(tag, translated\)/.test(page) &&
  /if \(this\.tagTranslation\.enabled\) \{[\s\S]*TagTranslationService\.searchSuggestions\(this\.ctx\(\), q, 30\)[\s\S]*localSuggestions\.length > 0[\s\S]*return[\s\S]*EhApiPhpService\.tagSuggest/.test(page))
ok('add-tag suggestion rows show localized names but select raw namespace:key labels',
  /Text\(s\.displayName\.length > 0 \? s\.displayName : s\.text\)/.test(page) &&
  /if \(s\.displayName\.length > 0\) \{[\s\S]*Text\(s\.text\)/.test(page) &&
  /selectAddSuggestion\(s: EhTagSuggestion\)[\s\S]*const label: string = s\.label\(\)[\s\S]*this\.addTagQuery = label[\s\S]*this\.addTagName = label[\s\S]*this\.addTagTranslate = this\.localizedFullTagDisplay\(label, s\.displayName\)/.test(page))
ok('MyTags writes still submit raw EH tag names, not localized display labels',
  /submitAdd\(\): Promise<void>[\s\S]*tagName: this\.addTagLabel\(\)/.test(page) &&
  /submitEdit\(\): Promise<void>[\s\S]*this\.editTagId/.test(page) &&
  !/tagName: this\.addTagTranslate/.test(page))

console.log(`✓ mytags tag translation contract: ${passed} assertions passed`)
