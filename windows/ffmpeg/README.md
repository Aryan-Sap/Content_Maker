# Bundled FFmpeg binaries

Place **`ffmpeg.exe`** and **`ffprobe.exe`** in this folder before building a
release/MSIX. They are copied next to the app executable during
`flutter build windows --release` (see the install rule in
`windows/CMakeLists.txt`) and resolved at runtime by
`lib/src/infrastructure/ffmpeg/ffmpeg_executables.dart`.

The binaries are **git-ignored** (they are large and license-bearing) — each
developer/CI drops their own copy here.

## Where to get them

Download a Windows build from a trusted source, for example the "essentials"
build from <https://www.gyan.dev/ffmpeg/builds/> or
<https://github.com/BtbN/FFmpeg-Builds/releases>, and copy `ffmpeg.exe` and
`ffprobe.exe` out of its `bin/` folder into this directory.

## License note

FFmpeg is distributed under the LGPL/GPL. If you redistribute the app with these
binaries, comply with the license of the specific build you ship (include the
license text / offer of source as required).
