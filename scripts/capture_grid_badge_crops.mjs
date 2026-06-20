#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const DEFAULT_HDC =
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'

function argValue(name, fallback) {
  const index = process.argv.indexOf(name)
  if (index >= 0 && process.argv[index + 1]) {
    return process.argv[index + 1]
  }
  return fallback
}

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: options.encoding ?? 'utf8',
    stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'],
  })
}

function parseBounds(bounds) {
  const match = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(bounds ?? '')
  if (!match) {
    return undefined
  }
  return match.slice(1).map(Number)
}

function collectGridItems(node, out) {
  if (!node || typeof node !== 'object') {
    return
  }
  const attrs = node.attributes ?? node
  if (attrs.type === 'GridItem') {
    const parsed = parseBounds(attrs.bounds)
    if (parsed) {
      out.push({ bounds: attrs.bounds, parsed })
    }
  }
  for (const value of Object.values(node)) {
    if (!value || typeof value !== 'object') {
      continue
    }
    if (Array.isArray(value)) {
      for (const child of value) {
        collectGridItems(child, out)
      }
    } else {
      collectGridItems(value, out)
    }
  }
}

function uniqueGridItems(items) {
  const seen = new Set()
  const unique = []
  for (const item of items) {
    if (seen.has(item.bounds)) {
      continue
    }
    seen.add(item.bounds)
    unique.push(item)
  }
  return unique
}

const hdc = argValue('--hdc', DEFAULT_HDC)
const target = argValue('--target', '127.0.0.1:5555')
const outDir = argValue(
  '--out',
  '.hvigor/outputs/gallery-browsing-layout-recovery/grid-badge-crops',
)
const existingScreenshot = argValue('--screenshot', '')
const existingLayout = argValue('--layout', '')
const remotePrefix = argValue('--remote-prefix', '/data/local/tmp/nexte_grid_badge')
const cropCount = Number.parseInt(argValue('--count', '9'), 10)
const cropWidth = Number.parseInt(argValue('--crop-width', '96'), 10)
const cropHeight = Number.parseInt(argValue('--crop-height', '82'), 10)
const scale = Number.parseInt(argValue('--scale', '4'), 10)

mkdirSync(outDir, { recursive: true })

let screenshot = existingScreenshot
let layoutPath = existingLayout
if (screenshot.length === 0 || layoutPath.length === 0) {
  const remoteImage = `${remotePrefix}.jpeg`
  const dumpOutput = run(hdc, ['-t', target, 'shell', 'uitest', 'dumpLayout'])
  const match = /DumpLayout saved to:(\S+)/.exec(dumpOutput)
  if (!match) {
    throw new Error(`Unable to find remote layout path in: ${dumpOutput}`)
  }
  const remoteLayout = match[1]

  run(hdc, ['-t', target, 'shell', 'snapshot_display', '-f', remoteImage], {
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  screenshot = join(outDir, 'screen.jpeg')
  layoutPath = join(outDir, 'layout.json')
  run(hdc, ['-t', target, 'file', 'recv', remoteImage, screenshot], {
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  run(hdc, ['-t', target, 'file', 'recv', remoteLayout, layoutPath], {
    stdio: ['ignore', 'pipe', 'pipe'],
  })
}

const layout = JSON.parse(readFileSync(layoutPath, 'utf8'))
const items = uniqueGridItems((() => {
  const result = []
  collectGridItems(layout, result)
  return result
})())

const crops = []
for (let i = 0; i < Math.min(cropCount, items.length); i++) {
  const [x1, y1, x2, y2] = items[i].parsed
  const x = Math.max(0, x2 - cropWidth - 2)
  const y = Math.max(0, y1 - 2)
  const crop = join(outDir, `badge_crop_${i}.jpeg`)
  run('sips', ['-c', String(cropHeight), String(cropWidth), '--cropOffset', String(y), String(x), screenshot, '--out', crop], {
    stdio: 'ignore',
  })
  run('sips', ['-z', String(cropHeight * scale), String(cropWidth * scale), crop, '--out', crop], {
    stdio: 'ignore',
  })
  crops.push({ index: i, bounds: items[i].bounds, crop })
}

const firstY = items[0]?.parsed[1]
const firstRowCount =
  firstY === undefined ? 0 : items.filter((item) => Math.abs(item.parsed[1] - firstY) < 5).length

console.log(JSON.stringify({
  target,
  screenshot,
  layout: layoutPath,
  gridItemCount: items.length,
  firstRowCount,
  crops,
}, null, 2))
