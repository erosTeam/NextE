export class WebDavRemoteText {
  body: string = ''
  exists: boolean = false
  etag: string = ''
}

export class WebDavManifestWritePrecondition {
  ifMatch: string = ''
  ifNoneMatch: string = ''
}

export class WebDavManifestWriteGuard {
  static precondition(remote: WebDavRemoteText): WebDavManifestWritePrecondition {
    const out: WebDavManifestWritePrecondition = new WebDavManifestWritePrecondition()
    if (!remote.exists) {
      out.ifNoneMatch = '*'
      return out
    }
    if (remote.etag.length > 0) {
      out.ifMatch = remote.etag
    }
    return out
  }

  static isConflictStatus(statusCode: number): boolean {
    return statusCode === 409 || statusCode === 412
  }
}
