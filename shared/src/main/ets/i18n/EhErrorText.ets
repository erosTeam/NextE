import { AppStrings } from './AppStrings'
import { EhError, EhErrorKind } from '../network/EhError'

/**
 * Maps a classified EhErrorKind to a localized, user-facing message. The `shared` HAR carries no
 * resources, so this resolves via AppStrings (entry context resourceManager). ArkUI `$r` requires a
 * string-LITERAL key (no dynamic key), so the kind→key switch lives here as a plain accessor and the
 * resolved string is fed straight into PageErrorState's ResourceStr message param.
 *
 * Only EhErrorKind.NotFound (a captured HTTP 404) maps to the "not available / removed" wording — no
 * other failure may read as 404. Raw `... HTTP <code>` engineering strings never reach the UI.
 */
export class EhErrorText {
  static keyFor(kind: EhErrorKind): string {
    switch (kind) {
      case EhErrorKind.NotFound:
        return 'error_gallery_unavailable'
      case EhErrorKind.SadPanda:
        return 'error_sad_panda'
      case EhErrorKind.LoginRequired:
        return 'error_login_required'
      case EhErrorKind.Cloudflare:
        return 'error_cloudflare'
      case EhErrorKind.RateLimited:
        return 'error_rate_limited'
      case EhErrorKind.ServerError:
        return 'error_server'
      case EhErrorKind.ParseFailure:
        return 'error_parse'
      case EhErrorKind.EmptyBody:
        return 'error_empty'
      case EhErrorKind.HttpError:
        return 'error_http'
      case EhErrorKind.Network:
        return 'error_network'
      default:
        return 'common_load_failed'
    }
  }

  /** Localized message for a classified kind. */
  static message(kind: EhErrorKind): string {
    return AppStrings.get(EhErrorText.keyFor(kind))
  }

  /** Localized message for any caught value (classifies the kind via EhError.kindOf). */
  static forUser(err: Object): string {
    return EhErrorText.message(EhError.kindOf(err))
  }
}
