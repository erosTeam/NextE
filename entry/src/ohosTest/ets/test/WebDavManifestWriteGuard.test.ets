import { describe, expect, it } from '@ohos/hypium'
import { WebDavManifestWriteGuard, WebDavRemoteText } from 'shared'

function remote(exists: boolean, etag: string = ''): WebDavRemoteText {
  const out: WebDavRemoteText = new WebDavRemoteText()
  out.exists = exists
  out.etag = etag
  return out
}

export default function webDavManifestWriteGuardTest(): void {
  describe('WebDAV manifest write guard', () => {
    it('creates missing manifests conditionally and replaces versioned manifests with If-Match', 0, (done: Function) => {
      const create = WebDavManifestWriteGuard.precondition(remote(false))
      expect(create.ifNoneMatch).assertEqual('*')
      expect(create.ifMatch).assertEqual('')

      const replace = WebDavManifestWriteGuard.precondition(remote(true, '"v2"'))
      expect(replace.ifMatch).assertEqual('"v2"')
      expect(replace.ifNoneMatch).assertEqual('')

      const fallback = WebDavManifestWriteGuard.precondition(remote(true))
      expect(fallback.ifMatch).assertEqual('')
      expect(fallback.ifNoneMatch).assertEqual('')
      done()
    })

    it('retries only WebDAV conflict responses', 0, (done: Function) => {
      expect(WebDavManifestWriteGuard.isConflictStatus(409)).assertEqual(true)
      expect(WebDavManifestWriteGuard.isConflictStatus(412)).assertEqual(true)
      expect(WebDavManifestWriteGuard.isConflictStatus(404)).assertEqual(false)
      expect(WebDavManifestWriteGuard.isConflictStatus(500)).assertEqual(false)
      done()
    })
  })
}
