#!/bin/sh
# Exercise the real clean recipe in an isolated project, including a writer
# holding an open directory just as Finder does.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
FIXTURE=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/copland clean.XXXXXX")
WRITER=
cleanup() {
    if [ -n "$WRITER" ]; then
        kill "$WRITER" 2>/dev/null || :
        wait "$WRITER" 2>/dev/null || :
    fi
    /usr/bin/chflags -R nouchg "$FIXTURE"
    /bin/rm -rf "$FIXTURE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
mkdir -p "$FIXTURE/build-support/scripts"
cp "$ROOT/Makefile" "$FIXTURE/Makefile"
cp "$ROOT/build-support/scripts/build.sh" "$FIXTURE/build-support/scripts/build.sh"
run_clean() { COPLAND_BUILD_INNER=0 /usr/bin/make -s -C "$FIXTURE" clean; }
fail() { printf 'Clean check failed: %s\n' "$1" >&2; exit 1; }

# A live lock must reject clean without deleting either the lock or products.
mkdir -p "$FIXTURE/build/internal/build.lock" "$FIXTURE/build/web"
printf '%s\n' "$$" > "$FIXTURE/build/internal/build.lock/pid"
printf 'product\n' > "$FIXTURE/build/web/keep"
if run_clean > "$FIXTURE/locked.log" 2>&1; then fail 'active lock ignored'; fi
[ -f "$FIXTURE/build/web/keep" ] || fail 'locked product removed'
[ "$(cat "$FIXTURE/build/internal/build.lock/pid")" = "$$" ] || fail 'live lock changed'
case "$(cat "$FIXTURE/locked.log")" in
    *'Another build is running.'*) ;;
    *) fail 'missing lock diagnostic';;
esac
/bin/unlink "$FIXTURE/build/internal/build.lock/pid"
/bin/rmdir "$FIXTURE/build/internal/build.lock"

# Hidden directories, symlinks and hard links must be handled safely.
mkdir -p "$FIXTURE/build/web/deep/.hidden" "$FIXTURE/build/internal/cache" "$FIXTURE/source"
printf 'source\n' > "$FIXTURE/source/keep"
/bin/chmod +a 'group:staff allow readsecurity' "$FIXTURE/source"
SOURCE_ACL=$(/bin/ls -lde "$FIXTURE/source" | /usr/bin/sed -n '2,$p')
ln -s "$FIXTURE/source" "$FIXTURE/build/web/external-dir"
ln -s "$FIXTURE/source/keep" "$FIXTURE/build/web/external-file"
ln "$FIXTURE/source/keep" "$FIXTURE/build/web/hard-link"
FILE_MODE=$(/usr/bin/stat -f '%p' "$FIXTURE/source/keep")
printf 'hidden\n' > "$FIXTURE/build/web/deep/.hidden/data"
printf 'cache\n' > "$FIXTURE/build/internal/cache/data"
(
    cd "$FIXTURE/build/web/deep"
    printf 'metadata\n' > .DS_Store
    : > "$FIXTURE/writer-ready"
    while :; do
        { printf 'metadata\n' > .DS_Store; } 2>/dev/null || :
    done
) &
WRITER=$!
while [ ! -f "$FIXTURE/writer-ready" ]; do /bin/sleep 0.01; done
run_clean
kill "$WRITER"
wait "$WRITER" 2>/dev/null || :
WRITER=
[ ! -e "$FIXTURE/build" ] || fail 'generated tree survived concurrent metadata writes'
[ "$(cat "$FIXTURE/source/keep")" = source ] || fail 'external source changed'
[ "$(/usr/bin/stat -f '%p' "$FIXTURE/source/keep")" = "$FILE_MODE" ] || fail 'hard-linked file mode changed'
[ "$(/bin/ls -lde "$FIXTURE/source" | /usr/bin/sed -n '2,$p')" = "$SOURCE_ACL" ] || fail 'symlink target ACL changed'
printf 'still writable\n' >> "$FIXTURE/source/keep"
: > "$FIXTURE/source/new"

# A failure midway through sealing must also restore directories already sealed.
mkdir -p "$FIXTURE/build/partial/blocked"
/usr/bin/chflags uchg "$FIXTURE/build/partial/blocked"
if run_clean > "$FIXTURE/seal-failed.log" 2>&1; then fail 'seal error ignored'; fi
[ ! -e "$FIXTURE/build/internal/build.lock" ] || fail 'lock not released after seal failure'
: > "$FIXTURE/build/partial/new"
/usr/bin/chflags nouchg "$FIXTURE/build/partial/blocked"
run_clean
[ ! -e "$FIXTURE/build" ] || fail 'clean failed after fixing seal error'

# A real deletion error must fail and restore the temporary ACL, preserving
# pre-existing permissions and leaving the next build able to write again.
mkdir -p "$FIXTURE/build/broken"
/bin/chmod +a 'group:staff allow readsecurity' "$FIXTURE/build/broken"
/bin/chmod +a 'group:everyone deny add_subdirectory' "$FIXTURE/build/broken"
ORIGINAL_ACL=$(/bin/ls -lde "$FIXTURE/build/broken" | /usr/bin/sed -n '2,$p')
printf 'immutable\n' > "$FIXTURE/build/broken/keep"
/usr/bin/chflags uchg "$FIXTURE/build/broken/keep"
if run_clean > "$FIXTURE/failed.log" 2>&1; then fail 'deletion error ignored'; fi
[ -f "$FIXTURE/build/broken/keep" ] || fail 'immutable fixture missing'
[ ! -e "$FIXTURE/build/internal/build.lock" ] || fail 'lock not released after failure'
[ "$(/bin/ls -lde "$FIXTURE/build/broken" | /usr/bin/sed -n '2,$p')" = "$ORIGINAL_ACL" ] || fail 'permissions not restored'
: > "$FIXTURE/build/broken/new"
/usr/bin/chflags nouchg "$FIXTURE/build/broken/keep"
run_clean
[ ! -e "$FIXTURE/build" ] || fail 'clean failed after fixing deletion error'

# Cleaning an already clean project needs no compiler or pre-existing tools.
run_clean
[ ! -e "$FIXTURE/build" ] || fail 'empty clean left generated directories'
printf 'Clean checks passed (concurrent metadata, locks, links, error recovery).\n'
