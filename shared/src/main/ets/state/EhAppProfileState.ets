import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class EhAppProfileState {
  @Trace enabled: boolean = true
}

export function connectEhAppProfile(): EhAppProfileState {
  return AppStorageV2.connect(EhAppProfileState, 'v2_ehAppProfile', () => new EhAppProfileState())!
}
