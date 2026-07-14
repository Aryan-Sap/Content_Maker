# Claude Project Context

Last updated: 2026-07-14

## Project Summary

Content Maker is a Flutter/Dart app for turning gameplay footage into short-form video exports. The current implementation is focused on local desktop rendering through FFmpeg, with Flutter UI targets for Android and Windows already scaffolded.

App flow: **Login (local profiles) → Project hub (create/open a project, choosing the Simple or Custom pipeline) → workspace**. Profiles and the project library persist via `AppSessionStore` (`%APPDATA%/Content Maker/session.json`). Key files:

- `lib/src/application/app_session_store.dart` — profiles, project summaries, `ProjectPipeline` enum.
- `lib/src/presentation/onboarding/login_screen.dart` — profile picker/creator.
- `lib/src/presentation/onboarding/project_hub_screen.dart` — new-project form with pipeline cards + recent projects.
- `RenderHomeScreen` now takes `projectName` and `initialPipeline` and is pushed from the hub; the workspace switcher remains available.

The app has two main workspaces:

- Automatic renderer: single source video to a Shorts-style export with blurred background, centered foreground gameplay, trim controls, optional uploaded audio, audio volume controls, output resolution presets, color style presets, sharpness, motion blur, panning blur, and optional motion interpolation.
- Custom editor: manual multi-clip timeline editor with video/audio clip import, canvas preview, timeline trimming/splitting/duplicating/deleting, track controls, clip inspector, color grading, motion processing, basic transitions, and timeline export.

## Tech Stack

- Flutter app using Material 3.
- Dart SDK constraint: `^3.12.2`.
- Main dependencies: `flutter`, `cupertino_icons`, `path`, `http`, `url_launcher`,
  `flutter_secure_storage`, `crypto` (the last four power social publishing).
- Dev dependencies: `flutter_test`, `flutter_lints`.
- FFmpeg and FFprobe are expected to be available on PATH for rendering, metadata probing, thumbnail generation, and preview support.
- Windows has a native file picker bridge implemented with a Flutter `MethodChannel`.

## Important Commands

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Quick CLI render:

```powershell
dart run tool/render_short.dart "C:\path\input.mp4" "C:\path\output_shorts.mp4"
dart run tool/render_short.dart "C:\path\input.mp4" "C:\path\output_shorts.mp4" --interpolate
```

## Repository Layout

```text
lib/main.dart                              App entry point
lib/src/app/content_maker_app.dart         Material app/theme setup
lib/src/presentation/render_home_screen.dart
                                            Automatic render UI and mode switcher
lib/src/presentation/manual_editor_screen.dart
                                            Manual editor UI, timeline, preview, inspector
lib/src/application/                       Use cases that validate jobs then call processors
lib/src/domain/rendering/                  Automatic render domain objects/contracts
lib/src/domain/editing/                    Manual timeline domain objects/contracts
lib/src/infrastructure/ffmpeg/             FFmpeg command builders and processors
lib/src/domain/publishing/                 Publishing contracts, jobs, metadata, auth models
lib/src/application/publish_export.dart    Publish use case (token refresh + delegate)
lib/src/application/manage_accounts.dart   Connect/disconnect/list accounts
lib/src/infrastructure/publishing/         YouTube/TikTok/Instagram adapters + OAuth
lib/src/presentation/publishing/           Publish panel + accounts dialog
tool/render_short.dart                     CLI wrapper for automatic short render
test/                                      Widget, FFmpeg builder, and publishing tests
windows/runner/                            Windows shell plus native file picker channel
```

## Architecture

The code is organized in a lightweight clean-architecture style:

- Domain: immutable-ish job, preset, project, and clip models plus processor interfaces.
- Application: use-case classes that run validation before delegating to an implementation.
- Infrastructure: FFmpeg-backed processors and command builders.
- Presentation: Flutter screens that collect user input, manage UI state, and stream render progress.

The app is intended to keep rendering backend details behind processor contracts:

- `VideoProcessor` handles `ShortsRenderJob`.
- `ManualTimelineProcessor` handles `ManualRenderJob`.

