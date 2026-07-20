import {
  ComicPageDocument,
  ComicQualitySeverity,
  ComicTextBlock,
} from '../model/ComicTranslation'

export class ComicTranslationEvaluationSnapshot {
  totalBlocks: number = 0
  translatedBlocks: number = 0
  geometryBlocks: number = 0
  sourceCharacters: number = 0
  translatedCharacters: number = 0
  infoSignals: number = 0
  warningSignals: number = 0
  errorSignals: number = 0
}

export enum ComicTranslationEvaluationIssueCode {
  MISSING_SOURCE = 'missing_source',
  UNEXPECTED_SOURCE = 'unexpected_source',
  READING_ORDER = 'reading_order',
  REQUIRED_TRANSLATION_TERM = 'required_translation_term',
}

export class ComicTranslationReferenceBlock {
  sourceVariants: string[] = []
  requiredTranslationTerms: string[] = []

  copy(): ComicTranslationReferenceBlock {
    const block: ComicTranslationReferenceBlock = new ComicTranslationReferenceBlock()
    for (let index: number = 0; index < this.sourceVariants.length; index++) {
      block.sourceVariants.push(this.sourceVariants[index])
    }
    for (let index: number = 0; index < this.requiredTranslationTerms.length; index++) {
      block.requiredTranslationTerms.push(this.requiredTranslationTerms[index])
    }
    return block
  }
}

export class ComicTranslationReferencePage {
  projectId: string = ''
  pageIndex: number = -1
  imageHash: string = ''
  blocks: ComicTranslationReferenceBlock[] = []

  copy(): ComicTranslationReferencePage {
    const page: ComicTranslationReferencePage = new ComicTranslationReferencePage()
    page.projectId = this.projectId
    page.pageIndex = this.pageIndex
    page.imageHash = this.imageHash
    for (let index: number = 0; index < this.blocks.length; index++) {
      page.blocks.push(this.blocks[index].copy())
    }
    return page
  }
}

export class ComicTranslationEvaluationIssue {
  code: ComicTranslationEvaluationIssueCode = ComicTranslationEvaluationIssueCode.MISSING_SOURCE
  referenceIndex: number = -1
  documentIndex: number = -1
  expectedText: string = ''
  actualText: string = ''
}

export class ComicTranslationAccuracySnapshot {
  expectedBlocks: number = 0
  actualBlocks: number = 0
  matchedSourceBlocks: number = 0
  missingSourceBlocks: number = 0
  unexpectedSourceBlocks: number = 0
  readingOrderErrors: number = 0
  requiredTranslationTermErrors: number = 0
  issues: ComicTranslationEvaluationIssue[] = []

  transcriptMatchPercent(): number {
    if (this.expectedBlocks === 0) {
      return this.actualBlocks === 0 ? 100 : 0
    }
    return Math.round(this.matchedSourceBlocks * 10000 / this.expectedBlocks) / 100
  }

  passed(): boolean {
    return this.missingSourceBlocks === 0 &&
      this.unexpectedSourceBlocks === 0 &&
      this.readingOrderErrors === 0 &&
      this.requiredTranslationTermErrors === 0
  }
}

/**
 * Structural coverage only. Accuracy still requires a reviewed fixture and must not be inferred
 * from these counts or from provider-reported confidence.
 */
