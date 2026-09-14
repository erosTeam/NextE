import { ReaderParams } from 'shared'

/**
 * NextE-owned input for the shared Reader host. Production and Lab requests
 * satisfy the same narrow contract, while failure injection stays Debug-only.
 */
export interface NextEReaderHostRequest {
  work: string
  unit: string
  pageIndex: number
  pageIndexProvided: boolean
  failurePage: number
  assetFailureMessage: string
  delayedMetricsPage: number
  failureLayout: string
  readingChrome: boolean
  thumbnailFailurePage: number
  volumeKeys: boolean
  volumeKeysOverride: boolean | null
  pageTurnAnimationOverride: boolean | null
  shareProbe: string
  informationProbe: string
  originalVariantProbe: string
  cropBorders: boolean
  progressReadWrite: boolean
  preferencesReadWrite: boolean
  thumbnailEntry: boolean
  entryLayout: string
  entryDirection: string
  entryLayoutOverride: string | null
  entryDirectionOverride: string | null
  rotateWidePagesOverride: boolean | null
  entryProbe: string
  chapterProbe: string
  productionSources?: boolean
}

/** Ordinary NextE route request. No Lab probe or layout override is enabled. */
export class NextEProductionReaderRequest implements NextEReaderHostRequest {
  work: string
  unit: string
  pageIndex: number
  pageIndexProvided: boolean = true
  failurePage: number = -1
  assetFailureMessage: string = ''
  delayedMetricsPage: number = -1
  failureLayout: string = 'continuous'
  readingChrome: boolean = true
  thumbnailFailurePage: number = -1
  volumeKeys: boolean = false
  volumeKeysOverride: boolean | null = null
  pageTurnAnimationOverride: boolean | null = null
  shareProbe: string = ''
  informationProbe: string = ''
  originalVariantProbe: string = ''
  cropBorders: boolean = false
  progressReadWrite: boolean = true
  preferencesReadWrite: boolean = true
  thumbnailEntry: boolean = false
  entryLayout: string = 'single'
  entryDirection: string = 'ltr'
  entryLayoutOverride: string | null = null
  entryDirectionOverride: string | null = null
  rotateWidePagesOverride: boolean | null = null
  entryProbe: string = ''
  chapterProbe: string = ''
  productionSources: boolean = true

  constructor(params: ReaderParams) {
    this.work = params.gid
    this.unit = params.token
    this.pageIndex = Math.max(0, Math.floor(params.index))
  }
}
