# Radiance Music for iPhone and iPad

Radiance Music on iOS: a Swift and SwiftUI twin of the Android app
([radiance-music-android](https://github.com/RadianceADM/radiance-music-android)). It reads and writes the same song
JSON, library files and share wire as the Android app and the computer app
([radiance-music](https://github.com/RadianceADM/radiance-music)). No music videos on mobile.

**Status: 0.1.0 in progress (stage 0).** The app opens. Search, Library and Now Playing come next.

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
scripts/ribs.sh install   # build, sign with the Apple ID, install on the iPhone plugged into this computer
scripts/ribs.sh clean     # delete the server's build folder
```

Signed with a free Apple ID for now: a copy installed this way stops opening after 7 days and has to be installed
again (`scripts/ribs.sh install` with the iPhone plugged in).

## License

GPL-3.0, like the Android app.
