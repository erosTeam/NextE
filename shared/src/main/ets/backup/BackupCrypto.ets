import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { BackupCipherMeta } from './BackupTypes'
import {
  BACKUP_CIPHER_ALGORITHM,
  BACKUP_CIPHER_IV_BYTES,
  BACKUP_CIPHER_SALT_BYTES,
  BACKUP_CIPHER_TAG_BYTES,
  BACKUP_KDF_ALGORITHM,
  BACKUP_KDF_ITERATIONS,
  BACKUP_KDF_KEY_SIZE,
} from './BackupTypes'

export interface BackupSealResult {
  cipherMeta: BackupCipherMeta
  ciphertext: string
}

/**
 * AES-256-GCM authenticated encryption with a PBKDF2-SHA256 derived key (ported verbatim from V2Next).
 *
 * Security notes:
 *  - The password lives only in local variables for the duration of seal()/open(); it is never
 *    persisted, logged, or returned. Callers must not store it either.
 *  - Each seal() draws a fresh random salt (16B) and IV (12B); never reuse an (key, iv) pair.
 *  - GCM authentication: the 16-byte auth tag is appended to the ciphertext, so a wrong password
 *    (wrong derived key) or any tampering surfaces as a decrypt failure.
 */
export class BackupCrypto {
  /** Schema v1 fixes its KDF settings so untrusted container metadata cannot choose decryption work. */
  static isSupportedMeta(meta: BackupCipherMeta): boolean {
    return meta.cipher === BACKUP_CIPHER_ALGORITHM &&
      meta.kdf === BACKUP_KDF_ALGORITHM &&
      meta.iterations === BACKUP_KDF_ITERATIONS &&
      meta.keySize === BACKUP_KDF_KEY_SIZE &&
      typeof meta.salt === 'string' && meta.salt.length > 0 &&
      typeof meta.iv === 'string' && meta.iv.length > 0
  }

  static seal(plaintext: string, password: string): BackupSealResult {
    const salt = BackupCrypto.randomBytes(BACKUP_CIPHER_SALT_BYTES)
    const iv = BackupCrypto.randomBytes(BACKUP_CIPHER_IV_BYTES)
    const keyBytes = BackupCrypto.deriveKey(password, salt)
    const symKey = BackupCrypto.importKey(keyBytes)

    const gcmParams = BackupCrypto.gcmParams(iv, null)
    const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmParams)

    const plainBytes = new util.TextEncoder().encodeInto(plaintext)
    const bodyBlob = cipher.updateSync({ data: plainBytes })
    const tagBlob = cipher.doFinalSync(null)
    // GCM emits "ciphertext + authTag"; persist them concatenated so open() can split the tag off.
    const sealed = BackupCrypto.concat(bodyBlob ? bodyBlob.data : new Uint8Array(), tagBlob.data)

    const cipherMeta: BackupCipherMeta = {
      cipher: BACKUP_CIPHER_ALGORITHM,
      kdf: BACKUP_KDF_ALGORITHM,
      iterations: BACKUP_KDF_ITERATIONS,
      keySize: BACKUP_KDF_KEY_SIZE,
      salt: BackupCrypto.toBase64(salt),
      iv: BackupCrypto.toBase64(iv),
    }
    return { cipherMeta: cipherMeta, ciphertext: BackupCrypto.toBase64(sealed) }
  }

  static open(ciphertextBase64: string, password: string, meta: BackupCipherMeta): string {
    if (!BackupCrypto.isSupportedMeta(meta)) {
      throw new Error('unsupported backup cipher metadata')
    }
    const salt = BackupCrypto.fromBase64(meta.salt)
    const iv = BackupCrypto.fromBase64(meta.iv)
    const sealed = BackupCrypto.fromBase64(ciphertextBase64)
    if (sealed.length < BACKUP_CIPHER_TAG_BYTES) {
      throw new Error('cipher blob too short')
    }
    const splitAt = sealed.length - BACKUP_CIPHER_TAG_BYTES
    const body = sealed.slice(0, splitAt)
    const tag = sealed.slice(splitAt, sealed.length)

    const keyBytes = BackupCrypto.deriveKey(password, salt)
    const symKey = BackupCrypto.importKey(keyBytes)

    const gcmParams = BackupCrypto.gcmParams(iv, tag)
    const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7')
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, gcmParams)
    const out1 = cipher.updateSync({ data: body })
    const out2 = cipher.doFinalSync(null)
    const plain = BackupCrypto.concat(
      out1 ? out1.data : new Uint8Array(),
      out2 ? out2.data : new Uint8Array(),
    )
    return BackupCrypto.decodeUtf8(plain)
  }

  private static deriveKey(
    password: string,
    salt: Uint8Array,
  ): Uint8Array {
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: BACKUP_KDF_ITERATIONS,
      keySize: BACKUP_KDF_KEY_SIZE,
    }
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256')
    const secret = kdf.generateSecretSync(spec)
    return secret.data
  }

  private static importKey(keyBytes: Uint8Array): cryptoFramework.SymKey {
    const generator = cryptoFramework.createSymKeyGenerator('AES256')
    const keyBlob: cryptoFramework.DataBlob = { data: keyBytes }
    return generator.convertKeySync(keyBlob)
  }

  private static gcmParams(
    iv: Uint8Array,
    authTag: Uint8Array | null,
  ): cryptoFramework.GcmParamsSpec {
    const ivBlob: cryptoFramework.DataBlob = { data: iv }
    const aadBlob: cryptoFramework.DataBlob = { data: new Uint8Array() }
    const tagBlob: cryptoFramework.DataBlob = {
      data: authTag ? authTag : new Uint8Array(BACKUP_CIPHER_TAG_BYTES),
    }
    return { iv: ivBlob, aad: aadBlob, authTag: tagBlob, algName: 'GcmParamsSpec' }
  }

  private static randomBytes(len: number): Uint8Array {
    const rand = cryptoFramework.createRandom()
    return rand.generateRandomSync(len).data
  }

  private static concat(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8')
    return decoder.decodeToString(bytes)
  }

  private static toBase64(bytes: Uint8Array): string {
    return new util.Base64Helper().encodeToStringSync(bytes)
  }

  private static fromBase64(text: string): Uint8Array {
    return new util.Base64Helper().decodeSync(text)
  }
}
