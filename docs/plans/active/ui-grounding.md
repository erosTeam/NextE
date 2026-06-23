# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: gallery detail read button initial hand edge

Status: active
Reference implementation: `feature/gallery/src/main/ets/pages/GalleryDetailPage.ets` read FAB rail and `shared/src/main/ets/services/MotionHandStateService.ets` resolved hand edge.
Surface type: gallery detail page floating read/resume button.
Primary information: the button appears on the resolved left/right hand edge without an initial cross-screen slide caused by first layout measurement.
Primary action: tapping the read button still opens Reader at the saved resume page.
Reuse or deviation: keep the existing smart-grip/follow/fixed edge state and translate-based slide; only gate animation until root/button widths are measured.
Verification: detail header visual contract, UI grounding contract, V1 decorator inventory, diff check, and signed HarmonyOS build.