This makes it possible to add Android-native rendering, Media3, or a cloud renderer later without forcing the UI to know how export is performed.

## Automatic Renderer Details

Key files:

- `lib/src/domain/rendering/render_preset.dart`
- `lib/src/domain/rendering/render_job.dart`
- `lib/src/infrastructure/ffmpeg/ffmpeg_command_builder.dart`
- `lib/src/infrastructure/ffmpeg/ffmpeg_video_processor.dart`
- `lib/src/presentation/render_home_screen.dart`

Default preset:

- `RenderPreset.gameplayShort`
- 1080x1920 canvas
- 608 px foreground height
- 60 fps
- `libx264`, CRF 16, preset `medium`
- AAC audio at 192k
- FPS conversion by default, optional `minterpolate` motion interpolation with a
  selectable `InterpolationQuality` (fast/balanced/quality, in
  `export_settings.dart`). When interpolation is on, `minterpolate` runs on the
  cropped foreground band only and the blurred background gets a cheap `fps`
  conversion — both land at the target rate before the overlay.

The automatic FFmpeg graph:

- Splits source video into background and foreground.
- Background is scaled/cropped to canvas, optionally panning-blurred and temporally blurred, gaussian blurred, darkened, and saturated.
- Foreground is scaled/cropped to foreground frame, color-adjusted, sharpened, and overlaid.
- Audio can use original source audio, source volume adjustment, or uploaded audio mixed with source audio via `amix`.
- Progress is parsed from FFmpeg `-progress pipe:1` using `out_time_ms`.

## Manual Editor Details

Key files:

- `lib/src/domain/editing/timeline_clip.dart`
- `lib/src/domain/editing/manual_edit_project.dart`
- `lib/src/domain/editing/manual_render_job.dart`
- `lib/src/infrastructure/ffmpeg/ffmpeg_manual_timeline_command_builder.dart`
- `lib/src/infrastructure/ffmpeg/ffmpeg_manual_timeline_processor.dart`
- `lib/src/presentation/manual_editor_screen.dart`

Manual project model:

- `ManualEditProject` stores output path, canvas size, frame rate, background color, blurred background toggle, and clips.
- `TimelineClip` supports video and audio clips.
- Clip properties include timeline start, trim range, track index, transform, opacity, volume, enabled/muted/locked state, grading values, motion blur, motion interpolation, panning blur, transition, source frame rate, source duration, and thumbnail path.
- Transitions: cut, dissolve, fade-through-black (outgoing fades out over the
  first half of the duration, incoming fades in over the second), slides/wipes
  (eased overlay movement), whip pan, zoom in/out (animated `scale` with
  `eval=frame` + alpha dissolve), circle open/close (animated `vignette`
  iris). Overlapping transitions hold the outgoing clip past its cut; the hold
  uses real source footage when the source has spare frames past the trim end
  (`sourceDurationSeconds` known), falling back to a `tpad` freeze frame.
- Timeline editing enforces no same-track overlaps (`_resolveTrackOverlap`),
  snaps clip edges/origin/playhead, splits are speed-aware and reset the second
  half's transition to cut, and duplicates land flush with the original.

The manual FFmpeg graph:

- Starts with a solid color base canvas.
- Layers enabled video clips by track/start order, with special ordering for adjacent transition clips.
- Optionally creates a blurred background layer per video clip.
- Applies trim, setpts, scaling, transform, grading, sharpness, motion filters, opacity, transitions, and overlay timing.
- Mixes enabled audible audio clips with trim, delay, volume, and `amix`.
- Progress is parsed from `out_time_ms` against project duration.

The manual editor UI is stateful and currently all in one large file. Be cautious when changing it: behavior is intertwined between clip normalization, timeline interactions, preview playback, inspector controls, and export job creation.

## Social Publishing

After a render completes, the app can push the video straight to YouTube (as a
Short) and TikTok via their official APIs, with Instagram present as a hand-off
stub. The slice mirrors the renderer's clean-architecture split so the UI streams
publish progress the same way it streams render progress.

Contract parallels:

