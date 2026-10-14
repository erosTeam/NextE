import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import { CookieJarSettings, EhCookieStore, EhHttpClient } from 'shared'

async function downloadContext(): Promise<common.UIAbilityContext> {
  const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function removeFixture(path: string): void {
  if (fileIo.accessSync(path)) {
    fileIo.unlinkSync(path)
  }
}

export default function publicModelDownloadIntegrationTest(): void {
  const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters
  const origin: string = parameters['-s modelDownloadFixture'] ?? ''
  if (origin.length === 0) {
    return
  }
  describe('PublicModelDownloadIntegration', () => {
    it('omits credentials on public native requests and preserves explicit EH authentication', 0, async () => {
      const context = await downloadContext()
      const publicPath: string = context.cacheDir + '/pr8-public-download-fixture.txt'
      const ehPath: string = context.cacheDir + '/pr8-eh-download-fixture.txt'
      const store: EhCookieStore = EhCookieStore.getInstance()
      const original: string = store.serializeForPersist()
      try {
        store.clear()
        store.set('fixture_marker', 'synthetic-pr8')
        await EhHttpClient.getInstance().downloadBinaryToFileInStream(
          origin + '/public', publicPath, (_loaded: number, _total: number): void => {},
          5000, 2000, 'text/plain', 1, 10000, false,
        )
        expect(fileIo.readTextSync(publicPath)).assertEqual('public-no-cookie')
        await EhHttpClient.getInstance().downloadBinaryToFileInStream(
          origin + '/eh', ehPath, (_loaded: number, _total: number): void => {},
          5000, 2000, 'text/plain', 1, 10000,
        )
        expect(fileIo.readTextSync(ehPath)).assertEqual('eh-synthetic-cookie')
      } finally {
        store.clear()
        if (original.length > 0) {
          CookieJarSettings.applyFromHeader(original)
        }
        removeFixture(publicPath)
        removeFixture(ehPath)
      }
    })

    it('terminates a native stream stalled after the first chunk and removes partial output', 0, async () => {
      const context = await downloadContext()
      const path: string = context.cacheDir + '/pr8-stalled-download-fixture.txt'
      let failure: string = ''
      const startedAt: number = Date.now()
      try {
        await EhHttpClient.getInstance().downloadBinaryToFileInStream(
          origin + '/stall', path, (_loaded: number, _total: number): void => {},
          5000, 500, 'text/plain', 1, 10000, false,
        )
      } catch (error) {
        failure = (error as Error).message
      }
      try {
        expect(failure.indexOf('no progress timeout') >= 0).assertEqual(true)
        expect(Date.now() - startedAt < 2500).assertEqual(true)
        expect(fileIo.accessSync(path)).assertEqual(false)
      } finally {
        removeFixture(path)
      }
    })
  })
}
