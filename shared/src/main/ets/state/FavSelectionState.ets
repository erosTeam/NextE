import { AppStorageV2 } from '@kit.ArkUI'
import { Favcat } from '../model/Favcat'
import { TabVisualIndexState } from './HomeSourceState'

/**
 * Favorites favcat-selector state. The favcat strip is a PINNED title-bar `bottomBuilder` (FavcatBar)
 * rendered OUTSIDE FavoritesPage's component tree — in a ComponentContent owned by Index — so it can
 * never touch the page's `FavoritesViewModel` (which is page-@Local, not in AppStorageV2). This shared
 * @Trace holder is the ONLY channel between the bar and the page, two directions (V2Next
 * FeedTabState/FeedPills doctrine; mirrors HomeSourceState):
 *   page → bar : snapshot fields (favList / selectedFavcat / orderByPosted) FavoritesPage publishes
 *                after the VM changes, so the bar renders the right chips + the title-bar order menu
 *                shows the right checkmark, without reaching the VM.
 *   bar → page : the command bus (cmdKind/cmdArg/cmdSeq) FavcatBar (chip select) and the HDS title-bar
 *                order action write via FavSelectionBridge; FavoritesPage @Monitors to drive
 *                vm.selectFavcat / vm.toggleOrder.
 * The favcat bar is chips-ONLY. Search + order live in the HDS title bar (eros_fe favorites nav bar:
 * search icon + sort_down), NOT hand-rolled into this bar. Search opens the single shared adaptive
 * search page in favorite scope (eros_fe goSearchPage(searchType: favorite)), so this holder carries
 * no search field at all.
 */
@ObservedV2
export class FavSelectionState {
  // ---- snapshot: page → bar ----
  // Full favcat set seen across loads (EH omits the active favcat from a filtered page; the VM merges).
  @Trace favList: Favcat[] = []
  // Selected slot: 'a' = all, '0'..'9' = network slots.
  @Trace selectedFavcat: string = 'a'
  // Order label state: true = posted-time (fs_p), false = favorited-time (fs_f, EH default).
  @Trace orderByPosted: boolean = false

  // ---- command bus: bar → page (single-writer FavSelectionBridge; page @Monitors cmdSeq) ----
  // Command kind: '' | 'select' | 'openOrderMenu'.
  @Trace cmdKind: string = ''
  // Command argument (favId for 'select'; '' otherwise).
  @Trace cmdArg: string = ''
  // Monotonic sequence so a repeated identical command still fires the page's @Monitor.
  @Trace cmdSeq: number = 0
}

/** Per-frame interpolated favcat index for the FavcatBar's sliding indicator (V2Next FeedVisualIndexState;
 * mirrors connectHomeSourceVisualIndex / connectToplistVisualIndex). The retained Favorites Swiper
 * publishes it continuously during a swipe so the bar indicator tracks the finger/page animation. */
export function connectFavcatVisualIndex(): TabVisualIndexState {
  return AppStorageV2.connect(TabVisualIndexState, 'v2:favcatVisualIndex', () => new TabVisualIndexState())!
}

const FAV_SELECTION_V2_KEY: string = 'v2:favSelection'

/** App-wide FavSelectionState singleton; seeds the default favcat slots so the bar shows pre-parse. */
export function connectFavSelection(): FavSelectionState {
  return AppStorageV2.connect(FavSelectionState, FAV_SELECTION_V2_KEY, () => seedFavSelection())!
}

/**
 * Seed the 10 network slots (0..9) BEFORE any favorites.php parse so the pinned bar is never empty on
 * first paint (eros_fe seeds EHConst.favList's 10 slots regardless of parse — const.dart:427 /
 * favorite_sel_controller.dart:111). The synthetic 'a' (all) chip is rendered by FavcatBar itself, not
 * a favList entry, so it is not seeded here. Placeholder titles 'Favorites N' are overwritten by the
 * real parse via FavoritesViewModel.mergeFavList. NextE does not model eros_fe's synthetic 'l' (local)
 * slot, so it is omitted.
 */
function seedFavSelection(): FavSelectionState {
  const s: FavSelectionState = new FavSelectionState()
  const seed: Favcat[] = []
  for (let i = 0; i < 10; i++) {
    seed.push(new Favcat(`${i}`, `Favorites ${i}`, 0))
  }
  s.favList = seed
  return s
}

/**
 * Single writer for the bar → page command bus (V2Next FeedTabBridge static publish* methods).
 * FavcatBar chip/order taps call these; FavoritesPage @Monitors cmdSeq and dispatches to the VM.
 * (searchActive is NOT a command — it's a shared toggle the bar writes directly.)
 */
export class FavSelectionBridge {
  static publishSelect(favId: string): void {
    const s: FavSelectionState = connectFavSelection()
    s.cmdArg = favId
    s.cmdKind = 'select'
    s.cmdSeq = s.cmdSeq + 1
  }

  // The title-bar order icon can't anchor a dropdown (HDS menu icons aren't owned nodes), so it asks
  // FavoritesPage (which owns the VM + an anchor node) to open the native order Menu.
  static publishOpenOrderMenu(): void {
    const s: FavSelectionState = connectFavSelection()
    s.cmdArg = ''
    s.cmdKind = 'openOrderMenu'
    s.cmdSeq = s.cmdSeq + 1
  }
}
