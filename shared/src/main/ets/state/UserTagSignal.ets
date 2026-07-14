import { AppStorageV2 } from '@kit.ArkUI'

/**
 * A tiny reactive bump emitted when My Tags finish loading, so already-rendered gallery cards re-evaluate
 * their tag colors (eros_fe re-derives tag colors at render via Obx). It is JUST a counter — safe in the
 * V2 observation graph (unlike the lookup Map, which lives in the plain `UserTagStore` singleton).
 *
 * Cards read `version` while calculating chip colors, so a My Tags update re-evaluates the existing
 * tag nodes without a re-fetch or a key-based rebuild. This fixes the cold-start race where the first
 * list parsed before My Tags arrived.
 */
@ObservedV2
export class UserTagSignal {
  @Trace version: number = 0
}

// AppStorageV2 validates this key for every rich gallery card that observes My Tags updates.
const USERTAG_SIGNAL_KEY: string = 'v2_userTagSignal'

export function connectUserTagSignal(): UserTagSignal {
  return AppStorageV2.connect(UserTagSignal, USERTAG_SIGNAL_KEY, () => new UserTagSignal())!
}
