#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
cd "$ROOT"
TARGET=${1:-all}
case "$TARGET" in all|cli|web|check|serve|clean|rebuild-toolchain) ;; *) echo "Unknown build target: $TARGET" >&2; exit 2;; esac
INTERNAL="$ROOT/build/internal"
LOCK="$INTERNAL/build.lock"
remove_tree() {
    # Finder may write .DS_Store while rm is traversing an open directory.
    # Retry the deletion, but preserve the failure for persistent errors.
    ATTEMPT=0
    while ! REMOVE_ERROR=$(/bin/rm -rf "$1" 2>&1); do
        ATTEMPT=$((ATTEMPT + 1))
        if [ "$ATTEMPT" -ge 3 ]; then printf '%s\n' "$REMOVE_ERROR" >&2; return 1; fi
        /bin/sleep 0.05
    done
}
release_lock() {
    remove_tree "$LOCK"
    if [ "$TARGET" = clean ]; then
        # Only remove empty parents after unlocking. A new build or Finder can
        # already be using them; never recursively delete them at this point.
        /bin/rmdir "$INTERNAL" 2>/dev/null || :
        /bin/rmdir "$ROOT/build" 2>/dev/null || :
    fi
}
if [ "${COPLAND_BUILD_INNER:-}" != 1 ]; then
    case "$ROOT" in *'"'*|*'\'*) echo 'Unsupported quotation character in project path' >&2; exit 2;; esac
    mkdir -p "$INTERNAL"
    if ! mkdir "$LOCK" 2>/dev/null; then
        if [ -f "$LOCK/pid" ]; then
            OWNER=$(cat "$LOCK/pid")
            if ! kill -0 "$OWNER" 2>/dev/null; then
                echo "Interrupted build lock ($OWNER). Remove build/internal/build.lock after verifying no build is running." >&2; exit 1
            fi
        fi
        echo 'Another build is running. Retry after it finishes; clean never interrupts it.' >&2
        exit 1
    fi
    echo $$ > "$LOCK/pid"
    trap 'release_lock' EXIT
    trap 'exit 130' INT TERM HUP
    # Acquire the lock before creating temporary files or replacing the profile.
    mkdir -p "$INTERNAL/tmp" "$INTERNAL/cache" "$INTERNAL/logs"
    cat > "$INTERNAL/build.sb" <<PROFILE