- `VideoPublisher` (contract) ↔ `VideoProcessor`.
- `PublishJob` / `PublishProgress` ↔ `ShortsRenderJob` / `RenderProgress`.
- `PublishExport` use case ↔ `CreateShortsExport`.

Key files:

- `lib/src/domain/publishing/publish_target.dart` — `PublishTarget` enum + capability flags.
- `lib/src/domain/publishing/publish_metadata.dart` — title/description/hashtags/privacy/madeForKids + `validate()`.
- `lib/src/domain/publishing/video_publisher.dart` — the publisher contract.
- `lib/src/application/publish_export.dart` — validates, ensures a valid OAuth token (refresh → else interactive authorize), then delegates; merges multiple targets into one stream.
- `lib/src/infrastructure/publishing/oauth/` — PKCE, loopback redirect server, `AuthorizationCodeFlow`, secure token store, `OAuthConfig` (reads `--dart-define`s).
- `lib/src/infrastructure/publishing/youtube/` — Google OAuth + Data API v3 resumable chunked upload.
- `lib/src/infrastructure/publishing/tiktok/` — TikTok OAuth v2 + Content Posting API (`FILE_UPLOAD` + status poll).
- `lib/src/infrastructure/publishing/instagram/instagram_publisher.dart` — hand-off stub (see limitation below).
- `lib/src/infrastructure/publishing/publishing_registry.dart` — composition root wiring the default adapters.
- `lib/src/presentation/publishing/publish_panel.dart` — the post-render publish UI.

OAuth secrets are provided at run/build time, never committed:

```powershell
# copy oauth.local.example.json -> oauth.local.json and fill in values
flutter run -d windows --dart-define-from-file=oauth.local.json
```

Prerequisites (external, one-time): a Google Cloud OAuth "Desktop app" client with
the YouTube Data API v3 enabled, and a TikTok for Developers app with the Content
Posting API enabled.

Keep the Google OAuth consent screen in **Testing** and add the signing-in Google
account as a **test user** — the `youtube.upload` scope is sensitive, so Production
would trigger Google's verification/audit. On the first consent the browser shows
the "Google hasn't verified this app" warning; the user clicks **Advanced → Go to
Content Maker (unsafe)** and allows both scopes. The interactive consent window is
15 minutes (`AuthorizationCodeFlow.obtainCode` / `LoopbackRedirectServer.waitForCode`
defaults), widened from 5 min so the warning click-through does not time out.

Platform limitations to preserve:

- **Instagram**: official Reels publishing needs a Business/Creator account + a
  public HTTPS video URL. For personal accounts there is no compliant API, so the
  adapter is an honest hand-off (opens the rendered file for manual upload). To
  enable real automation later, add an `InstagramGraphPublisher implements
  VideoPublisher` and swap it in `PublishingRegistry` — no caller changes.
- **TikTok**: posts are `SELF_ONLY` (private/draft) until the developer app passes
  TikTok's content-posting audit. The API path is identical once audited.
- The first browser consent per platform is unavoidable; refresh tokens make later
  posts hands-off.

## Rendered Clip Preview, Notifications, Links

- `lib/src/presentation/widgets/rendered_clip_player.dart` — in-app player for
  finished renders (MJPEG frames piped from FFmpeg + ffplay audio, seek slider,
  play/pause). Shown in the auto workspace between the render controls and the
  publish panel, and at the top of the manual editor's publish sheet.
- `lib/src/infrastructure/notifications/desktop_notifier.dart` — best-effort
  native notifications (Windows WinRT toast via PowerShell, no plugin needed;
  osascript/notify-send elsewhere). Fired on render/export completion or
  failure and per-target upload completion/failure, alongside in-app snackbars.
- The publish panel renders `remoteUrl` as a clickable link (url_launcher,
  external browser) and the upload-complete snackbar has an "Open" action.
- `FfmpegExecutables.ffplay` resolves ffplay the same way as ffmpeg/ffprobe —
  never invoke `'ffplay'` by bare name.
- Editor preview: paused frames use fast input seeking (`-ss` before `-i`),
  streams/stills scale to `min(iw,1600)` (no upscaling), and preview `Image`
  widgets set `filterQuality`/`isAntiAlias`.

