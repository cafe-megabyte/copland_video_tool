#ifndef COPLAND_TIMELINE_H
#define COPLAND_TIMELINE_H
#include "reveal.h"
/* Audible source samples, excluding AAC priming/remainder. Cue: final accent onset. */
#define COPLAND_SOUND_RATE 44100
#define COPLAND_SOUND_FRAMES 795756
#define COPLAND_SOUND_CUE 14.30
#define COPLAND_SOUND_BLANK 0.1
#define COPLAND_SOUND_DURATION ((double)COPLAND_SOUND_FRAMES / COPLAND_SOUND_RATE)
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
int copland_timeline_init_sound(CoplandTimeline *timeline, double fps,
                               int start_size, CoplandEasing easing);
/* Returns base (0), animated (1), final (2), or invalid (-1). */
int copland_frame_state(const CoplandTimeline *timeline, int index, double *size);
#endif
