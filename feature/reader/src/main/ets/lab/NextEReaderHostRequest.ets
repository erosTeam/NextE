import { ReaderParams } from 'shared'

/** NextE-owned production/session input for the shared Reader host. */
export interface NextEReaderHostRequest {
  work: string
  unit: string
  pageIndex: number
  pageIndexProvided: boolean
  readingChrome: boolean
  progressReadWrite: boolean
  preferencesReadWrite: boolean
  productionSources?: boolean
}

/** Ordinary NextE route request. Debug probes are supplied through a separate Lab input. */
export class NextEProductionReaderRequest implements NextEReaderHostRequest {
  work: string
  unit: string
  pageIndex: number
  pageIndexProvided: boolean = true
  readingChrome: boolean = true
  progressReadWrite: boolean = true
  preferencesReadWrite: boolean = true
  productionSources: boolean = true

  constructor(params: ReaderParams) {
    this.work = params.gid
    this.unit = params.token
    this.pageIndex = Math.max(0, Math.floor(params.index))
  }
}
