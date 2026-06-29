#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
const DEFAULT_TARGET = '192.168.50.197:12345'
const DEFAULT_BUNDLE = 'com.erosteam.nexte'
const DEFAULT_ABILITY = 'EntryAbility'
const DEFAULT_HAP = 'entry/build/default/outputs/default/entry-default-signed.hap'
const DETAIL_QA_URI = 'nexte://qa/image-block-seed'
const READER_QA_URI = 'nexte://qa/image-block-seed-reader'
const SUBSCRIPTION_READER_QA_URI = 'nexte://qa/image-block-subscription-reader'
const READER_OPEN_QA_URI = 'nexte://qa/image-block-reader-open'
const MANUAL_READER_QA_URI = 'nexte://qa/image-block-manual-reader'
const SETTINGS_QA_URI = 'nexte://qa/image-block-settings'
const SETTINGS_OPEN_QA_URI = 'nexte://qa/image-block-settings-open'
const SETTINGS_EDGE_QA_URI = 'nexte://qa/image-block-settings-edge'
const SETTINGS_REFRESH_QA_URI = 'nexte://qa/image-block-settings-refresh'
const PHYSICAL_TARGET = '192.168.50.197:12345'
const MANUAL_MARK_LABELS = ['屏蔽当前图片', 'Block current image', '現在の画像をブロック']
const UPDATE_RULES_LABELS = ['更新社区规则', 'Update community rules', 'コミュニティルールを更新']
const DELETE_LABELS = ['删除', 'Delete', '削除']
const LOCAL_RULE_SECTION_LABELS = ['本地手动屏蔽', 'Manual block rules', '手動ブロック']
const WHITELIST_SECTION_LABELS = ['误杀放行图片', 'Allowed images', '許可した画像']
const WHITELIST_ROW_TITLE_LABELS = ['已放行图片', 'Allowed image', '許可済み画像']
const CONTRIBUTION_DRAFT_LABELS = ['复制社区规则草稿', 'Copy community draft', 'コミュニティ下書きをコピー']
const IMAGE_BLOCK_TITLE_LABELS = ['图片屏蔽', 'Image blocks', '画像ブロック']
const SUBSCRIPTION_PROVIDER_LABELS = ['Chinese scanlator ads']

function argValue(name, fallback) {
  const index = process.argv.indexOf(name)
  if (index >= 0 && process.argv[index + 1] && !process.argv[index + 1].startsWith('--')) {
    return process.argv[index + 1]
  }
  return fallback
}

function hasFlag(name) {
  return process.argv.includes(name)
}

function nowStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, 'Z')
}

const hdc = argValue('--hdc', process.env.HDC || DEFAULT_HDC)
const target = argValue('--target', process.env.TARGET || DEFAULT_TARGET)
const bundle = argValue('--bundle', process.env.BUNDLE || DEFAULT_BUNDLE)
const ability = argValue('--ability', process.env.ABILITY || DEFAULT_ABILITY)
const hap = argValue('--hap', process.env.HAP || join(ROOT, DEFAULT_HAP))
const artifactDir = argValue('--artifact-dir', join(ROOT, '.hvigor', 'outputs', `image-block-seeded-reader-${nowStamp()}`))
const install = !hasFlag('--no-install')
const viaDetail = hasFlag('--via-detail')
const settingsEdgeMode = hasFlag('--settings-edge')
const settingsRefreshMode = hasFlag('--settings-refresh')
const settingsMode = hasFlag('--settings') || settingsEdgeMode || settingsRefreshMode
const manualMark = hasFlag('--manual-mark')
const subscriptionMode = hasFlag('--subscription')
const verifySettingsAfterMark = hasFlag('--verify-settings-after-mark')
const defaultQaUri = manualMark
  ? MANUAL_READER_QA_URI
  : (subscriptionMode
    ? SUBSCRIPTION_READER_QA_URI
    : (settingsRefreshMode
      ? SETTINGS_REFRESH_QA_URI
      : (settingsEdgeMode ? SETTINGS_EDGE_QA_URI : (settingsMode ? SETTINGS_QA_URI : (viaDetail ? DETAIL_QA_URI : READER_QA_URI)))))
const qaUri = argValue('--qa-uri', process.env.QA_URI || defaultQaUri)
const clickRead = viaDetail && !hasFlag('--no-click-read')
const verifySettingsAfterAllow = hasFlag('--verify-settings-after-allow')
const deleteWhitelist = hasFlag('--delete-whitelist')
const verifyBlockAfterWhitelistDelete = hasFlag('--verify-block-after-whitelist-delete')
const verifyBlockAfterSettingsRefresh = hasFlag('--verify-block-after-settings-refresh')
const allowAndVerify = hasFlag('--allow-and-verify') || verifySettingsAfterAllow || deleteWhitelist
const copyDraft = hasFlag('--copy-draft')
const deleteLocalRule = hasFlag('--delete-local-rule')
const verifyImageAfterLocalRuleDelete = hasFlag('--verify-image-after-local-rule-delete')
const verifySettingsAfterSubscription = hasFlag('--verify-settings-after-subscription')
const wakeUnlock = hasFlag('--wake-unlock') || process.env.NEXTE_WAKE_UNLOCK === '1'
const useLease = target === PHYSICAL_TARGET && !hasFlag('--no-lease') && process.env.NEXTE_SKIP_DEVICE_LEASE !== '1'
const leaseScript = join(ROOT, 'scripts', 'device-lease')
let leaseId = ''

mkdirSync(artifactDir, { recursive: true })

function writeArtifact(name, text) {
  const path = join(artifactDir, name)
  writeFileSync(path, text)
  return path
}

function run(command, args, options = {}) {
  const out = execFileSync(command, args, {
    cwd: ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  })
  return out
}

