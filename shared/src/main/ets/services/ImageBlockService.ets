import {
  IMAGE_BLOCK_SCOPE_WHOLE,
  IMAGE_BLOCK_SOURCE_ALLOW,
  ImageBlockDecision,
  ImageBlockRule,
} from '../model/ImageBlockRule'
import { PHashService } from './PHashService'

export class ImageBlockService {
  static decisionForHash(
    hash: string,
    rules: ImageBlockRule[],
    whitelist: string[] = [],
  ): ImageBlockDecision {
    const normalizedHash: string = PHashService.normalizeHex64(hash)
    const decision: ImageBlockDecision = new ImageBlockDecision()
    decision.hash = normalizedHash
    if (normalizedHash.length === 0 || ImageBlockService.isWhitelisted(normalizedHash, whitelist)) {
      return decision
    }
    if (ImageBlockService.isAllowedByRule(normalizedHash, rules)) {
      return decision
    }

    let bestRule: ImageBlockRule | null = null
    let bestDistance: number = 65
    for (let i: number = 0; i < rules.length; i++) {
      const rule: ImageBlockRule = rules[i]
      if (!rule.enabled || rule.scope !== IMAGE_BLOCK_SCOPE_WHOLE) {
        continue
      }
      const ruleHash: string = PHashService.normalizeHex64(rule.hash)
      if (ruleHash.length === 0) {
        continue
      }
      const distance: number = PHashService.hammingDistanceHex(normalizedHash, ruleHash)
      const threshold: number = PHashService.clampThreshold(rule.threshold)
      if (distance >= 0 && distance <= threshold && distance < bestDistance) {
        bestRule = rule
        bestDistance = distance
      }
    }

    if (bestRule === null) {
      return decision
    }
    decision.blocked = true
    decision.ruleId = bestRule.id
    decision.feedId = bestRule.feedId
    decision.sourceType = bestRule.sourceType
    decision.label = bestRule.label
    decision.threshold = PHashService.clampThreshold(bestRule.threshold)
    decision.distance = bestDistance
    return decision
  }

  private static isWhitelisted(hash: string, whitelist: string[]): boolean {
    for (let i: number = 0; i < whitelist.length; i++) {
      if (PHashService.normalizeHex64(whitelist[i]) === hash) {
        return true
      }
    }
    return false
  }

  private static isAllowedByRule(hash: string, rules: ImageBlockRule[]): boolean {
    for (let i: number = 0; i < rules.length; i++) {
      const rule: ImageBlockRule = rules[i]
      if (rule.enabled && rule.sourceType === IMAGE_BLOCK_SOURCE_ALLOW &&
        PHashService.normalizeHex64(rule.hash) === hash) {
        return true
      }
    }
    return false
  }
}
