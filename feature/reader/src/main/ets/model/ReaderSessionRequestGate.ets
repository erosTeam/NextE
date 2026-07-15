/**
 * Immutable ownership token for one Reader gallery session.
 *
 * A retained ReaderViewModel can begin loading gallery B before requests from gallery A return.
 * Snapshot the gallery identity at dispatch time so old preview/image work cannot merge into the
 * newer session after an await.
 */
export class ReaderSessionRequest {
  epoch: number
  gid: string
  token: string
  isEx: boolean
  sourceKey: string

  constructor(epoch: number, gid: string, token: string, isEx: boolean, sourceKey: string = '') {
    this.epoch = epoch
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.sourceKey = sourceKey
  }
}

/** Per-ReaderViewModel generation fence for gallery-scoped asynchronous work. */
export class ReaderSessionRequestGate {
  private epoch: number = 0
  private gid: string = ''
  private token: string = ''
  private isEx: boolean = false
  private sourceKey: string = ''

  begin(gid: string, token: string, isEx: boolean, sourceKey: string = ''): ReaderSessionRequest {
    this.epoch = this.epoch + 1
    this.gid = gid
    this.token = token
    this.isEx = isEx
    this.sourceKey = sourceKey
    return this.current()
  }

  current(): ReaderSessionRequest {
    return new ReaderSessionRequest(this.epoch, this.gid, this.token, this.isEx, this.sourceKey)
  }

  isCurrent(request: ReaderSessionRequest): boolean {
    return request.epoch === this.epoch &&
      request.gid === this.gid &&
      request.token === this.token &&
      request.isEx === this.isEx &&
      request.sourceKey === this.sourceKey
  }
}
