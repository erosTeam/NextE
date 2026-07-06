/**
 * EH account home limits parsed from home.php. Mirrors eros_fe EhHome: normal accounts expose current
 * image quota / total / reset GP cost, while limited high-resolution access can expose an unlock cost.
 */
export class EhHome {
  currentLimit: number = 0
  totLimit: number = 0
  resetCost: number = 0
  resetActionUrl: string = ''
  resetActionMethod: string = ''
  resetActionBody: string = ''
  highResolutionLimited: boolean = false
  unlockCost: number = 0

  constructor(
    currentLimit: number = 0,
    totLimit: number = 0,
    resetCost: number = 0,
    resetActionUrl: string = '',
    resetActionMethod: string = '',
    resetActionBody: string = '',
    highResolutionLimited: boolean = false,
    unlockCost: number = 0,
  ) {
    this.currentLimit = currentLimit
    this.totLimit = totLimit
    this.resetCost = resetCost
    this.resetActionUrl = resetActionUrl
    this.resetActionMethod = resetActionMethod
    this.resetActionBody = resetActionBody
    this.highResolutionLimited = highResolutionLimited
    this.unlockCost = unlockCost
  }

  hasImageLimits(): boolean {
    return this.totLimit > 0
  }

  hasUnlockCost(): boolean {
    return this.unlockCost > 0
  }

  hasResetAction(): boolean {
    return this.resetCost > 0 && this.resetActionUrl.length > 0
  }

  copy(): EhHome {
    return new EhHome(
      this.currentLimit,
      this.totLimit,
      this.resetCost,
      this.resetActionUrl,
      this.resetActionMethod,
      this.resetActionBody,
      this.highResolutionLimited,
      this.unlockCost,
    )
  }
}
