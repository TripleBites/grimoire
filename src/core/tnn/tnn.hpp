#pragma once

namespace tnn
{
    struct Layer {             // one allocation per array
    uint32_t in, out, words; // words = (in + 63) / 64
    uint64_t *mask;          // 1 = weight is nonzero
    uint64_t *sign;          // 1 = negative; must be 0 where mask is 0
    int16_t  *lo, *hi;       // per-neuron thresholds
    float    *mom;           // Top momentum, training only
    };
}