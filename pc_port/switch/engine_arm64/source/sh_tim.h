#ifndef SH_PC_TIM_H
#define SH_PC_TIM_H

#include <stddef.h>
#include <stdint.h>

/* Real PS1 TIM decoder, not a PS1 GPU emulation. Pixel order is 0xAARRGGBB.
 * On 16-bit TIM images, bit 15 (STP) is not emulated; transparent black
 * is represented by alpha 0 only for palette/texel value zero. */
typedef struct ShTimImage
{
    uint32_t width;
    uint32_t height;
    uint32_t bits_per_pixel;
    uint32_t* pixels;
} ShTimImage;

/* Returns zero on success; leaves out reset on all errors. */
int sh_tim_decode(const uint8_t* data, size_t len, ShTimImage* out);
int sh_tim_load_file(const char* filename, ShTimImage* out);
void sh_tim_image_free(ShTimImage* image);
int sh_tim_write_ppm(const char* filename, const ShTimImage* image);

#endif
