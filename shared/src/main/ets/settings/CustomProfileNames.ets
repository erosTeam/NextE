import { AppStrings } from '../i18n/AppStrings'
import {
  BUILTIN_DEFAULT_UUID, BUILTIN_POPULAR_UUID, BUILTIN_WATCHED_UUID,
  STARTER_CHINESE_UUID, STARTER_ANTHOLOGY_UUID,
} from '../model/CustomProfile'

/** Resource lookup failures are not valid persisted profile names. */
export class CustomProfileNames {
  static resourceKey(uuid: string): string {
    if (uuid === BUILTIN_DEFAULT_UUID) return 'home_source_default'
    if (uuid === BUILTIN_POPULAR_UUID) return 'home_source_popular'
    if (uuid === BUILTIN_WATCHED_UUID) return 'home_source_watched'
    if (uuid === STARTER_CHINESE_UUID) return 'tab_seed_chinese'
    if (uuid === STARTER_ANTHOLOGY_UUID) return 'tab_seed_anthology'
    return ''
  }

  static defaultName(key: string): string {
    const name: string = AppStrings.get(key)
    if (name.length === 0 || name === key) {
      throw new Error('Profile name resource unavailable: ' + key)
    }
    return name
  }

  static repair(uuid: string, name: string): string {
    const key: string = CustomProfileNames.resourceKey(uuid)
    return key.length > 0 && name === key ? CustomProfileNames.defaultName(key) : name
  }

  static assertPersistable(uuid: string, name: string): void {
    const key: string = CustomProfileNames.resourceKey(uuid)
    if (key.length > 0 && name === key) {
      throw new Error('Unresolved profile name resource: ' + key)
    }
  }
}
