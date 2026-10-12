#include "../../ports/pc/sh_tim.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

static void put16(uint8_t* ptr, uint16_t v)
{
    ptr[0] = (uint8_t)(v & 255u);
    ptr[1] = (uint8_t)(v >> 8u);
}

static void put32(uint8_t* ptr, uint32_t v)
{
    put16(ptr, (uint16_t)(v & 65535u));
    put16(ptr + 2, (uint16_t)(v >> 16u));
}

static void test_indexed(uint32_t bpp)
{
    uint8_t buf[600] = {0};
    const uint32_t entries = bpp == 4u ? 16u : 256u;
    const uint32_t clut_size = 12u + entries * 2u;
    const uint32_t image_start = 8u + clut_size;
    const uint32_t total = image_start + 14u;
    ShTimImage image = {0};

    put32(buf, 0x10u);
    put32(buf + 4u, (bpp == 4u ? 0u : 1u) | 8u);
    put32(buf + 8u, clut_size);
    put16(buf + 16u, (uint16_t)entries);
    put16(buf + 18u, 1u);
    put16(buf + 20u + 2u, 0x001Fu);
    put16(buf + 20u + 4u, 0x03E0u);
    put16(buf + 20u + 6u, 0x7C00u);
    put32(buf + image_start, 14u);
    put16(buf + image_start + 8u, 1u);
    put16(buf + image_start + 10u, 1u);
    buf[image_start + 12u] = bpp == 4u ? 0x21u : 2u;
    buf[image_start + 13u] = bpp == 4u ? 0x03u : 1u;

    assert(sh_tim_decode(buf, total, &image) == 0);
    assert(image.bits_per_pixel == bpp);
    assert(image.height == 1u);
    assert(image.width == (bpp == 4u ? 4u : 2u));
    if (bpp == 4u)
    {
        assert(image.pixels[0] == UINT32_C(0xFFFF0000));
        assert(image.pixels[1] == UINT32_C(0xFF00FF00));
        assert(image.pixels[2] == UINT32_C(0xFF0000FF));
        assert(image.pixels[3] == 0u);
    }
    else
    {
        assert(image.pixels[0] == UINT32_C(0xFF00FF00));
        assert(image.pixels[1] == UINT32_C(0xFFFF0000));
    }
    sh_tim_image_free(&image);
    assert(image.pixels == NULL);

    /* Malformed block boundaries must fail without allocation. */
    assert(sh_tim_decode(buf, (size_t)total - 1u, &image) != 0);
    assert(image.pixels == NULL);
    put16(buf + 16u, 2u);
    assert(sh_tim_decode(buf, total, &image) != 0);
    assert(image.pixels == NULL);
}

static void test_direct(void)
{
    uint8_t data[32] = {0};
    ShTimImage image = {0};
    put32(data, 0x10u);
    put32(data + 4u, 2u);
    put32(data + 8u, 16u);
    put16(data + 16u, 2u);
    put16(data + 18u, 1u);
    put16(data + 20u, 0x7FFFu);
    put16(data + 22u, 0x0000u);
    assert(sh_tim_decode(data, 24u, &image) == 0);
    assert(image.width == 2u && image.height == 1u);
    assert(image.pixels[0] == UINT32_C(0xFFFFFFFF));
    assert(image.pixels[1] == 0u);
    sh_tim_image_free(&image);

    memset(data, 0, sizeof(data));
    put32(data, 0x10u);
    put32(data + 4u, 3u);
    put32(data + 8u, 18u);
    put16(data + 16u, 3u);
    put16(data + 18u, 1u);
    data[20] = 255u;
    data[21] = 127u;
    data[22] = 0u;
    data[23] = 0u;
    data[24] = 128u;
    data[25] = 255u;
    assert(sh_tim_decode(data, 26u, &image) == 0);
    assert(image.bits_per_pixel == 24u);
    assert(image.width == 2u && image.height == 1u);
    assert(image.pixels[0] == UINT32_C(0xFFFF7F00));
    assert(image.pixels[1] == UINT32_C(0xFF0080FF));
    sh_tim_image_free(&image);

    data[0] = 0u;
    assert(sh_tim_decode(data, 26u, &image) != 0);
    assert(sh_tim_decode(NULL, 0u, &image) != 0);
    assert(sh_tim_decode(data, 26u, NULL) != 0);
}

int main(void)
{
    test_indexed(4u);
    test_indexed(8u);
    test_direct();
    return 0;
}
