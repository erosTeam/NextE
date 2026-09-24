#!/usr/bin/env node

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { spawn, spawnSync } from 'node:child_process'

const DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
const TRUSTED_HDC = process.env.HDC ?? DEFAULT_HDC

function fail(message) {
  console.error(message)
  process.exit(1)
}

function sha256File(filePath) {
  const digest = crypto.createHash('sha256')
  digest.update(fs.readFileSync(filePath))
  return digest.digest('hex')
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.length === 0) {
    fail(`${label} must be a non-empty string.`)
  }
  return value
}

function requireInteger(value, label, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    fail(`${label} must be an integer in ${minimum}..${maximum}.`)
  }
  return value
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

function validatePoint(xText, yText, display, label) {
  const x = Number(xText)
  const y = Number(yText)
  if (!Number.isInteger(x) || x < 0 || x >= display.widthPx) {
    fail(`${label}.x must be inside 0..${display.widthPx - 1}.`)
  }
  if (!Number.isInteger(y) || y < 0 || y >= display.heightPx) {
    fail(`${label}.y must be inside 0..${display.heightPx - 1}.`)
  }
}

function validateUiInput(args, display, label) {
  if (!Array.isArray(args) || args.some((value) => typeof value !== 'string')) {
    fail(`${label}.uiInput must be a string array.`)
  }
  const operation = args[0]
  if (['click', 'doubleClick', 'longClick'].includes(operation)) {
    if (args.length !== 3) {
      fail(`${label}.${operation} requires x and y.`)
    }
    validatePoint(args[1], args[2], display, label)
    return
  }
  if (['swipe', 'drag', 'fling'].includes(operation)) {
    if (args.length < 5 || args.length > 6) {
      fail(`${label}.${operation} requires x1, y1, x2, y2, and optional velocity.`)
    }
    validatePoint(args[1], args[2], display, `${label}.from`)
    validatePoint(args[3], args[4], display, `${label}.to`)
    if (args.length === 6) {
      requireInteger(Number(args[5]), `${label}.velocity`, 200, 40000)
    }
    return
  }
  if (operation === 'keyEvent' && args.length >= 2 && args.length <= 4) {
    return
  }
  fail(`${label} uses an unsupported uiInput operation.`)
}

function validateLaunchAbility(manifest) {
  if (manifest.launchAbility === undefined) return
  const launch = manifest.launchAbility
  if (launch === null || typeof launch !== 'object' || Array.isArray(launch)) {
    fail('launchAbility must be an object.')
  }
  launch.name = requireString(launch.name, 'launchAbility.name')
  launch.bundleName = requireString(launch.bundleName, 'launchAbility.bundleName')
  launch.abilityName = requireString(launch.abilityName, 'launchAbility.abilityName')
  launch.pauseAfterMs = requireInteger(launch.pauseAfterMs ?? 0, 'launchAbility.pauseAfterMs', 0, 600000)
  if (launch.parameters === undefined) {
    launch.parameters = {}
    return
  }
  if (launch.parameters === null || typeof launch.parameters !== 'object' || Array.isArray(launch.parameters)) {
    fail('launchAbility.parameters must be an object.')
  }
  for (const [key, value] of Object.entries(launch.parameters)) {
    if (!/^[A-Za-z0-9_.-]+$/.test(key) || typeof value !== 'string' || value.length === 0) {
      fail('launchAbility.parameters must contain simple non-empty string entries.')
    }
  }
}

function validateHilog(manifest) {
  if (manifest.hilog === undefined) return
  const hilog = manifest.hilog
  if (hilog === null || typeof hilog !== 'object' || Array.isArray(hilog)) {
    fail('hilog must be an object.')
  }
  if (!Array.isArray(hilog.hdcArgs) || hilog.hdcArgs.length !== 2 ||
    hilog.hdcArgs[0] !== 'shell' || hilog.hdcArgs[1] !== 'hilog') {
    fail('hilog.hdcArgs must be exactly ["shell", "hilog"].')
  }
  hilog.localFile = requireString(hilog.localFile, 'hilog.localFile')
  if (!/^[A-Za-z0-9._-]+\.txt$/.test(hilog.localFile)) {
    fail('hilog.localFile must be a simple .txt file name.')
  }
}

