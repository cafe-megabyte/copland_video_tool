#!/bin/sh
# Replace the asset and just two cue values in isolated source copies.
set -eu
INTERNAL="$PWD/build/internal"
SOURCE_ROOT=$PWD
SWAP="$INTERNAL/tests/sound-swap"
rm -rf "$SWAP"
mkdir -p "$SWAP/core" "$SWAP/macos" "$SWAP/web" "$SWAP/tests" "$SWAP/generated"
cp core/* "$SWAP/core/"
cp macos/main.m "$SWAP/macos/"
cp -R web/native "$SWAP/web/"
cp tests/core-check.c tests/audio-check.m "$SWAP/tests/"
sed -e 's/^#define COPLAND_SOUND_REVEAL_START .*/#define COPLAND_SOUND_REVEAL_START 0.25/' \
    -e 's/^#define COPLAND_SOUND_REVEAL_END .*/#define COPLAND_SOUND_REVEAL_END 2.0/' \
    core/soundtrack.h > "$SWAP/core/soundtrack.h"
"$INTERNAL/host-tools/audio-info" "$INTERNAL/tests/replacement.m4a" > "$SWAP/generated/soundtrack-audio.h"
"$CC" -O2 -std=c11 -Wall -Wextra -fobjc-arc -Wno-deprecated-declarations -isysroot "$SDK" \
    -I"$SWAP/generated" --ld-path="$LD" \
    "$SWAP/core/reveal.c" "$SWAP/core/image.c" "$SWAP/core/timeline.c" "$SWAP/macos/main.m" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -framework CoreVideo -framework CoreMedia -framework AVFoundation \
    -Wl,-sectcreate,__TEXT,__copland_sound,"$INTERNAL/tests/replacement.m4a" -lm -o "$SWAP/cli"
"$CC" -O2 -std=c11 -Wall -Wextra -isysroot "$SDK" -I"$SWAP/generated" --ld-path="$LD" \
    "$SWAP/tests/core-check.c" "$SWAP/core/reveal.c" "$SWAP/core/image.c" "$SWAP/core/timeline.c" -o "$SWAP/core-check"
"$CC" -O2 -fobjc-arc -Wno-deprecated-declarations -isysroot "$SDK" -I"$SWAP/generated" --ld-path="$LD" \
    "$SWAP/tests/audio-check.m" -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -o "$SWAP/audio-check"
"$CC" --target=wasm32-unknown-unknown -ffreestanding -fno-builtin -O3 -std=c11 -Wall -Wextra \
    -I"$SWAP/web/native/include" -I"$SWAP/generated" -c "$SWAP/web/native/wasm-adapter.c" -o "$SWAP/engine.o"
"$INTERNAL/toolchain/xcc/source/wcc" -nostdlib --entry-point= --stack-size=65536 \
    -e abi_version -e configure_memory -e prepare -e set_keyframe -e render -e sound_time -e timeline_value \
    -Wl,--allow-undefined -o "$SWAP/engine.wasm" "$SWAP/engine.o"
(
    cd "$SWAP"
    mkdir -p build/internal/tests
    ./core-check
    "$INTERNAL/host-tools/js-runner" "$SWAP/engine.wasm" "$SOURCE_ROOT/tests/wasm-compare.js"
)
"$INTERNAL/host-tools/js-runner" "$SWAP/engine.wasm" tests/sound-swap-check.js
for FPS in 1 24 29.97 30 60 120; do
    "$SWAP/cli" "$INTERNAL/tests/fixture.png" "$SWAP/cli-$FPS.mp4" --sound --fps "$FPS"
    "$SWAP/audio-check" "$INTERNAL/tests/replacement.m4a" "$SWAP/cli-$FPS.mp4" "$FPS" reveal
    "$SWAP/audio-check" "$INTERNAL/tests/replacement.m4a" "$INTERNAL/tests/js-replacement-$FPS.mp4" "$FPS"
    "$SWAP/audio-check" "$INTERNAL/tests/replacement.m4a" "$INTERNAL/tests/js-extended-replacement-$FPS.mp4" "$FPS" timing default 6.125
done
"$SWAP/cli" "$INTERNAL/tests/fixture.png" "$SWAP/cli-extended.mp4" --sound --hold 6.125 --fps 60
"$SWAP/audio-check" "$INTERNAL/tests/replacement.m4a" "$SWAP/cli-extended.mp4" 60 reveal default 6.125
printf 'Audio replacement passed: two cue changes, automatic duration, 48 kHz mono, native/WASM frames and unchanged AAC/PCM.\n'
