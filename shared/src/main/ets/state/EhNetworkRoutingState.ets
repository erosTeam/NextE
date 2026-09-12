import { AppStorageV2 } from '@kit.ArkUI'

/**
 * Runtime mirror for the EH network routing configuration.
 *
 * Every field is stored exactly as the user set it; validation and canonicalization live in
 * EhNetworkRoutingSettings so this holder stays a plain mirror of what was persisted.
 */
@ObservedV2
export class EhNetworkRoutingState {
  @Trace frontingEnabled: boolean = true
  @Trace builtInHostsEnabled: boolean = true
  @Trace dnsOverHttpsEnabled: boolean = false
  @Trace dohProvider: string = 'Yandex'
  @Trace proxyMode: string = 'System'
  @Trace proxyServer: string = ''
}

const EH_NETWORK_ROUTING_KEY: string = 'v2_ehNetworkRouting'

export function connectEhNetworkRouting(): EhNetworkRoutingState {
  return AppStorageV2.connect(
    EhNetworkRoutingState,
    EH_NETWORK_ROUTING_KEY,
    () => new EhNetworkRoutingState(),
  )!
}
