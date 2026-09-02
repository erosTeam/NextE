#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const repoRoot = process.cwd()
const roots = ['entry/src/main/ets', 'feature', 'shared/src/main/ets']
const interactiveInput = /\b(TextInput|TextArea|Search)\s*\(/

function collectEtsFiles(relativeRoot) {
  const absoluteRoot = path.join(repoRoot, relativeRoot)
  if (!fs.existsSync(absoluteRoot)) return []
  const files = []
  const pending = [absoluteRoot]
  while (pending.length > 0) {
    const current = pending.pop()
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name)
      if (entry.isDirectory()) {
        pending.push(absolute)
      } else if (entry.isFile() && entry.name.endsWith('.ets')) {
        files.push(absolute)
      }
    }
  }
  return files
}

function maskNonCode(source) {
  const chars = source.split('')
  let state = 'code'
  for (let index = 0; index < chars.length; index += 1) {
    const char = chars[index]
    const next = chars[index + 1]
    if (state === 'line-comment') {
      if (char === '\n') state = 'code'
      else chars[index] = ' '
      continue
    }
    if (state === 'block-comment') {
      if (char === '*' && next === '/') {
        chars[index] = ' '
        chars[index + 1] = ' '
        index += 1
        state = 'code'
      } else if (char !== '\n') {
        chars[index] = ' '
      }
      continue
    }
    if (state === 'single' || state === 'double' || state === 'template') {
      const end = state === 'single' ? "'" : state === 'double' ? '"' : '`'
      if (char === '\\') {
        chars[index] = ' '
        if (index + 1 < chars.length) {
          if (chars[index + 1] !== '\n') chars[index + 1] = ' '
          index += 1
        }
      } else if (char === end) {
        chars[index] = ' '
        state = 'code'
      } else if (char !== '\n') {
        chars[index] = ' '
      }
      continue
    }
    if (char === '/' && next === '/') {
      chars[index] = ' '
      chars[index + 1] = ' '
      index += 1
      state = 'line-comment'
    } else if (char === '/' && next === '*') {
      chars[index] = ' '
      chars[index + 1] = ' '
      index += 1
      state = 'block-comment'
    } else if (char === "'") {
      chars[index] = ' '
      state = 'single'
    } else if (char === '"') {
      chars[index] = ' '
      state = 'double'
    } else if (char === '`') {
      chars[index] = ' '
      state = 'template'
    }
  }
  return chars.join('')
}

function matchingIndex(code, openIndex, openChar, closeChar) {
  let depth = 0
  for (let index = openIndex; index < code.length; index += 1) {
    if (code[index] === openChar) depth += 1
    else if (code[index] === closeChar) {
      depth -= 1
      if (depth === 0) return index
    }
  }
  return -1
}

