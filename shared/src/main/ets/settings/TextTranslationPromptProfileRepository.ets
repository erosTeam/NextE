import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import {
  TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION,
  TextTranslationPromptProfile,
} from '../model/TextTranslationPromptProfile'
import { TextTranslationPromptCatalog, TEXT_TRANSLATION_PROMPT_BUILTIN_IDS } from '../services/TextTranslationPromptCatalog'
import { TextTranslationPromptCodec } from '../services/TextTranslationPromptCodec'
import {
  MAX_TEXT_TRANSLATION_CUSTOM_PROFILES,
  TextTranslationPromptContract,
} from '../services/TextTranslationPromptContract'
import {
  connectTextTranslationPromptProfiles,
  TextTranslationPromptProfilesState,
} from '../state/TextTranslationPromptProfilesState'

class TextTranslationPromptPersistScheduler {
  private writeTail: Promise<void> = Promise.resolve()

  enqueue(write: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.writeTail.then(write, write)
    this.writeTail = next
    return next
  }
}

/**
 * Single durable writer for the custom text-translation prompt store and the shared selection.
 * Every write validates an isolated snapshot, persists to Preferences, flushes, and only then
 * publishes the V2 mirror. Built-in IDs are rejected at this boundary so no caller can bypass
 * the read-only guarantee through the UI alone.
 */
