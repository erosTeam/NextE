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

  constructor(epoch: number, gid: string, token: string, isEx: boolean) {
    this.epoch = epoch
    this.gid = gid
    this.token = token
    this.isEx = isEx
  }
}

/** Per-ReaderViewModel generation fence for gallery-scoped asynchronous work. */
export class ReaderSessionRequestGate {
  private epoch: number = 0
  private gid: string = ''
  private token: string = ''
  private isEx: boolean = false

  begin(gid: string, token: string, isEx: boolean): ReaderSessionRequest {
    this.epoch = this.epoch + 1
    this.gid = gid
    this.token = token
    this.isEx = isEx
    return this.current()
  }

  current(): ReaderSessionRequest {
    return new ReaderSessionRequest(this.epoch, this.gid, this.token, this.isEx)
  }

  isCurrent(request: ReaderSessionRequest): boolean {
    return request.epoch === this.epoch &&
      request.gid === this.gid &&
      request.token === this.token &&
      request.isEx === this.isEx
  }
}
