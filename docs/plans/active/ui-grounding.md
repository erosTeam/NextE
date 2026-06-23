# UI Grounding Ledger

Purpose: current UI work must leave a small, checkable grounding record before product code changes. This is not a design spec and not a component whitelist; it records what existing implementation the change is grounded in and what evidence is required.

## Active: gallery tag information MyTags management sheets

Status: active
Reference implementation: `feature/user/src/main/ets/pages/MyTagsPage.ets` tagset rows and edit/add sheets; `feature/settings/src/main/ets/pages/*SettingsPage.ets` settings-style rows; HarmonyOS multi-bindSheet sample for nested sheets.
Surface type: gallery tag information half-modal with a second-level MyTags manage or tagset-selection half-modal.
Primary information: selected raw EH tag, localized tag display when available, and real EH MyTags tagset names/counts from `/mytags`.
Primary action: open existing user-tag editing when the tag is already in a set; otherwise choose a real tagset and continue into the add/edit flow.
Reuse or deviation: keep the project sheet shell and existing settings/list/form primitives; any deviation needs source or device evidence recorded here before code changes.
Verification: deterministic tag-info/MyTags contracts, V1 decorator inventory, signed HarmonyOS build, and emulator screenshots for both already-in-tagset and not-in-tagset paths.
