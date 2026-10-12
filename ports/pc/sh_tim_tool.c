#include "sh_tim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv)
{
    ShTimImage image = {0};
    int rc;
    if (!((argc == 3 && strcmp(argv[1], "--info") == 0) ||
          (argc == 4 && strcmp(argv[1], "--ppm") == 0)))
    {
        fprintf(stderr, "usage: %s --info file.TIM | --ppm file.TIM out.ppm\n", argv[0]);
        return EXIT_FAILURE;
    }
    if (sh_tim_load_file(argv[2], &image) != 0)
    {
        fprintf(stderr, "TIM invalid or unreadable: %s\n", argv[2]);
        return EXIT_FAILURE;
    }
    printf("TIM loaded: %ux%u %u-bpp\n",
        image.width, image.height, image.bits_per_pixel);
    rc = 0;
    if (argc == 4)
    {
        rc = sh_tim_write_ppm(argv[3], &image);
        if (rc == 0)
        {
            printf("PPM exported: %s\n", argv[3]);
        }
    }
    sh_tim_image_free(&image);
    return rc == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
