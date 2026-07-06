export class CookieJarEntry {
  name: string = ''
  value: string = ''

  constructor(name: string = '', value: string = '') {
    this.name = name
    this.value = value
  }

  copy(): CookieJarEntry {
    return new CookieJarEntry(this.name, this.value)
  }
}
