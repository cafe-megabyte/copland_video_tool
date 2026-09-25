#ifndef COPLAND_REVEAL_H
#define COPLAND_REVEAL_H

#include <stdint.h>

typedef struct {
    int x0, y0, x1, y1;
} CoplandBox;

typedef struct {
    double time;
    double size;
} CoplandKeyframe;

typedef enum {
    COPLAND_LINEAR,
    COPLAND_GEOMETRIC,
    COPLAND_SLOW_THEN_FAST,
    COPLAND_FAST_THEN_SLOW
} CoplandEasing;

/* All RGB buffers are tightly packed, top-to-bottom, three bytes per pixel. */
void copland_make_base(const uint8_t *source, uint8_t *base,
                       int width, int height, CoplandBox box,
                       const uint8_t background[3]);

void copland_render_frame(const uint8_t *source, const uint8_t *base,
                          uint8_t *frame, int width, int height,
                          CoplandBox box, int tile_size);

/* Crossfade adjacent integer grids for a continuous finish at small tile sizes. */
void copland_render_smooth_frame(const uint8_t *source, const uint8_t *base,
                                 uint8_t *frame, uint8_t *scratch,
                                 int width, int height, CoplandBox box,
                                 double tile_size);

double copland_continuous_size_at_time(double time, double duration, int start_size,
                                      CoplandEasing easing,
                                      const CoplandKeyframe *keyframes,
                                      int keyframe_count);

int copland_size_at_time(double time, double duration, int start_size,
                         CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int keyframe_count);

#endif
