import { AppStorageV2 } from '@kit.ArkUI'

@ObservedV2
export class DiagnosticsState {
  @Trace enabled: boolean = true
  @Trace minLevel: string = 'info'
}

const DIAGNOSTICS_STATE_KEY: string = 'v2:diagnostics'

export function connectDiagnostics(): DiagnosticsState {
  return AppStorageV2.connect(
    DiagnosticsState,
    DIAGNOSTICS_STATE_KEY,
    () => new DiagnosticsState(),
  )!
}
