/** A published application release that can be shown in the release-notes browser. */
export class AppRelease {
  tagName: string = ''
  body: string = ''
  htmlUrl: string = ''
  publishedAt: string = ''
  prerelease: boolean = false

  copy(): AppRelease {
    const next: AppRelease = new AppRelease()
    next.tagName = this.tagName
    next.body = this.body
    next.htmlUrl = this.htmlUrl
    next.publishedAt = this.publishedAt
    next.prerelease = this.prerelease
    return next
  }

  version(): string {
    return AppRelease.normalizeVersion(this.tagName)
  }

  static normalizeVersion(value: string): string {
    let out: string = value.trim()
    if (out.startsWith('v') || out.startsWith('V')) {
      out = out.substring(1)
    }
    const plus: number = out.indexOf('+')
    if (plus >= 0) {
      out = out.substring(0, plus)
    }
    const dash: number = out.indexOf('-')
    if (dash >= 0) {
      out = out.substring(0, dash)
    }
    return out.trim()
  }
}

/** Persistable stale-while-revalidate release-history snapshot. */
export class AppReleaseCacheSnapshot {
  releases: AppRelease[] = []
  etag: string = ''
  checkedAt: number = 0

  copy(): AppReleaseCacheSnapshot {
    const next: AppReleaseCacheSnapshot = new AppReleaseCacheSnapshot()
    for (let i: number = 0; i < this.releases.length; i++) {
      next.releases.push(this.releases[i].copy())
    }
    next.etag = this.etag
    next.checkedAt = this.checkedAt
    return next
  }
}
