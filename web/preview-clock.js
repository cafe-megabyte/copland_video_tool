// Audio drives the reveal. Once it ends, a monotonic clock drives the silent tail.
export function createPreviewClock(audio, start, audioDuration, now = () => performance.now()) {
  let tail = !audio || start >= audioDuration, origin = now(), tailStart = start;
  return () => {
    if (!tail && (audio.ended || audio.currentTime >= audioDuration)) {
      tail = true; origin = now(); tailStart = audioDuration;
    }
    return tail ? tailStart + (now() - origin) / 1000 : audio.currentTime;
  };
}
