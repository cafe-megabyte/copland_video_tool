/* Single translation unit lets Clang inline the small freestanding runtime. */
#include "runtime.c"
#include "../../core/reveal.c"
#include "../../core/image.c"
#include "../../core/timeline.c"

extern unsigned char __heap_base;
static uint32_t arena_end;
static int image_width, image_height, configured;
static uint8_t *input, *source, *base, *frame, *scratch, *output;
static uint8_t background[3];
static CoplandBox box;
static CoplandTimeline timeline;
static CoplandKeyframe keyframes[256];

unsigned abi_version(void) { return 1; }
unsigned heap_start(void) { return ((unsigned)(uintptr_t)&__heap_base + 15u) & ~15u; }
unsigned configure_memory(unsigned w, unsigned h) {
    configured = 0;
    arena_end = 0;
    if (!w || !h || w > 4096 || h > 4096 || w * h > 8388608) return 0;
    unsigned pixels = w * h, bytes = pixels * 16 + (w + (w & 1)) * (h + (h & 1)) * 4;
    unsigned start = heap_start();
    if (start + bytes < start || start + bytes > 192u * 1024 * 1024) return 0;
    unsigned pages = (start + bytes + 65535) / 65536;
    unsigned current = __builtin_wasm_memory_size(0);
    if (pages > current && __builtin_wasm_memory_grow(0, pages - current) == (size_t)-1) return 0;
    arena_end = start + bytes;
    image_width = (int)w; image_height = (int)h;
    input = (uint8_t *)(uintptr_t)start; source = input + pixels * 4;
    base = source + pixels * 3; frame = base + pixels * 3;
    scratch = frame + pixels * 3; output = scratch + pixels * 3;
    return (unsigned)(uintptr_t)input;
}
unsigned output_address(void) { return arena_end ? (unsigned)(uintptr_t)output : 0; }
int set_keyframe(unsigned index, double time, double size) {
    if (index >= 256 || !isfinite(time) || !isfinite(size)) return 0;
    keyframes[index] = (CoplandKeyframe){time, size}; return 1;
}
int prepare(double duration, double fps, double blank, double hold, int start,
            int easing, int mode, int x0, int y0, int x1, int y1,
            int threshold, int color, int count) {
    configured = 0;
    if (!arena_end || count < 0 || count > 256 || color < -1 || color > 0xffffff) return 0;
    box = (CoplandBox){x0, y0, x1, y1};
    background[0] = (color >> 16) & 255; background[1] = (color >> 8) & 255; background[2] = color & 255;
    if (!copland_prepare_image(input, source, image_width, image_height, 0, mode, &box,
                               threshold, color >= 0, background)) return -1;
    if (!start) start = box.x1 - box.x0 > box.y1 - box.y0 ? box.x1 - box.x0 : box.y1 - box.y0;
    if (!copland_timeline_init(&timeline, duration, fps, blank, hold, start,
                              (CoplandEasing)easing, keyframes, count)) return -2;
    copland_make_base(source, base, image_width, image_height, box, background);
    configured = 1;
    return timeline.total_frames;
}
unsigned render(unsigned index) {
    if (!configured || index >= (unsigned)timeline.total_frames) return 0;
    double size; int state = copland_frame_state(&timeline, (int)index, &size);
    const uint8_t *pixels = state == 0 ? base : source;
    if (state == 1) {
        if (!timeline.keyframe_count && size <= 16)
            copland_render_smooth_frame(source, base, frame, scratch, image_width, image_height, box, size);
        else copland_render_frame(source, base, frame, image_width, image_height, box, (int)lrint(size));
        pixels = frame;
    }
    copland_pack_rgba(pixels, output, image_width, image_height, background);
    return (unsigned)(uintptr_t)output;
}
int box_coordinate(int index) {
    if (index == 0) return box.x0; if (index == 1) return box.y0;
    if (index == 2) return box.x1; if (index == 3) return box.y1; return -1;
}
