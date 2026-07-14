import { AppStorageV2 } from '@kit.ArkUI'
import { CustomProfile } from '../model/CustomProfile'

/**
 * The ordered list of user-defined home sub-tabs + the selected tab. CustomProfilesSettings is the
 * single writer (restore/CRUD/reorder). The home sub-tab bar maps the non-hidden, login-gated profiles
 * to TabItem[]; the retained Swiper keys on profile.uuid.
 *
 * @Trace ARRAY rule: writers REASSIGN `profiles` (`state.profiles = next`) — never mutate in place — so
 * observers (the bar) re-render; a renamed/hidden profile becomes a new TabItem with a new ForEach key.
 */
@ObservedV2
export class CustomProfilesState {
  @Trace profiles: CustomProfile[] = []
  @Trace selectedUuid: string = ''

  /** The profile with this uuid, or null. */
  findByUuid(uuid: string): CustomProfile | null {
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].uuid === uuid) {
        return this.profiles[i]
      }
    }
    return null
  }
}

const CUSTOM_PROFILES_KEY: string = 'v2_customProfiles'

/** App-wide CustomProfilesState singleton from AppStorageV2. */
export function connectCustomProfiles(): CustomProfilesState {
  return AppStorageV2.connect(
    CustomProfilesState,
    CUSTOM_PROFILES_KEY,
    () => new CustomProfilesState(),
  )!
}
