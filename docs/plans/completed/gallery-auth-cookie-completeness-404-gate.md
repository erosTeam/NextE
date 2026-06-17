# Gallery auth/cookie completeness 404 gate

Created: 2026-06-17
Completed: 2026-06-17
Status: COMPLETED — implemented and pushed.

Implementation commits:

- `3d1bcad` — `fix(network): persist the complete cookie jar, not a 5-cookie whitelist`
- `667b1c9` — `feat(error): classify ambiguous "removed or is unavailable" as MaybeHidden`

## User report

Many galleries previously surfaced as 404 / deleted. User now identifies a likely root cause: incomplete login/cookie information.

Concrete example:

```text
https://e-hentai.org/g/3952732/02e514a2f6
```

With full login information, this gallery should not show as deleted. Therefore treating a deleted/404 page as gallery truth without verifying cookie completeness is wrong.

Additional user-provided mechanism (2026-06-17): some galleries with certain elements are only visible on ExHentai/里站 for normal users; visiting the E-Hentai/表站 URL may render as nonexistent/deleted. Donor users may be able to access the same gallery through the E-Hentai URL, apparently gated by one cookie / permission marker. Exact cookie name is unverified and must be determined without logging raw values.

## Product/engineering ruling

A gallery detail/fetch response that looks like deleted/404 must be classified as an auth/cookie-completeness-sensitive result before surfacing a hard deleted state.

Do not mask real 404s with vague retry, but do distinguish:

- verified real deleted/not found;
- unauthenticated/incomplete-cookie access denial that renders like deleted;
- ExHentai/E-Hentai mode mismatch / EH URL access denied for a gallery that is only visible on ExHentai;
- donor-permission/cookie-gated EH-domain access;
- parser failure / network failure.

## Required investigation

1. Inspect current cookie/auth model:
   - `EhCookieStore`, cookie jar persistence/restoration, login check;
   - whether all required e-hentai cookies are stored and sent for gallery detail requests;
   - whether `ipb_member_id`, `ipb_pass_hash`, `igneous`, `sk`, `yay/lv` or other relevant cookies are preserved if present;
   - identify which cookie/permission marker controls donor-only EH-domain access for otherwise ExHentai-only galleries, if present in the user's session, without printing the value;
   - domain/path behavior for `e-hentai.org` vs `exhentai.org`, including whether cookie scope prevents the relevant marker from being sent to the EH URL.
2. Reproduce the example gallery with:
   - current app/device cookie state;
   - full browser/session cookie state if available from user/device;
   - curl or app network logs where safe, without leaking cookies into logs or commits.
3. Inspect gallery detail response handling:
   - where deleted/404 text/status is classified;
   - whether auth-sensitive deleted pages are distinguishable by response body/login state/cookie completeness.
4. Fix durable root cause:
   - preserve/send complete cookie set;
   - avoid dropping unknown cookies;
   - add auth-sensitive error classification if server renders deletion for incomplete cookies.
5. Add deterministic gates where possible:
   - cookie jar round-trip keeps unknown/required cookies;
   - gallery detail classifier does not collapse auth-sensitive deleted into verified real deleted;
   - no credential/cookie values in logs, fixtures, commits, or HAP artifacts.

## Verification result

- Cookie jar persistence no longer uses the 5-cookie whitelist; unknown/auth capability cookies are round-tripped by `scripts/test_cookie_roundtrip_contract.mjs`.
- Ambiguous EH response text `This gallery has been removed or is unavailable.` maps to `MaybeHidden`, not hard `NotFound`.
- User-visible copy is official/neutral and does not expose ExHentai/donor/cookie/login implementation details.
- `.197 / ALN-AL80` device smoke opened the example gallery through deep link and showed the neutral MaybeHidden message, not a hard-deleted state.
- Secret-safety / HAP scans passed with no raw cookie/session values.

## Safety constraints

- Do not hardcode user cookies or session data.
- Do not log raw Cookie headers or credential values.
- If using device/browser cookies for reproduction, redact values in all notes.
- Before commit/push, scan git tracked files and build artifacts for cookie/session strings.

## Verification gate

- Example gallery `3952732/02e514a2f6` must not be reported as hard deleted when full auth cookies are present.
- Incomplete auth must surface as auth/cookie issue, not false deleted.
- Existing real deleted/404 behavior must still work.