function runHdc(args, control = false) {
  if (leaseId.length > 0 && control) {
    return run(leaseScript, ['run', '--lease', leaseId, '--', hdc, ...args])
  }
  return run(hdc, args)
}

function acquireLease() {
  if (!useLease) {
    return
  }
  try {
    leaseId = run(leaseScript, [
      'acquire',
      '--owner',
      'codex:image-block-seeded-reader',
      '--project',
      'NextE',
      '--ttl',
      '15m',
      '--reason',
      'Seeded image-block Reader QA',
    ]).trim()
  } catch (error) {
    const message = `${error.stderr || error.message || error}`
    writeArtifact('lease-error.txt', message)
    writeSummary('blocked_device_leased', { leaseError: message })
    process.exit(31)
  }
}

function releaseLease() {
  if (leaseId.length === 0) {
    return
  }
  try {
    run(leaseScript, ['release', '--lease', leaseId])
  } catch (_error) {}
  leaseId = ''
}

function parseBounds(bounds) {
  const match = /\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/.exec(bounds)
  if (!match) {
    return null
  }
  return {
    left: Number(match[1]),
    top: Number(match[2]),
    right: Number(match[3]),
    bottom: Number(match[4]),
  }
}

function visit(node, callback) {
  callback(node)
  const children = Array.isArray(node.children) ? node.children : []
  for (const child of children) {
    visit(child, callback)
  }
}

function pointFromBounds(bounds) {
  const centerY = Math.floor((bounds.top + bounds.bottom) / 2)
  return {
    x: Math.floor((bounds.left + bounds.right) / 2),
    y: bounds.top > 2100 ? Math.max(0, bounds.top - 32) : centerY,
  }
}

function joinedNodeText(attrs) {
  return [
    attrs.text || '',
    attrs.originalText || '',
    attrs.accessibilityText || '',
    attrs.description || '',
    attrs.contentDescription || '',
  ].join(' ').trim()
}

function findTextCenter(layout, labels) {
  let found = null
  visit(layout, (node) => {
    if (found !== null) {
      return
    }
    const attrs = node.attributes || {}
    const text = joinedNodeText(attrs)
    const matched = labels.some((label) => text.includes(label))
    if (!matched || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const point = pointFromBounds(bounds)
    found = {
      x: point.x,
      y: point.y,
      text: text.trim(),
    }
  })
  return found
}

function findExactTextCenter(layout, labels) {
  let found = null
  visit(layout, (node) => {
    if (found !== null) {
      return
    }
    const attrs = node.attributes || {}
    const candidates = [
      attrs.text || '',
      attrs.originalText || '',
      attrs.accessibilityText || '',
      attrs.description || '',
      attrs.contentDescription || '',
    ]
    const matched = candidates.some((candidate) => labels.includes(String(candidate).trim()))
    if (!matched || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const point = pointFromBounds(bounds)
    found = {
      x: point.x,
      y: point.y,
      text: joinedNodeText(attrs),
    }
  })
  return found
}

function findTextBounds(layout, labels) {
  let found = null
  visit(layout, (node) => {
    if (found !== null) {
      return
    }
    const attrs = node.attributes || {}
    const text = joinedNodeText(attrs)
    const matched = labels.some((label) => text.includes(label))
    if (!matched || typeof attrs.bounds !== 'string') {
      return
    }
    found = parseBounds(attrs.bounds)
  })
  return found
}

function layoutCenter(path) {
  const layout = readLayout(path)
  let best = null
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const area = Math.max(0, bounds.right - bounds.left) * Math.max(0, bounds.bottom - bounds.top)
    if (best === null || area > best.area) {
      best = { bounds, area }
    }
  })
  if (best === null) {
    return { x: 630, y: 1400 }
  }
  return {
    x: Math.floor((best.bounds.left + best.bounds.right) / 2),
    y: Math.floor((best.bounds.top + best.bounds.bottom) / 2),
  }
}

function bottomToolbarButtonCenter(path, index) {
  const layout = readLayout(path)
  let screenBottom = 0
  let maxButtonTop = -1
  const buttons = []
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    screenBottom = Math.max(screenBottom, bounds.bottom)
    if (attrs.type !== 'Button' || attrs.clickable !== 'true') {
      return
    }
    const width = bounds.right - bounds.left
    const height = bounds.bottom - bounds.top
    if (width < 40 || height < 40) {
      return
    }
    maxButtonTop = Math.max(maxButtonTop, bounds.top)
    buttons.push(bounds)
  })
  if (screenBottom <= 0 || maxButtonTop < Math.floor(screenBottom * 0.65)) {
    return null
  }
  const row = buttons
    .filter((bounds) => Math.abs(bounds.top - maxButtonTop) <= 24)
    .sort((left, right) => left.left - right.left)
  if (index < 0 || index >= row.length) {
    return null
  }
  const bounds = row[index]
  return {
    x: Math.floor((bounds.left + bounds.right) / 2),
    y: Math.floor((bounds.top + bounds.bottom) / 2),
    text: `reader bottom toolbar button ${index}`,
    bounds: `[${bounds.left},${bounds.top}][${bounds.right},${bounds.bottom}]`,
  }
}

function readLayout(path) {
  return JSON.parse(readFileSync(path, 'utf8'))
}

