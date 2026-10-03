#ifndef COPLAND_IMAGE_H
#define COPLAND_IMAGE_H
#include "reveal.h"
#include <stddef.h>
/* Input may be straight or premultiplied RGBA. Output is opaque packed RGB. */
int copland_prepare_image(const uint8_t *rgba, uint8_t *rgb, int width, int height,
                         int premultiplied, int box_mode, CoplandBox *box,
                         int threshold, int explicit_background, uint8_t background[3]);
void copland_pack_rgba(const uint8_t *rgb, uint8_t *rgba, int width, int height,
                       const uint8_t background[3]);
void copland_pack_bgra(const uint8_t *rgb, uint8_t *bgra, int width, int height,
                       size_t row_bytes, const uint8_t background[3]);
#endif
