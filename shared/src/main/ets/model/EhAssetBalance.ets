export class EhAssetBalance {
  gpText: string = ''
  creditText: string = ''

  constructor(gpText: string = '', creditText: string = '') {
    this.gpText = gpText
    this.creditText = creditText
  }

  hasAnyBalance(): boolean {
    return this.gpText.length > 0 || this.creditText.length > 0
  }

  copy(): EhAssetBalance {
    return new EhAssetBalance(this.gpText, this.creditText)
  }
}