function capture(name) {
  const remoteLayout = `/data/local/tmp/nexte_${name}.json`
  const remoteScreenCap = `/data/local/tmp/nexte_${name}.png`
  const remoteSnapshot = `/data/local/tmp/nexte_${name}.jpeg`
  runHdc(['-t', target, 'shell', 'uitest', 'dumpLayout', '-p', remoteLayout, '-a'], true)
  const layoutPath = join(artifactDir, `${name}.json`)
  runHdc(['-t', target, 'file', 'recv', remoteLayout, layoutPath], true)
  let screenshotPath = ''
  try {
    runHdc(['-t', target, 'shell', 'uitest', 'screenCap', '-p', remoteScreenCap], true)
    screenshotPath = join(artifactDir, `${name}.png`)
    runHdc(['-t', target, 'file', 'recv', remoteScreenCap, screenshotPath], true)
  } catch (error) {
    try {
      runHdc(['-t', target, 'shell', 'snapshot_display', '-f', remoteSnapshot], true)
      screenshotPath = join(artifactDir, `${name}.jpeg`)
      runHdc(['-t', target, 'file', 'recv', remoteSnapshot, screenshotPath], true)
      writeArtifact(`${name}-screencap-error.txt`, String(error))
    } catch (fallbackError) {
      writeArtifact(`${name}-screenshot-error.txt`, `${String(error)}\n${String(fallbackError)}`)
    }
  }
  return { layoutPath, screenshotPath }
}

function layoutText(path) {
  return readFileSync(path, 'utf8')
}

function isLocked(path) {
  const text = layoutText(path)
  return text.includes('ScreenLockRootComponent')
}

function keepAwake() {
  const steps = {}
  try {
    steps.timeout = runHdc(['-t', target, 'shell', 'power-shell', 'timeout', '-o', '600000'], true).trim()
  } catch (error) {
    steps.timeoutError = `${error.stderr || error.message || error}`
  }
  writeArtifact('wake-keep-awake.json', `${JSON.stringify(steps, null, 2)}\n`)
  return steps
}

function wakeAndUnlock() {
  const steps = {}
  try {
    steps.timeout = runHdc(['-t', target, 'shell', 'power-shell', 'timeout', '-o', '600000'], true).trim()
  } catch (error) {
    steps.timeoutError = `${error.stderr || error.message || error}`
  }
  try {
    steps.wakeup = runHdc(['-t', target, 'shell', 'power-shell', 'wakeup'], true).trim()
  } catch (error) {
    steps.wakeupError = `${error.stderr || error.message || error}`
  }
  sleep(1000)
  try {
    steps.swipe = runHdc([
      '-t',
      target,
      'shell',
      'uitest',
      'uiInput',
      'swipe',
      '630',
      '2580',
      '630',
      '260',
      '40000',
    ], true).trim()
  } catch (error) {
    steps.swipeError = `${error.stderr || error.message || error}`
  }
  writeArtifact('wake-unlock.json', `${JSON.stringify(steps, null, 2)}\n`)
  sleep(2000)
  return steps
}

function placeholderVisible(path) {
  const text = layoutText(path)
  return text.includes('图片已隐藏') ||
    text.includes('Image hidden') ||
    text.includes('画像を非表示にしました')
}

function readerStillForeground(path) {
  const text = layoutText(path)
  return text.includes('"bundleName":"com.erosteam.nexte"') &&
    !text.includes('SCBDesktop_Column_PageDesktopLayout')
}

function readerImageCandidateVisible(path) {
  const text = layoutText(path)
  return readerStillForeground(path) &&
    !placeholderVisible(path) &&
    !IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label)) &&
    !LOCAL_RULE_SECTION_LABELS.some((label) => text.includes(label)) &&
    !WHITELIST_SECTION_LABELS.some((label) => text.includes(label)) &&
    text.includes('"type":"Image"')
}

