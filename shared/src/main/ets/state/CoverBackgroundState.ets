import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class CoverBackgroundState {
  @Trace blurringOfCoverBackground: boolean = false
}

const COVER_BACKGROUND_KEY: string = 'v2:coverBackground'

export function connectCoverBackground(): CoverBackgroundState {
  return AppStorageV2.connect(CoverBackgroundState, COVER_BACKGROUND_KEY, () => new CoverBackgroundState())!
}
