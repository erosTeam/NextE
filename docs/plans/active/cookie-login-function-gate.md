# Cookie login function gate

- **status**: ACTIVE
- **owner**: controller / Claude lane `auth-cookie-login`
- **created**: 2026-06-17 19:20 +0800
- **base**: `cedb4ac`

## Scope

Implement the missing safe manual Cookie login/import path for NextE.

Existing baseline:

```text
- WebView login route exists: entry/src/main/ets/pages/EhLoginWebPage.ets
- Runtime/persistence exists: EhCookieStore + CookieJarSettings + AuthState
- Security incident removed bundled automatic session injection
- Roadmap M3 still lists manual pasted-cookie fallback as part of login foundation
```

## Required product behavior

```text
- User can paste a Cookie header / cookie string inside the app.
- App parses and persists it through CookieJarSettings / EhCookieStore.
- Required identity cookies: ipb_member_id + ipb_pass_hash.
- Preserve unknown cookies in the complete jar; do not whitelist-drop donor/permission cookies.
- If igneous exists and is not mystery, AuthState.hasIgneous must reflect it.
- Settings/auth UI must refresh after successful import.
- Logout still clears the complete jar.
```

## Security hard stops

```text
- Do not hardcode cookie/session values anywhere.
- Do not add raw cookie fixtures containing real secrets.
- Do not log raw Cookie headers or values.
- Do not package raw credential files or any auto-login resource.
- UI/logs may show only redacted facts: cookie names/counts/member id, never values.
- Commit must pass secret-safety and HAP/source leakage gates.
```

## Implementation preference

```text
- Prefer a small manual-import screen reachable from Settings account/login area.
- Reuse CookieJarSettings.applyFromHeader/save/syncAuthState; do not duplicate cookie parsing logic.
- Add user-facing validation for missing ipb_member_id/ipb_pass_hash.
- Keep WebView login path intact.
```

## Gates

```text
- add/extend cookie login contract test for manual import UI path and redaction
- existing cookie-roundtrip / cookiejar / secret-safety must stay green
- harness-verify must pass
- build-only must pass
```

## Device QA

```text
- Agent-controlled device operations require scripts/device-lease.
- Without a real user cookie, device QA may only verify route/UI/invalid-input behavior and mark real login import as BLOCKED_BY_USER_COOKIE.
- Do not request or print user's cookie in logs/chat. If user tests manually, controller only needs screenshots/status, not the cookie value.
```

## Non-scope

```text
- Do not implement favorites editing / mytags editing / destructive EH writes.
- Do not resume bundled automatic session injection.
- Do not alter detail preview/list-card UI in this lane.
```
