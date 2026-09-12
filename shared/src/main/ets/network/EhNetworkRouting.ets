import { common } from '@kit.AbilityKit'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit'
import { http } from '@kit.NetworkKit'
import { connection } from '@kit.NetworkKit'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { EhNetworkRoutingSettings, EhNetworkRoutingSnapshot } from '../settings/EhNetworkRoutingSettings'

const DOH_YANDEX_URL: string = 'https://common.dot.dns.yandex.net/dns-query'
const DOH_CLOUDFLARE_URL: string = 'https://cloudflare-dns.com/dns-query'
const DOH_GOOGLE_URL: string = 'https://dns.google/dns-query'

/**
 * Addresses the platform may use for a host instead of whatever the system resolver returns.
 *
 * These are operational constants, not configuration: a poisoned answer is the failure mode this
 * whole module exists to survive, and there is no way to discover the right answer from inside the
 * poisoned network. Only the EH domains are fronted (see FRONTING_HOST_SUFFIXES); the GitHub
 * entries are here so `addCustomDnsRule` can rescue the release/translation fetches too.
 */
const BUILT_IN_RULES: EhHostRule[] = [
  { host: 'e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'repo.e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'forums.e-hentai.org', ips: ['172.66.132.196', '172.66.140.62'] },
  { host: 'upld.e-hentai.org', ips: ['89.149.221.236', '95.211.208.236'] },
  {
    host: 'ehgt.org',
    ips: [
      '109.236.85.28', '62.112.8.21', '89.39.106.43',
      '2a00:7c80:0:123::3a85', '2a00:7c80:0:12d::38a1', '2a00:7c80:0:13b::37a4',
    ],
  },
  { host: 'github.com', ips: ['140.82.112.4', '140.82.113.4', '140.82.114.4', '140.82.121.4'] },
  { host: 'api.github.com', ips: ['140.82.112.6', '140.82.113.6', '140.82.114.6', '140.82.121.6'] },
  {
    host: 'raw.githubusercontent.com',
    ips: ['151.101.0.133', '151.101.64.133', '151.101.128.133', '151.101.192.133'],
  },
  {
    host: 'objects.githubusercontent.com',
    ips: ['185.199.108.133', '185.199.109.133', '185.199.110.133', '185.199.111.133'],
  },
  {
    host: 'github-releases.githubusercontent.com',
    ips: ['185.199.108.154', '185.199.109.154', '185.199.110.154', '185.199.111.154'],
  },
  {
    // Release downloads now redirect to this name instead of the legacy one above, and it answers
    // from the same Fastly block as `objects.githubusercontent.com` (measured 185.199.108-111.133,
    // byte-for-byte the same four addresses). Both names stay listed: a redirect that still lands on
    // the legacy host keeps its pinned answer, and this entry is what lets the model installs reach
    // their second hop when the system resolver is the thing that is broken.
    host: 'release-assets.githubusercontent.com',
    ips: ['185.199.108.133', '185.199.109.133', '185.199.110.133', '185.199.111.133'],
  },
]

const BUILT_EX_RULES: EhHostRule[] = [
  {
    host: 'exhentai.org',
    ips: [
      '178.175.128.251', '178.175.128.252', '178.175.128.253', '178.175.128.254',
      '178.175.129.251', '178.175.129.252', '178.175.129.253', '178.175.129.254',
      '178.175.132.19', '178.175.132.20', '178.175.132.21', '178.175.132.22',
    ],
  },
  { host: 'upld.exhentai.org', ips: ['178.175.132.22', '178.175.129.254', '178.175.128.254'] },
  {
    host: 's.exhentai.org',
    ips: [
      '178.175.129.253', '178.175.129.254', '178.175.128.253',
      '178.175.128.254', '178.175.132.21', '178.175.132.22',
    ],
  },
]

/**
 * Only these names are eligible for authority rewriting. Everything else keeps the ordinary
 * transport even when it has pinned addresses, because swapping the authority is what forces
 * certificate validation off and that cost must not leak to unrelated services. A name listed
 * here still needs an address in one of the tables above; without one there is nothing to dial.
 */