function readManifest(manifestPath) {
  const source = fs.readFileSync(manifestPath, 'utf8')
  const manifest = JSON.parse(source)
  if (manifest.schemaVersion !== 1) {
    fail('schemaVersion must be 1.')
  }
  requireString(manifest.name, 'name')
  requireString(manifest.target, 'target')
  requireString(manifest.authorizedTarget, 'authorizedTarget')
  if (manifest.target !== manifest.authorizedTarget) {
    fail('target and authorizedTarget must match exactly.')
  }
  manifest.hdc = requireString(manifest.hdc ?? TRUSTED_HDC, 'hdc')
  if (manifest.hdc !== TRUSTED_HDC || !path.isAbsolute(manifest.hdc)) {
    fail(`hdc must match the trusted HDC environment/default path: ${TRUSTED_HDC}`)
  }
  manifest.artifactDir = requireString(manifest.artifactDir, 'artifactDir')
  if (!path.isAbsolute(manifest.artifactDir)) {
    fail('artifactDir must be absolute.')
  }
  manifest.recordingFileName = requireString(manifest.recordingFileName, 'recordingFileName')
  if (!/^[A-Za-z0-9._-]+\.mp4$/.test(manifest.recordingFileName)) {
    fail('recordingFileName must be a simple .mp4 file name.')
  }
  manifest.timeoutMs = requireInteger(manifest.timeoutMs ?? 86400000, 'timeoutMs', 1000, 86400000)
  manifest.warmupMs = requireInteger(manifest.warmupMs ?? 500, 'warmupMs', 0, 10000)
  manifest.idleRecordMs = requireInteger(manifest.idleRecordMs ?? 2000, 'idleRecordMs', 0, 600000)
  if (manifest.display === null || typeof manifest.display !== 'object' || Array.isArray(manifest.display)) {
    fail('display must be an object.')
  }
  manifest.display.widthPx = requireInteger(manifest.display.widthPx, 'display.widthPx', 1, 100000)
  manifest.display.heightPx = requireInteger(manifest.display.heightPx, 'display.heightPx', 1, 100000)
  if (!Array.isArray(manifest.actions)) {
    fail('actions must be an array.')
  }
  manifest.actions.forEach((action, index) => {
    const label = `actions[${index}]`
    if (action === null || typeof action !== 'object' || Array.isArray(action)) {
      fail(`${label} must be an object.`)
    }
    action.name = requireString(action.name, `${label}.name`)
    validateUiInput(action.uiInput, manifest.display, label)
    action.pauseAfterMs = requireInteger(action.pauseAfterMs ?? 0, `${label}.pauseAfterMs`, 0, 600000)
  })
  validateLaunchAbility(manifest)
  validateHilog(manifest)
  if (manifest.actions.length > 0 && manifest.idleRecordMs > 0) {
    fail('idleRecordMs must be 0 when actions are present.')
  }
  if (manifest.context === null || typeof manifest.context !== 'object' || Array.isArray(manifest.context)) {
    fail('context must be an object.')
  }
  for (const field of ['project', 'codeIdentity', 'page', 'orientation']) {
    requireString(manifest.context[field], `context.${field}`)
  }
  return { manifest, source }
}

function startHilog(manifest) {
  const localFile = path.join(manifest.artifactDir, manifest.hilog.localFile)
  const stderrFile = path.join(manifest.artifactDir, `${manifest.hilog.localFile}.stderr.txt`)
  const stdoutFd = fs.openSync(localFile, 'wx')
  const stderrFd = fs.openSync(stderrFile, 'wx')
  const child = spawn(manifest.hdc, ['-t', manifest.target, ...manifest.hilog.hdcArgs], {
    stdio: ['ignore', stdoutFd, stderrFd],
  })
  const handle = {
    child,
    localFile,
    stderrFile,
    stdoutFd,
    stderrFd,
    startedAt: new Date().toISOString(),
    spawnError: null,
  }
  child.once('error', (error) => { handle.spawnError = error })
  return handle
}

async function stopHilog(handle) {
  if (handle.child.exitCode === null && handle.child.signalCode === null) {
    handle.child.kill('SIGTERM')
  }
  if (handle.child.exitCode === null && handle.child.signalCode === null) {
    await new Promise((resolve) => { handle.child.once('close', resolve) })
  }
  fs.closeSync(handle.stdoutFd)
  fs.closeSync(handle.stderrFd)
  const bytes = fs.existsSync(handle.localFile) ? fs.statSync(handle.localFile).size : 0
  return {
    file: handle.localFile,
    sha256: bytes > 0 ? sha256File(handle.localFile) : null,
    bytes,
    stderrFile: handle.stderrFile,
    exitCode: handle.child.exitCode,
    signal: handle.child.signalCode,
    startedAt: handle.startedAt,
    finishedAt: new Date().toISOString(),
    error: handle.spawnError?.message ?? null,
  }
}

