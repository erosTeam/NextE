import { AppStorageV2 } from '@kit.ArkUI'

/**
 * A tiny reactive bump emitted when My Tags finish loading, so already-rendered gallery cards re-evaluate
 * their tag colors (eros_fe re-derives tag colors at render via Obx). It is JUST a counter — safe in the
 * V2 observation graph (unlike the lookup Map, which lives in the plain `UserTagStore` singleton).
 *
 * Cards read `version` during build (subscribing) and key their tag chips on it; bumping it after the
 * usertag store is populated forces a re-color without a re-fetch, fixing the cold-start race where the
 * first list parsed before My Tags arrived.
 */
@ObservedV2
export class UserTagSignal {
  @Trace version: number = 0
}

const USERTAG_SIGNAL_KEY: string = 'v2:userTagSignal'

export function connectUserTagSignal(): UserTagSignal {
  return AppStorageV2.connect(UserTagSignal, USERTAG_SIGNAL_KEY, () => new UserTagSignal())!
}