const FRONTING_HOST_SUFFIXES: string[] = [
  'e-hentai.org',
  'exhentai.org',
  'ehgt.org',
]

/** How many of the best-scoring addresses stay in the normal rotation. */
const PREFERRED_ADDRESS_LIMIT: number = 3
/** Chance of dialing outside the preferred set, so a demoted address can still recover. */
const TAIL_SAMPLE_RATE: number = 0.08
/** Weight smoothing: larger means score differences matter less. */
const WEIGHT_SCORE_BASE: number = 500
/** Assumed round trip before an address has ever carried a request. */
const UNTESTED_LATENCY_MS: number = 2200
const FAILURE_LATENCY_PENALTY_MS: number = 2500
const SUCCESS_LATENCY_BONUS_MS: number = 120
const SLOW_RESPONSE_THRESHOLD_MS: number = 4000
const SLOW_RESPONSE_PENALTY_MS: number = 350
const NETWORK_CHANGE_DEBOUNCE_MS: number = 350
/** After a real foreground resume, stale pooled connections are bypassed for this long. */
const FRESH_CONNECTION_WINDOW_MS: number = 5000
/** `reuseConnections` / SOCKS5 arrive with API 26; lower runtimes must keep the old options. */
const MODERN_HTTP_API: string = '26.0.0'

export interface EhHostRule {
  host: string
  ips: string[]
}

/** Rolling measurement for one host/address pair. Only real request outcomes feed it. */
interface EhHostIpQuality {
  host: string
  ip: string
  latencyMs: number
  ok: boolean
  successCount: number
  failureCount: number
}

/**
 * The concrete transport decision for one request.
 *
 * `host` is always the caller's original authority so it can be sent as the `Host` header; `url`
 * carries the address actually dialed. Callers must use `url` and must not re-derive the header
 * from it, or the server sees a numeric name and routes the request to the wrong virtual host.
 */
export interface EhRequestPlan {
  url: string
  host: string
  fronted: boolean
}

/**
 * EH transport routing for networks where plain DNS answers cannot be trusted.
 *
 * Three cooperating layers, each independently switchable:
 *  1. `ensureHostRules` installs pinned addresses through `connection.addCustomDnsRule`, which is
 *     app-wide and leaves certificate validation intact.
 *  2. `createPlan` rewrites the authority to a pinned address and marks the request so callers add
 *     an explicit `Host` header. Dialing a literal address means no domain SNI is sent at all,
 *     which is the only way this platform can express "connect here, name yourself that" — there
 *     is no API that suppresses SNI directly. Those requests must skip certificate identity
 *     validation, because the certificate presented can never match a literal address.
 *  3. `applyTransportOptions` adds encrypted DNS (for the requests fronting does not claim) and
 *     the configured proxy.
 *
 * Addresses are chosen by weighted random from measured quality, so one throttled address stops
 * being a single point of failure while a small tail share keeps demoted addresses observable.
 */
export class EhNetworkRouting {
  private static readonly quality: EhHostIpQuality[] = []
  private static appliedHostRulesKey: string = ''
  private static pendingHostRules: Promise<void> | null = null
  private static runtimeConnection: connection.NetConnection | null = null
  private static changeTimer: number = -1
  private static freshConnectionUntilMs: number = 0
  private static previousFrontedHost: string = ''

  /** True when this request should be dialed by address with an explicit `Host` header. */
  static shouldFront(url: string): boolean {
    return EhNetworkRouting.createPlan(url).fronted
  }

  /**
   * True when at least one switch would change how a request goes out.
   *
   * Callers use this to decide whether to keep the stock transport or hand the request to the
   * override-aware one. With every switch at its default-off position this is false, which is what
   * keeps the untouched configuration byte-for-byte identical to the plain transport.
   */
  static overridesTransport(): boolean {
    if (EhNetworkRoutingSettings.frontingEnabled() || EhNetworkRoutingSettings.dnsOverHttpsEnabled()) {
      return true
    }
    return EhNetworkRoutingSettings.current().proxyMode !== EhNetworkRoutingSettings.PROXY_SYSTEM
  }

