#!/usr/bin/env node
/**
 * Contract: diagnostics is a real redacted local logging/export system, not a transient HiLog wrapper.
 *
 * Run: node scripts/test_diagnostics_logger_contract.mjs
 */
import { existsSync, readFileSync } from 'node:fs'
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

const requiredFiles = [
  'shared/src/main/ets/diagnostics/DiagnosticsRedactor.ets',
  'shared/src/main/ets/diagnostics/DiagnosticsLogFormatter.ets',
  'shared/src/main/ets/diagnostics/DiagnosticsStore.ets',
  'shared/src/main/ets/diagnostics/DiagnosticsLogFileSink.ets',
  'shared/src/main/ets/diagnostics/DiagnosticLogger.ets',
  'shared/src/main/ets/settings/DiagnosticsSettings.ets',
  'shared/src/main/ets/settings/DiagnosticsFileExport.ets',
  'shared/src/main/ets/state/DiagnosticsState.ets',
]
for (const file of requiredFiles) {
  ok(existsSync(join(ROOT, file)), `${file} exists`)
}

const logger = read('shared/src/main/ets/diagnostics/DiagnosticLogger.ets')
ok(/initializePersistentSink\(context: common\.UIAbilityContext\)/.test(logger), 'logger initializes persistent sink')
ok(/DiagnosticsStore\.append\(entry\)/.test(logger), 'logger writes memory ring')
ok(/DiagnosticsLogFileSink\.append\(entry\)/.test(logger), 'logger writes file sink')
ok(/DiagnosticsRedactor\.sanitizeEvent/.test(logger), 'logger redacts before sinks')
ok(/hilog\.(debug|info|warn|error)/.test(logger), 'logger still mirrors to native HiLog')

const redactor = read('shared/src/main/ets/diagnostics/DiagnosticsRedactor.ets')
for (const token of ['Cookie', 'Authorization', 'Bearer', 'igneous', 'ipb_pass_hash', 'api[_-]?key', 'content_rendered']) {
  ok(redactor.includes(token), `redactor handles ${token}`)
}

const fileSink = read('shared/src/main/ets/diagnostics/DiagnosticsLogFileSink.ets')
ok(/nexte-log-/.test(fileSink), 'file sink uses NextE log prefix')
ok(/DIAGNOSTICS_LOG_KEEP_COUNT/.test(fileSink) && /DIAGNOSTICS_LOG_MAX_AGE_DAYS/.test(fileSink),
  'file sink retains bounded local logs')
ok(/fileUri\.getUriFromPath/.test(fileSink), 'file sink exposes shareable file URI')
ok(/isDiagnosticsLogFileName/.test(fileSink), 'file sink validates retained log file names')

const settings = read('shared/src/main/ets/settings/DiagnosticsSettings.ets')
ok(/DIAGNOSTICS_ENABLED/.test(settings) && /DIAGNOSTICS_MIN_LEVEL/.test(settings),
  'diagnostics settings persist enabled/min-level')
ok(/DiagnosticLogger\.configure/.test(settings), 'settings configure logger')

const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets')
ok(/DiagnosticLogger\.initializePersistentSink\(this\.context\)/.test(entryAbility),
  'EntryAbility opens persistent diagnostics sink at startup')
ok(/DiagnosticLogger\.closePersistentSink\(\)/.test(entryAbility),
  'EntryAbility closes/prunes diagnostics sink at shutdown')

const sharedIndex = read('shared/src/main/ets/Index.ets')
ok(/DiagnosticsLogFileSink/.test(sharedIndex) && /DiagnosticsFileExport/.test(sharedIndex) && /connectDiagnostics/.test(sharedIndex),
  'shared barrel exports diagnostics system')

const favoritesVm = read('feature/user/src/main/ets/viewmodel/FavoritesViewModel.ets')
ok(/loadmore_start/.test(favoritesVm) && /loadmore_done/.test(favoritesVm) && /loadmore_failed/.test(favoritesVm),
  'favorites pagination records request, result, and failure diagnostics')
ok(/cursorHash=/.test(favoritesVm) && /nextHash=/.test(favoritesVm),
  'favorites pagination logs cursor hashes instead of raw paging tokens')

const commentTranslation = read('shared/src/main/ets/services/CommentTranslationService.ets')
ok(/comment_translate_start/.test(commentTranslation) && /comment_translate_done/.test(commentTranslation),
  'comment translation records request lifecycle diagnostics')
ok(/comment_llm_start/.test(commentTranslation) && /comment_google_start/.test(commentTranslation),
  'comment translation records provider selection diagnostics')

const imageCache = read('shared/src/main/ets/services/CachedImageFileService.ets')
ok(/urlHash=/.test(imageCache) && /cacheKeyHash=/.test(imageCache),
  'image cache diagnostics use hashes for image identity')
ok(!/DiagnosticLogger\.[^\n]+displayUri/.test(imageCache) && !/-> \$\{[^}]*displayUri/.test(imageCache),
  'image cache diagnostics do not export local displayUri paths')

if (failures > 0) {
  console.error(`\n✗ diagnostics logger contract: ${failures} failure(s)`)
  process.exit(1)
}

console.log('✓ diagnostics logger contract: redacted local diagnostics and bounded retained files locked')
