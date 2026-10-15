#!/bin/sh
set -eu
INTERNAL="$PWD/build/internal"
mkdir -p "$INTERNAL/tests/browser"
"$CC" -O2 -std=c11 -Wall -Wextra -isysroot "$SDK" -I"$INTERNAL/generated" --ld-path="$LD" \
    tests/core-check.c core/image.c core/reveal.c core/timeline.c -o "$INTERNAL/tests/core-check"
"$INTERNAL/tests/core-check"
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/wasm-compare.js
"$CC" -O2 -std=c11 -Wall -Wextra -isysroot "$SDK" -I"$INTERNAL/generated" --ld-path="$LD" \
    tests/sound-start-check.c core/image.c core/reveal.c core/timeline.c -o "$INTERNAL/tests/sound-start-check"
"$INTERNAL/tests/sound-start-check"
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/sound-start-check.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/i18n-check.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/image-import-check.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/video-size-check.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/import-lifecycle-check.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/preview-clock-check.js
"$CC" -O2 -fobjc-arc -Wno-deprecated-declarations -isysroot "$SDK" --ld-path="$LD" \
    tests/media-check.m -framework Foundation -framework AVFoundation -framework ImageIO \
    -framework CoreGraphics -framework CoreMedia -framework CoreVideo -framework AudioToolbox -o "$INTERNAL/tests/media-check"
"$INTERNAL/tests/media-check" fixture "$INTERNAL/tests/fixture.png"
"$INTERNAL/tests/media-check" sound-start-fixture "$INTERNAL/tests/sound-start.png"
"$INTERNAL/tests/media-check" audio-fixture "$INTERNAL/tests/replacement.wav"
/usr/bin/afconvert -f m4af -d aac -b 96000 -q 127 -s 0 "$INTERNAL/tests/replacement.wav" "$INTERNAL/tests/replacement.m4a"
./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli.mp4" --duration .4 --fps 10 --blank .2 --hold .3
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/cli.mp4" 10 66 50 > "$INTERNAL/tests/cli-report.json"
"$INTERNAL/tests/media-check" chunks "$INTERNAL/tests/baseline.mp4"
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/mp4-check.js
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/js-writer.mp4" 10 66 50 > "$INTERNAL/tests/js-writer-report.json"
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/baseline.mp4" 10 66 50 > "$INTERNAL/tests/baseline-report.json"
cmp "$INTERNAL/tests/baseline-report.json" "$INTERNAL/tests/js-writer-report.json"
if ./build/copland_video_tool "$INTERNAL/tests/fixture.png" --fps 0 > "$INTERNAL/tests/invalid-cli.log" 2>&1; then echo 'Invalid CLI options were accepted' >&2; exit 1; fi
"$CC" -O2 -fobjc-arc -Wno-deprecated-declarations -isysroot "$SDK" --ld-path="$LD" \
    -I"$INTERNAL/generated" tests/audio-check.m -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -o "$INTERNAL/tests/audio-check"
for FPS in 1 29.97 120; do
    case "$FPS" in 1) LEAD=default;; 29.97) LEAD=0;; 120) LEAD=1.234;; esac
    if [ "$LEAD" = default ]; then
        ./build/copland_video_tool "$INTERNAL/tests/sound-start.png" "$INTERNAL/tests/cli-start-$FPS-$LEAD.mp4" --fps "$FPS" --hold 6.125
    else
        ./build/copland_video_tool "$INTERNAL/tests/sound-start.png" "$INTERNAL/tests/cli-start-$FPS-$LEAD.mp4" --fps "$FPS" --blank "$LEAD" --hold 6.125
    fi
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/cli-start-$FPS-$LEAD.mp4" "$FPS" sound-start "$LEAD" 6.125
done
/bin/sh tests/sound-default-check.sh
for FPS in 1 24 29.97 30 60 120; do
    ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli-sound-$FPS.mp4" --sound --fps "$FPS"
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/cli-sound-$FPS.mp4" "$FPS" reveal
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/js-sound-$FPS.mp4" "$FPS"
    ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli-extended-$FPS.mp4" --sound --hold 6.125 --fps "$FPS"
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/cli-extended-$FPS.mp4" "$FPS" reveal default 6.125
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/js-extended-sound-$FPS.mp4" "$FPS" timing default 6.125
done
for HOLD in 0 1 6.125; do
    ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli-hold-$HOLD.mp4" --hold="$HOLD" --sound --fps 29.97
    "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/cli-hold-$HOLD.mp4" 29.97 reveal default "$HOLD"