  /** A status that proves the address actually carried the request through to the origin. */
  static isReachableStatus(statusCode: number): boolean {
    return statusCode >= 200 && statusCode < 400
  }

  /**
   * Decides how `url` will be carried, optionally rewriting its authority to a pinned address.
   * Returns the input untouched whenever fronting is off, the scheme is plain HTTP, the name is
   * not an EH host, or no address is known for it.
   */
  static createPlan(url: string): EhRequestPlan {
    const authority: string = EhNetworkRouting.authorityOf(url)
    const plan: EhRequestPlan = { url: url, host: authority, fronted: false }
    if (authority.length === 0) {
      return plan
    }
    if (!EhNetworkRoutingSettings.frontingEnabled()) {
      return plan
    }
    if (!EhNetworkRouting.isHttpsUrl(url)) {
      // Rewriting a cleartext request would buy nothing: there is no SNI to suppress, and the
      // pinned answer is already available through the DNS rule layer.
      return plan
    }
    const hostname: string = EhNetworkRouting.hostnameOf(authority)
    if (!EhNetworkRouting.isFrontableHost(hostname)) {
      return plan
    }
    const address: string = EhNetworkRouting.selectAddress(hostname.toLowerCase())
    if (address.length === 0) {
      return plan
    }
    plan.url = EhNetworkRouting.rewriteAuthority(url, address)
    plan.fronted = true
    return plan
  }

  /**
   * Shapes `options` in place for `plan`.
   *
   * Deliberately mutates rather than returns: every call site builds its own options object and
   * applies this immediately before handing it to the platform, so a copy would only dilute the
   * single place where these transport decisions are made.
   */
  static applyToOptions(options: http.HttpRequestOptions, plan: EhRequestPlan): void {
    options.usingCache = false
    EhNetworkRouting.applyTransportOptions(options)
    if (plan.fronted) {
      // The certificate name can never match a literal address, so identity validation has to be
      // dropped for exactly these requests. This is the documented cost of fronting.
      options.remoteValidation = 'skip'
      if (deviceInfo.apiAvailable(MODERN_HTTP_API)) {
        const dialed: string = EhNetworkRouting.hostnameOf(EhNetworkRouting.authorityOf(plan.url))
        if (dialed !== EhNetworkRouting.previousFrontedHost) {
          // Moving between addresses invalidates the pooled connection for the old one.
          options.reuseConnections = false
          EhNetworkRouting.previousFrontedHost = dialed
        }
      }
    } else if (deviceInfo.apiAvailable(MODERN_HTTP_API) &&
      Date.now() < EhNetworkRouting.freshConnectionUntilMs) {
      options.reuseConnections = false
    }
  }

  /** The `Host` header value a fronted request must carry, or an empty string when not fronted. */
  static hostHeaderFor(plan: EhRequestPlan): string {
    return plan.host
  }

  /**
   * Installs or clears the pinned-address rules. Best-effort per host: one rejected name must not
   * stop the rest, and a failure only means that name keeps using the system resolver.
   */
  static async ensureHostRules(): Promise<void> {
    const key: string = EhNetworkRoutingSettings.builtInHostsEnabled() ? 'On' : 'Off'
    if (key === EhNetworkRouting.appliedHostRulesKey) {
      return
    }
    if (EhNetworkRouting.pendingHostRules !== null) {
      await EhNetworkRouting.pendingHostRules
      return
    }
    EhNetworkRouting.pendingHostRules = EhNetworkRouting.applyHostRules(key)
    try {
      await EhNetworkRouting.pendingHostRules
    } finally {
      EhNetworkRouting.pendingHostRules = null
    }
  }

