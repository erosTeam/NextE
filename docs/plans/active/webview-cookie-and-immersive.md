# In-app gallery WebView: cookie fix + V2Next component/scaffold port + immersive nav

Status: implemented, device-verified (PuraX). Three linked fixes to the "应用内网页" gallery menu entry.

## 1. Cookie injection bug (logged-out WebView)

`GalleryWebPage.injectAppCookies` passed the whole `nw=1; ipb_member_id=…; ipb_pass_hash=…; igneous=…`
header as ONE value to `webview.WebCookieManager.configCookie(url, value)`. That API sets a SINGLE cookie,
so only `nw=1` stuck and the rest were parsed as attributes — the WebView loaded logged-out.

Fix: split the header on `;` and inject each pair with `configCookieSync(baseUrl, "name=value; Path=/",
false, true)`, then `saveCookieSync` (async fallback) — exactly V2Next's
`CookieJarSettings.restoreToWebCookieManager` per-cookie loop.

## 2. EhWebView ported up to V2Next's V2exWebView

`EhWebView` was a thin wrapper. Ported the fuller V2exWebView: added `onLoadFinished` + `onTitleReceive`
events and `.nestedScroll({ scrollUp/scrollDown: PARENT_FIRST })` + `.overScrollMode(NEVER)`. Kept it
parent-agnostic (NO ListItem wrap, unlike V2exWebView) so it still drops into the login page's Column.
`GalleryWebPage` uses `onTitleReceive` to title the bar with the page's live `<title>`.

## 3. Immersive nav (the actual ask: copy the scaffold + nestedScroll)

`GalleryWebPage` now wraps the WebView like V2Next's V2exWebViewScaffold: `HdsNavDestination` →
`SecondaryListScaffold` (NextE already had this, ported from V2Next) with the `EhWebView` as a
full-height `ListItem`, `immersiveTitleBar(title)`. The Web's `nestedScroll PARENT_FIRST` feeds the
scaffold List, so the page scrolls UNDER the translucent title bar (immersive) — mirroring GalleryInfoPage.
Replaced the old manual `Column` + `topAvoidHeight + TITLE_BAR_HEIGHT` padding (the scaffold's inset row
handles safe-area now).

## 4. Title-bar nav toolbar (back / forward / refresh)

Added a 3-item HDS title-bar menu (same `{ value: [{ content: { label, icon, isEnabled, action } }],
maxCount }` shape as Index.ets's tab menus) driving `WebviewController.backward/forward/refresh`. Back/forward
`isEnabled` track `accessBackward()/accessForward()`, refreshed in `onPageEnd` (`@Local canBack/canForward`),
so they grey out when there's no history. New i18n keys `web_nav_back/forward/refresh` (4 locales). The page
title bar moved from `immersiveTitleBar(title)` to `immersiveTitleBarOpts({ title, menu })`.

## Files

`entry/.../pages/GalleryWebPage.ets` (cookie loop + live title + scaffold/immersive + nav menu),
`shared/.../components/EhWebView.ets` (V2exWebView parity),
`entry/.../resources/{base,en_US,zh_CN,ja_JP}/element/string.json` (nav labels).

## Verification (PuraX)

Open gallery → ⋮ → 应用内网页: WebView loads LOGGED-IN (Watched/Favs/Uploads + "Add to Favorites"),
title bar shows the live page `<title>`, and scrolling slides content under the translucent title bar.
