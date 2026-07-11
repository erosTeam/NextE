import { common } from '@kit.AbilityKit'
import { abilityDelegatorRegistry } from '@kit.TestKit'
import { describe, expect, it } from '@ohos/hypium'
import { DiagnosticsLogFileSink } from 'shared'

const FIRST_MARKER: string = 'diagnostics_fd_open_marker'
const SECOND_MARKER: string = 'diagnostics_fd_reopen_marker'

async function appContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator()
  const ability = await delegator.getCurrentTopAbility()
  return ability.context as common.UIAbilityContext
}

function appendMarker(marker: string): void {
  DiagnosticsLogFileSink.append({
    ts: Date.now(),
    level: 'info',
    category: 'diagnostics_test',
    event: marker,
    message: marker,
  })
}

function currentLogName(): string {
  const info = DiagnosticsLogFileSink.currentInfo()
  return info ? info.fileName : ''
}

export default function diagnosticsLogFileSinkTest(): void {
  describe('DiagnosticsLogFileSink', () => {
    it('keeps the active log readable before close and after reopening', 0, async (done: Function) => {
      const context = await appContext()
      try {
        expect(context.filesDir.length > 0).assertEqual(true)

        DiagnosticsLogFileSink.initialize(context)
        appendMarker(FIRST_MARKER)
        const firstName = currentLogName()
        expect(firstName.length > 0).assertEqual(true)
        expect(DiagnosticsLogFileSink.exportLatestText().includes(FIRST_MARKER)).assertEqual(true)
        expect(DiagnosticsLogFileSink.readLogFileText(firstName).includes(FIRST_MARKER)).assertEqual(true)

        DiagnosticsLogFileSink.close()
        DiagnosticsLogFileSink.initialize(context)
        appendMarker(SECOND_MARKER)
        const secondName = currentLogName()
        expect(secondName.length > 0).assertEqual(true)
        expect(secondName === firstName).assertEqual(false)
        expect(DiagnosticsLogFileSink.exportLatestText().includes(SECOND_MARKER)).assertEqual(true)
        expect(DiagnosticsLogFileSink.readLogFileText(secondName).includes(SECOND_MARKER)).assertEqual(true)
      } finally {
        // Leave the sink usable if this test shares the app process with later diagnostics work.
        DiagnosticsLogFileSink.close()
        DiagnosticsLogFileSink.initialize(context)
      }
      done()
    })
  })
}
