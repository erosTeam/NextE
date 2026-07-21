import { describe, expect, it } from '@ohos/hypium'
import {
  AxiosTextResponse,
  MANGA_TRANSLATOR_UI_EXPORT_PATH,
  MANGA_TRANSLATOR_UI_IMPORT_PATH,
  MangaTranslatorUiSidecarConfig,
  MangaTranslatorUiSidecarConnectionService,
  MangaTranslatorUiSidecarConnectionTransport,
} from 'shared'

class FakeConnectionTransport implements MangaTranslatorUiSidecarConnectionTransport {
  urls: string[] = []
  methods: string[] = []
  headers: Record<string, string>[] = []
  bodies: string[] = []
  response: AxiosTextResponse = new AxiosTextResponse()

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
    return this.response
  }
}

class TestOpenApiOperation {}

class TestOpenApiPath {
  post: TestOpenApiOperation = new TestOpenApiOperation()
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
  return JSON.stringify(envelope)
}

export default function mangaTranslatorUiSidecarConnectionTest(): void {
  describe('MangaTranslatorUiSidecarConnectionService', () => {
    it('checks pinned capabilities without uploading an image', 0, async () => {
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.response.statusCode = 200
      transport.response.body = capabilityJson()

      const result = await MangaTranslatorUiSidecarConnectionService.check(
        config('http://192.168.50.10:5003/'),
        transport,
      )

      expect(result.protocolRevision).assertEqual(1)
      expect(transport.urls[0]).assertEqual('http://192.168.50.10:5003/openapi.json')
      expect(transport.methods[0]).assertEqual('GET')
      expect(transport.bodies[0]).assertEqual('')
      expect(transport.headers[0]['X-Session-Token'])
        .assertEqual('fixture-render-service-session-token')
    })

    it('rejects a service missing the pinned import route', 0, async () => {
      const transport: FakeConnectionTransport = new FakeConnectionTransport()
      transport.response.statusCode = 200
      transport.response.body = capabilityJson(false)
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
      transport.response.statusCode = 200
      transport.response.body = capabilityJson()
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
