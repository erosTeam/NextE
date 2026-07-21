import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH,
  MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MANGA_TRANSLATOR_UI_PROTOCOL_REVISION,
  MangaTranslatorUiSidecarConfig,
  MangaTranslatorUiSidecarConnectionService,
  MangaTranslatorUiSidecarConnectionTransport,
  MangaTranslatorUiSidecarSessionService,
} from 'shared'

class FakeConnectionTransport implements MangaTranslatorUiSidecarConnectionTransport {
  urls: string[] = []
  methods: string[] = []
  headers: Record<string, string>[] = []
  bodies: string[] = []
  responses: AxiosTextResponse[] = []
  private responseIndex: number = 0

  async requestText(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    _connectTimeoutMs: number,
    _readTimeoutMs: number,
  ): Promise<AxiosTextResponse> {
    this.urls.push(url)
    this.methods.push(method)
    this.headers.push(headers)
    this.bodies.push(body)
    if (this.responseIndex >= this.responses.length) {
      throw new Error('Unexpected fake connection request')
    }
    const response: AxiosTextResponse = this.responses[this.responseIndex]
    this.responseIndex++
    return response
  }
}

class TestOpenApiOperation {}

class TestOpenApiPath {
  post: TestOpenApiOperation = new TestOpenApiOperation()
  get: TestOpenApiOperation = new TestOpenApiOperation()
}

class TestOpenApiEnvelope {
  paths: Record<string, TestOpenApiPath> = {}
}

function config(baseUrl: string): MangaTranslatorUiSidecarConfig {
  const value: MangaTranslatorUiSidecarConfig = new MangaTranslatorUiSidecarConfig()
  value.baseUrl = baseUrl
  value.sessionToken = 'fixture-render-service-session-token'
  return value
}

function capabilityJson(includeImport: boolean = true): string {
  const envelope: TestOpenApiEnvelope = new TestOpenApiEnvelope()
  envelope.paths[MANGA_TRANSLATOR_UI_EXPORT_PATH] = new TestOpenApiPath()
  if (includeImport) {
    envelope.paths[MANGA_TRANSLATOR_UI_IMPORT_PATH] = new TestOpenApiPath()
  }
  envelope.paths[MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH] = new TestOpenApiPath()
  envelope.paths[MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH] = new TestOpenApiPath()
  return JSON.stringify(envelope)
}

function response(statusCode: number, body: string): AxiosTextResponse {
  const value: AxiosTextResponse = new AxiosTextResponse()
  value.statusCode = statusCode
  value.body = body
  return value
}

export default function mangaTranslatorUiSidecarConnectionTest(): void {
  describe('MangaTranslatorUiSidecarConnectionService', () => {
    it('checks pinned capabilities without uploading an image', 0, async () => {
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.responses.push(response(200, capabilityJson()))
      transport.responses.push(response(200, '{"valid":true}'))

      const result = await MangaTranslatorUiSidecarConnectionService.check(
        config('http://192.168.50.10:5003/'),
        transport,
      )

      expect(result.protocolRevision).assertEqual(MANGA_TRANSLATOR_UI_PROTOCOL_REVISION)
      expect(transport.urls[0]).assertEqual('http://192.168.50.10:5003/openapi.json')
      expect(transport.methods[0]).assertEqual('GET')
      expect(transport.bodies[0]).assertEqual('')
      expect(transport.headers[0]['X-Session-Token'] === undefined).assertTrue()
      expect(transport.urls[1]).assertEqual('http://192.168.50.10:5003' +
        MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH)
      expect(transport.headers[1]['X-Session-Token'])
        .assertEqual('fixture-render-service-session-token')
    })

    it('logs in with account credentials before validating the session', 0, async () => {
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.responses.push(response(200, capabilityJson()))
      transport.responses.push(response(
        200,
        '{"success":true,"token":"fresh-fixture-token","must_change_password":false}',
      ))
      transport.responses.push(response(200, '{"valid":true}'))
      const value: MangaTranslatorUiSidecarConfig = new MangaTranslatorUiSidecarConfig()
      value.baseUrl = 'http://127.0.0.1:5003'
      value.username = 'fixture-user'
      value.password = 'fixture-password'

      await MangaTranslatorUiSidecarConnectionService.check(value, transport)

      expect(transport.urls[1]).assertEqual('http://127.0.0.1:5003' +
        MANGA_TRANSLATOR_UI_AUTH_LOGIN_PATH)
      expect(transport.methods[1]).assertEqual('POST')
      expect(transport.urls[2]).assertEqual('http://127.0.0.1:5003' +
        MANGA_TRANSLATOR_UI_AUTH_CHECK_PATH)
      expect(transport.headers[2]['X-Session-Token']).assertEqual('fresh-fixture-token')
      MangaTranslatorUiSidecarSessionService.clearCachedSessions()
    })

    it('rejects a service missing the pinned import route', 0, async () => {
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.responses.push(response(200, capabilityJson(false)))
      let rejected: boolean = false
      try {
        await MangaTranslatorUiSidecarConnectionService.check(
          config('http://127.0.0.1:5003'),
          transport,
        )
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })

    it('rejects public HTTP before making a request', 0, async () => {
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.responses.push(response(200, capabilityJson()))
      let rejected: boolean = false
      try {
        await MangaTranslatorUiSidecarConnectionService.check(
          config('http://example.com:5003'),
          transport,
        )
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
      expect(transport.urls.length).assertEqual(0)
    })
  })
}
