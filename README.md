# Content Maker

Cross-platform gameplay video formatter for short-form exports.

## First Renderer Slice

The first implementation focuses on a reliable local render pipeline:

- Flutter shell for Android and Windows.
- FFmpeg command builder for the Shorts-style gameplay format.
- Desktop FFmpeg adapter with progress parsing.
- Dart CLI for quick video-to-video testing.
- Simple app surface with source/output paths and motion interpolation toggle.

## Run Checks

```powershell
flutter analyze
flutter test
```

## Render From CLI

```powershell
dart run tool/render_short.dart "C:\path\input.mp4" "C:\path\output_shorts.mp4"
```

For slower FFmpeg motion interpolation:

```powershell
dart run tool/render_short.dart "C:\path\input.mp4" "C:\path\output_shorts.mp4" --interpolate
```

## Publishing To YouTube / TikTok / Instagram

After a render finishes, the Publish panel can upload the video straight to your
channels via each platform's official API.

One-time setup:

1. Create a Google Cloud OAuth **Desktop app** client with the *YouTube Data API
   v3* enabled.
2. Create a **TikTok for Developers** app with the *Content Posting API* enabled.
3. Copy `oauth.local.example.json` to `oauth.local.json` (git-ignored) and fill in
   the client id/secret and TikTok client key/secret.

Credential checklist:

- YouTube:
  1. In Google Cloud Console, enable **YouTube Data API v3** for the project.
  2. On the **OAuth consent screen**, set user type **External** and leave the
     publishing status on **Testing** (do *not* click "Publish app" — the
     `youtube.upload` scope is sensitive and Production would force Google's full
     verification/audit). Under **Test users**, add the exact Google account you
     sign in with (e.g. `aryan.saproo@gmail.com`); in Testing mode only listed test
     users can pass consent.
  3. Create an OAuth client of type **Desktop app** (the loopback redirect
     `http://127.0.0.1:<port>/` the app uses is auto-allowed, nothing to register).
  4. Paste its client id and client secret into `YOUTUBE_CLIENT_ID` and
     `YOUTUBE_CLIENT_SECRET`.
- TikTok:
  1. In TikTok for Developers, create an app and add the **Desktop** platform.
  2. Add **Login Kit** and register this redirect URI:
     `http://127.0.0.1:*/`
  3. Add **Content Posting API**, enable **Direct Post**, and request approval
     for the `video.publish` scope.
  4. Paste the app's Client key and Client secret into `TIKTOK_CLIENT_KEY` and
     `TIKTOK_CLIENT_SECRET`.

Run with the credentials injected:

```powershell
dart run tool/check_oauth_config.dart youtube
flutter run -d windows
```

Use `dart run tool/check_oauth_config.dart all` when YouTube and TikTok
credentials are both filled.

For local development the app reads `oauth.local.json` from the project root if
no `--dart-define` values are present. For release builds/installers, still use
`--dart-define-from-file=oauth.local.json` so the credentials are available when
the installed app is launched outside this folder.

Optional YouTube live upload smoke test, after the YouTube config check passes:

```powershell
ffmpeg -y -f lavfi -i testsrc2=size=720x1280:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 6 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 30 -c:a aac -b:a 96k -shortest "build\upload_smoke\upload_smoke.mp4"
dart run tool/publish_video.dart youtube "build\upload_smoke\upload_smoke.mp4" --title "Content Maker private upload test" --privacy private
```

After TikTok credentials are filled, run the same config check with `all` and use
the TikTok smoke command:

```powershell
dart run tool/check_oauth_config.dart all
dart run tool/publish_video.dart tiktok "build\upload_smoke\upload_smoke.mp4" --title "Content Maker private upload test" --privacy private
```

The smoke-test command opens your browser for OAuth and uploads the selected
file directly. Start with `--privacy private`; unaudited TikTok apps are private
only anyway.

Notes:

- The first sign-in per platform opens your browser once; refresh tokens keep
  later posts hands-off.
- On the first YouTube consent, the browser shows "Google hasn't verified this
  app" (expected for an unverified personal app). Click **Advanced → Go to
  Content Maker (unsafe)**, leave both YouTube permission boxes checked, and
  **Allow**. You have 15 minutes to finish before the connect times out.
- TikTok posts stay private until your developer app passes TikTok's audit.
- Instagram Reels have no compliant API for personal accounts, so that option
  opens the rendered file for a manual upload instead of auto-posting.
- Building on Windows needs Developer Mode enabled (`start ms-settings:developers`).

## Building the Windows installer (MSIX)

The app ships FFmpeg with it, so end users don't need it installed.

Recommended release command:

```powershell
.\tool\build_windows_release.ps1 -OAuthTarget youtube -CopyFfmpegFromPath
```

That validates OAuth config, copies `ffmpeg.exe`/`ffprobe.exe` from PATH into the
git-ignored `windows/ffmpeg/` folder, runs analyzer/tests, builds the Windows
release, creates `dist/ContentMaker-windows-x64.zip`, and then creates the MSIX.
See `docs/distribution_checklist.md` for beta vs public distribution notes.

Manual steps:

1. **Drop FFmpeg binaries** into `windows/ffmpeg/` (`ffmpeg.exe` and
   `ffprobe.exe`). They're git-ignored; see `windows/ffmpeg/README.md` for where
   to download them. Without them the build still works but relies on FFmpeg
   being on the user's PATH.
2. **Build the release app** (bakes in OAuth keys + bundles FFmpeg):
   ```powershell
   flutter build windows --release --dart-define-from-file=oauth.local.json
   ```
3. **Package the installer** without rebuilding (so the keys/FFmpeg are kept):
   ```powershell
   dart run msix:create --build-windows false
   ```
   Output: `build/windows/x64/runner/Release/content_maker.msix`.

Signing:

- For local testing, msix signs with a generated test certificate and prints how
  to trust it (install the cert into *Local Machine → Trusted People*), then
  double-click the `.msix` to install.
- For real distribution, sign with a proper code-signing certificate by adding
  `certificate_path` / `certificate_password` under `msix_config` in
  `pubspec.yaml`, or publish to the Microsoft Store (which signs for you).

Runtime FFmpeg resolution order (`lib/src/infrastructure/ffmpeg/ffmpeg_executables.dart`):
`FFMPEG_LOCATION` env var → next to the app `.exe` → `ffmpeg/` subfolder → PATH.

## Current Architecture

```text
lib/src/domain/rendering        Render presets, jobs, processor contract
lib/src/application             Use cases
lib/src/infrastructure/ffmpeg   FFmpeg adapter and command builder
lib/src/presentation            Flutter screens
```

Android-native video rendering will be added behind the same `VideoProcessor`
contract, so the app surface does not need to care whether export is handled by
FFmpeg, Media3, or a future cloud renderer.
