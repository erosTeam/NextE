import { AppStorageV2 } from '@kit.ArkUI'

/** Toplist-only local filtering. Separate from Advanced Search f_sft/default-filter controls. */
@ObservedV2
export class ToplistFilterState {
  @Trace applyHiddenUserTags: boolean = true
}

const TOPLIST_FILTER_KEY: string = 'v2_toplistFilter'

export function connectToplistFilter(): ToplistFilterState {
  return AppStorageV2.connect(ToplistFilterState, TOPLIST_FILTER_KEY, () => new ToplistFilterState())!
}
