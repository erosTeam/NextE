import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'

/** File-only worker: no UI or service initialization on the TaskPool thread. */
@Concurrent
export function validateReaderModelFile(path: string, expectedBytes: number, expectedSha256: string): boolean {
  let file: fileIo.File | null = null
  try {
    if (fileIo.statSync(path).size !== expectedBytes) {
      return false
    }
    const md = cryptoFramework.createMd('SHA256')
    file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    const chunkBytes: number = 256 * 1024
    const buffer: ArrayBuffer = new ArrayBuffer(chunkBytes)
    while (true) {
      const read: number = fileIo.readSync(file.fd, buffer, { length: chunkBytes })
      if (read <= 0) {
        break
      }
      md.updateSync({ data: new Uint8Array(buffer, 0, read) })
    }
    const bytes: Uint8Array = md.digestSync().data
    const parts: string[] = []
    for (let i: number = 0; i < bytes.length; i++) {
      parts.push(bytes[i].toString(16).padStart(2, '0'))
    }
    return parts.join('') === expectedSha256
  } catch (_error) {
    return false
  } finally {
    if (file !== null) {
      fileIo.closeSync(file)
    }
  }
}
