#include "silent_hill/sh_rng.h"

#include <assert.h>
#include <stdint.h>

static void test_reference_sequence_from_zero(void)
{
    static const uint32_t expected[] = {
        UINT32_C(0x3C6EF35F),
        UINT32_C(0x47502932),
        UINT32_C(0xD1CCF6E9),
        UINT32_C(0xAAF95334),
        UINT32_C(0x6252E503)
    };

    ShRng rng;
    size_t idx;

    sh_rng_init(&rng, 0u);

    for (idx = 0u; idx < (sizeof(expected) / sizeof(expected[0])); idx++)
    {
        assert(sh_rng_next_u32(&rng) == expected[idx]);
    }

    assert(sh_rng_get_seed(&rng) == expected[4]);
}

static void test_reference_sequence_from_known_seed(void)
{
    static const uint32_t expected[] = {
        UINT32_C(0x75432777),
        UINT32_C(0xCD305E6A),
        UINT32_C(0x25DBFAC1),
        UINT32_C(0x4B5C952C),
        UINT32_C(0x84DE0E9B)
    };

    ShRng rng;
    size_t idx;

    sh_rng_init(&rng, UINT32_C(0x12345678));

    for (idx = 0u; idx < (sizeof(expected) / sizeof(expected[0])); idx++)
    {
        assert(sh_rng_next_u32(&rng) == expected[idx]);
    }
}

static void test_original_width_helpers(void)
{
    ShRng rng;

    sh_rng_init(&rng, 0u);
    assert(sh_rng_next_u15(&rng) == UINT16_C(7735));

    sh_rng_init(&rng, 0u);
    assert(sh_rng_next_u12(&rng) == UINT16_C(966));
}

static void test_null_safety(void)
{
    sh_rng_init(NULL, 1u);
    sh_rng_set_seed(NULL, 2u);

    assert(sh_rng_get_seed(NULL) == 0u);
    assert(sh_rng_next_u32(NULL) == 0u);
    assert(sh_rng_next_u15(NULL) == 0u);
    assert(sh_rng_next_u12(NULL) == 0u);
}

int main(void)
{
    test_reference_sequence_from_zero();
    test_reference_sequence_from_known_seed();
    test_original_width_helpers();
    test_null_safety();

    return 0;
}
