import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH,
  MangaRenderingServiceCredential,
  MangaTranslatorUiSessionRequest,
  MangaTranslatorUiSidecarSessionService,
  MangaTranslatorUiSidecarSessionTransport,
} from 'shared'

class FakeSessionTransport implements MangaTranslatorUiSidecarSessionTransport {
  urls: string[] = []
  bodies: string[] = []
  responses: AxiosTextResponse[] = []
  private responseIndex: number = 0

  async requestText(
    url: string,
    _method: string,
    _headers: Record<string, string>,
    body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    this.urls.push(url)
    this.bodies.push(body)
    if (this.responseIndex >= this.responses.length) {
      throw new Error('Unexpected fake login request')
    }
    const response: AxiosTextResponse = this.responses[this.responseIndex]
    this.responseIndex++
    return response
  }
}

function textResponse(statusCode: number, body: string): AxiosTextResponse {
  const response: AxiosTextResponse = new AxiosTextResponse()
  response.statusCode = statusCode
  response.body = body
  return response
}

function accountRequest(): MangaTranslatorUiSessionRequest {
  const request: MangaTranslatorUiSessionRequest = new MangaTranslatorUiSessionRequest()
  request.baseUrl = 'http://127.0.0.1:5003'
  request.username = 'fixture-user'
  request.password = 'fixture-password'
  return request
}

export default function mangaTranslatorUiSidecarSessionTest(): void {
  describe('MangaTranslatorUiSidecarSessionService', () => {
    it('deduplicates login and replaces only the rejected cached session', 0, async () => {
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
      const transport: FakeSessionTransport = new FakeSessionTransport()
      transport.responses.push(textResponse(
        200,
        '{"success":true,"token":"fixture-session-one","must_change_password":false}',
      ))
      transport.responses.push(textResponse(
        200,
        '{"success":true,"token":"fixture-session-two","must_change_password":false}',
      ))
      const request: MangaTranslatorUiSessionRequest = accountRequest()
      const first: string[] = await Promise.all([
        MangaTranslatorUiSidecarSessionService.acquire(request, transport),
        MangaTranslatorUiSidecarSessionService.acquire(request, transport),
      ])
      expect(first[0]).assertEqual('fixture-session-one')
      expect(first[1]).assertEqual('fixture-session-one')
      expect(transport.urls.length).assertEqual(1)
      expect(transport.urls[0].endsWith(MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH)).assertTrue()
      expect(transport.bodies[0].includes('fixture-user')).assertTrue()

      MangaTranslatorUiSidecarSessionService.invalidate(request, 'another-session')
      expect(await MangaTranslatorUiSidecarSessionService.acquire(request, transport))
        .assertEqual('fixture-session-one')
      MangaTranslatorUiSidecarSessionService.invalidate(request, 'fixture-session-one')
      expect(await MangaTranslatorUiSidecarSessionService.acquire(request, transport))
        .assertEqual('fixture-session-two')
      expect(transport.urls.length).assertEqual(2)
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
    })

    it('keeps old manual tokens readable without a login request', 0, async () => {
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
      const transport: FakeSessionTransport = new FakeSessionTransport()
      const request: MangaTranslatorUiSessionRequest = new MangaTranslatorUiSessionRequest()
      request.baseUrl = 'http://127.0.0.1:5003'
      request.legacySessionToken = 'legacy-fixture-token'
      expect(await MangaTranslatorUiSidecarSessionService.acquire(request, transport))
        .assertEqual('legacy-fixture-token')
      expect(transport.urls.length).assertEqual(0)
    })

    it('serializes account credentials and rejects incomplete login data', 0, async () => {
      const credential: MangaRenderingServiceCredential =
        MangaRenderingServiceCredential.account('fixture-user', 'fixture-password')
      const stored: string = MangaRenderingServiceCredential.serialize(credential)
      const restored: MangaRenderingServiceCredential =
        MangaRenderingServiceCredential.parseStored(stored)
      expect(restored.username).assertEqual('fixture-user')
      expect(restored.password).assertEqual('fixture-password')
      expect(restored.legacySessionToken).assertEqual('')
      expect(MangaRenderingServiceCredential.parseStored('legacy-token').hasLegacySession())
        .assertTrue()

      const transport: FakeSessionTransport = new FakeSessionTransport()
      transport.responses.push(textResponse(200, '{"success":false}'))
      let rejected: boolean = false
      try {
        await MangaTranslatorUiSidecarSessionService.acquire(accountRequest(), transport)
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
    })
  })
}
