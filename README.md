# Radiance Music for iPhone and iPad

Radiance Music on iOS: a Swift and SwiftUI twin of the Android app
([radiance-music-android](https://github.com/RadianceADM/radiance-music-android)). It reads and writes the same song
JSON, library files and share wire as the Android app and the computer app
([radiance-music](https://github.com/RadianceADM/radiance-music)). No music videos on mobile.

**Status: 0.1.0 in progress.** On the test iPhone: search (Internet Archive first, YouTube Music after), playing in
the background with the lock screen's controls, the queue, Liked Songs with Albums, Artists and Genres, lyrics,
the Mixer (karaoke, vocals only, low cut, high cut, reverb), splitting on the iPhone (Spleeter on ONNX Runtime),
sharing songs by QR with phones and the computer, Radiance Music Server libraries, story cards. Not released yet.

A YouTube song plays from a joined server's copy when the server has it, else from YouTube itself (the owner's rule
for every app). A song split on the iPhone goes up to the server it joined.

## Layout

| Folder | What |
|---|---|
| `Sources/RadianceKit` | songs, library, lyrics, search sources, plain-words errors. Foundation only, so it is tested on Linux |
| `Sources/RadianceMusic` | the app: SwiftUI, AVFoundation, MediaPlayer |
| `Tests/RadianceKitTests` | `swift test` (ports of the Android unit tests, plus samples from the computer and Android) |
| `scripts/ribs.sh` | test, build and install on the build server |

## Building (no Mac)

Built on Linux with [xtool](https://github.com/xtool-org/xtool) and the Swift 6.4 toolchain, on the build server:

```
scripts/ribs.sh test      # RadianceKit tests (Linux)
scripts/ribs.sh build     # the .ipa, copied back to build/
scripts/ribs.sh install   # build (release), sign with the Apple ID, install on the iPhone plugged into this computer
scripts/push-library.sh   # the computer's liked songs (with covers, lyrics, parts) onto the iPhone
scripts/ribs.sh clean     # delete the server's build folder
```

Signed with a free Apple ID for now: a copy installed this way stops opening after 7 days and has to be installed
again (`scripts/ribs.sh install` with the iPhone plugged in).

## License

Closed source (owner, 2026-11-10: every Radiance Music app but the Radiance Music Server). © Radiance Innovation
Centers in the Philippines. All rights reserved. Third-party parts keep their own licenses: ONNX Runtime (MIT),
Spleeter (MIT) and its sherpa-onnx export (Apache 2.0).