export class ComicTranslationEvaluator {
  static snapshot(document: ComicPageDocument): ComicTranslationEvaluationSnapshot {
    const snapshot: ComicTranslationEvaluationSnapshot = new ComicTranslationEvaluationSnapshot()
    snapshot.totalBlocks = document.blocks.length
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ComicTextBlock = document.blocks[index]
      snapshot.sourceCharacters = snapshot.sourceCharacters + block.sourceText.length
      if (block.translatedText.length > 0) {
        snapshot.translatedBlocks = snapshot.translatedBlocks + 1
        snapshot.translatedCharacters = snapshot.translatedCharacters + block.translatedText.length
      }
      if (block.polygon.length >= 3) {
        snapshot.geometryBlocks = snapshot.geometryBlocks + 1
      }
    }
    for (let index: number = 0; index < document.qualitySignals.length; index++) {
      const severity: ComicQualitySeverity = document.qualitySignals[index].severity
      if (severity === ComicQualitySeverity.ERROR) {
        snapshot.errorSignals = snapshot.errorSignals + 1
      } else if (severity === ComicQualitySeverity.WARNING) {
        snapshot.warningSignals = snapshot.warningSignals + 1
      } else {
        snapshot.infoSignals = snapshot.infoSignals + 1
      }
    }
    return snapshot
  }

  static accuracy(
    document: ComicPageDocument,
    reference: ComicTranslationReferencePage,
  ): ComicTranslationAccuracySnapshot {
    ComicTranslationEvaluator.validateIdentity(document, reference)
    const snapshot: ComicTranslationAccuracySnapshot = new ComicTranslationAccuracySnapshot()
    snapshot.expectedBlocks = reference.blocks.length
    snapshot.actualBlocks = document.blocks.length
    const matchedDocumentIndexes: Set<number> = new Set<number>()
    let previousDocumentIndex: number = -1
    for (let referenceIndex: number = 0; referenceIndex < reference.blocks.length; referenceIndex++) {
      const expected: ComicTranslationReferenceBlock = reference.blocks[referenceIndex]
      const documentIndex: number = ComicTranslationEvaluator.findSourceBlock(
        document.blocks,
        expected,
        matchedDocumentIndexes,
      )
      if (documentIndex < 0) {
        snapshot.missingSourceBlocks = snapshot.missingSourceBlocks + 1
        snapshot.issues.push(ComicTranslationEvaluator.issue(
          ComicTranslationEvaluationIssueCode.MISSING_SOURCE,
          referenceIndex,
          -1,
          ComicTranslationEvaluator.primaryExpectedText(expected),
          '',
        ))
        continue
      }
      matchedDocumentIndexes.add(documentIndex)
      snapshot.matchedSourceBlocks = snapshot.matchedSourceBlocks + 1
      if (documentIndex < previousDocumentIndex) {
        snapshot.readingOrderErrors = snapshot.readingOrderErrors + 1
        snapshot.issues.push(ComicTranslationEvaluator.issue(
          ComicTranslationEvaluationIssueCode.READING_ORDER,
          referenceIndex,
          documentIndex,
          ComicTranslationEvaluator.primaryExpectedText(expected),
          document.blocks[documentIndex].sourceText,
        ))
      }
      previousDocumentIndex = documentIndex
      if (!ComicTranslationEvaluator.hasRequiredTranslationTerms(
        document.blocks[documentIndex],
        expected,
      )) {
        snapshot.requiredTranslationTermErrors = snapshot.requiredTranslationTermErrors + 1
        snapshot.issues.push(ComicTranslationEvaluator.issue(
          ComicTranslationEvaluationIssueCode.REQUIRED_TRANSLATION_TERM,
          referenceIndex,
          documentIndex,
          expected.requiredTranslationTerms.join('|'),
          document.blocks[documentIndex].translatedText,
        ))
      }
    }
    for (let documentIndex: number = 0; documentIndex < document.blocks.length; documentIndex++) {
      if (!matchedDocumentIndexes.has(documentIndex)) {
        snapshot.unexpectedSourceBlocks = snapshot.unexpectedSourceBlocks + 1
        snapshot.issues.push(ComicTranslationEvaluator.issue(
          ComicTranslationEvaluationIssueCode.UNEXPECTED_SOURCE,
          -1,
          documentIndex,
          '',
          document.blocks[documentIndex].sourceText,
        ))
      }
    }
    return snapshot
  }

  private static validateIdentity(
    document: ComicPageDocument,
    reference: ComicTranslationReferencePage,
  ): void {
    if (document.projectId !== reference.projectId ||
      document.pageIndex !== reference.pageIndex ||
      document.imageHash !== reference.imageHash) {
      throw new Error('Comic translation evaluation identity mismatch')
    }
  }

  private static findSourceBlock(
    documentBlocks: ComicTextBlock[],
    reference: ComicTranslationReferenceBlock,
    matchedDocumentIndexes: Set<number>,
  ): number {
    for (let documentIndex: number = 0; documentIndex < documentBlocks.length; documentIndex++) {
      if (matchedDocumentIndexes.has(documentIndex)) {
        continue
      }
      const actual: string = ComicTranslationEvaluator.normalizeText(
        documentBlocks[documentIndex].sourceText,
      )
      for (let variantIndex: number = 0; variantIndex < reference.sourceVariants.length; variantIndex++) {
        const expected: string = ComicTranslationEvaluator.normalizeText(
          reference.sourceVariants[variantIndex],
        )
        if (expected.length > 0 && actual === expected) {
          return documentIndex
        }
      }
    }
    return -1
  }

  private static hasRequiredTranslationTerms(
    documentBlock: ComicTextBlock,
    reference: ComicTranslationReferenceBlock,
  ): boolean {
    for (let index: number = 0; index < reference.requiredTranslationTerms.length; index++) {
      if (!documentBlock.translatedText.includes(reference.requiredTranslationTerms[index])) {
        return false
      }
    }
    return true
  }

  private static primaryExpectedText(reference: ComicTranslationReferenceBlock): string {
    return reference.sourceVariants.length > 0 ? reference.sourceVariants[0] : ''
  }

  private static normalizeText(value: string): string {
    return value.trim().replace(/\s+/g, '')
  }

  private static issue(
    code: ComicTranslationEvaluationIssueCode,
    referenceIndex: number,
    documentIndex: number,
    expectedText: string,
    actualText: string,
  ): ComicTranslationEvaluationIssue {
    const issue: ComicTranslationEvaluationIssue = new ComicTranslationEvaluationIssue()
    issue.code = code
    issue.referenceIndex = referenceIndex
    issue.documentIndex = documentIndex
    issue.expectedText = expectedText
    issue.actualText = actualText
    return issue
  }
}
