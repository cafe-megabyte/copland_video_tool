#include "../core/image.h"
#include "../core/timeline.h"
#include "sound-start-fixture.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#define REQUIRE(v) do { if (!(v)) { fprintf(stderr, "Sound start check failed at %d (case %d)\n", __LINE__, case_id); exit(1); } } while (0)

static int case_id;
static uint8_t rgba[128 * 128 * 4], rgb[128 * 128 * 3], base[128 * 128 * 3];
static uint8_t frame[128 * 128 * 3], scratch[128 * 128 * 3], out[128 * 128 * 4];

static const uint8_t *render(const CoplandTimeline *t, int index, CoplandBox box) {
    double size;
    int state = copland_frame_state(t, index, &size);
    REQUIRE(state >= 0);
    if (!state) return base;
    if (state == 2) return rgb;
    if (size <= 16) copland_render_smooth_frame(rgb, base, frame, scratch, 128, 128, box, size);
    else copland_render_frame(rgb, base, frame, 128, 128, box, (int)lrint(size));
    return frame;
}

/* Brute-force actual frames: independent of the optimized centre-sample search. */
static int visible(const uint8_t *pixels, CoplandBox box) {
    for (int y = box.y0; y < box.y1; ++y)
        for (int x = box.x0; x < box.x1; ++x)
            for (int c = 0; c < 3; ++c) {
                int i = (y * 128 + x) * 3 + c;
                if (abs(pixels[i] - base[i]) >= 8) return 1;
            }
    return 0;
}

static uint32_t hash(const uint8_t *data, size_t length) {
    uint32_t value = 2166136261u;
    for (size_t i = 0; i < length; ++i) value = (value ^ data[i]) * 16777619u;
    return value;
}

static void check(FILE *json, int kind, double fps, double blank, double hold,
                  int start, int easing, int mode, int color) {
    sound_start_fixture(rgba, kind);
    CoplandBox box = {8, 9, 120, 126};
    uint8_t bg[3] = {(color >> 16) & 255, (color >> 8) & 255, color & 255};
    REQUIRE(copland_prepare_image(rgba, rgb, 128, 128, 0, mode, &box, 20, color >= 0, bg));
    copland_make_base(rgb, base, 128, 128, box, bg);
    int initial = start ? start : (box.x1 - box.x0 > box.y1 - box.y0 ? box.x1 - box.x0 : box.y1 - box.y0);
    CoplandTimeline t;
    REQUIRE(copland_timeline_init_sound(&t, fps, blank, hold, initial, (CoplandEasing)easing));
    CoplandTimeline original = t;
    int cue = t.blank_frames + t.reveal_frames - 1, first = -1;
    for (int i = t.blank_frames; i < cue; ++i) {
        if (visible(render(&t, i, box), box)) { first = i; break; }
    }
    double expected = first < 0 ? 0 : (first - t.blank_frames) / fps;
    copland_timeline_align_sound_start(&t, rgb, base, frame, scratch, 128, 128, box);
    if (first >= 0 || !visible(rgb, box)) REQUIRE(t.source_start == expected);
    else {
        /* A sparse visible grid can fall between all original video frames.
           Compare the fallback against actual integer renders, independently
           of the optimized detector and its inverse-curve search. */
        REQUIRE(t.source_start > 0 && t.source_start < t.duration);
        int tile = initial < 128 ? initial : 128;
        for (; tile >= 2; --tile) {
            copland_render_frame(rgb, base, frame, 128, 128, box, tile);
            if (visible(frame, box)) break;
        }
        double size;
        REQUIRE(copland_frame_state(&t, t.blank_frames, &size) == 1);
        if (tile >= 2) REQUIRE(fabs(size - tile) < 1e-10);
        else REQUIRE(size > 1 && size < 2);
        REQUIRE(visible(render(&t, t.blank_frames, box), box));
        expected = t.source_start;
    }
    REQUIRE(t.fps == fps && t.start_size == initial && t.easing == (CoplandEasing)easing && !t.keyframe_count);
    REQUIRE(t.blank_frames == original.blank_frames && t.reveal_frames == original.reveal_frames);
    REQUIRE(t.hold_frames == original.hold_frames && t.total_frames == original.total_frames);
    REQUIRE(t.duration == original.duration && t.total_duration == original.total_duration && t.reveal_end == original.reveal_end);
    REQUIRE(fabs(t.reveal_end - COPLAND_SOUND_REVEAL_END) <= .5 / fps + 1e-9);
    if (first >= 0) REQUIRE(visible(render(&t, t.blank_frames, box), box));
    if (t.blank_frames) REQUIRE(!visible(render(&t, t.blank_frames - 1, box), box));
    if (kind == 2 || kind == 3 || (kind == 0 && color == 0)) REQUIRE(expected == 0);
    if (kind == 1 || kind == 5) REQUIRE(expected == 0);
    if (kind == 0 && fps == 60 && easing == 0 && mode == 0 && start == 128 && blank == COPLAND_SOUND_REVEAL_START) {
        REQUIRE(first == 144 && expected == 91.0 / 60);
    }
    /* Repeating preparation must not compound the offset. */
    copland_timeline_align_sound_start(&t, rgb, base, frame, scratch, 128, 128, box);
    REQUIRE(t.source_start == expected);
    int indices[] = {0, t.blank_frames, t.blank_frames + 1, (t.blank_frames + cue) / 2,
                     cue - 1, cue, t.total_frames - 1};
    if (case_id) fputs(",\n", json);
    fprintf(json, "{\"kind\":%d,\"fps\":%.17g,\"blank\":%.17g,\"hold\":%.17g,\"start\":%d,\"easing\":%d,\"mode\":%d,\"color\":%d,\"count\":%d,\"duration\":%.17g,\"cue\":%.17g,\"frames\":[",
        kind, fps, blank, hold, start, easing, mode, color, t.total_frames, t.total_duration, t.reveal_end);
    for (size_t n = 0; n < sizeof(indices) / sizeof(indices[0]); ++n) {
        int index = indices[n];
        double size, time = fmin((index - t.blank_frames) / fps, t.duration);
        int state = copland_frame_state(&t, index, &size);
        if (state == 1) {
            if (index == cue) time = t.duration;
            else time = expected + (t.duration - expected) * (time / t.duration);
            double wanted = copland_continuous_size_at_time(time, original.duration, initial, original.easing, 0, 0);
            REQUIRE(fabs(size - wanted) < 1e-10);
        }
        if (index >= cue) REQUIRE(size == 1);
        const uint8_t *pixels = render(&t, index, box);
        copland_pack_rgba(pixels, out, 128, 128, bg);
        fprintf(json, "%s{\"index\":%d,\"hash\":%u}", n ? "," : "", index, hash(out, sizeof(out)));
    }
    fputs("]}", json);
    ++case_id;
}

