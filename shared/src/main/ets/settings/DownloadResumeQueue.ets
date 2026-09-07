export class DownloadResumeJob {
  key: string
  cancelled: boolean = false
  run: (job: DownloadResumeJob) => Promise<void>
  completion: Promise<void> = Promise.resolve()

  constructor(key: string, run: (job: DownloadResumeJob) => Promise<void>) {
    this.key = key
    this.run = run
  }
}

/** Manual download starts share a bound, including preparation and archive URL resolution. */
export class DownloadResumeQueue {
  private pending: DownloadResumeJob[] = []
  private active: Map<string, DownloadResumeJob> = new Map<string, DownloadResumeJob>()
  private limit: number = 1
  private changed: () => void

  constructor(changed: () => void = () => {}) {
    this.changed = changed
  }

  enqueue(key: string, limit: number, run: (job: DownloadResumeJob) => Promise<void>): boolean {
    const active: DownloadResumeJob | undefined = this.active.get(key)
    if ((active !== undefined && !active.cancelled) || this.pending.some((job: DownloadResumeJob) => job.key === key)) {
      return false
    }
    this.limit = Math.max(1, Math.floor(limit))
    this.pending.push(new DownloadResumeJob(key, run))
    this.drain()
    return true
  }

  has(key: string): boolean {
    const active: DownloadResumeJob | undefined = this.active.get(key)
    return (active !== undefined && !active.cancelled) || this.pending.some((job: DownloadResumeJob) => job.key === key)
  }

  cancel(key: string): void {
    this.pending = this.pending.filter((job: DownloadResumeJob) => job.key !== key)
    const active: DownloadResumeJob | undefined = this.active.get(key)
    if (active !== undefined) active.cancelled = true
  }

  async wait(key: string): Promise<void> {
    const active: DownloadResumeJob | undefined = this.active.get(key)
    if (active !== undefined) await active.completion
  }

  private drain(): void {
    while (this.active.size < this.limit) {
      const index: number = this.pending.findIndex((job: DownloadResumeJob) => !this.active.has(job.key))
      if (index < 0) return
      const job: DownloadResumeJob = this.pending.splice(index, 1)[0]
      this.active.set(job.key, job)
      // Defer until completion is installed: callers may cancel/wait immediately after enqueue.
      job.completion = Promise.resolve().then(async (): Promise<void> => {
        try {
          if (!job.cancelled) await job.run(job)
        } finally {
          this.active.delete(job.key)
          this.drain()
          this.changed()
        }
      })
    }
  }
}