function createArtifactDir(artifactDir) {
  if (fs.existsSync(artifactDir)) {
    fail(`artifactDir must be new: ${artifactDir}`)
  }
  let current = path.parse(artifactDir).root
  for (const part of path.relative(current, artifactDir).split(path.sep)) {
    current = path.join(current, part)
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) {
      fail(`artifactDir may not contain a symlink component: ${current}`)
    }
  }
  fs.mkdirSync(artifactDir, { recursive: true })
}

function commandRecord(phase, name, executable, args, result, startedAt, finishedAt) {
  return {
    phase,
    name,
    argv: [executable, ...args],
    startedAt,
    finishedAt,
    exitCode: result.status,
    signal: result.signal,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  }
}

function execute(records, phase, name, executable, args, options = {}) {
  const startedAt = new Date().toISOString()
  const result = spawnSync(executable, args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  })
  const finishedAt = new Date().toISOString()
  records.push(commandRecord(phase, name, executable, args, result, startedAt, finishedAt))
  if (result.error !== undefined) {
    throw result.error
  }
  if (result.status !== 0) {
    throw new Error(`${name} failed with exit code ${result.status}: ${result.stderr ?? ''}`)
  }
  return result.stdout ?? ''
}

function executeHdc(records, manifest, phase, name, args) {
  return execute(records, phase, name, manifest.hdc, ['-t', manifest.target, ...args])
}

function verifyConnected(records, manifest) {
  const output = execute(records, 'preflight', 'list-targets', manifest.hdc, ['list', 'targets', '-v'])
  const connected = output.split('\n').some((line) => {
    const fields = line.trim().split(/\s+/)
    return fields[0] === manifest.target && fields.includes('Connected')
  })
  if (!connected) {
    throw new Error(`Target is not Connected: ${manifest.target}`)
  }
}

function verifyPowerState(output, timeoutMs) {
  if (!output.includes('Current State: AWAKE')) {
    throw new Error('PowerManager did not report Current State: AWAKE.')
  }
  if (!output.includes(`OverrideTimeout=${timeoutMs}ms`)) {
    throw new Error(`PowerManager did not report OverrideTimeout=${timeoutMs}ms.`)
  }
}

function parseMediaTarget(output) {
  const countMatch = output.match(/find\s+(\d+)\s+result/)
  if (countMatch === null || Number(countMatch[1]) !== 1) {
    return ''
  }
  const uri = output.match(/"(file:\/\/media\/[^"\r\n]+)"/)
  if (uri !== null) {
    const assetUri = uri[1].match(/^(file:\/\/media\/Photo\/[^/]+)/)
    return assetUri?.[1] ?? uri[1]
  }
  const mediaPath = output.split('\n').map((line) => line.trim()).find((line) => {
    return line.startsWith('/storage/') || line.startsWith('/mnt/data/')
  })
  return mediaPath ?? ''
}

function parseExportedPath(output, recordingFileName) {
  const lines = output.split('\n').map((line) => line.trim())
  const exact = lines.find((line) => line === `/data/local/tmp/${recordingFileName}`)
  if (exact !== undefined) {
    return exact
  }
  return lines.find((line) => line.startsWith('/data/local/tmp/')) ?? ''
}

async function queryMediaTarget(records, manifest) {
  let lastOutput = ''
  for (let attempt = 1; attempt <= 12; attempt += 1) {
    lastOutput = executeHdc(
      records,
      manifest,
      'export',
      `query-recording-${attempt}`,
      ['shell', 'mediatool', 'query', manifest.recordingFileName, '-u'],
    )
    const target = parseMediaTarget(lastOutput)
    if (target.length > 0) {
      return target
    }
    await sleep(500)
  }
  throw new Error(`Recording did not appear in MediaLibrary: ${lastOutput}`)
}

