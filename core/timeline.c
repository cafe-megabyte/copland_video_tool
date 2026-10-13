#include "timeline.h"
#include <math.h>
#include <stddef.h>

int copland_timeline_init(CoplandTimeline *t, double duration, double fps,
                         double blank, double hold, int start_size, CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int count) {
    if (!t || !isfinite(duration) || duration <= 0 || !isfinite(fps) || fps <= 0 ||
        !isfinite(blank) || blank < 0 || !isfinite(hold) || hold < 0 || start_size < 1 ||
        easing < COPLAND_LINEAR || easing > COPLAND_FAST_THEN_SLOW || count < 0) return 0;
    if (count) {
        if (!keyframes || count < 2 || keyframes[0].time != 0 || keyframes[count - 1].size != 1) return 0;
        for (int i = 0; i < count; ++i) {
            if (!isfinite(keyframes[i].time) || !isfinite(keyframes[i].size) ||
                keyframes[i].time < 0 || keyframes[i].size < 1 || keyframes[i].size > 2147483647.0 ||
                (i && (keyframes[i].time <= keyframes[i - 1].time || keyframes[i].size > keyframes[i - 1].size))) return 0;
        }
        duration = keyframes[count - 1].time;
    }
    double b = nearbyint(blank * fps), r = fmax(2, ceil(duration * fps) + 1), h = nearbyint(hold * fps);
    if (!isfinite(b + r + h) || b + r + h > 10000000) return 0;
    *t = (CoplandTimeline){duration, fps, start_size, easing, keyframes, count,
        (int)b, (int)r, (int)h, (int)(b + r + h), (b + r + h) / fps, (b + r - 1) / fps, 0};
    return 1;
}

int copland_timeline_init_sound(CoplandTimeline *t, double fps, double blank, double hold, int start_size, CoplandEasing easing) {
    if (!t || !isfinite(fps) || fps < 1 || !isfinite(blank) || blank < 0 ||
        !isfinite(hold) || hold < 0 || start_size < 1 ||
        easing < COPLAND_LINEAR || easing > COPLAND_FAST_THEN_SLOW) return 0;
    if (!isfinite(COPLAND_SOUND_REVEAL_END) || blank >= COPLAND_SOUND_REVEAL_END ||
        COPLAND_SOUND_REVEAL_END >= COPLAND_SOUND_DURATION) return 0;
    double cue_frame = nearbyint(COPLAND_SOUND_REVEAL_END * fps);
    double duration = fmax(COPLAND_SOUND_DURATION, cue_frame / fps + hold);
    double total = ceil(duration * fps);
    if (!isfinite(total) || total > 10000000) return 0;
    int blank_frames = (int)nearbyint(blank * fps);
    int cue = (int)cue_frame;
    int reveal = cue - blank_frames + 1;
    if (reveal < 2 || cue >= total) return 0;
    *t = (CoplandTimeline){(cue - blank_frames) / fps, fps, start_size, easing, 0, 0,
        blank_frames, reveal, (int)total - cue - 1, (int)total, duration, cue / fps, 0};
    return 1;
}

static int sound_pixel_visible(const uint8_t *pixel, const uint8_t *base) {
    for (int c = 0; c < 3; ++c) {
        int delta = (int)pixel[c] - base[c];
        if (delta >= COPLAND_SOUND_VISIBLE_CONTRAST || delta <= -COPLAND_SOUND_VISIBLE_CONTRAST) return 1;
    }
    return 0;
}

static int sound_frame_visible(const uint8_t *pixels, const uint8_t *base, int width, CoplandBox box) {
    for (int y = box.y0; y < box.y1; ++y)
        for (int x = box.x0; x < box.x1; ++x) {
            size_t offset = ((size_t)y * width + x) * 3;
            if (sound_pixel_visible(pixels + offset, base + offset)) return 1;
        }
    return 0;
}

/* For integer grids every tile has its centre pixel's colour, and the base is
   uniform inside the box. Inspect those samples without filling whole frames. */