function openReaderChrome(path) {
  const center = layoutCenter(path)
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${center.x}`, `${center.y}`], true)
  writeArtifact('manual-chrome-click.json', `${JSON.stringify(center, null, 2)}\n`)
  sleep(1000)
  return capture('manual_chrome')
}

function findManualMarkButton(path) {
  return findTextCenter(readLayout(path), MANUAL_MARK_LABELS) || bottomToolbarButtonCenter(path, 1)
}

function installSucceeded(output) {
  return output.includes('install bundle successfully')
}

function settingsManualRuleVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const draftVisible = CONTRIBUTION_DRAFT_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    draftVisible &&
    text.includes('scanlator-ad') &&
    text.includes('ce9e...3cd5')
}

function localRuleCountText(path) {
  const layout = readLayout(path)
  const labelBounds = findTextBounds(layout, LOCAL_RULE_SECTION_LABELS)
  if (labelBounds === null) {
    return ''
  }
  let found = ''
  let bestLeft = -1
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (attrs.type !== 'Text' || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const centerY = Math.floor((bounds.top + bounds.bottom) / 2)
    if (bounds.left <= labelBounds.right || centerY < labelBounds.top - 60 || centerY > labelBounds.bottom + 60) {
      return
    }
    const text = String(attrs.text || attrs.originalText || '').trim()
    if (!/^\d+$/.test(text)) {
      return
    }
    if (bounds.left > bestLeft) {
      bestLeft = bounds.left
      found = text
    }
  })
  return found
}

function whitelistCountText(path) {
  const layout = readLayout(path)
  const labelBounds = findTextBounds(layout, WHITELIST_SECTION_LABELS)
  if (labelBounds === null) {
    return ''
  }
  let found = ''
  let bestLeft = -1
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (attrs.type !== 'Text' || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const centerY = Math.floor((bounds.top + bounds.bottom) / 2)
    if (bounds.left <= labelBounds.right || centerY < labelBounds.top - 60 || centerY > labelBounds.bottom + 60) {
      return
    }
    const text = String(attrs.text || attrs.originalText || '').trim()
    if (!/^\d+$/.test(text)) {
      return
    }
    if (bounds.left > bestLeft) {
      bestLeft = bounds.left
      found = text
    }
  })
  return found
}

function whitelistHashVisibleInSection(path) {
  const layout = readLayout(path)
  const sectionBounds = findTextBounds(layout, WHITELIST_SECTION_LABELS)
  if (sectionBounds === null) {
    return false
  }
  let found = false
  visit(layout, (node) => {
    if (found) {
      return
    }
    const attrs = node.attributes || {}
    if (typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null || bounds.top <= sectionBounds.bottom) {
      return
    }
    const text = joinedNodeText(attrs)
    if (text.includes('ce9e...3cd5')) {
      found = true
    }
  })
  return found
}

function settingsManualRuleRemovedVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const localSectionVisible = LOCAL_RULE_SECTION_LABELS.some((label) => text.includes(label))
  const draftVisible = CONTRIBUTION_DRAFT_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    localSectionVisible &&
    localRuleCountText(path) === '0' &&
    !draftVisible &&
    !text.includes('scanlator-ad / P1') &&
    !text.includes('ce9e...3cd5')
}

function settingsWhitelistVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const sectionVisible = WHITELIST_SECTION_LABELS.some((label) => text.includes(label))
  const rowTitleVisible = WHITELIST_ROW_TITLE_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    sectionVisible &&
    rowTitleVisible &&
    whitelistCountText(path) === '1' &&
    whitelistHashVisibleInSection(path)
}

function settingsWhitelistRemovedVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const sectionVisible = WHITELIST_SECTION_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    sectionVisible &&
    whitelistCountText(path) === '0' &&
    !whitelistHashVisibleInSection(path)
}

function settingsSubscriptionProviderVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const providerVisible = SUBSCRIPTION_PROVIDER_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    providerVisible &&
    text.includes('1/1 / 1') &&
    localRuleCountText(path) === '0' &&
    whitelistCountText(path) === '0' &&
    !text.includes('scanlator-ad / P1')
}

function settingsSubscriptionResetVisible(path) {
  const text = layoutText(path)
  const titleVisible = IMAGE_BLOCK_TITLE_LABELS.some((label) => text.includes(label))
  const providerVisible = SUBSCRIPTION_PROVIDER_LABELS.some((label) => text.includes(label))
  return titleVisible &&
    providerVisible &&
    text.includes('1/1 / 0') &&
    localRuleCountText(path) === '0' &&
    whitelistCountText(path) === '0' &&
    !text.includes('scanlator-ad / P1')
}

function findLocalRuleDeleteButton(path) {
  const layout = readLayout(path)
  const rowBounds = []
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    const text = joinedNodeText(attrs)
    if (!text.includes('scanlator-ad / P1') && !text.includes('ce9e...3cd5')) {
      return
    }
    if (typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds !== null) {
      rowBounds.push(bounds)
    }
  })
  if (rowBounds.length === 0) {
    return null
  }
  let rowTop = rowBounds[0].top
  let rowBottom = rowBounds[0].bottom
  for (const bounds of rowBounds) {
    rowTop = Math.min(rowTop, bounds.top)
    rowBottom = Math.max(rowBottom, bounds.bottom)
  }
  let found = null
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (attrs.type !== 'Button' || attrs.clickable !== 'true' || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const centerY = Math.floor((bounds.top + bounds.bottom) / 2)
    if (bounds.left < 900 || centerY < rowTop - 48 || centerY > rowBottom + 48) {
      return
    }
    const point = {
      x: Math.floor((bounds.left + bounds.right) / 2),
      y: Math.floor((bounds.top + bounds.bottom) / 2),
    }
    found = {
      x: point.x,
      y: point.y,
      text: 'local rule delete button',
      bounds: `[${bounds.left},${bounds.top}][${bounds.right},${bounds.bottom}]`,
    }
  })
  return found
}

function findWhitelistDeleteButton(path) {
  const layout = readLayout(path)
  const sectionBounds = findTextBounds(layout, WHITELIST_SECTION_LABELS)
  if (sectionBounds === null) {
    return null
  }
  const rowBounds = []
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null || bounds.top <= sectionBounds.bottom) {
      return
    }
    const text = joinedNodeText(attrs)
    const isWhitelistRowText = text.includes('ce9e...3cd5') ||
      WHITELIST_ROW_TITLE_LABELS.some((label) => text.includes(label))
    if (isWhitelistRowText) {
      rowBounds.push(bounds)
    }
  })
  if (rowBounds.length === 0) {
    return null
  }
  let rowTop = rowBounds[0].top
  let rowBottom = rowBounds[0].bottom
  for (const bounds of rowBounds) {
    rowTop = Math.min(rowTop, bounds.top)
    rowBottom = Math.max(rowBottom, bounds.bottom)
  }
  let found = null
  visit(layout, (node) => {
    const attrs = node.attributes || {}
    if (attrs.type !== 'Button' || attrs.clickable !== 'true' || typeof attrs.bounds !== 'string') {
      return
    }
    const bounds = parseBounds(attrs.bounds)
    if (bounds === null) {
      return
    }
    const centerY = Math.floor((bounds.top + bounds.bottom) / 2)
    if (bounds.left < 900 || centerY < rowTop - 48 || centerY > rowBottom + 48) {
      return
    }
    found = {
      x: Math.floor((bounds.left + bounds.right) / 2),
      y: Math.floor((bounds.top + bounds.bottom) / 2),
      text: 'whitelist delete button',
      bounds: `[${bounds.left},${bounds.top}][${bounds.right},${bounds.bottom}]`,
    }
  })
  return found
}

function settingsManualRuleEdgeVisible(path) {
  const text = layoutText(path)
  const titleVisible = text.includes('图片屏蔽') ||
    text.includes('Image blocks') ||
    text.includes('画像ブロック')
  const draftVisible = text.includes('复制社区规则草稿') ||
    text.includes('Copy community draft') ||
    text.includes('コミュニティ下書きをコピー')
  const missingSourceVisible = text.includes('缺少来源') ||
    text.includes('missing source') ||
    text.includes('ソースなし')
  const duplicateVisible = text.includes('重复') ||
    text.includes('duplicate') ||
    text.includes('重複')
  return titleVisible &&
    draftVisible &&
    text.includes('1/3') &&
    missingSourceVisible &&
    duplicateVisible
}

function contributionCopiedToastVisible(path) {
  const text = layoutText(path)
  return text.includes('已复制图片屏蔽草稿') ||
    text.includes('Copied image block draft') ||
    text.includes('画像ブロック下書きをコピーしました')
}

function verifySettingsRefreshPage(started) {
  let settings = started
  if (!settingsSubscriptionResetVisible(settings.layoutPath)) {
    for (let attempt = 0; attempt < 8; attempt++) {
      sleep(2500)
      settings = capture(`settings_refresh_reset_wait_${attempt}`)
      if (settingsSubscriptionResetVisible(settings.layoutPath)) {
        break
      }
    }
  }
  if (!settingsSubscriptionResetVisible(settings.layoutPath)) {
    writeSummary('blocked_settings_subscription_reset_not_seen', { settings })
    process.exit(45)
  }
  const updateButton = findTextCenter(readLayout(settings.layoutPath), UPDATE_RULES_LABELS)
  if (updateButton === null) {
    writeSummary('blocked_settings_subscription_update_button_not_seen', { settings })
    process.exit(46)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${updateButton.x}`, `${updateButton.y}`], true)
  writeArtifact('settings-refresh-click.json', `${JSON.stringify(updateButton, null, 2)}\n`)
  for (let attempt = 0; attempt < 16; attempt++) {
    sleep(2500)
    const updated = capture(`settings_refresh_wait_${attempt}`)
    if (settingsSubscriptionProviderVisible(updated.layoutPath)) {
      if (verifyBlockAfterSettingsRefresh) {
        verifyReaderBlockedAfterSettingsRefresh(updated, settings, updateButton)
        return
      }
      writeSummary('settings_subscription_update_visible', {
        settings: updated,
        resetSettings: settings,
        updateButton,
      })
      return
    }
  }
  writeSummary('blocked_settings_subscription_update_not_seen', { settings, updateButton })
  process.exit(47)
}

