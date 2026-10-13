#ifndef SOUND_START_FIXTURE_H
#define SOUND_START_FIXTURE_H
#include <stdint.h>
#include <string.h>
#define SOUND_START_SIDE 128
#define SOUND_START_KINDS 7
/* Sparse transparent centres reproduce Tigger's invisible coarse grids without
   depending on a private Desktop file. Black RGB also works premultiplied. */
static void sound_start_fixture(uint8_t *rgba, int kind) {
    memset(rgba, 0, SOUND_START_SIDE * SOUND_START_SIDE * 4);
    if (kind == 1) {
        for (int y = 0; y < SOUND_START_SIDE; ++y)
            for (int x = 0; x < SOUND_START_SIDE; ++x) {
                uint8_t *p = rgba + (y * SOUND_START_SIDE + x) * 4;
                p[0] = x; p[1] = y; p[2] = 200; p[3] = 255;
            }
    } else if (kind == 0) {
        rgba[(63 * SOUND_START_SIDE + 63) * 4 + 3] = 1;
        rgba[(119 * SOUND_START_SIDE + 55) * 4 + 3] = 24;
    } else if (kind == 2 || kind == 5) {
        rgba[(63 * SOUND_START_SIDE + 63) * 4 + 3] = kind == 2 ? 7 : 8;
    } else if (kind == 4) {
        rgba[(2 * SOUND_START_SIDE + 2) * 4 + 3] = 255;
    } else if (kind == 6) {
        rgba[(127 * SOUND_START_SIDE + 127) * 4 + 3] = 255;
    }
}
#endif
