# Distribution Checklist

Use this when turning the local Content Maker pipeline into a downloadable app.

## Beta download

This is the path we can build locally today.

1. Keep `oauth.local.json` out of git.
2. The production Google OAuth app is already verified, so beta testers need no
   allow-listing. Only a separate development client that is still in Testing
   mode needs testers listed under **Test users**.
3. Bundle FFmpeg so users do not need a separate install.
4. Add each Instagram beta account as an app tester in Meta when Instagram
   connection is enabled.
5. Build a Windows release:

   ```powershell
   .\tool\build_windows_release.ps1 -OAuthTarget youtube -CopyFfmpegFromPath
   ```

5. Share the portable ZIP from `dist\ContentMaker-windows-x64.zip`, or the MSIX
   from `build\windows\x64\runner\Release\content_maker.msix`.

The portable ZIP is best for fast beta testing. The MSIX is better for a real
installer, but local/test MSIX packages require users to trust the signing
certificate unless you use a real code-signing certificate or the Microsoft
Store.

## Public release

Before offering the app to arbitrary users:

1. ~~Move the Google OAuth consent screen from Testing to Production.~~ Done.
2. ~~Complete Google verification for the sensitive YouTube upload scope:
   `https://www.googleapis.com/auth/youtube.upload`.~~ Done: verified through
   Google Cloud Console.
3. Complete TikTok app review for Content Posting API access before enabling
   real TikTok posting for users.
4. Complete Meta App Review for Instagram professional accounts before making
   Instagram Login public.
5. Sign the Windows installer with a trusted code-signing certificate, or publish
   through the Microsoft Store.
6. Include FFmpeg license notices for the exact FFmpeg build shipped with the
   app.

Google verification is complete for the production client. Only a development
client still in Testing mode is limited to configured Google test users.
