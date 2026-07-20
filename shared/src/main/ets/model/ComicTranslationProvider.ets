export const COMIC_TRANSLATION_PROVIDER_OPENAI_API: string = 'openai_api'
export const COMIC_TRANSLATION_PROVIDER_CODEX_OAUTH: string = 'codex_oauth'

export class ComicTranslationProviderSettingsSnapshot {
  provider: string = COMIC_TRANSLATION_PROVIDER_OPENAI_API
  apiBaseUrl: string = 'https://api.openai.com/v1'
  apiKey: string = ''
  apiModel: string = 'gpt-4o-mini'
  codexModel: string = ''
}

/** Device-code login state contains no bearer or refresh credential. */
export class CodexOAuthDeviceSession {
  userCode: string = ''
  deviceAuthId: string = ''
  verificationUrl: string = 'https://auth.openai.com/codex/device'
  pollIntervalSeconds: number = 5
  expiresAt: number = 0
}

export class CodexOAuthAuthorizationExchange {
  authorizationCode: string = ''
  codeVerifier: string = ''
}

/** Sensitive device-local credential. Never log, sync, or expose through reactive UI state. */
export class CodexOAuthTokenSet {
  accessToken: string = ''
  refreshToken: string = ''
  idToken: string = ''
  accountId: string = ''
  expiresAt: number = 0
  lastRefreshAt: number = 0

  copy(): CodexOAuthTokenSet {
    const tokens: CodexOAuthTokenSet = new CodexOAuthTokenSet()
    tokens.accessToken = this.accessToken
    tokens.refreshToken = this.refreshToken
    tokens.idToken = this.idToken
    tokens.accountId = this.accountId
    tokens.expiresAt = this.expiresAt
    tokens.lastRefreshAt = this.lastRefreshAt
    return tokens
  }
}

export class CodexOAuthPollResult {
  pending: boolean = true
  exchange: CodexOAuthAuthorizationExchange | null = null
}
