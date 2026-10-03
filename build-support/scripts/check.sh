#!/bin/sh
set -eu
INTERNAL="$PWD/build/internal"
mkdir -p "$INTERNAL/tests/browser"
"$CC" -O2 -std=c11 -Wall -Wextra -isysroot "$SDK" --ld-path="$LD" \
    tests/core-check.c core/image.c core/reveal.c core/timeline.c -o "$INTERNAL/tests/core-check"
"$INTERNAL/tests/core-check"
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/wasm-compare.js
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/i18n-check.js
"$CC" -O2 -fobjc-arc -Wno-deprecated-declarations -isysroot "$SDK" --ld-path="$LD" \
    tests/media-check.m -framework Foundation -framework AVFoundation -framework ImageIO \
    -framework CoreGraphics -framework CoreMedia -framework CoreVideo -o "$INTERNAL/tests/media-check"
"$INTERNAL/tests/media-check" fixture "$INTERNAL/tests/fixture.png"
./build/copland_video_tool "$INTERNAL/tests/fixture.png" "$INTERNAL/tests/cli.mp4" --duration .4 --fps 10 --blank .2 --hold .3
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/cli.mp4" 10 66 50 > "$INTERNAL/tests/cli-report.json"
"$INTERNAL/tests/media-check" chunks "$INTERNAL/tests/baseline.mp4"
"$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/mp4-check.js
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/js-writer.mp4" 10 66 50 > "$INTERNAL/tests/js-writer-report.json"
"$INTERNAL/tests/media-check" inspect "$INTERNAL/tests/baseline.mp4" 10 66 50 > "$INTERNAL/tests/baseline-report.json"
cmp "$INTERNAL/tests/baseline-report.json" "$INTERNAL/tests/js-writer-report.json"
if ./build/copland_video_tool "$INTERNAL/tests/fixture.png" --fps 0 > "$INTERNAL/tests/invalid-cli.log" 2>&1; then echo 'Invalid CLI options were accepted' >&2; exit 1; fi
RELEASE=$(cat build/web/release.txt)
sed "s/__RELEASE__/$RELEASE/g" tests/browser-check.html > "$INTERNAL/tests/browser/index.html"
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
