import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { connectEhNetworkRouting, EhNetworkRoutingState } from '../state/EhNetworkRoutingState'

/**
 * Persisted shape of the EH network routing configuration.
 *
 * `frontingEnabled` is the aggressive layer: it dials pinned addresses and therefore has to skip
 * certificate identity validation. `builtInHostsEnabled` reaches the same addresses without that
 * cost, so it is the layer to keep when the stricter one is turned off.
 */
export class EhNetworkRoutingSnapshot {
  frontingEnabled: boolean = true
  builtInHostsEnabled: boolean = true
  dnsOverHttpsEnabled: boolean = false
  /** One of 'Yandex' | 'Cloudflare' | 'Google'. */
  dohProvider: string = 'Yandex'
  /** One of 'System' | 'Off' | 'HTTP' | 'SOCKS'. */
  proxyMode: string = 'System'
  /** 'host:port' for the manual proxy modes; empty when unset. */
  proxyServer: string = ''
}

export class EhNetworkRoutingSettings {
  static readonly PROXY_SYSTEM: string = 'System'
  static readonly PROXY_OFF: string = 'Off'
  static readonly PROXY_HTTP: string = 'HTTP'
  static readonly PROXY_SOCKS: string = 'SOCKS'

  static readonly PROVIDER_YANDEX: string = 'Yandex'
  static readonly PROVIDER_CLOUDFLARE: string = 'Cloudflare'
  static readonly PROVIDER_GOOGLE: string = 'Google'

  /**
   * Fronting is on by default: the reported symptom was EH being unreachable at all, and this is
   * the only layer that also defeats name-based blocking. The trade-off it carries — skipping
   * certificate identity validation — is the reason it stays a visible, reversible switch.
   */
  static readonly DEFAULT_FRONTING_ENABLED: boolean = true
  static readonly DEFAULT_BUILT_IN_HOSTS_ENABLED: boolean = true
  /**
   * Encrypted DNS stays off by default. It only helps requests fronting does not claim, and a
   * resolver that is itself unreachable would turn a working request into a failed one, so it
   * should be enabled deliberately rather than inherited.
   */
  static readonly DEFAULT_DNS_OVER_HTTPS_ENABLED: boolean = false
  static readonly DEFAULT_DOH_PROVIDER: string = 'Yandex'
  static readonly DEFAULT_PROXY_MODE: string = 'System'
  static readonly DEFAULT_PROXY_SERVER: string = ''

  static apply(snapshot: EhNetworkRoutingSnapshot): void {
    const state: EhNetworkRoutingState = connectEhNetworkRouting()
    state.frontingEnabled = snapshot.frontingEnabled
    state.builtInHostsEnabled = snapshot.builtInHostsEnabled
    state.dnsOverHttpsEnabled = snapshot.dnsOverHttpsEnabled
    state.dohProvider = EhNetworkRoutingSettings.normalizeProvider(snapshot.dohProvider)
    state.proxyMode = EhNetworkRoutingSettings.normalizeProxyMode(snapshot.proxyMode)
    state.proxyServer = EhNetworkRoutingSettings.normalizeProxyServer(snapshot.proxyServer)
  }

  static current(): EhNetworkRoutingSnapshot {
    const state: EhNetworkRoutingState = connectEhNetworkRouting()
    const snapshot = new EhNetworkRoutingSnapshot()
    snapshot.frontingEnabled = state.frontingEnabled
    snapshot.builtInHostsEnabled = state.builtInHostsEnabled
    snapshot.dnsOverHttpsEnabled = state.dnsOverHttpsEnabled
    snapshot.dohProvider = EhNetworkRoutingSettings.normalizeProvider(state.dohProvider)
    snapshot.proxyMode = EhNetworkRoutingSettings.normalizeProxyMode(state.proxyMode)
    snapshot.proxyServer = EhNetworkRoutingSettings.normalizeProxyServer(state.proxyServer)
    return snapshot
  }

  static frontingEnabled(): boolean {
    return connectEhNetworkRouting().frontingEnabled
  }

  static builtInHostsEnabled(): boolean {
    return connectEhNetworkRouting().builtInHostsEnabled
  }

  static dnsOverHttpsEnabled(): boolean {
    return connectEhNetworkRouting().dnsOverHttpsEnabled
  }