static int sound_grid_visible(const uint8_t *source, const uint8_t *base,
                              int width, CoplandBox box, int tile) {
    for (int y = box.y0; y < box.y1;) {
        int bottom = tile >= box.y1 - y ? box.y1 : y + tile;
        int cy = y + (bottom - y - 1) / 2;
        for (int x = box.x0; x < box.x1;) {
            int right = tile >= box.x1 - x ? box.x1 : x + tile;
            int cx = x + (right - x - 1) / 2;
            size_t offset = ((size_t)cy * width + cx) * 3;
            if (sound_pixel_visible(source + offset, base + offset)) return 1;
            x = right;
        }
        y = bottom;
    }
    return 0;
}

void copland_timeline_align_sound_start(CoplandTimeline *t,
                                       const uint8_t *source, const uint8_t *base,
                                       uint8_t *frame, uint8_t *scratch,
                                       int width, int height, CoplandBox box) {
    t->source_start = 0;
    int maximum_tile = box.x1 - box.x0 > box.y1 - box.y0 ? box.x1 - box.x0 : box.y1 - box.y0;
    for (int i = 0; i < t->reveal_frames - 1;) {
        double time = i / t->fps;
        double size = copland_continuous_size_at_time(time, t->duration, t->start_size, t->easing, 0, 0);
        int tile = (int)lrint(size);
        if (tile > maximum_tile) tile = maximum_tile;
        int visible;
        if (size <= 16) {
            copland_render_smooth_frame(source, base, frame, scratch, width, height, box, size);
            visible = sound_frame_visible(frame, base, width, box);
        } else visible = sound_grid_visible(source, base, width, box, tile);
        if (visible) { t->source_start = time; return; }
        /* Completely invisible images need no search, even at very high FPS. */
        if (!i && !sound_frame_visible(source, base, width, box)) return;
        int next = i + 1;
        if (size > 16) {
            /* Size is monotonic, visibility is not. Skip duplicate grids only;
               never binary-search for a visible image or trim later gaps. */
            int end = t->reveal_frames - 1;
            while (next < end) {
                int middle = next + (end - next) / 2;
                double candidate = copland_continuous_size_at_time(middle / t->fps,
                    t->duration, t->start_size, t->easing, 0, 0);
                if (candidate > 16 && lrint(candidate) >= tile) next = middle + 1;
                else end = middle;
            }
        }
        i = next;
    }
    /* At low FPS (or a very late lead-in) all visible intermediate grids may
       fall between sampled frames. Find one on the same continuous curve;
       the output frame grid and the full-image cue still stay unchanged. */
    int tile = t->start_size < maximum_tile ? t->start_size : maximum_tile;
    for (; tile >= 2; --tile)
        if (sound_grid_visible(source, base, width, box, tile)) break;
    double target = tile;
    if (tile < 2) {
        /* Grid 2 is invisible, grid 1 is visible. Within this one crossfade,
           all below-threshold colours form a single interval, so visibility
           can be bisected safely. Dyadic steps plus a half-step margin avoid
           rounding-threshold differences between native and WASM math. */
        int low = 1, high = 256;
        while (low < high) {
            int middle = low + (high - low) / 2;
            copland_render_smooth_frame(source, base, frame, scratch, width, height, box, 2 - middle / 256.0);
            if (sound_frame_visible(frame, base, width, box)) high = middle;
            else low = middle + 1;
        }
        target = 2 - (low + .5) / 256.0;
    }
    double low = 0, high = t->duration;
    for (int i = 0; i < 60; ++i) {
        double middle = (low + high) * .5;
        if (copland_continuous_size_at_time(middle, t->duration, t->start_size, t->easing, 0, 0) > target) low = middle;
        else high = middle;
    }
    t->source_start = high;
}

int copland_frame_state(const CoplandTimeline *t, int index, double *size) {
    if (!t || !size || index < 0 || index >= t->total_frames) return -1;
    if (index < t->blank_frames) { *size = t->start_size; return 0; }
    int animation = index - t->blank_frames;
    if (animation >= t->reveal_frames) { *size = 1; return 2; }
    double time = animation == t->reveal_frames - 1 ? t->duration : fmin(animation / t->fps, t->duration);
    if (t->source_start > 0 && time < t->duration)
        time = t->source_start + (t->duration - t->source_start) * (time / t->duration);
    *size = copland_continuous_size_at_time(time, t->duration, t->start_size, t->easing, t->keyframes, t->keyframe_count);
    return 1;
}
