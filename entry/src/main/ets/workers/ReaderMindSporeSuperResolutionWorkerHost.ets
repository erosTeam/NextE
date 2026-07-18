import { ThreadWorkerPriority, worker } from '@kit.ArkTS'
import {
  ReaderMindSporeSuperResolution,
  ReaderMindSporeSuperResolutionWorkerFactory,
} from 'shared'

class EntryReaderMindSporeWorkerFactory
  implements ReaderMindSporeSuperResolutionWorkerFactory {
  create(): worker.ThreadWorker {
    return new worker.ThreadWorker(
      'entry/ets/workers/ReaderMindSporeSuperResolutionWorker.ets', {
      name: 'reader_super_resolution_nnrt',
      priority: ThreadWorkerPriority.LOW,
      },
    )
  }
}

export function installReaderMindSporeSuperResolutionWorkerFactory(): void {
  ReaderMindSporeSuperResolution.configureWorkerFactory(
    new EntryReaderMindSporeWorkerFactory(),
  )
}
