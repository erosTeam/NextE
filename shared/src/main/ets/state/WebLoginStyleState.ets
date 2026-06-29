import { AppStorageV2 } from '@kit.ArkUI'

/** Controls whether the forums WebView login form is reshaped into the native-looking login layout. */
@ObservedV2
export class WebLoginStyleState {
  @Trace beautifyEnabled: boolean = true
}

const WEB_LOGIN_STYLE_KEY: string = 'v2:webLoginStyle'

export function connectWebLoginStyle(): WebLoginStyleState {
  return AppStorageV2.connect(WebLoginStyleState, WEB_LOGIN_STYLE_KEY, () => new WebLoginStyleState())!
}