function verifyReaderBlockedAfterSettingsRefresh(settings, resetSettings, updateButton) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    READER_OPEN_QA_URI,
  ], true)
  writeArtifact('block-after-settings-refresh-aa-start.txt', startOutput)
  sleep(4000)
  for (let attempt = 0; attempt < 16; attempt++) {
    const reader = capture(`block_after_settings_refresh_wait_${attempt}`)
    if (placeholderVisible(reader.layoutPath)) {
      writeSummary('reader_block_after_settings_refresh_visible', {
        reader,
        settings,
        resetSettings,
        updateButton,
        settingsQaUri: SETTINGS_REFRESH_QA_URI,
        readerQaUri: READER_OPEN_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_settings_refresh_reader_not_blocked', {
    settings,
    resetSettings,
    updateButton,
    readerQaUri: READER_OPEN_QA_URI,
  })
  process.exit(48)
}

function verifySettingsPage(started) {
  if (settingsRefreshMode) {
    verifySettingsRefreshPage(started)
    return
  }
  let settings = started
  const visible = settingsEdgeMode ? settingsManualRuleEdgeVisible : settingsManualRuleVisible
  if (!visible(settings.layoutPath)) {
    for (let attempt = 0; attempt < 8; attempt++) {
      sleep(2500)
      settings = capture(`settings_wait_${attempt}`)
      if (visible(settings.layoutPath)) {
        break
      }
    }
  }
  if (!visible(settings.layoutPath)) {
    writeSummary('blocked_settings_manual_rule_not_seen', { settings })
    process.exit(28)
  }
  const layout = readLayout(settings.layoutPath)
  const draftButton = findTextCenter(layout, ['复制社区规则草稿', 'Copy community draft', 'コミュニティ下書きをコピー'])
  if (draftButton === null) {
    writeSummary('blocked_settings_contribution_draft_not_seen', { settings })
    process.exit(29)
  }
  if (copyDraft) {
    runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${draftButton.x}`, `${draftButton.y}`], true)
    writeArtifact('draft-click.json', `${JSON.stringify(draftButton, null, 2)}\n`)
    sleep(1000)
    const afterDraftClick = capture('draft_wait_0')
    writeSummary('settings_contribution_draft_clicked', {
      settings: afterDraftClick,
      draftButton,
      toastVisible: contributionCopiedToastVisible(afterDraftClick.layoutPath),
    })
    return
  }
  if (deleteLocalRule) {
    verifyDeleteLocalRule(settings, null, null)
    return
  }
  writeSummary('settings_manual_rule_draft_visible', { settings, draftButton })
}

function verifyDeleteLocalRule(settings, reader, manualButton) {
  const deleteButton = findLocalRuleDeleteButton(settings.layoutPath)
  if (deleteButton === null) {
    writeSummary('blocked_local_rule_delete_button_not_found', { reader, settings, manualButton })
    process.exit(35)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${deleteButton.x}`, `${deleteButton.y}`], true)
  writeArtifact('local-rule-delete-click.json', `${JSON.stringify(deleteButton, null, 2)}\n`)
  sleep(1000)
  const alert = capture('local_rule_delete_alert')
  const confirmButton = findExactTextCenter(readLayout(alert.layoutPath), DELETE_LABELS)
  if (confirmButton === null) {
    writeSummary('blocked_local_rule_delete_confirm_not_seen', { reader, settings, alert, manualButton, deleteButton })
    process.exit(36)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${confirmButton.x}`, `${confirmButton.y}`], true)
  writeArtifact('local-rule-delete-confirm-click.json', `${JSON.stringify(confirmButton, null, 2)}\n`)
  for (let attempt = 0; attempt < 8; attempt++) {
    sleep(2500)
    const deleted = capture(`local_rule_delete_wait_${attempt}`)
    if (settingsManualRuleRemovedVisible(deleted.layoutPath)) {
      if (verifyImageAfterLocalRuleDelete) {
        verifyReaderImageAfterLocalRuleDelete(deleted, reader, manualButton, deleteButton, confirmButton)
        return
      }
      writeSummary('reader_manual_mark_rule_deleted', {
        reader,
        settings: deleted,
        manualButton,
        deleteButton,
        confirmButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
      })
      return
    }
  }
  writeSummary('blocked_local_rule_still_visible', { reader, settings, manualButton, deleteButton, confirmButton })
  process.exit(37)
}

function verifyReaderImageAfterLocalRuleDelete(settings, reader, manualButton, deleteButton, confirmButton) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    READER_OPEN_QA_URI,
  ], true)
  writeArtifact('image-after-local-rule-aa-start.txt', startOutput)
  sleep(4000)
  for (let attempt = 0; attempt < 12; attempt++) {
    const visible = capture(`image_after_local_rule_wait_${attempt}`)
    if (readerImageCandidateVisible(visible.layoutPath)) {
      writeSummary('reader_image_after_local_rule_delete_visible', {
        reader: visible,
        previousBlockedReader: reader,
        settings,
        manualButton,
        deleteButton,
        confirmButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
        readerQaUri: READER_OPEN_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_local_rule_delete_reader_still_blocked', {
    reader,
    settings,
    manualButton,
    deleteButton,
    confirmButton,
    readerQaUri: READER_OPEN_QA_URI,
  })
  process.exit(43)
}

function verifyDeleteWhitelist(settings, reader, readButton, allowButton) {
  const deleteButton = findWhitelistDeleteButton(settings.layoutPath)
  if (deleteButton === null) {
    writeSummary('blocked_whitelist_delete_button_not_found', { reader, settings, readButton, allowButton })
    process.exit(39)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${deleteButton.x}`, `${deleteButton.y}`], true)
  writeArtifact('whitelist-delete-click.json', `${JSON.stringify(deleteButton, null, 2)}\n`)
  sleep(1000)
  const alert = capture('whitelist_delete_alert')
  const confirmButton = findExactTextCenter(readLayout(alert.layoutPath), DELETE_LABELS)
  if (confirmButton === null) {
    writeSummary('blocked_whitelist_delete_confirm_not_seen', {
      reader,
      settings,
      alert,
      readButton,
      allowButton,
      deleteButton,
    })
    process.exit(40)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${confirmButton.x}`, `${confirmButton.y}`], true)
  writeArtifact('whitelist-delete-confirm-click.json', `${JSON.stringify(confirmButton, null, 2)}\n`)
  for (let attempt = 0; attempt < 8; attempt++) {
    sleep(2500)
    const deleted = capture(`whitelist_delete_wait_${attempt}`)
    if (settingsWhitelistRemovedVisible(deleted.layoutPath)) {
      if (verifyBlockAfterWhitelistDelete) {
        verifyReaderBlockedAfterWhitelistDelete(deleted, reader, readButton, allowButton, deleteButton, confirmButton)
        return
      }
      writeSummary('reader_allowlist_deleted', {
        reader,
        settings: deleted,
        readButton,
        allowButton,
        deleteButton,
        confirmButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
      })
      return
    }
  }
  writeSummary('blocked_whitelist_still_visible', { reader, settings, readButton, allowButton, deleteButton, confirmButton })
  process.exit(41)
}

function verifyReaderBlockedAfterWhitelistDelete(settings, reader, readButton, allowButton, deleteButton, confirmButton) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    READER_QA_URI,
  ], true)
  writeArtifact('block-after-whitelist-aa-start.txt', startOutput)
  sleep(4000)
  for (let attempt = 0; attempt < 12; attempt++) {
    const blocked = capture(`block_after_whitelist_wait_${attempt}`)
    if (placeholderVisible(blocked.layoutPath)) {
      writeSummary('reader_block_after_whitelist_delete_visible', {
        reader: blocked,
        previousAllowedReader: reader,
        settings,
        readButton,
        allowButton,
        deleteButton,
        confirmButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
        readerQaUri: READER_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_whitelist_delete_reader_not_blocked', {
    reader,
    settings,
    readButton,
    allowButton,
    deleteButton,
    confirmButton,
    readerQaUri: READER_QA_URI,
  })
  process.exit(42)
}

function verifySettingsAfterWhitelistAllow(reader, readButton, allowButton) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    SETTINGS_OPEN_QA_URI,
  ], true)
  writeArtifact('allow-settings-aa-start.txt', startOutput)
  sleep(3000)
  for (let attempt = 0; attempt < 8; attempt++) {
    const settings = capture(`allow_settings_wait_${attempt}`)
    if (settingsWhitelistVisible(settings.layoutPath)) {
      if (deleteWhitelist) {
        verifyDeleteWhitelist(settings, reader, readButton, allowButton)
        return
      }
      writeSummary('reader_allowlist_settings_visible', {
        reader,
        settings,
        readButton,
        allowButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_allow_settings_whitelist_not_seen', {
    reader,
    readButton,
    allowButton,
    settingsQaUri: SETTINGS_OPEN_QA_URI,
  })
  process.exit(38)
}

function verifySettingsAfterSubscriptionBlock(reader, readButton = null) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    SETTINGS_OPEN_QA_URI,
  ], true)
  writeArtifact('subscription-settings-aa-start.txt', startOutput)
  sleep(3000)
  for (let attempt = 0; attempt < 8; attempt++) {
    const settings = capture(`subscription_settings_wait_${attempt}`)
    if (settingsSubscriptionProviderVisible(settings.layoutPath)) {
      writeSummary('reader_subscription_settings_visible', {
        reader,
        settings,
        readButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_subscription_settings_not_seen', {
    reader,
    readButton,
    settingsQaUri: SETTINGS_OPEN_QA_URI,
  })
  process.exit(44)
}

function verifyAllowedImage(reader, readButton = null) {
  const layout = readLayout(reader.layoutPath)
  const allowButton = findTextCenter(layout, ['允许此图', 'Allow this image', 'この画像を許可'])
  if (allowButton === null) {
    writeSummary('blocked_allow_button_not_found', { reader, readButton })
    process.exit(26)
  }
  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${allowButton.x}`, `${allowButton.y}`], true)
  writeArtifact('allow-click.json', `${JSON.stringify(allowButton, null, 2)}\n`)
  for (let attempt = 0; attempt < 12; attempt++) {
    sleep(2500)
    const allowed = capture(`allow_wait_${attempt}`)
    if (readerImageCandidateVisible(allowed.layoutPath)) {
      if (verifySettingsAfterAllow || deleteWhitelist) {
        verifySettingsAfterWhitelistAllow(allowed, readButton, allowButton)
        return
      }
      writeSummary('reader_allowlist_image_visible', { reader: allowed, readButton, allowButton })
      return
    }
  }
  writeSummary('blocked_allowlist_image_not_seen', { reader, readButton, allowButton })
  process.exit(27)
}

