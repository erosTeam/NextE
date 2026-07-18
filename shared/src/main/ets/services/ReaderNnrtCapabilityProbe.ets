import { mindSporeLite } from '@kit.MindSporeLiteKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'

export class ReaderNnrtCapabilities {
  available: boolean = false
  acceleratorAvailable: boolean = false
  deviceCount: number = 0
  deviceNames: string[] = []
}

/**
 * Hardware-only probe. NNRT is not an inference option until a compatible MindSpore Lite model is
 * converted and its full operator graph is proven on a physical device.
 */
export class ReaderNnrtCapabilityProbe {
  static probe(): ReaderNnrtCapabilities {
    const result: ReaderNnrtCapabilities = new ReaderNnrtCapabilities()
    try {
      const devices: mindSporeLite.NNRTDeviceDescription[] =
        mindSporeLite.getAllNNRTDeviceDescriptions()
      result.deviceCount = devices.length
      result.available = devices.length > 0
      for (let i: number = 0; i < devices.length; i++) {
        const name: string = devices[i].deviceName()
        const type: mindSporeLite.NNRTDeviceType = devices[i].deviceType()
        result.deviceNames.push(name)
        if (type === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
          result.acceleratorAvailable = true
        }
      }
      DiagnosticLogger.info(
        'reader-super-resolution',
        'nnrt_capabilities',
        `count=${result.deviceCount} accelerator=${result.acceleratorAvailable} ` +
          `devices=${result.deviceNames.join(',')}`,
      )
    } catch (error) {
      DiagnosticLogger.warn(
        'reader-super-resolution',
        'nnrt_capabilities_failed',
        (error as Error).message,
      )
    }
    return result
  }
}
