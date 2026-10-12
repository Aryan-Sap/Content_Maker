# YouTube OAuth — Fix the consent timeout & finish the upload pipeline

**Goal:** Make the YouTube publishing pipeline work end-to-end. The upload code is
complete; the only blocker is the first-time Google consent, which fails with
`Timed out waiting for authorization.` because the GUI allowed just 5 minutes,
which is too short for a slow first-time sign-in and consent.

This file has three parts:
- **Part 1 — Code changes** (for Codex to apply/verify).
- **Part 2 — Google Cloud Console setup** (manual, human-only — Codex cannot do this).
- **Part 3 — Verification** (partly Codex, partly human).

---

## Part 1 — Code changes (Codex)

Widen the interactive consent window from 5 → 15 minutes so the warning
click-through cannot time out. Two one-line edits. **Verify they are present; apply
if missing.**

### Edit 1
File: `lib/src/infrastructure/publishing/oauth/authorization_code_flow.dart`
In `AuthorizationCodeFlow.obtainCode(...)`, the `timeout` parameter default:

```dart
// before
Duration timeout = const Duration(minutes: 5),
// after
Duration timeout = const Duration(minutes: 15),
```

### Edit 2
File: `lib/src/infrastructure/publishing/oauth/loopback_redirect_server.dart`
In `LoopbackRedirectServer.waitForCode(...)`, the `timeout` parameter default:

```dart
// before
Duration timeout = const Duration(minutes: 5),
// after
Duration timeout = const Duration(minutes: 15),
```

### Why both
`obtainCode` passes its `timeout` down to `waitForCode`, so Edit 1 covers the
YouTube (and TikTok) GUI connect. Edit 2 keeps the loopback server's own default in
sync for any direct caller. No other code changes — no new APIs, no signature
changes, only the default `Duration`.

### Do NOT change
- No HTTP client timeout on the token exchange or the resumable upload — large
  videos must not self-abort. Leave those unset.
- Do not touch scopes, PKCE, `access_type=offline`, or `prompt=consent` in
  `youtube_oauth_authenticator.dart` — they are correct and give a refresh token.

### Check for tests
`test/publishing/loopback_redirect_server_test.dart` passes an explicit
`timeout: const Duration(seconds: 5)`, so it is unaffected. Confirm no test asserts
the old 5-minute default before finishing.

### Gate
Run and confirm both pass:
```powershell
flutter analyze lib/src/infrastructure/publishing/oauth/authorization_code_flow.dart lib/src/infrastructure/publishing/oauth/loopback_redirect_server.dart
flutter test test/publishing/loopback_redirect_server_test.dart
```

---

## Part 2 — Google Cloud Console setup (human, one-time)

> Codex cannot perform these — they require signing into the Google account in a
> browser. Do them once for the channel's Google account (`aryan.saproo@gmail.com`).

1. **Enable the API:** [console.cloud.google.com](https://console.cloud.google.com)
   → select the project → **APIs & Services → Library** → enable
   **YouTube Data API v3**.

2. **OAuth consent screen** (APIs & Services → OAuth consent screen):
   - User type: **External**.
   - **Publishing status:** the production app is **In production and verified by
     Google** for the sensitive `youtube.upload` scope, so any account can consent.
     For a new development project, leave it on `Testing` and add yourself under
     **Test users** until you submit it for verification.
   - **Test users** (development clients only): add the exact account you sign in
     with. In Testing mode only listed test users can pass consent — **this is the
     step people miss.**
   - **Scopes:** ensure both are present:
     `https://www.googleapis.com/auth/youtube.upload` and
     `https://www.googleapis.com/auth/youtube.readonly`.

3. **OAuth client** (APIs & Services → Credentials → Create Credentials →
   OAuth client ID): **Application type = Desktop app**. Nothing else to configure —
   the app's loopback redirect `http://127.0.0.1:<port>/` is auto-allowed for
   Desktop clients, so there is no redirect URI to register.

4. **Put the secrets in the app:** copy `oauth.local.example.json` →
   `oauth.local.json` (git-ignored, project root) and fill:
   - `YOUTUBE_CLIENT_ID` (must end in `.apps.googleusercontent.com`)
   - `YOUTUBE_CLIENT_SECRET`

   Validate:
   ```powershell
   dart run tool/check_oauth_config.dart youtube
   ```

---

## Part 3 — Verification (end-to-end)

### The consent click-through (human, when pressing "Connect")
The browser opens automatically. Move through it without long pauses (you now have
15 minutes):
1. Pick the Google account that owns the YouTube channel; sign in if asked.
2. With the verified production client there is no warning. Only a development
   client in Testing mode shows **"Google hasn't verified this app"** → **Advanced**
   → **Go to Content Maker (unsafe)**.
3. Leave **both** YouTube permission boxes checked → **Continue / Allow**.
4. Tab shows *"Authorization complete. You can close this tab…"* — done.

### Steps
1. **Config loads:** `dart run tool/check_oauth_config.dart youtube` passes.
2. **Connect:** `flutter run -d windows` → publish panel → **Connect** → walk the
   click-through above. On success the panel shows your **channel title** (proves
   `youtube.readonly` + token exchange worked).
   - Optional: deliberately take longer than 5 minutes once to confirm the widened
     timeout holds.
3. **Publish:** publish a short test video → confirm it appears on the channel
   (resumable upload path in
   `lib/src/infrastructure/publishing/youtube/youtube_publisher.dart`). Start with
   privacy **private**.
4. **Hands-off refresh:** restart the app and Publish again **without** pressing
   Connect → confirms the stored refresh token works with no browser prompt. This is
   the "no missing links / hands-off" goal.

### Notes / gotchas
- A refresh token is issued only because the app sends `access_type=offline` +
  `prompt=consent`. It is stored in Windows secure storage (`SecureOAuthTokenStore`,
  DPAPI-backed).
- Only while a development project stays in **Testing**, refresh tokens can expire
  after ~7 days of disuse. If a later upload suddenly asks for consent again, just press **Connect**
  once more to re-issue one.
- If Connect fails immediately with an "access_denied"/blocked error (not a
  timeout), the signing-in account is almost certainly not in the **Test users**
  list — revisit Part 2, step 2.
