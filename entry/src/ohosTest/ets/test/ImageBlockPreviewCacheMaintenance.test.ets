import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import { ImageBlockPreviewCacheService } from 'shared'

const TEST_CACHE_SUFFIX: string = 'ohos-test-image-block-preview-maintenance'
const PREVIEW_COUNT: number = 129

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

function writePreview(path: string): number {
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

export default function imageBlockPreviewCacheMaintenanceTest(): void {
  describe('ImageBlockPreviewCache maintenance', () => {
    it('keeps generated preview crops bounded with batched maintenance', 0, async (done: Function) => {
      const context = isolatedCacheContext(await appContext())
      try {
        await ImageBlockPreviewCacheService.clear(context)
        for (let index: number = 0; index < PREVIEW_COUNT; index++) {
          const path = ImageBlockPreviewCacheService.filePath(context, `preview-${index}.jpg`)
          const bytes = writePreview(path)
          await ImageBlockPreviewCacheService.pruneAfterStore(context, path, bytes)
        }
        const stat = await ImageBlockPreviewCacheService.stat(context)
        expect(stat.count).assertEqual(128)
        expect(stat.bytes > 0).assertEqual(true)
      } finally {
        await ImageBlockPreviewCacheService.clear(context)
      }
      done()
    })
  })
}