function verifySettingsAfterManualMark(marked, manualButton) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    SETTINGS_OPEN_QA_URI,
  ], true)
  writeArtifact('manual-settings-aa-start.txt', startOutput)
  sleep(3000)
  for (let attempt = 0; attempt < 8; attempt++) {
    const settings = capture(`manual_settings_wait_${attempt}`)
    if (settingsManualRuleVisible(settings.layoutPath)) {
      if (deleteLocalRule) {
        const stableSettings = reopenSettingsForDelete('manual_settings_stable')
        if (settingsManualRuleVisible(stableSettings.layoutPath)) {
          verifyDeleteLocalRule(stableSettings, marked, manualButton)
          return
        }
        verifyDeleteLocalRule(settings, marked, manualButton)
        return
      }
      writeSummary('reader_manual_mark_settings_visible', {
        reader: marked,
        settings,
        manualButton,
        settingsQaUri: SETTINGS_OPEN_QA_URI,
      })
      return
    }
    sleep(2500)
  }
  writeSummary('blocked_manual_settings_rule_not_seen', {
    reader: marked,
    manualButton,
    settingsQaUri: SETTINGS_OPEN_QA_URI,
  })
  process.exit(34)
}

function reopenSettingsForDelete(prefix) {
  const startOutput = runHdc([
    '-t',
    target,
    'shell',
    'aa',
    'start',
    '-b',
    bundle,
    '-a',
    ability,
    '-U',
    SETTINGS_OPEN_QA_URI,
  ], true)
  writeArtifact(`${prefix}-aa-start.txt`, startOutput)
  sleep(3000)
  return capture(`${prefix}_wait_0`)
}

