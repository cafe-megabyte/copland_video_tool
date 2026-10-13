#ifndef COPLAND_TIMELINE_H
#define COPLAND_TIMELINE_H
#include "reveal.h"
#include "soundtrack.h"
typedef struct {
    double duration, fps;
    int start_size;
    CoplandEasing easing;
    const CoplandKeyframe *keyframes;
    int keyframe_count, blank_frames, reveal_frames, hold_frames, total_frames;
    double total_duration, reveal_end;
} CoplandTimeline;
int copland_timeline_init(CoplandTimeline *timeline, double duration, double fps,
                         double blank, double hold, int start_size, CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int count);
int copland_timeline_init_sound(CoplandTimeline *timeline, double fps, double blank, double hold,
                               int start_size, CoplandEasing easing);
/* Returns base (0), animated (1), final (2), or invalid (-1). */
int copland_frame_state(const CoplandTimeline *timeline, int index, double *size);
#endif
