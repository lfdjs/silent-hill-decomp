#include "sh_tim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SH_TIM_MAX_PIXELS (UINT32_C(4096) * UINT32_C(4096))
#define SH_TIM_MAX_FILE_BYTES (UINT32_C(64) * UINT32_C(1024) * UINT32_C(1024))

static uint16_t le16(const uint8_t* p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8u));
}

static uint32_t le32(const uint8_t* p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8u) |
        ((uint32_t)p[2] << 16u) | ((uint32_t)p[3] << 24u);
}

static uint32_t rgb555(uint16_t value)
{
    uint32_t r = (uint32_t)(value & UINT16_C(31));
    uint32_t g = (uint32_t)((value >> 5u) & UINT16_C(31));
    uint32_t b = (uint32_t)((value >> 10u) & UINT16_C(31));
    uint32_t a = value == 0u ? 0u : 255u;

    r = (r << 3u) | (r >> 2u);
    g = (g << 3u) | (g >> 2u);
    b = (b << 3u) | (b >> 2u);
    return (a << 24u) | (r << 16u) | (g << 8u) | b;
}

void sh_tim_image_free(ShTimImage* image)
{
    if (image != NULL)
    {
        free(image->pixels);
        memset(image, 0, sizeof(*image));
    }
}

/* TIM header (magic, mode), optional CLUT block and image block.
 * Every block length includes its own 12-byte header. */
int sh_tim_decode(const uint8_t* data, size_t len, ShTimImage* out)
{
    uint32_t mode;
    uint32_t bpp;
    uint32_t clut_entries = 0u;
    uint32_t row_bytes;
    uint32_t width;
    uint32_t height;
    uint32_t words;
    uint32_t block_bytes;
    const uint8_t* clut = NULL;
    const uint8_t* pixels;
    ShTimImage image = {0};
    size_t off = 8u;
    uint32_t x;
    uint32_t y;

    if (data == NULL || out == NULL || len < 20u)
    {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    if (le32(data) != UINT32_C(0x10))
    {
        return -1;
    }
    mode = le32(data + 4u);
    if ((mode & ~UINT32_C(0x0F)) != 0u || (mode & 7u) > 3u)
    {
        return -1;
    }
    bpp = (mode & 7u) == 0u ? 4u :
          (mode & 7u) == 1u ? 8u :
          (mode & 7u) == 2u ? 16u : 24u;

    if ((mode & 8u) != 0u)
    {
        if (len - off < 12u)
        {
            return -1;
        }
        block_bytes = le32(data + off);
        if (block_bytes < 12u || (size_t)block_bytes > len - off)
        {
            return -1;
        }
        /* X/Y are VRAM placement hints; palette row zero is selected. */
        if ((size_t)le16(data + off + 8u) *
            (size_t)le16(data + off + 10u) * 2u !=
            (size_t)block_bytes - 12u)
        {
            return -1;
        }
        clut_entries = (uint32_t)le16(data + off + 8u);
        if ((bpp == 4u && clut_entries < 16u) ||
            (bpp == 8u && clut_entries < 256u))
        {
            return -1;
        }
        clut = data + off + 12u;
        off += (size_t)block_bytes;
    }
    else if (bpp == 4u || bpp == 8u)
    {
        return -1;
    }

    if (len - off < 12u)
    {
        return -1;
    }
    block_bytes = le32(data + off);
    words = (uint32_t)le16(data + off + 8u);
    height = (uint32_t)le16(data + off + 10u);
    row_bytes = words * 2u;
    if (block_bytes < 12u || (size_t)block_bytes > len - off ||
        row_bytes == 0u || height == 0u ||
        (size_t)row_bytes * (size_t)height !=
        (size_t)block_bytes - 12u)
    {
        return -1;
    }
    pixels = data + off + 12u;
    if (bpp == 24u)
    {
        if ((row_bytes % 3u) != 0u)
        {
            return -1;
        }
        width = row_bytes / 3u;
    }
    else
    {
        width = (row_bytes * 8u) / bpp;
    }
    if (width == 0u || (uint64_t)width * height > SH_TIM_MAX_PIXELS)
    {
        return -1;
    }
    image.pixels = (uint32_t*)calloc(
        (size_t)width * (size_t)height, sizeof(uint32_t));
    if (image.pixels == NULL)
    {
        return -1;
    }
    image.width = width;
    image.height = height;
    image.bits_per_pixel = bpp;

    for (y = 0u; y < height; y++)
    {
        const uint8_t* row = pixels + (size_t)y * row_bytes;
        for (x = 0u; x < width; x++)
        {
            uint32_t color;
            if (bpp == 4u)
            {
                uint32_t index = ((x & 1u) != 0u) ?
                    ((uint32_t)row[x / 2u] >> 4u) :
                    ((uint32_t)row[x / 2u] & 15u);
                color = rgb555(le16(clut + index * 2u));
            }
            else if (bpp == 8u)
            {
                uint32_t index = row[x];
                if (index >= clut_entries)
                {
                    sh_tim_image_free(&image);
                    return -1;
                }
                color = rgb555(le16(clut + index * 2u));
            }
            else if (bpp == 16u)
            {
                color = rgb555(le16(row + x * 2u));
            }
            else
            {
                size_t pos = (size_t)x * 3u;
                color = UINT32_C(0xFF000000) |
                    ((uint32_t)row[pos] << 16u) |
                    ((uint32_t)row[pos + 1u] << 8u) |
                    (uint32_t)row[pos + 2u];
            }
            image.pixels[(size_t)y * width + x] = color;
        }
    }
    *out = image;
    return 0;
}

int sh_tim_load_file(const char* filename, ShTimImage* out)
{
    FILE* file;
    long length;
    size_t bytes;
    uint8_t* data;
    int rc;

    if (filename == NULL || out == NULL)
    {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    file = fopen(filename, "rb");
    if (file == NULL)
    {
        return -1;
    }
    if (fseek(file, 0, SEEK_END) != 0 ||
        (length = ftell(file)) < 20L ||
        (uint64_t)length > SH_TIM_MAX_FILE_BYTES ||
        fseek(file, 0, SEEK_SET) != 0)
    {
        fclose(file);
        return -1;
    }
    bytes = (size_t)length;
    data = (uint8_t*)malloc(bytes);
    if (data == NULL)
    {
        fclose(file);
        return -1;
    }
    if (fread(data, 1u, bytes, file) != bytes)
    {
        free(data);
        fclose(file);
        return -1;
    }
    fclose(file);
    rc = sh_tim_decode(data, bytes, out);
    free(data);
    return rc;
}

int sh_tim_write_ppm(const char* filename, const ShTimImage* image)
{
    FILE* file;
    uint64_t i;
    uint64_t count;
    if (filename == NULL || image == NULL || image->pixels == NULL ||
        image->width == 0u || image->height == 0u)
    {
        return -1;
    }
    file = fopen(filename, "wb");
    if (file == NULL)
    {
        return -1;
    }
    if (fprintf(file, "P6\n%u %u\n255\n",
                image->width, image->height) < 0)
    {
        fclose(file);
        return -1;
    }
    count = (uint64_t)image->width * image->height;
    for (i = 0u; i < count; i++)
    {
        uint32_t px = image->pixels[i];
        uint8_t rgb[3] = {
            (uint8_t)((px >> 16u) & 255u),
            (uint8_t)((px >> 8u) & 255u),
            (uint8_t)(px & 255u)
        };
        if (fwrite(rgb, 1u, sizeof(rgb), file) != sizeof(rgb))
        {
            fclose(file);
            return -1;
        }
    }
    return fclose(file) == 0 ? 0 : -1;
}