async function exportMediaTarget(records, manifest, mediaTarget, remoteExport) {
  let lastOutput = ''
  for (let attempt = 1; attempt <= 12; attempt += 1) {
    executeHdc(records, manifest, 'export', `remove-stale-export-${attempt}`, [
      'shell', 'rm', '-f', remoteExport,
    ])
    lastOutput = executeHdc(records, manifest, 'export', `export-media-uri-${attempt}`, [
      'shell', 'mediatool', 'recv', mediaTarget, remoteExport,
    ])
    const exportedPath = parseExportedPath(lastOutput, manifest.recordingFileName)
    if (exportedPath.length > 0 && !lastOutput.includes('[FAIL]')) {
      return exportedPath
    }
    await sleep(500)
  }
  throw new Error(`Recording remained unreadable in MediaLibrary: ${lastOutput}`)
}

async function deleteMediaTarget(records, manifest, mediaTarget) {
  if (!mediaTarget.startsWith('file://media/')) {
    throw new Error(`Recording MediaLibrary URI is unavailable for cleanup: ${mediaTarget}`)
  }
  executeHdc(records, manifest, 'cleanup', 'delete-recording-media-asset', [
    'shell', 'mediatool', 'delete', mediaTarget,
  ])
  let lastOutput = ''
  for (let attempt = 1; attempt <= 12; attempt += 1) {
    lastOutput = executeHdc(
      records,
      manifest,
      'cleanup',
      `verify-recording-media-deleted-${attempt}`,
      ['shell', 'mediatool', 'query', manifest.recordingFileName, '-u'],
    )
    if (parseMediaTarget(lastOutput).length === 0) {
      return
    }
    await sleep(500)
  }
  throw new Error(`Recording remained in MediaLibrary after cleanup: ${lastOutput}`)
}