done
for HOLD in -1 NaN inf 1e308; do
    set +e
    ./build/copland_video_tool "$INTERNAL/tests/fixture.png" --sound --hold="$HOLD" > "$INTERNAL/tests/invalid-sound-hold.log" 2>&1
    STATUS=$?
    set -e
    [ "$STATUS" = 2 ] || { echo 'Invalid sound hold was accepted' >&2; exit 1; }
done
for LEAD in 0 1.234; do
    for ORDER in before after; do
        if [ "$ORDER" = before ]; then
            ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli-lead-$LEAD-$ORDER.mp4" --blank "$LEAD" --sound --fps 29.97
        else
            ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli-lead-$LEAD-$ORDER.mp4" --sound --blank="$LEAD" --fps 29.97
        fi
        "$INTERNAL/tests/audio-check" assets/copland-theme.m4a "$INTERNAL/tests/cli-lead-$LEAD-$ORDER.mp4" 29.97 reveal "$LEAD"
    done
done
for LEAD in -1 NaN inf 999; do
    set +e
    ./build/copland_video_tool "$INTERNAL/tests/fixture.png" --sound --blank="$LEAD" > "$INTERNAL/tests/invalid-sound-lead.log" 2>&1
    STATUS=$?
    set -e
    [ "$STATUS" = 2 ] || { echo 'Invalid sound lead-in was accepted' >&2; exit 1; }
done
for OPTION in '--duration=9' '--keyframes=0:5,9:1'; do
    for ORDER in before after; do
        set +e
        if [ "$ORDER" = before ]; then
            ./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$OPTION" --sound > "$INTERNAL/tests/sound-conflict.log" 2>&1
        else
            ./build/copland_video_tool "$INTERNAL/tests/fixture.png" --sound "$OPTION" > "$INTERNAL/tests/sound-conflict.log" 2>&1
        fi
        STATUS=$?
        set -e
        [ "$STATUS" = 2 ] || { echo 'Conflicting sound options were accepted' >&2; exit 1; }
    done
done
/bin/sh tests/sound-swap-check.sh
RELEASE=$(cat build/web/release.txt)
sed "s/__RELEASE__/$RELEASE/g" tests/browser-check.html > "$INTERNAL/tests/browser/index.html"
sed "s/__RELEASE__/$RELEASE/g" tests/sound-ui-check.html > "$INTERNAL/tests/browser/sound-ui.html"
sed "s/__RELEASE__/$RELEASE/g" tests/image-import-check.html > "$INTERNAL/tests/browser/image-import.html"
# Only the syntax is checked here. A system browser runs the WebCodecs checks.
for SOURCE in web/*.js; do
    sed '/^import /d;s/^export //' "$SOURCE" > "$INTERNAL/tmp/js-syntax.js"
    printf '\nvar testDone = true;\n' >> "$INTERNAL/tmp/js-syntax.js"
    # Native JavaScriptCore parses modules through a Function constructor without
    # executing browser-only APIs. import.meta is legal only inside a module.
    printf 'new Function(readText("build/internal/tmp/js-syntax.js").replace(/import\\.meta/g,"({url: \\\"file:///test/\\\"})")); var testDone=true;\n' > "$INTERNAL/tmp/parse.js"
    "$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" "$INTERNAL/tmp/parse.js"
done
printf 'Checks passed. Browser test page: build/internal/tests/browser/index.html\n'