  /** Feeds one real request outcome back into address selection. Ignored for non-fronted traffic. */
  static recordOutcome(plan: EhRequestPlan, ok: boolean, elapsedMs: number): void {
    if (!plan.fronted) {
      return
    }
    const address: string = EhNetworkRouting.hostnameOf(EhNetworkRouting.authorityOf(plan.url))
    if (!EhNetworkRouting.isIpv4(address)) {
      return
    }
    const hostname: string = EhNetworkRouting.hostnameOf(plan.host).toLowerCase()
    if (hostname.length === 0) {
      return
    }
    const entry: EhHostIpQuality = EhNetworkRouting.qualityFor(hostname, address)
    if (ok) {
      const measured: number = Math.max(1, elapsedMs)
      entry.latencyMs = entry.successCount === 0
        ? measured
        : Math.floor((entry.latencyMs * 3 + measured) / 4)
      if (measured > SLOW_RESPONSE_THRESHOLD_MS) {
        entry.latencyMs += SLOW_RESPONSE_PENALTY_MS
      }
      entry.ok = true
      entry.successCount++
    } else {
      entry.latencyMs = entry.latencyMs + FAILURE_LATENCY_PENALTY_MS
      entry.ok = false
      entry.failureCount++
    }
  }

  /**
   * Watches for network changes so learned address quality and installed rules do not survive into
   * a network where they are wrong. Safe to call repeatedly.
   */
  static registerNetworkChangeListener(context: common.UIAbilityContext): void {
    if (EhNetworkRouting.runtimeConnection !== null) {
      return
    }
    const netConnection: connection.NetConnection = connection.createNetConnection()
    EhNetworkRouting.runtimeConnection = netConnection
    netConnection.on('netAvailable', (_handle: connection.NetHandle): void => {
      EhNetworkRouting.scheduleNetworkRefresh()
    })
    netConnection.on('netLost', (_handle: connection.NetHandle): void => {
      EhNetworkRouting.scheduleNetworkRefresh()
    })
    netConnection.on('netUnavailable', (): void => {
      EhNetworkRouting.scheduleNetworkRefresh()
    })
    netConnection.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo): void => {
      EhNetworkRouting.scheduleNetworkRefresh()
    })
    try {
      netConnection.register((error: BusinessError): void => {
        if (error !== undefined && error.code !== 0) {
          EhNetworkRouting.runtimeConnection = null
          DiagnosticLogger.warn('network', 'net_listener_register_failed', `${error.code}`)
        }
      })
    } catch (error) {
      EhNetworkRouting.runtimeConnection = null
      DiagnosticLogger.warn('network', 'net_listener_register_failed', (error as Error).message)
    }
  }

  static unregisterNetworkChangeListener(): void {
    const netConnection: connection.NetConnection | null = EhNetworkRouting.runtimeConnection
    if (netConnection === null) {
      return
    }
    EhNetworkRouting.runtimeConnection = null
    if (EhNetworkRouting.changeTimer !== -1) {
      clearTimeout(EhNetworkRouting.changeTimer)
      EhNetworkRouting.changeTimer = -1
    }
    try {
      netConnection.unregister((_error: BusinessError): void => {})
    } catch (error) {
      DiagnosticLogger.warn('network', 'net_listener_unregister_failed', (error as Error).message)
    }
  }

  /**
   * Bypasses pooled connections for a short window after a real foreground resume, because a
   * connection parked while the ability was suspended may no longer be usable.
   */
  static refreshAfterForeground(): void {
    EhNetworkRouting.freshConnectionUntilMs = Math.max(
      EhNetworkRouting.freshConnectionUntilMs,
      Date.now() + FRESH_CONNECTION_WINDOW_MS,
    )
  }

  /** Encrypted-DNS endpoint for the current provider, or an empty string when it is off. */
  static dnsOverHttpsUrl(): string {
    if (!EhNetworkRoutingSettings.dnsOverHttpsEnabled()) {
      return ''
    }
    const provider: string = EhNetworkRoutingSettings.dohProvider()
    if (provider === 'Cloudflare') {
      return DOH_CLOUDFLARE_URL
    }
    if (provider === 'Google') {
      return DOH_GOOGLE_URL
    }
    return DOH_YANDEX_URL
  }

  /** SOCKS5 needs API 26; older runtimes fall back to the system proxy only. */
  static socks5Supported(): boolean {
    return deviceInfo.apiAvailable(MODERN_HTTP_API)
  }

  /** Addresses the platform may use for `hostname`, or an empty list when none are known. */
  static addressesFor(hostname: string): string[] {
    return EhNetworkRouting.ipv4Candidates(hostname)
  }

  private static applyTransportOptions(options: http.HttpRequestOptions): void {
    EhNetworkRouting.applyProxy(options)
    const dohUrl: string = EhNetworkRouting.dnsOverHttpsUrl()
    if (dohUrl.length > 0) {
      options.dnsOverHttps = dohUrl
    }
  }

  private static applyProxy(options: http.HttpRequestOptions): void {
    const snapshot: EhNetworkRoutingSnapshot = EhNetworkRoutingSettings.current()
    const mode: string = snapshot.proxyMode
    if (mode === EhNetworkRoutingSettings.PROXY_OFF) {
      options.usingProxy = false
      return
    }
    if (mode === EhNetworkRoutingSettings.PROXY_HTTP || mode === EhNetworkRoutingSettings.PROXY_SOCKS) {
      const parts: string[] = EhNetworkRoutingSettings.parseProxyServer(snapshot.proxyServer)
      if (parts.length === 2) {
        const port: number = Number.parseInt(parts[1], 10)
        if (mode === EhNetworkRoutingSettings.PROXY_SOCKS) {
          if (EhNetworkRouting.socks5Supported()) {
            const socks: http.Socks5Proxy = { host: parts[0], port: port }
            options.usingSocks5Proxy = socks
            return
          }
        } else {
          // `exclusionList` is a required field on HttpProxy, unlike its SOCKS5 counterpart.
          // Empty is the honest value: the routing layers above already decide which hosts are
          // reshaped, and a second, parallel exclusion list would be one place too many.
          const proxy: http.HttpProxy = { host: parts[0], port: port, exclusionList: [] }
          options.usingProxy = proxy
          return
        }
      }
    }
    // System mode is left unset on purpose. The platform already follows the OS proxy setting, and
    // writing the field anyway would make an otherwise-untouched configuration differ from the
    // plain transport. A half-configured manual mode lands here too, where following the OS beats
    // silently sending traffic through an address the user never finished typing.
  }

  private static async applyHostRules(key: string): Promise<void> {
    if (key === 'Off') {
      await EhNetworkRouting.clearHostRules()
      EhNetworkRouting.appliedHostRulesKey = key
      return
    }
    let applied: number = 0
    for (let i = 0; i < BUILT_IN_RULES.length; i++) {
      if (await EhNetworkRouting.installRule(BUILT_IN_RULES[i])) {
        applied++
      }
    }
    for (let i = 0; i < BUILT_EX_RULES.length; i++) {
      if (await EhNetworkRouting.installRule(BUILT_EX_RULES[i])) {
        applied++
      }
    }
    EhNetworkRouting.appliedHostRulesKey = key
    DiagnosticLogger.info('network', 'host_rules_applied', `hosts=${applied}`)
  }

  private static async installRule(rule: EhHostRule): Promise<boolean> {
    try {
      await connection.addCustomDnsRule(rule.host, rule.ips)
      return true
    } catch (error) {
      DiagnosticLogger.warn('network', 'host_rule_failed', `${rule.host}: ${(error as Error).message}`)
      return false
    }
  }

  private static async clearHostRules(): Promise<void> {
    EhNetworkRouting.appliedHostRulesKey = ''
    for (let i = 0; i < BUILT_IN_RULES.length; i++) {
      await EhNetworkRouting.removeRule(BUILT_IN_RULES[i].host)
    }
    for (let i = 0; i < BUILT_EX_RULES.length; i++) {
      await EhNetworkRouting.removeRule(BUILT_EX_RULES[i].host)
    }
  }

  private static async removeRule(host: string): Promise<void> {
    try {
      await connection.removeCustomDnsRule(host)
    } catch (error) {
      // Nothing to remove, or the platform already forgot it. Either way there is no action.
    }
  }

  private static scheduleNetworkRefresh(): void {
    if (EhNetworkRouting.changeTimer !== -1) {
      clearTimeout(EhNetworkRouting.changeTimer)
    }
    EhNetworkRouting.changeTimer = setTimeout((): void => {
      EhNetworkRouting.changeTimer = -1
      EhNetworkRouting.refreshAfterNetworkChange()
    }, NETWORK_CHANGE_DEBOUNCE_MS)
  }

  private static refreshAfterNetworkChange(): void {
    // Address quality is a property of the path, not of the address, so it must not be carried
    // across a network change. Rules are re-installed because the platform drops them with the
    // connection that owned them.
    EhNetworkRouting.quality.splice(0, EhNetworkRouting.quality.length)
    EhNetworkRouting.appliedHostRulesKey = ''
    EhNetworkRouting.previousFrontedHost = ''
    EhNetworkRouting.refreshAfterForeground()
    EhNetworkRouting.ensureHostRules().catch((error: Error): void => {
      DiagnosticLogger.warn('network', 'host_rules_reapply_failed', error.message)
    })
    DiagnosticLogger.info('network', 'network_changed', 'quality reset, rules reapplied')
  }

  private static ipv4Candidates(hostname: string): string[] {
    const fromBuiltIn: string[] = EhNetworkRouting.ipv4For(hostname, BUILT_IN_RULES)
    if (fromBuiltIn.length > 0) {
      return fromBuiltIn
    }
    return EhNetworkRouting.ipv4For(hostname, BUILT_EX_RULES)
  }

  private static ipv4For(hostname: string, rules: EhHostRule[]): string[] {
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].host !== hostname) {
        continue
      }
      const result: string[] = []
      for (let j = 0; j < rules[i].ips.length; j++) {
        if (EhNetworkRouting.isIpv4(rules[i].ips[j])) {
          result.push(rules[i].ips[j])
        }
      }
      return result
    }
    return []
  }

  private static selectAddress(hostname: string): string {
    const candidates: string[] = EhNetworkRouting.ipv4Candidates(hostname)
    if (candidates.length === 0) {
      return ''
    }
    if (candidates.length === 1) {
      return candidates[0]
    }
    const ranked: EhHostIpQuality[] = []
    for (let i = 0; i < candidates.length; i++) {
      ranked.push(EhNetworkRouting.qualityFor(hostname, candidates[i]))
    }
    ranked.sort((left: EhHostIpQuality, right: EhHostIpQuality): number => {
      const leftScore: number = EhNetworkRouting.scoreOf(left)
      const rightScore: number = EhNetworkRouting.scoreOf(right)
      if (leftScore !== rightScore) {
        return leftScore - rightScore
      }
      return left.ip.localeCompare(right.ip)
    })
    const limit: number = Math.min(PREFERRED_ADDRESS_LIMIT, ranked.length)
    if (ranked.length > limit && Math.random() < TAIL_SAMPLE_RATE) {
      const tail: string = EhNetworkRouting.weightedPick(ranked, limit, ranked.length)
      if (tail.length > 0) {
        return tail
      }
    }
    const preferred: string = EhNetworkRouting.weightedPick(ranked, 0, limit)
    return preferred.length > 0 ? preferred : ranked[0].ip
  }

  private static weightedPick(ranked: EhHostIpQuality[], start: number, end: number): string {
    if (start >= end) {
      return ''
    }
    const bestScore: number = EhNetworkRouting.scoreOf(ranked[0])
    const weights: number[] = []
    let totalWeight: number = 0
    for (let i = start; i < end; i++) {
      const distance: number = Math.max(0, EhNetworkRouting.scoreOf(ranked[i]) - bestScore)
      const healthWeight: number = ranked[i].ok ? 1 : 0.15
      const weight: number = healthWeight / (WEIGHT_SCORE_BASE + distance)
      weights.push(weight)
      totalWeight += weight
    }
    if (totalWeight <= 0) {
      return ranked[start].ip
    }
    let cursor: number = Math.random() * totalWeight
    for (let i = 0; i < weights.length; i++) {
      cursor -= weights[i]
      if (cursor <= 0) {
        return ranked[start + i].ip
      }
    }
    return ranked[end - 1].ip
  }

  /** Lower is better. Failures sort last because the penalty exceeds any observed round trip. */
  private static scoreOf(entry: EhHostIpQuality): number {
    return entry.latencyMs
  }

  private static qualityFor(hostname: string, address: string): EhHostIpQuality {
    for (let i = 0; i < EhNetworkRouting.quality.length; i++) {
      const existing: EhHostIpQuality = EhNetworkRouting.quality[i]
      if (existing.host === hostname && existing.ip === address) {
        return existing
      }
    }
    const created: EhHostIpQuality = {
      host: hostname,
      ip: address,
      latencyMs: UNTESTED_LATENCY_MS,
      ok: true,
      successCount: 0,
      failureCount: 0,
    }
    EhNetworkRouting.quality.push(created)
    return created
  }

  private static isFrontableHost(hostname: string): boolean {
    if (hostname.length === 0) {
      return false
    }
    const normalized: string = hostname.toLowerCase()
    for (let i = 0; i < FRONTING_HOST_SUFFIXES.length; i++) {
      const suffix: string = FRONTING_HOST_SUFFIXES[i]
      if (normalized === suffix || normalized.endsWith(`.${suffix}`)) {
        return true
      }
    }
    return false
  }

  private static isHttpsUrl(url: string): boolean {
    return url.substring(0, 8).toLowerCase() === 'https://'
  }

  private static isIpv4(value: string): boolean {
    const parts: string[] = value.split('.')
    if (parts.length !== 4) {
      return false
    }
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i]
      if (part.length === 0 || part.length > 3) {
        return false
      }
      for (let j = 0; j < part.length; j++) {
        const code: number = part.charCodeAt(j)
        if (code < 48 || code > 57) {
          return false
        }
      }
      if (Number.parseInt(part, 10) > 255) {
        return false
      }
    }
    return true
  }

  /** The authority (host plus optional port) exactly as it appears in `url`. */
  private static authorityOf(url: string): string {
    const schemeEnd: number = url.indexOf('://')
    if (schemeEnd < 0) {
      return ''
    }
    const start: number = schemeEnd + 3
    let end: number = url.length
    const slash: number = url.indexOf('/', start)
    if (slash >= 0) {
      end = slash
    }
    const query: number = url.indexOf('?', start)
    if (query >= 0 && query < end) {
      end = query
    }
    return url.substring(start, end)
  }

  /** An authority with any port removed. */
  private static hostnameOf(authority: string): string {
    const bracket: number = authority.indexOf(']')
    const colon: number = authority.lastIndexOf(':')
    if (colon > 0 && bracket < colon) {
      return authority.substring(0, colon)
    }
    return authority
  }

  /**
   * Swaps the hostname inside `url` for `address`, keeping the scheme, any explicit port, the
   * path and the query, so only the address actually dialed changes.
   */
  private static rewriteAuthority(url: string, address: string): string {
    const schemeEnd: number = url.indexOf('://')
    if (schemeEnd < 0) {
      return url
    }
    const start: number = schemeEnd + 3
    let end: number = url.length
    const slash: number = url.indexOf('/', start)
    if (slash >= 0) {
      end = slash
    }
    const authority: string = url.substring(start, end)
    const hostname: string = EhNetworkRouting.hostnameOf(authority)
    const port: string = hostname.length < authority.length ? authority.substring(hostname.length) : ''
    return url.substring(0, start) + address + port + url.substring(end)
  }
}