(version 1)
(allow default)
(deny network*)
(deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local"))
(deny file-write*)
(allow file-write* (subpath "$ROOT/build") (literal "/dev/null"))
PROFILE
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="$INTERNAL/tmp" \
        CLANG_MODULE_CACHE_PATH="$INTERNAL/cache/modules" COPLAND_BUILD_INNER=1 \
        COPLAND_DEVELOPER_DIR="${DEVELOPER_DIR:-}" \
        /usr/bin/sandbox-exec -f "$INTERNAL/build.sb" /bin/sh "$0" "$TARGET"
    if [ "$TARGET" = serve ]; then
        release_lock; trap - EXIT INT TERM HUP
        exec "$INTERNAL/host-tools/server" "$ROOT/build/web" 8080
    fi
    exit 0
fi
if [ "$TARGET" = clean ]; then
    # Keep the lock's directory alive until all generated contents are gone.
    for CLEAN_PARENT in "$ROOT/build" "$INTERNAL"; do
        for CLEAN_PATH in "$CLEAN_PARENT/"* "$CLEAN_PARENT/".[!.]* "$CLEAN_PARENT/"..?*; do
            [ "$CLEAN_PATH" != "$INTERNAL" ] && [ "$CLEAN_PATH" != "$LOCK" ] || continue
            remove_tree "$CLEAN_PATH"
        done
    done
    exit 0
fi
if [ "$TARGET" = rebuild-toolchain ]; then rm -rf "$INTERNAL/toolchain"; TARGET=web; fi
DEVELOPER=${COPLAND_DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
if [ -x "$DEVELOPER/usr/bin/clang" ]; then
    CC="$DEVELOPER/usr/bin/clang"; LD="$DEVELOPER/usr/bin/ld"; SDK="$DEVELOPER/SDKs/MacOSX.sdk"
else
    CC="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    LD="$DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld"
    SDK="$DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi
[ -x "$CC" ] && [ -x "$LD" ] && [ -d "$SDK" ] || { echo 'Install/select the Apple Command Line Tools first.' >&2; exit 1; }
SDKROOT=$SDK
export CC SDK LD SDKROOT
mkdir -p "$INTERNAL/state" "$INTERNAL/host-tools" "$INTERNAL/tests"
DESCRIPTOR="$INTERNAL/tmp/compiler-state"
{ "$CC" --version; printf '%s\n' "$CC" "$SDK"; /usr/bin/stat -f '%z %m' "$CC"; cat "$SDK/SDKSettings.json"; } > "$DESCRIPTOR"
snapshot() {
    SNAP="$INTERNAL/tmp/$1-inputs"
    rm -rf "$SNAP"; mkdir -p "$SNAP"
    cp "$DESCRIPTOR" "$SNAP/compiler"
    cp build-support/scripts/build.sh "$SNAP/recipe"
    shift
    for INPUT in "$@"; do
        mkdir -p "$SNAP/$(dirname "$INPUT")"
        cp -R "$INPUT" "$SNAP/$INPUT"
    done
}
unchanged() { [ -d "$INTERNAL/state/$1" ] && /usr/bin/diff -qr "$SNAP" "$INTERNAL/state/$1" >/dev/null; }
remember() { rm -rf "$INTERNAL/state/$1"; mv "$SNAP" "$INTERNAL/state/$1"; }
host_tool() {
    NAME=$1; shift
    snapshot "host-$NAME" "build-support/tools/$NAME.m"
    if [ ! -x "$INTERNAL/host-tools/$NAME" ] || ! unchanged "host-$NAME"; then
        "$CC" -O2 -fobjc-arc -isysroot "$SDK" --ld-path="$LD" "build-support/tools/$NAME.m" "$@" -o "$INTERNAL/tmp/$NAME"
        mv "$INTERNAL/tmp/$NAME" "$INTERNAL/host-tools/$NAME"
        remember "host-$NAME"
    fi
}
build_cli() {
    snapshot cli core macos
    if [ -x build/copland_video_tool ] && unchanged cli; then echo 'CLI is current.'; return; fi
    mkdir -p "$INTERNAL/cli/staging"
    echo 'Building universal macOS CLI…'
    "$CC" -O3 -std=c11 -Wall -Wextra -fobjc-arc -isysroot "$SDK" \
        -mmacosx-version-min=11.0 -arch arm64 -arch x86_64 --ld-path="$LD" \
        core/reveal.c core/image.c core/timeline.c macos/main.m \
        -framework Foundation -framework CoreGraphics -framework ImageIO \
        -framework CoreVideo -framework CoreMedia -framework AVFoundation \
        -lm -o "$INTERNAL/cli/staging/copland_video_tool"
    "$INTERNAL/cli/staging/copland_video_tool" --help >/dev/null
    mv "$INTERNAL/cli/staging/copland_video_tool" build/copland_video_tool
    remember cli
}
build_linker() {
    ARCHIVE=; COUNT=0
    for FILE in vendor/toolchain/xcc/* vendor/toolchain/xcc/.[!.]*; do
        [ -f "$FILE" ] || continue
        [ "$(basename "$FILE")" != .DS_Store ] || continue
        ARCHIVE=$FILE; COUNT=$((COUNT + 1))
    done
    [ "$COUNT" = 1 ] || { echo 'vendor/toolchain/xcc must contain exactly one original source archive.' >&2; exit 1; }
    snapshot linker build-support/patches/xcc-host-only.patch
    cp "$ARCHIVE" "$SNAP/archive"
    LINKER="$INTERNAL/toolchain/xcc/source/wcc"
    if [ -x "$LINKER" ] && unchanged linker; then return; fi
    echo 'Building the small WASM linker from its original source archive…'
    rm -rf "$INTERNAL/toolchain/xcc"
    mkdir -p "$INTERNAL/toolchain/xcc/unpack"
    /usr/bin/tar -xf "$ARCHIVE" -C "$INTERNAL/toolchain/xcc/unpack"
    set -- "$INTERNAL/toolchain/xcc/unpack/"*
    [ "$#" = 1 ] && [ -d "$1" ] || { echo 'Expected one upstream source root in archive.' >&2; exit 1; }
    mv "$1" "$INTERNAL/toolchain/xcc/source"
    (cd "$INTERNAL/toolchain/xcc/source" && /usr/bin/patch -p1 < "$ROOT/build-support/patches/xcc-host-only.patch" && \
        /usr/bin/make CC="\"$CC\"" OPTIMIZE=-O2 LDFLAGS="--ld-path=\"$LD\"" wcc) > "$INTERNAL/logs/xcc.log" 2>&1 || { cat "$INTERNAL/logs/xcc.log" >&2; exit 1; }
    remember linker
}
build_web() {
    build_linker
    host_tool package-check -framework Foundation
    snapshot web core web build-support/patches/xcc-host-only.patch build-support/tools/icons.m build-support/tools/js-runner.m build-support/tools/package-check.m tests/wasm-smoke.js
    cp "$INTERNAL/state/linker/archive" "$SNAP/linker-archive"
    if [ -f build/web/index.html ] && unchanged web && "$INTERNAL/host-tools/package-check" build/web; then echo 'Web app is current.'; return; fi
    WEB_SNAP=$SNAP
    echo 'Building WASM and the offline website…'
    mkdir -p "$INTERNAL/wasm/objects"
    "$CC" --target=wasm32-unknown-unknown -ffreestanding -fno-builtin -O3 -std=c11 -Wall -Wextra \
        -Iweb/native/include -c web/native/wasm-adapter.c -o "$INTERNAL/wasm/objects/engine.o"
    EXPORTS='abi_version heap_start configure_memory output_address set_keyframe prepare render box_coordinate'
    set --
    for NAME in $EXPORTS; do set -- "$@" -e "$NAME"; done
    "$LINKER" -nostdlib --entry-point= --stack-size=65536 "$@" -Wl,--allow-undefined \
        -o "$INTERNAL/wasm/engine.wasm" "$INTERNAL/wasm/objects/engine.o"
    host_tool js-runner -framework Foundation -framework JavaScriptCore
    "$INTERNAL/host-tools/js-runner" "$INTERNAL/wasm/engine.wasm" tests/wasm-smoke.js
    RELEASE=$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')
    STAGE="$INTERNAL/web/staging"
    rm -rf "$STAGE"; mkdir -p "$STAGE/releases/$RELEASE"
    if [ ! -d build/web ] && [ -d "$INTERNAL/web/previous" ]; then mv "$INTERNAL/web/previous" build/web; fi
    if [ -d build/web/releases ]; then cp -R build/web/releases/. "$STAGE/releases/"; fi
    cp web/*.js web/*.css "$STAGE/releases/$RELEASE/"
    rm "$STAGE/releases/$RELEASE/service-worker.js"
    cp "$INTERNAL/wasm/engine.wasm" "$STAGE/releases/$RELEASE/engine.wasm"
    cp web/manifest.webmanifest "$STAGE/manifest.webmanifest"
    host_tool icons -framework Foundation -framework CoreGraphics -framework ImageIO
    "$INTERNAL/host-tools/icons" "$STAGE" "$ROOT/web/assets/icon.svg"
    cp "$INTERNAL/toolchain/xcc/source/LICENSE" "$STAGE/XCC-LICENSE.txt"
    printf '%s\n' "$RELEASE" > "$STAGE/release.txt"
    /usr/bin/sed "s/__RELEASE__/$RELEASE/g" web/index.html > "$STAGE/index.html"
    /usr/bin/sed "s/__RELEASE__/$RELEASE/g" web/service-worker.js > "$STAGE/service-worker.js"
    INVENTORY="$STAGE/offline-resources.json"
    printf '[\n' > "$INVENTORY"
    FIRST=1
    for FILE in "$STAGE/index.html" "$STAGE/manifest.webmanifest" "$STAGE/"icon*.png "$STAGE/favicon.ico" "$STAGE/XCC-LICENSE.txt" "$STAGE/releases/$RELEASE/"*; do
        REL=${FILE#"$STAGE/"}; SIZE=$(/usr/bin/stat -f '%z' "$FILE")
        [ "$FIRST" = 1 ] || printf ',\n' >> "$INVENTORY"
        FIRST=0; printf ' {"path":"%s","size":%s}' "$REL" "$SIZE" >> "$INVENTORY"
    done
    printf '\n]\n' >> "$INVENTORY"
    "$INTERNAL/host-tools/package-check" "$STAGE"
    PREVIOUS="$INTERNAL/web/previous"
    rm -rf "$PREVIOUS"
    if [ -d build/web ]; then mv build/web "$PREVIOUS"; fi
    if ! mv "$STAGE" build/web; then [ ! -d "$PREVIOUS" ] || mv "$PREVIOUS" build/web; exit 1; fi
    rm -rf "$PREVIOUS"
    SNAP=$WEB_SNAP; remember web
}
case "$TARGET" in
    cli) build_cli;;
    web) build_web;;
    all|check) build_cli; build_web;;
    serve) build_web; host_tool server -framework Foundation;;
esac
if [ "$TARGET" = check ]; then /bin/sh build-support/scripts/check.sh; fi
