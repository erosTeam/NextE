import {
  connectAuth,
  AuthState,
  connectHomeSource,
  HomeSourceState,
  connectHomeSourceVisualIndex,
  TabVisualIndexState,
  RetainedSubtabHost,
  ActiveKeyState,
} from 'shared'
import { GallerySourcePage } from '../components/GallerySourcePage'

// Global @Builder (no `this`) so passing it to RetainedSubtabHost's @BuilderParam under @ComponentV2
// can't hit the instance-@Builder `this`-loss crash. Renders one retained gallery-source page per key,
// handed the SHARED active-key signal (so cached pages still get their first-activation load).
@Builder
function gallerySourcePageBuilder(key: string, active: ActiveKeyState, scroller: Scroller) {
  GallerySourcePage({ sourceKey: key, active: active, scroller: scroller })
}

/**
 * Gallery tab: retained per-SOURCE sub-tabs on the shared RetainedSubtabHost framework. The source
 * switcher (默认/热门/订阅, HomeSourceBar in the title bar) writes the HomeSourceState selection BUS; the
 * host swipes to the retained GallerySourcePage for that source (each owns its own VM + scroller) and
 * publishes the visual index for the bar's sliding indicator. HomePage only adapts this surface to the
 * framework: the visible source keys (login-gated), the selection bus read/write, and the scroller handoff.
 */
@ComponentV2
export struct HomePage {
  @Local auth: AuthState = connectAuth();
  @Local homeSource: HomeSourceState = connectHomeSource();
  @Local visual: TabVisualIndexState = connectHomeSourceVisualIndex();
  // Index consumes the ACTIVE source's scroller for the title-bar bindToScrollable (auto-hide).
  @Event onScrollerReady?: (scroller: Scroller) => void;

  // 订阅 (watched) is login-only (eros_fe). The keyed host retains '' / 'popular' when 'watched' is added/
  // removed on login change. Must mirror HomeSourceBar's tab order so the visual index lines up.
  private visibleSources(): string[] {
    return this.auth.isLogin ? ['', 'popular', 'watched'] : ['', 'popular']
  }

  // If the user logs out while on 订阅, fall back to the front page (the host then drops the 'watched' key).
  @Monitor('auth.isLogin')
  onLoginChange(): void {
    if (!this.auth.isLogin && this.homeSource.source === 'watched') {
      this.homeSource.source = ''
    }
  }

  build() {
    RetainedSubtabHost({
      keys: this.visibleSources(),
      selectedKey: this.homeSource.source,
      pageBuilder: gallerySourcePageBuilder,
      onSelectKey: (key: string) => {
        this.homeSource.source = key
      },
      onVisualIndex: (value: number) => {
        this.visual.value = value
      },
      onScrollerReady: (scroller: Scroller) => {
        if (this.onScrollerReady) {
          this.onScrollerReady(scroller)
        }
      },
    })
  }
}
