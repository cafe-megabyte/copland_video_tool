#ifndef COPLAND_TIMELINE_H
#define COPLAND_TIMELINE_H
#include "reveal.h"
typedef struct {
    double duration, fps;
    int start_size;
    CoplandEasing easing;
    const CoplandKeyframe *keyframes;
    int keyframe_count, blank_frames, reveal_frames, hold_frames, total_frames;
} CoplandTimeline;
int copland_timeline_init(CoplandTimeline *timeline, double duration, double fps,
                         double blank, double hold, int start_size, CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int count);
/* Returns base (0), animated (1), final (2), or invalid (-1). */
int copland_frame_state(const CoplandTimeline *timeline, int index, double *size);
#endif
