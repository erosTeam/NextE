import { describe, expect, it } from '@ohos/hypium'
import { abilityDelegatorRegistry, Driver } from '@kit.TestKit'
import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'

const KEYS: string[] = ['home_source_default', 'home_source_popular', 'home_source_watched',
  'tab_seed_chinese', 'tab_seed_anthology']

async function realContext(driver: Driver): Promise<common.UIAbilityContext> {
  const d = abilityDelegatorRegistry.getAbilityDelegator()
  await d.startAbility({ bundleName: 'com.erosteam.nexte', abilityName: 'EntryAbility' })
  for (let i = 0; i < 80; i++) {
    try { const a = await d.getCurrentTopAbility(); if (a.context.abilityInfo.name === 'EntryAbility') return a.context as common.UIAbilityContext } catch (_) {}
    await driver.delayMs(100)
  }
  throw new Error('EntryAbility context unavailable')
}

/** Read-only: no reserved built-in name may persist as its raw resource key. */
export default function customProfileNameVerifyTrialTest(): void {
  const args = abilityDelegatorRegistry.getArguments().parameters
  if (args['-s class'] !== 'CustomProfileNameVerifyTrial') return
  describe('CustomProfileNameVerifyTrial', (): void => {
    it('noReservedNameIsPersistedAsItsResourceKey', 0, async (): Promise<void> => {
      const d = abilityDelegatorRegistry.getAbilityDelegator()
      const driver = Driver.create()
      const context = await realContext(driver)
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context,
        { name: 'NextE.db', securityLevel: relationalStore.SecurityLevel.S3, autoCleanDirtyData: true })
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT profile_uuid, name, last_edit_time FROM custom_profiles ' +
        'WHERE scope_key=? AND COALESCE(deleted_at,0)=0', ['global'])
      let keyNames = 0
      let total = 0
      try {
        while (rs.goToNextRow()) {
          total++
          const uuid = rs.getString(0)
          const name = rs.getString(1)
          const reserved = uuid === 'builtin-default' || uuid === 'builtin-popular' ||
            uuid === 'builtin-watched' || uuid === 'starter-language-chinese' ||
            uuid === 'starter-other-anthology'
          if (!reserved) continue
          d.print('[CPV] ' + uuid + '=' + name + '@' + rs.getLong(2))
          if (KEYS.indexOf(name) >= 0) keyNames++
        }
      } finally { rs.close() }
      d.print('[CPV] active_rows=' + total + ' reserved_key_names=' + keyNames)
      expect(total > 0).assertTrue()
      expect(keyNames).assertEqual(0)
    })
  })
}
