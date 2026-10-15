#!/usr/bin/env node
/**
 * Contract: AppScope/app.json5 versionName is the single release version source.
 * The root and every host module (entry, feature/*, shared) oh-package.json5
 * version must equal it, and build-profile.json5 modules[] exactly matches the
 * on-disk feature/* + shared + entry set (no orphan module dir, no unregistered
 * module). Cheap structural guard so the monorepo can't silently drift.
 *
 * third_party/* keeps its own library version and is exempt.
 *
 * Run: node scripts/test_version_consistency_contract.mjs
 */
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

// minimal JSON5 reader: strip // and /* */ comments + trailing commas, then JSON.parse
function readJson5(p) {
  let s = readFileSync(p, 'utf8')
  s = s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1')
  s = s.replace(/,(\s*[}\]])/g, '$1')
  return JSON.parse(s)
}

const errors = []
const buildProfile = readJson5(join(ROOT, 'build-profile.json5'))
const registered = buildProfile.modules.map((m) => m.srcPath.replace(/^\.\//, ''))

// 0) release version consistency: app.json5 is the single source of truth.
const appJson = readJson5(join(ROOT, 'AppScope', 'app.json5'))
const appVersion = appJson.app?.versionName
if (typeof appVersion !== 'string' || !/^\d+\.\d+\.\d+$/.test(appVersion)) {
  errors.push('AppScope/app.json5 app.versionName must be X.Y.Z')
} else {
  const rootPkg = readJson5(join(ROOT, 'oh-package.json5'))
  if (rootPkg.version !== appVersion) {
    errors.push(`oh-package.json5 version ${rootPkg.version} != app.json5 versionName ${appVersion}`)
  }
  for (const m of buildProfile.modules) {
    if (m.srcPath.startsWith('./third_party')) continue
    const pkgPath = join(ROOT, m.srcPath, 'oh-package.json5')
    if (existsSync(pkgPath)) {
      const pkg = readJson5(pkgPath)
      if (pkg.version !== appVersion) {
        errors.push(`${m.srcPath}/oh-package.json5 version ${pkg.version} != app.json5 versionName ${appVersion}`)
      }
    }
  }
  const npmPackagePath = join(ROOT, 'package.json')
  if (existsSync(npmPackagePath) && readJson5(npmPackagePath).version !== appVersion) {
    errors.push('package.json version does not match app.versionName')
  }
  if (!existsSync(join(ROOT, `changelog/v${appVersion}.md`)) ||
      readFileSync(join(ROOT, `changelog/v${appVersion}.md`), 'utf8').trim().length === 0) {
    errors.push(`changelog/v${appVersion}.md must exist and be non-empty`)
  }
  const releaseRef = process.env.GITHUB_REF ?? ''
  if (releaseRef.startsWith('refs/tags/') && releaseRef !== `refs/tags/v${appVersion}`) {
    errors.push(`release tag ${releaseRef} does not match v${appVersion}`)
  }
}
if (!Number.isSafeInteger(appJson.app?.versionCode) || appJson.app.versionCode <= 0) {
  errors.push('AppScope/app.json5 app.versionCode must be a positive integer')
}

// 1) every registered module dir exists with an oh-package.json5
for (const m of buildProfile.modules) {
  const dir = join(ROOT, m.srcPath)
  if (!existsSync(join(dir, 'oh-package.json5'))) {
    errors.push(`registered module '${m.name}' has no oh-package.json5 at ${m.srcPath}`)
  }
  if (!existsSync(join(dir, 'src/main/module.json5'))) {
    errors.push(`registered module '${m.name}' has no src/main/module.json5`)
  }
}

// 2) every feature/* dir is registered
if (existsSync(join(ROOT, 'feature'))) {
  for (const d of readdirSync(join(ROOT, 'feature'))) {
    const rel = `feature/${d}`
    if (!registered.includes(rel)) {
      errors.push(`feature dir '${rel}' is not registered in build-profile.json5 modules[]`)
    }
  }
}

if (errors.length > 0) {
  console.error('✗ version/module consistency: ' + errors.length + ' issue(s)')
  for (const e of errors) console.error('  ' + e)
  process.exit(1)
}
console.log('✓ version/module consistency: ' + buildProfile.modules.length + ' modules registered & present')
