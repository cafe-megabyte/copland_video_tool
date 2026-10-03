#include "image.h"

static int straight(int channel, int alpha, int premultiplied) {
    if (!alpha) return 0;
    if (!premultiplied) return channel;
    int result = (channel * 255 + alpha / 2) / alpha;
    return result > 255 ? 255 : result;
}

int copland_prepare_image(const uint8_t *rgba, uint8_t *rgb, int width, int height,
                         int premultiplied, int box_mode, CoplandBox *box,
                         int threshold, int explicit_background, uint8_t background[3]) {
    if (!rgba || !rgb || !box || !background || width <= 0 || height <= 0 ||
        threshold < 0 || threshold > 255 || box_mode < 0 || box_mode > 2 ||
        (size_t)width > (size_t)-1 / (size_t)height / 4) return 0;
    size_t count = (size_t)width * height;
    int has_alpha = 0, corner[3];
    for (size_t i = 0; i < count; ++i) if (rgba[4 * i + 3] < 255) has_alpha = 1;
    for (int c = 0; c < 3; ++c) {
        corner[c] = straight(rgba[c], rgba[3], premultiplied);
        if (!explicit_background) background[c] = has_alpha && !rgba[3] ? 255 : corner[c];
    }
    if (!box_mode) *box = (CoplandBox){0, 0, width, height};
    else if (box_mode == 1) {
        *box = (CoplandBox){width, height, 0, 0};
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            const uint8_t *p = rgba + ((size_t)y * width + x) * 4;
            int visible = p[3] > 0;
            if (!has_alpha) {
                int d[3];
                for (int c = 0; c < 3; ++c) { d[c] = (int)p[c] - corner[c]; if (d[c] < 0) d[c] = -d[c]; }
                visible = ((19595 * d[0] + 38470 * d[1] + 7471 * d[2] + 32768) >> 16) > threshold;
            }
            if (visible) {
                if (x < box->x0) box->x0 = x;
                if (y < box->y0) box->y0 = y;
                if (x + 1 > box->x1) box->x1 = x + 1;
                if (y + 1 > box->y1) box->y1 = y + 1;
            }
        }
    }
    if (box->x0 < 0 || box->y0 < 0 || box->x1 > width || box->y1 > height ||
        box->x0 >= box->x1 || box->y0 >= box->y1) return 0;
    for (size_t i = 0; i < count; ++i) for (int c = 0; c < 3; ++c) {
        int alpha = rgba[4 * i + 3];
        int foreground = premultiplied ? rgba[4 * i + c] : (rgba[4 * i + c] * alpha + 127) / 255;
        int mixed = foreground + (background[c] * (255 - alpha) + 127) / 255;
        rgb[3 * i + c] = (uint8_t)(mixed > 255 ? 255 : mixed);
    }
    return 1;
}

static void pack(const uint8_t *rgb, uint8_t *rgba, int width, int height,
                 size_t row_bytes, int bgra, const uint8_t background[3]) {
    int ew = width + (width & 1), eh = height + (height & 1);
    for (int y = 0; y < eh; ++y) for (int x = 0; x < ew; ++x) {
        const uint8_t *p = x < width && y < height ? rgb + ((size_t)y * width + x) * 3 : background;
        size_t offset = (size_t)y * row_bytes + x * 4;
        rgba[offset] = p[bgra ? 2 : 0];
        rgba[offset + 1] = p[1];
        rgba[offset + 2] = p[bgra ? 0 : 2];
        rgba[offset + 3] = 255;
    }
}

void copland_pack_rgba(const uint8_t *rgb, uint8_t *rgba, int width, int height,
                       const uint8_t background[3]) {
    pack(rgb, rgba, width, height, (size_t)(width + (width & 1)) * 4, 0, background);
}
void copland_pack_bgra(const uint8_t *rgb, uint8_t *bgra, int width, int height,
                       size_t row_bytes, const uint8_t background[3]) {
    pack(rgb, bgra, width, height, row_bytes, 1, background);
}
