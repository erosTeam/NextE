import { describe, expect, it } from '@ohos/hypium'
import { CookieJarSettings, EhConstants, EhCookieStore, EhProfile, EhProfileSettings } from 'shared'

function cookie(name: string, value: string): string {
  return `${name}${String.fromCharCode(61)}${value}`
}

function countCookie(header: string, name: string): number {
  const parts: string[] = header.split(';')
  let count: number = 0
  for (let i: number = 0; i < parts.length; i++) {
    const part: string = parts[i].trim()
    const equals: number = part.indexOf(String.fromCharCode(61))
    if (equals > 0 && part.substring(0, equals) === name) {
      count++
    }
  }
  return count
}

export default function ehProfileSelectionCookieTest(): void {
  describe('EhProfile selected cookie', () => {
    it('uses only a server-selected profile and keeps the request override isolated until success', 0, (done: Function) => {
      const settings: EhProfileSettings = new EhProfileSettings()
      settings.profiles = [
        new EhProfile('Profile one', 1, false, false),
        new EhProfile('Profile two', 2, true, false),
      ]
      settings.selectedProfile = 2
      const selected: string = settings.selectedProfileCookieValue()
      expect(selected).assertEqual('2')

      settings.selectedProfile = 1
      expect(settings.selectedProfileCookieValue()).assertEqual('')

      settings.profiles = []
      settings.selectedProfile = 0
      expect(settings.selectedProfileCookieValue()).assertEqual('')

      const cookieStore: EhCookieStore = EhCookieStore.getInstance()
      const original: string = cookieStore.serializeForPersist()
      try {
        cookieStore.clear()
        CookieJarSettings.applyFromHeader(
          `${cookie(EhConstants.COOKIE_MEMBER_ID, 'member-a')}; ` +
          `${cookie(EhConstants.COOKIE_PASS_HASH, 'pass-a')}; ` +
          `${cookie(EhConstants.COOKIE_PROFILE_SELECTION, 'old-profile')}; ` +
          `${cookie('fixture_marker', 'kept')}`,
        )
        const requestHeader: string = cookieStore.headerWithCookieOverride(
          EhConstants.COOKIE_PROFILE_SELECTION,
          selected,
        )
        expect(CookieJarSettings.parseCookieValue(
          requestHeader,
          EhConstants.COOKIE_PROFILE_SELECTION,
        )).assertEqual('2')
        expect(countCookie(requestHeader, EhConstants.COOKIE_PROFILE_SELECTION)).assertEqual(1)
        expect(requestHeader.indexOf(cookie('fixture_marker', 'kept')) >= 0).assertEqual(true)
        expect(cookieStore.get(EhConstants.COOKIE_PROFILE_SELECTION)).assertEqual('old-profile')

        cookieStore.set(EhConstants.COOKIE_PROFILE_SELECTION, selected)
        const persisted: string = cookieStore.serializeForPersist()
        expect(CookieJarSettings.parseCookieValue(
          persisted,
          EhConstants.COOKIE_PROFILE_SELECTION,
        )).assertEqual('2')
        cookieStore.clear()
        CookieJarSettings.applyFromHeader(persisted)
        expect(cookieStore.get(EhConstants.COOKIE_PROFILE_SELECTION)).assertEqual('2')
      } finally {
        cookieStore.clear()
        if (original.length > 0) {
          CookieJarSettings.applyFromHeader(original)
        }
      }
      done()
    })
  })
}
