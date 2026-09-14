[CmdletBinding()]
param(
  [ValidateSet('youtube', 'tiktok', 'instagram', 'all')]
  [string]$OAuthTarget = 'youtube',

  [string]$ConfigPath = 'oauth.local.json',

  [switch]$CopyFfmpegFromPath,

  [switch]$SkipTests,

  [switch]$SkipMsix,

  [switch]$NoPortableZip
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ConfigFullPath = Join-Path $RepoRoot $ConfigPath
$FfmpegDir = Join-Path $RepoRoot 'windows\ffmpeg'
$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$ExePath = Join-Path $ReleaseDir 'content_maker.exe'
$DistDir = Join-Path $RepoRoot 'dist'
$ZipPath = Join-Path $DistDir 'ContentMaker-windows-x64.zip'
$MsixPath = Join-Path $ReleaseDir 'content_maker.msix'

function Write-Step {
  param([string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH."
  }
}

function Copy-ToolFromPath {
  param(
    [string]$Name,
    [string]$Destination
  )

  $Command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $Command) {
    throw "Could not find $Name on PATH."
  }

  New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
  Copy-Item -LiteralPath $Command.Source -Destination $Destination -Force
  Write-Host "Copied $($Command.Source) -> $Destination"
}

Set-Location $RepoRoot

Write-Step 'Checking release tools'
Require-Command flutter
Require-Command dart

Write-Step 'Checking OAuth config'
if (-not (Test-Path -LiteralPath $ConfigFullPath)) {
  throw "Missing $ConfigPath. Copy oauth.local.example.json to $ConfigPath and fill the release credentials."
}
dart run tool\check_oauth_config.dart $OAuthTarget $ConfigPath

if ($CopyFfmpegFromPath) {
  Write-Step 'Copying FFmpeg binaries from PATH'
  Copy-ToolFromPath 'ffmpeg' (Join-Path $FfmpegDir 'ffmpeg.exe')
  Copy-ToolFromPath 'ffprobe' (Join-Path $FfmpegDir 'ffprobe.exe')
}

Write-Step 'Checking bundled FFmpeg'
$BundledFfmpeg = Test-Path -LiteralPath (Join-Path $FfmpegDir 'ffmpeg.exe')
$BundledFfprobe = Test-Path -LiteralPath (Join-Path $FfmpegDir 'ffprobe.exe')
if ($BundledFfmpeg -and $BundledFfprobe) {
  Write-Host 'FFmpeg and FFprobe will be bundled into the release.'
} else {
  Write-Warning 'FFmpeg/FFprobe are not both present in windows\ffmpeg. The app will build, but users will need FFmpeg on PATH unless you rerun with -CopyFfmpegFromPath.'
}

if (-not $SkipTests) {
  Write-Step 'Running analyzer and tests'
  flutter analyze
  flutter test
}

Write-Step 'Building Windows release'
# Never let an installer produced by an older build slip into the portable ZIP.
# A fresh MSIX, when requested, is created separately after the ZIP is packaged.
if (Test-Path -LiteralPath $MsixPath) {
  Remove-Item -LiteralPath $MsixPath -Force
}
flutter build windows --release --dart-define-from-file=$ConfigPath

if (-not (Test-Path -LiteralPath $ExePath)) {
  throw "Expected release executable was not found at $ExePath."
}

if (-not $NoPortableZip) {
  Write-Step 'Creating portable ZIP'
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }
  Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $ZipPath -Force
  Write-Host "Portable ZIP: $ZipPath"
}

if (-not $SkipMsix) {
  Write-Step 'Creating MSIX installer'
  dart run msix:create --build-windows false --install-certificate false
  if (Test-Path -LiteralPath $MsixPath) {
    Write-Host "MSIX installer: $MsixPath"
  } else {
    Write-Warning "MSIX command finished, but $MsixPath was not found. Check msix output above."
  }
}

Write-Step 'Release build complete'
Write-Host "Release folder: $ReleaseDir"
if (Test-Path -LiteralPath $ZipPath) {
  Write-Host "Portable ZIP:   $ZipPath"
}
if (Test-Path -LiteralPath $MsixPath) {
  Write-Host "MSIX installer: $MsixPath"
}
