# NextE background variants

These are optional background-color variants for the selected NextE pages mark.
The foreground is shared across all variants.

The default app icon currently uses the first variant, Aqua, through the
existing compatibility resource names:

- `AppScope/resources/base/media/app_icon_layered.json`
- `AppScope/resources/base/media/app_icon.png`
- `AppScope/resources/base/media/app_icon_sunset_solid_background.png`
- `AppScope/resources/base/media/app_icon_sunset_solid_foreground.png`

The review preview is also packaged as a media resource:

- `AppScope/resources/base/media/app_icon_nexte_pages_variants_preview.png`

Optional layered resources:

- `app_icon_nexte_pages_aqua_layered.json`
- `app_icon_nexte_pages_cyan_layered.json`
- `app_icon_nexte_pages_azure_layered.json`
- `app_icon_nexte_pages_emerald_layered.json`
- `app_icon_nexte_pages_slate_layered.json`
- `app_icon_nexte_pages_violet_layered.json`
- `app_icon_nexte_pages_rose_layered.json`
- `app_icon_nexte_pages_amber_layered.json`
- `app_icon_nexte_pages_graphite_layered.json`
- `app_icon_nexte_pages_midnight_layered.json`

To switch a build later, point the app icon resource to one of these layered
JSON files and use the matching flat PNG for store/fallback assets if needed.
