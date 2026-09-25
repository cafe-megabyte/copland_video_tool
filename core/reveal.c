#include "reveal.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

void copland_make_base(const uint8_t *source, uint8_t *base,
                       int width, int height, CoplandBox box,
                       const uint8_t background[3]) {
    memcpy(base, source, (size_t)width * (size_t)height * 3);
    for (int y = box.y0; y < box.y1; ++y) {
        for (int x = box.x0; x < box.x1; ++x) {
            size_t offset = ((size_t)y * (size_t)width + (size_t)x) * 3;
            memcpy(base + offset, background, 3);
        }
    }
}

void copland_render_frame(const uint8_t *source, const uint8_t *base,
                          uint8_t *frame, int width, int height,
                          CoplandBox box, int tile_size) {
    size_t bytes = (size_t)width * (size_t)height * 3;
    if (tile_size <= 1) {
        memcpy(frame, source, bytes);
        return;
    }
    memcpy(frame, base, bytes);
    for (int y = box.y0; y < box.y1;) {
        int bottom = tile_size >= box.y1 - y ? box.y1 : y + tile_size;
        int cy = y + (bottom - y - 1) / 2;
        for (int x = box.x0; x < box.x1;) {
            int right = tile_size >= box.x1 - x ? box.x1 : x + tile_size;
            int cx = x + (right - x - 1) / 2;
            size_t sample = ((size_t)cy * (size_t)width + (size_t)cx) * 3;
            for (int row = y; row < bottom; ++row) {
                for (int col = x; col < right; ++col) {
                    size_t target = ((size_t)row * (size_t)width + (size_t)col) * 3;
                    memcpy(frame + target, source + sample, 3);
                }
            }
            x = right;
        }
        y = bottom;
    }
    (void)height;
}

void copland_render_smooth_frame(const uint8_t *source, const uint8_t *base,
                                 uint8_t *frame, uint8_t *scratch,
                                 int width, int height, CoplandBox box,
                                 double tile_size) {
    int lower = (int)floor(tile_size);
    double blend = tile_size - lower;
    copland_render_frame(source, base, frame, width, height, box, lower);
    if (blend <= 0.0) return;
    copland_render_frame(source, base, scratch, width, height, box, lower + 1);
    size_t bytes = (size_t)width * (size_t)height * 3;
    for (size_t i = 0; i < bytes; ++i)
        frame[i] = (uint8_t)lrint((1.0 - blend) * frame[i] + blend * scratch[i]);
}

double copland_continuous_size_at_time(double time, double duration, int start_size,
                                      CoplandEasing easing,
                                      const CoplandKeyframe *keyframes,
                                      int keyframe_count) {
    double size = 1.0;
    if (keyframes && keyframe_count >= 2) {
        if (time >= keyframes[keyframe_count - 1].time) return 1.0;
        for (int i = 0; i + 1 < keyframe_count; ++i) {
            CoplandKeyframe a = keyframes[i], b = keyframes[i + 1];
            if (time <= b.time) {
                double fraction = (time - a.time) / (b.time - a.time);
                size = a.size + fraction * (b.size - a.size);
                break;
            }
        }
    } else {
        double progress = fmin(1.0, time / duration);
        if (easing == COPLAND_GEOMETRIC) {
            /* Equal time intervals reduce the side length by the same ratio. */
            size = pow((double)start_size, 1.0 - progress);
        } else if (easing == COPLAND_LINEAR) {
            /* Match the slopes of a linear lead-in and a geometric finish.
               The last few grid sizes then receive enough frames to resolve. */
            double finish_duration = fmin(1.8, duration * 0.2);
            double finish_start = duration - finish_duration;
            double ratio = finish_start / finish_duration;
            double low = 1.0, high = (double)start_size;
            for (int i = 0; i < 40; ++i) {
                double middle = (low + high) * 0.5;
                if (middle * (1.0 + ratio * log(middle)) < start_size) low = middle;
                else high = middle;
            }
            double join_size = (low + high) * 0.5;
            if (time < finish_start)
                size = start_size + (join_size - start_size) * (time / finish_start);
            else {
                double remaining = fmax(0.0, (duration - time) / finish_duration);
                size = pow(join_size, remaining);
            }
        } else {
            if (easing == COPLAND_SLOW_THEN_FAST) progress *= progress;
            else if (easing == COPLAND_FAST_THEN_SLOW)
                progress = 1.0 - (1.0 - progress) * (1.0 - progress);
            size = (double)start_size + progress * (1.0 - (double)start_size);
        }
    }
    return fmax(1.0, size);
}

int copland_size_at_time(double time, double duration, int start_size,
                         CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int keyframe_count) {
    double size = copland_continuous_size_at_time(time, duration, start_size,
                                                 easing, keyframes, keyframe_count);
    long rounded = lrint(size); /* Python round(): nearest, ties to even. */
    return rounded < 1 ? 1 : (int)rounded;
}