  static dohProvider(): string {
    return EhNetworkRoutingSettings.normalizeProvider(connectEhNetworkRouting().dohProvider)
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      const snapshot = new EhNetworkRoutingSnapshot()
      snapshot.frontingEnabled = store.getSync(
        StorageKeys.NETWORK_FRONTING_ENABLED,
        EhNetworkRoutingSettings.DEFAULT_FRONTING_ENABLED,
      ) as boolean
      snapshot.builtInHostsEnabled = store.getSync(
        StorageKeys.NETWORK_BUILT_IN_HOSTS_ENABLED,
        EhNetworkRoutingSettings.DEFAULT_BUILT_IN_HOSTS_ENABLED,
      ) as boolean
      snapshot.dnsOverHttpsEnabled = store.getSync(
        StorageKeys.NETWORK_DOH_ENABLED,
        EhNetworkRoutingSettings.DEFAULT_DNS_OVER_HTTPS_ENABLED,
      ) as boolean
      snapshot.dohProvider = store.getSync(
        StorageKeys.NETWORK_DOH_PROVIDER,
        EhNetworkRoutingSettings.DEFAULT_DOH_PROVIDER,
      ) as string
      snapshot.proxyMode = store.getSync(
        StorageKeys.NETWORK_PROXY_MODE,
        EhNetworkRoutingSettings.DEFAULT_PROXY_MODE,
      ) as string
      snapshot.proxyServer = store.getSync(
        StorageKeys.NETWORK_PROXY_SERVER,
        EhNetworkRoutingSettings.DEFAULT_PROXY_SERVER,
      ) as string
      EhNetworkRoutingSettings.apply(snapshot)
      DiagnosticLogger.info(
        'network',
        'routing_restored',
        `fronting=${snapshot.frontingEnabled} hosts=${snapshot.builtInHostsEnabled} proxy=${snapshot.proxyMode}`,
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'routing_restore_failed', (error as Error).message)
      EhNetworkRoutingSettings.apply(new EhNetworkRoutingSnapshot())
    }
  }

  static async save(context: common.UIAbilityContext, snapshot: EhNetworkRoutingSnapshot): Promise<void> {
    EhNetworkRoutingSettings.apply(snapshot)
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, StorageKeys.STORE_SETTINGS)
      store.putSync(StorageKeys.NETWORK_FRONTING_ENABLED, snapshot.frontingEnabled)
      store.putSync(StorageKeys.NETWORK_BUILT_IN_HOSTS_ENABLED, snapshot.builtInHostsEnabled)
      store.putSync(StorageKeys.NETWORK_DOH_ENABLED, snapshot.dnsOverHttpsEnabled)
      store.putSync(StorageKeys.NETWORK_DOH_PROVIDER, EhNetworkRoutingSettings.normalizeProvider(snapshot.dohProvider))
      store.putSync(StorageKeys.NETWORK_PROXY_MODE, EhNetworkRoutingSettings.normalizeProxyMode(snapshot.proxyMode))
      store.putSync(StorageKeys.NETWORK_PROXY_SERVER, EhNetworkRoutingSettings.normalizeProxyServer(snapshot.proxyServer))
      store.flushSync()
      DiagnosticLogger.info(
        'network',
        'routing_saved',
        `fronting=${snapshot.frontingEnabled} hosts=${snapshot.builtInHostsEnabled} proxy=${snapshot.proxyMode}`,
      )
    } catch (error) {
      DiagnosticLogger.warn('settings', 'routing_save_failed', (error as Error).message)
    }
  }

  static normalizeProvider(value: string): string {
    if (value === EhNetworkRoutingSettings.PROVIDER_CLOUDFLARE) {
      return EhNetworkRoutingSettings.PROVIDER_CLOUDFLARE
    }
    if (value === EhNetworkRoutingSettings.PROVIDER_GOOGLE) {
      return EhNetworkRoutingSettings.PROVIDER_GOOGLE
    }
    return EhNetworkRoutingSettings.PROVIDER_YANDEX
  }

  static normalizeProxyMode(value: string): string {
    if (value === EhNetworkRoutingSettings.PROXY_OFF) {
      return EhNetworkRoutingSettings.PROXY_OFF
    }
    if (value === EhNetworkRoutingSettings.PROXY_HTTP) {
      return EhNetworkRoutingSettings.PROXY_HTTP
    }
    if (value === EhNetworkRoutingSettings.PROXY_SOCKS) {
      return EhNetworkRoutingSettings.PROXY_SOCKS
    }
    return EhNetworkRoutingSettings.PROXY_SYSTEM
  }

  /** Canonical 'host:port', or an empty string when the input is not usable. */
  static normalizeProxyServer(value: string): string {
    const parts: string[] = EhNetworkRoutingSettings.parseProxyServer(value)
    if (parts.length !== 2) {
      return ''
    }
    return `${parts[0]}:${parts[1]}`
  }

  /** Exactly `[host, port]` for a usable 'host:port', otherwise an empty list. */
  static parseProxyServer(value: string): string[] {
    if (value === null || value === undefined) {
      return []
    }
    const trimmed: string = value.trim()
    const colon: number = trimmed.lastIndexOf(':')
    if (colon <= 0 || colon === trimmed.length - 1) {
      return []
    }
    const host: string = trimmed.substring(0, colon).trim()
    const portText: string = trimmed.substring(colon + 1).trim()
    if (host.length === 0 || portText.length === 0) {
      return []
    }
    for (let i = 0; i < portText.length; i++) {
      const code: number = portText.charCodeAt(i)
      if (code < 48 || code > 57) {
        return []
      }
    }
    const port: number = Number.parseInt(portText, 10)
    if (port <= 0 || port > 65535) {
      return []
    }
    return [host, port.toString()]
  }
}