function verifyManualMark(started) {
  let reader = started
  if (placeholderVisible(reader.layoutPath)) {
    writeSummary('blocked_manual_mark_preexisting_placeholder', { reader })
    process.exit(33)
  }
  if (!readerImageCandidateVisible(reader.layoutPath)) {
    for (let attempt = 0; attempt < 16; attempt++) {
      sleep(3000)
      reader = capture(`manual_reader_wait_${attempt}`)
      if (placeholderVisible(reader.layoutPath)) {
        writeSummary('blocked_manual_mark_preexisting_placeholder', { reader })
        process.exit(33)
      }
      if (readerImageCandidateVisible(reader.layoutPath)) {
        break
      }
    }
  }
  if (!readerImageCandidateVisible(reader.layoutPath)) {
    writeSummary('blocked_manual_mark_image_not_seen', { reader })
    process.exit(33)
  }

  let chrome = reader
  let manualButton = findManualMarkButton(chrome.layoutPath)
  if (manualButton === null) {
    chrome = openReaderChrome(chrome.layoutPath)
    manualButton = findManualMarkButton(chrome.layoutPath)
  }
  if (manualButton === null) {
    chrome = openReaderChrome(chrome.layoutPath)
    manualButton = findManualMarkButton(chrome.layoutPath)
  }
  if (manualButton === null) {
    writeSummary('blocked_manual_mark_button_not_found', { reader, chrome })
    process.exit(33)
  }

  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${manualButton.x}`, `${manualButton.y}`], true)
  writeArtifact('manual-mark-click.json', `${JSON.stringify(manualButton, null, 2)}\n`)
  for (let attempt = 0; attempt < 16; attempt++) {
    sleep(3000)
    const marked = capture(`manual_mark_wait_${attempt}`)
    if (placeholderVisible(marked.layoutPath)) {
      if (verifySettingsAfterMark) {
        verifySettingsAfterManualMark(marked, manualButton)
        return
      }
      writeSummary('reader_manual_mark_placeholder_visible', { reader: marked, manualButton })
      return
    }
  }
  writeSummary('blocked_manual_mark_placeholder_not_seen', { reader, manualButton })
  process.exit(33)
}

function finishWithPlaceholder(reader, readButton = null) {
  if (allowAndVerify) {
    verifyAllowedImage(reader, readButton)
    return
  }
  if (subscriptionMode) {
    if (verifySettingsAfterSubscription) {
      verifySettingsAfterSubscriptionBlock(reader, readButton)
      return
    }
    if (readButton === null) {
      writeSummary('reader_subscription_placeholder_visible', { reader })
      return
    }
    writeSummary('reader_subscription_placeholder_visible', { reader, readButton })
    return
  }
  if (readButton === null) {
    writeSummary('reader_block_placeholder_visible', { reader })
    return
  }
  writeSummary('reader_block_placeholder_visible', { reader, readButton })
}

function writeSummary(status, extra = {}) {
  const summary = {
    status,
    target,
    bundle,
    ability,
    qaUri,
    viaDetail,
    settingsMode,
    allowAndVerify,
    verifySettingsAfterAllow,
    verifyBlockAfterWhitelistDelete,
    verifyBlockAfterSettingsRefresh,
    copyDraft,
    deleteLocalRule,
    verifyImageAfterLocalRuleDelete,
    deleteWhitelist,
    settingsEdgeMode,
    settingsRefreshMode,
    subscriptionMode,
    verifySettingsAfterSubscription,
    manualMark,
    verifySettingsAfterMark,
    wakeUnlock,
    hap,
    artifactDir,
    leaseUsed: useLease,
    seedGalleryUrl: 'https://e-hentai.org/g/3049882/d7e740a39e/',
    seedPage: 1,
    seedHash: 'ce9e181d354a3cd5',
    edgeMissingSourceHash: '0123456789abcdef',
    ...extra,
  }
  const path = writeArtifact('summary.json', `${JSON.stringify(summary, null, 2)}\n`)
  console.log(JSON.stringify({ ...summary, summary: path }, null, 2))
}

function sleep(ms) {
  execFileSync('/bin/sleep', [`${Math.max(0, Math.ceil(ms / 1000))}`], { stdio: 'ignore' })
}

function main() {
  if (!existsSync(hdc)) {
    throw new Error(`hdc not found: ${hdc}`)
  }
  if (install && !existsSync(hap)) {
    throw new Error(`signed HAP not found: ${hap}`)
  }

  acquireLease()

  const targets = run(hdc, ['list', 'targets', '-v'])
  writeArtifact('targets.txt', targets)
  if (!targets.includes(`${target}\t\tTCP\tConnected`)) {
    writeSummary('blocked_target_not_connected')
    process.exit(20)
  }

  const echo = runHdc(['-t', target, 'shell', 'echo', 'ok'])
  writeArtifact('echo.txt', echo)
  if (!echo.includes('ok')) {
    writeSummary('blocked_shell_not_ready')
    process.exit(21)
  }

  if (wakeUnlock) {
    keepAwake()
  }

  let preflight = capture('preflight')
  if (isLocked(preflight.layoutPath)) {
    if (wakeUnlock) {
      const unlock = wakeAndUnlock()
      preflight = capture('preflight_after_wake_unlock')
      if (!isLocked(preflight.layoutPath)) {
        writeArtifact('wake-unlock-result.json', `${JSON.stringify({
          status: 'unlocked',
          unlock,
          preflight,
        }, null, 2)}\n`)
      } else {
        writeSummary('blocked_screen_locked_after_wake_unlock', { preflight, unlock })
        process.exit(32)
      }
    } else {
      writeSummary('blocked_screen_locked', { preflight })
      process.exit(22)
    }
  }

  if (install) {
    const installOutput = runHdc(['-t', target, 'install', '-r', hap], true)
    writeArtifact('install.txt', installOutput)
    if (!installSucceeded(installOutput)) {
      writeSummary('blocked_install_failed', { installOutput })
      process.exit(30)
    }
  }

  runHdc(['-t', target, 'shell', 'aa', 'force-stop', bundle], true)
  const startOutput = runHdc(['-t', target, 'shell', 'aa', 'start', '-b', bundle, '-a', ability, '-U', qaUri], true)
  writeArtifact('aa-start.txt', startOutput)
  sleep(4000)

  const started = capture('after_start')
  if (isLocked(started.layoutPath)) {
    writeSummary('blocked_screen_locked_after_start', { started })
    process.exit(23)
  }

  if (settingsMode) {
    verifySettingsPage(started)
    return
  }

  if (manualMark) {
    verifyManualMark(started)
    return
  }

  if (!viaDetail) {
    if (placeholderVisible(started.layoutPath)) {
      finishWithPlaceholder(started)
      return
    }
    for (let attempt = 0; attempt < 16; attempt++) {
      sleep(3000)
      const reader = capture(`reader_wait_${attempt}`)
      if (placeholderVisible(reader.layoutPath)) {
        finishWithPlaceholder(reader)
        return
      }
    }
    writeSummary('blocked_placeholder_not_seen')
    process.exit(25)
  }

  if (!clickRead) {
    writeSummary('opened_seeded_gallery_detail', { detail: started })
    return
  }

  let readButton = null
  let detailLayoutPath = started.layoutPath
  for (let attempt = 0; attempt < 8; attempt++) {
    const layout = readLayout(detailLayoutPath)
    readButton = findTextCenter(layout, ['阅读', 'Read', '继续', 'Continue'])
    if (readButton !== null) {
      break
    }
    sleep(2500)
    const next = capture(`detail_wait_${attempt}`)
    detailLayoutPath = next.layoutPath
  }
  if (readButton === null) {
    writeSummary('blocked_read_button_not_found', { detailLayoutPath })
    process.exit(24)
  }

  runHdc(['-t', target, 'shell', 'uitest', 'uiInput', 'click', `${readButton.x}`, `${readButton.y}`], true)
  writeArtifact('read-click.json', `${JSON.stringify(readButton, null, 2)}\n`)

  for (let attempt = 0; attempt < 16; attempt++) {
    sleep(3000)
    const reader = capture(`reader_wait_${attempt}`)
    if (placeholderVisible(reader.layoutPath)) {
      finishWithPlaceholder(reader, readButton)
      return
    }
  }
  writeSummary('blocked_placeholder_not_seen', { readButton })
  process.exit(25)
}

process.on('exit', releaseLease)
process.on('SIGINT', () => {
  releaseLease()
  process.exit(130)
})
process.on('SIGTERM', () => {
  releaseLease()
  process.exit(143)
})

main()
