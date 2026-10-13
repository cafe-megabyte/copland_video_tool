#!/bin/sh
# Exercise mode selection through real exports, including output tracks and notices.
set -eu
TESTS="$PWD/build/internal/tests"
CLI="$PWD/build/copland_video_tool"
fail() { printf 'Sound default check failed: %s\n' "$1" >&2; exit 1; }
silent() { "$TESTS/media-check" silent "$1" "$2" 66 50 > /dev/null; }
no_notice() {
    case "$(cat "$1")" in *'sound disabled automatically'*) fail 'unexpected automatic-mode notice';; esac
}

"$CLI" "$TESTS/fixture.png" "$TESTS/default-sound.mp4" > "$TESTS/default-sound.log" 2>&1
"$TESTS/audio-check" assets/copland-theme.m4a "$TESTS/default-sound.mp4" 60 reveal > "$TESTS/default-sound-audio.log"
no_notice "$TESTS/default-sound.log"

"$CLI" "$TESTS/fixture.png" "$TESTS/default-sound-options.mp4" --fps 29.97 --blank .2 --hold 6.125 \
    --start-size 11 --easing geometric --bbox full --threshold 20 --background 000000 > "$TESTS/default-sound-options.log" 2>&1
"$TESTS/audio-check" assets/copland-theme.m4a "$TESTS/default-sound-options.mp4" 29.97 reveal .2 6.125 > "$TESTS/default-sound-options-audio.log"
no_notice "$TESTS/default-sound-options.log"

"$CLI" "$TESTS/fixture.png" "$TESTS/explicit-silent.mp4" --no-sound --fps 10 > "$TESTS/explicit-silent.log" 2>&1
silent "$TESTS/explicit-silent.mp4" 102
no_notice "$TESTS/explicit-silent.log"

for MODE in duration keyframes both; do
    for ORDER in before after; do
        case "$MODE" in
            duration) set -- --duration=9; FPS=1; COUNT=10;;
            keyframes) set -- --keyframes '0:11,.2:1'; FPS=10; COUNT=3;;
            both) set -- --keyframes='0:11,.2:1' --duration 9; FPS=10; COUNT=3;;
        esac
        OUTPUT="$TESTS/auto-silent-$MODE-$ORDER.mp4"
        LOG="$TESTS/auto-silent-$MODE-$ORDER.log"
        if [ "$ORDER" = before ]; then
            "$CLI" "$@" "$TESTS/fixture.png" "$OUTPUT" --fps "$FPS" --blank 0 --hold 0 > "$LOG" 2>&1
        else
            "$CLI" "$TESTS/fixture.png" "$OUTPUT" --fps "$FPS" --blank 0 --hold 0 "$@" > "$LOG" 2>&1
        fi
        silent "$OUTPUT" "$COUNT"
        case "$(cat "$LOG")" in *'note: sound disabled automatically because '*) ;; *) fail 'missing mode-selection notice';; esac
        NOTICE=$(/usr/bin/sed -n '/^note:/p' "$LOG")
        case "$MODE:$NOTICE" in
            duration:*'because --duration was specified.'|keyframes:*'because --keyframes was specified.'|both:*'because --duration and --keyframes were specified.') ;;
            *) fail 'notice names the wrong triggering options';;
        esac
    done
done

"$CLI" "$TESTS/fixture.png" "$TESTS/explicit-silent-timing.mp4" --duration .4 --fps 10 --blank 0 --hold 0 --no-sound > "$TESTS/explicit-silent-timing.log" 2>&1
silent "$TESTS/explicit-silent-timing.mp4" 5
no_notice "$TESTS/explicit-silent-timing.log"

for INVALID in both-first both-last sound-value silent-value; do
    case "$INVALID" in
        both-first) set -- --sound --no-sound;;
        both-last) set -- --no-sound --sound;;
        sound-value) set -- --sound=false;;
        silent-value) set -- --no-sound=false;;
    esac
    set +e
    "$CLI" "$TESTS/fixture.png" "$@" > "$TESTS/invalid-sound-mode.log" 2>&1
    STATUS=$?
    set -e
    [ "$STATUS" = 2 ] || fail 'invalid sound flags were accepted'
done
printf 'Sound defaults: audio on by default, compatible settings, automatic silent mode with reasons, explicit silent mode and conflicting flags passed.\n'
