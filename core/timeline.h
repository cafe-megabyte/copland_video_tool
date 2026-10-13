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
    double source_start;
} CoplandTimeline;
int copland_timeline_init(CoplandTimeline *timeline, double duration, double fps,
                         double blank, double hold, int start_size, CoplandEasing easing,
                         const CoplandKeyframe *keyframes, int count);
int copland_timeline_init_sound(CoplandTimeline *timeline, double fps, double blank, double hold,
                               int start_size, CoplandEasing easing);
/* Trim only the initially invisible part of a sound reveal. RGB inputs and the
   box must already be prepared; frame and scratch are width * height * 3 bytes.
   Images below the contrast threshold keep their original timing. */
#define COPLAND_SOUND_VISIBLE_CONTRAST 8
void copland_timeline_align_sound_start(CoplandTimeline *timeline,
                                       const uint8_t *source, const uint8_t *base,
                                       uint8_t *frame, uint8_t *scratch,
                                       int width, int height, CoplandBox box);
/* Returns base (0), animated (1), final (2), or invalid (-1). */
int copland_frame_state(const CoplandTimeline *timeline, int index, double *size);
#endif
