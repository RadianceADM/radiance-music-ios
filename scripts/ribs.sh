#!/bin/bash
# Radiance Music for iOS on ribs02 (owner: builds on ribs02, never on the laptop; no Mac).
#   scripts/ribs.sh test       the RadianceKit tests (Linux, swift test)
#   scripts/ribs.sh build      the app for the iPhone (xtool dev build --ipa): the .ipa comes back to ./build/
#   scripts/ribs.sh install    build, then put it on the iPhone on the laptop's USB (ribs02 reaches it through
#                              the laptop's usbmuxd, forwarded over ssh)
#   scripts/ribs.sh clean      delete the scratch copy's build folder on ribs02
# Runs as radmin at nice 19 in the scratch copy /srv/build/src/rm-ios.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=/srv/build/src/rm-ios
what=${1:-test}
quiet() { grep -v -e '^---' -e 'Radiance Innovation' -e AUTHORIZED -e 'Personal data' -e 'Questions:' || true; }

sync() {
    rsync -a --delete --exclude .build --exclude /build --exclude /xtool --exclude /.bsp --exclude .git --exclude '*.ipa' ./ "ribs:$SRC/" 2>&1 | quiet
    ssh ribs "chown -R radmin: $SRC" 2>&1 | quiet
}

case "$what" in
test)
    sync
    ssh ribs "cd $SRC && sudo -u radmin -H bash -c '. /srv/build/ios/env.sh; cd $SRC; RADIANCE_KIT_ONLY=1 RADIANCE_LIVE=${RADIANCE_LIVE:-0} nice -n 19 swift test ${TEST_FILTER:+--filter $TEST_FILTER} 2>&1'" 2>&1 | quiet
    ;;
build|install)
    sync
    ssh ribs "cd $SRC && sudo -u radmin -H bash -c '. /srv/build/ios/env.sh; cd $SRC; nice -n 19 xtool dev build --ipa ${CONFIG:+-c $CONFIG} 2>&1'" 2>&1 | quiet
    mkdir -p build
    ipa=$(ssh ribs "ls -t $SRC/xtool/*.ipa 2>/dev/null | head -1" 2>/dev/null | quiet)
    [ -n "$ipa" ] || { echo "no .ipa made"; exit 1; }
    scp -q "ribs:$ipa" build/RadianceMusic.ipa 2>&1 | quiet
    ls -la build/RadianceMusic.ipa
    if [ "$what" = install ]; then
        # ribs02's xtool talks to the iPhone through this laptop's usbmuxd (the phone on this USB), over a socket in
        # ribs02's /tmp that lasts only while this runs (SELinux lets sshd make one there, not in /srv/build or a port)
        sock=/tmp/rm-usbmuxd-$$.sock
        ssh -o ExitOnForwardFailure=yes -R "$sock:/var/run/usbmuxd" ribs \
            "chown radmin: $sock && cd $SRC && sudo -u radmin -H env USBMUXD_SOCKET_ADDRESS=UNIX:$sock bash -c '. /srv/build/ios/env.sh; cd $SRC; xtool dev run --usb 2>&1'; rm -f $sock" 2>&1 | quiet
    fi
    ;;
clean)
    ssh ribs "rm -rf $SRC/.build $SRC/xtool" 2>&1 | quiet
    ;;
*)
    echo "usage: $0 test|build|install|clean"; exit 2 ;;
esac
