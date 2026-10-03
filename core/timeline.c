#include "timeline.h"
#include <math.h>

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
        (int)b, (int)r, (int)h, (int)(b + r + h)};
    return 1;
}

int copland_frame_state(const CoplandTimeline *t, int index, double *size) {
    if (!t || !size || index < 0 || index >= t->total_frames) return -1;
    if (index < t->blank_frames) { *size = t->start_size; return 0; }
    int animation = index - t->blank_frames;
    if (animation >= t->reveal_frames) { *size = 1; return 2; }
    double time = animation == t->reveal_frames - 1 ? t->duration : fmin(animation / t->fps, t->duration);
    *size = copland_continuous_size_at_time(time, t->duration, t->start_size, t->easing, t->keyframes, t->keyframe_count);
    return 1;
}
