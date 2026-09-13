/** Read-only evidence for the explicitly enabled debug entry; never owns navigation or pixels. */
export class ReaderTrialEntryFacts {
  epoch: number = 0
  site: string = ''
  galleryId: string = ''
  pageIndex: number = -1
  sourceComponentId: string = ''
  snapshotReady: boolean = false
  snapshotCaptured: boolean = false
  movingObserved: boolean = false
  phase: string = ''
  closed: boolean = true
  windowEvents: string[] = []
}

export class ReaderTrialEntryProbe {
  private static facts: ReaderTrialEntryFacts = new ReaderTrialEntryFacts()

  static begin(epoch: number, site: string, galleryId: string, pageIndex: number,
    sourceComponentId: string, ready: boolean): void {
    const facts = new ReaderTrialEntryFacts()
    facts.epoch = epoch; facts.site = site; facts.galleryId = galleryId; facts.pageIndex = pageIndex
    facts.sourceComponentId = sourceComponentId; facts.snapshotReady = ready
    facts.phase = 'capture'; facts.closed = false
    ReaderTrialEntryProbe.facts = facts
  }

  static captured(epoch: number, captured: boolean): void {
    if (ReaderTrialEntryProbe.facts.epoch === epoch && !ReaderTrialEntryProbe.facts.closed) {
      ReaderTrialEntryProbe.facts.snapshotCaptured = captured
    }
  }

  static phase(epoch: number, phase: string): void {
    const facts = ReaderTrialEntryProbe.facts
    if (facts.epoch !== epoch || facts.closed) return
    facts.phase = phase
    if (phase === 'moving' || phase === 'waiting' || phase === 'revealing' || phase === 'finished') {
      facts.movingObserved = true
    }
  }

  static close(epoch: number): void {
    if (ReaderTrialEntryProbe.facts.epoch === epoch) ReaderTrialEntryProbe.facts.closed = true
  }

  static windowEvent(epoch: number, event: string): void {
    if (ReaderTrialEntryProbe.facts.epoch === epoch) ReaderTrialEntryProbe.facts.windowEvents.push(event)
  }

  static hostRemoved(): void {
    ReaderTrialEntryProbe.facts.windowEvents.push(`${Date.now()} host_clear_requested`)
  }

  static read(): ReaderTrialEntryFacts {
    const source = ReaderTrialEntryProbe.facts
    const facts = new ReaderTrialEntryFacts()
    facts.epoch = source.epoch; facts.site = source.site; facts.galleryId = source.galleryId
    facts.pageIndex = source.pageIndex; facts.sourceComponentId = source.sourceComponentId
    facts.snapshotReady = source.snapshotReady; facts.snapshotCaptured = source.snapshotCaptured
    facts.movingObserved = source.movingObserved; facts.phase = source.phase; facts.closed = source.closed
    facts.windowEvents = source.windowEvents.slice()
    return facts
  }
}