export class TextTranslationPromptProfileRepository {
  private static readonly scheduler: TextTranslationPromptPersistScheduler =
    new TextTranslationPromptPersistScheduler()

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const custom: TextTranslationPromptProfile[] = TextTranslationPromptCodec.decode(
        store.getSync(StorageKeys.TEXT_TRANSLATION_PROMPT_CUSTOM_PROFILES, '') as string,
      )
      TextTranslationPromptProfileRepository.applyState(
        custom,
        TextTranslationPromptProfileRepository.resolveSelection(
          store.getSync(StorageKeys.TEXT_TRANSLATION_PROMPT_SELECTED_PROFILE, '') as string,
          custom,
        ),
      )
    } catch (error) {
      // Corrupt JSON or an invalid entry: run with no custom profiles and the standard built-in.
      // Never crash at startup and never silently pick another custom profile.
      DiagnosticLogger.warn('settings', 'text_translation_prompt_restore_failed', (error as Error).message)
      TextTranslationPromptProfileRepository.applyState(
        [],
        TextTranslationPromptCatalog.defaultProfileId(),
      )
    }
  }

  /** Isolated current selection snapshot; resolves invalid ids down to standard. */
  static currentSelection(): TextTranslationPromptProfile {
    return connectTextTranslationPromptProfiles().selectedProfile()
  }

  static select(context: common.UIAbilityContext, promptProfileId: string): Promise<void> {
    const canonicalId: string = promptProfileId
    if (canonicalId.length === 0) {
      return Promise.reject(new Error('Text translation prompt selection is empty'))
    }
    return TextTranslationPromptProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const custom: TextTranslationPromptProfile[] =
        TextTranslationPromptProfileRepository.readCustom(store)
      const resolved: string =
        TextTranslationPromptProfileRepository.resolveSelection(canonicalId, custom)
      store.putSync(StorageKeys.TEXT_TRANSLATION_PROMPT_SELECTED_PROFILE, resolved)
      store.flushSync()
      connectTextTranslationPromptProfiles().selectedPromptProfileId = resolved
    })
  }

  static upsertCustom(
    context: common.UIAbilityContext,
    candidate: TextTranslationPromptProfile,
  ): Promise<void> {
    const isolated: TextTranslationPromptProfile = candidate.copy()
    return TextTranslationPromptProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      if (TEXT_TRANSLATION_PROMPT_BUILTIN_IDS.indexOf(isolated.promptProfileId) >= 0 ||
        TextTranslationPromptContract.isBuiltinId(isolated.promptProfileId)) {
        throw new Error('Built-in text translation prompt profiles are read-only')
      }
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const custom: TextTranslationPromptProfile[] =
        TextTranslationPromptProfileRepository.readCustom(store)
      const index: number = TextTranslationPromptProfileRepository.indexOf(custom, isolated.promptProfileId)
      if (index < 0 && custom.length >= MAX_TEXT_TRANSLATION_CUSTOM_PROFILES) {
        throw new Error('Too many custom text translation prompt profiles')
      }
      const existing: TextTranslationPromptProfile | null = index < 0 ? null : custom[index]
      const next: TextTranslationPromptProfile =
        TextTranslationPromptProfileRepository.prepareForUpsert(existing, isolated, Date.now())
      if (index < 0) {
        custom.push(next)
      } else {
        custom[index] = next
      }
      TextTranslationPromptProfileRepository.writeCustom(store, custom)
      store.flushSync()
      connectTextTranslationPromptProfiles().customProfiles = TextTranslationPromptCodec.copyProfiles(custom)
    })
  }

  static removeCustom(context: common.UIAbilityContext, promptProfileId: string): Promise<void> {
    return TextTranslationPromptProfileRepository.scheduler.enqueue(async (): Promise<void> => {
      if (TEXT_TRANSLATION_PROMPT_BUILTIN_IDS.indexOf(promptProfileId) >= 0 ||
        TextTranslationPromptContract.isBuiltinId(promptProfileId)) {
        throw new Error('Built-in text translation prompt profiles cannot be removed')
      }
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const custom: TextTranslationPromptProfile[] =
        TextTranslationPromptProfileRepository.readCustom(store)
      const index: number = TextTranslationPromptProfileRepository.indexOf(custom, promptProfileId)
      if (index < 0) {
        return
      }
      const remaining: TextTranslationPromptProfile[] = []
      for (let i: number = 0; i < custom.length; i++) {
        if (i !== index) {
          remaining.push(custom[i])
        }
      }
      TextTranslationPromptProfileRepository.writeCustom(store, remaining)
      const state: TextTranslationPromptProfilesState = connectTextTranslationPromptProfiles()
      if (state.selectedPromptProfileId === promptProfileId) {
        // Atomic with the removal inside this one serial write: the selection never dangles.
        state.selectedPromptProfileId = TextTranslationPromptCatalog.defaultProfileId()
        store.putSync(
          StorageKeys.TEXT_TRANSLATION_PROMPT_SELECTED_PROFILE,
          TextTranslationPromptCatalog.defaultProfileId(),
        )
      }
      store.flushSync()
      state.customProfiles = TextTranslationPromptCodec.copyProfiles(remaining)
    })
  }

  /**
   * Pure preparation of a copied-profile draft. The caller supplies a fresh UUID and the
   * localized copy name; the source's style text is carried over verbatim. The copy starts a
   * brand-new revision domain (revision 1): the cache scope also carries the new prompt id.
   */
  static copyAsCustom(
    source: TextTranslationPromptProfile,
    newId: string,
    localizedCopyName: string,
    now: number,
  ): TextTranslationPromptProfile {
    if (newId.length === 0 || TextTranslationPromptContract.isBuiltinId(newId)) {
      throw new Error('Copied text translation prompt profile needs a fresh custom ID')
    }
    const value: TextTranslationPromptProfile = new TextTranslationPromptProfile()
    value.schemaVersion = TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION
    value.promptProfileId = newId
    value.displayName = localizedCopyName
    value.styleInstructions = source.styleInstructions
    value.promptRevision = 1
    value.builtIn = false
    value.createdAt = now
    value.updatedAt = now
    TextTranslationPromptContract.validateCustomProfile(value)
    return value
  }

  /**
   * Unit-testable upsert preparation. Renaming a custom profile keeps its revision (and its
   * cache domain); only a style-text change advances the revision.
   */
  static prepareForUpsert(
    existing: TextTranslationPromptProfile | null,
    candidate: TextTranslationPromptProfile,
    now: number,
  ): TextTranslationPromptProfile {
    if (!TextTranslationPromptContract.nonNegativeInteger(now)) {
      throw new Error('Text translation prompt update time is invalid')
    }
    const next: TextTranslationPromptProfile = candidate.copy()
    next.schemaVersion = TEXT_TRANSLATION_PROMPT_SCHEMA_VERSION
    next.displayName = next.displayName.trim()
    // Trim only the outer edges and canonicalize line endings; interior newlines are content.
    next.styleInstructions =
      TextTranslationPromptContract.normalizeLineEndings(next.styleInstructions.trim())
    if (existing === null) {
      next.promptRevision = 1
      next.createdAt = now
      next.updatedAt = now
    } else {
      TextTranslationPromptContract.validateCustomProfile(existing)
      if (existing.styleInstructions !== next.styleInstructions) {
        next.promptRevision = existing.promptRevision + 1
      } else {
        next.promptRevision = existing.promptRevision
      }
      next.createdAt = existing.createdAt
      next.updatedAt = Math.max(now, existing.updatedAt + 1)
    }
    TextTranslationPromptContract.validateCustomProfile(next)
    return next
  }

  /** A selection resolves only to an existing built-in or custom profile; everything else is standard. */
  static resolveSelection(rawSelection: string, custom: TextTranslationPromptProfile[]): string {
    const trimmed: string = rawSelection.trim()
    if (trimmed.length === 0) {
      return TextTranslationPromptCatalog.defaultProfileId()
    }
    if (TEXT_TRANSLATION_PROMPT_BUILTIN_IDS.indexOf(trimmed) >= 0) {
      return trimmed
    }
    if (TextTranslationPromptProfileRepository.indexOf(custom, trimmed) >= 0) {
      return trimmed
    }
    return TextTranslationPromptCatalog.defaultProfileId()
  }

  private static readCustom(store: preferences.Preferences): TextTranslationPromptProfile[] {
    return TextTranslationPromptCodec.decode(
      store.getSync(StorageKeys.TEXT_TRANSLATION_PROMPT_CUSTOM_PROFILES, '') as string,
    )
  }

  private static writeCustom(
    store: preferences.Preferences,
    custom: TextTranslationPromptProfile[],
  ): void {
    if (custom.length === 0) {
      store.deleteSync(StorageKeys.TEXT_TRANSLATION_PROMPT_CUSTOM_PROFILES)
    } else {
      store.putSync(StorageKeys.TEXT_TRANSLATION_PROMPT_CUSTOM_PROFILES, TextTranslationPromptCodec.encode(custom))
    }
  }

  private static indexOf(custom: TextTranslationPromptProfile[], promptProfileId: string): number {
    for (let index: number = 0; index < custom.length; index++) {
      if (custom[index].promptProfileId === promptProfileId) {
        return index
      }
    }
    return -1
  }

  private static applyState(
    custom: TextTranslationPromptProfile[],
    selectedPromptProfileId: string,
  ): void {
    const state: TextTranslationPromptProfilesState = connectTextTranslationPromptProfiles()
    state.customProfiles = TextTranslationPromptCodec.copyProfiles(custom)
    state.selectedPromptProfileId = selectedPromptProfileId
  }
}