int main(void) {
    FILE *json = fopen("build/internal/tests/sound-start-frames.json", "w"); REQUIRE(json);
    fputs("{\"images\":[", json);
    for (int kind = 0; kind < SOUND_START_KINDS; ++kind) {
        sound_start_fixture(rgba, kind);
        if (kind) fputc(',', json);
        fputc('"', json);
        for (size_t i = 0; i < sizeof(rgba); ++i) fprintf(json, "%02x", rgba[i]);
        fputc('"', json);
    }
    fputs("],\"cases\":[\n", json);
    const double rates[] = {1, 24, 29.97, 30, 60, 120};
    for (int r = 0; r < 6; ++r)
        for (int easing = 0; easing < 4; ++easing) {
            check(json, 0, rates[r], COPLAND_SOUND_REVEAL_START, 0, 128, easing, 0, -1);
            check(json, 0, rates[r], 0, 6.125, 256, easing, 0, 0xdcc864);
            check(json, 0, rates[r], 1.234, 0, 32, easing, 2, 0xffffff);
            check(json, 0, rates[r], 0, 0, 0, easing, 1, 0x173363);
            check(json, 4, rates[r], COPLAND_SOUND_REVEAL_START, 0, 9, easing, 0, -1);
        }
    for (int kind = 1; kind < SOUND_START_KINDS; ++kind)
        check(json, kind, 60, 0, 0, 128, 0, 0, -1);
    check(json, 0, 60, 0, 0, 128, 0, 0, 0);
    /* Only the cue frame originally differs: find an intermediate grid without
       changing the two-frame output or moving the final-image cue. */
    check(json, 0, 1, nearbyint(COPLAND_SOUND_REVEAL_END) - 1, 0, 128, 0, 0, -1);
    for (int r = 0; r < 6; ++r)
        check(json, 6, rates[r], (nearbyint(COPLAND_SOUND_REVEAL_END * rates[r]) - .6) / rates[r], 0, 2, r % 4, 0, -1);
    fputs("\n]}\n", json); REQUIRE(!fclose(json));
    printf("Sound start: %d configurations matched independently rendered frames; FPS, easing, region, background and sound timings preserved.\n", case_id);
    return 0;
}
