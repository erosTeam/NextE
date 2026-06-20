#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { join } from 'node:path'

const DEFAULT_HDC =
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'

function argValue(name, fallback) {
  const index = process.argv.indexOf(name)
  if (index >= 0 && process.argv[index + 1]) {
    return process.argv[index + 1]
  }
  return fallback
}

function run(command, args) {
  return execFileSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
}

const hdc = argValue('--hdc', DEFAULT_HDC)
const target = argValue('--target', '127.0.0.1:5555')
const outDir = argValue('--out', '.hvigor/outputs/harmony-capture')
const name = argValue('--name', 'screen')
const remotePrefix = argValue('--remote-prefix', `/data/local/tmp/${name}`)

mkdirSync(outDir, { recursive: true })

const remoteImage = `${remotePrefix}.jpeg`
const dumpOutput = run(hdc, ['-t', target, 'shell', 'uitest', 'dumpLayout'])
const match = /DumpLayout saved to:(\S+)/.exec(dumpOutput)
if (!match) {
  throw new Error(`Unable to find remote layout path in: ${dumpOutput}`)
}
const remoteLayout = match[1]

run(hdc, ['-t', target, 'shell', 'snapshot_display', '-f', remoteImage])

const screenshot = join(outDir, `${name}.jpeg`)
const layout = join(outDir, `${name}.json`)
run(hdc, ['-t', target, 'file', 'recv', remoteImage, screenshot])
run(hdc, ['-t', target, 'file', 'recv', remoteLayout, layout])

console.log(JSON.stringify({
  target,
  screenshot,
  layout,
}, null, 2))
