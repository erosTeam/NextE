#!/usr/bin/env node
/**
 * Contract: no EH session credentials or dev-session bootstrap can reach source control or HAPs.
 *
 * `.gitignore` only prevents commits; Harmony rawfiles are still bundled into HAPs when present
 * under app resources. Login must come from the in-app WebView flow or persisted Preferences,
 * never from a bundled credential resource.
 *
 * Run: node scripts/test_secret_safety_contract.mjs
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const errors = []

function rel(p) {
  return relative(ROOT, p).replace(/\\/g, '/')
}

function walk(dir, out, options = {}) {
  let entries
  try {
    entries = readdirSync(dir)
  } catch {
    return out
  }
  for (const name of entries) {
    const p = join(dir, name)
    let s
    try {
      s = statSync(p)
    } catch {
      continue
    }
    if (s.isDirectory()) {
      if (options.skipDirs?.has(name)) continue
      walk(p, out, options)
    } else {
      out.push(p)
    }
  }
  return out
}

function command(args, opts = {}) {
  try {
    return execFileSync(args[0], args.slice(1), { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts })
  } catch (e) {
    return e.stdout?.toString() ?? ''
  }
}

const appFiles = []
for (const d of ['entry', 'feature', 'shared']) {
  walk(join(ROOT, d), appFiles, { skipDirs: new Set(['build', 'oh_modules', 'node_modules']) })
}
const forbiddenSourcePatterns = [
  { name: 'legacy session injector method', re: /\binjectDevSession\b/ },
  { name: 'bundled credential rawfile read', re: /getRawFileContentSync\s*\(\s*['"]dev_session\.txt['"]\s*\)/ },
  { name: 'legacy injection diagnostic', re: /dev_session_injected/ },
]
for (const f of appFiles) {
  if (!/\.(ets|ts|js|mjs|json5?|xml)$/.test(f)) continue
  const text = readFileSync(f, 'utf8')
  for (const p of forbiddenSourcePatterns) {
    if (p.re.test(text)) errors.push(`${rel(f)} contains forbidden app-source token: ${p.name}`)
  }
}

const rawfile = join(ROOT, 'entry/src/main/resources/rawfile/dev_session.txt')
if (existsSync(rawfile)) {
  const size = statSync(rawfile).size
  errors.push(`${rel(rawfile)} exists (${size} bytes). Remove/quarantine it before building; ignored files still package into HAPs.`)
}

const buildRoot = join(ROOT, 'entry/build')
if (existsSync(buildRoot)) {
  const buildFiles = walk(buildRoot, [], { skipDirs: new Set(['oh_modules', 'node_modules']) })
  for (const f of buildFiles) {
    const r = rel(f)
    if (/resources\/rawfile\/dev_session\.txt$/.test(r)) errors.push(`${r} exists in build output/intermediates`)
  }
}

const packageFiles = []
walk(ROOT, packageFiles, { skipDirs: new Set(['.git', 'oh_modules', 'node_modules', '.hvigor']) })
for (const f of packageFiles) {
  if (!/\.(hap|app|apk|aab|zip)$/i.test(f)) continue
  const listing = command(['unzip', '-l', f])
  if (/resources\/rawfile\/dev_session\.txt/.test(listing)) errors.push(`${rel(f)} packages resources/rawfile/dev_session.txt`)
}

const tracked = command(['git', 'ls-files', '-z']).split('\0').filter(Boolean)
for (const p of tracked) {
  const lower = p.toLowerCase()
  const isAllowedSample = lower.endsWith('.sample') || lower.endsWith('.example')
  if (isAllowedSample) continue
  if (
    lower.endsWith('/dev_session.txt') ||
    lower === '.env.local' ||
    lower === 'scripts/dev.env' ||
    /\.(hap|app|apk|aab|p12|jks|keystore|pem|key)$/i.test(lower)
  ) {
    errors.push(`tracked forbidden path: ${p}`)
  }
}

const publicDocPatterns = [
  { name: 'legacy dev-session wording', re: /dev[_-]session/i },
  { name: 'legacy injector symbol', re: /injectDevSession|getRawFileContentSync\s*\(\s*['"]dev_session\.txt['"]\s*\)/ },
  { name: 'account-specific logged-in id', re: /logged-in\s*\(ID\s*\d+/i },
  { name: 'real account data claim', re: /real account data/i },
]
const publicTextExt = /\.(md|txt|json|json5|yaml|yml)$/i
const excludedText = new Set(['scripts/test_secret_safety_contract.mjs'])
for (const p of tracked) {
  if (!publicTextExt.test(p) || excludedText.has(p)) continue
  const full = join(ROOT, p)
  if (!existsSync(full)) continue
  const text = readFileSync(full, 'utf8')
  for (const pat of publicDocPatterns) {
    if (pat.re.test(text)) errors.push(`${p} contains forbidden public-history marker: ${pat.name}`)
  }
}

const stagedPatch = command(['git', 'diff', '--cached', '--unified=0', '--', ':!scripts/test_cookiejar_contract.mjs'])
const addedLines = stagedPatch.split('\n').filter((l) => l.startsWith('+') && !l.startsWith('+++'))
const cookiePatterns = [
  /ipb_pass_hash\s*=\s*[A-Za-z0-9_-]{12,}/,
  /ipb_member_id\s*=\s*\d{2,}/,
  /igneous\s*=\s*[A-Za-z0-9_-]{8,}/,
  /Cookie\s*:\s*[^\n]*(ipb_member_id\s*=|ipb_pass_hash\s*=|igneous\s*=)/i,
]
for (const line of addedLines) {
  if (cookiePatterns.some((re) => re.test(line))) {
    errors.push('staged diff adds EH cookie-looking material (redacted by gate)')
    break
  }
}

if (errors.length > 0) {
  console.error(`✗ secret safety contract: ${errors.length} issue(s)`)
  for (const e of errors) console.error('  ' + e)
  process.exit(1)
}

console.log('✓ secret safety contract: no bundled session injection, no packaged credential rawfile, no public-history markers')
