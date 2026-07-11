import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import { CachedImageFileService } from 'shared'

const TEST_CACHE_SUFFIX: string = 'ohos-test-cached-image-file-maintenance'
const IMAGE_COUNT: number = 257

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function isolatedCacheContext(host: common.UIAbilityContext): common.UIAbilityContext {
  return {
    cacheDir: `${host.cacheDir}/${TEST_CACHE_SUFFIX}`,
  } as common.UIAbilityContext
}

function writeImage(path: string): number {
  let file: fileIo.File | null = null
  try {
    file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    return fileIo.writeSync(file.fd, 'x')
  } finally {
    if (file) {
      try {
        fileIo.closeSync(file)
      } catch (_error) {}
    }
  }
}

export default function cachedImageFileMaintenanceTest(): void {
  describe('CachedImageFileService maintenance', () => {
    it('keeps recovery thumbnails bounded without evicting the current store', 0, async (done: Function) => {
      const context = isolatedCacheContext(await appContext())
      let newestPath: string = ''
      try {
        await CachedImageFileService.clear(context)
        for (let index: number = 0; index < IMAGE_COUNT; index++) {
          const path = CachedImageFileService.filePath(context, '', `fallback-${index}`)
          const bytes = writeImage(path)
          await CachedImageFileService.pruneAfterStore(context, path, bytes)
          newestPath = path
        }
        const stat = await CachedImageFileService.stat(context)
        expect(stat.count).assertEqual(256)
        expect(stat.bytes > 0).assertEqual(true)
        expect(fileIo.statSync(newestPath).size > 0).assertEqual(true)
      } finally {
        await CachedImageFileService.clear(context)
      }
      done()
    })
  })
}
