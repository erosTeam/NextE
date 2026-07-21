import { CodexOAuthTokenSet } from '../model/ComicTranslationProvider'

export const CODEX_OAUTH_TOKEN_STORE_MAX_CHARS: number = 512 * 1024
const CODEX_OAUTH_TOKEN_MAX_CHARS: number = 128 * 1024
const CODEX_OAUTH_ACCOUNT_ID_MAX_CHARS: number = 160

class RawCodexOAuthTokenSet {
  accessToken: string = ''
  refreshToken: string = ''
  idToken: string = ''
  accountId: string = ''
  expiresAt: number = 0
  lastRefreshAt: number = 0
}

export class CodexOAuthTokenCodec {
  static parse(rawText: string): CodexOAuthTokenSet | null {
    if (rawText.trim().length === 0 || rawText.length > CODEX_OAUTH_TOKEN_STORE_MAX_CHARS) {
      return null
    }
    try {
      const raw: RawCodexOAuthTokenSet = JSON.parse(rawText) as RawCodexOAuthTokenSet
      if (raw === null || typeof raw !== 'object' ||
        typeof raw.accessToken !== 'string' || raw.accessToken.length === 0 ||
        typeof raw.refreshToken !== 'string' || raw.refreshToken.length === 0) {
        return null
      }
      const tokens: CodexOAuthTokenSet = new CodexOAuthTokenSet()
      tokens.accessToken = raw.accessToken
      tokens.refreshToken = raw.refreshToken
      tokens.idToken = typeof raw.idToken === 'string' ? raw.idToken : ''
      tokens.accountId = typeof raw.accountId === 'string' ? raw.accountId : ''
      tokens.expiresAt = CodexOAuthTokenCodec.safeTimestamp(raw.expiresAt)
      tokens.lastRefreshAt = CodexOAuthTokenCodec.safeTimestamp(raw.lastRefreshAt)
      return CodexOAuthTokenCodec.isValid(tokens) ? tokens : null
    } catch (_error) {
      return null
    }
  }

  static serialize(tokens: CodexOAuthTokenSet): string {
    if (!CodexOAuthTokenCodec.isValid(tokens)) {
      throw new Error('Codex OAuth token set is invalid')
    }
    const encoded: string = JSON.stringify(tokens)
    if (encoded.length > CODEX_OAUTH_TOKEN_STORE_MAX_CHARS) {
      throw new Error('Codex OAuth token set is invalid')
    }
    return encoded
  }

  static isValid(tokens: CodexOAuthTokenSet): boolean {
    return CodexOAuthTokenCodec.validCredential(tokens.accessToken, true) &&
      CodexOAuthTokenCodec.validCredential(tokens.refreshToken, true) &&
      CodexOAuthTokenCodec.validCredential(tokens.idToken, false) &&
      CodexOAuthTokenCodec.validAccountId(tokens.accountId) &&
      CodexOAuthTokenCodec.validTimestamp(tokens.expiresAt) &&
      CodexOAuthTokenCodec.validTimestamp(tokens.lastRefreshAt)
  }

  private static validCredential(value: string, required: boolean): boolean {
    if (typeof value !== 'string' || value.length > CODEX_OAUTH_TOKEN_MAX_CHARS ||
      value !== value.trim()) {
      return false
    }
    if (required && value.length === 0) {
      return false
    }
    return !CodexOAuthTokenCodec.containsControlCharacter(value)
  }

  private static validAccountId(value: string): boolean {
    return typeof value === 'string' && value.length <= CODEX_OAUTH_ACCOUNT_ID_MAX_CHARS &&
      value === value.trim() && !CodexOAuthTokenCodec.containsControlCharacter(value)
  }

  private static containsControlCharacter(value: string): boolean {
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index)
      if (code <= 31 || code === 127) {
        return true
      }
    }
    return false
  }

  private static validTimestamp(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER
  }

  private static safeTimestamp(value: number | null | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 &&
      value <= Number.MAX_SAFE_INTEGER
      ? Math.floor(value)
      : 0
  }
}
