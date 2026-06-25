export interface DiagnosticLogEntry {
  ts: number
  level: string
  category: string
  event: string
  message: string
}

const REDACTED: string = '<redacted>'
const DROPPED: string = '<omitted>'
const MAX_STRING_LENGTH: number = 220

export class DiagnosticsRedactor {
  static sanitizeEvent(entry: DiagnosticLogEntry): DiagnosticLogEntry {
    try {
      return {
        ts: entry.ts > 0 ? entry.ts : Date.now(),
        level: DiagnosticsRedactor.safeToken(entry.level || 'info'),
        category: DiagnosticsRedactor.safeToken(entry.category || 'app'),
        event: DiagnosticsRedactor.safeToken(entry.event || 'unknown'),
        message: DiagnosticsRedactor.sanitizeString(entry.message || ''),
      }
    } catch (_error) {
      return {
        ts: Date.now(),
        level: 'error',
        category: 'diagnostics',
        event: 'redaction_failed',
        message: 'Diagnostic redaction failed',
      }
    }
  }

  static ownerHash(value: string): string {
    const clean = (value || '').trim()
    if (!clean) {
      return ''
    }
    return `${clean.length}:${DiagnosticsRedactor.fnv1a(clean)}`
  }

  static sanitizeString(value: string): string {
    let clean = value || ''
    clean = clean.replace(/(Cookie|Set-Cookie)\s*[:=][^;\n]+/gi, `$1=${REDACTED}`)
    clean = clean.replace(/Authorization\s*[:=]\s*(Bearer\s+)?[^\s;]+/gi, `Authorization=${REDACTED}`)
    clean = clean.replace(/Bearer\s+[A-Za-z0-9._~+\/-]+/gi, `Bearer ${REDACTED}`)
    clean = clean.replace(/\b(https?|socks5):\/\/[^\s/@]+:[^\s/@]*@/gi, `$1://${REDACTED}@`)
    clean = clean.replace(/([?&](igneous|ipb_member_id|ipb_pass_hash|sk|token|auth|code|password|pass_hash|delete_once|redeem|once)[^=]*=)[^&#\s]+/gi, `$1${REDACTED}`)
    clean = clean.replace(/\b(igneous|ipb_member_id|ipb_pass_hash|pass_hash|api[_-]?key)\s*[:=]\s*[^;\s,}]+/gi, `$1=${REDACTED}`)
    clean = clean.replace(/\/mission\/daily\/redeem\?[^\s]+/gi, '/mission/daily/redeem?once=<redacted>')
    clean = clean.replace(/\/delete\/notification\/\d+\?[^\s]+/gi, '/delete/notification/<id>?once=<redacted>')
    clean = clean.replace(/\/thank\/(reply|topic)\/\d+\?[^\s]+/gi, '/thank/$1/<id>?once=<redacted>')
    clean = clean.replace(/\/favorite\/(topic|node)\/[^\s?]+\?[^\s]+/gi, '/favorite/$1/<id>?once=<redacted>')
    clean = clean.replace(/\/private\/var\/folders\/[^\s]+/gi, '/<tmp>/<path>')
    clean = clean.replace(/\/data\/storage\/[^\s]+/gi, '/<app-data>/<path>')
    if (clean.indexOf('<html') >= 0 || clean.indexOf('<div') >= 0 || clean.indexOf('content_rendered') >= 0) {
      return DROPPED
    }
    if (clean.length > MAX_STRING_LENGTH) {
      return clean.substring(0, MAX_STRING_LENGTH) + '...'
    }
    return clean
  }

  static safeToken(value: string): string {
    const clean = (value || '').replace(/[^a-zA-Z0-9_.:-]/g, '_').substring(0, 80)
    return clean.length > 0 ? clean : 'unknown'
  }

  private static fnv1a(value: string): string {
    let hash = 2166136261
    for (let i = 0; i < value.length; i += 1) {
      hash ^= value.charCodeAt(i)
      hash = Math.imul(hash, 16777619) >>> 0
    }
    return hash.toString(16)
  }
}
