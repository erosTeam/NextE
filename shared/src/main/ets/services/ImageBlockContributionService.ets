import {
  IMAGE_BLOCK_DEFAULT_THRESHOLD,
  IMAGE_BLOCK_SCOPE_WHOLE,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { PHashService } from './PHashService'

const DEFAULT_LABEL: string = 'scanlator-ad'
const DEFAULT_FEED_ID: string = 'zh-scanlator-ads'
const RULES_REPO_NEW_ISSUE_URL: string = 'https://github.com/erosTeam/nexte-image-block-rules/issues/new'
const RULE_SUBMISSION_TEMPLATE: string = 'rule_submission.yml'
const RULE_SUBMISSION_LABEL: string = 'rule-submission'
const MAX_SOURCE_URL_LENGTH: number = 2048
const MAX_NOTE_LENGTH: number = 200
const MAX_ISSUE_URL_LENGTH: number = 7600

class ImageBlockContributionLine {
  hash: string = ''
  threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  label: string = DEFAULT_LABEL
  scope: string = IMAGE_BLOCK_SCOPE_WHOLE
  sourceUrl: string = ''
  note: string = ''
}

class ImageBlockContributionLineWithPage extends ImageBlockContributionLine {
  sourcePage: number = 0
}

export class ImageBlockContributionDraft {
  hash: string = ''
  threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD
  label: string = DEFAULT_LABEL
  scope: string = IMAGE_BLOCK_SCOPE_WHOLE
  sourceUrl: string = ''
  sourcePage: number = 0
  note: string = ''

  toJsonLine(): string {
    return ImageBlockContributionService.toJsonLine(this)
  }
}

export class ImageBlockContributionBatch {
  drafts: ImageBlockContributionDraft[] = []
  jsonl: string = ''
  totalCount: number = 0
  includedCount: number = 0
  skippedMissingSourceCount: number = 0
  skippedDuplicateHashCount: number = 0
  skippedInvalidCount: number = 0

  skippedCount(): number {
    return this.skippedMissingSourceCount + this.skippedDuplicateHashCount + this.skippedInvalidCount
  }
}

export class ImageBlockContributionIssuePackage {
  title: string = ''
  body: string = ''
  issueUrl: string = ''
  jsonl: string = ''
  includedCount: number = 0
  totalCount: number = 0
  skippedCount: number = 0
  urlTooLong: boolean = false
}

export class ImageBlockContributionService {
  static buildDraftFromRule(
    rule: ImageBlockRule,
    note: string = '',
  ): ImageBlockContributionDraft {
    return ImageBlockContributionService.buildDraft(
      rule.hash,
      rule.sourceUrl,
      note,
      rule.label,
      rule.threshold,
      rule.sourcePage,
    )
  }

  static buildJsonlLineFromRule(rule: ImageBlockRule, note: string = ''): string {
    return ImageBlockContributionService.buildDraftFromRule(rule, note).toJsonLine()
  }

  static buildJsonlLinesFromRules(rules: ImageBlockRule[]): string {
    const lines: string[] = []
    for (let i: number = 0; i < rules.length; i++) {
      lines.push(ImageBlockContributionService.buildJsonlLineFromRule(rules[i]))
    }
    return lines.join('\n')
  }

  static buildSubmissionBatchFromRules(rules: ImageBlockRule[]): ImageBlockContributionBatch {
    const batch: ImageBlockContributionBatch = new ImageBlockContributionBatch()
    batch.totalCount = rules.length
    const seenHashes: string[] = []
    const lines: string[] = []
    for (let i: number = 0; i < rules.length; i++) {
      const rule: ImageBlockRule = rules[i]
      const hash: string = PHashService.normalizeHex64(rule.hash)
      if (hash.length === 0) {
        batch.skippedInvalidCount++
        continue
      }
      if (rule.sourceUrl.trim().length === 0) {
        batch.skippedMissingSourceCount++
        continue
      }
      if (ImageBlockContributionService.cleanSourcePage(rule.sourcePage) <= 0) {
        batch.skippedInvalidCount++
        continue
      }
      if (ImageBlockContributionService.hasSeenHash(seenHashes, hash)) {
        batch.skippedDuplicateHashCount++
        continue
      }
      try {
        const draft: ImageBlockContributionDraft = ImageBlockContributionService.buildDraftFromRule(rule)
        batch.drafts.push(draft)
        lines.push(draft.toJsonLine())
        seenHashes.push(draft.hash)
      } catch (error) {
        batch.skippedInvalidCount++
      }
    }
    batch.jsonl = lines.join('\n')
    batch.includedCount = batch.drafts.length
    return batch
  }

  static buildIssuePackageFromRules(rules: ImageBlockRule[]): ImageBlockContributionIssuePackage {
    return ImageBlockContributionService.buildIssuePackageFromBatch(
      ImageBlockContributionService.buildSubmissionBatchFromRules(rules),
    )
  }

  static buildIssuePackageFromBatch(batch: ImageBlockContributionBatch): ImageBlockContributionIssuePackage {
    const pack: ImageBlockContributionIssuePackage = new ImageBlockContributionIssuePackage()
    pack.jsonl = batch.jsonl
    pack.includedCount = batch.includedCount
    pack.totalCount = batch.totalCount
    pack.skippedCount = batch.skippedCount()
    if (batch.includedCount <= 0 || batch.jsonl.length === 0) {
      return pack
    }
    pack.title = ImageBlockContributionService.issueTitle(batch)
    pack.body = ImageBlockContributionService.issueBody(batch)
    const fullUrl: string = ImageBlockContributionService.issueUrl(batch, pack.title, pack.body)
    if (fullUrl.length > MAX_ISSUE_URL_LENGTH) {
      pack.issueUrl = ImageBlockContributionService.issueUrl(batch, pack.title, '')
      pack.urlTooLong = true
    } else {
      pack.issueUrl = fullUrl
    }
    return pack
  }

  static buildDraft(
    hash: string,
    sourceUrl: string,
    note: string = '',
    label: string = DEFAULT_LABEL,
    threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD,
    sourcePage: number = 0,
  ): ImageBlockContributionDraft {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    if (normalizedHash.length === 0) {
      throw new Error('Image block contribution hash must be 16 lowercase hex characters')
    }
    const draft: ImageBlockContributionDraft = new ImageBlockContributionDraft()
    draft.hash = normalizedHash
    draft.threshold = PHashService.clampThreshold(threshold)
    draft.label = ImageBlockContributionService.cleanLabel(label)
    draft.scope = IMAGE_BLOCK_SCOPE_WHOLE
    draft.sourceUrl = ImageBlockContributionService.sanitizeReviewSourceUrl(sourceUrl)
    draft.sourcePage = ImageBlockContributionService.cleanSourcePage(sourcePage)
    draft.note = ImageBlockContributionService.cleanNote(note)
    return draft
  }

  static buildJsonlLine(
    hash: string,
    sourceUrl: string,
    note: string = '',
    label: string = DEFAULT_LABEL,
    threshold: number = IMAGE_BLOCK_DEFAULT_THRESHOLD,
    sourcePage: number = 0,
  ): string {
    return ImageBlockContributionService.buildDraft(hash, sourceUrl, note, label, threshold, sourcePage).toJsonLine()
  }

  static toJsonLine(draft: ImageBlockContributionDraft): string {
    const sourcePage: number = ImageBlockContributionService.cleanSourcePage(draft.sourcePage)
    if (sourcePage > 0) {
      const line: ImageBlockContributionLineWithPage = new ImageBlockContributionLineWithPage()
      ImageBlockContributionService.fillLine(line, draft)
      line.sourcePage = sourcePage
      return JSON.stringify(line)
    }
    const line: ImageBlockContributionLine = new ImageBlockContributionLine()
    ImageBlockContributionService.fillLine(line, draft)
    return JSON.stringify(line)
  }

  static sanitizeReviewSourceUrl(sourceUrl: string): string {
    let out: string = sourceUrl.trim()
    const fragmentIndex: number = out.indexOf('#')
    if (fragmentIndex >= 0) {
      out = out.substring(0, fragmentIndex)
    }
    if (out.length === 0) {
      throw new Error('Image block contribution sourceUrl is required')
    }
    if (out.length > MAX_SOURCE_URL_LENGTH) {
      throw new Error('Image block contribution sourceUrl is too long')
    }
    if (!out.startsWith('https://') && !out.startsWith('http://')) {
      throw new Error('Image block contribution sourceUrl must be http(s)')
    }
    const forbidden: string = ImageBlockContributionService.firstForbiddenFragment(out.toLowerCase())
    if (forbidden.length > 0) {
      throw new Error('Image block contribution sourceUrl contains unsafe token: ' + forbidden)
    }
    return out
  }

  private static cleanLabel(label: string): string {
    const clean: string = label.trim().replace(/\s+/g, '-')
    return clean.length > 0 ? clean.substring(0, Math.min(clean.length, 48)) : DEFAULT_LABEL
  }

  private static cleanNote(note: string): string {
    const clean: string = note.trim().replace(/\s+/g, ' ')
    return clean.substring(0, Math.min(clean.length, MAX_NOTE_LENGTH))
  }

  private static cleanSourcePage(sourcePage: number): number {
    if (!Number.isFinite(sourcePage) || sourcePage <= 0) {
      return 0
    }
    return Math.floor(sourcePage)
  }

  private static fillLine(line: ImageBlockContributionLine, draft: ImageBlockContributionDraft): void {
    line.hash = PHashService.normalizeHex64(draft.hash)
    if (line.hash.length === 0) {
      throw new Error('Image block contribution hash must be 16 lowercase hex characters')
    }
    line.threshold = PHashService.clampThreshold(draft.threshold)
    line.label = ImageBlockContributionService.cleanLabel(draft.label)
    line.scope = IMAGE_BLOCK_SCOPE_WHOLE
    line.sourceUrl = ImageBlockContributionService.sanitizeReviewSourceUrl(draft.sourceUrl)
    line.note = ImageBlockContributionService.cleanNote(draft.note)
  }

  private static issueTitle(batch: ImageBlockContributionBatch): string {
    if (batch.drafts.length === 1) {
      return 'rule: add pHash ' + batch.drafts[0].hash
    }
    return 'rule: add ' + batch.drafts.length + ' pHash rules'
  }

  private static issueBody(batch: ImageBlockContributionBatch): string {
    const lines: string[] = [
      'NextE app-copied image-block rule draft.',
      '',
      'Feed: ' + DEFAULT_FEED_ID,
      'Rules: ' + batch.includedCount + '/' + batch.totalCount,
      'Skipped: ' + batch.skippedCount(),
      '',
      'Review:',
    ]
    for (let i: number = 0; i < batch.drafts.length; i++) {
      const draft: ImageBlockContributionDraft = batch.drafts[i]
      lines.push(
        '- `' + draft.hash + '` P' + draft.sourcePage + ' ' + draft.sourceUrl,
      )
    }
    lines.push('')
    lines.push('JSONL:')
    lines.push('```jsonl')
    lines.push(batch.jsonl)
    lines.push('```')
    lines.push('')
    lines.push('Maintainer dry run:')
    lines.push('```bash')
    lines.push('node tools/rules.mjs import-jsonl --feed ' + DEFAULT_FEED_ID + ' --file app-draft.jsonl')
    lines.push('```')
    return lines.join('\n')
  }

  private static issueUrl(batch: ImageBlockContributionBatch, title: string, body: string): string {
    let url: string = RULES_REPO_NEW_ISSUE_URL +
      '?title=' + encodeURIComponent(title) +
      '&labels=' + encodeURIComponent(RULE_SUBMISSION_LABEL)
    if (batch.drafts.length === 1) {
      const draft: ImageBlockContributionDraft = batch.drafts[0]
      url +=
        '&template=' + encodeURIComponent(RULE_SUBMISSION_TEMPLATE) +
        '&hash=' + encodeURIComponent(draft.hash) +
        '&source_url=' + encodeURIComponent(draft.sourceUrl) +
        '&source_page=' + encodeURIComponent(draft.sourcePage.toString()) +
        '&note=' + encodeURIComponent(draft.note.length > 0 ? draft.note : 'Repeated full-page scanlator ad.') +
        '&feed=' + encodeURIComponent(DEFAULT_FEED_ID)
      return url
    }
    if (body.length > 0) {
      url += '&body=' + encodeURIComponent(body)
    }
    return url
  }

  private static hasSeenHash(hashes: string[], hash: string): boolean {
    for (let i: number = 0; i < hashes.length; i++) {
      if (hashes[i] === hash) {
        return true
      }
    }
    return false
  }

  private static firstForbiddenFragment(value: string): string {
    const forbidden: string[] = [
      'ipb_member_id',
      'ipb_pass_hash',
      'igneous',
      'cookie=',
      'set-cookie',
      'authorization=',
      'showkey',
      'fullimg.php',
      'nl=',
      'sk=',
      'token=',
      'auth=',
      'password=',
      'passwd=',
      'session=',
      'sid=',
    ]
    for (let i: number = 0; i < forbidden.length; i++) {
      if (value.indexOf(forbidden[i]) >= 0) {
        return forbidden[i]
      }
    }
    return ''
  }
}
