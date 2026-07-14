import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class HomeTabAutoHideState {
  @Trace autoHide: boolean = true
}

const HOME_TAB_AUTO_HIDE_V2_KEY: string = 'v2_homeTabAutoHide'

export function connectHomeTabAutoHide(): HomeTabAutoHideState {
  return AppStorageV2.connect(HomeTabAutoHideState, HOME_TAB_AUTO_HIDE_V2_KEY, () => new HomeTabAutoHideState())!
}
