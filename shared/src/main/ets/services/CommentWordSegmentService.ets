import { textProcessing } from '@kit.NaturalLanguageKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

/**
 * One segment from the engine's ICU word segmenter. The project compiles against the ES2021 lib, whose
 * declarations stop before `Intl.Segmenter`, and ArkTS rejects both namespace declaration merging and a
 * namespace used as an object, so the segmenter is reached through `globalThis` with these local types.
 */
interface IcuSegment {
  segment: string
  isWordLike?: boolean
}

interface IcuSegments {
  [Symbol.iterator](): Iterator<IcuSegment>
}

/** Local word segmentation. Prefer the Chinese platform dictionary and ICU for Japanese. */
export class CommentWordSegmentService {
  private static readonly PLATFORM_INPUT_LIMIT: number = 1000
  private static readonly KANA_RE: RegExp = /[\u3040-\u309F\u30A0-\u30FF]/
  private static readonly HAS_CONTENT_RE: RegExp = /[\p{L}\p{N}]/u
  private static readonly TOKEN_SPLIT_RE: RegExp = /[\s\p{P}\p{S}]+/u

  /** Keep every word occurrence in source order; only punctuation and whitespace are omitted. */
  static async segment(content: string): Promise<string[]> {
    if (content.trim().length === 0) {
      return []
    }
    const out: string[] = []
    // The platform limit applies per call. Process the remaining text instead of dropping the tail.
    let offset: number = 0
    while (offset < content.length) {
      let end: number = Math.min(offset + CommentWordSegmentService.PLATFORM_INPUT_LIMIT, content.length)
      if (end < content.length) {
        const slice: string = content.substring(offset, end)
        const boundary: number = Math.max(slice.lastIndexOf('\n'), slice.lastIndexOf('。'),
          slice.lastIndexOf('！'), slice.lastIndexOf('？'), slice.lastIndexOf(' '))
        if (boundary >= 0) {
          end = offset + boundary + 1
        } else if (/[\uD800-\uDBFF]/.test(content.charAt(end - 1))) {
          end--
        }
      }
      const source: string = content.substring(offset, end)
      let raw: string[] = []
      let tier: string = 'icu'
      if (!CommentWordSegmentService.KANA_RE.test(source)) {
        raw = await CommentWordSegmentService.segmentByPlatform(source)
        tier = 'platform'
      }
      if (raw.length === 0) {
        raw = CommentWordSegmentService.segmentByIcu(source)
        tier = 'icu'
      }
      if (raw.length === 0) {
        raw = CommentWordSegmentService.segmentBySplit(source)
        tier = 'split'
      }
      const words: string[] = CommentWordSegmentService.completeWords(source, raw)
      out.push(...words)
      DiagnosticLogger.info('local_block', 'word_tokens',
        `tier=${tier} offset=${offset} chars=${source.length} tokens=${words.length}`)
      offset = end
    }
    return out
  }

  /** Preserve meaningful spans an engine skipped; never remove single-character words or numbers. */
  private static completeWords(source: string, raw: string[]): string[] {
    const out: string[] = []
    let offset: number = 0
    for (const piece of raw) {
      const word: string = piece.trim()
      if (word.length === 0) {
        continue
      }
      const start: number = source.indexOf(word, offset)
      if (start < 0) {
        continue
      }
      out.push(...CommentWordSegmentService.segmentBySplit(source.substring(offset, start)))
      if (CommentWordSegmentService.HAS_CONTENT_RE.test(word)) {
        out.push(word)
      }
      offset = start + word.length
    }
    out.push(...CommentWordSegmentService.segmentBySplit(source.substring(offset)))
    return out
  }

  /** ICU word segmentation through the engine's `Intl.Segmenter`; a missing constructor is normal. */
  private static segmentByIcu(content: string): string[] {
    const out: string[] = []
    try {
      const globalApi: ESObject = globalThis
      const intlApi: ESObject = globalApi.Intl
      if (intlApi === undefined || intlApi === null) {
        return out
      }
      const ctor: ESObject = intlApi.Segmenter
      if (ctor === undefined || ctor === null) {
        return out
      }
      const locale: string = CommentWordSegmentService.KANA_RE.test(content) ? 'ja' : 'zh'
      const segmenter: ESObject = new ctor(locale, { granularity: 'word' })
      const segments: IcuSegments = segmenter.segment(content) as IcuSegments
      for (const piece of segments) {
        if (piece !== undefined && typeof piece.segment === 'string') {
          out.push(piece.segment)
        }
      }
    } catch (error) {
      DiagnosticLogger.warn(
        'local_block',
        'segment_icu_failed',
        (error as BusinessError).message || 'unknown',
      )
    }
    return out
  }

  /** Official segmenter; unavailable inputs (unsupported language, simulator, service error) yield nothing. */
  private static async segmentByPlatform(content: string): Promise<string[]> {
    const out: string[] = []
    try {
      const segments: textProcessing.WordSegment[] = await textProcessing.getWordSegment(content)
      for (let i: number = 0; i < segments.length; i++) {
        const segment: textProcessing.WordSegment = segments[i]
        if (segment !== undefined && typeof segment.word === 'string') {
          out.push(segment.word)
        }
      }
    } catch (error) {
      DiagnosticLogger.warn(
        'local_block',
        'segment_platform_failed',
        `code=${(error as BusinessError).code} msg=${(error as BusinessError).message}`,
      )
    }
    return out
  }

  /** Offline split by whitespace and punctuation; crude for CJK, so it only runs when nothing else worked. */
  private static segmentBySplit(content: string): string[] {
    const out: string[] = []
    const pieces: string[] = content.split(CommentWordSegmentService.TOKEN_SPLIT_RE)
    for (let i: number = 0; i < pieces.length; i++) {
      const piece: string = pieces[i].trim()
      if (CommentWordSegmentService.HAS_CONTENT_RE.test(piece)) {
        out.push(piece)
      }
    }
    return out
  }

}