async function main() {
  const validateOnly = process.argv[3] === '--validate-only'
  if (process.argv.length < 3 || process.argv.length > 4 || (process.argv.length === 4 && !validateOnly)) {
    fail(`Usage: ${path.basename(process.argv[1])} <recording-manifest.json> [--validate-only]`)
  }
  const manifestPath = path.resolve(process.argv[2])
  const loaded = readManifest(manifestPath)
  const manifest = loaded.manifest
  if (validateOnly) {
    console.log(JSON.stringify({ result: 'valid', manifest: manifestPath, target: manifest.target }, null, 2))
    return
  }
  createArtifactDir(manifest.artifactDir)

  const records = []
  const copiedManifest = path.join(manifest.artifactDir, 'recording-manifest.json')
  fs.writeFileSync(copiedManifest, loaded.source)
  const manifestSha256 = crypto.createHash('sha256').update(loaded.source).digest('hex')
  const runnerSha256 = sha256File(new URL(import.meta.url))
  const localRecording = path.join(manifest.artifactDir, manifest.recordingFileName)
  const remoteExport = `/data/local/tmp/${manifest.recordingFileName}`
  let recordingStarted = false
  let hilogHandle = null
  let hilog = null
  let error = null

  try {
    verifyConnected(records, manifest)
    executeHdc(records, manifest, 'preflight', 'transport-check', ['shell', 'echo', 'ok'])
    executeHdc(records, manifest, 'preflight', 'wake', ['shell', 'power-shell', 'wakeup'])
    executeHdc(records, manifest, 'preflight', 'keep-awake', [
      'shell', 'power-shell', 'timeout', '-o', `${manifest.timeoutMs}`,
    ])
    const initialPower = executeHdc(records, manifest, 'preflight', 'verify-power', [
      'shell', 'hidumper', '-s', 'PowerManagerService', '-a', '-s',
    ])
    verifyPowerState(initialPower, manifest.timeoutMs)
    executeHdc(records, manifest, 'preflight', 'window-state', [
      'shell', 'hidumper', '-s', 'WindowManagerService', '-a', '-a',
    ])

    if (manifest.hilog !== undefined) {
      hilogHandle = startHilog(manifest)
      await sleep(100)
      if (hilogHandle.spawnError !== null || hilogHandle.child.exitCode !== null) {
        throw new Error(`hilog did not remain running: ${hilogHandle.spawnError?.message ??
          `exit code ${hilogHandle.child.exitCode}`}`)
      }
    }

    if (manifest.launchAbility !== undefined) {
      const launchArgs = ['shell', 'aa', 'start', '-b', manifest.launchAbility.bundleName,
        '-a', manifest.launchAbility.abilityName]
      for (const [key, value] of Object.entries(manifest.launchAbility.parameters)) {
        launchArgs.push('--ps', key, value)
      }
      executeHdc(records, manifest, 'preparation', manifest.launchAbility.name, launchArgs)
      await sleep(manifest.launchAbility.pauseAfterMs)
    }

    executeHdc(records, manifest, 'recording', 'start-recorder', [
      'shell', 'aa', 'start',
      '-b', 'com.huawei.hmos.screenrecorder',
      '-a', 'com.huawei.hmos.screenrecorder.ServiceExtAbility',
      '--ps', 'CustomizedFileName', manifest.recordingFileName,
    ])
    recordingStarted = true
    // ScreenRecorder can reset the timeout override. Check it inside the same
    // continuous recording before the first UI input, keeping every action in
    // this runner's existing ordered chain.
    executeHdc(records, manifest, 'recording', 'keep-awake-after-recorder-start', [
      'shell', 'power-shell', 'timeout', '-o', `${manifest.timeoutMs}`,
    ])
    const recordingPower = executeHdc(records, manifest, 'recording', 'verify-power-after-recorder-start', [
      'shell', 'hidumper', '-s', 'PowerManagerService', '-a', '-s',
    ])
    verifyPowerState(recordingPower, manifest.timeoutMs)
    await sleep(manifest.warmupMs)
    if (manifest.actions.length === 0) {
      await sleep(manifest.idleRecordMs)
    } else {
      for (const action of manifest.actions) {
        executeHdc(records, manifest, 'measurement', action.name, [
          'shell', 'uitest', 'uiInput', ...action.uiInput,
        ])
        await sleep(action.pauseAfterMs)
      }
    }
  } catch (caught) {
    error = caught instanceof Error ? caught : new Error(String(caught))
  } finally {
    if (recordingStarted) {
      try {
        executeHdc(records, manifest, 'recording', 'stop-recorder', [
          'shell', 'aa', 'start',
          '-b', 'com.huawei.hmos.screenrecorder',
          '-a', 'com.huawei.hmos.screenrecorder.ServiceExtAbility',
        ])
      } catch (caught) {
        if (error === null) {
          error = caught instanceof Error ? caught : new Error(String(caught))
        }
      }
    }
    if (hilogHandle !== null) {
      try {
        hilog = await stopHilog(hilogHandle)
        if (hilog.error !== null && error === null) {
          error = new Error(`hilog failed: ${hilog.error}`)
        }
      } catch (caught) {
        if (error === null) {
          error = caught instanceof Error ? caught : new Error(String(caught))
        }
      }
    }
  }

  if (error === null) {
    try {
      const mediaTarget = await queryMediaTarget(records, manifest)
      let downloadablePath = mediaTarget
      if (mediaTarget.startsWith('file://media/')) {
        downloadablePath = await exportMediaTarget(records, manifest, mediaTarget, remoteExport)
      }
      executeHdc(records, manifest, 'export', 'receive-recording', [
        'file', 'recv', downloadablePath, localRecording,
      ])
      if (!fs.existsSync(localRecording) || fs.statSync(localRecording).size === 0) {
        throw new Error(`Recording was not downloaded: ${localRecording}`)
      }
      // Preserve the verified local evidence first. Only then remove both the temporary export and
      // the original MediaLibrary asset so repeated diagnostics do not fill the device gallery.
      if (downloadablePath.startsWith('/data/local/tmp/')) {
        executeHdc(records, manifest, 'export', 'remove-exported-copy', [
          'shell', 'rm', downloadablePath,
        ])
      }
      await deleteMediaTarget(records, manifest, mediaTarget)
      const finalPower = executeHdc(records, manifest, 'postflight', 'verify-power-final', [
        'shell', 'hidumper', '-s', 'PowerManagerService', '-a', '-s',
      ])
      verifyPowerState(finalPower, manifest.timeoutMs)
    } catch (caught) {
      error = caught instanceof Error ? caught : new Error(String(caught))
    }
  }

  fs.writeFileSync(path.join(manifest.artifactDir, 'command-ledger.json'), `${JSON.stringify(records, null, 2)}\n`)
  const summary = {
    result: error === null ? 'success' : 'failed',
    manifest: copiedManifest,
    manifestSha256,
    runnerSha256,
    target: manifest.target,
    recording: error === null ? localRecording : null,
    recordingSha256: error === null ? sha256File(localRecording) : null,
    hilog,
    error: error?.message ?? null,
  }
  fs.writeFileSync(path.join(manifest.artifactDir, 'summary.json'), `${JSON.stringify(summary, null, 2)}\n`)
  console.log(JSON.stringify(summary, null, 2))
  if (error !== null) {
    process.exit(1)
  }
}

await main()