## Windows Native File Picker

The Flutter UI calls `MethodChannel('content_maker/file_picker')` with:

- `pickVideo`
- `pickAudio`

Windows implementation is in `windows/runner/flutter_window.cpp` and `windows/runner/flutter_window.h`. It uses `GetOpenFileNameW` and returns the selected path as a UTF-8 string. The picker is currently Windows-only from the UI perspective; the render processors are desktop-capable on Windows, macOS, and Linux.

## Tests

Current tests cover:

- Automatic FFmpeg command builder behavior.
- Manual timeline FFmpeg command builder behavior.
- Basic widget rendering for the renderer workspace.
- Switching into the custom editor workspace.

Relevant test files:

- `test/infrastructure/ffmpeg/ffmpeg_command_builder_test.dart`
- `test/infrastructure/ffmpeg/ffmpeg_manual_timeline_command_builder_test.dart`
- `test/widget_test.dart`

When changing FFmpeg command generation, prefer adding or updating command-builder tests first. They are fast and protect the most fragile behavior.

## Current Git State

At the time this file was created, the repository appeared to have all project files untracked in Git. Do not assume a clean committed baseline. Check `git status --short` before editing, staging, or committing.

## Implementation Notes And Gotchas

- Keep FFmpeg command construction covered by tests. Filter graph strings are easy to regress.
- Avoid making the presentation layer depend directly on FFmpeg details beyond existing processor construction.
- `manual_editor_screen.dart` is large; preserve existing interaction behavior unless intentionally refactoring.
- `copyWith` methods use nullable parameters, so they cannot currently distinguish "set this nullable field to null" from "leave unchanged" for nullable fields like thumbnail/source duration.
- FFmpeg and FFprobe availability is not validated at app startup; failures surface during probing/rendering.
- Android rendering is not implemented yet. Desktop FFmpeg rendering is the first working backend.
- The UI uses a dark visual language with a soft blue accent (`0xFF8AB4F8`) and
  8–12 px corner radii (theme in `content_maker_app.dart`). Preserve that style
  unless intentionally redesigning.
- Publishing plugins (`flutter_secure_storage`, `url_launcher`) are native. Building
  on Windows requires Developer Mode enabled (symlink support): `start ms-settings:developers`.
- Publishing OAuth client credentials come from `--dart-define`s (see `OAuthConfig`);
  without them the connect buttons surface a "not configured" message rather than crashing.
- Publisher request builders (`YoutubePublisher.buildVideoResource`,
  `TiktokPublisher.buildInitRequest`/`privacyLevel`) are covered by tests in
  `test/publishing/`; keep them green when changing API payloads.
- FFmpeg/FFprobe are never invoked by bare name anymore. Everything goes through
  `FfmpegExecutables.ffmpeg` / `.ffprobe`
  (`lib/src/infrastructure/ffmpeg/ffmpeg_executables.dart`), which prefers a
  bundled binary next to the app before falling back to PATH. When adding a new
  FFmpeg call, use the resolver, not a literal `'ffmpeg'`.
- Windows distribution is an MSIX built from `msix_config` in `pubspec.yaml`.
  FFmpeg binaries dropped into `windows/ffmpeg/` are copied next to the executable
  by an OPTIONAL install rule in `windows/CMakeLists.txt`. Package with a
  pre-built release: `dart run msix:create --build-windows false` (so dart-defined
  OAuth keys survive). See README "Building the Windows installer".
- Android is not yet buildable: the render pipeline spawns `ffmpeg` as a process,
  which Android cannot do. A native (no-cloud) Android render backend is the next
  planned effort and must replace the `Process.start` FFmpeg calls behind the
  existing `VideoProcessor`/`ManualTimelineProcessor` contracts.

## Good Next Areas

- Add a clearer project save/load model for manual edits.
- Break `manual_editor_screen.dart` into smaller widgets/controllers.
- Add backend abstraction for non-desktop rendering.
- Add user-facing validation for missing FFmpeg/FFprobe.
- Add more tests around manual editor job creation and domain validation.
- Consider integration tests with tiny generated media files if FFmpeg is available in CI/local environment.
