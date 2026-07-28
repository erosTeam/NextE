#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

function fail(message) {
  throw new Error(message)
}

function argumentsMap(values) {
  const result = new Map()
  for (let index = 0; index < values.length; index += 2) {
    const key = values[index]
    const value = values[index + 1]
    if (!key?.startsWith('--') || value === undefined) {
      fail(
        'Usage: comic_translation_input_ab.mjs --probe-root DIR --manifest FILE ' +
        '--output FILE [--review FILE]',
      )
    }
    result.set(key.slice(2), value)
  }
  return result
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function integer(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(`${label} must be a non-negative integer`)
  }
  return value
}

function requiredText(value, label) {
  if (typeof value !== 'string' || value.length === 0) {
    fail(`${label} must be non-empty text`)
  }
  return value
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function median(values) {
  if (values.length === 0) {
    return 0
  }
  const ordered = [...values].sort((left, right) => left - right)
  const middle = Math.floor(ordered.length / 2)
  return ordered.length % 2 === 0
    ? (ordered[middle - 1] + ordered[middle]) / 2
    : ordered[middle]
}

function probeFiles(probeRoot, probeId, expectedMode) {
  const directory = path.join(probeRoot, probeId)
  const request = readJson(path.join(directory, 'request.json'))
  const response = readJson(path.join(directory, 'response.json'))
  const status = readJson(path.join(directory, 'status.json'))
  if (request.schemaVersion !== 2 || response.schemaVersion !== 2 ||
    status.schemaVersion !== 2) {
    fail(`${probeId} does not use debug probe schema 2`)
  }
  if (request.probeId !== probeId || response.probeId !== probeId ||
    status.probeId !== probeId || request.inputMode !== expectedMode ||
    response.diagnostics?.inputMode !== expectedMode) {
    fail(`${probeId} identity or input mode is inconsistent`)
  }
  if (status.state !== 'ready' || status.errorCode !== '') {
    fail(`${probeId} is not a successful ready result`)
  }
  return { request, response, status }
}

function translatedById(response, label) {
  const result = new Map()
  const blocks = response.batch?.blocks
  if (!Array.isArray(blocks)) {
    fail(`${label} response blocks are missing`)
  }
  for (const block of blocks) {
    const blockId = requiredText(block.blockId, `${label} block id`)
    const text = requiredText(block.translatedText, `${label} translated text`)
    if (result.has(blockId)) {
      fail(`${label} has duplicate block ${blockId}`)
    }
    result.set(blockId, text)
  }
  return result
}

function modeMetrics(files) {
  const diagnostics = files.response.diagnostics
  const imageDataUrlChars =
    integer(diagnostics.fullImageDataUrlChars, 'full image chars') +
    integer(diagnostics.regionCropDataUrlChars, 'crop chars')
  return {
    promptVersion: requiredText(files.response.batch.promptVersion, 'prompt version'),
    contextFingerprint: requiredText(
      files.response.batch.contextFingerprint,
      'context fingerprint',
    ),
    blockCount: files.response.batch.blocks.length,
    probeElapsedMs: integer(files.response.elapsedMs, 'probe elapsed'),
    promptChars: integer(diagnostics.promptChars, 'prompt chars'),
    fullImageDataUrlChars: integer(
      diagnostics.fullImageDataUrlChars,
      'full image chars',
    ),
    regionCropCount: integer(diagnostics.regionCropCount, 'crop count'),
    regionCropDataUrlChars: integer(
      diagnostics.regionCropDataUrlChars,
      'crop chars',
    ),
    regionCropBytes: integer(diagnostics.regionCropBytes, 'crop bytes'),
    regionCropPixels: integer(diagnostics.regionCropPixels, 'crop pixels'),
    imageDataUrlChars,
    providerResponseChars: integer(
      diagnostics.providerResponseChars,
      'provider response chars',
    ),
    prepareMs: integer(diagnostics.prepareMs, 'prepare ms'),
    providerMs: integer(diagnostics.providerMs, 'provider ms'),
    parseMs: integer(diagnostics.parseMs, 'parse ms'),
    translatorTotalMs: integer(diagnostics.totalMs, 'translator total ms'),
  }
}

function pairedResult(probeRoot, pair) {
  const pageId = requiredText(pair.pageId, 'pair pageId')
  const multimodalId = requiredText(pair.multimodalProbeId, `${pageId} multimodal probe`)
  const textOnlyId = requiredText(pair.textOnlyProbeId, `${pageId} text-only probe`)
  const multimodal = probeFiles(probeRoot, multimodalId, 'multimodal')
  const textOnly = probeFiles(probeRoot, textOnlyId, 'text_only')
  const left = multimodal.request
  const right = textOnly.request
  const identityChecks = {
    sameSource: sameJson(left.source, right.source),
    sameDocumentPayload: left.documentPayload === right.documentPayload,
    sameContext: sameJson(left.context, right.context),
    sameRequestedTranslationRevision:
      left.requestedTranslationRevision === right.requestedTranslationRevision,
    sameSourceProfile:
      multimodal.response.batch.sourceProfileId === textOnly.response.batch.sourceProfileId,
    sameSourceRevision:
      multimodal.response.batch.sourceRevision === textOnly.response.batch.sourceRevision,
    sameModel: multimodal.response.batch.modelId === textOnly.response.batch.modelId,
    sameTargetLanguage:
      multimodal.response.batch.targetLanguage === textOnly.response.batch.targetLanguage,
  }
  for (const [check, passed] of Object.entries(identityChecks)) {
    if (!passed) {
      fail(`${pageId} failed required A/B identity check ${check}`)
    }
  }
  const document = JSON.parse(left.documentPayload)
  if (!Array.isArray(document.blocks) || document.blocks.length === 0) {
    fail(`${pageId} document has no blocks`)
  }
  const multimodalText = translatedById(multimodal.response, `${pageId} multimodal`)
  const textOnlyText = translatedById(textOnly.response, `${pageId} text-only`)
  const blocks = document.blocks.map((block) => {
    const blockId = requiredText(block.blockId, `${pageId} document block id`)
    const multimodalTranslation = multimodalText.get(blockId)
    const textOnlyTranslation = textOnlyText.get(blockId)
    if (multimodalTranslation === undefined || textOnlyTranslation === undefined) {
      fail(`${pageId} response is missing document block ${blockId}`)
    }
    return {
      blockId,
      readingOrder: block.readingOrder,
      kind: block.kind,
      sourceText: block.sourceText,
      normalizedSourceText: block.normalizedSourceText,
      multimodalTranslation,
      textOnlyTranslation,
      translationsEqual: multimodalTranslation === textOnlyTranslation,
      manualReview: {
        visibleSourceChecked: false,
        ocrIssue: '',
        preferredMode: '',
        multimodalQuality: '',
        textOnlyQuality: '',
        note: '',
      },
    }
  })
  if (multimodalText.size !== blocks.length || textOnlyText.size !== blocks.length) {
    fail(`${pageId} response contains an unknown block`)
  }
  const multimodalMetrics = modeMetrics(multimodal)
  const textOnlyMetrics = modeMetrics(textOnly)
  if (multimodalMetrics.imageDataUrlChars <= 0 ||
    multimodalMetrics.regionCropCount !== Math.min(16, blocks.length) ||
    textOnlyMetrics.imageDataUrlChars !== 0 ||
    textOnlyMetrics.regionCropCount !== 0 ||
    multimodalMetrics.contextFingerprint === textOnlyMetrics.contextFingerprint) {
    fail(`${pageId} input-mode diagnostics do not prove the intended isolation`)
  }
  return {
    pageId,
    source: {
      projectId: left.source.projectId,
      pageIndex: left.source.pageIndex,
      imageHash: left.source.imageHash,
      width: left.source.imageWidth,
      height: left.source.imageHeight,
      sourceLanguage: left.context.sourceLanguage,
      targetLanguage: left.context.targetLanguage,
      documentSha256: sha256(left.documentPayload),
      documentChars: left.documentPayload.length,
      blockCount: blocks.length,
    },
    provider: {
      sourceProfileId: multimodal.response.batch.sourceProfileId,
      sourceRevision: multimodal.response.batch.sourceRevision,
      modelId: multimodal.response.batch.modelId,
    },
    identityChecks,
    multimodal: multimodalMetrics,
    textOnly: textOnlyMetrics,
    changedTranslationBlocks: blocks.filter((block) => !block.translationsEqual).length,
    blocks,
  }
}

function attachManualReview(pairs, review) {
  if (review.schemaVersion !== 1 ||
    review.protocol !== 'visible-source-manual-block-review-v1' ||
    !Array.isArray(review.pages)) {
    fail('Manual review file is invalid')
  }
  const qualityValues = new Set(['correct', 'minor_issue', 'major_issue', 'failed'])
  const preferredValues = new Set(['multimodal', 'text_only', 'equal'])
  const ocrIssueValues = new Set(['none', 'minor', 'major'])
  const reviewedPages = new Map()
  for (const page of review.pages) {
    const pageId = requiredText(page.pageId, 'review pageId')
    if (reviewedPages.has(pageId) || !Array.isArray(page.blocks)) {
      fail(`Manual review page ${pageId} is duplicated or has no blocks`)
    }
    reviewedPages.set(pageId, page.blocks)
  }
  const summary = {
    protocol: review.protocol,
    reviewedBlocks: 0,
    preferredMode: {
      multimodal: 0,
      textOnly: 0,
      equal: 0,
    },
    ocrIssue: {
      none: 0,
      minor: 0,
      major: 0,
    },
    quality: {
      multimodal: {
        correct: 0,
        minorIssue: 0,
        majorIssue: 0,
        failed: 0,
        acceptable: 0,
      },
      textOnly: {
        correct: 0,
        minorIssue: 0,
        majorIssue: 0,
        failed: 0,
        acceptable: 0,
      },
    },
  }
  for (const pair of pairs) {
    const pageReviews = reviewedPages.get(pair.pageId)
    if (!pageReviews || pageReviews.length !== pair.blocks.length) {
      fail(`Manual review page ${pair.pageId} does not match the A/B blocks`)
    }
    const blockReviews = new Map()
    for (const blockReview of pageReviews) {
      const blockId = requiredText(blockReview.blockId, `${pair.pageId} review block id`)
      if (blockReviews.has(blockId)) {
        fail(`Manual review duplicates ${pair.pageId}/${blockId}`)
      }
      blockReviews.set(blockId, blockReview)
    }
    for (const block of pair.blocks) {
      const blockReview = blockReviews.get(block.blockId)
      if (!blockReview || blockReview.visibleSourceChecked !== true ||
        !ocrIssueValues.has(blockReview.ocrIssue) ||
        !preferredValues.has(blockReview.preferredMode) ||
        !qualityValues.has(blockReview.multimodalQuality) ||
        !qualityValues.has(blockReview.textOnlyQuality) ||
        typeof blockReview.note !== 'string') {
        fail(`Manual review is incomplete for ${pair.pageId}/${block.blockId}`)
      }
      block.manualReview = {
        visibleSourceChecked: true,
        ocrIssue: blockReview.ocrIssue,
        preferredMode: blockReview.preferredMode,
        multimodalQuality: blockReview.multimodalQuality,
        textOnlyQuality: blockReview.textOnlyQuality,
        note: blockReview.note,
      }
      summary.reviewedBlocks += 1
      const preferredKey = blockReview.preferredMode === 'text_only'
        ? 'textOnly'
        : blockReview.preferredMode
      summary.preferredMode[preferredKey] += 1
      summary.ocrIssue[blockReview.ocrIssue] += 1
      for (const [mode, field] of [
        ['multimodal', 'multimodalQuality'],
        ['textOnly', 'textOnlyQuality'],
      ]) {
        const quality = blockReview[field]
        const qualityKey = quality === 'minor_issue'
          ? 'minorIssue'
          : quality === 'major_issue'
            ? 'majorIssue'
            : quality
        summary.quality[mode][qualityKey] += 1
        if (quality === 'correct' || quality === 'minor_issue') {
          summary.quality[mode].acceptable += 1
        }
      }
    }
    if (blockReviews.size !== pair.blocks.length) {
      fail(`Manual review contains an unknown block on ${pair.pageId}`)
    }
    reviewedPages.delete(pair.pageId)
  }
  if (reviewedPages.size !== 0) {
    fail('Manual review contains an unknown page')
  }
  return summary
}

const args = argumentsMap(process.argv.slice(2))
const probeRoot = path.resolve(requiredText(args.get('probe-root'), '--probe-root'))
const manifestPath = path.resolve(requiredText(args.get('manifest'), '--manifest'))
const outputPath = path.resolve(requiredText(args.get('output'), '--output'))
const manifest = readJson(manifestPath)
if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.pairs) ||
  manifest.pairs.length === 0) {
  fail('A/B manifest is invalid')
}
const pairs = manifest.pairs.map((pair) => pairedResult(probeRoot, pair))
const reviewPath = args.has('review')
  ? path.resolve(requiredText(args.get('review'), '--review'))
  : ''
const manualReview = reviewPath.length > 0
  ? attachManualReview(pairs, readJson(reviewPath))
  : undefined
const modes = ['multimodal', 'textOnly']
const aggregate = {}
for (const mode of modes) {
  aggregate[mode] = {
    pages: pairs.length,
    blocks: pairs.reduce((sum, pair) => sum + pair[mode].blockCount, 0),
    medianProviderMs: median(pairs.map((pair) => pair[mode].providerMs)),
    medianTranslatorTotalMs: median(
      pairs.map((pair) => pair[mode].translatorTotalMs),
    ),
    totalImageDataUrlChars: pairs.reduce(
      (sum, pair) => sum + pair[mode].imageDataUrlChars,
      0,
    ),
  }
}
const report = {
  schemaVersion: 1,
  protocol: 'same-page-same-document-same-provider-input-mode-ab-v1',
  aggregate,
  ...(manualReview ? { manualReview } : {}),
  pairs,
}
fs.mkdirSync(path.dirname(outputPath), { recursive: true })
fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`)
console.log(`Wrote ${pairs.length} paired result(s) to ${outputPath}`)
