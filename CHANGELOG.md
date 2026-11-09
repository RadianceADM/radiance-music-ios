# Changelog

## 0.1.0 (in progress)

- Stage 0: the project (SwiftPM + xtool, built on Linux), the app icon (the setting sun), a first screen in
  Radiance's colours.
- RadianceKit: songs (the computer's and Android's JSON), Liked Songs A to Z, history, where you left off, the
  Albums/Artists/Genres shelves, saving with covers and lyrics, songs found in the Files folder, the computer's
  library.json import, the Internet Archive, LRCLIB and YouTube Music lyrics, Deezer genres, sharp covers, plain-words
  errors, the Radiance Music Server client. 53 tests, most ported from the Android app.
- YouTube songs: a joined server's copy first (the same artist and title, as Android matches it), else from YouTube
  itself; liked ones are saved as .m4a.
- Stage 1: search with suggestions, the player (background, lock screen, Control Center, headphone buttons, pause when
  headphones come out), queue (move, take out), shuffle, repeat, songs like this, where you left off, "Loading…",
  plain-words errors (skip, stop after 3 in a row).
- Stage 2: Library pills (Liked Songs, History, Albums, Artists, Genres, each joined server), Home rows, genres from
  Deezer, songs found in Files → Radiance Music, the computer's library (scripts/push-library.sh).
- Stage 3: Now Playing with the cover's colours flowing, lyrics with the sung line lit (tap to jump, hold to share).
- Stage 4: the Mixer (Song / Karaoke / Vocals only, carried from song to song; low cut, high cut, reverb), splitting
  on the iPhone (Spleeter on ONNX Runtime, pauses when hot or low on battery), the split song and its parts sent to
  the joined server.
- Stage 5 (part): share songs by QR (the same wire as Android and the computer), server libraries (search, save, split
  there), joining a server from its invite QR.
- Stage 6 (part): story cards (a song, or a lyric line), a sidebar on iPad and wide windows.