function builderBodies(masked) {
  const bodies = new Map()
  const builderPattern = /@Builder\s+(?:(?:private|public|protected)\s+)?([A-Za-z_]\w*)\s*\(/g
  let match
  while ((match = builderPattern.exec(masked)) !== null) {
    const openParen = masked.indexOf('(', match.index)
    const closeParen = matchingIndex(masked, openParen, '(', ')')
    if (closeParen < 0) continue
    const openBrace = masked.indexOf('{', closeParen)
    if (openBrace < 0) continue
    const closeBrace = matchingIndex(masked, openBrace, '{', '}')
    if (closeBrace < 0) continue
    bodies.set(match[1], masked.slice(openBrace + 1, closeBrace))
    builderPattern.lastIndex = closeBrace + 1
  }
  return bodies
}

function inputReachable(body, builders, visiting = new Set()) {
  if (interactiveInput.test(body)) return true
  const callPattern = /\bthis\.([A-Za-z_]\w*)\s*\(/g
  let match
  while ((match = callPattern.exec(body)) !== null) {
    const name = match[1]
    if (visiting.has(name) || !builders.has(name)) continue
    const nextVisiting = new Set(visiting)
    nextVisiting.add(name)
    if (inputReachable(builders.get(name), builders, nextVisiting)) return true
  }
  return false
}

function lineNumber(source, index) {
  return source.slice(0, index).split('\n').length
}

const failures = []
const files = roots.flatMap(collectEtsFiles)
for (const absolute of files) {
  const source = fs.readFileSync(absolute, 'utf8')
  const masked = maskNonCode(source)
  const builders = builderBodies(masked)

  const slotPattern = /(suffixBuilderParam|prefixBuilderParam)\s*:\s*\(\s*\)\s*=>\s*\{/g
  let match
  while ((match = slotPattern.exec(masked)) !== null) {
    const openBrace = masked.indexOf('{', match.index)
    const closeBrace = matchingIndex(masked, openBrace, '{', '}')
    if (closeBrace < 0) {
      failures.push(
        `${path.relative(repoRoot, absolute)}:${lineNumber(source, match.index)} malformed ${match[1]}`,
      )
      continue
    }
    const body = masked.slice(openBrace + 1, closeBrace)
    if (inputReachable(body, builders)) {
      failures.push(
        `${path.relative(repoRoot, absolute)}:${lineNumber(source, match.index)} ` +
          `interactive input is reachable from ${match[1]}; mount it as a stable sibling instead`,
      )
    }
    slotPattern.lastIndex = closeBrace + 1
  }

  const slotReferencePattern = /(suffixBuilderParam|prefixBuilderParam)\s*:\s*this\.([A-Za-z_]\w*)/g
  while ((match = slotReferencePattern.exec(masked)) !== null) {
    if (builders.has(match[2]) && inputReachable(builders.get(match[2]), builders)) {
      failures.push(
        `${path.relative(repoRoot, absolute)}:${lineNumber(source, match.index)} ` +
          `interactive input is reachable from ${match[1]}; mount it as a stable sibling instead`,
      )
    }
  }

  const hdsBuilderPattern = /new\s+(SuffixCustomBuilder|PrefixCustomBuilder)\s*\(\s*\(\s*\)\s*=>\s*\{/g
  while ((match = hdsBuilderPattern.exec(masked)) !== null) {
    const openBrace = masked.indexOf('{', match.index)
    const closeBrace = matchingIndex(masked, openBrace, '{', '}')
    if (closeBrace < 0) {
      failures.push(
        `${path.relative(repoRoot, absolute)}:${lineNumber(source, match.index)} malformed ${match[1]}`,
      )
      continue
    }
    const body = masked.slice(openBrace + 1, closeBrace)
    if (inputReachable(body, builders)) {
      failures.push(
        `${path.relative(repoRoot, absolute)}:${lineNumber(source, match.index)} ` +
          `interactive input is reachable from ${match[1]}; mount it as a stable sibling instead`,
      )
    }
    hdsBuilderPattern.lastIndex = closeBrace + 1
  }
}

const inlinePath = path.join(repoRoot, 'shared/src/main/ets/components/InlineEditRow.ets')
const inlineSource = fs.readFileSync(inlinePath, 'utf8')
if (!inlineSource.includes('this.InputOverlay()')) {
  failures.push('InlineEditRow must mount InputOverlay directly in its stable component tree')
}
if (!/TextInput\(\{\s*text:\s*this\.fieldText\b/.test(inlineSource)) {
  failures.push('InlineEditRow TextInput must bind to its private fieldText mirror')
}
if (!/\.onChange\(\(v:\s*string\)\s*=>\s*\{\s*this\.fieldText\s*=\s*v\s*this\.onChange\(v\)/s.test(inlineSource)) {
  failures.push('InlineEditRow must update its local mirror before publishing the edit')
}

if (failures.length > 0) {
  console.error('Input node stability contract failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `✓ Input node stability: ${files.length} ArkTS file(s), ` +
    'no interactive input in dynamic HDS custom builders',
)
