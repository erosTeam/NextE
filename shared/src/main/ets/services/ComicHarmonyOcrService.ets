import { image } from '@kit.ImageKit'
import { textRecognition } from '@kit.CoreVisionKit'

export class ComicLocalOcrPoint {
  x: number = 0
  y: number = 0

  constructor(x: number = 0, y: number = 0) {
    this.x = x
    this.y = y
  }
}

export class ComicLocalOcrLine {
  text: string = ''
  polygon: ComicLocalOcrPoint[] = []
}

export class ComicLocalOcrResult {
  lines: ComicLocalOcrLine[] = []
  elapsedMs: number = 0
}

export interface ComicLocalOcrEngine {
  engineId(): string

  revision(): number

  supportedLanguages(): Promise<string[]>

  recognize(pixelMap: image.PixelMap): Promise<ComicLocalOcrResult>
}

/** Device OCR adapter. Calls are serialized because Core Vision OCR owns process-wide model state. */
export class HarmonyComicLocalOcrEngine implements ComicLocalOcrEngine {
  private initialized: boolean = false
  private languageCache: string[] | null = null
  private queue: Promise<void> = Promise.resolve()

  engineId(): string {
    return 'harmony-core-vision-text-recognition'
  }

  revision(): number {
    return 1
  }

  async supportedLanguages(): Promise<string[]> {
    if (this.languageCache !== null) {
      return this.languageCache.slice()
    }
    const values: string[] = await textRecognition.getSupportedLanguages()
    const normalized: string[] = []
    const seen: Set<string> = new Set<string>()
    for (let index: number = 0; index < values.length; index++) {
      const value: string = values[index].trim()
      if (value.length > 0 && !seen.has(value)) {
        seen.add(value)
        normalized.push(value)
      }
    }
    this.languageCache = normalized
    return normalized.slice()
  }

  recognize(pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    const task: Promise<ComicLocalOcrResult> = this.queue.then(
      async (): Promise<ComicLocalOcrResult> => this.recognizeSerial(pixelMap),
    )
    this.queue = task.then(
      (): void => {},
      (): void => {},
    )
    return task
  }

  async release(): Promise<void> {
    await this.queue
    if (this.initialized) {
      await textRecognition.release()
      this.initialized = false
    }
  }

  private async recognizeSerial(pixelMap: image.PixelMap): Promise<ComicLocalOcrResult> {
    if (!this.initialized) {
      const initialized: boolean = await textRecognition.init()
      if (!initialized) {
        throw new Error('Harmony device OCR initialization failed')
      }
      this.initialized = true
    }
    const startedAt: number = Date.now()
    const raw: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText({ pixelMap: pixelMap }, {
        isDirectionDetectionSupported: true,
      })
    const result: ComicLocalOcrResult = new ComicLocalOcrResult()
    result.elapsedMs = Math.max(0, Date.now() - startedAt)
    for (let blockIndex: number = 0; blockIndex < raw.blocks.length; blockIndex++) {
      const rawBlock: textRecognition.TextBlock = raw.blocks[blockIndex]
      for (let lineIndex: number = 0; lineIndex < rawBlock.lines.length; lineIndex++) {
        const rawLine: textRecognition.TextLine = rawBlock.lines[lineIndex]
        const text: string = rawLine.value.trim()
        if (text.length <= 0 || rawLine.cornerPoints.length < 3) {
          continue
        }
        const line: ComicLocalOcrLine = new ComicLocalOcrLine()
        line.text = text
        for (let pointIndex: number = 0; pointIndex < rawLine.cornerPoints.length; pointIndex++) {
          const point: textRecognition.PixelPoint = rawLine.cornerPoints[pointIndex]
          line.polygon.push(new ComicLocalOcrPoint(point.x, point.y))
        }
        result.lines.push(line)
      }
    }
    return result
  }
}
