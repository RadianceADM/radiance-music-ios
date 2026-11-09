#!/bin/bash
# The computer's Radiance Music library onto the iPhone (as ~/Downloads/rm-phone-library/push.sh did for the S24):
# the liked songs with their covers and lyrics, read by the app's Import into Liked Songs.
#   scripts/push-library.sh [HOW_MANY]     (all of them without a number)
# The computer's songs are Opus in Ogg, which the iPhone's player can't open: on ribs02 (builds and conversions run
# there, never on the laptop) each goes into an MP4 (.m4a) as it is (CONV=copy, no re-encoding), or into AAC
# (CONV=aac, 256 kbps) if the iPhone won't play that. Then they go
# over USB into the app's Documents (Files → Radiance Music) and Documents/Library, library.json last.
# The split parts (Vorbis, which the iPhone can't open either) become AAC (.m4a, 160 kbps) for the Mixer: the four
# (and Piano, Guitar), or the two halves when that's all a song has. PARTS=0 leaves them out. Scratch: ribs02 /srv/build/src/rm-ios-import and
# ~/.cache/rm-ios-import here, both deleted at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
LIB=${LIB:-$HOME/Downloads/rm-phone-library/library.json}
MUSIC="$HOME/Music/Radiance Music"
WORK=/srv/build/src/rm-ios-import
HERE=$HOME/.cache/rm-ios-import
APP=${APP:-XTL-F9JU94RG3U.io.github.radianceadm.music}
PMD=$HOME/.local/share/rm-ios-tools/venv/bin/pymobiledevice3
quiet() { grep -v -e '^---' -e 'Radiance Innovation' -e AUTHORIZED -e 'Personal data' -e 'Questions:' || true; }

rm -rf "$HERE"; mkdir -p "$HERE/in" "$HERE/out"
# the iPhone's library.json (songs as .caf, no parts yet) and the files it needs
python3 - "$LIB" "${1:-0}" "$HERE" "${PARTS:-1}" <<'PY'
import json, os, sys
lib, most, here, withparts = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4] == "1"
songs = json.load(open(lib))["songs"]
if most > 0: songs = songs[:most]
need, out = [], []
for e in songs:
    name = e["song"]
    base, ext = os.path.splitext(name)
    need.append(name)
    e = dict(e)
    if ext.lower() == ".opus": e["song"] = base + ".m4a"
    parts = e.pop("parts", None) or {}
    four = all(k in parts for k in ("drums", "bass", "other", "vocals"))
    keep = [k for k in parts if (k in ("drums", "bass", "other", "vocals", "piano", "guitar")) if four] if four else [k for k in parts if k in ("music", "vocals")]
    if withparts and keep:
        e["parts"] = {}
        for k in keep:
            need.append(parts[k])
            e["parts"][k] = os.path.splitext(parts[k])[0] + ".m4a"
    for k in ("cover", "lrc", "lyricsfile"):
        if e.get(k): need.append(e[k])
    out.append(e)
json.dump({"songs": out}, open(os.path.join(here, "library.json"), "w"), ensure_ascii=False, indent=1)
open(os.path.join(here, "need.txt"), "w").write("\n".join(need) + "\n")
print(f"{len(out)} songs, {len(need)} files")
PY
ssh ribs "rm -rf $WORK && install -d -o radmin -g radmin $WORK/in '$WORK/out/Radiance Music' $WORK/out/Library" 2>&1 | quiet
rsync -a --files-from="$HERE/need.txt" "$MUSIC/" "ribs:$WORK/in/" 2>&1 | quiet
CONV=${CONV:-copy}
# Opus into an .m4a (as it is, or as AAC); covers, lyrics and other songs as they are
ssh ribs "chown -R radmin: $WORK && cd $WORK && sudo -u radmin bash -c '
  cd $WORK/in
  for f in *; do
    case \"\${f,,}\" in
      *.opus) if [ $CONV = aac ]; then codec=\"-c:a libfdk_aac -b:a 256k\"; else codec=\"-c:a copy\"; fi
              nice -n 19 ffmpeg -nostdin -loglevel error -y -i \"\$f\" -map 0:a:0 \$codec -movflags +faststart -f mp4 \"../out/Radiance Music/\${f%.*}.m4a\" ;;
      *.m4a|*.flac|*.mp3) cp \"\$f\" \"../out/Radiance Music/\" ;;
      *.ogg) nice -n 19 ffmpeg -nostdin -loglevel error -y -i \"\$f\" -map 0:a:0 -c:a libfdk_aac -b:a 160k -movflags +faststart -f mp4 \"../out/Library/\${f%.*}.m4a\" ;;
      *) cp \"\$f\" ../out/Library/ ;;
    esac
  done
  du -sh ../out/*'" 2>&1 | quiet
rsync -a "ribs:$WORK/out/" "$HERE/out/" 2>&1 | quiet
# onto the iPhone: the songs' folder, the covers' and lyrics' folder (pushed whole: a push makes the folders it
# brings, inside Documents), then library.json (the app reads it when it's new). Paths start at the app's folder.
push() { "$PMD" apps push --documents "$APP" "$1" "$2" 2>&1 | { grep -v -e INFO -e '^\s*$' || true; } | tail -3; }
push "$HERE/out/Radiance Music" "Documents"
push "$HERE/out/Library" "Documents"
push "$HERE/library.json" "Documents/Library/library.json"
echo "pushed: $(ls "$HERE/out/Radiance Music" | wc -l) songs, $(ls "$HERE/out/Library" | wc -l) covers and lyrics"
ssh ribs "rm -rf $WORK" 2>&1 | quiet
rm -rf "$HERE"
